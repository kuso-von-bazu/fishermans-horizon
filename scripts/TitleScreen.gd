extends CanvasLayer
## TitleScreen — タイトル/勝利のフルスクリーン・オーバーレイ。
## show_title(): 開始画面。 show_victory(): レヴィアタン討伐後のエンディング。
## レイアウトは CenterContainer で常に画面中央に収まるようにし、解像度に依存しない。

signal start_pressed
signal continue_pressed
signal boss_rush_pressed   # #209

var _root: Control
var _title: Label
var _body: Label
var _button: Button
var _continue_button: Button
var _bg: ColorRect
var _art: TextureRect
var _logo: TextureRect   # #175: タイトルロゴ(錨・船・大砲・羅針盤の紋章)
var _boss_rush_button: Button   # #209: エンディング到達後に右上へ表示
var _crown: TextureRect   # #209再2: ボスラッシュ制覇の証(ボタンの左に表示)
var _night_sky: Control   # #209再2: 制覇画面の三日月と星空
var _art_br: TextureRect  # #209再3: 制覇画面の前景(水平線から下の海・漁船・島)

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
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	# #175: ロゴ画像があれば紋章として最上部に表示(文字タイトルは冗長になるので隠す)
	if ResourceLoader.exists("res://assets/images/logo.png"):
		_logo = TextureRect.new()
		_logo.texture = load("res://assets/images/logo.png")
		_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(_logo)
		# #175再: フルスクリーン(論理縦720)でも下部のBGM表記が見切れないよう
		# ロゴ高さを画面の高さに追従させる(画面縦の約34%上限)。リサイズにも対応。
		_fit_logo()
		get_viewport().size_changed.connect(_fit_logo)

	_title = Label.new()
	_title.text = "Fisherman's Horizon"
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_body = Label.new()
	_body.text = "海面上昇に沈んだ世界。粗末な蒸気漁船から始め、漁と狩りで身を立て、\n近海の主を討ち、海賊を狩り、名声を轟かせて未踏の漁場を目指せ。\n人類種の天敵レヴィアタンを討ち、伝説の漁場へ至るのだ。\n\n[W/S]前進・後進   [A/D]旋回   [マウス]照準   [左クリック]射撃\n[右クリック]魚雷(ロックオン時のみ)   [E]漁・寄港   [R]ファストトラベル
[敵をクリック]ロックオン   [マウスホイール]ロックオン対象の切替   [1〜4]陣形チェンジ   [5]スキル発動\n燃料が尽きる前に帰港せよ"
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

	# #209: 画面右上のボスラッシュボタン(エンディング到達後のみ表示)
	_boss_rush_button = Button.new()
	_boss_rush_button.text = "Boss Rush"
	_boss_rush_button.add_theme_font_size_override("font_size", 22)
	_boss_rush_button.custom_minimum_size = Vector2(180, 48)
	_boss_rush_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_boss_rush_button.offset_left = -204
	_boss_rush_button.offset_right = -24
	_boss_rush_button.offset_top = 24
	_boss_rush_button.offset_bottom = 72
	_boss_rush_button.pressed.connect(func(): emit_signal("boss_rush_pressed"))
	_gild_boss_rush_button()   # #209再: 金色の豪華な縁取り
	_root.add_child(_boss_rush_button)

	# #209再2: ボスラッシュ制覇後、ボタンの左側に王冠を表示する
	if ResourceLoader.exists("res://assets/images/crown.png"):
		_crown = TextureRect.new()
		_crown.texture = load("res://assets/images/crown.png")
		_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crown.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_crown.offset_left = -262      # ボタン(-204..-24)の左隣
		_crown.offset_right = -210
		_crown.offset_top = 20
		_crown.offset_bottom = 76
		_crown.visible = false
		_root.add_child(_crown)

	# #90: BGM著作権表示(MusMus)
	var credit := Label.new()
	credit.text = "BGM: フリーBGM・音楽素材MusMus  https://musmus.main.jp"
	credit.add_theme_font_size_override("font_size", 14)
	credit.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(credit)

# #209再: Boss Rush ボタンを金色の豪華な縁取りで飾る。
# 外周に太い金枠、内側に細い明るい金のラインを重ねて二重の額縁に見せ、
# 文字も金色にして押下・ホバーで明るさが変わるようにする。
func _gild_boss_rush_button() -> void:
	var gold_dark := Color(0.42, 0.30, 0.06)
	var gold := Color(0.85, 0.68, 0.24)
	var gold_lit := Color(1.0, 0.88, 0.48)

	var mk := func(bg_top: Color, border: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg_top
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(4)
		sb.border_color = border
		sb.shadow_color = Color(0.85, 0.68, 0.24, 0.45)
		sb.shadow_size = 8
		sb.set_expand_margin_all(2)
		return sb

	_boss_rush_button.add_theme_stylebox_override("normal", mk.call(Color(0.10, 0.08, 0.03, 0.95), gold))
	_boss_rush_button.add_theme_stylebox_override("hover", mk.call(Color(0.20, 0.15, 0.05, 0.97), gold_lit))
	_boss_rush_button.add_theme_stylebox_override("pressed", mk.call(Color(0.06, 0.05, 0.02, 0.98), gold_dark))
	_boss_rush_button.add_theme_stylebox_override("focus", mk.call(Color(0.10, 0.08, 0.03, 0.95), gold))
	_boss_rush_button.add_theme_color_override("font_color", gold_lit)
	_boss_rush_button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.72))
	_boss_rush_button.add_theme_color_override("font_pressed_color", gold)
	_boss_rush_button.add_theme_constant_override("outline_size", 4)
	_boss_rush_button.add_theme_color_override("font_outline_color", Color(0.25, 0.16, 0.02, 0.9))

	# 内側の細い金ライン(額縁の二重線)。ボタンより一回り小さく重ねる
	var inner := Panel.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 5
	inner.offset_top = 5
	inner.offset_right = -5
	inner.offset_bottom = -5
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0, 0, 0, 0)
	isb.set_corner_radius_all(6)
	isb.set_border_width_all(1)
	isb.border_color = Color(1.0, 0.92, 0.60, 0.75)
	inner.add_theme_stylebox_override("panel", isb)
	_boss_rush_button.add_child(inner)

