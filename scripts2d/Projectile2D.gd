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
var target: Node2D = null
var dir: Vector2 = Vector2.UP
var from_player: bool = true

func setup(p_dir: Vector2, w: Dictionary, p_target: Node2D = null) -> void:
	dmg = float(w.get("dmg", 5))
	speed = (70.0 + float(w.get("dmg", 5)) * 0.3) * K
	slip = bool(w.get("slip", false))
	debuff = bool(w.get("debuff", false))
	homing = bool(w.get("homing", false))
	target = p_target
	dir = p_dir.normalized()

func _ready() -> void:
	var mesh := Polygon2D.new()
	var r := 4.0 if not homing else 5.0
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	mesh.polygon = pts
	if from_player:
		mesh.color = Color(0.65, 0.9, 1.0) if homing else Color(1.0, 0.85, 0.35)
	else:
		mesh.color = Color(1.0, 0.45, 0.2) if fire else Color(1.0, 0.3, 0.3)
	add_child(mesh)
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = r + 2.0
	col.shape = sh
	add_child(col)
	body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	if homing and is_instance_valid(target):
		var want := (target.global_position - global_position).normalized()
		dir = dir.lerp(want, 5.0 * delta).normalized()
	global_position += dir * speed * delta
	life -= delta
	if life <= 0:
		queue_free()

func _on_hit(body: Node) -> void:
	if from_player and body.is_in_group("enemy"):
		if body.has_method("take_hit"):
			body.take_hit(dmg, slip, debuff)
			Audio.play("sfx_enemy_hit", -9.0)
		queue_free()
	elif not from_player and body.is_in_group("player"):
		if fire:
			GameState.apply_fire(dmg)
		else:
			GameState.run_armor = maxf(GameState.run_armor - dmg, 0.0)
			GameState.stats_changed.emit()
		Audio.play("sfx_hit", -6.0)
		queue_free()
	elif body.is_in_group("island_body"):
		queue_free()
