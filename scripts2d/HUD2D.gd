extends CanvasLayer
## HUD2D — 2D版の航海HUD。資金/名声/食料/魚倉/装甲(数値付き#2#4#6)/漁獲物アイコン/
## ソナー(東西南北#18)/武器/通知/大破メッセージ(#8)。3D版HUDの移植。

var lbl_money: Label
var lbl_fame: Label
var lbl_loc: Label
var bar_food: ProgressBar
var bar_hold: ProgressBar
var bar_armor: ProgressBar
var lbl_food_val: Label
var lbl_hold_val: Label
var lbl_armor_val: Label
var lbl_status: Label   # #64: 炎上/毒の表示
var lbl_return: Label   # #68: 帰還長押しの進捗
var lbl_hint: Label     # #241: 出港時のワンポイントヒント
var _hint_box: CenterContainer   # #241再: ヒントを囲む半透明枠
var lbl_catch: Label    # #232再4: 「大漁!」(漁ゲージと同じ位置)
var lbl_guide: Label    # #232: ガイド対象名と残距離
var cargo_box: HBoxContainer
var weapon_box: HBoxContainer
var _weapon_labels: Array = []
var notice_box: VBoxContainer
var sonar: Control
var prompt: Label
var _fishing_meter: Control   # #232: E長押し中の往復ゲージ
var _fishing_value: float = 0.0
var _fishing_bonus: bool = false
const FISHING_BAND_W := 0.176    # #232再4: 発光帯の幅(World2D と同じ値。1.1倍)
var _fishing_band: float = 0.72  # #232再: 発光帯の左端(漁ごとに抽選)

var _sonar_blips: Array = []   # [{pos:Vector2, color:Color}]
var _guide_pos = null          # #60/#61: ガイド対象のワールド座標(null=なし)
var _home_pos = null           # #76: 直近に寄港した島(緑の弧)
var _player_node: Node2D
var _ui_root: Control
var _damage_overlay: Control
var _damage_dir_angle: float = 0.0
var _damage_flash_t: float = 0.0
const OverlayMenus := preload("res://scripts/OverlayMenus.gd")

func _ready() -> void:
	layer = 10
	_build()

func _root() -> Control:
	if _ui_root == null:
		_ui_root = Control.new()
		_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ui_root)
	return _ui_root

