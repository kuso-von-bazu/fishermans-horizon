extends Node
## Audio — 効果音とBGMの再生を担うシングルトン。
## SFXはプール再生、BGMは finished シグナルでループさせる。

var _sfx_pool: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _current_bgm: String = ""
# #253: 波の音。ゲーム中は常時ループ。オープニング/エンディング/ポーズ中は止める
var _ambient: AudioStreamPlayer
# #251再: 放射系武器の持続音。撃っている間だけ鳴らし続ける(1系統ずつ)
var _loop_sfx: AudioStreamPlayer
var _loop_name: String = ""
const LOOP_FILES := {
	"sfx_flamer": "res://assets/audio/火炎放射.mp3",
	"sfx_chiller": "res://assets/audio/冷気放射.mp3",
}
const AMBIENT_FILE := "res://assets/audio/波の音.mp3"
# 航海中・寄港中だけ true。オープニング/エンディングでは false。
# ポーズ中の判定はここで一括して見る(呼び出し側に散らさない)
var ambient_enabled: bool = false
var _cache: Dictionary = {}
var _bgm_volume: float = 1.0
var _sfx_volume: float = 1.0
const SETTINGS_PATH := "user://audio_settings.cfg"

# 共有者提供のBGM(MP3)を優先使用。無ければ合成wavにフォールバック(_bgm_stream内)
const BGM_FILES := {
	"bgm_sea":       "res://assets/audio/フィールド.mp3",
	"bgm_port":      "res://assets/audio/港.mp3",
	"bgm_boss":      "res://assets/audio/近海の主.mp3",
	"bgm_leviathan": "res://assets/audio/レヴイアタン.mp3",
	"bgm_king":      "res://assets/audio/海賊王.mp3",
	"bgm_ending":    "res://assets/audio/エンディング.mp3",
	# #279: 夜の海域(月下・星霜・常闇)専用の航海BGM
	"bgm_night":     "res://assets/audio/夜.mp3",
}

func _ready() -> void:
	_load_settings()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_bgm = AudioStreamPlayer.new()
	_apply_bgm_volume()
	add_child(_bgm)
	_bgm.finished.connect(func():
		if _bgm.stream:
			_bgm.play())   # ループ
	# #253: 波の音。ポーズ中も鳴り続けないよう process_mode は既定(継承)のまま
	_ambient = AudioStreamPlayer.new()
	add_child(_ambient)
	if ResourceLoader.exists(AMBIENT_FILE):
		var amb := load(AMBIENT_FILE)
		if amb is AudioStreamMP3:
			amb.loop = true
		_ambient.stream = amb
	_apply_ambient_volume()
	# #251再: 放射音のループ再生用
	_loop_sfx = AudioStreamPlayer.new()
	add_child(_loop_sfx)
	# ポーズ中でも止める判断ができるよう、Audio自身は常に動かす
	process_mode = Node.PROCESS_MODE_ALWAYS

# #226: 共有者提供の効果音(mp3)を優先使用。無ければ従来の合成wav。
const SFX_FILES := {
	"sfx_gun": "res://assets/audio/ガトリングガン.mp3",
	"sfx_cannon": "res://assets/audio/大砲.mp3",      # #226再2: 大砲・大口径カノン砲
	"sfx_skill": "res://assets/audio/スキル.mp3",     # #226再2: スキル発動(突撃・一斉射撃)
	"sfx_torpedo": "res://assets/audio/魚雷.mp3",       # #226再3: 魚雷・追尾魚雷改
	"sfx_harpoon": "res://assets/audio/銛.mp3",         # #47再3: 銛・強化銛砲
	"sfx_lord_roar": "res://assets/audio/近海の主の鳴き声.mp3",   # #79再: 主・レヴィアタン出現時
	# #233再2: 共有者提供の効果音。無ければ音声生成.py の合成wavへフォールバック
	"sfx_crit": "res://assets/audio/クリティカル.mp3",
	# #278再3: 入港・出港の汽笛を共有者提供のmp3に差し替え(従来は合成音)
	"sfx_horn": "res://assets/audio/汽笛.mp3",
}

