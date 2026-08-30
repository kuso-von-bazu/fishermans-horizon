extends Node
## #282: 嵐越えの島・海嘯の島(共有の専用曲)/ 果ての島(専用曲)の航海BGM差し替えを検証する。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()

	# --- 共有者提供のmp3が同梱・インポートされていること ---
	var storm_path := "res://assets/audio/嵐越えの島海域・海嘯の島海域.mp3"
	var blizzard_path := "res://assets/audio/果ての島海域.mp3"
	check(ResourceLoader.exists(storm_path), "嵐越えの島海域・海嘯の島海域.mp3 が無い(未インポート)")
	check(ResourceLoader.exists(blizzard_path), "果ての島海域.mp3 が無い(未インポート)")

	# --- Audio._bgm_stream が提供mp3を読み込むこと(合成/デフォルトへのフォールバックでない) ---
	var World = preload("res://scripts2d/World2D.gd")
	var storm_stream: AudioStream = Audio._bgm_stream("bgm_storm")
	var blizzard_stream: AudioStream = Audio._bgm_stream("bgm_blizzard")
	var sea_stream: AudioStream = Audio._bgm_stream("bgm_sea")
	check(storm_stream is AudioStreamMP3, "bgm_storm が提供mp3で読み込まれていない")
	check(blizzard_stream is AudioStreamMP3, "bgm_blizzard が提供mp3で読み込まれていない")
	check(storm_stream != sea_stream, "bgm_storm が通常の航海BGMのまま(差し替わっていない)")
	check(blizzard_stream != sea_stream, "bgm_blizzard が通常の航海BGMのまま(差し替わっていない)")
	check(storm_stream != blizzard_stream, "嵐/果ての島で同じ曲になっている")
	if storm_stream is AudioStreamMP3:
		check((storm_stream as AudioStreamMP3).loop, "bgm_storm がループしない")
	if blizzard_stream is AudioStreamMP3:
		check((blizzard_stream as AudioStreamMP3).loop, "bgm_blizzard がループしない")

	# --- World2D._sea_bgm が海域(天候)ごとに正しい曲を選ぶこと ---
	var w := World.new()
	add_child(w)
	for spec in [
		["嵐越えの島(storm)", 3, "bgm_storm"],
		["海嘯の島(surge)", 7, "bgm_storm"],
		["果ての島(blizzard)", 4, "bgm_blizzard"],
		["月下の島(night、従来どおり夜BGM)", 2, "bgm_night"],
		["始まりの島(sunny、従来どおり通常BGM)", 0, "bgm_sea"],
	]:
		GameState.current_island = int(spec[1])
		var got: String = w._sea_bgm()
		check(got == str(spec[2]), "%s の航海BGMが %s でない(実際 %s)" % [str(spec[0]), str(spec[2]), got])
	w.free()

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK storm_blizzard_bgm")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
