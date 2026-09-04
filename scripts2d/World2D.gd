extends Node2D
## World2D — 見下ろし2D版の統合。3D版Worldの全要素(#1〜#23対応込み)を2Dで再構成。
## フェーズ: title / dock(港メニュー) / sea(漁・戦闘)。ロジックは GameState/Database を共用。

const PlayerScript = preload("res://scripts2d/Player2D.gd")
const IslandScript = preload("res://scripts2d/Island2D.gd")
const FishSchoolScript = preload("res://scripts2d/FishSchool2D.gd")
const EnemyScript = preload("res://scripts2d/Enemy2D.gd")
const ProjectileScript = preload("res://scripts2d/Projectile2D.gd")
const RelicScript = preload("res://scripts2d/Relic2D.gd")
const FlotsamScript = preload("res://scripts2d/Flotsam2D.gd")   # #267
const ObstacleScript = preload("res://scripts2d/Obstacle2D.gd")
const EscortScript = preload("res://scripts2d/Escort2D.gd")
const HUDScript = preload("res://scripts2d/HUD2D.gd")
const PortUIScript = preload("res://scripts/PortUI.gd")
const TitleScript = preload("res://scripts/TitleScreen.gd")
const OverlayMenusScript = preload("res://scripts/OverlayMenus.gd")   # #235/#236: 撮影フック用

const K := 6.0          # 3D数値→2D px 換算
var player: CharacterBody2D
var camera: Camera2D
var islands: Array = []
var hud: CanvasLayer
var port_ui: CanvasLayer
var title: CanvasLayer
var ocean_mat: ShaderMaterial
var weather_mat: ShaderMaterial   # #190/#191/#192: 近海ごとの天候オーバーレイ
var weather_rect: ColorRect
var _weather_cur: Dictionary = {"tint": Color(0,0,0,0), "rain": 0.0, "snow": 0.0, "night": 0.0, "rough": 0.0, "moon": 1.0, "stars": 0.0}
var _weather_target: Dictionary = {"tint": Color(0,0,0,0), "rain": 0.0, "snow": 0.0, "night": 0.0, "rough": 0.0, "moon": 1.0, "stars": 0.0}
var _weather_name: String = ""

var phase: String = "title"
var fish_schools: Array = []
var enemies: Array = []
var relics_world: Array = []
var flotsam_world: Array = []   # #267: 漂流者・漂流貨物
var obstacles: Array = []      # #193: 海上の障害物(岩礁/流氷)
var escorts: Array = []        # #196: 船団の僚艦(2番艦〜5番艦)
var slot_cooldowns: Array = [0.0, 0.0, 0.0, 0.0]
var slot_ammo: Array = [0, 0, 0, 0]        # #27: 残弾。0でリロード(reload秒)
var lock_target: Node2D = null
var spawn_timer: float = 0.0
const MAX_FISH := 7
const MAX_ENEMIES := 6   # 主(+取り巻き)以外の通常敵の上限(#69/#71/#72/#73再修正)
var _dock_grace: float = 0.0
var _dock_target: int = -1
var _returning: bool = false
var _victory_shown: bool = false
var _food_choice_shown: bool = false
var _food_dialog_open: bool = false
var _food_dialog: CanvasLayer
var _food_msg: Label
var _boss_bgm_on: String = ""    # #79: 主接近中の緊迫BGM("" / "bgm_boss" / "bgm_leviathan")
var _return_hold: float = 0.0    # #68: 帰還キー長押しの累積秒
# #209: ボスラッシュ
var _boss_rush: bool = false
var _br_split_root: String = ""   # #209再10: 分裂する主のID(分裂体が残る間は未撃破)
var _br_index: int = 0
var _br_boss: Node = null
var _br_active: bool = false   # ボスが出現中(解放済み参照は null 比較で真になるため別途フラグで持つ)
var _br_boss2: Node = null     # #209再4: 番いの主(ギガントセイウチ)の2体目
var _br_pair: bool = false     # 番いかどうか(解放済み参照の null 比較を避けるためフラグで持つ)
var _br_wait: float = 0.0
var _br_won: bool = false      # #284: レヴィアタン討伐の瞬間から旗艦を無敵にし、_br_fail()を封じる
var _skill_cd: float = 0.0        # #224: スキルのクールダウン残り
var _skill_cd_max: float = 1.0
var _fishing_target: Node = null     # #232: 漁ゲージの対象魚群
var _fishing_phase: float = 0.0
var _fishing_value: float = 0.0
# #232再: 発光帯(2倍)の左端。漁のたびに抽選して当たりの位置を固定させない
const FISHING_BAND_W := 0.19   # #232再5: 帯の幅
var _fishing_band: float = 0.72

# 離した瞬間の針が発光帯の中にあるか
func _fishing_in_band() -> bool:
	return _fishing_value >= _fishing_band and _fishing_value <= _fishing_band + FISHING_BAND_W

func island_pos(idx: int) -> Vector2:
	var p: Vector3 = Database.island(idx).pos
	return Vector2(p.x, p.z) * K

func _ready() -> void:
	add_to_group("world2d")   # #278(提案6): 効果側から夜の海域かどうかを引くため
	GameState.load_display_settings()   # #278(提案4): 画面シェイクのON/OFF
	_build_ocean()
	_build_weather()
	_build_islands()
	_build_player()
	# #256: 射線が遮られていることを海面上に赤で示すオーバーレイ
	_los_overlay = Node2D.new()
	_los_overlay.set_script(preload("res://scripts2d/LosOverlay2D.gd"))
	_los_overlay.z_index = 5
	add_child(_los_overlay)
	_build_fade()   # #278(提案7-4): 入港・出港のフェード
	hud = HUDScript.new()
	add_child(hud)
	port_ui = PortUIScript.new()
	add_child(port_ui)
	port_ui.set_sail_requested.connect(_on_set_sail)
	port_ui.fast_travel_requested.connect(_on_fast_travel)
	GameState.stats_changed.connect(_on_stats_changed)
	title = TitleScript.new()
	add_child(title)
	title.start_pressed.connect(_on_title_start)
	title.continue_pressed.connect(_on_title_continue)
	title.boss_rush_pressed.connect(_on_boss_rush)   # #209
	GameState.load_achievements()   # #265: 実績はセーブとは別に読み込む
	GameState.dock_reset()
	_enter_dock(0, false)
	port_ui.close()
	phase = "title"
	title.show_title()
	_maybe_screenshot()

# ---------------- 構築 ----------------
func _build_ocean() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://shaders/ocean2d.gdshader")
	rect.material = ocean_mat
	layer.add_child(rect)
	# #135: 島のワールド座標をシェーダへ(島周りは淡い青にする)
	var ipos := PackedVector2Array()
	for i in Database.islands.size():
		ipos.append(island_pos(i))
	while ipos.size() < 10:   # #248/#251: シェーダ側の配列長(島10)に合わせる
		ipos.append(Vector2(1e9, 1e9))
	ocean_mat.set_shader_parameter("islands", ipos)
	ocean_mat.set_shader_parameter("island_count", mini(Database.islands.size(), 10))
	# #278(提案7-1): 海岸の白波。浅瀬の縁は Island2D._coast(132*small, wob, seed_off=1)。
	# シェーダ側で同じ式を再現できるよう、半径・ゆらぎ・位相を渡す。
	var irad := PackedFloat32Array()
	var iwob := PackedFloat32Array()
	var iseed := PackedFloat32Array()
	for i in 10:
		if i < Database.islands.size() and i < IslandScript.PALETTES.size():
			var pal: Dictionary = IslandScript.PALETTES[i]
			irad.append(132.0 * float(pal.get("small", 1.0)))
			iwob.append(float(pal.get("wob", 0.16)))
			iseed.append(float(i * 7 + 1))
		else:
			irad.append(0.0)
			iwob.append(0.0)
			iseed.append(0.0)
	ocean_mat.set_shader_parameter("island_r", irad)
	ocean_mat.set_shader_parameter("island_wob", iwob)
	ocean_mat.set_shader_parameter("island_seed", iseed)

# #278(提案7-4): 入港・出港の切り替えに0.3秒のフェード+汽笛を挟む。
# 画面の差し替え自体は従来どおり即座に行い、その上を暗幕が晴れていく形にする
# (切り替えを await にすると、寄港・出港を呼ぶ箇所すべてに影響が及ぶため)。
var _fade: ColorRect
var _shot_mode: bool = false   # --shot での撮影中はフェードを出さない
var _debris_targets: Array = []   # --shot:debris で撮影直前に倒す敵

func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30   # 港UI(20)より前、実績トースト(40)より後ろ
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)

func port_transition(with_horn := true) -> void:
	if _fade == null or _shot_mode:
		return
	_fade.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.3)
	if with_horn:
		Audio.play("sfx_horn", -10.0)

# #190/#191/#192: 天候オーバーレイ(夜/大雨/吹雪)。海の上・HUDの下に全画面で重ねる
func _build_weather() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	weather_rect = ColorRect.new()
	weather_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	weather_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather_mat = ShaderMaterial.new()
	weather_mat.shader = load("res://shaders/weather2d.gdshader")
	weather_rect.material = weather_mat
	layer.add_child(weather_rect)
	_apply_weather("")

# #191再: 天候は current_island でなく「実際にいる海域(最寄りの島)」に追従させる。
# 別の島を目指して航行中でも、近づいた海域の天候になる。
# #279: 夜の海域(月下=night / 星霜=starry / 常闇=dark)は専用の航海BGM「夜」を鳴らす
const NIGHT_SEA_WEATHERS := ["night", "starry", "dark"]
# #282: 嵐越えの島(storm)・海嘯の島(surge)は共有の専用曲、果ての島(blizzard)は単独の専用曲
const STORM_SEA_WEATHERS := ["storm", "surge"]
const BLIZZARD_SEA_WEATHERS := ["blizzard"]

func _sea_bgm() -> String:
	var w := str(Database.island(GameState.current_island).get("weather", ""))
	if NIGHT_SEA_WEATHERS.has(w):
		return "bgm_night"
	if STORM_SEA_WEATHERS.has(w):
		return "bgm_storm"
	if BLIZZARD_SEA_WEATHERS.has(w):
		return "bgm_blizzard"
	return "bgm_sea"

func _nearest_island_weather() -> String:
	if not is_instance_valid(player):
		return ""
	var best := 1e18
	var best_i := GameState.current_island
	for i in Database.islands.size():
		var d: float = player.global_position.distance_to(island_pos(i))
		if d < best:
			best = d
			best_i = i
	return str(Database.island(best_i).get("weather", ""))

# 天候名から目標パラメータを求める(反映は _update_weather で滑らかに補間)
func _weather_params(w: String) -> Dictionary:
	var tint := Color(0, 0, 0, 0)
	var rain := 0.0
	var snow := 0.0
	var night := 0.0
	var rough := 0.0
	var moon := 1.0    # #239: 海面に映る月(月下のみ)
	var stars := 0.0   # #239: 海面に映る星(星霜のみ)
	var sunlight := 0.0   # #250: 強い日射し(潮鳴りのみ)
	match w:
		"sunny":     # #250: 潮鳴りの島。始まりの島より明るく、海面に太陽の反射
			sunlight = 1.0
		"night":     # #190: 月下の島の近海は常に夜
			tint = Color(0.05, 0.08, 0.22, 0.40)
			night = 1.0
		"storm":     # #191: 嵐越えの島の近海は大雨と高波
			tint = Color(0.10, 0.12, 0.18, 0.24)
			rain = 1.0
			rough = 1.0
		"blizzard":  # #192: 果ての島の近海は吹雪と荒波
			tint = Color(0.72, 0.80, 0.90, 0.18)
			snow = 1.0
			rough = 0.85
		"flurry":    # #248: 北の孤島。吹雪を弱めた雪(天候効果そのものは吹雪と同じ)
			tint = Color(0.72, 0.80, 0.90, 0.10)
			snow = 0.40
			rough = 0.85
		"starry":    # #239: 星霜の島。月下から月の反射を除き、星の反射を敷き詰める
			tint = Color(0.05, 0.08, 0.22, 0.40)
			night = 1.0
			moon = 0.0
			stars = 1.0
		"dark":      # #239: 常闇の島。月下から月の反射を除いただけの暗い海
			tint = Color(0.04, 0.06, 0.16, 0.46)
			night = 1.0
			moon = 0.0
		"surge":     # #239: 海嘯の島。嵐越えから雨を除いた荒波
			tint = Color(0.10, 0.12, 0.18, 0.24)
			rough = 1.0
	return {"tint": tint, "rain": rain, "snow": snow, "night": night, "rough": rough, "moon": moon, "stars": stars, "sunlight": sunlight}

# 目標値を設定(instant=trueで即反映。寄港/出港時のみ)
func _apply_weather(w: String, instant := true) -> void:
	_weather_name = w
	GameState.active_weather = w
	_weather_target = _weather_params(w)
	if instant:
		_weather_cur = _weather_target.duplicate()
	_push_weather()

# #278(提案6): 夜の海域(月下・星霜・常闇)か。砲口炎・爆発・炎上の光はここでだけ出す
func is_night_sea() -> bool:
	return phase == "sea" and float(_weather_cur.get("night", 0.0)) > 0.5

# 現在値をシェーダへ流し込む
func _push_weather() -> void:
	if weather_mat:
		weather_mat.set_shader_parameter("tint", _weather_cur.tint)
		weather_mat.set_shader_parameter("rain", _weather_cur.rain)
		weather_mat.set_shader_parameter("snow", _weather_cur.snow)
	if weather_rect:
		weather_rect.visible = _weather_cur.tint.a > 0.001 or _weather_cur.rain > 0.001 or _weather_cur.snow > 0.001
	if ocean_mat:
		ocean_mat.set_shader_parameter("night", _weather_cur.night)
		ocean_mat.set_shader_parameter("rough", _weather_cur.rough)
		ocean_mat.set_shader_parameter("moon", _weather_cur.moon)     # #239
		ocean_mat.set_shader_parameter("stars", _weather_cur.stars)   # #239
		ocean_mat.set_shader_parameter("sunlight", _weather_cur.sunlight)   # #250

