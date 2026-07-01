extends Node3D
## World — ゲーム全体の統合。環境/海/島/プレイヤー/スポーン/HUD/港メニューを管理し、
## 「帰港(港メニュー)」と「航海(漁・戦闘)」のフェーズを切り替える。

const PlayerScript = preload("res://scripts/Player.gd")
const IslandScript = preload("res://scripts/Island.gd")
const FishSchoolScript = preload("res://scripts/FishSchool.gd")
const EnemyScript = preload("res://scripts/Enemy.gd")
const ProjectileScript = preload("res://scripts/Projectile.gd")
const HUDScript = preload("res://scripts/HUD.gd")
const PortUIScript = preload("res://scripts/PortUI.gd")
const TitleScript = preload("res://scripts/TitleScreen.gd")
const RelicScript = preload("res://scripts/Relic.gd")

var player: CharacterBody3D
var islands: Array = []          # Island ノード
var hud: CanvasLayer
var port_ui: CanvasLayer
var title: CanvasLayer
var _victory_shown: bool = false

var phase: String = "title"      # "title" / "dock" / "sea"
var fish_schools: Array = []
var enemies: Array = []
var relics_world: Array = []

var slot_cooldowns: Array = [0.0, 0.0, 0.0, 0.0]
var lock_target: Node3D = null

var spawn_timer: float = 0.0
const MAX_FISH := 7
const MAX_ENEMIES := 4
var _dock_grace: float = 0.0

func _ready() -> void:
	_build_environment()
	_build_ocean()
	_build_islands()
	_build_player()
	# HUD / PortUI
	hud = HUDScript.new()
	add_child(hud)
	port_ui = PortUIScript.new()
	add_child(port_ui)
	port_ui.set_sail_requested.connect(_on_set_sail)
	port_ui.fast_travel_requested.connect(_on_fast_travel)
	GameState.stats_changed.connect(_on_stats_changed)
	# タイトル
	title = TitleScript.new()
	add_child(title)
	title.start_pressed.connect(_on_title_start)
	# 始まりの島で待機(港メニューはタイトルの裏)
	GameState.dock_reset()
	_enter_dock(0, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	port_ui.close()
	phase = "title"
	title.show_title()
	_maybe_screenshot()

# 開発検証用: 起動引数に "--shot[:port]" があれば撮影して終了。
func _maybe_screenshot() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var want_shot := false
	var want_port := false
	var want_sea := false
	var want_boss := false
	for a in args:
		if a.begins_with("--shot"):
			want_shot = true
			if a.find("port") != -1:
				want_port = true
			if a.find("sea") != -1:
				want_sea = true
			if a.find("boss") != -1:
				want_boss = true
	if not want_shot:
		return
	await get_tree().create_timer(0.6).timeout
	if want_sea:
		title.visible = false
		_on_set_sail()
		if want_boss:
			# 検証用ショーケース: 開けた海で各3Dモデルを近距離一列に並べて確認
			player.control_enabled = false
			player.global_position = Vector3(0, 0, 400)
			player.rotation.y = 0
			player.cam_yaw = 0.0
			player.cam_pitch = -0.12
			player._update_cam_rot()
			if player.ship_rig:
				player.ship_rig.visible = false   # ショーケース時は自船を隠す
			var lineup := [
				["pirate", "corsair"], ["mob", "narwhal"], ["mob", "seahunter"],
				["lord", "sawshark"], ["lord", "walrus"], ["lord", "whale"],
				["lord", "hydra"], ["lord", "quetzal"],
			]
			var n := lineup.size()
			for i in n:
				var x := (float(i) - (n - 1) / 2.0) * 12.0
				_make_enemy(lineup[i][0], lineup[i][1], Vector3(x, 0, 372))
			await get_tree().create_timer(0.4).timeout
		else:
			await get_tree().create_timer(1.2).timeout
	elif want_port:
		title.visible = false
		phase = "dock"
		port_ui.open()
		var want_tavern := false
		for a in args:
			if a.begins_with("--shot") and a.find("tavern") != -1:
				want_tavern = true
		if want_tavern:
			port_ui.show_tavern()
		await get_tree().create_timer(0.3).timeout
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

func _on_title_start() -> void:
	if _victory_shown:
		get_tree().reload_current_scene()
		return
	title.visible = false
	phase = "dock"
	port_ui.open()

# ---------------- 構築 ----------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.35, 0.55, 0.8)
	pm.sky_horizon_color = Color(0.7, 0.8, 0.85)
	pm.ground_horizon_color = Color(0.6, 0.7, 0.75)
	pm.ground_bottom_color = Color(0.2, 0.35, 0.45)
	pm.sun_angle_max = 30.0
	sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.85)
	env.fog_density = 0.0015
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

