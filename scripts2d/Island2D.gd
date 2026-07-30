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

# #172: 島ごとに配色・植生・地形を変える(0南国/1涼しい岩場/2砂漠/3火山/4寒冷)
# #190: 月下の島(index2)を砂漠+わずかな緑地として追加し、火山/寒冷を1つずつ後ろへ
const PALETTES := [
	{"shallow": Color(0.55,0.82,0.87,0.45), "sand": Color(0.90,0.83,0.62), "grass": Color(0.44,0.64,0.36), "grass2": Color(0.33,0.52,0.30), "mtn": Color(0.52,0.48,0.44), "peak": Color(0.72,0.70,0.66), "tree": Color(0.25,0.55,0.25), "trunk": Color(0.45,0.32,0.18), "trees": 5, "wob": 0.16},
	{"shallow": Color(0.45,0.72,0.85,0.45), "sand": Color(0.80,0.79,0.70), "grass": Color(0.36,0.56,0.40), "grass2": Color(0.23,0.41,0.31), "mtn": Color(0.45,0.46,0.50), "peak": Color(0.66,0.68,0.72), "tree": Color(0.20,0.45,0.34), "trunk": Color(0.38,0.30,0.22), "trees": 7, "wob": 0.20},
	# #190: 月下の島=砂漠。砂丘が島の大部分を占め、中央の泉のまわりだけわずかに緑(oasis=緑地を小さく描く)
	{"shallow": Color(0.52,0.76,0.80,0.45), "sand": Color(0.88,0.78,0.53), "grass": Color(0.80,0.68,0.43), "grass2": Color(0.45,0.55,0.30), "mtn": Color(0.66,0.55,0.38), "peak": Color(0.86,0.76,0.55), "tree": Color(0.30,0.52,0.28), "trunk": Color(0.42,0.32,0.20), "trees": 2, "wob": 0.14, "oasis": true},
	{"shallow": Color(0.50,0.58,0.66,0.45), "sand": Color(0.58,0.50,0.42), "grass": Color(0.46,0.44,0.31), "grass2": Color(0.31,0.27,0.21), "mtn": Color(0.40,0.26,0.22), "peak": Color(0.80,0.36,0.18), "tree": Color(0.32,0.40,0.22), "trunk": Color(0.32,0.24,0.16), "trees": 3, "wob": 0.24},
	{"shallow": Color(0.60,0.74,0.84,0.45), "sand": Color(0.83,0.85,0.88), "grass": Color(0.62,0.66,0.68), "grass2": Color(0.47,0.52,0.56), "mtn": Color(0.55,0.57,0.62), "peak": Color(0.93,0.95,0.99), "tree": Color(0.24,0.40,0.32), "trunk": Color(0.34,0.26,0.18), "trees": 3, "wob": 0.18, "conifer": true},
]

func _draw() -> void:
	var p: Dictionary = PALETTES[clampi(island_id, 0, PALETTES.size() - 1)]
	var wob: float = p.wob
	# 浅瀬(にじみ)→砂浜→緑地→深緑→山 …すべて不規則な海岸線(#41)。#172: 島ごとに配色・輪郭のゆらぎを変える
	draw_colored_polygon(_coast(132, wob, 1), p.shallow)
	draw_colored_polygon(_coast(112, wob * 0.9, 1), p.sand)
	draw_colored_polygon(_coast(86, wob, 3), p.grass)
	if bool(p.get("oasis", false)):
		# #190: 砂漠の島は緑地がわずか。中央の泉(オアシス)まわりだけ小さく緑を置く
		draw_colored_polygon(_coast(26, wob * 1.4, 5), p.grass2)
		draw_circle(Vector2(6, 10), 10, Color(0.35, 0.62, 0.72, 0.9))
	else:
		draw_colored_polygon(_coast(52, wob * 1.3, 5), p.grass2)
	# 山(頂と影)
	draw_circle(Vector2(-12, -12), 22, p.mtn)
	draw_circle(Vector2(-16, -16), 10, p.peak)
	# 樹木(海岸ぞいに数本。島ごとに本数・色が異なる)
	var rng := RandomNumberGenerator.new()
	rng.seed = island_id * 31 + 7
	var conifer := bool(p.get("conifer", false))
	for t in int(p.trees):
		var a := rng.randf() * TAU
		var pt := Vector2(cos(a), sin(a)) * rng.randf_range(58.0, 88.0)
		if conifer:
			# #172再: 果ての島は針葉樹(モミの木)。細い幹＋積み重ねた三角の樹冠
			draw_line(pt, pt + Vector2(0, -8), p.trunk, 2.0)
			var top := pt + Vector2(0, -8)
			for tier in 3:
				var ty := top.y + tier * 7.0        # 上段ほど小さく、下へずらして重ねる
				var w := 5.0 + tier * 3.0
				var h := 9.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(top.x, ty),
					Vector2(top.x - w, ty + h),
					Vector2(top.x + w, ty + h),
				]), p.tree)
		else:
			draw_line(pt, pt + Vector2(2, -9), p.trunk, 3.0)
			for f in 5:
				var fa := TAU * f / 5.0 + rng.randf() * 0.5
				draw_line(pt + Vector2(2, -9), pt + Vector2(2, -9) + Vector2(cos(fa), sin(fa) * 0.6) * 9.0, p.tree, 2.0)
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
