extends Node
## Audio — 効果音とBGMの再生を担うシングルトン。
## SFXはプール再生、BGMは finished シグナルでループさせる。

var _sfx_pool: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _current_bgm: String = ""
var _cache: Dictionary = {}

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = -10.0
	add_child(_bgm)
	_bgm.finished.connect(func():
		if _bgm.stream:
			_bgm.play())   # ループ

func _stream_of(name: String) -> AudioStream:
	if not _cache.has(name):
		var path := "res://assets/audio/%s.wav" % name
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name]

func play(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _stream_of(name)
	if s == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = s
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	# 全て再生中なら先頭を上書き
	_sfx_pool[0].stream = s
	_sfx_pool[0].volume_db = vol_db
	_sfx_pool[0].pitch_scale = pitch
	_sfx_pool[0].play()

func play_bgm(name: String) -> void:
	if _current_bgm == name:
		return
	_current_bgm = name
	var s := _stream_of(name)
	_bgm.stream = s
	if s:
		_bgm.play()

func stop_bgm() -> void:
	_current_bgm = ""
	_bgm.stop()
