extends Node
## 実入力イベントをゲームへ送り、UI決定・操船・戦闘・画面境界を検証する。
const World := preload("res://scripts2d/World2D.gd")
const Controls := preload("res://scripts/ControlInput.gd")
const Menus := preload("res://scripts/OverlayMenus.gd")
var failures: Array[String] = []
var world: Node2D

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 3) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func button(index: int, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func axis(index: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = index
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(index: int) -> void:
	button(index, true)
	await frames()
	button(index, false)
	await frames()

func find_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null

func capture(label: String) -> void:
	if not "--visual" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var path := "user://issue293-%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT_SAVED:", ProjectSettings.globalize_path(path))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await frames()
	GameState.reset_all()
	world = World.new()
	add_child(world)
	await frames()
	# 新旧の設定保存が互いを消さず、ロード後にも操作方式が残る。
	GameState.set_pad_mode(true)
	GameState.set_screen_shake(false)
	GameState.pad_mode = false
	GameState.screen_shake = true
	GameState.load_display_settings()
	check(GameState.pad_mode and not GameState.screen_shake, "操作方式と画面シェイクの保存が共存しない")
	await frames()
	Menus.show_settings(world.title._root)
	await frames()
	var overlay: Control = world.title._root.get_node("SharedOverlay")
	var mode: Button = overlay.find_child("InputMode", true, false)
	check(mode != null and mode.text.contains("パッド"), "歯車の設定にパッド切替が無い")
	world.gamepad._focus(mode)
	await capture("settings")
	await tap(JOY_BUTTON_A)
	check(not GameState.pad_mode, "設定ボタンをパッドで決定しても操作方式が切り替わらない")
	# マウスと同じpressed経路でパッドへ戻す。
	mode.pressed.emit()
	await frames()
	check(GameState.pad_mode, "キーボード・マウスからパッドへ切り替わらない")
	world.gamepad._focus(mode)
	axis(JOY_AXIS_LEFT_Y, 1.0)
	await frames()
	check(get_viewport().gui_get_focus_owner() != mode, "左スティックでUI選択が動かない")
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames()
	var first := get_viewport().gui_get_focus_owner()
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() != first, "十字キーでUI選択が動かない")
	# 全8種類の決定で実際に「閉じる」を押す。トリガーは保持しても一度だけ。
	for index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, 100, 101]:
		if world.title._root.get_node_or_null("SharedOverlay") == null:
			Menus.show_settings(world.title._root)
		await frames()
		overlay = world.title._root.get_node("SharedOverlay")
		world.gamepad._focus(find_button(overlay, "閉じる"))
		if index < 100:
			await tap(index)
		else:
			var trigger := JOY_AXIS_TRIGGER_LEFT if index == 100 else JOY_AXIS_TRIGGER_RIGHT
			axis(trigger, 1.0)
			await frames()
			axis(trigger, 0.8)
			await frames()
			axis(trigger, 0.0)
			await frames()
		check(world.title._root.get_node_or_null("SharedOverlay") == null, "決定ボタン%dで閉じられない" % index)
		check(world.phase == "title", "閉じる入力が背後のゲーム開始にも伝わった")

	world.title.visible = false
	world._enter_dock(0, false)
	await frames()
	# 港の実ボタンでタブを開き、スクロール内のボタンにもフォーカスできる。
	world.gamepad._focus(find_button(world.port_ui._root, "造船所"))
	await tap(JOY_BUTTON_X)
	check(world.port_ui.content.get_child_count() > 0, "港のタブを決定できない")
	await capture("port")
	world.port_ui._show_image_popup("res://assets/images/ui_defeated_stamp.png")
	await frames()
	check(world.gamepad.menu_root() == world.port_ui._img_popup, "画像拡大中に背景の港ボタンが操作対象になる")
	await tap(JOY_BUTTON_B)
	check(world.port_ui._img_popup == null, "パッドで画像拡大を閉じられない")
	var sail := find_button(world.port_ui._root, "出港する")
	world.gamepad._focus(sail)
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames()
	check(world.phase == "sea", "R2決定で出港できない")
	check(not Controls.pressed("fire_primary"), "出港決定のR2が射撃へ持ち越された")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames()
	world._clear_sea_actors()
	world.spawn_timer = 1000
	world.player.global_position = Vector2(1200, 1800)
	world.player.rotation = 0.0
	world.player.velocity = Vector2.ZERO
	world.camera.global_position = world.player.global_position
	world._dock_target = -1
	await frames()

	# 左スティックのデッドゾーン、前進、後退、左右旋回。
	axis(JOY_AXIS_LEFT_Y, -0.1)
	await frames()
	check(world.player.velocity.length() < 0.01, "スティック微小入力で船が動く")
	axis(JOY_AXIS_LEFT_Y, -1.0)
	await frames(8)
	check(world.player.velocity.y < 0, "左スティック上で前進しない")
	axis(JOY_AXIS_LEFT_Y, 1.0)
	await frames(30)
	check(world.player.velocity.y > 0, "左スティック下で後退しない")
	axis(JOY_AXIS_LEFT_Y, 0.0)
	axis(JOY_AXIS_LEFT_X, 1.0)
	var rotation_before: float = world.player.rotation
	await frames(5)
	check(world.player.rotation > rotation_before, "左スティック右で右旋回しない")
	rotation_before = world.player.rotation
	axis(JOY_AXIS_LEFT_X, -1.0)
	await frames(5)
	check(world.player.rotation < rotation_before, "左スティック左で左旋回しない")
	axis(JOY_AXIS_LEFT_X, 0.0)
	world.player.velocity = Vector2.ZERO
	var aim_before: Vector2 = world.gamepad.aim_offset
	axis(JOY_AXIS_RIGHT_X, 1.0)
	await frames(6)
	check(world.gamepad.aim_offset.x > aim_before.x, "右スティックで照準が動かない")
	axis(JOY_AXIS_RIGHT_X, 0.0)
	await frames()
	check(world.aim_position().is_equal_approx(world.gamepad.aim_position()), "射撃の照準がパッドカーソルを使っていない")
	await capture("sea")

	# 実在の敵を2体置いてR1と×○を確認。
	for offset in [Vector2(140, -60), Vector2(-180, -60)]:
		var enemy = world.EnemyScript.new()
		enemy.setup("mob", "narwhal")
		world.add_child(enemy)
		enemy.global_position = world.player.global_position + offset
		enemy.set_physics_process(false)
		world.enemies.append(enemy)
	world.gamepad.aim_offset = Vector2(140, -60)
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(world.lock_target == world.enemies[0], "R1で照準に最も近い敵を選べない")
	await tap(JOY_BUTTON_A)
	check(world.lock_target == world.enemies[1], "×がホイール下と同じ順に切り替わらない")
	await tap(JOY_BUTTON_B)
	check(world.lock_target == world.enemies[0], "○がホイール上と同じ順に切り替わらない")

	# 入力が実際の発射処理に届き、弾数が減る。
	GameState.ship_id = "hunter_h"
	GameState.weapons = ["cannon", "torpedo", "", ""]
	world._reset_ammo()
	world.slot_cooldowns = [0.0, 0.0, 0.0, 0.0]
	# --negative: R2割当を取り除くと実射撃の検査が落ちることを確認する。
	if "--negative" in OS.get_cmdline_user_args():
		InputMap.action_erase_events("pad_fire_primary")
	var ammo: int = world.slot_ammo[0]
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames()
	check(world.slot_ammo[0] != ammo or world.slot_cooldowns[0] > 0.0, "R2で射撃処理が走らない")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	ammo = world.slot_ammo[1]
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await frames()
	check(world.slot_ammo[1] != ammo or world.slot_cooldowns[1] > 0.0, "L2で魚雷が発射されない")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await frames()

	GameState.visited_islands = [0, 1]
	GameState.fleet.append(GameState.fleet[0].duplicate(true))
	var dpad := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]
	for slot in 4:
		await tap(dpad[slot])
		check(GameState.formation_slot == slot, "十字キーの陣形%dが選べない" % (slot + 1))
	world._skill_cd = 0.0
	GameState.formations[3] = "ring"   # 防御スキルで入力経路を検証。敵を消す後続テストと斉射タイマーを干渉させない。
	await tap(JOY_BUTTON_LEFT_SHOULDER)
	check(world._skill_cd > 0.0, "L1でスキルが発動しない")
	button(JOY_BUTTON_Y, true)
	await frames(5)
	check(world._return_hold > 0.0, "△長押しで帰還が進まない")
	button(JOY_BUTTON_Y, false)
	await frames()
	check(world._return_hold == 0.0, "△を離しても帰還ゲージが残る")

	# □の長押し・解放を既存の漁処理に通す。
	world._clear_sea_actors()
	await frames()
	var fish = world.FishSchoolScript.new()
	fish.setup("bonito", 5)
	world.add_child(fish)
	fish.global_position = world.player.global_position
	world.fish_schools.append(fish)
	var cargo_before: int = GameState.used_hold()
	button(JOY_BUTTON_X, true)
	await frames(5)
	check(world._fishing_target == fish, "□で漁を開始できない")
	button(JOY_BUTTON_X, false)
	await frames()
	check(GameState.used_hold() > cargo_before, "□を離しても魚を獲得できない")

	# 燃料確認はポーズ中にも操作でき、背景の攻撃へ入力を渡さない。
	world._show_food_choice()
	await frames()
	check(get_tree().paused and world.gamepad.menu_root() == world._food_dialog, "燃料確認に操作対象が切り替わらない")
	var choices: Array = world._food_dialog.find_children("*", "Button", true, false)
	world.gamepad._focus(choices[1])
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames()
	check(not get_tree().paused and not world._food_dialog_open, "ポーズ中の確認をパッドで決定できない")
	check(not Controls.pressed("fire_primary"), "確認のR2が射撃に持ち越された")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames()
	world.gamepad._connection_changed(0, false)
	check(not Controls.pressed("fire_primary"), "切断時に射撃が解除されない")

	# キーボードへ戻すとパッドは無効、既存Wキー経路は有効。
	GameState.set_pad_mode(false)
	axis(JOY_AXIS_LEFT_Y, -1.0)
	await frames()
	check(Controls.strength("throttle_up") == 0.0, "キーボードモードでもパッドで操船できてしまう")
	Input.action_press("throttle_up")
	check(Controls.strength("throttle_up") == 1.0, "キーボード入力の互換性が失われた")
	Input.action_release("throttle_up")
	axis(JOY_AXIS_LEFT_Y, 0.0)
	world.queue_free()
	await frames()
	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue293: settings, navigation, all pad controls, modal isolation")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED issue293: %d" % failures.size())
		get_tree().quit(1)