# #209再2: ボスラッシュ制覇画面の背景。三日月と満点の星空を手続き的に描く。
# 星は種を固定した乱数で配置するので、毎回同じ夜空になる。
func _build_night_sky() -> void:
	if _night_sky != null and is_instance_valid(_night_sky):
		return
	_night_sky = Control.new()
	_night_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night_sky.set_script(preload("res://scripts/NightSky.gd"))
	_root.add_child(_night_sky)
	_root.move_child(_night_sky, 1)   # 背景色のすぐ上、文字より下

# #209再3: 制覇画面の前景。水平線より下だけを残した背景画を星空の上に重ね、
# 「同じ構図のまま空だけ夜空」に見せる(遠方のレヴィアタンは空ごと置き換わる)。
func _build_br_art() -> void:
	if _art_br != null and is_instance_valid(_art_br):
		return
	if not ResourceLoader.exists("res://assets/images/title_brwin.png"):
		return
	_art_br = TextureRect.new()
	_art_br.texture = load("res://assets/images/title_brwin.png")
	_art_br.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_br.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art_br.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_br.modulate = Color(0.34, 0.46, 0.76, 0.95)   # 夕景を月明かりの夜へ寄せる
	_art_br.visible = false
	_root.add_child(_art_br)
	_root.move_child(_art_br, 2)   # 星空(1)の上、文字より下

func _fit_logo() -> void:
	# #175再: ロゴ高さを画面縦に追従(約30%、160〜300pxに制限)。横は元画像比を維持。
	if not _logo:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var h := clampf(vp.get_visible_rect().size.y * 0.30, 160.0, 300.0)
	var aspect := 1672.0 / 941.0   # 生成ロゴの縦横比
	_logo.custom_minimum_size = Vector2(h * aspect, h)

func show_title() -> void:
	_title.text = "Fisherman's Horizon"
	_button.text = "船出する"
	if _bg:
		_bg.color = Color(0.03, 0.07, 0.12, 1.0)
	if _art:
		_art.modulate = Color(1, 1, 1, 0.45)
	_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	# #175: ロゴがあれば紋章を表示し文字タイトルは隠す
	if _logo:
		_logo.visible = true
		_title.visible = false
	if _continue_button:
		_continue_button.visible = GameState.has_save()   # #93: セーブがある時のみ
	if _boss_rush_button:
		# #209: エンディング到達後、かつ本編のセーブ(船団)がある時だけ遊べる
		_boss_rush_button.visible = GameState.has_cleared() and GameState.has_save()
	if _crown:
		# #209再2: ボスラッシュを制覇していれば王冠を灯す
		_crown.visible = _boss_rush_button.visible and GameState.has_cleared_boss_rush()
	if _night_sky:
		_night_sky.visible = false
	if _art_br:
		_art_br.visible = false
	visible = true

func show_victory(night := false) -> void:
	# #80: 厳かな雰囲気(深い闇+金色に沈む景色+金文字)
	if night:
		# #209: ボスラッシュ制覇。通常エンディングを夜にした背景+専用メッセージ
		_title.text = "Boss Rush 制覇!"
		_body.text = "おめでとう!あなたこそ真の海の王者です!"
		_button.text = "タイトルへ"
		if _bg:
			_bg.color = Color(0.010, 0.014, 0.040, 1.0)
		# #209再3: 通常エンディングと同じ構図(海・漁船・島)を活かしつつ、
		# 水平線より上(遠方のレヴィアタンがいた空)は星空と三日月に置き換える
		if _art:
			_art.visible = false
		_build_night_sky()
		if _night_sky:
			_night_sky.visible = true
		_build_br_art()
		if _art_br:
			_art_br.visible = true
		_title.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	else:
		_title.text = "Fisherman's Horizon 到達!"
		_body.text = "レヴィアタンは討たれた。\nあなたは伝説の漁場 Fisherman's Horizon へ至り、\n人類の食糧難を一挙に解決する英雄となった。\n\n── 完 ──"
		_button.text = "もう一度遊ぶ"
		if _bg:
			_bg.color = Color(0.015, 0.02, 0.045, 1.0)
		if _art:
			_art.visible = true
			_art.modulate = Color(0.85, 0.7, 0.45, 0.25)
		if _night_sky:
			_night_sky.visible = false
		if _art_br:
			_art_br.visible = false
		_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	# #175: 勝利画面ではロゴを隠して文字タイトル(到達!)を見せる
	if _logo:
		_logo.visible = false
	_title.visible = true
	if _continue_button:
		_continue_button.visible = false   # 勝利画面では非表示
	if _boss_rush_button:
		_boss_rush_button.visible = false
	if _crown:
		_crown.visible = false   # #209再3: 制覇画面では王冠を表示しない
	visible = true
