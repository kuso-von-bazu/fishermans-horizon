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

func _draw() -> void:
	# 浅瀬→砂浜→緑地→山
	draw_circle(Vector2.ZERO, 130, Color(0.55, 0.8, 0.85, 0.55))
	draw_circle(Vector2.ZERO, 105, Color(0.89, 0.82, 0.6))
	draw_circle(Vector2.ZERO, 78, Color(0.42, 0.62, 0.35))
	draw_circle(Vector2(-14, -10), 36, Color(0.32, 0.5, 0.3))
	draw_circle(Vector2(-14, -10), 16, Color(0.55, 0.52, 0.48))
	# 港(桟橋)
	draw_rect(Rect2(70, -10, 55, 20), Color(0.5, 0.36, 0.22))
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
