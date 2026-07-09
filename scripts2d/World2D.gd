extends Node2D
## World2D — 見下ろし2D版の統合。3D版Worldの全要素(#1〜#23対応込み)を2Dで再構成。
## フェーズ: title / dock(港メニュー) / sea(漁・戦闘)。ロジックは GameState/Database を共用。

const PlayerScript = preload("res://scripts2d/Player2D.gd")
const IslandScript = preload("res://scripts2d/Island2D.gd")
const FishSchoolScript = preload("res://scripts2d/FishSchool2D.gd")
const EnemyScript = preload("res://scripts2d/Enemy2D.gd")
const ProjectileScript = preload("res://scripts2d/Projectile2D.gd")
const RelicScript = preload("res://scripts2d/Relic2D.gd")
const HUDScript = preload("res://scripts2d/HUD2D.gd")
const PortUIScript = preload("res://scripts/PortUI.gd")
const TitleScript = preload("res://scripts/TitleScreen.gd")

const K := 6.0          # 3D数値→2D px 換算
var player: CharacterBody2D
var camera: Camera2D
var islands: Array = []
var hud: CanvasLayer
var port_ui: CanvasLayer
var title: CanvasLayer
var ocean_mat: ShaderMaterial

var phase: String = "title"
var fish_schools: Array = []
var enemies: Array = []
var relics_world: Array = []
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

func island_pos(idx: int) -> Vector2:
	var p: Vector3 = Database.island(idx).pos
	return Vector2(p.x, p.z) * K

