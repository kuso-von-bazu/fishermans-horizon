extends Area2D
## Projectile2D — 弾(ガトリング/大砲/銛/魚雷/敵弾)。魚雷は target を追尾。

const K := 6.0

var speed: float = 480.0
var dmg: float = 5.0
var life: float = 2.6
var slip: bool = false
var debuff: bool = false
var homing: bool = false
var fire: bool = false
var falloff: bool = false   # #63: ガトリング系は距離で威力減衰
var target: Node2D = null
var dir: Vector2 = Vector2.UP
var from_player: bool = true
var _t: float = 0.0
var _travel: float = 0.0

func setup(p_dir: Vector2, w: Dictionary, p_target: Node2D = null) -> void:
	dmg = float(w.get("dmg", 5))
	speed = (70.0 + float(w.get("dmg", 5)) * 0.3) * K
	slip = bool(w.get("slip", false))
	debuff = bool(w.get("debuff", false))
	homing = bool(w.get("homing", false))
	falloff = bool(w.get("falloff", false))
	target = p_target
	dir = p_dir.normalized()

func _ready() -> void:
	# #78: 攻撃の種類で弾の見た目を変える
	var mesh := Polygon2D.new()
	var r := 4.0
	if homing:
		# 魚雷: 細長いカプセル型(尾びれ付き)
		mesh.polygon = PackedVector2Array([
			Vector2(-3, -9), Vector2(0, -12), Vector2(3, -9), Vector2(3, 7),
			Vector2(6, 12), Vector2(0, 9), Vector2(-6, 12), Vector2(-3, 7)])
		mesh.color = Color(0.65, 0.9, 1.0) if from_player else Color(0.95, 0.4, 0.55)
		r = 5.0
	elif falloff:
		# ガトリング: 細い曳光弾
		mesh.polygon = PackedVector2Array([
			Vector2(-1.6, -8), Vector2(1.6, -8), Vector2(1.6, 8), Vector2(-1.6, 8)])
		mesh.color = Color(1.0, 0.95, 0.5) if from_player else Color(1.0, 0.5, 0.3)
		r = 3.0
	elif debuff:
		# 銛: 長い柄+返しのある穂先
		mesh.polygon = PackedVector2Array([
			Vector2(0, -14), Vector2(4, -7), Vector2(1.4, -7), Vector2(1.4, 12),
			Vector2(-1.4, 12), Vector2(-1.4, -7), Vector2(-4, -7)])
		mesh.color = Color(0.8, 0.85, 0.9)
	elif fire:
		# 炎弾: ゆらめく火の玉
		var pts_f := PackedVector2Array()
		for i in 10:
			var a := TAU * i / 10.0
			var rr := 6.0 if i % 2 == 0 else 3.5
			pts_f.append(Vector2(cos(a), sin(a)) * rr)
		mesh.polygon = pts_f
		mesh.color = Color(1.0, 0.5, 0.15)
		r = 5.0
	else:
		# 砲弾: 大きめの鉄球
		var pts := PackedVector2Array()
		for i in 12:
			var a := TAU * i / 12.0
			pts.append(Vector2(cos(a), sin(a)) * 6.0)
		mesh.polygon = pts
		mesh.color = Color(0.35, 0.36, 0.4) if from_player else Color(0.55, 0.2, 0.2)
		r = 6.0
	rotation = dir.angle() + PI / 2
	add_child(mesh)
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = r + 2.0
	col.shape = sh
	add_child(col)
	body_entered.connect(_on_hit)
	if homing:
		# 泡のトレイル(#30)
		var trail := CPUParticles2D.new()
		trail.amount = 20
		trail.lifetime = 0.6
		trail.initial_velocity_min = 4.0
		trail.initial_velocity_max = 14.0
		trail.scale_amount_min = 1.5
		trail.scale_amount_max = 3.0
		trail.color = Color(0.8, 0.95, 1.0, 0.6)
		add_child(trail)
		life = 4.0

func _physics_process(delta: float) -> void:
	_t += delta
	if homing:
		if is_instance_valid(target):
			# 旋回力が徐々に立ち上がり弧を描いて追う(#30)
			var steer: float = lerpf(1.2, 7.0, minf(_t / 0.9, 1.0))
			var want := (target.global_position - global_position).normalized()
			dir = dir.lerp(want, steer * delta).normalized()
		# 蛇行(ホーミングらしい揺れ)
		var wob := dir.rotated(PI / 2) * sin(_t * 9.0) * 0.35
		global_position += (dir + wob).normalized() * speed * delta
		rotation = dir.angle() + PI / 2   # #78: 魚雷は進行方向を向く
	else:
		global_position += dir * speed * delta
	_travel += speed * delta
	life -= delta
	if life <= 0:
		queue_free()

# #63: 一定距離(45*K)を超えると線形減衰、最低35%まで
func _eff_dmg() -> float:
	if not falloff:
		return dmg
	var factor: float = clampf(1.0 - maxf(_travel - 45.0 * K, 0.0) / (75.0 * K) * 0.65, 0.35, 1.0)
	return dmg * factor

func _on_hit(body: Node) -> void:
	if from_player and body.is_in_group("enemy"):
		if body.has_method("take_hit"):
			body.take_hit(_eff_dmg(), slip, debuff)
			Audio.play("sfx_enemy_hit", -9.0)
		queue_free()
	elif not from_player and body.is_in_group("player"):
		if fire:
			GameState.apply_fire(dmg)
		else:
			GameState.damage_player(_eff_dmg())   # 敏捷カット込み
		Audio.play("sfx_hit", -6.0)
		queue_free()
	elif body.is_in_group("island_body"):
		queue_free()
