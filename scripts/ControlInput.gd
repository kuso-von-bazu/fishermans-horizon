extends RefCounted
## #293: キーボードとパッドを同じゲーム操作へ接続する。
## pad_* はUI決定と共有しない。画面切替時は一度離すまで持ち越さない。

const BUTTONS := {
	"interact": JOY_BUTTON_X, "fast_return": JOY_BUTTON_Y,
	"lock_next": JOY_BUTTON_A, "lock_previous": JOY_BUTTON_B,
	"formation_1": JOY_BUTTON_DPAD_UP, "formation_2": JOY_BUTTON_DPAD_RIGHT,
	"formation_3": JOY_BUTTON_DPAD_DOWN, "formation_4": JOY_BUTTON_DPAD_LEFT,
	"skill": JOY_BUTTON_LEFT_SHOULDER, "lock_nearest": JOY_BUTTON_RIGHT_SHOULDER,
}
const AXES := {
	"throttle_up": [JOY_AXIS_LEFT_Y, -1.0], "throttle_down": [JOY_AXIS_LEFT_Y, 1.0],
	"turn_left": [JOY_AXIS_LEFT_X, -1.0], "turn_right": [JOY_AXIS_LEFT_X, 1.0],
	"aim_left": [JOY_AXIS_RIGHT_X, -1.0], "aim_right": [JOY_AXIS_RIGHT_X, 1.0],
	"aim_up": [JOY_AXIS_RIGHT_Y, -1.0], "aim_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"fire_primary": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "fire_torpedo": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}
static var sea_enabled := false
static var blocked: Dictionary = {}
static var focused := true

static func install() -> void:
	for action in BUTTONS:
		var name := "pad_" + str(action)
		if InputMap.has_action(name):
			continue
		InputMap.add_action(name, 0.25)
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = BUTTONS[action]
		InputMap.action_add_event(name, event)
	for action in AXES:
		var name := "pad_" + str(action)
		if InputMap.has_action(name):
			continue
		InputMap.add_action(name, 0.25)
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = AXES[action][0]
		event.axis_value = AXES[action][1]
		InputMap.action_add_event(name, event)

static func reset_held() -> void:
	for action in BUTTONS.keys() + AXES.keys():
		blocked[action] = true

static func refresh(enabled: bool) -> void:
	if enabled != sea_enabled:
		reset_held()
	sea_enabled = enabled
	for action in blocked.keys():
		if not Input.is_action_pressed("pad_" + str(action)):
			blocked.erase(action)

static func _available(action: String) -> bool:
	return focused and sea_enabled and not blocked.has(action)

static func strength(action: String) -> float:
	if not GameState.pad_mode:
		return Input.get_action_strength(action) if focused else 0.0
	return Input.get_action_strength("pad_" + action) if _available(action) else 0.0

static func pressed(action: String) -> bool:
	return strength(action) > 0.0

static func just_pressed(action: String) -> bool:
	if not GameState.pad_mode:
		return focused and Input.is_action_just_pressed(action)
	return _available(action) and Input.is_action_just_pressed("pad_" + action)

static func just_released(action: String) -> bool:
	if not GameState.pad_mode:
		return focused and Input.is_action_just_released(action)
	return _available(action) and Input.is_action_just_released("pad_" + action)