func _ready() -> void:
	_build_ocean()
	_build_islands()
	_build_player()
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
	while ipos.size() < 4:
		ipos.append(Vector2(1e9, 1e9))
	ocean_mat.set_shader_parameter("islands", ipos)
	ocean_mat.set_shader_parameter("island_count", mini(Database.islands.size(), 4))

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
	# #16: マウスホイールでロックオン対象を切替(航海中のみ)
	if phase == "sea" and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_lock(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_lock(1)

func _process(_d: float) -> void:
	# カメラ追従 + 海シェーダにカメラ左上のワールド座標を渡す
	if camera and player:
		camera.global_position = player.global_position
	if ocean_mat and player:
		var vp := get_viewport_rect().size
		ocean_mat.set_shader_parameter("cam_pos", player.global_position - vp * 0.5)

# ---------------- フェーズ ----------------
func _on_title_start() -> void:
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
	var was_at_sea := GameState.at_sea
	if was_at_sea and not GameState.crew.is_empty():
		GameState.grow_crew()   # 航海を終えたクルーが成長(#39)
	phase = "dock"
	_dock_target = -1
	_returning = false
	GameState.current_island = island_id
	if not GameState.visited_islands.has(island_id):
		GameState.visited_islands.append(island_id)   # 到達記録(#19)
	if do_reset:
		GameState.dock_reset()
	player.global_position = island_pos(island_id) + Vector2(0, 260)
	player.velocity = Vector2.ZERO
	player.control_enabled = false
	_clear_sea_actors()
	if hud:
		hud.visible = false
	Audio.play_bgm("bgm_port")
	_boss_bgm_on = ""
	GameState.docking_locked = false   # 寄港完了でロック解除(次の航海はset_sailでも解除)
	# #93: 航海から寄港(強制帰還/大破含む)するたびオートセーブ。勝利時は保存しない
	if was_at_sea and not _victory_shown:
		GameState.save_game()
	port_ui.open(was_at_sea)   # #104: 航海から戻った時だけ寄港バナー

func _on_set_sail() -> void:
	port_ui.close()
	phase = "sea"
	# クルーの賃金(#39): 出港ごとに支払い
	var wages := GameState.crew_wages()
	if wages > 0:
		GameState.add_money(-mini(wages, GameState.money))
		GameState.notice.emit("クルーへ賃金 %d を支払った" % wages)
	GameState.set_sail()
	player.control_enabled = true
	player.rebuild_visual()
	player.global_position = island_pos(GameState.current_island) + Vector2(0, 300)
	hud.visible = true
	hud.rebuild_weapons()
	hud.update_bars()
	hud.set_location("航海中: %s 近海" % Database.island(GameState.current_island).name)
	Audio.play_bgm("bgm_sea")
	_boss_bgm_on = ""
	_return_hold = 0.0
	_dock_grace = 2.0
	_dock_target = -1
	_food_choice_shown = false
	_food_dialog_open = false
	slot_cooldowns = [0.0, 0.0, 0.0, 0.0]
	_reset_ammo()
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
	if phase != "sea":
		return
	if _dock_grace > 0.0:
		_dock_grace -= delta
	GameState.regen_fire(delta)
	GameState.tick_slips(delta)   # #64/#72: 炎上・毒のスリップ
	GameState.run_food = maxf(GameState.run_food - delta * 1.5 * GameState.food_drain_mult(), 0.0)
	# #68: Rキーを5秒長押しで直近の島へ帰還。長押し中に装甲0なら大破(後段の装甲チェックで処理)
	if Input.is_action_pressed("fast_return") and not _returning and not _food_dialog_open:
		_return_hold += delta
		hud.set_return_progress(_return_hold / 5.0)
		if _return_hold >= 5.0:
			_return_hold = 0.0
			hud.set_return_progress(0.0)
			GameState.notice.emit("%s へ帰還" % Database.island(GameState.current_island).name)
			_enter_dock(GameState.current_island, true)
			return
	elif _return_hold > 0.0:
		_return_hold = 0.0
		hud.set_return_progress(0.0)
	if not _update_docking():
		_update_fishing(delta)
	_update_spawns(delta)
	_update_weapons(delta)
	_update_lock_on()
	_update_sonar()
	_update_boss_bgm()
	if hud:
		hud.update_bars()
	# 強制帰還・食料選択(#17/#23)
	if GameState.run_armor <= 0.0:
		_forced_return("船が大破!", true)
	elif GameState.run_food <= 0.0:
		_forced_return("燃料が尽きた! 直近の島へ強制帰還")
	elif GameState.run_food <= GameState.max_food() * 0.5:
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
	if _victory_shown:
		return
	if GameState.defeated_lords.has("leviathan") or GameState.claimed_lords.has("leviathan"):
		_victory_shown = true
		phase = "title"
		if hud: hud.visible = false
		port_ui.close()
		_clear_sea_actors()
		Audio.play_bgm("bgm_ending")   # #80: 厳かなエンディングBGM
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
		return
	hud.set_prompt("[E]長押しで漁  (%s)" % Database.fish_def(nearest.fish_id).name)
	if Input.is_action_pressed("interact"):
		var got: String = nearest.try_fish(delta)
		if got != "":
			GameState.add_cargo(got)

# ---------------- スポーン ----------------
func _ring_pos(rmin: float, rmax: float) -> Vector2:
	var ang := randf() * TAU
	return player.global_position + Vector2(cos(ang), sin(ang)) * randf_range(rmin * K, rmax * K)

func _update_spawns(delta: float) -> void:
	fish_schools = fish_schools.filter(func(f): return is_instance_valid(f) and not f.depleted())
	enemies = enemies.filter(func(e): return is_instance_valid(e))
	relics_world = relics_world.filter(func(r): return is_instance_valid(r))
	for fs in fish_schools.duplicate():
		if player.global_position.distance_to(fs.global_position) > 320 * K:
			fs.queue_free()
	for r in relics_world.duplicate():
		if player.global_position.distance_to(r.global_position) > 360 * K:
			r.queue_free()
	# #69他再修正: 主以外の敵は遠く離れたらデスポーンして枠を空ける(#67: 主と取り巻きは免除)
	for e in enemies.duplicate():
		if is_instance_valid(e) and e.kind != "lord" and not e.is_escort and player.global_position.distance_to(e.global_position) > 400 * K:
			e.queue_free()
	spawn_timer -= delta
	if spawn_timer > 0:
		return
	spawn_timer = 1.5
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

func _spawn_fish() -> void:
	var isle: Dictionary = Database.island(GameState.current_island)
	var pool: Array = isle.spawn.duplicate()
	if randf() < 0.08:
		pool.append("grouper")
	var id: String = pool[randi() % pool.size()]
	# #53: 島の領域内(入港圏+余白)には魚群を出さない
	var pos := _ring_pos(40, 160)
	for attempt in 6:
		var ok := true
		for isle_node in islands:
			if pos.distance_to(isle_node.global_position) < 340.0:
				ok = false
				break
		if ok:
			break
		pos = _ring_pos(40, 160)
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
		var ps := ["raider", "corsair", "dread"]
		id = ps[mini(isle, 2)]
		if isle == 0:
			id = "raider"
	elif roll < 0.38:
		kind = "mob"
		id = Database.pick_mob(isle)   # #38: 島tierごとの出現割合
	elif roll < 0.50:
		# #73再: 海賊王。島の周り以外の全海域で出現。先の島ほど出やすい(始0.02/潮0.04/嵐0.08/果0.12)。同時1体
		var king_rate := [0.02, 0.04, 0.08, 0.12][clampi(isle, 0, 3)]
		if not near_island and not _king_alive() and randf() < king_rate:
			kind = "pirate"
			id = "king"
	if id == "":
		return
	# #71: マーマン等は必ず群れで出現
	var grp := int(Database.combat_mobs.get(id, {}).get("group", 1)) if kind == "mob" else 1
	var pos := _ring_pos(70, 150)
	for gi in grp:
		_make_enemy(kind, id, pos + Vector2.RIGHT.rotated(randf() * TAU) * (0.0 if gi == 0 else randf_range(70.0, 160.0)))
	if id == "king":
		GameState.notice.emit("海賊王の旗艦が現れた!")

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
		if is_instance_valid(e) and e.kind == "lord" and e.id == id:
			return true
	return false

func _king_alive() -> bool:
	for e in enemies:
		if is_instance_valid(e) and e.kind == "pirate" and e.id == "king":
			return true
	return false

# #62: 主の取り巻き。戦闘モブ2体を主の周囲に出現させる(#67: 上限・デスポーン免除)
# #119: レヴィアタンはカリュブディス/ティアマット/ダゴンから2種。#120: マーマンは取り巻きにしない
func _spawn_escorts(center: Vector2, lord_id: String = "") -> Array:
	var out: Array = []
	var ids: Array = []
	if lord_id == "leviathan":
		var pool := ["charybdis", "tiamat", "dagon"]
		pool.shuffle()
		ids = [pool[0], pool[1]]
	elif lord_id == "hydra" or lord_id == "quetzal":
		# #141: カリュブディス必ず1体+クラーケン/ワイバーンのいずれか1体
		ids = ["charybdis", ["kraken", "wyvern"][randi() % 2]]
	else:
		for i in 2:
			var mid: String = Database.pick_mob(GameState.current_island)
			var guard := 0
			while mid == "merman" and guard < 8:   # #120: マーマン除外
				mid = Database.pick_mob(GameState.current_island)
				guard += 1
			if mid == "merman":
				mid = "wyrm"
			ids.append(mid)
	# #62再: 取り巻きは主の前方(プレイヤー側)に盾として配置
	var to_p: Vector2 = (player.global_position - center).normalized() if is_instance_valid(player) else Vector2.DOWN
	var perp := to_p.rotated(PI / 2)
	var i := 0
	for mid in ids:
		var side := -1.0 if i == 0 else 1.0
		var off := to_p * randf_range(120.0, 190.0) + perp * side * randf_range(50.0, 110.0)
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
	return ipos + Vector2(sin(a), -cos(a)) * randf_range(320.0, 430.0) * K

func _make_enemy(kind: String, id: String, pos: Vector2) -> CharacterBody2D:
	var e := CharacterBody2D.new()
	e.set_script(EnemyScript)
	e.setup(kind, id)
	add_child(e)
	e.global_position = pos
	enemies.append(e)
	return e

func _spawn_relic() -> void:
	# #124: 島の領域内には遺産を出さない(魚群#53と同様に島から離す)
	var pos := _ring_pos(60, 180)
	for attempt in 6:
		var ok := true
		for isle_node in islands:
			if pos.distance_to(isle_node.global_position) < 340.0:
				ok = false
				break
		if ok:
			break
		pos = _ring_pos(60, 180)
	for isle_node in islands:
		if pos.distance_to(isle_node.global_position) < 340.0:
			return
	var r := Area2D.new()
	r.set_script(RelicScript)
	r.setup(randi_range(200, 500) * (GameState.current_island + 1))
	add_child(r)
	r.global_position = pos
	relics_world.append(r)

# ---------------- 武器 ----------------
func _reset_ammo() -> void:
	slot_ammo = [0, 0, 0, 0]
	for i in mini(4, GameState.weapons.size()):
		var wid: String = GameState.weapons[i]
		if wid != "" and Database.weapons.has(wid):
			slot_ammo[i] = int(Database.weapons[wid].mag)

# 発射後の弾倉消費(#27)。弾切れでリロード時間をクールダウンに載せ、弾を補充。
func _consume_ammo(i: int, w: Dictionary) -> void:
	slot_ammo[i] = int(slot_ammo[i]) - 1
	if slot_ammo[i] <= 0:
		slot_cooldowns[i] = float(w.reload)
		slot_ammo[i] = int(w.mag)
		GameState.notice.emit("%s リロード中…" % w.name)
	else:
		slot_cooldowns[i] = float(w.cooldown)

func _update_weapons(delta: float) -> void:
	for i in slot_cooldowns.size():
		if slot_cooldowns[i] > 0:
			slot_cooldowns[i] -= delta
	if GameState.docking_locked:
		return   # #101: 大破/寄港確定後は攻撃不可(討伐・賞金取得を防ぐ)
	var slots := int(GameState.ship().slots)
	if Input.is_action_pressed("fire_primary"):
		for i in slots:
			var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
			if wid == "" or not Database.weapons.has(wid):
				continue
			var w: Dictionary = Database.weapons[wid]
			if w.kind == "aim" and slot_cooldowns[i] <= 0:
				_fire_aim(w)
				_consume_ammo(i, w)
	if Input.is_action_just_pressed("fire_torpedo"):
		for i in slots:
			var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
			if wid == "" or not Database.weapons.has(wid):
				continue
			var w: Dictionary = Database.weapons[wid]
			if w.kind == "lock" and slot_cooldowns[i] <= 0:
				_fire_torpedo(w)
				_consume_ammo(i, w)
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
	var dmg: float = float(w.dmg) * GameState.attack_mult()
	if randf() < GameState.crit_chance():
		dmg *= 2.0   # 水兵のクリティカル
		w2["crit"] = true   # #139: メッセージは命中時に出す
	w2.dmg = dmg
	return w2

func _fire_aim(w: Dictionary) -> void:
	Audio.play(w.get("sfx", "sfx_gun"), -4.0, randf_range(0.95, 1.05))
	var dir := (get_global_mouse_position() - player.global_position).normalized()
	var proj := Area2D.new()
	proj.set_script(ProjectileScript)
	add_child(proj)
	proj.global_position = player.global_position + dir * 40.0
	proj.from_player = true
	proj.setup(dir, _crewed(w))

func _fire_torpedo(w: Dictionary) -> void:
	Audio.play("sfx_torpedo", -4.0)
	var dir: Vector2 = player.forward()
	if lock_target and is_instance_valid(lock_target):
		dir = (lock_target.global_position - player.global_position).normalized()
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
		if not is_instance_valid(e) or e.aerial:
			continue
		if e.global_position.distance_to(player.global_position) > lock_r:
			continue
		# 画面内判定
		var rel: Vector2 = e.global_position - (cam_pos - vp * 0.5)
		if rel.x < -40 or rel.y < -40 or rel.x > vp.x + 40 or rel.y > vp.y + 40:
			continue
		out.append(e)
	return out

# #16: ロック対象は倒すか画面外に出るまで固定。ホイールで切替
func _update_lock_on() -> void:
	var lockable := _lockable_enemies()
	# 現在のロックが有効(生存・画面内・射程内)なら維持
	if lock_target and is_instance_valid(lock_target) and lockable.has(lock_target):
		return
	# 無効になったら最寄りを新規ロック
	var t: Node2D = _pick_nearest_lock(lockable)
	_set_lock(t)

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
	elif want == "" and _boss_bgm_on != "":
		_boss_bgm_on = ""
		Audio.play_bgm("bgm_sea")

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
	return ipos + Vector2(sin(a), -cos(a)) * 375.0 * K

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
	if player:
		player.control_enabled = false
	if _food_dialog == null:
		_build_food_dialog()
	_food_msg.text = "燃料が半分を切りました。\n直近の島(%s)へ帰港するか、%s を目指しますか?\n(目指して燃料が尽きた場合は直近の島へ強制帰還します)" % [
		Database.island(GameState.current_island).name, _onward_island_name()]
	_food_dialog.visible = true

func _build_food_dialog() -> void:
	_food_dialog = CanvasLayer.new()
	_food_dialog.layer = 25
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
		GameState.notice.emit("%s へ帰港" % Database.island(GameState.current_island).name)
		_enter_dock(GameState.current_island, true))
	hb.add_child(b1)
	var b2 := Button.new()
	b2.text = "次の島を目指す"
	b2.add_theme_font_size_override("font_size", 20)
	b2.pressed.connect(func():
		_food_dialog.visible = false
		_food_dialog_open = false
		if player:
			player.control_enabled = true
		GameState.notice.emit("%s を目指す" % _onward_island_name()))
	hb.add_child(b2)