func _build_ocean() -> void:
	var ocean := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	ocean.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.34, 0.48)
	mat.metallic = 0.3
	mat.roughness = 0.35
	ocean.mesh.material = mat
	ocean.position.y = 0.0
	add_child(ocean)

func _build_islands() -> void:
	for i in Database.islands.size():
		var isle := Node3D.new()
		isle.set_script(IslandScript)
		isle.setup(i)                       # _ready は add_child で走るため先に設定
		add_child(isle)
		isle.global_position = Database.islands[i].pos
		isle.player_docked.connect(_on_player_docked)
		islands.append(isle)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	add_child(player)
	player.global_position = Database.island(0).pos + Vector3(0, 0, 40)

# ---------------- フェーズ遷移 ----------------
func _enter_dock(island_id: int, do_reset := true) -> void:
	phase = "dock"
	GameState.current_island = island_id
	if do_reset:
		GameState.dock_reset()
	var isle_pos: Vector3 = Database.island(island_id).pos
	player.global_position = isle_pos + Vector3(0, 0, 40)
	player.velocity = Vector3.ZERO
	player.control_enabled = false
	_clear_sea_actors()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud:
		hud.visible = false
	port_ui.open()

func _on_set_sail() -> void:
	port_ui.close()
	phase = "sea"
	GameState.set_sail()
	player.control_enabled = true
	var isle_pos: Vector3 = Database.island(GameState.current_island).pos
	player.global_position = isle_pos + Vector3(0, 0, 60)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.visible = true
	hud.rebuild_weapons()
	hud.set_location("航海中: %s 近海" % Database.island(GameState.current_island).name)
	_dock_grace = 2.0
	slot_cooldowns = [0.0, 0.0, 0.0, 0.0]

func _on_fast_travel(island_id: int) -> void:
	if GameState.run_food < Database.island(island_id).get("food_cost", 0):
		pass
	port_ui.close()
	_enter_dock(island_id, true)

func _on_player_docked(island_id: int) -> void:
	if phase != "sea" or _dock_grace > 0.0:
		return
	GameState.notice.emit("%s に帰港" % Database.island(island_id).name)
	_enter_dock(island_id, true)

func _forced_return(reason: String) -> void:
	GameState.notice.emit(reason)
	_enter_dock(GameState.current_island, true)

# ---------------- メインループ ----------------
func _physics_process(delta: float) -> void:
	if phase != "sea":
		return
	if _dock_grace > 0.0:
		_dock_grace -= delta
	GameState.regen_fire(delta)
	_update_food(delta)
	_update_fishing(delta)
	_update_spawns(delta)
	_update_weapons(delta)
	_update_sonar()
	_update_lock_on()
	if hud:
		hud.update_bars()
	# 強制帰還条件
	if GameState.run_armor <= 0.0:
		_forced_return("装甲が尽き船が大破! 強制帰還")
	elif _food_forced_threshold() and GameState.run_food <= GameState.max_food() * 0.5 and not _can_voyage_onward():
		_forced_return("食料が半分を切った。始まりの近海から強制帰還")
	elif GameState.run_food <= 0.0:
		_forced_return("食料が尽きた! 強制帰還")

func _food_forced_threshold() -> bool:
	# 「始めの島にいるうち」= 船の航続が現在島止まりで次島に行けない
	return int(GameState.ship().range) <= GameState.current_island

func _can_voyage_onward() -> bool:
	return int(GameState.ship().range) > GameState.current_island

func _update_food(delta: float) -> void:
	GameState.run_food = maxf(GameState.run_food - delta * 1.5, 0.0)

