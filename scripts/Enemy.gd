extends CharacterBody3D
const Models = preload("res://scripts/Models.gd")
## Enemy — 近海の主/戦闘モブ/海賊の共通実体。すべて立体3Dモデル(Models.gd)で表示する。
## kind: "mob"(戦闘モブ=漁獲可) / "pirate"(首=賞金) / "lord"(主=漁獲+賞金)

signal died(enemy)

var kind: String = "mob"
var id: String = "narwhal"
var def: Dictionary = {}
var hp: float = 50.0
var max_hp: float = 50.0
var dmg: float = 5.0
var ranged: bool = false
var aerial: bool = false
var fly_height: float = 0.0
var speed: float = 7.0
var attack_range: float = 9.0
var attack_cd: float = 1.4
var _atk_timer: float = 0.0
var _slip: float = 0.0
var _debuff_t: float = 0.0
var _scale: float = 1.0
var _rig: Node3D
var _name_label: Label3D
var player: Node3D
var pair_partner: Node = null
var _bob_phase: float = 0.0

func setup(p_kind: String, p_id: String) -> void:
	kind = p_kind
	id = p_id
	match kind:
		"mob": def = Database.combat_mobs[id]
		"pirate": def = Database.pirates[id]
		"lord": def = Database.lords[id]
	hp = float(def.hp)
	max_hp = hp
	dmg = float(def.dmg)
	ranged = bool(def.get("ranged", false))
	aerial = bool(def.get("aerial", false))
	if aerial:
		fly_height = 11.0
	if kind == "lord":
		speed = 5.0
		attack_range = 12.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("sonar_enemy")
	var col_color: Color = def.get("color", Color(0.6, 0.3, 0.3))
	# モデル倍率
	if kind == "pirate":
		_scale = clampf(0.7 + max_hp / 600.0, 0.8, 1.6)
	else:
		_scale = clampf(0.7 + max_hp / 700.0, 0.8, 4.2)
	# リグ(モデルの親。揺れ・回転演出用)
	_rig = Node3D.new()
	add_child(_rig)
	var model: Node3D
	if kind == "pirate":
		model = Models.ship(_scale, col_color, Color(0.55, 0.5, 0.42), true)
	else:
		model = Models.sea_beast(id, col_color, _scale)
	_rig.add_child(model)
	# 衝突形状(モデル外形に概ね合わせる)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if kind == "pirate":
		box.size = Vector3(2.6 * _scale, 2.2 * _scale, 7.0 * _scale)
	else:
		box.size = Vector3(2.4 * _scale, 2.2 * _scale, 4.4 * _scale)
	col.shape = box
	col.position.y = 0.6 * _scale
	add_child(col)
	# 名前+HP ラベル
	_name_label = Label3D.new()
	_name_label.text = def.name
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position.y = 3.4 * _scale + fly_height + 1.0
	_name_label.font_size = 40
	_name_label.outline_size = 8
	_name_label.no_depth_test = true
	_name_label.modulate = Color(1, 0.7, 0.7) if kind != "mob" else Color(0.8, 1, 0.8)
	add_child(_name_label)
	_bob_phase = randf() * TAU
	var ps := get_tree().get_first_node_in_group("player")
	if ps:
		player = ps
	position.y = fly_height

func take_hit(amount: float, slip: bool, debuff: bool) -> void:
	var mult := 1.0
	if _debuff_t > 0.0:
		mult = 1.25
	hp -= amount * mult
	if slip and kind == "pirate":
		_slip += amount * 0.6
	if debuff and kind == "lord":
		_debuff_t = 6.0
	_flash()
	if hp <= 0:
		_die()

func _flash() -> void:
	# 被弾でリグを一瞬スケールパンチ
	if _rig:
		_rig.scale = Vector3.ONE * 1.12
		var tw := create_tween()
		tw.tween_property(_rig, "scale", Vector3.ONE, 0.18)