func _stream_of(name: String) -> AudioStream:
	if not _cache.has(name):
		var s: AudioStream = null
		if SFX_FILES.has(name) and ResourceLoader.exists(SFX_FILES[name]):
			s = load(SFX_FILES[name])
			if s is AudioStreamMP3:
				s.loop = false   # 効果音なのでループさせない
		if s == null:
			var path := "res://assets/audio/%s.wav" % name
			s = load(path) if ResourceLoader.exists(path) else null
		_cache[name] = s
	return _cache[name]

# #47再4: 特定の効果音だけ音量を微調整する(呼び出し側の指定にこの値を足す)
const SFX_VOL_ADJ := {
	"sfx_harpoon": -6.0,   # 銛の音が大きかったので少し下げる
}

func play(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	vol_db += float(SFX_VOL_ADJ.get(name, 0.0)) + _volume_db(_sfx_volume)
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
	# #279: 専用曲が見つからないときは通常の航海BGMへ退避する(無音にしない)
	if s == null and name != "bgm_sea":
		s = _bgm_stream("bgm_sea")
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

func _process(_d: float) -> void:
	# #253: ゲーム中は常時。オープニング・エンディング・ポーズ中は鳴らさない
	var want: bool = ambient_enabled and not get_tree().paused
	if want:
		play_ambient()
	else:
		stop_ambient()

# #251再: 放射系の持続音。撃っている間は毎フレーム呼び、離したら stop_loop_sfx()。
func play_loop_sfx(name: String) -> void:
	if not LOOP_FILES.has(name):
		return
	if _loop_name == name and _loop_sfx.playing:
		return   # すでに鳴っている(重ねて鳴らさない)
	var path: String = str(LOOP_FILES[name])
	if not ResourceLoader.exists(path):
		return
	var st := load(path)
	if st is AudioStreamMP3:
		st.loop = true
	_loop_sfx.stream = st
	_loop_sfx.volume_db = -12.0 + _volume_db(_sfx_volume)
	_loop_name = name
	_loop_sfx.play()

func stop_loop_sfx() -> void:
	if _loop_sfx and _loop_sfx.playing:
		_loop_sfx.stop()
	_loop_name = ""

func loop_sfx_name() -> String:
	return _loop_name if (_loop_sfx and _loop_sfx.playing) else ""

# #253: 波の音の開始/停止。BGMの音量設定に連動させる
func play_ambient() -> void:
	if _ambient and _ambient.stream and not _ambient.playing:
		_ambient.play()

func stop_ambient() -> void:
	if _ambient:
		_ambient.stop()

func ambient_playing() -> bool:
	return _ambient != null and _ambient.playing

func bgm_volume() -> float:
	return _bgm_volume

func sfx_volume() -> float:
	return _sfx_volume

func set_bgm_volume(value: float) -> void:
	_bgm_volume = clampf(value, 0.0, 1.0)
	_apply_bgm_volume()
	_save_settings()

func set_sfx_volume(value: float) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	_save_settings()

func _volume_db(value: float) -> float:
	return -80.0 if value <= 0.001 else linear_to_db(value)

func _apply_bgm_volume() -> void:
	if _bgm:
		_bgm.volume_db = -10.0 + _volume_db(_bgm_volume)
	_apply_ambient_volume()

func _apply_ambient_volume() -> void:
	if _ambient:
		_ambient.volume_db = -16.0 + _volume_db(_bgm_volume)   # #253: BGMより控えめに敷く

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_bgm_volume = clampf(float(cfg.get_value("audio", "bgm", 1.0)), 0.0, 1.0)
		_sfx_volume = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm", _bgm_volume)
	cfg.set_value("audio", "sfx", _sfx_volume)
	cfg.save(SETTINGS_PATH)
