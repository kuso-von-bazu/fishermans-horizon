extends Area3D
## Relic — 旧文明の遺産。海上に漂い、近づくと自動回収して資金相当を得る(魚倉を圧迫しない)。
## 換金自体は酒場で行うため、回収時は GameState.relics(換金待ち)に加算する。

var value: int = 300
var _t: float = 0.0
var _rig: Node3D
var _collected := false

func setup(v: int) -> void:
	value = v

func _ready() -> void:
	add_to_group("relic")
	add_to_group("sonar_relic")
	# 光る遺物(装飾箱+浮遊リング)
	_rig = Node3D.new()
	add_child(_rig)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.0, 1.4)
	box.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.72, 0.3)
	m.metallic = 0.8
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color(0.6, 0.5, 0.15)
	m.emission_energy_multiplier = 0.6
	box.mesh.material = m
	box.position.y = 1.0
	_rig.add_child(box)
	# 浮遊リング
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.1
	tm.outer_radius = 1.4
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.5, 0.8, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.4, 0.7, 1.0)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.mesh.material = rm
	ring.position.y = 1.0
	ring.rotation_degrees.x = 90
	_rig.add_child(ring)
	# 光柱(目印)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 30.0
	beam.mesh = cyl
	var bmt := StandardMaterial3D.new()
	bmt.albedo_color = Color(0.7, 0.85, 1.0, 0.18)
	bmt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.mesh.material = bmt
	beam.position.y = 15.0
	_rig.add_child(beam)
	var label := Label3D.new()
	label.text = "旧文明の遺産"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 3.0
	label.font_size = 30
	label.outline_size = 6
	label.modulate = Color(1.0, 0.95, 0.7)
	label.no_depth_test = true
	add_child(label)
	# 回収判定
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 6.0
	col.shape = sph
	add_child(col)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_t += delta
	if _rig:
		_rig.rotation.y += delta * 1.2
		_rig.position.y = sin(_t * 1.5) * 0.3

func _on_body_entered(body: Node) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	GameState.add_relic(value)
	queue_free()
