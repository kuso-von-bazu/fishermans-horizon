extends CharacterBody2D
## Escort2D — 船団の僚艦(2番艦〜5番艦)(#196)。
## 旗艦(プレイヤー)の陣形スロットへ追従し、ロックオン中の敵を自動で攻撃する。
## 装甲が0になるとその艦だけ離脱(queue_free)し、World2D側で「X番艦は離脱した!」を出す。

const K := 6.0
const PlayerScript = preload("res://scripts2d/Player2D.gd")
const ProjectileScript = preload("res://scripts2d/Projectile2D.gd")

signal detached(fleet_index: int)

var fleet_index: int = 1          # GameState.fleet の添字
var ship_id: String = "skiff"
var max_speed: float = 66.0
var slot_offset: Vector2 = Vector2(120, 120)   # 旗艦から見た陣形上の相対位置(ローカル)
var _sc: float = 1.0
var _half_h: float = 42.0
var _cooldowns: Array = [0.0, 0.0, 0.0, 0.0]
var _ammo: Array = [0, 0, 0, 0]
var _wake: CPUParticles2D
var _smoke: CPUParticles2D
var _sprays: Array = []
var _half_w: float = 30.0
var _label: Label
var _ram_cd: float = 0.0
var _bump_cd: float = 0.0     # #193再3: 障害物の接触ダメージのクールダウン
var _burn_t: float = 0.0      # #215: 炎上(旗艦と同様)
var _burn_dps: float = 0.0
var _poison_t: float = 0.0    # #215: 毒のスリップ
var _poison_dps: float = 0.0
var _flame: CPUParticles2D
# #224: 陣形スキル(僚艦も発動する)
var charge_t: float = 0.0
var _charge_hit: Array = []
var volley_queue: Array = []
var volley_target: Node2D = null
var _charge_sprays: Array = []   # #224再: 突撃中の大きなしぶき(左右)
var _dead: bool = false
var player: Node2D

func setup(idx: int) -> void:
	fleet_index = idx
	ship_id = str(GameState.fleet[idx].ship_id)

func _ready() -> void:
	add_to_group("fleet_ship")
	max_speed = float(Database.ships[ship_id].speed) * K
	player = get_tree().get_first_node_in_group("player")
	_build_visual()
	_reset_ammo()
	# #227: 旗艦(1)・敵(2)・島/障害物(1)のいずれとも重ならないようにする
	# (以前は陣形が崩れないよう旗艦・敵とすり抜けていたが、重なり解消を優先)
	collision_layer = 4
	collision_mask = 3

