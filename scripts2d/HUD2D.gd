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
var cargo_box: HBoxContainer
var weapon_box: HBoxContainer
var _weapon_labels: Array = []
var notice_box: VBoxContainer
var sonar: Control
var prompt: Label

var _sonar_blips: Array = []   # [{pos:Vector2, color:Color}]
var _guide_pos = null          # #60/#61: ガイド対象のワールド座標(null=なし)
var _home_pos = null           # #76: 直近に寄港した島(緑の弧)
var _player_node: Node2D
var _ui_root: Control

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
	# #68: 帰還キーのヒント(ソナー下)。資金/名声と同じ見やすい白フォントに
	lbl_return = _label("[R]長押し(3秒)で直近の島へ帰還", 17)
	lbl_return.anchor_left = 1.0
	lbl_return.anchor_right = 1.0
	lbl_return.offset_left = -350
	lbl_return.offset_right = -16
	lbl_return.offset_top = 286
	lbl_return.offset_bottom = 312
	lbl_return.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_return.add_theme_constant_override("outline_size", 4)
	lbl_return.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(lbl_return)

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

# 船団が2隻以上のときだけ、画面下中央に陣形1〜4のボタンを出す
func build_formation_bar(on_pick: Callable) -> void:
	if _form_box:
		_form_box.queue_free()
		_form_box = null
	_form_btns.clear()
	pointer_on_ui = false
	if GameState.fleet.size() <= 1:
		return
	_form_box = HBoxContainer.new()
	_form_box.add_theme_constant_override("separation", 6)
	_form_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_form_box.offset_left = -240
	_form_box.offset_right = 240
	_form_box.offset_top = -132
	_form_box.offset_bottom = -96
	_form_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_root().add_child(_form_box)
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

# 選択中の陣形を強調
func set_formation(slot: int) -> void:
	for i in _form_btns.size():
		var b: Button = _form_btns[i]
		b.add_theme_color_override("font_color", Color(1, 0.95, 0.5) if i == slot else Color(0.85, 0.9, 0.95))

func set_prompt(text: String) -> void:
	if prompt:
		prompt.text = text

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
	if sonar:
		sonar.queue_redraw()

# #60/#61: ガイド対象(Vector2かnull)
func set_guide(pos) -> void:
	_guide_pos = pos

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
	var range_px := 220.0 * 6.0
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
	if _home_pos != null:
		var hang: float = ((_home_pos as Vector2) - pp).rotated(-rot).angle()
		sonar.draw_arc(center, r - 3.0, hang - 0.28, hang + 0.28, 14, Color(0.2, 0.95, 0.35, 0.9), 5.0)
	# #60/#61: ガイド方向をソナー外周の赤い弧で示す(距離に関係なく常に表示)
	if _guide_pos != null:
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
