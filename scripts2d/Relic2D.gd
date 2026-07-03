extends Area2D
## Relic2D — 旧文明の遺産(見下ろし2D)。接近で自動回収(魚倉非圧迫・換金は酒場)。

var value: int = 300
var _t: float = 0.0
var _collected := false

func setup(v: int) -> void:
	value = v

func _ready() -> void:
	add_to_group("relic")
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 44.0
	col.shape = sh
	add_child(col)
	var lbl := Label.new()
	lbl.text = "旧文明の遺産"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.position = Vector2(-50, -52)
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	body_entered.connect(_on_enter)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	# 金の遺物+回転する光輪
	var pulse := 0.7 + sin(_t * 3.0) * 0.3
	draw_circle(Vector2.ZERO, 26 + sin(_t * 2.0) * 3.0, Color(0.5, 0.8, 1.0, 0.18 * pulse))
	draw_rect(Rect2(-11, -8, 22, 16), Color(0.85, 0.72, 0.3))
	draw_rect(Rect2(-11, -8, 22, 5), Color(0.95, 0.85, 0.45))
	for i in 6:
		var a := _t * 1.2 + TAU * i / 6.0
		draw_circle(Vector2(cos(a), sin(a)) * 20.0, 2.2, Color(0.6, 0.85, 1.0, 0.8))

func _on_enter(body: Node) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	GameState.add_relic(value)
	Audio.play("sfx_sell", -3.0)
	queue_free()