# 航行中は最寄りの海域の天候へ徐々に寄せる(海域をまたぐと自然に切り替わる)
func _update_weather(delta: float) -> void:
	if phase != "sea":
		return
	var want := _nearest_island_weather()
	if want != _weather_name:
		_weather_name = want
		GameState.active_weather = want
		_weather_target = _weather_params(want)
	var t: float = clampf(delta / 1.5, 0.0, 1.0)
	_weather_cur.tint = (_weather_cur.tint as Color).lerp(_weather_target.tint, t)
	for k in ["rain", "snow", "night", "rough", "moon", "stars", "sunlight"]:   # #239/#250
		_weather_cur[k] = lerpf(float(_weather_cur[k]), float(_weather_target[k]), t)
	_push_weather()

func _build_islands() -> void:
	for i in Database.islands.size():
		var isle := StaticBody2D.new()
		isle.set_script(IslandScript)
		isle.setup(i)
		add_child(isle)
		isle.global_position = island_pos(i)
		isle.dock_ready.connect(_on_dock_ready)
		isle.dock_left.connect(_on_dock_left)
		islands.append(isle)

func _build_player() -> void:
	player = CharacterBody2D.new()
	player.set_script(PlayerScript)
	add_child(player)
	player.global_position = island_pos(0) + Vector2(0, 260)
	# カメラは World 直下(playerの子だと rebuild_visual の全消しで道連れになる)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.global_position = player.global_position

func _input(event: InputEvent) -> void:
	if phase != "sea":
		return
	# #16: マウスホイールでロックオン対象を切替(航海中のみ)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_lock(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_lock(1)
		elif event.button_index == MOUSE_BUTTON_LEFT and not _pointer_on_ui():
			_click_lock(get_global_mouse_position())   # #196: 敵をクリックでロック
	# #196: 1〜4キーで陣形チェンジ
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_formation_slot(0)
			KEY_2: _set_formation_slot(1)
			KEY_3: _set_formation_slot(2)
			KEY_4: _set_formation_slot(3)
			KEY_5: _use_skill()   # #224

# #196: クリック位置に最も近い敵へロックを移す
func _click_lock(pos: Vector2) -> void:
	var best: Node2D = null
	var best_d := 1e18
	for e in _lockable_enemies():
		var r: float = float(e.get("_radius")) if e.get("_radius") != null else 40.0
		var d: float = e.global_position.distance_to(pos)
		if d < r + 40.0 and d < best_d:
			best_d = d
			best = e
	if best != null:
		_set_lock(best)

# ---------------- #278(提案4/5): 打撃感の演出 ----------------
# 画面シェイク(設定でON/OFF・既定OFF)・ヒットストップ・演出ズーム。
# カメラは World 直下にあるので、追従位置へ揺れの分だけオフセットを足す。
var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _shake_amp: float = 0.0
var _zoom_t: float = 0.0
var _zoom_dur: float = 0.0
var _zoom_mult: float = 1.0
var _hitstop_on: bool = false

func screen_shake(amp: float, dur: float) -> void:
	if not GameState.screen_shake or phase != "sea":
		return
	if _shake_t > 0.0 and amp <= _shake_amp:
		return   # 弱い揺れで強い揺れを上書きしない
	_shake_amp = amp
	_shake_dur = dur
	_shake_t = dur

# 敵撃破の瞬間だけ時間を止める。戻すタイマーは ignore_time_scale=true にしないと
# 止めた倍率のまま待つことになり、0.05秒が1秒になってしまう。
func hit_stop(dur := 0.05, scale := 0.05) -> void:
	if _hitstop_on or phase != "sea":
		return
	_hitstop_on = true
	Engine.time_scale = scale
	var t := get_tree().create_timer(dur, true, false, true)
	t.timeout.connect(func():
		Engine.time_scale = 1.0
		_hitstop_on = false)

# 一斉射撃の発動時・主の登場時に少しだけ寄って戻る(索敵範囲は変えないので
# プレイ感には影響しない)
func zoom_punch(mult := 1.1, dur := 0.2) -> void:
	if phase != "sea":
		return
	_zoom_mult = mult
	_zoom_dur = dur
	_zoom_t = dur

func _process(_d: float) -> void:
	# カメラ追従 + 海シェーダにカメラ左上のワールド座標を渡す
	if camera and player:
		var off := Vector2.ZERO
		if _shake_t > 0.0:
			_shake_t = maxf(_shake_t - _d, 0.0)
			var k := _shake_t / maxf(_shake_dur, 0.001)   # 減衰
			off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amp * k
		camera.global_position = player.global_position + off
		var z := 1.0
		if _zoom_t > 0.0:
			_zoom_t = maxf(_zoom_t - _d, 0.0)
			var u := 1.0 - _zoom_t / maxf(_zoom_dur, 0.001)   # 0→1
			z = 1.0 + (_zoom_mult - 1.0) * sin(u * PI)        # 寄って戻る
		camera.zoom = Vector2(z, z)
	if ocean_mat and player:
		var zoom := camera.zoom.x if camera else 1.0
		var cpos := camera.global_position if camera else player.global_position
		var vp := get_viewport_rect().size / maxf(zoom, 0.01)
		ocean_mat.set_shader_parameter("cam_pos", cpos - vp * 0.5)
		ocean_mat.set_shader_parameter("cam_zoom", zoom)
	_update_weather(_d)   # #191再: 航行中は最寄りの海域の天候へ追従

# ---------------- フェーズ ----------------
func _on_title_start() -> void:
	_boss_rush = false          # #209
	GameState.boss_rush = false
	if _victory_shown:
		_victory_shown = false
		GameState.reset_all()
		get_tree().reload_current_scene()
		return
	title.visible = false
	phase = "dock"
	port_ui.open()

# #93: セーブから再開。ロード後は保存された島の港から開始
func _on_title_continue() -> void:
	if not GameState.load_game():
		return
	_victory_shown = false
	title.visible = false
	_enter_dock(GameState.current_island, false)

func _enter_dock(island_id: int, do_reset := true) -> void:
	# #237再3: 自主的な寄港(Eキー)は _forced_return と違い docking_locked を
	# 立てていなかったため、寄港確定の瞬間に飛来していた弾・近接攻撃の被弾音が
	# 素通りしていた(「たまに鳴る」の残り原因)。寄港処理の先頭で必ず立てる。
	# #237再4: ただし海から戻ったときだけ。起動直後やタイトルからの初期化でも
	#   ここを通るが、そこには止めるべき攻撃も敵もいないので立てない
	#   (立てたままだと出港するまでロックが残り、判定に紛れ込む)。
	var was_at_sea := GameState.at_sea
	if was_at_sea:
		GameState.docking_locked = true
	if was_at_sea:
		port_transition(false)   # #278再4: 入港時は汽笛を鳴らさない(出港時のみ)
	if was_at_sea and not GameState.crew.is_empty():
		GameState.grow_crew()   # 航海を終えたクルーが成長(#39)
	phase = "dock"
	# #224: 港へ入った時点で陣形スキルのクールダウンを全回復する
	_skill_cd = 0.0
	_skill_cd_max = 1.0
	_dock_target = -1
	_returning = false
	_clear_return_hold()   # #280: 帰還長押しの進捗とHUD表示を寄港時に必ず戻す
	GameState.current_island = island_id
	if not GameState.visited_islands.has(island_id):
		GameState.visited_islands.append(island_id)   # 到達記録(#19)
	if do_reset:
		GameState.dock_reset()
	player.global_position = island_pos(island_id) + Vector2(0, 260)
	player.velocity = Vector2.ZERO
	player.control_enabled = false
	_apply_weather(str(Database.island(island_id).get("weather", "")))   # #190/#191/#192: 近海の天候
	_clear_sea_actors()
	if hud:
		hud.visible = false
	Audio.play_bgm("bgm_port")
	Audio.ambient_enabled = true   # #253: 寄港中も波の音は鳴らす
	_boss_bgm_on = ""
	# #237再4: ここで解除すると、港にいる間は敵のガードが効かなくなる。
	#   居残った敵が港で近接攻撃を続け、被弾音だけが鳴っていた原因。
	#   出港(GameState.set_sail)で解除されるので、ここでは解除しない。
	# #93: 航海から寄港(強制帰還/大破含む)するたびオートセーブ。勝利時は保存しない
	if was_at_sea and not _victory_shown:
		GameState.save_game()
	port_ui.open(was_at_sea)   # #104: 航海から戻った時だけ寄港バナー

func _on_set_sail() -> void:
	port_ui.close()
	port_transition()   # #278(提案7-4): 出港の演出
	# #93再: 出港時もオートセーブ。航海中に終了しても港での買い物が失われないようにする。
	# 燃料費・賃金・修理費を引く「前」に保存するので、再開時は出港直前の状態に戻る
	# (再開後に出港すればそこで改めて徴収されるため、二重取りにならない)。
	if not _boss_rush and not _victory_shown:
		GameState.save_game()
	phase = "sea"
	# #168: 燃料費(初回出港を除き、船の定価の0.5%・粗末な漁船は5)を徴収
	if GameState.has_departed:
		var fuel := GameState.fuel_cost()
		if fuel > 0:
			var paid_fuel: int = mini(fuel, GameState.money)
			GameState.add_money(-paid_fuel)
			if paid_fuel < fuel:
				GameState.notice.emit("燃料費を踏み倒した!")   # #195: 資金不足で払いきれなかった
			else:
				GameState.notice.emit("燃料費 %d を支払った" % fuel)
	GameState.has_departed = true
	# クルーの賃金(#39): 出港ごとに支払い
	var wages := GameState.crew_wages()
	if wages > 0:
		GameState.add_money(-mini(wages, GameState.money))
		GameState.notice.emit("クルーへ賃金 %d を支払った" % wages)
	# #196: 離脱した船の修理費を徴収してから出港
	var rep := GameState.fleet_repair_cost()
	if rep > 0:
		var paid_rep: int = mini(rep, GameState.money)
		GameState.add_money(-paid_rep)
		if paid_rep < rep:
			GameState.notice.emit("修理費を踏み倒した!")
		else:
			GameState.notice.emit("離脱した船の修理費 %d を支払った" % rep)
		GameState.clear_fleet_damage()
	GameState.set_sail()
	_apply_weather(str(Database.island(GameState.current_island).get("weather", "")))   # #190/#191/#192: 近海の天候
	player.control_enabled = true
	player.rebuild_visual()
	player.global_position = island_pos(GameState.current_island) + Vector2(0, 300)
	player.rotation = PI   # #196再: 出港時は船団ごと真南を向く(forward=+Y)
	hud.visible = true
	hud.rebuild_weapons()
	hud.update_bars()
	hud.set_location("航海中: %s 近海" % Database.island(GameState.current_island).name)
	# #241: 出港時のワンポイントヒント(ボスラッシュは対象外)
	if not _boss_rush and hud and hud.has_method("show_departure_hint"):
		hud.show_departure_hint(GameState.next_departure_hint())
	Audio.play_bgm(_sea_bgm())
	# #259: 出港時に船団速度と、それを決めている船を知らせる
	GameState.notice.emit("船団速度: %.1f (%s が律速)" % [GameState.fleet_speed(), GameState.slowest_ship_name()])
	Audio.ambient_enabled = true   # #253: 波の音
	_boss_bgm_on = ""
	_clear_return_hold()   # #280: 「帰還まで○秒」を持ち越さない
	_dock_grace = 2.0
	_dock_target = -1
	_food_choice_shown = false
	_food_dialog_open = false
	if _food_dialog:
		_food_dialog.visible = false
	get_tree().paused = false   # #24再: ポーズが残ったまま出港しないよう保険
	slot_cooldowns = [0.0, 0.0, 0.0, 0.0]
	_rapid_t = 0.0
	_barrier_t = 0.0
	_reset_ammo()
	GameState.formation_slot = 0        # #196: 陣形1がデフォルト
	_spawn_escorts_fleet()
	if hud and hud.has_method("build_formation_bar"):
		hud.build_formation_bar(_set_formation_slot, _use_skill)   # #224   # #196: 画面上の陣形ボタン
	# #67: 出港時に未討伐の主が確実に海域へ出現しているようにする
	_try_spawn_lord()

func _on_fast_travel(island_id: int) -> void:
	port_ui.close()
	_enter_dock(island_id, true)

func _on_dock_ready(island_id: int) -> void:
	if phase == "sea":
		_dock_target = island_id

func _on_dock_left(island_id: int) -> void:
	if _dock_target == island_id:
		_dock_target = -1

func _update_docking() -> bool:
	if _dock_target < 0 or _dock_grace > 0.0:
		return false
	hud.set_prompt("[E] %s に寄港する" % Database.island(_dock_target).name)
	if Input.is_action_just_pressed("interact"):
		GameState.notice.emit("%s に帰港" % Database.island(_dock_target).name)
		_enter_dock(_dock_target, true)
	return true

# #280: 帰還長押し(R)の進捗と、HUDの「帰還まで○秒」表示をまとめて戻す。
#   長押し中に燃料半減のダイアログが出るとゲームがポーズし、
#   _physics_process の解除処理が走らないまま入港できてしまうため、
#   寄港・出港・ダイアログ表示のそれぞれで確実に消す。
func _clear_return_hold() -> void:
	_return_hold = 0.0
	if hud and hud.has_method("set_return_progress"):
		hud.set_return_progress(0.0)

