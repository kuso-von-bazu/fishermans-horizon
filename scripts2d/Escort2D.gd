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
	# 旗艦・敵とはすり抜ける(押し合いで陣形が崩れないように)。障害物/島とは衝突。
	collision_layer = 4
	collision_mask = 1
	if player is CollisionObject2D:
		(player as CollisionObject2D).add_collision_exception_with(self)

func _build_visual() -> void:
	for c in get_children():
		c.queue_free()
	var sc := _ship_scale()
	_sc = sc
	var tex := _build_ship_texture()
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2.ONE * PlayerScript.PIX_SCALE * sc
	add_child(spr)
	var mh: Array = PlayerScript.SHIP_MAPS.get(ship_id, PlayerScript.SHIP_MAP)
	_half_h = mh.size() * 0.5 * PlayerScript.PIX_SCALE * sc
	# 当たり判定(障害物・島用)
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 13.0 * sc
	cap.height = 60.0 * sc
	col.shape = cap
	add_child(col)
	# 航跡
	_wake = CPUParticles2D.new()
	_wake.amount = 14
	_wake.lifetime = 0.7
	_wake.local_coords = false
	_wake.direction = Vector2(0, 1)
	_wake.spread = 12.0
	_wake.initial_velocity_min = 10.0
	_wake.initial_velocity_max = 30.0
	_wake.scale_amount_min = 2.0
	_wake.scale_amount_max = 4.0
	_wake.color = Color(0.9, 0.97, 1.0, 0.5)
	_wake.position = Vector2(0, _half_h)
	_wake.z_index = -1
	add_child(_wake)
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
	add_child(lbl)

# Player2D と同じドット絵マップから船体テクスチャを作る(衝角は旗艦のみなので描かない)
func _build_ship_texture() -> ImageTexture:
	var map: Array = PlayerScript.SHIP_MAPS.get(ship_id, PlayerScript.SHIP_MAP)
	var w: int = map[0].length()
	var h := map.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = map[y]
		for x in w:
			var ch := row[x]
			if PlayerScript.PIX.has(ch):
				img.set_pixel(x, y, PlayerScript.PIX[ch])
	return ImageTexture.create_from_image(img)

# 旗艦(Player2D._ship_scale)と同じ基準でスケールを決める(艦の大きさが揃うように)
func _ship_scale() -> float:
	var extra: float = 1.15 if ship_id == "cruiser" else 1.0
	return clampf(0.9 + float(Database.ships[ship_id].armor) / 1500.0, 0.9, 1.8) * extra

func armor() -> float:
	return float(GameState.fleet[fleet_index].armor)

func take_damage(amount: float) -> void:
	if _dead or GameState.docking_locked:
		return
	var cut: float = minf(0.015 * GameState.crew_sum_of(fleet_index, "agi"), 0.40)
	var e: Dictionary = GameState.fleet[fleet_index]
	e.armor = maxf(float(e.armor) - amount * (1.0 - cut), 0.0)
	GameState.stats_changed.emit()
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
	# 陣形スロットへ追従(旗艦の向きに合わせた相対位置)
	var target: Vector2 = player.global_position + slot_offset.rotated(player.rotation)
	var to := target - global_position
	var dist := to.length()
	if dist > 6.0:
		var want: float = minf(max_speed * clampf(dist / 120.0, 0.25, 1.6), max_speed * 1.6)
		velocity = velocity.move_toward(to.normalized() * want, max_speed * 4.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, max_speed * 4.0 * delta)
	# 進行方向(ほぼ旗艦と同じ向き)へ艦首を向ける
	var face: Vector2 = player.forward() if velocity.length() < 12.0 else velocity.normalized()
	rotation = lerp_angle(rotation, face.angle() + PI / 2.0, 8.0 * delta)
	move_and_slide()
	if _wake:
		_wake.emitting = velocity.length() > max_speed * 0.15
	_auto_fire(delta)

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
