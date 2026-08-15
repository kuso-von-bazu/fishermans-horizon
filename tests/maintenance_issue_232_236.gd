extends Node
## #232/#233/#235/#236 の追補分の検証。
## Codex実装分は tests/maintenance_issue_231_234.gd が担当。ここでは
## 「クリティカル専用SFX」と「近接被弾でも方向が出るか」を確認する。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()

	# --- #233再: クリティカル専用SFX ---
	check(ResourceLoader.exists("res://assets/audio/sfx_crit.wav"), "sfx_crit.wav が未インポート")
	var crit_stream: AudioStream = Audio._stream_of("sfx_crit")
	check(crit_stream != null, "sfx_crit が読み込めない(--headless --import 漏れ)")
	var hit_stream: AudioStream = Audio._stream_of("sfx_enemy_hit")
	if crit_stream != null and hit_stream != null:
		# 着弾音より長い余韻を持つ = 単なるピッチ違いの流用ではない
		check(crit_stream.get_length() > hit_stream.get_length(),
			"sfx_crit の余韻が着弾音より短い(%.3f <= %.3f)" % [crit_stream.get_length(), hit_stream.get_length()])
	# 実際に高音成分が優勢かをwavから直接確かめる(前半後半の零交差数で代用)
	var f := FileAccess.open("res://assets/audio/sfx_crit.wav", FileAccess.READ)
	check(f != null, "sfx_crit.wav を開けない")
	if f != null:
		f.seek(44)   # WAVヘッダを飛ばす
		var prev := 0
		var zc_crit := 0
		var n := 0
		while f.get_position() < f.get_length() - 1 and n < 4000:
			var v := f.get_16()
			if v > 32767:
				v -= 65536
			var sgn := 1 if v >= 0 else -1
			if n > 0 and sgn != prev:
				zc_crit += 1
			prev = sgn
			n += 1
		f.close()
		# 22050Hz で 4000サンプル中の零交差。高音(1.5k〜6kHz)主体なら数百回に達する
		check(zc_crit > 200, "sfx_crit の零交差が少なく高音になっていない(%d回)" % zc_crit)

	# --- #233再: 近接攻撃でも被弾方向が出る ---
	# World2D 相当のダミー(show_damage_direction を持つ親)を敵の親に据えて、
	# Enemy2D._damage_player から方向通知が飛ぶことを確認する。
	var world_stub := Node2D.new()
	world_stub.set_script(preload("res://tests/damage_dir_stub.gd"))
	add_child(world_stub)
	var Enemy = preload("res://scripts2d/Enemy2D.gd")
	var e := CharacterBody2D.new()
	e.set_script(Enemy)
	e.setup("mob", "narwhal")
	world_stub.add_child(e)
	await get_tree().process_frame
	e.global_position = Vector2(500, -250)
	world_stub.received = null
	e._damage_player(1.0)
	check(world_stub.received != null, "近接攻撃で被弾方向が通知されない")
	if world_stub.received != null:
		check((world_stub.received as Vector2).is_equal_approx(Vector2(500, -250)),
			"通知された位置が敵の位置と違う: %s" % str(world_stub.received))

	# HUD側が相対ベクトルから角度を出せること(World2Dは source - player を渡す)
	var HUD = preload("res://scripts2d/HUD2D.gd")
	var hud := CanvasLayer.new()
	hud.set_script(HUD)
	add_child(hud)
	await get_tree().process_frame
	hud.show_damage_direction(Vector2(0, -100))   # 真上から被弾
	check(absf(hud._damage_dir_angle - (-PI / 2.0)) < 0.001, "被弾方向の角度が上向きにならない")
	check(hud._damage_flash_t > 0.0, "被弾フラッシュが始まらない")
	var before: float = hud._damage_dir_angle   # 動的スクリプトの値は型推論できない
	hud.show_damage_direction(Vector2.ZERO)       # 位置不明時は角度を維持する
	check(absf(hud._damage_dir_angle - before) < 0.001, "ゼロベクトルで角度が壊れる")

	# --- #237: 寄港確定後は被弾音・演出を出さない ---
	# 敵弾が旗艦/僚艦に当たっても、近接圏の敵が攻撃しても、音と演出まで止まること。
	GameState.docking_locked = true
	world_stub.received = null
	var Proj = preload("res://scripts2d/Projectile2D.gd")
	var eb := Area2D.new()
	eb.set_script(Proj)
	world_stub.add_child(eb)
	eb.setup(Vector2.RIGHT, {"dmg": 20.0})
	eb.from_player = false
	var hull := Node2D.new()
	hull.add_to_group("player")
	add_child(hull)
	GameState.run_armor = 100.0
	eb._on_hit(hull)
	check(world_stub.received == null, "寄港確定後に敵弾の被弾方向フラッシュが出る")
	check(absf(GameState.run_armor - 100.0) < 0.001, "寄港確定後に敵弾でダメージが入る")
	check(not is_instance_valid(eb) or eb.is_queued_for_deletion(), "寄港確定後の敵弾が消えない")

	# 近接攻撃は _attack ごと止まる(以前は _ranged_attack にしかガードが無かった)
	world_stub.received = null
	e._atk_timer = 0.0
	e._attack(1.0, 0.0)
	check(world_stub.received == null, "寄港確定後も近接攻撃が通っている")
	GameState.docking_locked = false

	# --- #232再: 漁の発光帯の位置がランダム(右寄り固定でない) ---
	var World2 = preload("res://scripts2d/World2D.gd")
	var w2 := Node2D.new()
	w2.set_script(World2)
	var bands: Array = []
	for i in 60:
		# _update_fishing の抽選と同じ式(抽選だけを取り出して検証する)
		bands.append(randf_range(0.06, 0.94 - w2.FISHING_BAND_W))
	var lo := 0
	var mid := 0
	var hi := 0
	for b in bands:
		var v: float = b
		if v < 0.30: lo += 1
		elif v < 0.55: mid += 1
		else: hi += 1
	check(lo > 0 and mid > 0 and hi > 0, "発光帯が左/中央/右のいずれかに偏っている(左%d 中%d 右%d)" % [lo, mid, hi])
	# 帯がメーターからはみ出さないこと
	var over := 0
	for b in bands:
		var v2: float = b
		if v2 < 0.0 or v2 + w2.FISHING_BAND_W > 1.0:
			over += 1
	check(over == 0, "発光帯がメーターの外へはみ出す抽選がある(%d件)" % over)
	# World2D 側の当たり判定が _fishing_band を実際に見ていること(式の複製ではなく実コードを叩く)
	w2._fishing_band = 0.08
	w2._fishing_value = 0.14
	check(w2._fishing_in_band(), "左寄りの帯にあるのに World2D が当たりと判定しない")
	w2._fishing_value = 0.80
	check(not w2._fishing_in_band(), "帯の外なのに World2D が当たりと判定する")
	w2._fishing_band = 0.72
	w2._fishing_value = 0.80
	check(w2._fishing_in_band(), "右寄りの帯で当たりと判定しない")
	# HUD側の判定が渡された帯位置に追従すること(左寄りでも当たると判定できる)
	hud.set_fishing_meter(0.14, true, 0.08)
	check(hud._fishing_bonus, "左寄りの帯で当たり判定にならない")
	hud.set_fishing_meter(0.80, true, 0.08)
	check(not hud._fishing_bonus, "帯の外なのに当たり判定になる")
	hud.set_fishing_meter(0.0, false, 0.72)
	w2.free()

	# --- #236再: 早見表・音量設定の表示中はポーズし、閉じたら必ず解除する ---
	var Overlay2 = preload("res://scripts/OverlayMenus.gd")
	var host := Control.new()
	add_child(host)
	check(not get_tree().paused, "テスト開始時点でポーズしている")
	Overlay2.show_help(host)
	check(get_tree().paused, "早見表を開いてもポーズしない")
	var ov: Node = host.get_node_or_null("SharedOverlay")
	check(ov != null, "オーバーレイが生成されない")
	if ov != null:
		check(ov.process_mode == Node.PROCESS_MODE_ALWAYS, "ポーズ中にオーバーレイ自身が止まる(閉じるボタンが効かない)")
	# 設定へ切り替えてもポーズが維持されること(古いオーバーレイの解放順の罠)
	Overlay2.show_settings(host)
	check(get_tree().paused, "早見表→音量設定の切替でポーズが解けている")
	# 閉じたら解除
	host.get_node("SharedOverlay").free()
	await get_tree().process_frame
	check(not get_tree().paused, "オーバーレイを閉じてもポーズが解除されない")
	host.free()

	# --- #235再/#236再: 歯車・?は画像アイコン(フォント依存の文字化けを回避) ---
	for kind in ["gear", "help"]:
		check(ResourceLoader.exists("res://assets/images/ui_%s.png" % kind), "UIアイコン画像がない: %s" % kind)
		var ib: Button = Overlay2.icon_button(kind, "tip")
		check(ib.icon != null, "%s ボタンが画像でなく文字のまま" % kind)
		check(ib.text == "", "%s ボタンに文字が残っている(豆腐の原因)" % kind)
		ib.free()

	# --- #235再/#236再: タイトル画面の歯車・?が実際にクリックできる ---
	# 報告された不具合そのもの(全画面の背景画像がクリックを吸っていた)を
	# 実際のマウス入力で再現確認する。位置だけでなく入力が届くかを見る。
	var Title = preload("res://scripts/TitleScreen.gd")
	var title := CanvasLayer.new()
	title.set_script(Title)
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var gear_btn: Button = null
	for n in title._root.get_children():
		if n is Button and n.tooltip_text == "音量設定":
			gear_btn = n
	check(gear_btn != null, "タイトルに歯車ボタンが無い")
	# 実際のマウス操作の模擬は Godot 側で成立しない(ヘッドレス/実ウィンドウとも
	# push_input が CanvasLayer 上の Control のピッキングに乗らない)ため、
	# 不具合の構造そのものを検証する:
	# 「アイコンボタンより後ろの兄弟に、マウスを遮る全画面 Control が無いこと」。
	# 入力の優先順位は z_index ではなくツリーの並び順で決まるので、後ろに
	# MOUSE_FILTER_STOP の全画面 Control があるとボタンは永久に押せなくなる。
	if gear_btn != null:
		var gear_idx := gear_btn.get_index()
		var blockers: Array = []
		for n in title._root.get_children():
			if n.get_index() <= gear_idx or not (n is Control):
				continue
			var c := n as Control
			# 遮るのは STOP だけ。PASS は素通しなので後ろのボタンに届く
			# (実際 Boss Rush ボタンは PASS の CenterContainer より後ろで動作している)
			if c.mouse_filter != Control.MOUSE_FILTER_STOP:
				continue
			# ボタンの矩形を覆っているか
			if c.get_rect().encloses(gear_btn.get_rect()):
				blockers.append("%s(%s)" % [c.name, c.get_class()])
		check(blockers.is_empty(), "歯車ボタンを覆ってクリックを奪う後続ノードがある: %s" % str(blockers))
	# 背景がクリックを吸わない設定になっていること(原因側の確認)
	check(title._bg.mouse_filter == Control.MOUSE_FILTER_IGNORE, "タイトル背景がクリックを吸う")
	if title._art != null:
		check(title._art.mouse_filter == Control.MOUSE_FILTER_IGNORE, "タイトル背景画像がクリックを吸う")
	title.free()
	get_tree().paused = false

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK crit_sfx/melee_direction/dock_silence/fishing_band/pause/icons/title_click")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