func _forced_return(reason: String, wrecked: bool = false) -> void:
	if _returning:
		return
	_returning = true
	GameState.docking_locked = true   # #101/#105: この時点以降は被弾・積荷取得を無効化
	if wrecked:
		var lost := GameState.used_hold()
		GameState.cargo.clear()
		GameState.stats_changed.emit()
		Audio.play("sfx_wreck", -2.0)
		var msg := "船が大破! 漁獲物(%d)を失い強制帰還" % lost
		# #99再: 定価の4%の修理費(残金が0未満にならないよう徴収)
		var repair := int(float(GameState.ship().price) * 0.04)
		var paid: int = mini(repair, GameState.money)
		if paid > 0:
			GameState.add_money(-paid)
		if paid < repair:
			msg += "\n修理費を踏み倒した!"   # #195: 資金不足で払いきれなかった
		else:
			msg += "\n修理費 %d を支払った" % paid
		var gone := GameState.wreck_lose_crew()   # #97: 0〜2人ロスト
		if gone != "":
			msg += "\n%s が海に消えた…" % gone
		hud.show_big_message(msg, 4.0)   # #100: 大破メッセージは長めに表示
	else:
		hud.show_big_message(reason)
	GameState.notice.emit(reason)
	if player:
		player.control_enabled = false
	# #100: 大破時は表示時間を確保してから帰港
	await get_tree().create_timer(4.5 if wrecked else 1.8).timeout
	_enter_dock(GameState.current_island, true)

# ---------------- メインループ ----------------
func _physics_process(delta: float) -> void:
	if _los_toast_t > 0.0:
		_los_toast_t = maxf(_los_toast_t - delta, 0.0)   # #256
	if phase != "sea":
		Audio.stop_loop_sfx()   # #251再: 航海中以外では放射音を止める
		if _los_overlay:
			_los_overlay.set_state(null, Vector2.ZERO, Vector2.ZERO, false)
		return
	_update_los_overlay()   # #256
	GameState.regen_fire(delta)
	GameState.tick_slips(delta)   # #64/#72: 炎上・毒のスリップ
	# #209: ボスラッシュ(燃料・魚倉・寄港なし。装甲は回復しない)
	if _boss_rush:
		_br_update(delta)
		_update_spawns(delta)
		_update_weapons(delta)
		_update_lock_on()
		_update_sonar()
		_tick_skill(delta)   # #224
		if hud:
			hud.update_bars()
		if GameState.run_armor <= 0.0 and not _br_won:   # #284: 討伐と同時の大破を無効化
			_br_fail()
		return
	if _dock_grace > 0.0:
		_dock_grace -= delta
	# #258: 燃料は「経過時間」ではなく「進んだ距離」に応じて減らす。
	#   以前は時間比例だったため、遅い船を1隻入れると『遅い』のうえに
	#   『同じ距離で燃料も余計に食う』二重の罰になっていた。
	#   基準は旗艦が単艦で出したときの速度。船団が遅くても同じ距離なら同じ消費になる。
	var _solo_px: float = maxf(float(GameState.ship().speed) * K, 1.0)
	var _moved: float = player.velocity.length() * delta if is_instance_valid(player) else 0.0
	var _weather_mult: float = 1.2 if GameState.active_weather in ["blizzard", "flurry"] and not GameState.boss_rush else 1.0   # #232: 吹雪は燃料消費+20%
	# #258再: 停泊中も従来の15%は消費する(止まれば無消費、を避ける)
	var _rate: float = IDLE_FUEL_RATE + (1.0 - IDLE_FUEL_RATE) * (_moved / _solo_px) / maxf(delta, 0.0001)
	GameState.run_food = maxf(GameState.run_food - delta * _rate * 1.5 * GameState.food_drain_mult() * _weather_mult, 0.0)
	# #68: Rキーを5秒長押しで直近の島へ帰還。長押し中に装甲0なら大破(後段の装甲チェックで処理)
	if Input.is_action_pressed("fast_return") and not _returning and not _food_dialog_open:
		_return_hold += delta
		hud.set_return_progress(_return_hold / 3.0)
		if _return_hold >= 3.0:
			_return_hold = 0.0
			hud.set_return_progress(0.0)
			GameState.notice.emit("%s へ帰還" % Database.island(GameState.current_island).name)
			_enter_dock(GameState.current_island, true)
			return
	elif _return_hold > 0.0:
		_clear_return_hold()
	if not _update_docking():
		_update_fishing(delta)
	_update_spawns(delta)
	_update_weapons(delta)
	_update_lock_on()
	_update_sonar()
	_update_boss_bgm()
	_tick_skill(delta)   # #224
	if hud:
		hud.update_bars()
	_check_victory()   # #159: 画面外でレヴィアタンを倒しても確実に毎フレーム勝利判定
	if _victory_shown:
		return   # #284: レヴィアタン討伐と同時の旗艦大破を無効化(旗艦は討伐の瞬間から無敵)
	# 強制帰還・食料選択(#17/#23)
	if GameState.run_armor <= 0.0:
		_forced_return("船が大破!", true)
	elif GameState.run_food <= 0.0:
		_forced_return("燃料が尽きた! 直近の島へ強制帰還")
	elif GameState.run_food <= GameState.max_food() * 0.5:
		# #285: 果ての島(最終島)には「次の島」の概念が無いため、
		#   その島から出港した航海では燃料半分の通知/強制帰還を出さない。
		if Database.island(GameState.current_island).name != "果ての島":
			if _can_voyage_onward() and _has_onward_island():
				if not _food_choice_shown and not _food_dialog_open:
					_food_choice_shown = true
					_show_food_choice()
			else:
				_forced_return("燃料が半分を切った。直近の島へ強制帰還")

func _on_stats_changed() -> void:
	if hud and hud.visible:
		hud.update_bars()
		hud.refresh_money_fame()
	_check_victory()

func _check_victory() -> void:
	if _victory_shown or _boss_rush:
		return   # #209: ボスラッシュの勝利判定は _br_finish で行う
	if GameState.defeated_lords.has("leviathan") or GameState.claimed_lords.has("leviathan"):
		_victory_shown = true
		phase = "title"
		if hud: hud.visible = false
		port_ui.close()
		_clear_sea_actors()
		Audio.play_bgm("bgm_ending")   # #80: 厳かなエンディングBGM
		Audio.ambient_enabled = false   # #253: エンディングでは鳴らさない
		GameState.mark_cleared()       # #209: ボスラッシュを解放
		title.show_victory()

# ---------------- 漁 ----------------
func _update_fishing(delta: float) -> void:
	var nearest = null
	var best := 120.0
	for fs in fish_schools:
		if not is_instance_valid(fs) or fs.depleted():
			continue
		var d: float = player.global_position.distance_to(fs.global_position)
		if d < best:
			best = d
			nearest = fs
	if nearest == null:
		hud.set_prompt("")
		hud.set_fishing_meter(0.0, false)
		_fishing_target = null
		return
	hud.set_prompt("[E]長押し→黄色い帯で離す  (%s)" % Database.fish_def(nearest.fish_id).name)
	if Input.is_action_just_pressed("interact"):
		_fishing_target = nearest
		_fishing_phase = 0.0
		_fishing_value = 0.0
		# #232再: 当たりの位置が固定だと作業になるので、漁のたびに帯の位置を抽選する。
		# 端すぎると狙えないので、帯全体が 0.06〜0.94 に収まる範囲で左寄り〜右寄りを取る。
		_fishing_band = randf_range(0.06, 0.94 - FISHING_BAND_W)
	if Input.is_action_pressed("interact") and is_instance_valid(_fishing_target):
		_fishing_phase += delta * 1.2   # #232再3: 往復速度を1.2へ
		_fishing_value = (sin(_fishing_phase * TAU - PI * 0.5) + 1.0) * 0.5
		hud.set_fishing_meter(_fishing_value, true, _fishing_band)
	elif Input.is_action_just_released("interact") and is_instance_valid(_fishing_target):
		var bonus := _fishing_in_band()
		# #232再8: 大漁(帯当たり)は獲得2尾でも群れの残り数は1尾しか減らさない
		var caught: Array = _fishing_target.catch_fish(2 if bonus else 1, 1)
		for got in caught:
			if not GameState.add_cargo(str(got)):
				break
		if bonus and not caught.is_empty():
			hud.show_catch_bonus("大漁! 獲得量2倍")   # #232再4: 漁ゲージのあった位置に出す
		hud.set_fishing_meter(0.0, false)
		_fishing_target = null
	else:
		hud.set_fishing_meter(0.0, false)

# ---------------- スポーン ----------------
func _ring_pos(rmin: float, rmax: float) -> Vector2:
	var ang := randf() * TAU
	return player.global_position + Vector2(cos(ang), sin(ang)) * randf_range(rmin * K, rmax * K)

func _update_spawns(delta: float) -> void:
	fish_schools = fish_schools.filter(func(f): return is_instance_valid(f) and not f.depleted())
	enemies = enemies.filter(func(e): return is_instance_valid(e))
	relics_world = relics_world.filter(func(r): return is_instance_valid(r))
	flotsam_world = flotsam_world.filter(func(x): return is_instance_valid(x))   # #267
	obstacles = obstacles.filter(func(o): return is_instance_valid(o))
	for fs in fish_schools.duplicate():
		if player.global_position.distance_to(fs.global_position) > 320 * K:
			fs.queue_free()
	for r in relics_world.duplicate():
		if player.global_position.distance_to(r.global_position) > 360 * K:
			r.queue_free()
	for x in flotsam_world.duplicate():   # #267
		if player.global_position.distance_to(x.global_position) > 360 * K:
			x.queue_free()
	# #193: 障害物も遠く離れたら片付ける(数を保ちつつ処理を軽く)
	for o in obstacles.duplicate():
		if player.global_position.distance_to(o.global_position) > 380 * K:
			o.queue_free()
	# #69他再修正: 主以外の敵は遠く離れたらデスポーンして枠を空ける(#67/#166: 主・取り巻き・海賊王は免除)
	for e in enemies.duplicate():
		if is_instance_valid(e) and e.kind != "lord" and not e.is_escort and not (e.kind == "pirate" and e.id == "king") and player.global_position.distance_to(e.global_position) > 400 * K:
			e.queue_free()
	spawn_timer -= delta
	if spawn_timer > 0:
		return
	spawn_timer = 1.5
	if _boss_rush:
		# #209: ボスラッシュは流氷だけの海。魚群・遺産・通常の敵は出さない
		for i in 3:
			if obstacles.size() >= _obstacle_max():
				break
			_spawn_obstacle()
		return
	_try_spawn_lord()   # #67: 未討伐の主は全て海域に出現している(各主ごとに存在チェック)
	if fish_schools.size() < MAX_FISH:
		_spawn_fish()
	# #69他再修正/#67: 上限は主・取り巻きを除いた通常敵で数える
	var regular := 0
	for e in enemies:
		if is_instance_valid(e) and e.kind != "lord" and not e.is_escort:
			regular += 1
	if regular < MAX_ENEMIES:
		_spawn_enemy()
	if relics_world.size() < 2 and randf() < 0.12:
		_spawn_relic()
	# #267再: 漂流者・漂流貨物のレアスポーン(遺産よりさらに珍しい)。出現率を下げてほしいとの要望で0.035→0.015
	if not _boss_rush and flotsam_world.size() < 1 and randf() < 0.015:
		_spawn_flotsam()
	# #193: 障害物は地形に近いので、1tickに複数出して早めに規定数まで満たす
	for i in 3:
		if obstacles.size() >= _obstacle_max():
			break
		_spawn_obstacle()

func _spawn_fish() -> void:
	var isle: Dictionary = Database.island(GameState.current_island)
	var pool: Array = isle.spawn.duplicate()
	if randf() < 0.08:
		pool.append("grouper")
	var id: String = pool[randi() % pool.size()]
	# #53: 島の領域内(入港圏+余白)には魚群を出さない
	var pos := _ring_pos(40, 160)
	for attempt in 6:
		var ok := _clear_of_obstacles(pos)   # #193再2: 障害物の上には湧かせない
		if ok:
			for isle_node in islands:
				if pos.distance_to(isle_node.global_position) < 340.0:
					ok = false
					break
		if ok:
			break
		pos = _ring_pos(40, 160)
	if not _clear_of_obstacles(pos):
		return
	for isle_node in islands:
		if pos.distance_to(isle_node.global_position) < 340.0:
			return   # 6回試して島の上なら今回は見送り
	var fs := Node2D.new()
	fs.set_script(FishSchoolScript)
	fs.setup(id, randi_range(3, 7))
	add_child(fs)
	fs.global_position = pos
	fish_schools.append(fs)

