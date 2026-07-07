extends CanvasLayer
## TitleScreen — タイトル/勝利のフルスクリーン・オーバーレイ。
## show_title(): 開始画面。 show_victory(): レヴィアタン討伐後のエンディング。
## レイアウトは CenterContainer で常に画面中央に収まるようにし、解像度に依存しない。

signal start_pressed
signal continue_pressed

var _root: Control
var _title: Label
var _body: Label
var _button: Button
var _continue_button: Button
var _bg: ColorRect
var _art: TextureRect

func _ready() -> void:
	layer = 30
	_build()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_bg = ColorRect.new()
	_bg.color = Color(0.03, 0.07, 0.12, 1.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_bg)
	# タイトル画像があれば背景に薄く敷く
	if ResourceLoader.exists("res://assets/images/title.png"):
		_art = TextureRect.new()
		_art.texture = load("res://assets/images/title.png")
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		_art.modulate = Color(1, 1, 1, 0.45)
		_root.add_child(_art)

	# 画面全体を覆う CenterContainer で中身を中央寄せ
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	center.add_child(margin)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	margin.add_child(vb)

	_title = Label.new()
	_title.text = "Fisherman's Horizon"
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_body = Label.new()
	_body.text = "海面上昇に沈んだ世界。粗末な蒸気漁船から始め、漁と狩りで身を立て、\n近海の主を討ち、海賊を狩り、名声を轟かせて未踏の漁場を目指せ。\n人類種の天敵レヴィアタンを討ち、伝説の漁場へ至るのだ。\n\n[W/S]前進・後進   [A/D]旋回   [マウス]照準   [左クリック]射撃\n[右クリック]魚雷(ロックオン)   [E]漁・寄港   燃料が尽きる前に帰港せよ"
	_body.add_theme_font_size_override("font_size", 20)
	_body.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_body)

	_button = Button.new()
	_button.text = "船出する"
	_button.add_theme_font_size_override("font_size", 26)
	_button.custom_minimum_size = Vector2(240, 56)
	_button.pressed.connect(func(): emit_signal("start_pressed"))
	var bc := CenterContainer.new()
	bc.add_child(_button)
	vb.add_child(bc)

	# #93: 続きから(セーブがある時のみ表示)
	_continue_button = Button.new()
	_continue_button.text = "続きから"
	_continue_button.add_theme_font_size_override("font_size", 22)
	_continue_button.custom_minimum_size = Vector2(200, 48)
	_continue_button.pressed.connect(func(): emit_signal("continue_pressed"))
	var cc2 := CenterContainer.new()
	cc2.add_child(_continue_button)
	vb.add_child(cc2)

	# #90: BGM著作権表示(MusMus)
	var credit := Label.new()
	credit.text = "BGM: フリーBGM・音楽素材MusMus  https://musmus.main.jp"
	credit.add_theme_font_size_override("font_size", 14)
	credit.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(credit)

func show_title() -> void:
	_title.text = "Fisherman's Horizon"
	_button.text = "船出する"
	if _bg:
		_bg.color = Color(0.03, 0.07, 0.12, 1.0)
	if _art:
		_art.modulate = Color(1, 1, 1, 0.45)
	_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	if _continue_button:
		_continue_button.visible = GameState.has_save()   # #93: セーブがある時のみ
	visible = true

func show_victory() -> void:
	# #80: 厳かな雰囲気(深い闇+金色に沈む景色+金文字)
	_title.text = "Fisherman's Horizon 到達!"
	_body.text = "レヴィアタンは討たれた。\nあなたは伝説の漁場 Fisherman's Horizon へ至り、\n人類の食糧難を一挙に解決する英雄となった。\n\n── 完 ──"
	_button.text = "もう一度遊ぶ"
	if _bg:
		_bg.color = Color(0.015, 0.02, 0.045, 1.0)
	if _art:
		_art.modulate = Color(0.85, 0.7, 0.45, 0.25)
	_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	if _continue_button:
		_continue_button.visible = false   # 勝利画面では非表示
	visible = true