func _build() -> void:
	var root := _root()
	# 左上: 資金/名声
	var tl := PanelContainer.new()
	_style(tl)
	root.add_child(tl)
	tl.position = Vector2(16, 16)
	var vb := VBoxContainer.new()
	tl.add_child(vb)
	lbl_money = _label("資金: 0", 22)
	lbl_fame = _label("名声: 0", 22)
	vb.add_child(lbl_money)
	vb.add_child(lbl_fame)

	# 右上: 場所
	var tr := PanelContainer.new()
	_style(tr)
	root.add_child(tr)
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -270
	tr.offset_right = -16
	tr.offset_top = 16
	tr.offset_bottom = 56
	lbl_loc = _label("航海中", 20)
	tr.add_child(lbl_loc)

	# #236: 航海中も操作・武器一覧へ戻れる早見表ボタン。
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.tooltip_text = "操作・武器 早見表"
	help_btn.add_theme_font_size_override("font_size", 22)
	help_btn.anchor_left = 1.0
	help_btn.anchor_right = 1.0
	help_btn.offset_left = -326
	help_btn.offset_right = -278
	help_btn.offset_top = 16
	help_btn.offset_bottom = 56
	help_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	help_btn.mouse_entered.connect(func(): pointer_on_ui = true)
	help_btn.mouse_exited.connect(func(): pointer_on_ui = false)
	help_btn.pressed.connect(func(): OverlayMenus.show_help(root))
	root.add_child(help_btn)

	# ソナー(右上)
	sonar = Control.new()
	sonar.anchor_left = 1.0
	sonar.anchor_right = 1.0
	sonar.offset_left = -226
	sonar.offset_right = -16
	sonar.offset_top = 70
	sonar.offset_bottom = 280
	sonar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sonar.draw.connect(_draw_sonar)
	root.add_child(sonar)
	# #232: 赤いガイド弧の直下に対象名と概算残距離を表示
	lbl_guide = _label("", 17)
	lbl_guide.anchor_left = 1.0
	lbl_guide.anchor_right = 1.0
	lbl_guide.offset_left = -350   # #232再: 下の[R]帰還ヒントと中心をそろえる
	lbl_guide.offset_right = -16
	lbl_guide.offset_top = 282
	lbl_guide.offset_bottom = 308
	lbl_guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_guide.add_theme_color_override("font_color", Color(1.0, 0.72, 0.64))
	lbl_guide.add_theme_constant_override("outline_size", 4)
	lbl_guide.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(lbl_guide)

	# #68: 帰還キーのヒント(ソナー下)。資金/名声と同じ見やすい白フォントに
	lbl_return = _label("[R]長押し(3秒)で直近の島へ帰還", 17)
	lbl_return.anchor_left = 1.0
	lbl_return.anchor_right = 1.0
	lbl_return.offset_left = -350
	lbl_return.offset_right = -16
	lbl_return.offset_top = 312
	lbl_return.offset_bottom = 338
	lbl_return.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_return.add_theme_constant_override("outline_size", 4)
	lbl_return.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(lbl_return)

	# #233: 被弾方向フラッシュと低装甲ビネットは全画面の最前面へ描画
	_damage_overlay = Control.new()
	_damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_overlay.draw.connect(_draw_damage_feedback)
	root.add_child(_damage_overlay)

	# 左下: 漁獲物パネル(#2)
	var cargo_panel := PanelContainer.new()
	_style(cargo_panel)
	root.add_child(cargo_panel)
	cargo_panel.anchor_left = 0.0
	cargo_panel.anchor_right = 0.0
	cargo_panel.anchor_top = 1.0
	cargo_panel.anchor_bottom = 1.0
	cargo_panel.offset_left = 16
	cargo_panel.offset_right = 500
	cargo_panel.offset_top = -246
	cargo_panel.offset_bottom = -158
	var cvb := VBoxContainer.new()
	cargo_panel.add_child(cvb)
	cvb.add_child(_label("漁獲物", 15))
	cargo_box = HBoxContainer.new()
	cargo_box.add_theme_constant_override("separation", 6)
	cvb.add_child(cargo_box)

	# 左下: バー(#4/#6)
	var bl := PanelContainer.new()
	_style(bl)
	root.add_child(bl)
	bl.anchor_left = 0.0
	bl.anchor_right = 0.0
	bl.anchor_top = 1.0
	bl.anchor_bottom = 1.0
	bl.offset_left = 16
	bl.offset_right = 430
	bl.offset_top = -150
	bl.offset_bottom = -16
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bl.add_child(bv)
	bar_food = _bar(Color(0.4, 0.85, 0.4))
	bar_hold = _bar(Color(0.4, 0.6, 0.95))
	bar_armor = _bar(Color(0.95, 0.75, 0.3))
	lbl_food_val = _label("", 15)
	lbl_hold_val = _label("", 15)
	lbl_armor_val = _label("", 15)
	bv.add_child(_bar_row("燃料", bar_food, lbl_food_val))
	bv.add_child(_bar_row("魚倉", bar_hold, lbl_hold_val))
	bv.add_child(_bar_row("装甲", bar_armor, lbl_armor_val))
	# #64: 炎上/毒の状態異常表示
	lbl_status = _label("", 16)
	lbl_status.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	bv.add_child(lbl_status)

	# 下中央: 武器スロット
	weapon_box = HBoxContainer.new()
	weapon_box.add_theme_constant_override("separation", 8)
	weapon_box.anchor_left = 0.5
	weapon_box.anchor_right = 0.5
	weapon_box.anchor_top = 1.0
	weapon_box.anchor_bottom = 1.0
	weapon_box.offset_left = -220
	weapon_box.offset_right = 220
	weapon_box.offset_top = -64
	weapon_box.offset_bottom = -16
	root.add_child(weapon_box)

	# #241: 出港時のワンポイントヒント(武器スロットの上に3秒)
	# #241再: 資金・名声などと同じ半透明グレーの枠に入れて読みやすくする。
	# 枠は中身の幅に合わせたいので CenterContainer で包む(全幅の帯にしない)。
	_hint_box = CenterContainer.new()
	_hint_box.anchor_left = 0.5
	_hint_box.anchor_right = 0.5
	_hint_box.anchor_top = 1.0
	_hint_box.anchor_bottom = 1.0
	_hint_box.offset_left = -560
	_hint_box.offset_right = 560
	_hint_box.offset_top = -156   # 案内文(-110)よりさらに上。武器スロットとも重ならない
	_hint_box.offset_bottom = -110
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.visible = false
	root.add_child(_hint_box)
	var hint_panel := PanelContainer.new()
	_style(hint_panel)   # 資金/名声パネルと同じ半透明グレー+角丸
	_hint_box.add_child(hint_panel)
	lbl_hint = _label("", 21)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.add_theme_color_override("font_color", Color(0.78, 0.96, 1.0))
	lbl_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(lbl_hint)

	# 中央下: 案内
	prompt = _label("", 22)
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = -110
	prompt.offset_bottom = -76
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color(1, 1, 0.6))
	root.add_child(prompt)

	# #232: 漁の技術介入ゲージ。黄色帯で離すと獲得量2倍
	_fishing_meter = Control.new()
	_fishing_meter.anchor_left = 0.5
	_fishing_meter.anchor_right = 0.5
	_fishing_meter.anchor_top = 1.0
	_fishing_meter.anchor_bottom = 1.0
	_fishing_meter.offset_left = -170
	_fishing_meter.offset_right = 170
	_fishing_meter.offset_top = -142
	_fishing_meter.offset_bottom = -120
	_fishing_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fishing_meter.visible = false
	_fishing_meter.draw.connect(_draw_fishing_meter)
	root.add_child(_fishing_meter)
	# #232再4: 「大漁!」は漁ゲージが出ていたその場所に表示する
	lbl_catch = _label("", 22)
	lbl_catch.anchor_left = 0.5
	lbl_catch.anchor_right = 0.5
	lbl_catch.anchor_top = 1.0
	lbl_catch.anchor_bottom = 1.0
	lbl_catch.offset_left = -170
	lbl_catch.offset_right = 170
	lbl_catch.offset_top = -146
	lbl_catch.offset_bottom = -114
	lbl_catch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_catch.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	lbl_catch.add_theme_constant_override("outline_size", 6)
	lbl_catch.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_catch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_catch.visible = false
	root.add_child(lbl_catch)

	# 通知トースト
	notice_box = VBoxContainer.new()
	notice_box.anchor_left = 0.5
	notice_box.anchor_right = 0.5
	notice_box.offset_left = -260
	notice_box.offset_right = 260
	notice_box.offset_top = 90
	notice_box.offset_bottom = 300
	root.add_child(notice_box)

	GameState.notice.connect(show_notice)
	GameState.stats_changed.connect(rebuild_cargo)
	rebuild_weapons()
	rebuild_cargo()
	refresh_money_fame()

