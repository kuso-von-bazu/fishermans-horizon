extends CanvasLayer
## AchievementToast — #265再3: 実績を達成した瞬間に、その実績のバッヂ絵を
## 画面中央へ「ドンと」大きく出す0.8秒の演出。
##
## 航海中(HUD2D)と寄港中(PortUI)のどちらでも同じ演出を出したいので、
## どちらにも属さない自前の CanvasLayer(autoload)として持つ。
## PortUI が layer 20 なので、それより手前の 40 に置く。
##
## 同時に複数の実績が解除されることがある(討伐でキラー系とバウンティ系が同時など)ので
## 1件ずつ順番に見せる。ボスラッシュ中は GameState 側で通知そのものが出ない。

const PixelFont = preload("res://scripts/PixelFont.gd")   # #278(提案3): 見出しはピクセルフォント

const POPUP_SEC := 0.8        # 1件あたりの表示時間(共有者指定)
const POP_IN := 0.14          # 大きい状態から等倍へ縮んで現れるまで
const FADE_OUT := 0.25        # 消えるまで
const MAX_QUEUE := 6          # 一度に大量解除されたときの上限(古い順に見せて残りは捨てる)

var _queue: Array = []
var _busy: bool = false
var _root: Control

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS   # ヒットストップ(time_scale)中でも進む
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	GameState.achievement_unlocked.connect(_on_unlocked)

func _on_unlocked(aid: String) -> void:
	if _queue.size() >= MAX_QUEUE:
		return
	_queue.append(aid)
	if not _busy:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var aid: String = _queue.pop_front()
	var holder := _build(aid)
	if holder == null:
		_next()   # 絵が無い実績は飛ばす
		return
	_root.add_child(holder)
	# 0.00-0.14 1.7倍から等倍へ(ドンと出る) / 0.14-0.55 保持 / 0.55-0.80 膨らみながら消える
	holder.scale = Vector2(1.7, 1.7)
	holder.modulate.a = 0.0
	# 並行/直列は chain()・parallel() で明示する。set_parallel(true) のままだと
	# 待ち時間と消えるアニメが同時に走り、0.8秒より早く消えてしまう。
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(holder, "scale", Vector2.ONE, POP_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, POP_IN * 0.7)
	tw.chain().tween_interval(POPUP_SEC - POP_IN - FADE_OUT)
	tw.chain().tween_property(holder, "modulate:a", 0.0, FADE_OUT)
	tw.parallel().tween_property(holder, "scale", Vector2(1.12, 1.12), FADE_OUT)
	tw.chain().tween_callback(holder.queue_free)
	tw.chain().tween_callback(_next)

# バッヂ絵＋「実績達成」＋実績名の縦並び。絵が無ければ null を返す。
func _build(aid: String) -> Control:
	var a: Dictionary = Database.achievement(aid)
	if a.is_empty():
		return null
	var path := str(a.get("icon", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 0.5
	holder.anchor_bottom = 0.5
	holder.offset_left = -170.0
	holder.offset_right = 170.0
	holder.offset_top = -190.0
	holder.offset_bottom = 10.0
	holder.pivot_offset = Vector2(170.0, 100.0)   # 中心から拡縮する

	# 海の上でも読めるよう、HUDと同じ「ドットの枠線」の暗幕を敷く
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.08, 0.82)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.86, 0.45, 0.95)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2.ZERO
	sb.shadow_color = Color(0, 0, 0, 0.85)
	sb.anti_aliasing = false
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	var tex := TextureRect.new()
	tex.texture = load(path)
	# #265再2 と同じ理由: 元画像のサイズを最小サイズとして要求させない
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # ドット絵をぼかさない
	tex.custom_minimum_size = Vector2(128, 128)
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # 横長の敵も128px角に収める
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tex)

	vb.add_child(_line("実績達成", 24, Color(1.0, 0.86, 0.45)))
	vb.add_child(_line(str(a.get("name", "")), 36, Color(1, 1, 1)))
	return holder

func _line(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelFont.apply(l, size)
	return l