func _spawn_enemy() -> void:
	# #25: 島の近く(入港圏の外側まで)は戦闘系の出現を大幅に抑え、漁メインの安全圏にする
	var near_island := false
	for isle_node in islands:
		if player.global_position.distance_to(isle_node.global_position) < 1500.0:
			near_island = true
			break
	if near_island and randf() < 0.75:
		return
	var roll := randf()
	var kind := "mob"
	var id := ""
	var isle := GameState.current_island
	# 海賊12%(#1,#10)、戦闘モブ26%(#3)、海賊王レア(#73)、残りは静かな海
	if roll < 0.12:
		kind = "pirate"
		# #190: 島が5つになったので island index → 海賊の格 を明示表で対応させる
		id = _sea_pirate_top(isle)
		# #197: 先の島ほど、海賊が2〜3隻の船団を組んで現れる(単独のこともある)
		var pos_p := _ring_pos(70, 150)
		for pid in _pirate_group(id, isle):
			# #197再2: 海賊船同士の距離を少し開ける
			_make_enemy("pirate", pid, pos_p + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(170.0, 330.0))
		return
	elif roll < 0.38:
		kind = "mob"
		id = Database.pick_mob(isle)   # #38: 島tierごとの出現割合
	elif roll < 0.50:
		# #73再: 海賊王。島の周り以外の全海域で出現。先の島ほど出やすい(始0.02/潮0.04/嵐0.08/果0.12)。同時1体
		var king_rate: float = [0.02, 0.04, 0.06, 0.08, 0.12][Database.tier_of(isle)]   # #190: 月下の島ぶんを追加。#248: indexではなくtierで引く
		if not near_island and not _king_alive() and randf() < king_rate:
			# #197再3: 海賊王は必ず随伴艦1〜3隻を伴って現れる
			var kpos := _ring_pos(70, 150)
			var king := _make_enemy("pirate", "king", kpos)
			var escort_ids := _king_group(isle)
			for i in escort_ids.size():
				var e := _make_enemy("pirate", str(escort_ids[i]), kpos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(200.0, 360.0))
				e.is_escort = true   # 海賊王と一緒に行動させる(上限・デスポーン免除)
				king.escorts.append(e)
			GameState.notice.emit("海賊王の船団が現れた!")
			return
	if id == "":
		return
	# #71: マーマン等は必ず群れで出現
	var grp := int(Database.combat_mobs.get(id, {}).get("group", 1)) if kind == "mob" else 1
	var pos := _ring_pos(70, 150)
	for gi in grp:
		_make_enemy(kind, id, pos + Vector2.RIGHT.rotated(randf() * TAU) * (0.0 if gi == 0 else randf_range(70.0, 160.0)))

# #197: 通常の海賊船団の編成。
# 少なくとも1隻はその海域の海賊。残りはその海域の海賊か、より弱い海賊からランダム。
const PIRATE_RANKS := ["raider", "corsair", "dread"]

# #248: その海域(島tier)に出る海賊の格。indexで引くと島5〜8がずれる
func _sea_pirate_top(isle: int) -> String:
	return ["raider", "corsair", "dread", "dread", "dread"][Database.tier_of(isle)]

func _pirate_group(top_id: String, isle: int) -> Array:
	var out: Array = [top_id]
	# #197再: 単独出現の確率を上げ、船団を組む確率を下げる
	var fleet_rate: float = [0.0, 0.12, 0.18, 0.24, 0.30][Database.tier_of(isle)]
	if randf() >= fleet_rate:
		return out                      # 単独で現れる
	var tier := Database.tier_of(isle)
	var extra := 1 if randf() < (0.65 - 0.1 * float(tier)) else 2   # 先の海域ほど3隻になりやすい
	var top := PIRATE_RANKS.find(top_id)
	for i in extra:
		out.append(str(PIRATE_RANKS[randi() % (maxi(top, 0) + 1)]))
	return out

# #197再3: 海賊王の随伴艦。必ず1〜3隻を伴い、うち1隻は必ずその海域の海賊。
# 残りはその海域の海賊か、より格下の海賊からランダム。
func _king_group(isle: int) -> Array:
	var top_id := _sea_pirate_top(isle)
	var top := maxi(PIRATE_RANKS.find(top_id), 0)
	var out: Array = [top_id]           # 1隻目は必ずその海域の格
	for i in randi_range(0, 2):
		out.append(str(PIRATE_RANKS[randi() % (top + 1)]))
	return out

# #67再: 未討伐の主は全て、それぞれの定位置の沖に同時出現させる
func _try_spawn_lord() -> void:
	var isle := GameState.current_island
	var lords: Array = Database.island(isle).get("lords", [])
	for id in lords:
		if GameState.claimed_lords.has(id) or GameState.defeated_lords.has(id):
			continue
		if _lord_id_alive(id):
			continue
		if bool(Database.lords.get(id, {}).get("pair", false)):
			var base := _lord_spawn_pos(id)
			var a := _make_enemy("lord", id, base + Vector2(50, 0))
			var b := _make_enemy("lord", id, base + Vector2(-50, 0))
			a.pair_partner = b
			b.pair_partner = a
			var esc := _spawn_escorts(base, id)
			a.escorts = esc
			b.escorts = esc
		else:
			var lpos := _lord_spawn_pos(id)
			var lord := _make_enemy("lord", id, lpos)
			lord.escorts = _spawn_escorts(lpos, id)

func _lord_id_alive(id: String) -> bool:
	for e in enemies:
		if not is_instance_valid(e) or e.kind != "lord":
			continue
		if e.id == id:
			return true
		# #239再4: 分裂した個体(夜の帝王→中型→小型)が生きている間は、
		# 元の主もまだ討伐されていない扱いにする。これが無いと
		# 「本体が消えた=未出現」と見なされ、分裂中に2体目が湧いてしまう。
		if str(e.get("split_root")) == id:
			return true
	return false

func _king_alive() -> bool:
	for e in enemies:
		if is_instance_valid(e) and e.kind == "pirate" and e.id == "king":
			return true
	return false

# #62: 主の取り巻き。戦闘モブ2体を主の周囲に出現させる(#67: 上限・デスポーン免除)
# #119再: レヴィアタンはザッハーク/ティアマット/ダゴンから2種。#120: マーマンは取り巻きにしない
# #209再: tier で取り巻きの選定元(島index)を指定できる。既定は現在の海域。
# ボスラッシュでは「そのボスが本来出現する島」の海域から選ぶ。
func _spawn_escorts(center: Vector2, lord_id: String = "", tier: int = -1) -> Array:
	if tier < 0:
		tier = GameState.current_island
	var out: Array = []
	var ids: Array = []
	if bool(Database.lords.get(lord_id, {}).get("no_escort", false)):
		return out   # #187: 幽霊船など取り巻きを持たない主
	if lord_id == "leviathan":
		ids = ["zahhak", "tiamat", "dagon"]   # #119再: 3種を1匹ずつ
	elif lord_id == "aspidochelone" or lord_id == "legion":
		ids = ["starfish", "zaratan"]   # #190再: 月下の主の取り巻きはオニヒトデ1体+ザラタン1体
	elif lord_id == "hydra" or lord_id == "quetzal" or lord_id == "kraken_lord" or lord_id == "griffon":
		# #141再3: その海域には出ない強敵を取り巻きにする(ザッハーク1体+ティアマット1体)
		ids = ["zahhak", "tiamat"]
	elif lord_id == "undine":
		ids = ["mermaid", "mermaid"]   # #246: ウンディーネはマーメイド2体で固定
	elif lord_id == "siren":
		ids = ["lamia", "lamia"]       # #246: セイレーンはラミア2体で固定
	else:
		for i in 2:
			var mid: String = Database.pick_mob(tier)
			var guard := 0
			# #120: マーマン / #239再4: ゾンビウオ は取り巻きにしない(群れで出る敵なので)
			while (mid == "merman" or mid == "zombie_fish") and guard < 8:
				mid = Database.pick_mob(tier)
				guard += 1
			if mid == "merman":
				mid = "wyrm"
			ids.append(mid)
	# #62再: 取り巻きは主の前方(プレイヤー側)に盾として配置
	var to_p: Vector2 = (player.global_position - center).normalized() if is_instance_valid(player) else Vector2.DOWN
	var perp := to_p.rotated(PI / 2)
	var i := 0
	for mid in ids:
		var side := float(i) - float(ids.size() - 1) / 2.0   # #119再: 取り巻きを中央対称に配置(2体でも3体でも均等に)
		var off := to_p * randf_range(120.0, 190.0) + perp * side * randf_range(80.0, 120.0)
		var e := _make_enemy("mob", mid, center + off)
		e.is_escort = true
		out.append(e)
		i += 1
	return out

func _lord_alive() -> bool:
	for e in enemies:
		if is_instance_valid(e) and e.kind == "lord":
			return true
	return false

# 主は島から離れた決まった方角の沖(#15,#18)。北=-Y。#67再: 距離を元に戻す
func _lord_spawn_pos(id: String) -> Vector2:
	var ipos := island_pos(GameState.current_island)
	var deg: float = float(Database.lords.get(id, {}).get("dir", 0)) + randf_range(-15.0, 15.0)
	var a := deg_to_rad(deg)
	# #155再: spawn_dist_mult で出現沖合の距離を延長(レヴィアタンは少し遠く)
	var dmult: float = float(Database.lords.get(id, {}).get("spawn_dist_mult", 1.0))
	return ipos + Vector2(sin(a), -cos(a)) * randf_range(320.0, 430.0) * K * dmult

func _make_enemy(kind: String, id: String, pos: Vector2) -> CharacterBody2D:
	var e := CharacterBody2D.new()
	e.set_script(EnemyScript)
	e.setup(kind, id)
	add_child(e)
	e.global_position = pos
	enemies.append(e)
	return e

# #239: 夜の帝王の分裂。元の主の周囲へ子individualを生み、討伐判定を引き継がせる。
# 生まれた個体は上限・デスポーンの対象外(取り巻き扱い)にして、
# すべて倒すまで討伐にならないようにする。
func spawn_split(src: Node2D, into_id: String, count: int) -> void:
	if into_id == "" or not Database.lords.has(into_id):
		return
	var root: String = str(src.get("split_root"))
	if root == "":
		root = str(src.get("id"))
	for i in count:
		var ang := TAU * float(i) / float(maxi(count, 1)) + randf() * 0.6
		var pos: Vector2 = src.global_position + Vector2(cos(ang), sin(ang)) * 90.0
		var e := _make_enemy("lord", into_id, pos)
		e.split_root = root
		e.is_escort = true          # 上限計数・距離デスポーンの対象外にする
		e._aggro = true

# #193: 島ごとの障害物。始まりの島〜嵐越えの島は岩礁、果ての島は流氷(低速で移動)
func _obstacle_kind() -> String:
	return "ice" if Database.tier_of(GameState.current_island) >= 4 else "reef"   # #239

# 始まりの島の近海は岩礁を少なめに
func _obstacle_max() -> int:
	return [3, 8, 8, 9, 7, 8, 8, 9, 7, 8][clampi(GameState.current_island, 0, 9)]   # #239: 島8つぶん。#248/#251: 寄り道の島2つで10

func _spawn_obstacle() -> void:
	var pos := _ring_pos(85, 200)
	for attempt in 8:
		if _obstacle_spot_ok(pos):
			break
		pos = _ring_pos(85, 200)
	if not _obstacle_spot_ok(pos):
		return
	var o := StaticBody2D.new()
	o.set_script(ObstacleScript)
	o.setup(_obstacle_kind())
	add_child(o)
	o.global_position = pos
	obstacles.append(o)

# #193再2: 障害物の上に重なっていないか(魚群・遺産の湧き位置チェック用)
func _clear_of_obstacles(pos: Vector2, margin := 40.0) -> bool:
	for o in obstacles:
		if is_instance_valid(o):
			var orad: float = float(o.get("radius")) if o.get("radius") != null else 50.0
			if pos.distance_to(o.global_position) < orad + margin:
				return false
	return true

# 島の上・他の障害物の近くには置かない
func _obstacle_spot_ok(pos: Vector2) -> bool:
	for isle_node in islands:
		if pos.distance_to(isle_node.global_position) < 380.0:
			return false
	for o in obstacles:
		if is_instance_valid(o) and pos.distance_to(o.global_position) < 260.0:
			return false
	return true

func _spawn_relic() -> void:
	# #124: 島の領域内には遺産を出さない(魚群#53と同様に島から離す)
	var pos := _ring_pos(60, 180)
	for attempt in 6:
		var ok := _clear_of_obstacles(pos)   # #193再2: 障害物の上には湧かせない
		if ok:
			for isle_node in islands:
				if pos.distance_to(isle_node.global_position) < 340.0:
					ok = false
					break
		if ok:
			break
		pos = _ring_pos(60, 180)
	if not _clear_of_obstacles(pos):
		return
	for isle_node in islands:
		if pos.distance_to(isle_node.global_position) < 340.0:
			return
	var r := Area2D.new()
	r.set_script(RelicScript)
	# #207: 島ごとの価値を引き上げ(潮鳴り1.2 月下1.4 嵐越え1.7 果て2.0倍)。ランダムのぶれは維持
	var relic_mult: float = [1.0, 1.2, 1.4, 1.7, 2.0][Database.tier_of(GameState.current_island)]   # #248: indexではなくtierで引く
	r.setup(int(round(float(randi_range(200, 500) * (Database.tier_of(GameState.current_island) + 1)) * relic_mult)))   # #239
	add_child(r)
	r.global_position = pos
	relics_world.append(r)

# #267: 漂流者・漂流貨物を1つ出す。配置の条件は遺産と同じ(島の上・障害物の上は避ける)
func _spawn_flotsam() -> void:
	var pos := _ring_pos(60, 180)
	for attempt in 6:
		var ok := _clear_of_obstacles(pos)
		if ok:
			for isle_node in islands:
				if pos.distance_to(isle_node.global_position) < 340.0:
					ok = false
					break
		if ok:
			break
		pos = _ring_pos(60, 180)
	if not _clear_of_obstacles(pos):
		return
	for isle_node2 in islands:
		if pos.distance_to(isle_node2.global_position) < 340.0:
			return
	var f := Area2D.new()
	f.set_script(FlotsamScript)
	f.setup("castaway" if randf() < 0.5 else "cargo")
	add_child(f)
	f.global_position = pos
	flotsam_world.append(f)

