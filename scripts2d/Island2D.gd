extends StaticBody2D
## Island2D — 島(見下ろし2D)。砂浜+緑+港。寄港はEで手動(#7)、名声解放済みのみ(#入港制限)。

signal dock_ready(island_id: int)
signal dock_left(island_id: int)

const DOCK_RADIUS := 190.0
var island_id: int = 0
var _player_inside := false
var _warned := false

func setup(id: int) -> void:
	island_id = id

func _ready() -> void:
	add_to_group("island_body")
	var def: Dictionary = Database.island(island_id)
	# 見た目は _draw で描画
	queue_redraw()
	# 衝突(陸地)
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 100.0
	col.shape = sh
	add_child(col)
	# 名前
	var lbl := Label.new()
	lbl.text = def.name
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 7)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.position = Vector2(-120, -170)
	lbl.custom_minimum_size = Vector2(240, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	# 入港圏
	var area := Area2D.new()
	var acol := CollisionShape2D.new()
	var ash := CircleShape2D.new()
	ash.radius = DOCK_RADIUS
	acol.shape = ash
	area.add_child(acol)
	add_child(area)
	area.body_entered.connect(_on_enter)
	area.body_exited.connect(_on_exit)

# 島idを種にした不規則な海岸線ポリゴン(#41)
func _coast(base_r: float, wobble: float, seed_off: int, points: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var s1 := float(island_id * 7 + seed_off)
	for i in points:
		var a := TAU * i / points
		var r := base_r * (1.0 + wobble * sin(3.0 * a + s1) + wobble * 0.6 * sin(7.0 * a + s1 * 2.3))
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _draw() -> void:
	# 浅瀬(にじみ)→砂浜→緑地→深緑→山 …すべて不規則な海岸線(#41)
	draw_colored_polygon(_coast(132, 0.16, 1), Color(0.55, 0.82, 0.87, 0.45))
	draw_colored_polygon(_coast(112, 0.15, 1), Color(0.90, 0.83, 0.62))
	draw_colored_polygon(_coast(86, 0.17, 3), Color(0.44, 0.64, 0.36))
	draw_colored_polygon(_coast(52, 0.22, 5), Color(0.33, 0.52, 0.30))
	# 山(頂と影)
	draw_circle(Vector2(-12, -12), 22, Color(0.52, 0.48, 0.44))
	draw_circle(Vector2(-16, -16), 10, Color(0.72, 0.70, 0.66))
	# ヤシの木(海岸ぞいに数本)
	var rng := RandomNumberGenerator.new()
	rng.seed = island_id * 31 + 7
	for t in 5:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * rng.randf_range(58.0, 88.0)
		draw_line(p, p + Vector2(2, -9), Color(0.45, 0.32, 0.18), 3.0)
		for f in 5:
			var fa := TAU * f / 5.0 + rng.randf() * 0.5
			draw_line(p + Vector2(2, -9), p + Vector2(2, -9) + Vector2(cos(fa), sin(fa) * 0.6) * 9.0, Color(0.25, 0.55, 0.25), 2.0)
	# 港町(桟橋+家々)
	draw_rect(Rect2(78, -8, 52, 16), Color(0.5, 0.36, 0.22))
	for h in 3:
		var hx := 46 + h * 16
		draw_rect(Rect2(hx, -24, 12, 12), Color(0.78, 0.42, 0.32))
		draw_rect(Rect2(hx + 1, -28, 10, 5), Color(0.55, 0.30, 0.22))
	# 入港圏の破線円
	var seg := 40
	for i in seg:
		if i % 2 == 0:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 0.7) / seg
			draw_arc(Vector2.ZERO, DOCK_RADIUS, a0, a1, 4, Color(1, 1, 0.8, 0.35), 3.0)

func _on_enter(body: Node) -> void:
	if not body.is_in_group("player") or _player_inside:
		return
	if not GameState.unlocked_islands.has(island_id):
		if not _warned:
			_warned = true
			GameState.notice.emit("%s に入港するには名声が足りない(必要:%d)" % [Database.island(island_id).name, Database.island(island_id).fame_req])
		return
	_player_inside = true
	dock_ready.emit(island_id)

func _on_exit(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_warned = false
		dock_left.emit(island_id)