func _build_visual() -> void:
	for c in get_children():
		c.queue_free()
	var sc := _ship_scale()
	_sc = sc
	var map: Array = PlayerScript.SHIP_MAPS.get(ship_id, PlayerScript.SHIP_MAP)
	var mw: int = map[0].length()
	var half_cols := 0.0
	for row in map:
		for x in mw:
			if row[x] != ".":
				half_cols = maxf(half_cols, absf(float(x) + 0.5 - float(mw) / 2.0))
	_half_w = half_cols * PlayerScript.PIX_SCALE * sc
	_half_h = (float(map.size()) / 2.0 - 1.0) * PlayerScript.PIX_SCALE * sc
	var spr := Sprite2D.new()
	spr.texture = _build_ship_texture()
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2.ONE * PlayerScript.PIX_SCALE * sc
	spr.z_index = 2
	add_child(spr)
	# 当たり判定(障害物・島用)
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 13.0 * sc
	cap.height = 60.0 * sc
	col.shape = cap
	add_child(col)
	# #196再: 煙突の煙・航跡・舷側しぶきを旗艦と同じ表現に揃える
	var smoke := CPUParticles2D.new()
	smoke.amount = 20
	smoke.lifetime = 3.8
	smoke.local_coords = false
	smoke.position = Vector2(0, -6 * sc)
	smoke.spread = 180.0
	smoke.gravity = Vector2.ZERO
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 5.0 * sc
	smoke.initial_velocity_min = 0.0
	smoke.initial_velocity_max = 0.0
	smoke.scale_amount_min = 4.0
	smoke.scale_amount_max = 8.0
	var scurve := Curve.new()
	scurve.add_point(Vector2(0.0, 0.6))
	scurve.add_point(Vector2(1.0, 2.6))
	smoke.scale_amount_curve = scurve
	var sramp := Gradient.new()
	sramp.set_color(0, Color(0.88, 0.88, 0.9, 0.42))
	sramp.set_color(1, Color(0.9, 0.9, 0.92, 0.0))
	smoke.color_ramp = sramp
	smoke.z_index = 3
	add_child(smoke)
	_smoke = smoke
	_wake = CPUParticles2D.new()
	_wake.amount = 70
	_wake.lifetime = 3.2
	_wake.local_coords = false
	_wake.position = Vector2(0, _half_h)
	_wake.spread = 12.0
	_wake.gravity = Vector2.ZERO
	_wake.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_wake.emission_rect_extents = Vector2(_half_w, 1.5)
	_wake.initial_velocity_min = 0.0
	_wake.initial_velocity_max = 3.0
	_wake.scale_amount_min = 2.5
	_wake.scale_amount_max = 6.0
	var wramp := Gradient.new()
	wramp.set_color(0, Color(0.9, 0.97, 1.0, 0.5))
	wramp.set_color(1, Color(0.9, 0.97, 1.0, 0.0))
	_wake.color_ramp = wramp
	add_child(_wake)
	_sprays = []
	for side in [-1.0, 1.0]:
		var spray := CPUParticles2D.new()
		spray.amount = 16
		spray.lifetime = 1.0
		spray.local_coords = false
		spray.position = Vector2(side * _half_w, -10 * sc)
		spray.spread = 60.0
		spray.gravity = Vector2.ZERO
		spray.initial_velocity_min = 4.0
		spray.initial_velocity_max = 12.0
		spray.scale_amount_min = 1.5
		spray.scale_amount_max = 3.5
		var spr_ramp := Gradient.new()
		spr_ramp.set_color(0, Color(0.95, 1.0, 1.0, 0.45))
		spr_ramp.set_color(1, Color(0.95, 1.0, 1.0, 0.0))
		spray.color_ramp = spr_ramp
		add_child(spray)
		_sprays.append(spray)
	# #224再: 突撃中だけ舷側へ大きく跳ね上がるしぶき(旗艦と同じ演出)
	_charge_sprays = []
	for side2 in [-1.0, 1.0]:
		var cs := CPUParticles2D.new()
		cs.emitting = false
		cs.amount = 90
		cs.lifetime = 0.5
		# 船に張り付く座標系にして、舷側で大きく割れる波として見せる
		cs.local_coords = true
		cs.position = Vector2(side2 * _half_w * 0.9, 2 * sc)
		cs.direction = Vector2(side2, 0.62).normalized()   # #224再3: 斜め後ろへ跳ねる
		cs.spread = 34.0
		cs.gravity = Vector2.ZERO
		cs.initial_velocity_min = 55.0
		cs.initial_velocity_max = 135.0
		cs.damping_min = 90.0
		cs.damping_max = 150.0
		cs.scale_amount_min = 10.0
		cs.scale_amount_max = 22.0
		var cramp := Gradient.new()
		cramp.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
		cramp.set_color(1, Color(0.70, 0.90, 1.0, 0.0))
		cs.color_ramp = cramp
		cs.z_index = 3
		add_child(cs)
		_charge_sprays.append(cs)
	# #215: 炎上アニメ(炎上中のみ噴く)
	_flame = CPUParticles2D.new()
	_flame.amount = 18
	_flame.lifetime = 0.7
	_flame.emitting = false
	_flame.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_flame.emission_rect_extents = Vector2(12.0 * sc, 20.0 * sc)
	_flame.direction = Vector2(0, -1)
	_flame.gravity = Vector2(0, -80)
	_flame.spread = 20.0
	_flame.initial_velocity_min = 20.0
	_flame.initial_velocity_max = 50.0
	_flame.scale_amount_min = 2.0
	_flame.scale_amount_max = 5.0
	var framp := Gradient.new()
	framp.set_color(0, Color(1.0, 0.85, 0.35, 0.9))
	framp.set_color(1, Color(0.7, 0.15, 0.05, 0.0))
	_flame.color_ramp = framp
	_flame.z_index = 5
	add_child(_flame)
	# 艦名ラベル
	var lbl := Label.new()
	lbl.text = GameState.fleet_label(fleet_index)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.position = Vector2(-60, -_half_h - 34)
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 4
	add_child(lbl)
	_label = lbl

