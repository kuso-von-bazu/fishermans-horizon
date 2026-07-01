extends CanvasLayer
## HUD — 航海中の情報表示(資金/名声/食料/魚倉/装甲/武器/ソナー/通知/照準)。
## World から update_bars() と set_sonar_data() を毎フレーム呼ばれる。

var lbl_money: Label
var lbl_fame: Label
var lbl_loc: Label
var bar_food: ProgressBar
var bar_hold: ProgressBar
var bar_armor: ProgressBar
var lbl_food_val: Label
var lbl_hold_val: Label
var lbl_armor_val: Label
var cargo_panel: PanelContainer
var cargo_box: HBoxContainer
var weapon_box: HBoxContainer
var notice_box: VBoxContainer
var crosshair: Control
var sonar: Control
var prompt: Label

var _sonar_blips: Array = []   # [{pos:Vector3, color:Color}]
var _player_node: Node3D

func _ready() -> void:
	layer = 10
	_build()

func _make_panel(pos: Vector2, size: Vector2, anchor_right := false, anchor_bottom := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	add_control(p)
	p.position = pos
	p.size = size
	return p

func add_control(c: Control) -> void:
	if get_child_count() == 0 or not (get_child(0) is Control):
		pass
	_root().add_child(c)

var _ui_root: Control
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
	tr.set_anchor(SIDE_LEFT, 1)
	tr.set_anchor(SIDE_RIGHT, 1)
	tr.position = Vector2(-260, 16)
	tr.size = Vector2(244, 40)
	lbl_loc = _label("航海中", 20)
	tr.add_child(lbl_loc)

	# 右上ソナー(場所パネルの下)
	sonar = Control.new()
	sonar.custom_minimum_size = Vector2(200, 200)
	sonar.set_anchor(SIDE_LEFT, 1)
	sonar.set_anchor(SIDE_RIGHT, 1)
	sonar.position = Vector2(-216, 70)
	sonar.size = Vector2(200, 200)
	sonar.draw.connect(_draw_sonar)
	root.add_child(sonar)

	# 左下: バー類
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
	bar_food = _bar("食料", Color(0.4, 0.85, 0.4))
	bar_hold = _bar("魚倉", Color(0.4, 0.6, 0.95))
	bar_armor = _bar("装甲", Color(0.95, 0.75, 0.3))
	lbl_food_val = _label("", 15)
	lbl_hold_val = _label("", 15)
	lbl_armor_val = _label("", 15)
	bv.add_child(_bar_row("食料", bar_food, lbl_food_val))
	bv.add_child(_bar_row("魚倉", bar_hold, lbl_hold_val))
	bv.add_child(_bar_row("装甲", bar_armor, lbl_armor_val))

	# 漁獲物アイコン列(バーの上)
	cargo_panel = PanelContainer.new()
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

	# 下中央: 武器スロット
	weapon_box = HBoxContainer.new()
	weapon_box.add_theme_constant_override("separation", 8)
	weapon_box.set_anchor(SIDE_LEFT, 0.5)
	weapon_box.set_anchor(SIDE_RIGHT, 0.5)
	weapon_box.set_anchor(SIDE_TOP, 1)
	weapon_box.set_anchor(SIDE_BOTTOM, 1)
	weapon_box.position = Vector2(-200, -64)
	weapon_box.size = Vector2(400, 48)
	root.add_child(weapon_box)

	# 中央: 照準
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)

	# 中央下: インタラクト案内
	prompt = _label("", 22)
	prompt.set_anchor(SIDE_LEFT, 0.5)
	prompt.set_anchor(SIDE_RIGHT, 0.5)
	prompt.set_anchor(SIDE_TOP, 1)
	prompt.position = Vector2(-200, -110)
	prompt.size = Vector2(400, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color(1, 1, 0.6))
	root.add_child(prompt)

	# 通知トースト
	notice_box = VBoxContainer.new()
	notice_box.set_anchor(SIDE_LEFT, 0.5)
	notice_box.set_anchor(SIDE_RIGHT, 0.5)
	notice_box.position = Vector2(-250, 90)
	notice_box.size = Vector2(500, 200)
	notice_box.alignment = BoxContainer.ALIGNMENT_BEGIN
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

func _bar(name: String, col: Color) -> ProgressBar:
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

