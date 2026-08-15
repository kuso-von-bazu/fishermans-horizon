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

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK crit_sfx/melee_damage_direction")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