func _on_stats_changed() -> void:
	if hud and hud.visible:
		hud.update_bars()
		hud.refresh_money_fame()
	_check_victory()

func _check_victory() -> void:
	if _victory_shown:
		return
	if GameState.defeated_lords.has("leviathan") or GameState.claimed_lords.has("leviathan"):
		_victory_shown = true
		phase = "title"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if hud: hud.visible = false
		port_ui.close()
		_clear_sea_actors()
		title.show_victory()

# ---------------- 漁 ----------------
func _update_fishing(delta: float) -> void:
	var nearest = null
	var best := 14.0
	for fs in fish_schools:
		if not is_instance_valid(fs) or fs.depleted():
			continue
		var d: float = player.global_position.distance_to(fs.global_position)
		if d < best:
			best = d
			nearest = fs
	if nearest == null:
		hud.set_prompt("")
		return
	hud.set_prompt("[E]長押しで漁  (%s)" % Database.fish_def(nearest.fish_id).name)
	if Input.is_action_pressed("interact"):
		var got: String = nearest.try_fish(delta)
		if got != "":
			if not GameState.add_cargo(got):
				pass

# ---------------- スポーン ----------------
func _update_spawns(delta: float) -> void:
	fish_schools = fish_schools.filter(func(f): return is_instance_valid(f) and not f.depleted())
	enemies = enemies.filter(func(e): return is_instance_valid(e))
	# 遠すぎる魚群を間引き
	for fs in fish_schools.duplicate():
		if player.global_position.distance_to(fs.global_position) > 320:
			fs.queue_free()
	relics_world = relics_world.filter(func(r): return is_instance_valid(r))
	for r in relics_world.duplicate():
		if player.global_position.distance_to(r.global_position) > 360:
			r.queue_free()
	spawn_timer -= delta
	if spawn_timer > 0:
		return
	spawn_timer = 1.5
	if fish_schools.size() < MAX_FISH:
		_spawn_fish()
	if enemies.size() < MAX_ENEMIES:
		_spawn_enemy()
	# 旧文明の遺産は低確率で出現(運よく見つける)
	if relics_world.size() < 2 and randf() < 0.12:
		_spawn_relic()

func _ring_pos(rmin: float, rmax: float) -> Vector3:
	var ang := randf() * TAU
	var rad := randf_range(rmin, rmax)
	return player.global_position + Vector3(cos(ang) * rad, 0, sin(ang) * rad)

func _spawn_fish() -> void:
	var isle: Dictionary = Database.island(GameState.current_island)
	var pool: Array = isle.spawn.duplicate()
	if randf() < 0.08:
		pool.append("grouper")   # レア魚
	var id: String = pool[randi() % pool.size()]
	var fs := Node3D.new()
	fs.set_script(FishSchoolScript)
	fs.setup(id, randi_range(3, 7))         # _ready 前に設定
	add_child(fs)
	fs.global_position = _ring_pos(40, 160)
	fish_schools.append(fs)

func _spawn_enemy() -> void:
	var roll := randf()
	var kind := "mob"
	var id := ""
	var isle := GameState.current_island
	# 海賊は控えめ(Issue #1: 22%)、戦闘モブも頻度減(Issue #3: 63%→26%)、
	# 残り(約38%)は何も出さず海を穏やかに保つ。
	if roll < 0.22:
		kind = "pirate"
		var ps := ["raider", "corsair", "dread"]
		id = ps[mini(isle, 2)]
		if isle == 0:
			id = "raider"
	elif roll < 0.48:
		kind = "mob"
		var mobs := Database.combat_mobs.keys()
		id = mobs[randi() % mobs.size()]
	elif roll < 0.62:
		# 主は低確率で出現(対応島のみ)
		var lords: Array = Database.island(isle).get("lords", [])
		var avail := lords.filter(func(l): return not GameState.claimed_lords.has(l) and not GameState.defeated_lords.has(l))
		if avail.is_empty():
			kind = "mob"
			id = Database.combat_mobs.keys()[0]
		else:
			kind = "lord"
			id = avail[randi() % avail.size()]
	if id == "":
		return  # スキップ帯(約38%): 何も出さず海を穏やかに保つ
	if kind == "lord" and bool(Database.lords.get(id, {}).get("pair", false)):
		# 番い(ギガントセイウチ): 2体同時出現。両方倒さねば討伐扱いにならない。
		var base := _ring_pos(70, 150)
		var a := _make_enemy(kind, id, base + Vector3(7, 0, 0))
		var b := _make_enemy(kind, id, base + Vector3(-7, 0, 0))
		a.pair_partner = b
		b.pair_partner = a
	else:
		_make_enemy(kind, id, _ring_pos(70, 150))