# ---------------- ボスラッシュ(#209) ----------------
# 出現順: 主を順に、7番目に海賊王(取り巻きは海賊(大)1+海賊(中)1で固定)
# #209再9: 新しい主(#239)を加え、出現順もレビュアー指定へ入れ替え。
# ①〜⑩を倒すと最大装甲の5%、⑪〜⑯を倒すと10%回復する(BR_HEAL_BIG_FROM)。
const BOSS_RUSH_ORDER := [
	{"kind": "lord", "id": "sawshark"},        # ①
	{"kind": "lord", "id": "dumbo"},           # ②
	{"kind": "lord", "id": "whale"},           # ③
	{"kind": "lord", "id": "walrus"},          # ④(番い2体)
	{"kind": "lord", "id": "aspidochelone"},   # ⑤
	{"kind": "lord", "id": "undine"},          # ⑥
	{"kind": "lord", "id": "night_emperor"},   # ⑦(分裂)
	{"kind": "lord", "id": "legion"},          # ⑧
	{"kind": "lord", "id": "siren"},           # ⑨
	{"kind": "lord", "id": "wraith"},          # ⑩
	{"kind": "pirate", "id": "king", "escorts": ["dread", "dread", "corsair"]},   # ⑪ #209再10: 大×2・中×1
	{"kind": "lord", "id": "kraken_lord"},     # ⑫
	{"kind": "lord", "id": "hydra"},           # ⑬
	{"kind": "lord", "id": "griffon"},         # ⑭
	{"kind": "lord", "id": "quetzal"},         # ⑮
	{"kind": "lord", "id": "ghost"},           # ⑯
	{"kind": "lord", "id": "leviathan"},       # ⑰
]
# ⑪(index 10)以降は回復量が10%になる
const BR_HEAL_BIG_FROM := 10
# 島から遠く離れた海域(島の存在しないステージ)
const BR_ARENA := Vector2(0.0, 120000.0)

func _on_boss_rush() -> void:
	if not GameState.load_game():
		GameState.notice.emit("セーブデータが見つかりません")
		return
	_boss_rush = true
	GameState.boss_rush = true
	GameState.mark_boss_rush_played()   # #265再5: 実績「真の海の王者」の表示解禁用
	_victory_shown = false
	_returning = false
	_br_index = 0
	_br_boss = null
	_br_active = false
	_br_wait = 0.0
	_br_won = false
	# 討伐済みの記録は持ち込まない(勝利判定が即座に走らないように)
	GameState.defeated_lords.clear()
	GameState.claimed_lords.clear()
	GameState.current_island = 4   # #248: 果ての島そのものを指す(島の追加で末尾がずれないように)
	title.visible = false
	port_ui.close()
	phase = "sea"
	GameState.set_sail()      # 装甲を満タンにして出撃(以後は回復しない)
	_clear_sea_actors()
	player.global_position = BR_ARENA
	player.rotation = PI
	player.velocity = Vector2.ZERO
	player.control_enabled = true
	player.rebuild_visual()
	camera.global_position = player.global_position
	hud.visible = true
	hud.rebuild_weapons()
	hud.update_bars()
	hud.set_location("Boss Rush")
	Audio.play_bgm("bgm_boss")
	Audio.ambient_enabled = true   # #253: ボスラッシュも海の上
	_boss_bgm_on = "bgm_boss"
	Audio.play("sfx_lord_roar", -2.0)   # #79再: ボスラッシュ開始時も主のBGMなので鳴らす
	slot_cooldowns = [0.0, 0.0, 0.0, 0.0]
	_rapid_t = 0.0
	_barrier_t = 0.0
	_reset_ammo()
	GameState.formation_slot = 0
	_spawn_escorts_fleet()
	if hud and hud.has_method("build_formation_bar"):
		hud.build_formation_bar(_set_formation_slot, _use_skill)   # #224
	_apply_weather("blizzard")   # 果ての島近海を模した海
	_br_spawn_next()

# 次のボスを少しだけ離れた位置に出す
func _br_spawn_next() -> void:
	if _br_index >= BOSS_RUSH_ORDER.size():
		_br_finish()
		return
	var spec: Dictionary = BOSS_RUSH_ORDER[_br_index]
	var ang := randf() * TAU
	var pos: Vector2 = player.global_position + Vector2(cos(ang), sin(ang)) * randf_range(700.0, 950.0)
	var boss := _make_enemy(str(spec.kind), str(spec.id), pos)
	boss._aggro = true
	# #209再4: 番いの主(ギガントセイウチ)は本編と同じく2体出し、両方倒すまで撃破にしない
	_br_boss2 = null
	_br_pair = str(spec.kind) == "lord" and bool(Database.lords.get(str(spec.id), {}).get("pair", false))
	if _br_pair:
		boss.global_position = pos + Vector2(60, 0)
		var mate := _make_enemy(str(spec.kind), str(spec.id), pos + Vector2(-60, 0))
		mate._aggro = true
		boss.pair_partner = mate
		mate.pair_partner = boss
		_br_boss2 = mate
	if spec.has("escorts"):
		for eid in spec.escorts:          # 海賊王は取り巻き固定
			var e := _make_enemy("pirate", str(eid), pos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(120.0, 200.0))
			e.is_escort = true
			boss.escorts.append(e)
	else:
		# #209再: 取り巻きは、そのボスが本来出現する島の海域のモブから選ぶ
		var home: int = int(Database.lords[str(spec.id)].island)
		boss.escorts = _spawn_escorts(pos, str(spec.id), home)
		if _br_pair and is_instance_valid(_br_boss2):
			_br_boss2.escorts = boss.escorts   # 取り巻きは番いで共有
	_br_boss = boss
	# #209再10: 分裂する主(夜の帝王)は、本体が消えても分裂体が残っている間は未撃破
	_br_split_root = str(spec.id) if Database.lords.get(str(spec.id), {}).has("split") else ""
	_br_active = true
	var nm: String = Database.lords[str(spec.id)].name if str(spec.kind) == "lord" else Database.pirates[str(spec.id)].name
	if _br_pair:
		nm += "(つがい2体)"
	hud.show_big_message("%d / %d  %s" % [_br_index + 1, BOSS_RUSH_ORDER.size(), nm], 2.0)

# #209再10: 分裂した本体の生き残り(分裂体)がまだ海上にいるか
func _br_split_alive() -> bool:
	if _br_split_root == "":
		return false
	for e in enemies:
		if is_instance_valid(e) and str(e.get("split_root")) == _br_split_root:
			return true
	return false

# ボス撃破の監視(取り巻きは倒さなくてもボスを倒せば消える)
func _br_update(delta: float) -> void:
	if _br_wait > 0.0:
		_br_wait -= delta
		if _br_wait <= 0.0:
			_br_spawn_next()
		return
	# 解放済みのNode参照は `!= null` が偽になるため、_br_active で「出現中」を管理する
	# #209再4: 番いの場合は2体とも倒れるまで撃破としない
	var boss_gone: bool = not is_instance_valid(_br_boss) and not _br_split_alive()
	var mate_gone: bool = not _br_pair or not is_instance_valid(_br_boss2)
	if _br_active and boss_gone and mate_gone:
		_br_active = false
		_br_pair = false
		_br_boss = null
		_br_boss2 = null
		_br_split_root = ""
		for e in enemies.duplicate():     # 残った取り巻きを消す
			if is_instance_valid(e):
				e.queue_free()
		enemies.clear()
		_br_index += 1
		_br_wait = 1.6
		# #209再2: ボスを1体倒すごとに船団の全艦が最大装甲の5%回復する
		if _br_index < BOSS_RUSH_ORDER.size():
			# #209再6: ⑦〜⑩のボスは10%、①〜⑥は5%回復(_br_index=倒したボスの通し番号)
			var heal_pct: float = 0.10 if _br_index >= BR_HEAL_BIG_FROM else 0.05   # #209再9
			GameState.heal_fleet_percent(heal_pct)
			GameState.notice.emit("船団の装甲が回復した(最大値の%d%%)" % int(heal_pct * 100.0))
		else:
			# #284: レヴィアタン討伐の瞬間から旗艦を無敵にする(制覇画面へ進むまでの間、大破扱いにしない)
			_br_won = true

func _br_finish() -> void:
	if _victory_shown:
		return
	_victory_shown = true
	phase = "title"
	if hud: hud.visible = false
	_clear_sea_actors()
	Audio.play_bgm("bgm_ending")
	Audio.ambient_enabled = false   # #253: エンディングでは鳴らさない
	GameState.mark_boss_rush_cleared()   # #209再2: タイトルに王冠を出す
	title.show_victory(true)   # #209: 夜の背景+専用メッセージ

func _br_fail() -> void:
	if _returning or _br_won:   # #284: レヴィアタン討伐後は旗艦無敵につき大破処理を行わない
		return
	_returning = true
	GameState.docking_locked = true
	if player:
		player.control_enabled = false
	hud.show_big_message("旗艦が大破! Boss Rush 終了", 3.0)
	await get_tree().create_timer(3.2).timeout
	_boss_rush = false
	GameState.boss_rush = false
	phase = "title"
	if hud: hud.visible = false
	_clear_sea_actors()
	Audio.play_bgm("bgm_port")
	Audio.ambient_enabled = false   # #253: タイトルへ戻るので止める
	title.show_title()

# ---------------- 船団(#196) ----------------
# 陣形ごとの相対位置(旗艦の向きを基準にしたローカル座標。+Y=後方)
# #196再: 旗艦と僚艦の距離を短くして、船団がまとまって見えるようにする
const FORMATION_OFFSETS := {
	"line":    [Vector2(-95, 15), Vector2(95, 15), Vector2(-185, 35), Vector2(185, 35)],      # 単横陣
	"column":  [Vector2(0, 95), Vector2(0, 185), Vector2(0, 275), Vector2(0, 365)],           # 単縦陣
	"vee":     [Vector2(-80, 80), Vector2(80, 80), Vector2(-155, 160), Vector2(155, 160)],    # 鋒矢陣(後方へ広がる)
	"inv_vee": [Vector2(-45, -95), Vector2(45, -95), Vector2(-90, -190), Vector2(90, -190)],  # 鶴翼陣(#196再2: 角度を急に)
	"echelon": [Vector2(-80, 75), Vector2(-160, 150), Vector2(-240, 225), Vector2(-320, 300)],# 斜線陣
	# #196再8: 輪形陣。旗艦を中心に僚艦が等間隔で取り囲む
	"ring":    [Vector2(0, -115), Vector2(115, 0), Vector2(0, 115), Vector2(-115, 0)],
}

# #224: 陣形ごとのスキル定義は GameState.FORMATION_SKILLS に集約(港UIからも参照するため)
const CHARGE_TIME := 1.2   # 突撃の持続秒(#224再3: 1.2秒へ戻す)
const RAPID_TIME := 5.0    # #224再2: 速射態勢の持続秒
const BARRIER_TIME := 3.0  # #224再2: 防御弾幕の持続秒
const BARRIER_R := 130.0   # #224再2: 迎撃半径(輪形陣の輪の内側)
const ENCIRCLE_STAGGER := 0.5   # #224再2: 包囲射撃の時間差

var _rapid_t: float = 0.0     # #224再2: 速射態勢の残り(弾倉を減らさない)
var _barrier_t: float = 0.0   # #224再2: 防御弾幕の残り

func _current_skill() -> Dictionary:
	return GameState.FORMATION_SKILLS.get(_current_formation(), GameState.FORMATION_SKILLS["line"])

# スキル発動(スキルボタン or 5キー)。旗艦と僚艦がそろって発動する
func _use_skill() -> void:
	if phase != "sea" or _skill_cd > 0.0:
		return
	var sk: Dictionary = _current_skill()
	# #265: 実績「突撃!」= 5隻すべてが超硬タングステン衝角の状態で単縦陣の突撃を発動
	if str(sk.kind) == "charge" and GameState.fleet.size() >= GameState.max_fleet_cap():
		var all_tungsten := true
		for e0 in GameState.fleet:
			if str(e0.get("ram", "none")) != "tungsten":
				all_tungsten = false
				break
		if all_tungsten:
			GameState.charge_all_tungsten = true
			GameState.check_achievements()
	match str(sk.kind):
		"volley":
			# #224再: 非ロックオン時も発動できる。ロック中はロック対象へ、
			# 非ロック時は各艦がそれぞれの前方へ撃つ(start_volley に null を渡す)
			var tgt: Node2D = lock_target if (lock_target != null and is_instance_valid(lock_target)) else null
			player.start_volley(tgt)
			for e in escorts:
				if is_instance_valid(e):
					e.start_volley(tgt)
		"encircle":
			_start_encircle()   # #224再2: 鶴翼陣。時間差斉射+回避無効
		"rapid":
			_rapid_t = RAPID_TIME   # #224再2: 斜線陣
		"barrier":
			_barrier_t = BARRIER_TIME   # #224再2: 輪形陣
		_:
			# charge / wedge。wedge は旗艦の衝角ダメージ1.5倍+押し込み
			player.wedge_mult = 1.5 if str(sk.kind) == "wedge" else 1.0
			player.charge_t = CHARGE_TIME
			player._charge_hit.clear()
			for e2 in escorts:
				if is_instance_valid(e2):
					e2.charge_t = CHARGE_TIME
					e2._charge_hit.clear()
	_skill_cd = float(sk.cd)
	_skill_cd_max = float(sk.cd)
	GameState.notice.emit("%s!" % str(sk.name))
	Audio.play("sfx_skill", -5.0, 1.0)   # #224再3: スキル発動の専用効果音
	if str(sk.kind) == "volley" or str(sk.kind) == "encircle":
		zoom_punch(1.1, 0.2)   # #278(提案5): 一斉射撃の発動時に0.2秒だけ寄る

# クールダウンを進め、HUDへ進捗を渡す
# #224再2: 鶴翼陣「包囲射撃」。ロック対象へ各艦が0.5秒間隔で斉射し、
# その間だけ対象の回避(dodge)を無効にする。ロックしていなければ通常の一斉射撃。
func _start_encircle() -> void:
	var tgt: Node2D = lock_target if (lock_target != null and is_instance_valid(lock_target)) else null
	if tgt != null and tgt.has_method("suppress_dodge"):
		# 全艦が撃ち終わるまで(艦数×間隔+余裕)回避を無効化する
		tgt.suppress_dodge(ENCIRCLE_STAGGER * float(escorts.size() + 1) + 1.5)
	player.start_volley(tgt)
	var i := 1
	for e in escorts:
		if not is_instance_valid(e):
			continue
		var ship: Node = e
		var wait := ENCIRCLE_STAGGER * float(i)
		i += 1
		get_tree().create_timer(wait).timeout.connect(func():
			if is_instance_valid(ship) and phase == "sea":
				ship.start_volley(tgt if (tgt != null and is_instance_valid(tgt)) else null))

