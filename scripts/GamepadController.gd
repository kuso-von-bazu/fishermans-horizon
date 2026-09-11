extends Node
## #293: UIのフォーカス移動と航海中の照準。ポーズ中もメニューを操作する。
const Controls := preload("res://scripts/ControlInput.gd")
const CONFIRM_BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
var world: Node2D
var aim_offset := Vector2(0, -240)
var _menu: Node
var _mode := false
var _direction := Vector2.ZERO
var _repeat := 0.0
var _triggers: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	process_physics_priority = -100
	Controls.install()
	Controls.reset_held()
	_mode = GameState.pad_mode
	Input.joy_connection_changed.connect(_connection_changed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Controls.focused = false
		Controls.reset_held()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Controls.focused = true

func _connection_changed(_device: int, connected: bool) -> void:
	Controls.reset_held()
	if GameState.pad_mode and not connected:
		GameState.notice.emit("パッドの接続が切れました。設定でキーボード・マウスに戻せます。")

func menu_root() -> Node:
	if not is_instance_valid(world):
		return null
	if world._food_dialog_open and is_instance_valid(world._food_dialog):
		return world._food_dialog
	var root: Control
	if world.phase == "title" or (is_instance_valid(world.title) and world.title.visible):
		root = world.title._root
		if is_instance_valid(world.title._confirm) and world.title._confirm.visible:
			root = world.title._confirm
	elif world.phase == "dock":
		root = world.port_ui._root
		if is_instance_valid(world.port_ui._img_popup):
			return world.port_ui._img_popup
	elif is_instance_valid(world.hud):
		root = world.hud._ui_root
	if root == null:
		return null
	var overlay := root.get_node_or_null("SharedOverlay")
	if overlay != null:
		return overlay
	return root if world.phase != "sea" else null

func _sync_context() -> void:
	var next := menu_root()
	if next != _menu or _mode != GameState.pad_mode:
		_menu = next
		_mode = GameState.pad_mode
		Controls.reset_held()
		_direction = Vector2.ZERO
		_repeat = 0.25
	Controls.refresh(GameState.pad_mode and _menu == null and world.phase == "sea"
		and not get_tree().paused and not GameState.docking_locked)

func _physics_process(_delta: float) -> void:
	_sync_context()
	if not Controls.sea_enabled or not Controls.focused:
		return
	for slot in 4:
		if Controls.just_pressed("formation_%d" % (slot + 1)):
			world._set_formation_slot(slot)
	if Controls.just_pressed("lock_next"):
		world._cycle_lock(1)
	if Controls.just_pressed("lock_previous"):
		world._cycle_lock(-1)
	if Controls.just_pressed("skill"):
		world._use_skill()
	if Controls.just_pressed("lock_nearest"):
		var best: Node2D
		var distance := INF
		for enemy in world._lockable_enemies():
			var d: float = enemy.global_position.distance_squared_to(aim_position())
			if d < distance:
				distance = d
				best = enemy
		world._set_lock(best)

func aim_position() -> Vector2:
	return world.player.global_position + aim_offset

func _process(delta: float) -> void:
	_sync_context()
	# 照準描画は既存のLosOverlay2Dを使い、射線が塞がると赤くなる表示も保つ。
	if Controls.sea_enabled and Controls.focused:
		var stick := Vector2(Controls.strength("aim_right") - Controls.strength("aim_left"),
			Controls.strength("aim_down") - Controls.strength("aim_up"))
		if stick.length() > 0.0:
			aim_offset = (aim_offset + stick.limit_length(1.0) * 600.0 * delta).limit_length(900.0)
		var canvas := world.get_viewport().get_canvas_transform()
		var screen := canvas * aim_position()
		var viewport_size := get_viewport().get_visible_rect().size
		screen = screen.clamp(Vector2(24, 24), viewport_size - Vector2(24, 24))
		aim_offset = canvas.affine_inverse() * screen - world.player.global_position
	if not GameState.pad_mode or _menu == null or not Controls.focused:
		return
	_ensure_focus()
	# 長文の早見表や一覧は右スティックでもスクロールできる。
	var scroll_axis := Input.get_action_strength("pad_aim_down") - Input.get_action_strength("pad_aim_up")
	if absf(scroll_axis) > 0.1:
		var scrolls := _menu.find_children("*", "ScrollContainer", true, false)
		for scroll in scrolls:
			if scroll.is_visible_in_tree():
				scroll.scroll_vertical += int(scroll_axis * 650.0 * delta)
				break
	var dir := Vector2(
		Input.get_action_strength("pad_turn_right") - Input.get_action_strength("pad_turn_left")
		+ Input.get_action_strength("pad_formation_2") - Input.get_action_strength("pad_formation_4"),
		Input.get_action_strength("pad_throttle_down") - Input.get_action_strength("pad_throttle_up")
		+ Input.get_action_strength("pad_formation_3") - Input.get_action_strength("pad_formation_1"))
	if dir.length() < 0.45:
		_direction = Vector2.ZERO
		_repeat = 0.0
		return
	dir = Vector2(signf(dir.x), 0) if absf(dir.x) > absf(dir.y) else Vector2(0, signf(dir.y))
	_repeat -= delta
	if dir != _direction or _repeat <= 0.0:
		_move_focus(dir)
		_repeat = 0.32 if dir != _direction else 0.12
		_direction = dir

func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	# 標準ui_accept等の暗黙の割当が、背景や新しい画面を再度決定しないよう消費する。
	get_viewport().set_input_as_handled()
	_sync_context()
	var confirm := false
	if event is InputEventJoypadButton:
		confirm = event.pressed and event.button_index in CONFIRM_BUTTONS
	elif event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		var key := "%d:%d" % [event.device, event.axis]
		var down: bool = event.axis_value > 0.5
		confirm = down and not bool(_triggers.get(key, false))
		_triggers[key] = down
	if GameState.pad_mode and Controls.focused and _menu != null and confirm:
		_activate_focus()

func _collect(node: Node, result: Array[Control]) -> void:
	if node.is_queued_for_deletion():
		return
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is CanvasLayer and not node.visible:
		return
	if (node is BaseButton and not node.disabled) or node is Slider:
		var c := node as Control
		c.focus_mode = Control.FOCUS_ALL
		if not c.has_meta("pad_focus"):
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = Color(1.0, 0.88, 0.2)
			style.set_border_width_all(3)
			c.add_theme_stylebox_override("focus", style)
			c.set_meta("pad_focus", true)
		result.append(c)
	for child in node.get_children():
		_collect(child, result)

func _candidates() -> Array[Control]:
	var result: Array[Control] = []
	if is_instance_valid(_menu):
		_collect(_menu, result)
	return result

func _ensure_focus() -> Control:
	var candidates := _candidates()
	var current := get_viewport().gui_get_focus_owner()
	if not candidates.has(current):
		if candidates.is_empty():
			return null
		current = candidates[0]
		_focus(current)
	return current

func _focus(control: Control) -> void:
	control.grab_focus()
	var ancestor := control.get_parent()
	while ancestor != null and ancestor != _menu:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()

func _move_focus(dir: Vector2) -> void:
	var current := _ensure_focus()
	if current == null:
		return
	if current is Slider and dir.x != 0:
		current.value += dir.x * 0.05
		return
	var origin := current.get_global_rect().get_center()
	var best: Control
	var score := INF
	for candidate in _candidates():
		if candidate == current:
			continue
		var diff := candidate.get_global_rect().get_center() - origin
		var forward := diff.dot(dir)
		if forward <= 1.0:
			continue
		var side := absf(diff.cross(dir))
		var value := forward + side * 3.0
		if value < score:
			score = value
			best = candidate
	if best != null:
		_focus(best)

func _activate_focus() -> void:
	if is_instance_valid(world.port_ui._img_popup) and _menu == world.port_ui._img_popup:
		world.port_ui._close_image_popup.call_deferred()
		return
	var current := _ensure_focus()
	if current is BaseButton:
		# 決定は押した瞬間に一度だけ。接続されたハンドラは次フレームへ送る。
		# ハンドラがUIを再構築しても、入力処理中のノードを解放しない。
		_activate_button.call_deferred(current)

func _activate_button(button: BaseButton) -> void:
	if not is_instance_valid(button) or not _candidates().has(button):
		return
	if button.toggle_mode:
		button.button_pressed = not button.button_pressed
	button.pressed.emit()
	_sync_context()
