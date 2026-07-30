extends StaticBody2D
## Obstacle2D — 海上の障害物(#193)。
## ・船がぶつかると小ダメージ。ぶつかっても障害物は消滅しない。
## ・敵味方どちらの弾も、当たると消える(Projectile2Dが group "obstacle" で判定)。
## reef=岩礁(始まりの島〜嵐越えの島。始まり近海は数少なめ) / ice=流氷(果ての島。低速で移動)

var kind: String = "reef"
var radius: float = 46.0
var drift: Vector2 = Vector2.ZERO   # #193: 流氷だけ低速で漂う
var _shape: PackedVector2Array = PackedVector2Array()
var _bumps: Array = []              # 表面の起伏(岩の頭/氷の割れ目)

func setup(p_kind: String) -> void:
	kind = p_kind

func _ready() -> void:
	add_to_group("obstacle")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if kind == "ice":
		radius = rng.randf_range(54.0, 98.0)
		drift = Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(6.0, 15.0)
	else:
		radius = rng.randf_range(34.0, 62.0)
	# 不規則な輪郭(島の海岸線#41と同じ考え方で、岩/氷らしいゴツゴツを作る)
	var pts := 14 if kind == "reef" else 9
	var seed_a := rng.randf() * TAU
	for i in pts:
		var a := TAU * i / pts
		var wob: float = rng.randf_range(0.72, 1.28) if kind == "reef" else rng.randf_range(0.84, 1.16)
		_shape.append(Vector2(cos(a + seed_a), sin(a + seed_a)) * radius * wob)
	for b in (4 if kind == "reef" else 3):
		var ba := rng.randf() * TAU
		_bumps.append({
			"pos": Vector2(cos(ba), sin(ba)) * radius * rng.randf_range(0.15, 0.5),
			"r": radius * rng.randf_range(0.16, 0.30),
		})
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = radius * 0.80   # 見た目よりやや小さめ(輪郭の尖りで理不尽に当たらないように)
	col.shape = sh
	add_child(col)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if drift != Vector2.ZERO:
		global_position += drift * delta   # StaticBody2Dの座標はスクリプト側が持つ(島と同じ扱い)

func _draw() -> void:
	if kind == "ice":
		# 流氷: 白〜淡青の板氷。縁を明るく、上面に割れ目
		draw_colored_polygon(_scaled(_shape, 1.06), Color(0.62, 0.78, 0.86, 0.55))   # 水中に沈む縁
		draw_colored_polygon(_shape, Color(0.88, 0.93, 0.97))
		for b in _bumps:
			draw_circle(b.pos, b.r, Color(0.97, 0.99, 1.0))
		draw_polyline(_scaled(_shape, 1.0) + PackedVector2Array([_shape[0]]), Color(0.55, 0.70, 0.82), 2.0)
	else:
		# 岩礁: 濡れた暗い岩+白い波しぶきの輪
		draw_arc(Vector2.ZERO, radius * 1.12, 0, TAU, 30, Color(0.95, 0.98, 1.0, 0.45), 5.0)
		draw_colored_polygon(_scaled(_shape, 1.05), Color(0.16, 0.22, 0.26, 0.6))    # 水面下の影
		draw_colored_polygon(_shape, Color(0.34, 0.32, 0.30))
		for b in _bumps:
			draw_circle(b.pos, b.r, Color(0.46, 0.44, 0.41))

func _scaled(poly: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * s)
	return out