# #224再2: 防御弾幕。輪の内側に入った敵弾を消す
func _tick_barrier(delta: float) -> void:
	if _barrier_t <= 0.0:
		return
	_barrier_t = maxf(_barrier_t - delta, 0.0)
	if not is_instance_valid(player):
		return
	for p in get_tree().get_nodes_in_group("enemy_shot"):
		if not is_instance_valid(p):
			continue
		if player.global_position.distance_to(p.global_position) <= BARRIER_R:
			p.queue_free()

func _tick_skill(delta: float) -> void:
	if _rapid_t > 0.0:
		_rapid_t = maxf(_rapid_t - delta, 0.0)
	_tick_barrier(delta)
	if _skill_cd > 0.0:
		_skill_cd = maxf(_skill_cd - delta, 0.0)
	if hud and hud.has_method("set_skill_state"):
		var ready_now: bool = _skill_cd <= 0.0
		var prog: float = 1.0 if ready_now else 1.0 - (_skill_cd / maxf(_skill_cd_max, 0.001))
		hud.set_skill_state(str(_current_skill().name), prog, ready_now)

func _current_formation() -> String:
	var i := clampi(GameState.formation_slot, 0, 3)
	return str(GameState.formations[i])

# 出港時に僚艦(副船長を乗せた艦)を生成する
func _spawn_escorts_fleet() -> void:
	_clear_escorts()
	for i in range(1, GameState.fleet.size()):
		if not GameState.can_sail(i):
			continue
		var e := CharacterBody2D.new()
		e.set_script(EscortScript)
		e.setup(i)
		add_child(e)
		e.detached.connect(_on_escort_detached)
		escorts.append(e)
	_apply_formation()
	# 生成直後は陣形位置へ即座に配置(出港時に一列に固まらないように)
	for e2 in escorts:
		if is_instance_valid(e2):
			e2.global_position = player.global_position + e2.slot_offset.rotated(player.rotation)

func _clear_escorts() -> void:
	for e in escorts:
		if is_instance_valid(e):
			e.queue_free()
	escorts.clear()

# 陣形スロットを僚艦へ割り当てる
func _apply_formation() -> void:
	var offs: Array = FORMATION_OFFSETS.get(_current_formation(), FORMATION_OFFSETS["line"])
	var n := 0
	for e in escorts:
		if is_instance_valid(e):
			e.slot_offset = offs[mini(n, offs.size() - 1)]
			n += 1

func _on_escort_detached(idx: int) -> void:
	GameState.notice.emit("%sは離脱した!" % GameState.fleet_label(idx))
	hud.show_big_message("%sは離脱した!" % GameState.fleet_label(idx), 2.0)
	var lost := GameState.detach_lose_crew(idx)
	if lost != "":
		GameState.notice.emit("%s が海に消えた…" % lost)
	escorts = escorts.filter(func(x): return is_instance_valid(x))

# 1〜4キー/画面ボタンで陣形を切り替える
func _set_formation_slot(slot: int) -> void:
	if phase != "sea":
		return
	# #224: 潮鳴り到達前、または旗艦1隻だけなら1〜4キー/ボタンで変更しない。
	if not GameState.visited_islands.has(1) or GameState.fleet.size() <= 1:
		GameState.formation_slot = 0
		return
	GameState.formation_slot = clampi(slot, 0, 3)
	_apply_formation()
	var nm: String = PortUIScript.FORMATION_NAMES.get(_current_formation(), "?")
	GameState.notice.emit("陣形%d: %s" % [GameState.formation_slot + 1, nm])
	if hud and hud.has_method("set_formation"):
		hud.set_formation(GameState.formation_slot)

# #196: 射線上に味方(旗艦・僚艦)がいると撃てない(魚雷は射線を無視)
# #257: 弾は旗艦の中心だけでなく左右の舷からも撃てる。射線が通る原点を返す。
#   砲は船の中心線ではなく舷側に並ぶので、僚艦のすぐ脇をかすめるだけの
#   理不尽な遮断が減り、僚艦が正面に重なる「盾」としての遮断は残る。
const BROADSIDE_OFFSET := 30.0

# その原点から撃ったとき、射線を遮っている僚艦を返す(遮っていなければ null)
func _line_blocker_from(origin: Vector2, dir: Vector2, dist: float) -> Node2D:
	for m in escorts:
		if not is_instance_valid(m):
			continue
		var rel: Vector2 = m.global_position - origin
		var along := rel.dot(dir)
		if along <= 0.0 or along > dist:
			continue
		if absf(rel.cross(dir)) < 46.0:
			return m
	return null

# #256: 「撃てない」を伝えるトーストの間隔(連打で溢れないように)
# #258再: 停泊中の燃料消費(航行中を1としたときの割合)
const IDLE_FUEL_RATE := 0.15

const LOS_TOAST_CD := 2.0
var _los_toast_t: float = 0.0
var _los_overlay: Node2D = null

func _notify_los_blocked(weapon_name: String) -> void:
	if _los_toast_t > 0.0:
		return
	_los_toast_t = LOS_TOAST_CD
	GameState.notice.emit("僚艦が射線上! (%s)" % weapon_name)

# #256: 遮断の可視化。狙っている方向が塞がっていれば、原因の僚艦と射線を赤で示す
func _update_los_overlay() -> void:
	if _los_overlay == null or not is_instance_valid(player):
		return
	if phase != "sea" or GameState.docking_locked:
		_los_overlay.set_state(null, Vector2.ZERO, Vector2.ZERO, false)
		return
	# 装備しているエイム武器のうち最も射程の長いものを基準にする
	var reach := 0.0
	for i in mini(4, GameState.weapons.size()):
		var wid: String = GameState.weapons[i]
		if wid == "" or not Database.weapons.has(wid):
			continue
		var w: Dictionary = Database.weapons[wid]
		if str(w.kind) == "aim":
			reach = maxf(reach, float(w.range) * K * 1.2)
	if reach <= 0.0:
		_los_overlay.set_state(null, player.global_position, get_global_mouse_position(), true)
		return   # #256再: エイム武器が無くても照準そのものは出す
	var m := get_global_mouse_position()
	var dir := (m - player.global_position).normalized()
	var blocker: Node2D = null
	if _clear_muzzle(dir, reach) == null:
		blocker = _line_blocker_from(player.global_position, dir, reach)
	_los_overlay.set_state(blocker, player.global_position, m)

# #257: 中心・左舷・右舷のうち射線が通る発射原点を返す。どこからも通らなければ null。
func _clear_muzzle(dir: Vector2, dist: float) -> Variant:
	var side := dir.orthogonal()
	for off in [0.0, BROADSIDE_OFFSET, -BROADSIDE_OFFSET]:
		var o: Vector2 = player.global_position + side * off
		if _line_blocker_from(o, dir, dist) == null:
			return o
	return null

# 中心から見て射線を遮っている僚艦(表示用。どの舷からも通らないときだけ意味を持つ)
func _line_blocked_for_player(dir: Vector2, dist: float) -> bool:
	return _clear_muzzle(dir, dist) == null

# ---------------- 武器 ----------------
func _reset_ammo() -> void:
	slot_ammo = [0, 0, 0, 0]
	for i in mini(4, GameState.weapons.size()):
		var wid: String = GameState.weapons[i]
		if wid != "" and Database.weapons.has(wid):
			slot_ammo[i] = int(Database.weapons[wid].mag)

# 発射後の弾倉消費(#27)。弾切れでリロード時間をクールダウンに載せ、弾を補充。
func _consume_ammo(i: int, w: Dictionary) -> void:
	if _rapid_t > 0.0:
		slot_cooldowns[i] = float(w.cooldown)   # #224再2: 速射態勢=弾倉を減らさずリロードもしない
		return
	slot_ammo[i] = int(slot_ammo[i]) - 1
	if slot_ammo[i] <= 0:
		slot_cooldowns[i] = float(w.reload) * GameState.formation_passive("reload") * GameState.badge_mult("reload")   # #224再2: 単横陣
		slot_ammo[i] = int(w.mag)
		GameState.notice.emit("%s リロード中…" % w.name)
	else:
		slot_cooldowns[i] = float(w.cooldown)

# #196再: 画面のUI(陣形ボタンなど)の上にカーソルがあるか
func _pointer_on_ui() -> bool:
	if hud == null:
		return false
	if hud.get("pointer_on_ui") == true:
		return true
	var ui_root = hud.get("_ui_root")
	return ui_root != null and ui_root.get_node_or_null("SharedOverlay") != null

# #251再2: 放射系の持続音を鳴らすべきか。撃つボタンを押している間は、
#   1発ごとのクールダウンに関係なく鳴らし続ける。リロード中は止める。
func _loop_sfx_wanted(pressed: bool) -> String:
	if not pressed:
		return ""
	for i in mini(int(GameState.ship().slots), GameState.weapons.size()):
		var wid: String = GameState.weapons[i]
		if wid == "" or not Database.weapons.has(wid):
			continue
		var w: Dictionary = Database.weapons[wid]
		if not w.has("loop_sfx"):
			continue
		# リロード中(残クールダウンが1発ぶんより長い)は鳴らさない
		if float(slot_cooldowns[i]) > float(w.cooldown) + 0.01:
			continue
		return str(w.loop_sfx)
	return ""

func _update_weapons(delta: float) -> void:
	for i in slot_cooldowns.size():
		if slot_cooldowns[i] > 0:
			slot_cooldowns[i] -= delta
	if GameState.docking_locked or _food_dialog_open:
		Audio.stop_loop_sfx()   # #251再: 撃てない状態では放射音も止める
		return   # #101: 大破/寄港確定後は攻撃不可 / #24再: 食料選択中も撃たない
	var slots := int(GameState.ship().slots)
	if Input.is_action_pressed("fire_primary") and not _pointer_on_ui():   # #196再: 陣形ボタン上では撃たない
		for i in slots:
			var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
			if wid == "" or not Database.weapons.has(wid):
				continue
			var w: Dictionary = Database.weapons[wid]
			if w.kind == "aim" and slot_cooldowns[i] <= 0:
				if _fire_aim(w):
					_consume_ammo(i, w)   # #264: 撃てたときだけ弾を減らす
	if Input.is_action_just_pressed("fire_torpedo"):
		for i in slots:
			var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
			if wid == "" or not Database.weapons.has(wid):
				continue
			var w: Dictionary = Database.weapons[wid]
			if w.kind == "lock" and slot_cooldowns[i] <= 0:
				# #252: 魚雷系はロックオンした敵がいないと撃てない(弾も減らさない)
				if lock_target == null or not is_instance_valid(lock_target):
					GameState.notice.emit("%s: 敵をロックオンしていない" % str(w.name))
					continue
				_fire_torpedo(w)
				_consume_ammo(i, w)
	# #251再2: 放射音の反映。発射したフレームだけで判断すると、連射の合間
	#   (毎フレームのうち大半)で止めてしまい、実質鳴らなくなる。
	#   「押している間ずっと」で判断する。
	var want_loop := _loop_sfx_wanted(Input.is_action_pressed("fire_primary") and not _pointer_on_ui())
	if want_loop != "":
		Audio.play_loop_sfx(want_loop)
	elif Audio.loop_sfx_name() != "":
		Audio.stop_loop_sfx()
	# HUDに残弾を表示(#27)
	var texts: Array = []
	for i in slots:
		var wid2: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
		if wid2 == "" or not Database.weapons.has(wid2):
			texts.append("")
		elif slot_cooldowns[i] > float(Database.weapons[wid2].cooldown) + 0.01:
			texts.append("リロード")
		else:
			texts.append("弾%d" % int(slot_ammo[i]))
	hud.update_ammo(texts)

# クルー効果(#39)を武器威力に反映した複製を返す
func _crewed(w: Dictionary) -> Dictionary:
	var w2 := w.duplicate()
	# #251: 武器が自前のデバフ種別を持つ場合(冷気放射器)は銛の設定で上書きしない
	if not w.has("debuff_kind"):
		w2["debuff_kind"] = GameState.harpoon_debuff   # #196再: 旗艦の銛の効果
	var dmg: float = float(w.dmg) * GameState.attack_mult() * GameState.formation_passive("shot_dmg") * GameState.badge_mult("shot_dmg")   # #224再2: 鶴翼陣
	if randf() < GameState.crit_chance():
		dmg *= 2.0   # 水兵のクリティカル
		w2["crit"] = true   # #139: メッセージは命中時に出す
	w2.dmg = dmg
	return w2

# #264: 実際に発射できたかを返す(撃てなかったときに弾を減らさないため)
func _fire_aim(w: Dictionary) -> bool:
	var dir := (get_global_mouse_position() - player.global_position).normalized()
	# #196: 味方に射線が重なるときは撃たない(フレンドリーファイア無し)。魚雷は射線を無視できる
	# #257: 中心が塞がっていても、左右の舷から射線が通ればそこから撃つ
	var muzzle = _clear_muzzle(dir, float(w.range) * K * 1.2)
	if muzzle == null:
		_notify_los_blocked(str(w.name))   # #256: 撃てなかったことを必ず伝える
		return false   # #264: 弾を消費させない
	# #251再: 放射系は持続音(ループ)に任せ、1発ごとの効果音は鳴らさない
	if not w.has("loop_sfx"):
		Audio.play(w.get("sfx", "sfx_gun"), -8.0, randf_range(0.95, 1.05))   # #47再: 攻撃音を少し小さく
	var proj := Area2D.new()
	proj.set_script(ProjectileScript)
	add_child(proj)
	proj.global_position = (muzzle as Vector2) + dir * 40.0
	proj.from_player = true
	proj.setup(dir, _crewed(w))
	return true