func _style(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _label(t: String, sz: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l

func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(200, 18)
	b.show_percentage = false
	b.max_value = 1.0
	b.value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	bg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", bg)
	return b

func _bar_row(name: String, bar: ProgressBar, val_label: Label) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _label(name, 18)
	l.custom_minimum_size = Vector2(48, 0)
	h.add_child(l)
	h.add_child(bar)
	val_label.custom_minimum_size = Vector2(96, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val_label)
	return h

func update_bars() -> void:
	bar_food.value = clampf(GameState.run_food / maxf(GameState.max_food(), 1.0), 0, 1)
	bar_hold.value = clampf(float(GameState.used_hold()) / maxf(float(GameState.max_hold()), 1.0), 0, 1)
	bar_armor.value = clampf(GameState.run_armor / maxf(GameState.max_armor(), 1.0), 0, 1)
	lbl_food_val.text = "%d%%" % int(bar_food.value * 100)
	lbl_hold_val.text = "%d/%d 残%d" % [GameState.used_hold(), GameState.max_hold(), GameState.free_hold()]
	lbl_armor_val.text = "%d/%d" % [int(GameState.run_armor), int(GameState.max_armor())]
	# #64: 状態異常の常時表示
	if lbl_status:
		var st: Array = []
		if GameState.burn_t > 0.0:
			st.append("炎上中(あと%d秒)" % int(ceil(GameState.burn_t)))
		if GameState.poison_t > 0.0:
			st.append("毒(あと%d秒)" % int(ceil(GameState.poison_t)))
		lbl_status.text = "  ".join(st)
		lbl_status.visible = not st.is_empty()

func rebuild_cargo() -> void:
	if cargo_box == null:
		return
	for c in cargo_box.get_children():
		c.queue_free()
	if GameState.cargo.is_empty():
		cargo_box.add_child(_label("(なし)", 14))
		return
	for id in GameState.cargo:
		cargo_box.add_child(_cargo_icon(id, int(GameState.cargo[id])))

func _cargo_icon(id: String, qty: int) -> Control:
	var holder := PanelContainer.new()
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.18, 0.9)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(2)
	holder.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	holder.add_child(vb)
	var path := ""
	if Database.fish.has(id): path = "res://assets/images/fish_%s.png" % id
	elif Database.combat_mobs.has(id): path = "res://assets/images/mob_%s.png" % id
	elif Database.lords.has(id): path = "res://assets/images/lord_%s.png" % id
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(48, 30)
		vb.add_child(tr)
	else:
		var n := _label(id, 12)
		n.custom_minimum_size = Vector2(48, 30)
		vb.add_child(n)
	var cnt := _label("x%d" % qty, 13)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cnt)
	return holder

