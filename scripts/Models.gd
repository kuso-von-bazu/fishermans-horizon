extends RefCounted
## Models — プリミティブを組み合わせて簡易3Dモデル(魚/海獣/海賊船)を生成する静的ライブラリ。
## class_name は使わず preload 定数経由で参照する(インポート前の直起動でも確実に解決するため)。
## ビルボードは使わず、すべて立体メッシュで構築する。生成画像は別途UI挿絵/テクスチャに使う。

# ---- 低レベルヘルパ ----
static func _mat(color: Color, rough := 0.55, metal := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

static func _mi(mesh: Mesh, color: Color, pos := Vector3.ZERO, scale := Vector3.ONE, rot_deg := Vector3.ZERO, rough := 0.55, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, rough, metal)
	mi.position = pos
	mi.scale = scale
	mi.rotation_degrees = rot_deg
	return mi

static func _sphere(r := 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 10
	return s

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	return c

static func _prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p

# ===========================================================================
# 魚モブ — 小型の立体魚(体+尾びれ+背びれ)。length は全長[m]。
# ===========================================================================
static func fish(color: Color, length: float = 1.2) -> Node3D:
	var root := Node3D.new()
	var L := length
	# 体: 紡錘形(回転楕円)
	var body := _mi(_sphere(0.5), color, Vector3.ZERO, Vector3(0.45 * L, 0.42 * L, 1.0 * L), Vector3.ZERO, 0.4, 0.25)
	root.add_child(body)
	# 尾びれ(垂直の三角)
	var tail := _mi(_prism(Vector3(0.05, 0.55 * L, 0.5 * L)), color.darkened(0.1), Vector3(0, 0, 0.55 * L), Vector3.ONE, Vector3(90, 0, 0), 0.4)
	root.add_child(tail)
	# 背びれ
	var dorsal := _mi(_prism(Vector3(0.04, 0.3 * L, 0.4 * L)), color.darkened(0.15), Vector3(0, 0.28 * L, 0.05 * L), Vector3.ONE, Vector3(0, 0, 0), 0.4)
	root.add_child(dorsal)
	# 目
	for sx in [-1.0, 1.0]:
		var eye := _mi(_sphere(0.5), Color(0.05, 0.05, 0.05), Vector3(sx * 0.16 * L, 0.05 * L, -0.34 * L), Vector3(0.12 * L, 0.12 * L, 0.12 * L), Vector3.ZERO, 0.2, 0.4)
		root.add_child(eye)
	return root

# ===========================================================================
# 海の獣 — 戦闘モブ/近海の主。id ごとに特徴パーツを足す。
# size_scale は全体倍率(HP等から World 側で決定)。
# ===========================================================================
static func sea_beast(id: String, color: Color, size_scale: float = 1.0) -> Node3D:
	var root := Node3D.new()
	var s := size_scale
	# 共通: 大きな紡錘形の体
	var body_len := 3.0 * s
	var body := _mi(_sphere(0.5), color, Vector3.ZERO, Vector3(1.1 * s, 1.0 * s, body_len), Vector3.ZERO, 0.55, 0.05)
	root.add_child(body)
	# 尾びれ(水平フルーク)
	root.add_child(_mi(_prism(Vector3(1.6 * s, 0.12 * s, 1.0 * s)), color.darkened(0.12), Vector3(0, 0, body_len * 0.55), Vector3.ONE, Vector3(0, 0, 0), 0.55))
	# 胸びれ(両側)
	for sx in [-1.0, 1.0]:
		root.add_child(_mi(_prism(Vector3(0.1 * s, 0.5 * s, 1.0 * s)), color.darkened(0.1), Vector3(sx * 0.9 * s, -0.2 * s, -0.2 * body_len), Vector3.ONE, Vector3(0, sx * 25.0, sx * 70.0), 0.55))

	match id:
		"narwhal":
			# 一本角
			root.add_child(_mi(_cyl(0.02 * s, 0.12 * s, 2.2 * s), Color(0.95, 0.93, 0.85), Vector3(0, 0.1 * s, -body_len * 0.85), Vector3.ONE, Vector3(-90, 0, 0), 0.4))
		"seahunter":
			# シャチ: 白い腹紋 + 背びれ
			root.add_child(_mi(_prism(Vector3(0.12 * s, 1.0 * s, 0.7 * s)), Color(0.1, 0.1, 0.12), Vector3(0, 0.8 * s, 0), Vector3.ONE, Vector3.ZERO, 0.5))
			root.add_child(_mi(_sphere(0.5), Color(0.95, 0.95, 0.95), Vector3(0, -0.55 * s, 0.2 * body_len), Vector3(0.7 * s, 0.5 * s, 1.3 * s), Vector3.ZERO, 0.5))
		"ornithocheirus", "quetzal":
			# 翼竜/羽毛竜: 大きな翼 + くちばし
			for sx in [-1.0, 1.0]:
				root.add_child(_mi(_box(Vector3(2.6 * s, 0.08 * s, 1.3 * s)), color.lightened(0.05), Vector3(sx * 1.7 * s, 0.5 * s, 0), Vector3.ONE, Vector3(0, 0, sx * 18.0), 0.6))
			root.add_child(_mi(_cyl(0.02 * s, 0.25 * s, 1.2 * s), Color(0.9, 0.8, 0.3), Vector3(0, 0, -body_len * 0.7), Vector3.ONE, Vector3(-90, 0, 0), 0.5))
		"wyrm":
			# 幼竜: 小さな翼 + 角
			for sx in [-1.0, 1.0]:
				root.add_child(_mi(_box(Vector3(1.4 * s, 0.06 * s, 0.9 * s)), color.lightened(0.1), Vector3(sx * 1.0 * s, 0.5 * s, -0.1 * body_len), Vector3.ONE, Vector3(0, 0, sx * 30.0), 0.6))
			for sx in [-1.0, 1.0]:
				root.add_child(_mi(_cyl(0.01 * s, 0.08 * s, 0.7 * s), Color(0.9, 0.85, 0.7), Vector3(sx * 0.2 * s, 0.6 * s, -body_len * 0.55), Vector3.ONE, Vector3(-70, 0, sx * 15.0), 0.5))
		"sawshark":
			# のこぎりザメ: 長い鋸の吻 + 背びれ
			var saw := _mi(_box(Vector3(0.5 * s, 0.12 * s, 1.8 * s)), Color(0.55, 0.6, 0.62), Vector3(0, 0, -body_len * 0.75), Vector3.ONE, Vector3.ZERO, 0.4, 0.6)
			root.add_child(saw)
			for i in range(6):
				var tx := 0.28 * s
				root.add_child(_mi(_prism(Vector3(0.04 * s, 0.18 * s, 0.12 * s)), Color(0.8, 0.82, 0.8), Vector3(tx, 0, -body_len * 0.55 - i * 0.22 * s), Vector3.ONE, Vector3(0, 0, 90), 0.4, 0.6))
				root.add_child(_mi(_prism(Vector3(0.04 * s, 0.18 * s, 0.12 * s)), Color(0.8, 0.82, 0.8), Vector3(-tx, 0, -body_len * 0.55 - i * 0.22 * s), Vector3.ONE, Vector3(0, 0, -90), 0.4, 0.6))
			root.add_child(_mi(_prism(Vector3(0.1 * s, 0.9 * s, 0.7 * s)), color.darkened(0.1), Vector3(0, 0.8 * s, 0), Vector3.ONE, Vector3.ZERO, 0.5))
		"dumbo":
			# 海の象: 大きな耳 + 鼻
			for sx in [-1.0, 1.0]:
				root.add_child(_mi(_sphere(0.5), color.lightened(0.05), Vector3(sx * 1.2 * s, 0.3 * s, -body_len * 0.35), Vector3(1.4 * s, 1.2 * s, 0.18 * s), Vector3(0, 0, 0), 0.6))
			root.add_child(_mi(_cyl(0.12 * s, 0.22 * s, 1.6 * s), color, Vector3(0, -0.2 * s, -body_len * 0.7), Vector3.ONE, Vector3(-60, 0, 0), 0.6))
		"walrus":
			# セイウチ: 二本の牙 + 丸い顔
			root.add_child(_mi(_sphere(0.5), color.lightened(0.05), Vector3(0, -0.1 * s, -body_len * 0.5), Vector3(1.2 * s, 1.1 * s, 0.9 * s), Vector3.ZERO, 0.6))
			for sx in [-1.0, 1.0]:
				root.add_child(_mi(_cyl(0.03 * s, 0.12 * s, 1.1 * s), Color(0.93, 0.9, 0.82), Vector3(sx * 0.25 * s, -0.5 * s, -body_len * 0.7), Vector3.ONE, Vector3(-100, 0, 0), 0.4))
		"whale":
			# 巨大髭鯨: 体をさらに長く + 顎
			body.scale = Vector3(1.3 * s, 1.2 * s, 1.7 * body_len / 3.0)
			root.add_child(_mi(_box(Vector3(1.6 * s, 0.5 * s, 1.6 * s)), color.darkened(0.05), Vector3(0, -0.5 * s, -body_len * 0.7), Vector3.ONE, Vector3.ZERO, 0.6))
		"hydra":
			# ヒュドラ: 複数の首と頭
			for k in range(3):
				var ang := (k - 1) * 28.0
				var neck := _mi(_cyl(0.18 * s, 0.28 * s, 2.0 * s), color.darkened(0.05), Vector3(sin(deg_to_rad(ang)) * 0.7 * s, 1.0 * s, -body_len * 0.55), Vector3.ONE, Vector3(-50, ang, 0), 0.55)
				root.add_child(neck)
				root.add_child(_mi(_sphere(0.35 * s), color.lightened(0.05), Vector3(sin(deg_to_rad(ang)) * 1.2 * s, 1.9 * s, -body_len * 0.78), Vector3.ONE, Vector3.ZERO, 0.5))
		"leviathan":
			# 神話的巨獣: 巨大化 + 背の棘列 + 顎
			body.scale = Vector3(1.8 * s, 1.7 * s, 2.4 * s)
			for i in range(7):
				root.add_child(_mi(_prism(Vector3(0.12 * s, (0.8 - i * 0.05) * s, 0.5 * s)), color.darkened(0.2), Vector3(0, 1.3 * s, -body_len * 0.5 + i * 0.6 * s), Vector3.ONE, Vector3.ZERO, 0.5))
			root.add_child(_mi(_box(Vector3(2.2 * s, 0.7 * s, 2.2 * s)), color.darkened(0.1), Vector3(0, -0.6 * s, -body_len * 0.95), Vector3.ONE, Vector3.ZERO, 0.5))
			# 赤く光る目
			for sx in [-1.0, 1.0]:
				root.add_child(_mi(_sphere(0.5), Color(1.0, 0.2, 0.1), Vector3(sx * 0.6 * s, 0.5 * s, -body_len * 0.95), Vector3(0.35 * s, 0.35 * s, 0.35 * s), Vector3.ZERO, 0.2, 0.0))
	return root

# ===========================================================================
# 船 — プレイヤー/海賊。水面(y=0)に正しく浮く(喫水を少しだけ沈める)。
# ===========================================================================
static func ship(scale: float, hull_color: Color, sail_color: Color, pirate := false) -> Node3D:
	var root := Node3D.new()
	var s := scale
	var hull_c := hull_color
	# 船体(下部): 喫水線がy=0付近。底をやや沈める。
	var hull := _mi(_box(Vector3(2.2 * s, 1.3 * s, 6.0 * s)), hull_c, Vector3(0, 0.15 * s, 0), Vector3.ONE, Vector3.ZERO, 0.6)
	root.add_child(hull)
	# 舷側を少し絞った上甲板
	root.add_child(_mi(_box(Vector3(2.4 * s, 0.25 * s, 6.0 * s)), hull_c.lightened(0.1), Vector3(0, 0.85 * s, 0), Vector3.ONE, Vector3.ZERO, 0.6))
	# 船首(先細り)
	root.add_child(_mi(_prism(Vector3(2.2 * s, 1.3 * s, 2.0 * s)), hull_c, Vector3(0, 0.15 * s, -3.7 * s), Vector3.ONE, Vector3(-90, 0, 0), 0.6))
	# 船尾の小屋
	root.add_child(_mi(_box(Vector3(1.8 * s, 1.2 * s, 1.6 * s)), hull_c.darkened(0.1), Vector3(0, 1.45 * s, 2.0 * s), Vector3.ONE, Vector3.ZERO, 0.6))
	# マスト
	root.add_child(_mi(_cyl(0.1 * s, 0.12 * s, 5.0 * s), Color(0.4, 0.28, 0.16), Vector3(0, 3.0 * s, -0.3 * s), Vector3.ONE, Vector3.ZERO, 0.7))
	# 帆(平面)
	var sail := _mi(_box(Vector3(3.2 * s, 3.4 * s, 0.08 * s)), sail_color, Vector3(0, 3.6 * s, -0.1 * s), Vector3.ONE, Vector3.ZERO, 0.8)
	root.add_child(sail)
	# ヤード
	root.add_child(_mi(_cyl(0.05 * s, 0.05 * s, 3.6 * s), Color(0.4, 0.28, 0.16), Vector3(0, 5.2 * s, -0.1 * s), Vector3.ONE, Vector3(0, 0, 90), 0.7))
	if pirate:
		# 海賊旗(ドクロ色の小旗)
		root.add_child(_mi(_box(Vector3(0.9 * s, 0.6 * s, 0.04 * s)), Color(0.08, 0.08, 0.08), Vector3(0.5 * s, 5.4 * s, -0.1 * s), Vector3.ONE, Vector3.ZERO, 0.8))
		# 砲門(舷側)
		for sx in [-1.0, 1.0]:
			for zz in [-1.5, 0.0, 1.5]:
				root.add_child(_mi(_cyl(0.12 * s, 0.12 * s, 0.7 * s), Color(0.15, 0.15, 0.17), Vector3(sx * 1.2 * s, 0.6 * s, zz * s), Vector3.ONE, Vector3(0, 0, 90), 0.4, 0.7))
	return root