# ---------------- クリーンアップ ----------------
func _clear_sea_actors() -> void:
	for a in fish_schools + enemies + relics_world:
		if is_instance_valid(a):
			a.queue_free()
	fish_schools.clear()
	enemies.clear()
	relics_world.clear()
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
	var want_guide := false
	var want_bullets := false
	for a in args:
		if a.begins_with("--shot"):
			want_shot = true
			want_port = a.find("port") != -1
			want_sea = a.find("sea") != -1
			want_boss = a.find("boss") != -1
			want_food = a.find("food") != -1
			want_tavern = a.find("tavern") != -1
			want_guide = a.find("guide") != -1
			want_bullets = a.find("bullets") != -1
	if not want_shot:
		return
	await get_tree().create_timer(0.6).timeout
	if want_sea:
		title.visible = false
		_on_set_sail()
		if want_guide:   # #60/#61: ガイド弧の表示確認
			GameState.unlocked_islands = [0, 1]
			GameState.visited_islands = [0]
			GameState.guide_target = {"kind": "island", "id": 1}
			await get_tree().create_timer(0.5).timeout
		if want_bullets:   # #78: 各武器の弾を静止配置して見た目を確認
			player.control_enabled = false
			var specs := [
				{"dmg": 8, "falloff": true},                 # ガトリング(黄・細)
				{"dmg": 40},                                 # 大砲(赤橙・丸)
				{"dmg": 18, "debuff": true},                 # 銛(シアン・銛型)
				{"dmg": 22, "homing": true},                 # 魚雷(緑・カプセル)
			]
			for i in specs.size():
				var proj := Area2D.new()
				proj.set_script(ProjectileScript)
				add_child(proj)
				proj.from_player = true
				proj.global_position = player.global_position + Vector2((i - 1.5) * 90.0, -120.0)
				proj.setup(Vector2.UP, specs[i])
				proj.speed = 0.0   # 静止させて撮影
			# 敵の炎弾も1つ
			var fp := Area2D.new()
			fp.set_script(ProjectileScript)
			add_child(fp)
			fp.from_player = false
			fp.fire = true
			fp.global_position = player.global_position + Vector2(270.0, -120.0)
			fp.setup(Vector2.UP, {"dmg": 20})
			fp.speed = 0.0
			await get_tree().create_timer(0.4).timeout
		if want_food:
			GameState.unlocked_islands = [0, 1]
			GameState.visited_islands = [0]
			_show_food_choice()
			await get_tree().create_timer(0.5).timeout
		if want_boss:
			player.control_enabled = false
			player.global_position = Vector2(0, 24000)
			var lineup := [
				["pirate", "king"], ["mob", "kraken"], ["mob", "wyvern"],
				["mob", "merman"], ["mob", "charybdis"], ["mob", "tiamat"], ["mob", "dagon"],
			]
			for i in lineup.size():
				var x := (float(i) - (lineup.size() - 1) / 2.0) * 260.0
				_make_enemy(lineup[i][0], lineup[i][1], player.global_position + Vector2(x, -330))
			await get_tree().create_timer(0.25).timeout
		else:
			await get_tree().create_timer(1.0).timeout
	elif want_port:
		title.visible = false
		phase = "dock"
		port_ui.open()
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