func refresh_money_fame() -> void:
	if lbl_money:
		lbl_money.text = "資金: %d" % GameState.money
	if lbl_fame:
		lbl_fame.text = "名声: %d" % GameState.fame

func set_location(text: String) -> void:
	if lbl_loc:
		lbl_loc.text = text

# ---------------- 陣形ボタン(#196) ----------------
var _form_box: HBoxContainer
var _form_btns: Array = []
var pointer_on_ui: bool = false   # #196再: 陣形ボタン上ではロック/射撃をしない
var _skill_btn: Button            # #224: 陣形スキルのボタン
var _skill_cover: ColorRect
var _skill_holder: Control
var _on_skill: Callable = Callable()

# スキルボタンは旗艦1隻でも表示する。陣形1〜4のボタンは船団が2隻以上のときだけ出す。
func build_formation_bar(on_pick: Callable, on_skill: Callable = Callable()) -> void:
	_on_skill = on_skill
	if _form_box:
		_form_box.queue_free()
		_form_box = null
	_form_btns.clear()
	_skill_btn = null
	_skill_cover = null
	_skill_holder = null
	pointer_on_ui = false
	_form_box = HBoxContainer.new()
	_form_box.add_theme_constant_override("separation", 6)
	# #196再9: 画面上部中央へ配置
	_form_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_form_box.offset_left = -240
	_form_box.offset_right = 240
	_form_box.offset_top = 14
	_form_box.offset_bottom = 50
	_form_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_root().add_child(_form_box)
	if GameState.visited_islands.has(1) and GameState.fleet.size() > 1:
		for i in 4:
			var b := Button.new()
			b.text = "陣形%d" % (i + 1)
			b.add_theme_font_size_override("font_size", 16)
			b.focus_mode = Control.FOCUS_NONE
			var idx: int = i
			b.pressed.connect(func(): on_pick.call(idx))
			b.mouse_entered.connect(func(): pointer_on_ui = true)
			b.mouse_exited.connect(func(): pointer_on_ui = false)
			_form_box.add_child(b)
			_form_btns.append(b)
		set_formation(GameState.formation_slot)
	# #224: 陣形4の右にスキルボタン。使用可能なら赤枠、クールダウン中は左から右へグレーが解除される
	if _on_skill.is_valid():
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(196, 34)   # #224再: 「スキル(5キー): 一斉射撃」が収まる幅
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_form_box.add_child(holder)
		_skill_btn = Button.new()
		_skill_btn.text = "スキル(5キー)"
		_skill_btn.add_theme_font_size_override("font_size", 16)
		_skill_btn.focus_mode = Control.FOCUS_NONE
		_skill_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_skill_btn.pressed.connect(func(): _on_skill.call())
		_skill_btn.mouse_entered.connect(func(): pointer_on_ui = true)
		_skill_btn.mouse_exited.connect(func(): pointer_on_ui = false)
		holder.add_child(_skill_btn)
		# クールダウン中の覆い(右側に残り、左から解除される)
		_skill_cover = ColorRect.new()
		_skill_cover.color = Color(0.1, 0.1, 0.12, 0.72)
		_skill_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skill_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(_skill_cover)
		_skill_holder = holder
		set_skill_state("", 1.0, true)