func _fire_torpedo(w: Dictionary) -> void:
	# #252: ロック中の敵がいるときだけ呼ばれる(呼び出し側で確認済み)
	if lock_target == null or not is_instance_valid(lock_target):
		return
	Audio.play("sfx_torpedo", -8.0)   # #47再: 攻撃音を少し小さく
	var dir: Vector2 = (lock_target.global_position - player.global_position).normalized()
	var proj := Area2D.new()
	proj.set_script(ProjectileScript)
	add_child(proj)
	proj.global_position = player.global_position + dir * 40.0
	proj.from_player = true
	proj.setup(dir, _crewed(w), lock_target)

# #16: ロック可能な敵(非空中・射程内・画面内)の一覧
func _lockable_enemies() -> Array:
	var out: Array = []
	var vp := get_viewport_rect().size
	var cam_pos: Vector2 = camera.global_position if camera else player.global_position
	var lock_r := 160.0 * K * GameState.lock_range_mult()
	for e in enemies:
		if not is_instance_valid(e):
			continue   # #196: 空中の敵もロック可能に(魚雷は当たらないが僚艦の砲撃対象になる)
		if e.global_position.distance_to(player.global_position) > lock_r:
			continue
		# #210: 画面外へある程度出てもロックは外れない(横=1/3画面, 縦=1/2画面まで許容)
		var mx := vp.x / 3.0
		var my := vp.y / 2.0
		var rel: Vector2 = e.global_position - (cam_pos - vp * 0.5)
		if rel.x < -mx or rel.y < -my or rel.x > vp.x + mx or rel.y > vp.y + my:
			continue
		out.append(e)
	return out

# #16/#196再: ロック対象は倒すか画面外に出るまで固定。自動ロックは廃止し、
# クリック(またはホイール切替)でのみロックする。
func _update_lock_on() -> void:
	if lock_target == null:
		return
	var lockable := _lockable_enemies()
	if is_instance_valid(lock_target) and lockable.has(lock_target):
		return
	_set_lock(null)   # 倒された/圏外に出たら解除(自動で次を掴まない)

func _pick_nearest_lock(lockable: Array) -> Node2D:
	var best := 1e18
	var t: Node2D = null
	for e in lockable:
		var d: float = e.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			t = e
	return t

func _set_lock(t: Node2D) -> void:
	if t != null and t != lock_target:
		Audio.play("sfx_lock", -6.0)
	if lock_target and is_instance_valid(lock_target):
		lock_target.locked = false
	lock_target = t
	if lock_target and is_instance_valid(lock_target):
		lock_target.locked = true

# #239再6: レイスの瞬間移動など、敵側の都合でロックを外す
func release_lock_on(e: Node2D) -> void:
	if lock_target != null and lock_target == e:
		_set_lock(null)
		GameState.notice.emit("ロックオンが外れた!")

# #16: マウスホイールでロック対象を切替
func _cycle_lock(dir: int) -> void:
	var lockable := _lockable_enemies()
	if lockable.is_empty():
		return
	var idx := lockable.find(lock_target)
	if idx < 0:
		_set_lock(lockable[0])
		return
	idx = (idx + dir + lockable.size()) % lockable.size()
	_set_lock(lockable[idx])

# #79: 主に発見されている(アグロ中)間は緊迫BGM、離れると通常BGMへ戻す
# レヴィアタン戦のみ専用曲(共有者提供 レヴイアタン.mp3)
func _update_boss_bgm() -> void:
	var leviathan := false
	var lord_danger := false
	var king_danger := false
	for e in enemies:
		if not is_instance_valid(e) or e.get("_aggro") != true:
			continue
		if e.kind == "lord":
			lord_danger = true
			if e.id == "leviathan":
				leviathan = true
		elif e.kind == "pirate" and e.id == "king":
			king_danger = true
	# 優先: レヴィアタン > 近海の主 > 海賊王
	var want := ""
	if leviathan:
		want = "bgm_leviathan"
	elif lord_danger:
		want = "bgm_boss"
	elif king_danger:
		want = "bgm_king"
	if want != "" and _boss_bgm_on != want:
		_boss_bgm_on = want
		Audio.play_bgm(want)
		# #79再: 主・レヴィアタンのBGMへ切り替わる時だけ鳴き声を重ねる(海賊王では鳴らさない)
		if want == "bgm_boss" or want == "bgm_leviathan":
			Audio.play("sfx_lord_roar", -2.0)
			# #278(提案4/5): 主の登場は大きめのシェイク1回＋演出ズーム
			screen_shake(9.0, 0.5)
			zoom_punch(1.12, 0.35)
	elif want == "" and _boss_bgm_on != "":
		_boss_bgm_on = ""
		Audio.play_bgm(_sea_bgm())

# #233: 敵弾の発生位置から被弾方向をHUDへ渡す。
func show_damage_direction(source_pos: Vector2) -> void:
	if hud and is_instance_valid(player):
		hud.show_damage_direction(source_pos - player.global_position)
	screen_shake(3.0, 0.15)   # #278(提案4): 被弾で2〜4px・0.15秒

# ---------------- ソナー ----------------
func _update_sonar() -> void:
	var blips: Array = []
	for fs in fish_schools:
		if is_instance_valid(fs):
			blips.append({"pos": fs.global_position, "color": Color(0.4, 0.9, 1.0)})
	for e in enemies:
		if is_instance_valid(e):
			var c := Color(1, 0.3, 0.3)
			if e.kind == "pirate": c = Color(1, 0.6, 0.2)
			elif e.kind == "lord": c = Color(1, 0.1, 0.5)
			blips.append({"pos": e.global_position, "color": c})
	for r in relics_world:
		if is_instance_valid(r):
			blips.append({"pos": r.global_position, "color": Color(1.0, 0.9, 0.4)})
	for x2 in flotsam_world:   # #267: 漂流物もソナーに出す
		if is_instance_valid(x2):
			blips.append({"pos": x2.global_position, "color": Color(0.6, 1.0, 0.85)})
	for isle in islands:
		blips.append({"pos": isle.global_position, "color": Color(0.55, 0.85, 0.5)})
	hud.set_guide(_guide_world_pos())   # #60/#61
	hud.set_home_guide(island_pos(GameState.current_island))   # #76: 直近寄港島は緑
	hud.set_sonar_data(player, blips)

# #60/#61: ガイド対象のワールド座標。達成済みなら自動解除。
func _guide_world_pos() -> Variant:
	var g: Dictionary = GameState.guide_target
	if g.is_empty():
		return null
	if str(g.get("kind", "")) == "island":
		var iid := int(g.get("id", -1))
		if iid < 0 or GameState.visited_islands.has(iid):
			GameState.guide_target = {}
			return null
		return island_pos(iid)
	var lid := str(g.get("id", ""))
	if not Database.lords.has(lid) or GameState.defeated_lords.has(lid) or GameState.claimed_lords.has(lid):
		GameState.guide_target = {}
		return null
	# 出現中の主がいれば実位置、いなければ島から見た定位置(方角×沖合の中央値)
	for e in enemies:
		if is_instance_valid(e) and e.kind == "lord" and e.id == lid:
			return e.global_position
	var ld: Dictionary = Database.lords[lid]
	var ipos := island_pos(int(ld.island))
	var a := deg_to_rad(float(ld.get("dir", 0)))
	return ipos + Vector2(sin(a), -cos(a)) * 375.0 * K * float(ld.get("spawn_dist_mult", 1.0))   # #155再

# ---------------- 食料半減の選択(#17/#23) ----------------
# #24: 船の隠しrange値でなく、仕様どおり「燃料積載で次の島に到達できるか」で判定。
# 半燃料時点の残燃料で、現在位置から最寄りの先の島まで届くかを見積もる。
func _can_voyage_onward() -> bool:
	var next := _nearest_onward_island()
	if next < 0:
		return false
	var dist: float = player.global_position.distance_to(island_pos(next))
	var travel_time: float = dist / maxf(player.max_speed, 1.0)
	var fuel_needed: float = travel_time * 1.5 * GameState.food_drain_mult()
	return GameState.max_food() * 0.5 >= fuel_needed * 0.85

func _nearest_onward_island() -> int:
	var best := -1
	var best_d := 1e18
	for iid in GameState.unlocked_islands:
		if iid > GameState.current_island:
			var d: float = player.global_position.distance_to(island_pos(iid))
			if d < best_d:
				best_d = d
				best = iid
	return best

func _has_onward_island() -> bool:
	for iid in GameState.unlocked_islands:
		if iid > GameState.current_island:
			return true
	return false

func _onward_island_name() -> String:
	var best := 999
	for iid in GameState.unlocked_islands:
		if iid > GameState.current_island and iid < best:
			best = iid
	return Database.island(best).name if best < 999 else "次の島"

func _show_food_choice() -> void:
	_food_dialog_open = true
	_clear_return_hold()   # #280: 長押し中にダイアログが出たら、その場で進捗を捨てる
	if player:
		player.control_enabled = false
	if _food_dialog == null:
		_build_food_dialog()
	_food_msg.text = "燃料が半分を切りました。\n直近の島(%s)へ帰港するか、%s を目指しますか?\n(目指して燃料が尽きた場合は直近の島へ強制帰還します)" % [
		Database.island(GameState.current_island).name, _onward_island_name()]
	_food_dialog.visible = true
	get_tree().paused = true   # #24再: 選択中はゲームを止める(敵の攻撃で状況が変わらないように)

func _build_food_dialog() -> void:
	_food_dialog = CanvasLayer.new()
	_food_dialog.layer = 25
	# #24再: ポーズ中もダイアログ自身は動かす(ボタンを押せるようにする)
	_food_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_food_dialog)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_food_dialog.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.16, 0.98)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.3, 0.6, 0.7)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	_food_msg = Label.new()
	_food_msg.add_theme_font_size_override("font_size", 22)
	_food_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_food_msg)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var b1 := Button.new()
	b1.text = "直近の島へ帰港する"
	b1.add_theme_font_size_override("font_size", 20)
	b1.pressed.connect(func():
		_food_dialog.visible = false
		_food_dialog_open = false
		get_tree().paused = false   # #24再
		GameState.notice.emit("%s へ帰港" % Database.island(GameState.current_island).name)
		_enter_dock(GameState.current_island, true))
	hb.add_child(b1)
	var b2 := Button.new()
	b2.text = "次の島を目指す"
	b2.add_theme_font_size_override("font_size", 20)
	b2.pressed.connect(func():
		_food_dialog.visible = false
		_food_dialog_open = false
		get_tree().paused = false   # #24再
		if player:
			player.control_enabled = true
		GameState.notice.emit("%s を目指す" % _onward_island_name()))
	hb.add_child(b2)

# ---------------- クリーンアップ ----------------
func _clear_sea_actors() -> void:
	_clear_escorts()   # #196
	# #105再2: 飛行中の弾も片付ける。残しておくと寄港後も残留し、
	# 次の出港時に island 付近で被弾することがあった。
	for c in get_children():
		if c is Area2D and c.get_script() == ProjectileScript:
			c.queue_free()
	for a in fish_schools + enemies + relics_world + obstacles + flotsam_world:
		if is_instance_valid(a):
			a.queue_free()
	# #237再4: enemies 配列から漏れた個体が居残ると、港でも近接攻撃を続けて
	#   被弾音だけが鳴る。配列を信用せず、子から敵を直接探して確実に消す。
	for c in get_children():
		if c.get_script() == EnemyScript and is_instance_valid(c):
			c.queue_free()
	fish_schools.clear()
	enemies.clear()
	relics_world.clear()
	flotsam_world.clear()   # #267
	obstacles.clear()
	lock_target = null