func _physics_process(delta: float) -> void:
	if _slip > 0.0:
		var tick: float = minf(_slip, 8.0 * delta)
		hp -= tick
		_slip -= tick
		if hp <= 0:
			_die()
			return
	if _debuff_t > 0.0:
		_debuff_t -= delta
	if _name_label:
		_name_label.text = "%s  %d/%d" % [def.name, maxi(int(hp), 0), int(max_hp)]
	# 揺れ(水面/飛行のバウンド)
	if _rig:
		_bob_phase += delta * 1.6
		_rig.position.y = sin(_bob_phase) * (0.12 if kind == "pirate" else 0.25) * _scale
		_rig.rotation.z = sin(_bob_phase * 0.7) * 0.04
	if not is_instance_valid(player):
		return
	var to: Vector3 = player.global_position - global_position
	to.y = 0
	var dist := to.length()
	# プレイヤーの方を向く(モデル前方 -Z をプレイヤーへ)
	if dist > 0.5:
		var dir := to.normalized()
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 2.5)
	if dist > attack_range:
		var d := to.normalized()
		velocity.x = d.x * speed
		velocity.z = d.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		_attack(delta, dist)
	velocity.y = 0
	move_and_slide()
	position.y = fly_height

func _attack(delta: float, dist: float) -> void:
	_atk_timer -= delta
	if _atk_timer > 0:
		return
	_atk_timer = attack_cd
	if id == "leviathan":
		_leviathan_attack(dist)
	elif id == "hydra":
		_ranged_attack(true)
	elif ranged:
		# 遠隔敵: 離れていれば射撃、接近されたら近接も行う
		if dist <= attack_range * 0.6:
			_damage_player(dmg)
		else:
			_ranged_attack(false)
	elif dist <= attack_range:
		_damage_player(dmg)

func _ranged_attack(is_fire: bool) -> void:
	var proj = preload("res://scripts/Projectile.gd").new()
	get_parent().add_child(proj)
	proj.global_position = global_position + Vector3(0, 1.5 + fly_height, 0)
	proj.from_player = false
	proj.fire = is_fire
	var dir := (player.global_position - global_position).normalized()
	proj.setup(dir, {"dmg": dmg, "slip": false, "debuff": false, "homing": false})

func _leviathan_attack(dist: float) -> void:
	if dist <= attack_range * 1.4:
		_damage_player(dmg * 1.3)
		GameState.notice.emit("レヴィアタンの薙ぎ払い!")
	else:
		_damage_player(dmg)
		GameState.notice.emit("レヴィアタンの津波!")

func _damage_player(amount: float) -> void:
	GameState.run_armor = maxf(GameState.run_armor - amount, 0.0)
	GameState.stats_changed.emit()

func _die() -> void:
	died.emit(self)
	match kind:
		"mob":
			if not GameState.add_cargo(id):
				GameState.notice.emit("%s を仕留めたが魚倉が満杯" % def.name)
		"pirate":
			GameState.add_head(id)
			GameState.add_fame(int(def.get("fame", 1)))
			GameState.notice.emit("%s を撃退(首を確保 / 名声+%d)" % [def.name, int(def.get("fame", 1))])
		"lord":
			if GameState.free_hold() >= int(def.cap):
				GameState.add_cargo(id, int(def.cap))
			var is_pair: bool = bool(def.get("pair", false))
			var partner_alive: bool = is_pair and is_instance_valid(pair_partner) and not pair_partner.is_queued_for_deletion()
			if is_pair and partner_alive:
				GameState.notice.emit("番いの片割れ %s を倒した。もう1体も討て!" % def.name)
			else:
				if not GameState.defeated_lords.has(id) and not GameState.claimed_lords.has(id):
					GameState.defeated_lords.append(id)
				GameState.notice.emit("近海の主 %s を討伐! 賞金は酒場で受領" % def.name)
	queue_free()