# #224: スキルボタンの表示更新。progress=0..1(1で使用可能)
func set_skill_state(skill_name: String, progress: float, ready_now: bool) -> void:
	if _skill_btn == null or not is_instance_valid(_skill_btn):
		return
	if skill_name != "":
		# #224再: キーボードでも撃てることが分かるようキー名を併記
		_skill_btn.text = "スキル(5キー): %s" % skill_name
	if _skill_cover:
		var w: float = _skill_holder.size.x if _skill_holder else 196.0
		# 左から解除=覆いの左端を右へずらす
		_skill_cover.offset_left = w * clampf(progress, 0.0, 1.0)
		_skill_cover.visible = not ready_now
	# 使用可能なら赤囲み、クールダウン中は枠なし
	if ready_now:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.18, 0.22, 0.92)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(3)
		sb.border_color = Color(1.0, 0.2, 0.15)
		_skill_btn.add_theme_stylebox_override("normal", sb)
		_skill_btn.add_theme_stylebox_override("hover", sb)
	else:
		_skill_btn.remove_theme_stylebox_override("normal")
		_skill_btn.remove_theme_stylebox_override("hover")

# 選択中の陣形を強調
func set_formation(slot: int) -> void:
	for i in _form_btns.size():
		var b: Button = _form_btns[i]
		b.add_theme_color_override("font_color", Color(1, 0.95, 0.5) if i == slot else Color(0.85, 0.9, 0.95))

# #241: 出港時のワンポイントヒントを一定時間だけ表示する
func show_departure_hint(text: String, hold := 5.0) -> void:   # #241再3: 3秒→5秒
	if lbl_hint == null or _hint_box == null or text.strip_edges() == "":
		return
	lbl_hint.text = "ヒント：%s" % text
	_hint_box.visible = true
	_hint_box.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(_hint_box, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): _hint_box.visible = false)

# #232再4: 漁ゲージがあった位置に「大漁!」を出す
func show_catch_bonus(text: String, hold := 1.2) -> void:
	if lbl_catch == null:
		return
	lbl_catch.text = text
	lbl_catch.visible = true
	lbl_catch.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(lbl_catch, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): lbl_catch.visible = false)

func set_prompt(text: String) -> void:
	if prompt:
		prompt.text = text

# #232再: band_start=発光帯の左端(0〜1)。漁のたびにWorld2Dが抽選して渡す
func set_fishing_meter(value: float, visible_now: bool, band_start: float = 0.72) -> void:
	_fishing_value = clampf(value, 0.0, 1.0)
	_fishing_band = clampf(band_start, 0.0, 1.0 - FISHING_BAND_W)
	_fishing_bonus = _fishing_value >= _fishing_band and _fishing_value <= _fishing_band + FISHING_BAND_W
	if _fishing_meter:
		_fishing_meter.visible = visible_now
		_fishing_meter.queue_redraw()

func _draw_fishing_meter() -> void:
	if _fishing_meter == null:
		return
	var sz := _fishing_meter.size
	_fishing_meter.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.08, 0.12, 0.9), true)
	_fishing_meter.draw_rect(Rect2(Vector2(sz.x * _fishing_band, 1), Vector2(sz.x * FISHING_BAND_W, sz.y - 2)), Color(1.0, 0.88, 0.18, 0.75), true)
	var x := sz.x * _fishing_value
	_fishing_meter.draw_line(Vector2(x, 0), Vector2(x, sz.y), Color.WHITE if not _fishing_bonus else Color(1.0, 1.0, 0.3), 5.0)
	_fishing_meter.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.65, 0.9, 1.0, 0.8), false, 2.0)