# Player2D と同じドット絵マップから船体テクスチャを作る。
# #196再2: 僚艦にも衝角を装着できるので、旗艦と同じ描き方で衝角を描く。
func _build_ship_texture() -> ImageTexture:
	var map: Array = PlayerScript.SHIP_MAPS.get(ship_id, PlayerScript.SHIP_MAP)
	var w: int = map[0].length()
	var h := map.size()
	var ram: String = str(GameState.fleet[fleet_index].get("ram", "none"))
	var with_ram: bool = ram != "none"
	# 船幅(実際の最大ビーム)を走査して衝角のサイズを船体に比例させる
	var beam := 0
	for row0 in map:
		var lo := -1
		var hi := -1
		for x0 in w:
			if row0[x0] != ".":
				if lo < 0:
					lo = x0
				hi = x0
		if lo >= 0:
			beam = maxi(beam, hi - lo + 1)
	var ram_extend := int(round(float(h) / 4.0)) if with_ram else 0
	var embed := int(round(float(h) / 6.0)) if with_ram else 0
	var img := Image.create(w, h + ram_extend, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if with_ram:
		var rc := Color(0.78, 0.82, 0.88) if ram == "steel" else Color(0.5, 0.46, 0.4)
		var rc_edge := rc.darkened(0.28)
		var cx := w / 2
		var base_half := float(beam) / 4.0
		var ram_len := ram_extend + embed
		for ry in ram_len:
			var t: float = float(ry) / float(maxi(ram_len - 1, 1))
			var half: int = int(round(base_half * pow(t, 1.25)))
			for x1 in range(cx - half, cx + half + 1):
				if x1 >= 0 and x1 < w:
					var edge: bool = half >= 2 and (x1 == cx - half or x1 == cx + half)
					img.set_pixel(x1, ry, rc_edge if edge else rc)
	for y in h:
		var row: String = map[y]
		for x in w:
			var ch := row[x]
			if PlayerScript.PIX.has(ch):
				img.set_pixel(x, y + ram_extend, PlayerScript.PIX[ch])
	return ImageTexture.create_from_image(img)

# 旗艦(Player2D._ship_scale)と同じ基準でスケールを決める(艦の大きさが揃うように)
func _ship_scale() -> float:
	var extra: float = 1.15 if ship_id == "cruiser" else 1.0
	return clampf(0.9 + float(Database.ships[ship_id].armor) / 1500.0, 0.9, 1.8) * extra

# #224: 突撃で貫いた敵に衝角ダメージ(1回の突撃につき同じ敵へは1度だけ)
# #224再6: 突撃中の貫通(旗艦と同じ理由で、敵側からの押し返しも例外で無効化する)
var _charge_excepted: Array = []

func _apply_charge_exceptions() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is CollisionObject2D and not _charge_excepted.has(e):
			add_collision_exception_with(e)
			_charge_excepted.append(e)

func _clear_charge_exceptions() -> void:
	for e in _charge_excepted:
		if is_instance_valid(e) and e is CollisionObject2D:
			remove_collision_exception_with(e)
	_charge_excepted.clear()

func _charge_pierce() -> void:
	var ram: String = str(GameState.fleet[fleet_index].get("ram", "none"))
	var rd := float(Database.rams[ram].dmg) if Database.rams.has(ram) else 0.0
	# #224再: 衝角なしでも船体の体当たりとして一定のダメージが入る
	if rd <= 0.0:
		rd = Database.HULL_RAM_DMG
	var reach := 34.0 * _sc
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		if e.get("aerial") == true or _charge_hit.has(e.get_instance_id()):
			continue
		var er: float = float(e.get("_radius")) if e.get("_radius") != null else 30.0
		if global_position.distance_to(e.global_position) > reach + er:
			continue
		_charge_hit.append(e.get_instance_id())
		var dmg: float = rd * 3.5   # 3倍速の突撃ぶん(旗艦の 0.5+速度比 と同等)
		e.take_hit(dmg, false, false)
		Audio.play("sfx_cannon", -9.0, 1.3)

# #224: 一斉射撃
func start_volley(target: Node2D) -> void:
	volley_target = target
	volley_queue.clear()
	var wp: Array = GameState.fleet[fleet_index].weapons
	for i in mini(4, wp.size()):
		var wid: String = str(wp[i])
		if wid == "" or not Database.weapons.has(wid):
			continue
		var w: Dictionary = Database.weapons[wid]
		volley_queue.append({"slot": i, "left": int(ceil(float(w.mag) / 2.0)), "timer": 0.0})

func _tick_volley(delta: float) -> void:
	if volley_queue.is_empty():
		return
	# #224再: 非ロックオン時(volley_target が null)は前方へ撃つので中断しない
	if volley_target != null and not is_instance_valid(volley_target):
		volley_queue.clear()
		return
	var wp: Array = GameState.fleet[fleet_index].weapons
	for q in volley_queue:
		q.timer -= delta
		if q.timer > 0.0 or int(q.left) <= 0:
			continue
		var w: Dictionary = Database.weapons[str(wp[int(q.slot)])]
		q.timer = float(w.cooldown) / 3.0
		q.left = int(q.left) - 1
		# #224再: ロック中はロック対象へ、非ロック時は自艦の前方へ
		var dir := Vector2.UP.rotated(rotation) if volley_target == null else (volley_target.global_position - global_position).normalized()
		var w2 := w.duplicate()
		w2.dmg = float(w.dmg) * GameState.attack_mult_of(fleet_index)
		w2["debuff_kind"] = str(GameState.fleet[fleet_index].get("harpoon", "slip"))
		Audio.play(str(w.get("sfx", "sfx_gun")), -14.0, randf_range(0.95, 1.05))
		var proj := Area2D.new()
		proj.set_script(ProjectileScript)
		get_parent().add_child(proj)
		proj.global_position = global_position + dir * 40.0
		proj.from_player = true
		proj.setup(dir, w2, volley_target if str(w.kind) == "lock" else null)
	volley_queue = volley_queue.filter(func(q): return int(q.left) > 0)

# #212: 敵と同じ円形の装甲ゲージを描く(上から時計回り。残量で緑→赤)
func _draw() -> void:
	var maxa := float(Database.ships[ship_id].armor)
	var frac := clampf(armor() / maxf(maxa, 1.0), 0.0, 1.0)
	var r := maxf(_half_w, _half_h) + 10.0
	draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	if frac > 0.0:
		var col := Color(1, 0.2, 0.15).lerp(Color(0.35, 1.0, 0.4), frac)
		draw_arc(Vector2.ZERO, r, -PI / 2, -PI / 2 + TAU * frac, 40, col, 5.0)

# #215: 旗艦と同様に炎上する
func ignite(dps := 4.0) -> void:
	if _dead or GameState.docking_locked:
		return
	_burn_t = 4.5
	_burn_dps = dps
	GameState.notice.emit("%sが炎上!" % GameState.fleet_label(fleet_index))

# #215: ダゴンの毒などのスリップダメージ
func apply_poison(dur: float, dps: float) -> void:
	if _dead or GameState.docking_locked:
		return
	if _poison_t <= 0.0:
		GameState.notice.emit("%sが毒液を浴びた!" % GameState.fleet_label(fleet_index))
	_poison_t = maxf(_poison_t, dur)
	_poison_dps = dps

# 炎上・毒の時間経過(敏捷カットは掛からない=旗艦のtick_slipsと同じ扱い)
func _tick_slips(delta: float) -> void:
	var e: Dictionary = GameState.fleet[fleet_index]
	var dmg := 0.0
	if _burn_t > 0.0:
		_burn_t -= delta
		dmg += _burn_dps * delta
	if _poison_t > 0.0:
		_poison_t -= delta
		dmg += _poison_dps * delta
	if dmg > 0.0:
		e.armor = maxf(float(e.armor) - dmg, 0.0)
		GameState.stats_changed.emit()
		queue_redraw()
		if float(e.armor) <= 0.0:
			_detach()
	if _flame:
		_flame.emitting = _burn_t > 0.0

# #193再3: 障害物に接触すると旗艦と同様に小ダメージ
func _check_obstacle_bump() -> void:
	if _bump_cd > 0.0 or GameState.docking_locked or _dead:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o := c.get_collider()
		if o == null or not (o is Node) or not (o as Node).is_in_group("obstacle"):
			continue
		var maxa := float(Database.ships[ship_id].armor)
		var impact: float = clampf(player.velocity.length() / maxf(player.max_speed, 1.0), 0.0, 1.0)
		var dmg: float = clampf(maxa * 0.012, 3.0, 20.0) * (0.6 + 0.8 * impact)
		take_damage(dmg)
		var nm := "流氷" if str(o.get("kind")) == "ice" else "岩礁"
		GameState.notice.emit("%sが%sに接触! %d ダメージ" % [GameState.fleet_label(fleet_index), nm, int(dmg)])
		_bump_cd = 1.2
		return

func armor() -> float:
	return float(GameState.fleet[fleet_index].armor)

func take_damage(amount: float) -> void:
	if _dead or GameState.docking_locked:
		return
	var cut: float = minf(0.015 * GameState.crew_sum_of(fleet_index, "agi"), 0.40)
	var e: Dictionary = GameState.fleet[fleet_index]
	var dealt := amount * (1.0 - cut)
	e.armor = maxf(float(e.armor) - dealt, 0.0)
	# #215再2: 旗艦(GameState.damage_player)と同じく、被弾時12%で炎上する
	if amount >= 3.0 and _burn_t <= 0.0 and randf() < 0.12:
		_burn_t = 4.5
		_burn_dps = 2.5 + amount * 0.12
		GameState.notice.emit("%sが炎上!" % GameState.fleet_label(fleet_index))
	GameState.stats_changed.emit()
	queue_redraw()   # #212
	if float(e.armor) <= 0.0:
		_detach()

func _detach() -> void:
	if _dead:
		return
	_dead = true
	GameState.fleet[fleet_index]["damaged"] = true   # 次回出港時に修理費
	detached.emit(fleet_index)
	queue_free()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	for i in _cooldowns.size():
		if _cooldowns[i] > 0.0:
			_cooldowns[i] -= delta
	if _bump_cd > 0.0:
		_bump_cd -= delta
	_tick_slips(delta)   # #215: 炎上・毒
	# #196再: 独自に動かず、旗艦の操作(位置・向き)にそのまま追従する。
	# 陣形上の相対位置を旗艦の向きで回した点を目標にし、そこへ剛体的に張り付く。
	var target: Vector2 = player.global_position + slot_offset.rotated(player.rotation)
	var to := target - global_position
	velocity = to / maxf(delta, 0.0001)          # 目標へ張り付く速度
	# #196再2: 陣形切替などで目標が大きく動いても、僚艦の速度は船団全体の速度までに制限する
	# #224再: 突撃中は旗艦が3倍速で走るので、僚艦も同じだけ加速して隊列を保つ
	var cap: float = player.max_speed * (3.0 if charge_t > 0.0 else 1.0)
	if velocity.length() > cap:
		velocity = velocity.normalized() * cap
	rotation = player.rotation                    # 向きも旗艦と同じ
	queue_redraw()                                # #212: 装甲ゲージの更新
	if _label:
		# ラベルは船と一緒に回ると裏返るので、常に画面上向き・船の真上に置く
		_label.rotation = -rotation
		_label.position = Vector2(-60, -_half_h - 34).rotated(-rotation)
	# #224: 突撃中は貫通のため敵との衝突を外す
	if charge_t > 0.0:
		charge_t -= delta
		collision_mask = 1          # #224再5: 敵(2)を外して貫通
		_apply_charge_exceptions()  # #224再6: 敵側からの押し返しも無効化する
		if charge_t <= 0.0:
			collision_mask = 3
			_clear_charge_exceptions()
			_charge_hit.clear()
	# #224再: 突撃中だけ舷側の大しぶきを噴かせる
	for cs in _charge_sprays:
		if is_instance_valid(cs):
			cs.emitting = charge_t > 0.0
	move_and_slide()
	if charge_t > 0.0:
		_charge_pierce()
	_tick_volley(delta)
	_check_obstacle_bump()   # #193再3
	var moving: bool = player.velocity.length() > player.max_speed * 0.15
	var reversing: bool = player.velocity.dot(player.forward()) < -1.0
	if _wake:
		_wake.emitting = moving
		_wake.position = Vector2(0, -_half_h) if reversing else Vector2(0, _half_h)
		_wake.direction = Vector2(0, -1) if reversing else Vector2(0, 1)
	if _smoke:
		_smoke.gravity = -player.velocity * 0.7
	for spray in _sprays:
		spray.emitting = player.velocity.length() > player.max_speed * 0.2 and not reversing
	_auto_fire(delta)
	_handle_ram(delta)

# #196再2: 僚艦も衝角で体当たりできる。旗艦と同じく前方の敵を近接判定で突く。
func _handle_ram(delta: float) -> void:
	# #224再5: 突撃中は _charge_pierce が判定するので通常の衝角判定は止める
	if charge_t > 0.0:
		return
	if _ram_cd > 0.0:
		_ram_cd -= delta
		return
	if GameState.docking_locked:
		return
	var ram: String = str(GameState.fleet[fleet_index].get("ram", "none"))
	var rd := float(Database.rams[ram].dmg) if Database.rams.has(ram) else 0.0
	if rd <= 0.0:
		return
	# 船団としての進行速度で判定する(僚艦は陣形追従で速度が変動するため)
	var pv: Vector2 = player.velocity
	if pv.length() < 3.0 * K:
		return
	if pv.dot(player.forward()) <= 0.0:
		return   # #54再: 船団がバックしている間は衝角ダメージなし
	var reach := 28.0 * _sc
	var vdir := forward()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		if e.get("aerial") == true:
			continue   # 空中の敵には衝角は届かない
		var to_e: Vector2 = e.global_position - global_position
		var er: float = float(e.get("_radius")) if e.get("_radius") != null else 30.0
		if to_e.length() > reach + er:
			continue
		if vdir.dot(to_e.normalized()) < 0.3:
			continue   # 進行方向(前方)の敵だけ
		var dmg := rd * (0.5 + pv.length() / maxf(player.max_speed, 1.0))
		e.take_hit(dmg, false, false)
		GameState.notice.emit("%sの衝角の一撃! %d ダメージ" % [GameState.fleet_label(fleet_index), int(dmg)])
		if e is CharacterBody2D:
			e.velocity += vdir * 220.0
		Audio.play("sfx_cannon", -8.0, 1.3)
		_ram_cd = 0.8
		return

func forward() -> Vector2:
	return Vector2.UP.rotated(rotation)

func _reset_ammo() -> void:
	_ammo = [0, 0, 0, 0]
	var wp: Array = GameState.fleet[fleet_index].weapons
	for i in mini(4, wp.size()):
		var wid: String = str(wp[i])
		if wid != "" and Database.weapons.has(wid):
			_ammo[i] = int(Database.weapons[wid].mag)

# #196: 僚艦はロックオンした敵を自動的に攻撃する
func _auto_fire(_delta: float) -> void:
	if GameState.docking_locked:
		return
	var world := get_parent()
	if world == null or world.get("lock_target") == null:
		return
	var tgt = world.lock_target
	if not is_instance_valid(tgt):
		return
	var to: Vector2 = tgt.global_position - global_position
	var wp: Array = GameState.fleet[fleet_index].weapons
	for i in mini(4, wp.size()):
		var wid: String = str(wp[i])
		if wid == "" or not Database.weapons.has(wid):
			continue
		var w: Dictionary = Database.weapons[wid]
		if _cooldowns[i] > 0.0:
			continue
		var is_lock: bool = str(w.kind) == "lock"
		# 魚雷は空中の敵には当たらないので撃たない
		if is_lock and tgt.get("aerial") == true:
			continue
		if to.length() > float(w.range) * K * 1.2:
			continue
		var dir := to.normalized()
		# #196: 味方に射線が重なるときは撃たない(魚雷は射線を無視して撃てる)
		if not is_lock and _line_blocked(dir, to.length()):
			continue
		var w2 := w.duplicate()
		w2.dmg = float(w.dmg) * GameState.attack_mult_of(fleet_index)
		w2["debuff_kind"] = str(GameState.fleet[fleet_index].get("harpoon", "slip"))   # #196再: この艦の銛の効果
		Audio.play(str(w.get("sfx", "sfx_gun")), -12.0, randf_range(0.95, 1.05))
		var proj := Area2D.new()
		proj.set_script(ProjectileScript)
		world.add_child(proj)
		proj.global_position = global_position + dir * 40.0
		proj.from_player = true
		proj.setup(dir, w2, tgt if is_lock else null)
		_consume(i, w)

func _consume(i: int, w: Dictionary) -> void:
	_ammo[i] = int(_ammo[i]) - 1
	if _ammo[i] <= 0:
		_cooldowns[i] = float(w.reload)
		_ammo[i] = int(w.mag)
	else:
		_cooldowns[i] = float(w.cooldown)

# 射線上に味方(旗艦・他の僚艦)がいるか
func _line_blocked(dir: Vector2, dist: float) -> bool:
	var mates: Array = [player]
	mates.append_array(get_tree().get_nodes_in_group("fleet_ship"))
	for m in mates:
		if m == self or not is_instance_valid(m):
			continue
		var rel: Vector2 = m.global_position - global_position
		var along := rel.dot(dir)
		if along <= 0.0 or along > dist:
			continue
		if absf(rel.cross(dir)) < 46.0:   # 射線からの横ずれが船体幅より小さい=重なっている
			return true
	return false
