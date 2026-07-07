extends Node
## Audio — 効果音とBGMの再生を担うシングルトン。
## SFXはプール再生、BGMは finished シグナルでループさせる。

var _sfx_pool: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _current_bgm: String = ""
var _cache: Dictionary = {}

# 共有者提供のBGM(MP3)を優先使用。無ければ合成wavにフォールバック(_bgm_stream内)
const BGM_FILES := {
	"bgm_sea":       "res://assets/audio/フィールド.mp3",
	"bgm_port":      "res://assets/audio/港.mp3",
	"bgm_boss":      "res://assets/audio/近海の主.mp3",
	"bgm_leviathan": "res://assets/audio/レヴイアタン.mp3",
	"bgm_king":      "res://assets/audio/海賊王.mp3",
	"bgm_ending":    "res://assets/audio/エンディング.mp3",
}

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

# BGMストリーム: MP3(共有者提供)を優先、無ければ合成wav。ループ有効化。
func _bgm_stream(name: String) -> AudioStream:
	var key := "bgm::" + name
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	if BGM_FILES.has(name) and ResourceLoader.exists(BGM_FILES[name]):
		s = load(BGM_FILES[name])
	if s == null:
		s = _stream_of(name)
	# MP3/Vorbis/wavそれぞれのループ指定(ギャップレス)
	if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = true
	_cache[key] = s
	return s

func play_bgm(name: String) -> void:
	if _current_bgm == name:
		return
	_current_bgm = name
	var s := _bgm_stream(name)
	_bgm.stream = s
	if s:
		_bgm.play()

func stop_bgm() -> void:
	_current_bgm = ""
	_bgm.stop()