func rebuild_weapons() -> void:
	if weapon_box == null:
		return
	for c in weapon_box.get_children():
		c.queue_free()
	_weapon_labels.clear()
	var slots := int(GameState.ship().slots)
	for i in slots:
		var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
		var p := PanelContainer.new()
		_style(p)
		p.custom_minimum_size = Vector2(104, 48)
		var nm := "空"
		if wid != "" and Database.weapons.has(wid):
			nm = Database.weapons[wid].name
		var vbx := VBoxContainer.new()
		vbx.add_theme_constant_override("separation", 0)
		vbx.add_child(_label("%d:%s" % [i + 1, nm], 15))
		var ammo := _label("", 13)
		ammo.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		vbx.add_child(ammo)
		_weapon_labels.append(ammo)
		p.add_child(vbx)
		weapon_box.add_child(p)

# 残弾/リロード表示(#27)
func update_ammo(texts: Array) -> void:
	for i in _weapon_labels.size():
		if i < texts.size() and is_instance_valid(_weapon_labels[i]):
			_weapon_labels[i].text = str(texts[i])

func show_notice(text: String) -> void:
	refresh_money_fame()
	var l := _label(text, 20)
	l.add_theme_color_override("font_color", Color(1, 1, 0.7))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_box.add_child(l)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func show_big_message(text: String, hold := 1.4) -> void:
	var l := _label(text, 42)
	l.add_theme_color_override("font_color", Color(1, 0.55, 0.4))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.4
	l.anchor_bottom = 0.4
	l.offset_left = -420
	l.offset_right = 420
	l.offset_top = -40
	l.offset_bottom = 40
	_root().add_child(l)
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

# --- ソナー ---
func set_sonar_data(player: Node2D, blips: Array) -> void:
	_player_node = player
	_sonar_blips = blips
	_update_guide_label()
	if sonar:
		sonar.queue_redraw()

# #60/#61: ガイド対象(Vector2かnull)
func set_guide(pos) -> void:
	_guide_pos = pos
	_update_guide_label()

func _update_guide_label() -> void:
	if lbl_guide == null:
		return
	if _guide_pos == null or _player_node == null or GameState.boss_rush:
		lbl_guide.text = ""
		return
	var g: Dictionary = GameState.guide_target
	var nm := "目的地"
	if str(g.get("kind", "")) == "island":
		var iid := int(g.get("id", -1))
		if iid >= 0 and iid < Database.islands.size():
			nm = str(Database.island(iid).name)
	elif str(g.get("kind", "")) == "lord":
		var lid := str(g.get("id", ""))
		if Database.lords.has(lid):
			nm = str(Database.lords[lid].name)
	var dist := int(round((_player_node.global_position.distance_to(_guide_pos as Vector2) / 6.0) / 10.0) * 10.0)
	lbl_guide.text = "ガイド: %s まで 約%d" % [nm, dist]

func show_damage_direction(relative_source: Vector2) -> void:
	if relative_source.length_squared() > 0.01:
		_damage_dir_angle = relative_source.angle()
	_damage_flash_t = 0.3
	if _damage_overlay:
		_damage_overlay.queue_redraw()

func _process(delta: float) -> void:
	if _damage_flash_t > 0.0:
		_damage_flash_t = maxf(_damage_flash_t - delta, 0.0)
	if _damage_overlay:
		_damage_overlay.queue_redraw()

func _draw_damage_feedback() -> void:
	if _damage_overlay == null:
		return
	var sz := _damage_overlay.size
	var center := sz * 0.5
	if _damage_flash_t > 0.0:
		var radius := maxf(minf(sz.x, sz.y) * 0.5 - 24.0, 80.0)
		var alpha := clampf(_damage_flash_t / 0.3, 0.0, 1.0)
		_damage_overlay.draw_arc(center, radius, _damage_dir_angle - 0.32, _damage_dir_angle + 0.32, 24, Color(1.0, 0.05, 0.03, 0.9 * alpha), 13.0)
	# #233再: 低装甲のビネットは「赤みを濃く・内側の境界をぼかす」。
	# 一本の太い矩形枠だと内側に硬い線が出るので、細い枠を内側へ向かって
	# 少しずつ薄くしながら重ね、グラデーションで減衰させる。
	if GameState.run_armor / maxf(GameState.max_armor(), 1.0) <= 0.25 and GameState.at_sea:
		var steps := 22
		var band := 62.0                     # ぼかしの幅(内側へ何px滲ませるか)
		var step_w := band / float(steps)
		for i in steps:
			var t: float = float(i) / float(steps - 1)   # 0=外周 1=内側
			# 外周は濃く、内側へ向けて二次関数的に消える
			var a: float = 0.42 * pow(1.0 - t, 2.0)
			var inset: float = 2.0 + band * t
			_damage_overlay.draw_rect(
				Rect2(Vector2(inset, inset), sz - Vector2(inset * 2.0, inset * 2.0)),
				Color(0.62, 0.0, 0.0, a), false, step_w + 1.0)