func _spawn_relic() -> void:
	var r := Area3D.new()
	r.set_script(RelicScript)
	var tier := GameState.current_island
	r.setup(randi_range(200, 500) * (tier + 1))
	add_child(r)
	r.global_position = _ring_pos(60, 180)
	relics_world.append(r)

func _make_enemy(kind: String, id: String, pos: Vector3) -> CharacterBody3D:
	var e := CharacterBody3D.new()
	e.set_script(EnemyScript)
	e.setup(kind, id)                       # _ready 前に設定
	add_child(e)
	e.global_position = pos
	enemies.append(e)
	return e

# ---------------- 武器 ----------------
func _update_weapons(delta: float) -> void:
	for i in slot_cooldowns.size():
		if slot_cooldowns[i] > 0:
			slot_cooldowns[i] -= delta
	var slots := int(GameState.ship().slots)
	if Input.is_action_pressed("fire_primary"):
		for i in slots:
			var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
			if wid == "" or not Database.weapons.has(wid):
				continue
			var w: Dictionary = Database.weapons[wid]
			if w.kind == "aim" and slot_cooldowns[i] <= 0:
				_fire_aim(w)
				slot_cooldowns[i] = float(w.cooldown)
	if Input.is_action_just_pressed("fire_torpedo"):
		for i in slots:
			var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
			if wid == "" or not Database.weapons.has(wid):
				continue
			var w: Dictionary = Database.weapons[wid]
			if w.kind == "lock" and slot_cooldowns[i] <= 0:
				_fire_torpedo(w)
				slot_cooldowns[i] = float(w.cooldown)

func _fire_aim(w: Dictionary) -> void:
	var aim: Vector3 = player.get_aim_point()
	var muzzle: Vector3 = player.global_position + Vector3(0, 1.5, 0)
	var dir := (aim - muzzle).normalized()
	var proj := Area3D.new()
	proj.set_script(ProjectileScript)
	add_child(proj)
	proj.global_position = muzzle
	proj.from_player = true
	proj.setup(dir, w)

func _fire_torpedo(w: Dictionary) -> void:
	var muzzle: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var dir: Vector3 = -player.transform.basis.z
	if lock_target and is_instance_valid(lock_target):
		dir = (lock_target.global_position - muzzle).normalized()
	var proj := Area3D.new()
	proj.set_script(ProjectileScript)
	add_child(proj)
	proj.global_position = muzzle
	proj.from_player = true
	proj.setup(dir, w, lock_target)

func _update_lock_on() -> void:
	# 画面前方の最も近い非空中の敵をロック
	var best := 9999.0
	var t: Node3D = null
	var fwd: Vector3 = -player.transform.basis.z
	for e in enemies:
		if not is_instance_valid(e) or e.aerial:
			continue
		var to: Vector3 = e.global_position - player.global_position
		if to.length() > 160:
			continue
		if fwd.dot(to.normalized()) < 0.4:
			continue
		var d := to.length()
		if d < best:
			best = d
			t = e
	lock_target = t

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
	for isle in islands:
		blips.append({"pos": isle.global_position, "color": Color(0.55, 0.85, 0.5)})
	hud.set_sonar_data(player, blips)

# ---------------- クリーンアップ ----------------
func _clear_sea_actors() -> void:
	for fs in fish_schools:
		if is_instance_valid(fs): fs.queue_free()
	for e in enemies:
		if is_instance_valid(e): e.queue_free()
	for r in relics_world:
		if is_instance_valid(r): r.queue_free()
	fish_schools.clear()
	enemies.clear()
	relics_world.clear()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if phase == "sea":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
