extends Node3D
## Island — 島。中心にメッシュ、周囲に入港判定の Area3D を持つ。
## プレイヤーが入港圏に入ると World に通知して帰港(港メニュー)へ。

signal dock_ready(island_id: int)   # プレイヤーが寄港可能圏に入った(名声解放済みの島のみ)
signal dock_left(island_id: int)

var island_id: int = 0
var dock_radius: float = 26.0
var _player_inside := false

func setup(id: int) -> void:
	island_id = id

func _ready() -> void:
	add_to_group("island")
	add_to_group("sonar_island")
	var def: Dictionary = Database.island(island_id)
	# 島本体(円錐+土台)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 12.0
	cyl.bottom_radius = 16.0
	cyl.height = 4.0
	base.mesh = cyl
	base.position.y = 1.0
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.78, 0.55)
	base.material_override = bmat
	add_child(base)
	# 山
	var hill := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 10.0
	cone.height = 12.0
	hill.mesh = cone
	hill.position.y = 8.0
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.35, 0.55, 0.3)
	hill.material_override = hmat
	add_child(hill)
	# 灯台/建物
	var house := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3, 4, 3)
	house.mesh = box
	house.position = Vector3(8, 4, 0)
	var hsm := StandardMaterial3D.new()
	hsm.albedo_color = Color(0.8, 0.4, 0.3)
	house.material_override = hsm
	add_child(house)
	# 名前表示
	var label := Label3D.new()
	label.text = def.name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 18.0
	label.font_size = 64
	label.outline_size = 12
	add_child(label)
	# 入港判定
	var area := Area3D.new()
	area.name = "DockArea"
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = dock_radius
	col.shape = sph
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

var _warned := false

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or _player_inside:
		return
	# 名声で解放済みの島にのみ入港できる
	if not GameState.unlocked_islands.has(island_id):
		if not _warned:
			_warned = true
			var req: int = Database.island(island_id).fame_req
			GameState.notice.emit("%s に入港するには名声が足りない(必要:%d)" % [Database.island(island_id).name, req])
		return
	_player_inside = true
	dock_ready.emit(island_id)   # 寄港は自動でなく、プレイヤーがEで選択(Issue #7)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_warned = false
		dock_left.emit(island_id)
