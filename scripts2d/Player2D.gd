extends CharacterBody2D
## Player2D — 見下ろし2Dのプレイヤー船。戦車的操作(W/S前後・A/D旋回)。
## rotation=0 で船首は上(-Y)。forward = Vector2.UP.rotated(rotation)。
## 照準はマウスカーソル位置(World2D側で取得)。

const K := 6.0   # 3D数値→2D píxel換算(速度など)

var max_speed: float = 66.0
var accel: float = 40.0
var turn_speed: float = 1.2
var control_enabled: bool = true
var _ram_cd: float = 0.0
var _wake: CPUParticles2D
var _body_pts: PackedVector2Array

func _ready() -> void:
	add_to_group("player")
	max_speed = float(GameState.ship().speed) * K
	_build_visual()

func _build_visual() -> void:
	var sc := _ship_scale()
	# 船体(上向きの流線形ポリゴン)
	var hull := Polygon2D.new()
	_body_pts = PackedVector2Array([
		Vector2(0, -34), Vector2(10, -18), Vector2(13, 6), Vector2(10, 26),
		Vector2(-10, 26), Vector2(-13, 6), Vector2(-10, -18),
	])
	hull.polygon = _body_pts
	hull.color = Color(0.48, 0.34, 0.20)
	hull.scale = Vector2.ONE * sc
	add_child(hull)
	# 甲板
	var deck := Polygon2D.new()
	deck.polygon = PackedVector2Array([
		Vector2(0, -26), Vector2(7, -14), Vector2(9, 6), Vector2(7, 20),
		Vector2(-7, 20), Vector2(-9, 6), Vector2(-7, -14),
	])
	deck.color = Color(0.72, 0.58, 0.38)
	deck.scale = Vector2.ONE * sc
	add_child(deck)
	# 帆(横桁+布)
	var yard := Polygon2D.new()
	yard.polygon = PackedVector2Array([Vector2(-16, -4), Vector2(16, -4), Vector2(16, -1), Vector2(-16, -1)])
	yard.color = Color(0.35, 0.24, 0.13)
	yard.scale = Vector2.ONE * sc
	add_child(yard)
	var sail := Polygon2D.new()
	sail.polygon = PackedVector2Array([Vector2(-14, -2), Vector2(14, -2), Vector2(10, 14), Vector2(-10, 14)])
	sail.color = Color(0.92, 0.90, 0.82)
	sail.scale = Vector2.ONE * sc
	add_child(sail)
	# 衝突形状
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 13.0 * sc
	cap.height = 60.0 * sc
	col.shape = cap
	add_child(col)
	# 航跡パーティクル
	_wake = CPUParticles2D.new()
	_wake.amount = 24
	_wake.lifetime = 1.2
	_wake.position = Vector2(0, 28 * sc)
	_wake.direction = Vector2(0, 1)
	_wake.spread = 20.0
	_wake.initial_velocity_min = 10.0
	_wake.initial_velocity_max = 30.0
	_wake.scale_amount_min = 2.0
	_wake.scale_amount_max = 5.0
	_wake.color = Color(0.85, 0.95, 1.0, 0.5)
	add_child(_wake)

func _ship_scale() -> float:
	return clampf(0.9 + float(GameState.ship().armor) / 1500.0, 0.9, 1.8)

func rebuild_visual() -> void:
	for c in get_children():
		c.queue_free()
	max_speed = float(GameState.ship().speed) * K
	_build_visual()

func forward() -> Vector2:
	return Vector2.UP.rotated(rotation)

func _physics_process(delta: float) -> void:
	if _ram_cd > 0.0:
		_ram_cd -= delta
	if not control_enabled:
		velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
		move_and_slide()
		return
	var throttle := 0.0
	var steer := 0.0
	if Input.is_action_pressed("throttle_up"):
		throttle += 1.0
	if Input.is_action_pressed("throttle_down"):
		throttle -= 0.6
	if Input.is_action_pressed("turn_left"):
		steer -= 1.0
	if Input.is_action_pressed("turn_right"):
		steer += 1.0
	var spd := velocity.length()
	var steer_factor: float = clampf(spd / maxf(max_speed, 1.0), 0.2, 1.0)
	rotation += steer * turn_speed * steer_factor * delta
	velocity = velocity.move_toward(forward() * throttle * max_speed, accel * delta)
	move_and_slide()
	if _wake:
		_wake.emitting = spd > max_speed * 0.25
	_handle_ram()

func _handle_ram() -> void:
	if _ram_cd > 0.0:
		return
	var rd := float(Database.rams[GameState.ram_id].dmg)
	if rd <= 0.0 or velocity.length() < 3.0 * K:
		return
	for i in get_slide_collision_count():
		var col = get_slide_collision(i).get_collider()
		if col and col.is_in_group("enemy") and col.has_method("take_hit"):
			col.take_hit(rd * (0.5 + velocity.length() / maxf(max_speed, 1.0)), false, false)
			Audio.play("sfx_enemy_hit", -6.0)
			_ram_cd = 0.8
			return