# ---------------- 検証用スクリーンショット ----------------
# 起動引数 --shot[:port[:tavern]|:sea[:boss|:food]][=path] で撮影して終了。
func _maybe_screenshot() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var want_shot := false
	var want_port := false
	var want_sea := false
	var want_boss := false
	var want_food := false
	var want_tavern := false
	var want_bestiary := false
	var want_yard := false     # #211再: 造船所の撮影
	var want_guide := false
	var want_bullets := false
	var want_charge := false   # #224再: 突撃のしぶきを撮影
	var want_isle := 0        # #190: 撮影する海域(島index)
	var want_brwin := false   # #209: ボスラッシュ制覇画面
	var want_title := false   # #209再: タイトル画面(Boss Rushボタン付き)
	var want_confirm := false   # #225再: 上書き確認ダイアログ
	var want_help := false      # #236: 操作早見表
	var want_settings := false  # #235: 音量設定
	var want_fleet := false     # #224再2: 編成タブ
	var want_hintlog := false
	var want_ach := false   # #265
	var want_ach2 := false   # #265: 実績メニューを下までスクロールして撮る
	var want_ach3 := false   # #265再: 未達成のまま撮る(「？」の揃いを見る)   # #241再2: ヒントログ
	var want_ach4 := false   # #265再2: 近海の主の実績(バッヂの大きさが揃っているか)
	var want_achtoast := false   # #265再3: 達成トースト(バッヂ絵がドンと出る演出)
	var want_nightfx := false    # #278(提案6): 夜の海域の光(目の光・炎上の灯り)
	var want_debris := false     # #278(提案4): 撃破の破片
	var want_retbug := false     # #280: 帰還長押し中に燃料半減→帰港→再出港
	var want_ach5 := false       # #265再4: 実績メニューの先頭(説明文と「討伐」の見出し)
	for a in args:
		if a.begins_with("--shot"):
			want_shot = true
			want_port = a.find("port") != -1
			want_sea = a.find("sea") != -1
			want_boss = a.find("boss") != -1
			want_food = a.find("food") != -1
			want_tavern = a.find("tavern") != -1
			want_bestiary = a.find("bestiary") != -1
			want_yard = a.find("yard") != -1
			want_guide = a.find("guide") != -1
			want_bullets = a.find("bullets") != -1
			want_charge = a.find("charge") != -1   # #224再
			want_brwin = a.find("brwin") != -1   # #209: ボスラッシュ制覇画面
			want_title = a.find("title") != -1   # #209再
			want_confirm = a.find("confirm") != -1   # #225再
			want_help = a.find("help") != -1 or a.find("hintlog") != -1   # #236/#241再2
			want_settings = a.find("settings") != -1 # #235
			want_fleet = a.find("fleet") != -1       # #224再2
			want_hintlog = a.find("hintlog") != -1   # #241再2
			want_ach = a.find("ach") != -1   # #265: 実績メニュー
			want_ach2 = a.find("ach2") != -1   # #265
			want_ach3 = a.find("ach3") != -1   # #265再
			want_ach4 = a.find("ach4") != -1   # #265再2
			want_achtoast = a.find("achtoast") != -1   # #265再3
			want_nightfx = a.find("nightfx") != -1     # #278(提案6)
			want_debris = a.find("debris") != -1       # #278(提案4)
			want_retbug = a.find("retbug") != -1       # #280
			want_ach5 = a.find("ach5") != -1           # #265再4
			# #190: isle<N> で撮影する海域(島index)を指定(天候・障害物の確認用)
			var ip := a.find("isle")
			if ip != -1 and ip + 4 < a.length():
				var n := a.substr(ip + 4, 1)
				if n.is_valid_int():
					want_isle = clampi(int(n), 0, Database.islands.size() - 1)
	if not want_shot:
		return
	_shot_mode = true   # #278(提案7-4): 撮影中はフェードの暗幕を写さない
	await get_tree().create_timer(0.6).timeout
	if want_title:   # #209再: クリア済み+セーブありでBoss Rushボタンを出したタイトル
		GameState.money = 12345
		GameState.save_game()
		GameState.mark_cleared()
		GameState.mark_boss_rush_cleared()   # #209再2: 王冠の確認
		title.show_title()
		await get_tree().create_timer(0.4).timeout
		if want_confirm:   # #225再: 上書き確認ダイアログの撮影
			title._on_start_pressed()
			await get_tree().create_timer(0.3).timeout
	if want_brwin:
		# #209: ボスラッシュ制覇のエンディング画面を撮影
		title.show_victory(true)
		await get_tree().create_timer(0.4).timeout
	if want_sea:
		title.visible = false
		if want_isle > 0:
			GameState.current_island = want_isle
			GameState.unlocked_islands.assign(range(Database.islands.size()))
			GameState.money = 999999
			GameState.buy_ship("dread")
			GameState.dock_reset()
		if want_charge:   # #224再: 出港前に船団を組む(旗艦=弩級で舷側しぶきを見やすく)
			GameState.money = 9999999
			GameState.unlocked_islands.assign(range(Database.islands.size()))
			GameState.buy_ship("dread")
			GameState.fleet_exchange(0, 0)
			GameState.ship_stock.clear()
			GameState.buy_ship("corvette")
			GameState.fleet_add(0)
			GameState.buy_ship("cutter")
			GameState.fleet_add(0)
			for fi in [1, 2]:
				GameState.target_ship = fi
				GameState.hire_crew("firstmate")
			GameState.dock_reset()
		_on_set_sail()
		if want_guide:   # #60/#61: ガイド弧の表示確認
			GameState.unlocked_islands = [0, 1]
			GameState.visited_islands = [0]
			GameState.guide_target = {"kind": "island", "id": 1}
			await get_tree().create_timer(0.5).timeout
		if want_charge:   # #224再: 突撃中の舷側しぶきを撮影
			GameState.formation_slot = 1      # 単縦陣=突撃
			_apply_formation()
			await get_tree().create_timer(4.5).timeout    # 購入通知が消えるまで待つ
			_skill_cd = 0.0
			_use_skill()
			await get_tree().create_timer(0.12).timeout   # 撮影までに他所で0.3秒待つので短めに
		if want_bullets:   # #78: 各武器の弾を静止配置して見た目を確認
			player.control_enabled = false
			var specs := [
				{"dmg": 8, "falloff": true},                 # ガトリング(黄・細)
				{"dmg": 40},                                 # 大砲(赤橙・丸)
				{"dmg": 18, "debuff": true},                 # 銛(シアン・銛型)
				{"dmg": 22, "homing": true},                 # 魚雷(緑・カプセル)
				# #248/#251: 追加した武器の弾も並べて見比べられるように
				{"dmg": 24, "shape": "note"},                # (参考)音符弾
				{"dmg": 5, "shape": "flame_jet", "art": "res://assets/images/pixel/fx_flame.png"},   # 火炎放射器
				{"dmg": 5, "shape": "frost_jet", "art": "res://assets/images/pixel/fx_frost.png"},   # 冷気放射器
				{"dmg": 24, "shape": "lance_spear"},         # 槍砲
			]
			for i in specs.size():
				var proj := Area2D.new()
				proj.set_script(ProjectileScript)
				add_child(proj)
				proj.from_player = true
				proj.global_position = player.global_position + Vector2((float(i) - 3.5) * 90.0, -120.0)
				proj.setup(Vector2.UP, specs[i])
				proj.speed = 0.0   # 静止させて撮影
			# 敵の炎弾も1つ
			var fp := Area2D.new()
			fp.set_script(ProjectileScript)
			add_child(fp)
			fp.from_player = false
			fp.fire = true
			fp.global_position = player.global_position + Vector2(450.0, -120.0)   # #251: 追加した弾と重ならない位置へ
			fp.setup(Vector2.UP, {"dmg": 20})
			fp.speed = 0.0
			await get_tree().create_timer(0.4).timeout
		if want_food:
			GameState.unlocked_islands = [0, 1]
			GameState.visited_islands = [0]
			_show_food_choice()
			await get_tree().create_timer(0.5).timeout
		if want_retbug:
			# #280: R長押しの途中で燃料が半分を切り、「直近の島へ帰港する」を
			#   選んだあと再出港したときに「帰還まで○秒」が残らないかを撮る。
			GameState.unlocked_islands = [0, 1]
			GameState.visited_islands = [0]
			_return_hold = 1.8
			hud.set_return_progress(_return_hold / 3.0)
			await get_tree().create_timer(0.2).timeout
			_show_food_choice()
			await get_tree().create_timer(0.3).timeout
			for b in _food_dialog.find_children("", "Button", true, false):
				if str(b.text).begins_with("直近の島"):
					b.pressed.emit()
					break
			await get_tree().create_timer(0.4).timeout
			_on_set_sail()
			await get_tree().create_timer(0.5).timeout
		if want_nightfx:
			# #278(提案6): 常闇の海で「夜の帝王(大・中・小)の目」と「炎上する海賊」を並べる
			player.control_enabled = false
			var night_line := [["lord", "night_emperor"], ["lord", "night_bat_medium"],
				["lord", "night_bat_small"], ["pirate", "dread"]]
			for i in night_line.size():
				var e := _make_enemy(night_line[i][0], night_line[i][1],
					player.global_position + Vector2((float(i) - 1.5) * 340.0, -140.0))
				if e != null and night_line[i][0] == "pirate" and e.has_method("ignite_slip"):
					e.ignite_slip(40.0)   # 炎上させて灯りを確認する
			await get_tree().create_timer(0.5).timeout
			GameState.run_armor = 999999.0   # 撮影中に沈まないように
		if want_debris:
			# #278(提案4): 撃破の破片(その敵のドット絵の色を拾った矩形の粒)を撮る。
			# 破片は0.55秒で消えるので、敵を並べておいて撮影の直前に倒す。
			player.control_enabled = false
			GameState.run_armor = 999999.0
			for i in 3:
				_debris_targets.append(_make_enemy("mob", "kraken",
					player.global_position + Vector2((float(i) - 1.0) * 360.0, -220.0)))
		if want_boss:
			player.control_enabled = false
			player.global_position = Vector2(0, 24000)
			var lineup := [
				["pirate", "king"], ["mob", "kraken"], ["mob", "wyvern"],
				["mob", "merman"], ["mob", "charybdis"], ["mob", "tiamat"], ["mob", "dagon"],
				["mob", "zahhak"],
				# #190: 月下の島の新しい敵
				["mob", "starfish"], ["mob", "zaratan"],
				["lord", "aspidochelone"], ["lord", "legion"],
			]
			# #190: 体数が増えたので折り返して2段に並べる(画面からはみ出さないように)
			var per_row := 6
			var rows := int(ceil(float(lineup.size()) / float(per_row)))
			for i in lineup.size():
				var col := i % per_row
				var row := i / per_row
				var n_in_row: int = mini(per_row, lineup.size() - row * per_row)
				var x := (float(col) - (n_in_row - 1) / 2.0) * 260.0
				var y := -560.0 + float(row) * 300.0 - (float(rows) - 2.0) * 150.0
				_make_enemy(lineup[i][0], lineup[i][1], player.global_position + Vector2(x, y))
			await get_tree().create_timer(0.25).timeout
		else:
			await get_tree().create_timer(1.0).timeout
	elif want_port:
		title.visible = false
		if want_isle > 0:   # #211再: 先の島の港も撮影できるように
			GameState.current_island = want_isle
			GameState.unlocked_islands.assign(range(Database.islands.size()))
			GameState.money = 999999
			GameState.dock_reset()
		phase = "dock"
		port_ui.open()
		if want_tavern:
			# #231再2: --shot:port:tavern:lords で「主の情報」タブを撮影する
			# #287再3: :defeated を足すとその島の主を討伐済みにする(スタンプの確認用)
			for a3 in args:
				if a3.find("defeated") != -1:
					for lid in Database.island(GameState.current_island).get("lords", []):
						if not GameState.defeated_lords.has(str(lid)):
							GameState.defeated_lords.append(str(lid))
			for a2 in args:
				if a2.find("lords") != -1:
					port_ui._tavern_section = "lords"
				elif a2.find("crew") != -1:
					port_ui._tavern_section = "crew"
			port_ui.show_tavern()
		if want_ach:
			# #265: すべての実績を達成した状態で実績メニューを開く(確認用)
			if not want_ach3:
				for a2 in Database.achievements:
					GameState.achieved[str(a2.id)] = true
			# #265再8: 複数ステータスにまたがるバフ(最も文字数が長いケース)を選んだ状態で撮る。
			# 単一ステータスの"fame_max"だけだと横スクロール回帰(#265)を見逃すため。
			GameState.badge_id = "true_sea_ruler"
			port_ui.show_achievements()
			# #265: ach2 指定時は下(専用バッヂの並ぶ(3)〜(7))までスクロールする
			if want_ach2 or want_ach4 or want_ach5:
				await get_tree().create_timer(0.3).timeout
				var sc0: Node = port_ui.content.get_parent()
				while sc0 != null and not (sc0 is ScrollContainer):
					sc0 = sc0.get_parent()
				if sc0 is ScrollContainer:
					# #265再2: ach4 は「近海の主の討伐」のあたり(中ほど)で止める
					# #265再4: ach5 は先頭(説明文と「討伐」の見出し)を写す
					(sc0 as ScrollContainer).scroll_vertical = 0 if want_ach5 else (2450 if want_ach4 else 100000)
		if want_yard:
			port_ui._shipyard_weapon_slot = 0   # #248: 武器一覧も写るようスロット1を開いておく
			port_ui.show_shipyard()
		if want_fleet:   # #224再2: 編成タブ(陣形の効果一覧)を撮影
			GameState.visited_islands = [0, 1]
			if GameState.fleet.size() < 2:
				GameState.money = 9999999
				GameState.buy_ship("skiff")
				GameState.fleet_add(0)
			port_ui.show_fleet()
		if want_bestiary:   # #177: 討伐記録タブの確認(一部を討伐済みにして表示)
			GameState.record_kill("mob", "narwhal")
			GameState.record_kill("mob", "charybdis")
			GameState.record_kill("mob", "charybdis")
			GameState.record_kill("pirate", "king")
			port_ui.show_bestiary()
		await get_tree().create_timer(0.3).timeout
	# #235/#236: 音量設定・操作早見表のオーバーレイ(タイトル画面の上に重ねて撮影)
	if want_help or want_settings:
		var host: Control = title._root if title.get("_root") != null else null
		if host == null:
			host = Control.new()
			host.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(host)
		if want_settings:
			OverlayMenusScript.show_settings(host)
		else:
			# #241再2: 早見表/ヒントログの確認用にログを仕込む
			if GameState.hint_log.is_empty():
				GameState.current_island = 0
				GameState.next_departure_hint()
				GameState.next_departure_hint()
			if want_hintlog:
				OverlayMenusScript.show_hint_log(host)
			else:
				OverlayMenusScript.show_help(host)
		await get_tree().create_timer(0.35).timeout
	if want_debris:
		for e in _debris_targets:
			if is_instance_valid(e):
				e._die()
		await get_tree().create_timer(0.14).timeout
	if want_achtoast:
		# #265再3: 実績達成トースト(バッヂ絵がドンと出る0.8秒の演出)の見せ場を撮る
		port_ui.close()
		GameState.achieved.clear()
		GameState.achievement_unlocked.emit("lord_leviathan")
		await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "user://shot.png"
	for a in args:
		if a.begins_with("--shot") and a.find("=") != -1:
			out = a.substr(a.find("=") + 1)
	img.save_png(out)
	print("SHOT_SAVED:", ProjectSettings.globalize_path(out))
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
