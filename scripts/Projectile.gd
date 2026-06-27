extends Area3D
## Projectile — 弾(ガトリング/大砲/銛/魚雷)。命中で Enemy にダメージ。
## 魚雷は homing=true で target を追尾。

var speed: float = 80.0
var dmg: float = 5.0
var life: float = 3.0
var slip: bool = false       # スリップダメージ(海賊船向け)
var debuff: bool = false     # デバフ(主向け)
var homing: bool = false
var fire: bool = false        # 炎(ヒュドラ)=回復するスリップとして命中
var target: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var from_player: bool = true

func setup(dir: Vector3, w: Dictionary, _target: Node3D = null) -> void:
	dmg = float(w.get("dmg", 5))
	speed = 70.0 + float(w.get("dmg", 5)) * 0.3
	slip = bool(w.get("slip", false))
	debuff = bool(w.get("debuff", false))
	homing = bool(w.get("homing", false))
	target = _target
	velocity = dir.normalized() * speed

func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.85, 0.3) if not homing else Color(0.6, 0.9, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mesh.material_override = mat
	add_child(mesh)
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.5
	col.shape = sh
	add_child(col)
	monitoring = true
	body_entered.connect(_on_hit_body)
	area_entered.connect(_on_hit_area)

func _physics_process(delta: float) -> void:
	if homing and is_instance_valid(target):
		var to := (target.global_position - global_position).normalized()
		velocity = velocity.lerp(to * speed, 4.0 * delta)
	global_position += velocity * delta
	life -= delta
	if life <= 0:
		queue_free()

func _on_hit_body(body: Node) -> void:
	if from_player and body.is_in_group("enemy"):
		_apply(body)
	elif not from_player and body.is_in_group("player"):
		if fire:
			GameState.apply_fire(dmg)
		else:
			GameState.run_armor = maxf(GameState.run_armor - dmg, 0.0)
			GameState.stats_changed.emit()
		queue_free()
	elif body.is_in_group("island"):
		queue_free()

func _on_hit_area(area: Area3D) -> void:
	if from_player and area.is_in_group("enemy"):
		_apply(area)

func _apply(enemy: Node) -> void:
	if enemy.has_method("take_hit"):
		enemy.take_hit(dmg, slip, debuff)
	queue_free()
