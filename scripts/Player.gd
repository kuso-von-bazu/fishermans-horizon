extends CharacterBody3D
const Models = preload("res://scripts/Models.gd")
## Player — プレイヤーの船。低速で戦車的な操作。三人称カメラを子に持つ。
## 武器発射・漁獲判定のフックも持つが、戦闘の本体は Weapons/World 側で拡張する。

signal fished(item_id: String)

@export var max_speed: float = 11.0
@export var accel: float = 6.0
@export var turn_speed: float = 1.2   # rad/s

var throttle: float = 0.0     # -1..1
var steer: float = 0.0        # -1..1
var control_enabled: bool = true
var ship_rig: Node3D
var cam_pivot: Node3D
var cam_arm: SpringArm3D
var camera: Camera3D
var aim_marker: Node3D
var cam_yaw: float = 0.0
var cam_pitch: float = -0.30
var mouse_sens: float = 0.005
var _ram_cd: float = 0.0
var _bob_t: float = 0.0

func _ready() -> void:
	add_to_group("player")
	_build_visual()
	_build_camera()
	max_speed = float(GameState.ship().speed)

func _build_visual() -> void:
	# 立体的な帆船モデル(Models.ship)。揺れ演出用に _rig 配下へ。
	var sc := _ship_scale()
	ship_rig = Node3D.new()
	add_child(ship_rig)
	var model := Models.ship(sc, Color(0.5, 0.36, 0.22), Color(0.85, 0.82, 0.72), false)
	ship_rig.add_child(model)
	# 衝突形状
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6 * sc, 2.2 * sc, 7.0 * sc)
	col.shape = box
	col.position.y = 0.7 * sc
	add_child(col)

func _ship_scale() -> float:
	# 船が大きいほど見た目も大きく(装甲値を目安に)
	return clampf(0.9 + float(GameState.ship().armor) / 1500.0, 0.9, 1.8)

func _build_camera() -> void:
	# cam_pivot: ヨー(左右), cam_arm: ピッチ(上下)。船体の向きとは独立に回せる。
	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	cam_pivot.top_level = true   # 親(船体)の回転を継がない
	cam_pivot.position = Vector3(0, 6.0, 0)
	add_child(cam_pivot)
	cam_arm = SpringArm3D.new()
	cam_arm.spring_length = 19.0
	cam_pivot.add_child(cam_arm)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 0)
	camera.fov = 72
	cam_arm.add_child(camera)
	_update_cam_rot()
	# 照準マーカー(エイム位置)
	aim_marker = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.4
	sph.height = 0.8
	(aim_marker as MeshInstance3D).mesh = sph
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(1, 0.3, 0.2)
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	(aim_marker as MeshInstance3D).material_override = am
	aim_marker.visible = false

func _update_cam_rot() -> void:
	if cam_pivot:
		cam_pivot.rotation = Vector3(0, cam_yaw, 0)
	if cam_arm:
		cam_arm.rotation = Vector3(cam_pitch, 0, 0)

func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * mouse_sens
		cam_pitch = clampf(cam_pitch - event.relative.y * mouse_sens, -1.2, 0.4)
		_update_cam_rot()

func _follow_camera() -> void:
	if cam_pivot:
		cam_pivot.global_position = global_position + Vector3(0, 6.0, 0)

func _physics_process(delta: float) -> void:
	_follow_camera()
	if not control_enabled:
		velocity = velocity.move_toward(Vector3.ZERO, accel * delta)
		move_and_slide()
		global_position.y = 0.0
		return
	throttle = 0.0
	steer = 0.0
	if Input.is_action_pressed("throttle_up"):
		throttle += 1.0
	if Input.is_action_pressed("throttle_down"):
		throttle -= 0.6
	if Input.is_action_pressed("turn_left"):
		steer += 1.0
	if Input.is_action_pressed("turn_right"):
		steer -= 1.0
	# 旋回(前進中ほど曲がりやすい)
	var spd := velocity.length()
	var steer_factor: float = clampf(spd / max_speed, 0.15, 1.0)
	rotate_y(steer * turn_speed * steer_factor * delta)
	# 推進
	var forward := -transform.basis.z
	var target_vel := forward * throttle * max_speed
	velocity = velocity.move_toward(target_vel, accel * delta)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0
	_handle_ram(delta)
	# 軽い船の揺れ(旋回でロール + 緩やかな上下動)
	if ship_rig:
		ship_rig.rotation.z = lerp(ship_rig.rotation.z, steer * -0.1, delta * 3.0)
		_bob_t += delta
		ship_rig.position.y = sin(_bob_t * 1.3) * 0.12

func _handle_ram(delta: float) -> void:
	if _ram_cd > 0.0:
		_ram_cd -= delta
		return
	var rd := float(Database.rams[GameState.ram_id].dmg)
	if rd <= 0.0:
		return
	var spd := velocity.length()
	if spd < 3.0:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col = c.get_collider()
		if col and col.is_in_group("enemy") and col.has_method("take_hit"):
			col.take_hit(rd * (0.5 + spd / maxf(max_speed, 1.0)), false, false)
			_ram_cd = 0.8
			return

func get_aim_point() -> Vector3:
	# 画面中央(カメラ前方)のレイが当たった点をエイム点とする。
	# 当たらなければ前方遠方。空中の敵も狙えるようy=0には投影しない。
	if camera == null:
		return global_position - transform.basis.z * 100.0
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var to := from + dir * 300.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit and hit.has("position"):
		return hit.position
	return to