func _bar_row(name: String, bar: ProgressBar, val_label: Label = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _label(name, 18)
	l.custom_minimum_size = Vector2(48, 0)
	h.add_child(l)
	h.add_child(bar)
	if val_label:
		val_label.custom_minimum_size = Vector2(96, 0)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(val_label)
	return h

func update_bars() -> void:
	bar_food.value = clampf(GameState.run_food / maxf(GameState.max_food(), 1.0), 0, 1)
	bar_hold.value = clampf(float(GameState.used_hold()) / maxf(float(GameState.max_hold()), 1.0), 0, 1)
	bar_armor.value = clampf(GameState.run_armor / maxf(GameState.max_armor(), 1.0), 0, 1)
	if lbl_food_val:
		lbl_food_val.text = "%d%%" % int(bar_food.value * 100)
	if lbl_hold_val:
		# 魚倉: 使用/容量 と 残キャパシティ
		lbl_hold_val.text = "%d/%d 残%d" % [GameState.used_hold(), GameState.max_hold(), GameState.free_hold()]
	if lbl_armor_val:
		lbl_armor_val.text = "%d/%d" % [int(GameState.run_armor), int(GameState.max_armor())]

# 漁獲物アイコン列を再構築(cargo変更時=stats_changedで呼ぶ)
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
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	else:
		var n := _label(_cargo_name(id), 12)
		n.custom_minimum_size = Vector2(48, 30)
		vb.add_child(n)
	var cnt := _label("x%d" % qty, 13)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cnt)
	return holder

func _cargo_name(id: String) -> String:
	if Database.fish.has(id): return Database.fish[id].name
	if Database.combat_mobs.has(id): return Database.combat_mobs[id].name
	if Database.lords.has(id): return Database.lords[id].name
	return id

func refresh_money_fame() -> void:
	if lbl_money:
		lbl_money.text = "資金: %d" % GameState.money
	if lbl_fame:
		lbl_fame.text = "名声: %d" % GameState.fame

func set_location(text: String) -> void:
	if lbl_loc:
		lbl_loc.text = text

func set_prompt(text: String) -> void:
	if prompt:
		prompt.text = text

func rebuild_weapons() -> void:
	if weapon_box == null:
		return
	for c in weapon_box.get_children():
		c.queue_free()
	var slots := int(GameState.ship().slots)
	for i in slots:
		var wid := GameState.weapons[i] if i < GameState.weapons.size() else ""
		var p := PanelContainer.new()
		_style(p)
		p.custom_minimum_size = Vector2(90, 44)
		var name := "空"
		if wid != "" and Database.weapons.has(wid):
			name = Database.weapons[wid].name
		var l := _label("%d:%s" % [i + 1, name], 16)
		p.add_child(l)
		weapon_box.add_child(p)

func show_big_message(text: String) -> void:
	var l := _label(text, 42)
	l.add_theme_font_size_override("font_size", 42)
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
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

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

# --- ソナー ---
func set_sonar_data(player: Node3D, blips: Array) -> void:
	_player_node = player
	_sonar_blips = blips
	if sonar:
		sonar.queue_redraw()

func _draw_sonar() -> void:
	var r := 100.0
	var center := Vector2(r, r)
	sonar.draw_circle(center, r, Color(0.05, 0.15, 0.2, 0.7))
	sonar.draw_arc(center, r, 0, TAU, 48, Color(0.3, 0.8, 0.9, 0.6), 2.0)
	sonar.draw_line(center - Vector2(r, 0), center + Vector2(r, 0), Color(0.2, 0.5, 0.6, 0.4), 1.0)
	sonar.draw_line(center - Vector2(0, r), center + Vector2(0, r), Color(0.2, 0.5, 0.6, 0.4), 1.0)
	if _player_node == null:
		return
	var range_m := 220.0
	var pp := _player_node.global_position
	var yaw := _player_node.rotation.y
	for b in _sonar_blips:
		var rel: Vector3 = b.pos - pp
		# プレイヤーの向きを上にする回転
		var x := rel.x * cos(yaw) - rel.z * sin(yaw)
		var z := rel.x * sin(yaw) + rel.z * cos(yaw)
		var sx := x / range_m * r
		var sy := z / range_m * r
		if Vector2(sx, sy).length() > r:
			continue
		sonar.draw_circle(center + Vector2(sx, sy), 4.0, b.color)
	# 自機
	sonar.draw_circle(center, 3.0, Color.WHITE)

func _draw_crosshair() -> void:
	var c := crosshair.get_viewport_rect().size * 0.5
	var col := Color(1, 1, 1, 0.7)
	crosshair.draw_line(c - Vector2(12, 0), c + Vector2(12, 0), col, 2.0)
	crosshair.draw_line(c - Vector2(0, 12), c + Vector2(0, 12), col, 2.0)
	crosshair.draw_arc(c, 16, 0, TAU, 24, Color(1, 1, 1, 0.3), 1.5)
