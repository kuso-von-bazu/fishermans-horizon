extends Area2D
## Flotsam2D — #267: 航海中のレアスポーン。触れると回収する。
##   kind = "castaway"(漂流者) / "cargo"(漂流貨物)
## 遺産(Relic2D)と同じく接触で回収し、1回だけ効果を出す。

var kind: String = "castaway"
var _t: float = 0.0
var _taken := false
var _sprite: Sprite2D = null

func setup(p_kind: String) -> void:
	kind = p_kind

func _ready() -> void:
	add_to_group("flotsam")
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 44.0
	col.shape = sh
	add_child(col)
	# ドット絵があれば使う。無ければ _draw のシルエットで代用する
	var path := "res://assets/images/pixel/fx_%s.png" % ("castaway" if kind == "castaway" else "cargo")
	if ResourceLoader.exists(path):
		_sprite = Sprite2D.new()
		_sprite.texture = load(path)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tex: Texture2D = _sprite.texture
		var longest: float = float(maxi(tex.get_width(), tex.get_height()))
		_sprite.scale = Vector2.ONE * (54.0 / maxf(longest, 1.0))
		add_child(_sprite)
	var lbl := Label.new()
	lbl.text = "漂流者" if kind == "castaway" else "漂流貨物"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9) if kind == "castaway" else Color(1.0, 0.92, 0.72))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.position = Vector2(-50, -54)
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	body_entered.connect(_on_enter)

func _process(delta: float) -> void:
	_t += delta
	# ゆっくり上下に漂う
	if _sprite:
		_sprite.position.y = sin(_t * 1.6) * 3.0
	queue_redraw()

func _draw() -> void:
	# 水面のさざなみ(目印)。ドット絵の有無に関わらず出す
	var pulse := 0.7 + sin(_t * 3.0) * 0.3
	var col := Color(0.6, 1.0, 0.8, 0.16 * pulse) if kind == "castaway" else Color(1.0, 0.85, 0.5, 0.16 * pulse)
	draw_circle(Vector2.ZERO, 28 + sin(_t * 2.0) * 3.0, col)
	if _sprite != null:
		return
	# 画像が無いときの代用シルエット
	if kind == "castaway":
		draw_circle(Vector2(0, -6), 7, Color(0.92, 0.82, 0.7))
		draw_rect(Rect2(-9, 2, 18, 10), Color(0.35, 0.55, 0.75))
	else:
		draw_rect(Rect2(-13, -9, 26, 18), Color(0.55, 0.4, 0.24))
		draw_rect(Rect2(-13, -3, 26, 5), Color(0.75, 0.6, 0.35))

func _on_enter(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	if GameState.docking_locked:
		return   # 寄港確定後は拾わない(遺産と同じ扱い)
	_taken = true
	if kind == "castaway":
		GameState.rescue_castaway()
	else:
		GameState.collect_drifting_cargo()
	Audio.play("sfx_lock", -6.0)
	queue_free()