# #76: 直近に寄港した島(緑の弧)
func set_home_guide(pos) -> void:
	_home_pos = pos

# #68: 帰還長押しの進捗(0.0〜1.0)。0で通常ヒントへ戻す
func set_return_progress(t: float) -> void:
	if lbl_return == null:
		return
	if t <= 0.0:
		lbl_return.text = "[R]長押し(3秒)で直近の島へ帰還"
		lbl_return.add_theme_color_override("font_color", Color.WHITE)
	else:
		var secs: float = ceil((1.0 - clampf(t, 0.0, 1.0)) * 3.0)
		var bars := int(clampf(t, 0.0, 1.0) * 10.0)
		lbl_return.text = "帰還まで %d秒  [%s%s]" % [int(secs), "■".repeat(bars), "・".repeat(10 - bars)]
		lbl_return.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))

func _draw_sonar() -> void:
	var r := 105.0
	var center := Vector2(r, r)
	sonar.draw_circle(center, r, Color(0.05, 0.15, 0.2, 0.7))
	sonar.draw_arc(center, r, 0, TAU, 48, Color(0.3, 0.8, 0.9, 0.6), 2.0)
	if _player_node == null:
		return
	var weather_mult := 0.75 if GameState.active_weather == "night" and not GameState.boss_rush else 1.0
	var range_px := 220.0 * 6.0 * GameState.sonar_range_mult() * weather_mult   # #201/#232: 夜はソナー範囲-25%
	var pp := _player_node.global_position
	var rot := _player_node.rotation
	# 東西南北(#18): 自機の向きが上
	var font := ThemeDB.fallback_font
	var compass := [["北", Vector2(0, -1)], ["東", Vector2(1, 0)], ["南", Vector2(0, 1)], ["西", Vector2(-1, 0)]]
	for c in compass:
		var v: Vector2 = (c[1] as Vector2).rotated(-rot)
		var pos := center + v * (r - 13) - Vector2(7, -6)
		sonar.draw_string(font, pos, c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.97, 1.0))
	# #76: 直近に寄港した島の方向を緑の弧で示す(常時)
	# #209再8: ボスラッシュには寄港の概念がないので緑の弧も出さない
	if _home_pos != null and not GameState.boss_rush:
		var hang: float = ((_home_pos as Vector2) - pp).rotated(-rot).angle()
		sonar.draw_arc(center, r - 3.0, hang - 0.28, hang + 0.28, 14, Color(0.2, 0.95, 0.35, 0.9), 5.0)
	# #60/#61: ガイド方向をソナー外周の赤い弧で示す(距離に関係なく常に表示)
	# #209再7: ボスラッシュには目的地の概念がないので赤い弧は出さない
	if _guide_pos != null and not GameState.boss_rush:
		var gang: float = ((_guide_pos as Vector2) - pp).rotated(-rot).angle()
		sonar.draw_arc(center, r - 3.0, gang - 0.35, gang + 0.35, 16, Color(1.0, 0.12, 0.08, 0.95), 6.0)
	for b in _sonar_blips:
		var rel: Vector2 = ((b.pos as Vector2) - pp).rotated(-rot) / range_px * r
		if rel.length() > r - 4:
			continue
		sonar.draw_circle(center + rel, 4.0, b.color)
	var tri := PackedVector2Array([
		center + Vector2(0, -9), center + Vector2(-5, 5), center + Vector2(5, 5)])
	sonar.draw_colored_polygon(tri, Color.WHITE)
