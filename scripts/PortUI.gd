extends CanvasLayer
## PortUI — 帰港中の港メニュー。魚市場/酒場/造船所/出港/ファストトラベル。

signal set_sail_requested
signal fast_travel_requested(island_id: int)

var panel: PanelContainer
var content: VBoxContainer
var header: Label
var _root: Control

func _ready() -> void:
	layer = 20
	visible = false
	_build()
	GameState.notice.connect(func(_t): if visible: _refresh_header())

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# 画面全体の CenterContainer で常に中央寄せ(解像度非依存)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.16, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.3, 0.6, 0.7)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(720, 540)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	header = _h(" ", 28)
	vb.add_child(header)

	# タブボタン行
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	tabs.add_child(_btn("魚市場", show_market))
	tabs.add_child(_btn("酒場", show_tavern))
	tabs.add_child(_btn("造船所", show_shipyard))
	tabs.add_child(_btn("航路", show_travel))

	var sep := HSeparator.new()
	vb.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	# 出港ボタン(常時下部)
	var sail := _btn("⚓ 出港する", func(): emit_signal("set_sail_requested"))
	sail.add_theme_color_override("font_color", Color(1, 1, 0.6))
	vb.add_child(sail)

func open() -> void:
	visible = true
	_refresh_header()
	show_market()

func close() -> void:
	visible = false

func _refresh_header() -> void:
	var def: Dictionary = Database.island(GameState.current_island)
	header.text = "%s    資金:%d  名声:%d  魚倉:%d/%d" % [
		def.name, GameState.money, GameState.fame,
		GameState.used_hold(), GameState.max_hold()]

func _clear() -> void:
	for c in content.get_children():
		c.queue_free()

# ---------------- 魚市場 ----------------
func show_market() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("魚市場 — 漁獲物の販売", 22))
	var isle := GameState.current_island
	if GameState.cargo.is_empty():
		content.add_child(_p("売る漁獲物がありません。"))
	else:
		var total := 0
		for id in GameState.cargo:
			var qty := int(GameState.cargo[id])
			var unit := Database.sale_price(id, isle)
			var nm := _item_name(id)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(_portrait(id, 46))
			if unit <= 0:
				row.add_child(_p("%s x%d — この島では売れません" % [nm, qty]))
			else:
				total += unit * qty
				row.add_child(_p("%s x%d  @%d = %d" % [nm, qty, unit, unit * qty]))
			content.add_child(row)
		content.add_child(_p("合計見込み: %d" % total))
		content.add_child(_btn("すべて売却", func():
			GameState.sell_all()
			show_market()))

# ---------------- 酒場 ----------------
func show_tavern() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("酒場 — 賞金・情報・遺産換金", 22))
	var isle := GameState.current_island
	var lord_total := 0
	for lid in GameState.defeated_lords:
		if Database.lords[lid].island == isle:
			lord_total += int(Database.lords[lid].bounty)
	var head_total := 0
	for pid in GameState.heads:
		head_total += int(Database.pirates[pid].bounty) * int(GameState.heads[pid])
	content.add_child(_p("討伐済みの主の賞金(この島で受領可): %d" % lord_total))
	content.add_child(_p("海賊の首の賞金: %d" % head_total))
	content.add_child(_p("旧文明の遺産: %d" % GameState.relics))
	content.add_child(_btn("賞金・換金を受け取る", func():
		GameState.claim_bounties()
		show_tavern()))
	content.add_child(_p(""))
	content.add_child(_h("この近海の主", 18))
	for lid in Database.island(isle).get("lords", []):
		var ld: Dictionary = Database.lords[lid]
		var st := "討伐済" if (GameState.claimed_lords.has(lid) or GameState.defeated_lords.has(lid)) else "未討伐"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_portrait(lid, 72))
		row.add_child(_p("%s\nHP:%d  賞金:%d  [%s]" % [ld.name, ld.hp, ld.bounty, st]))
		content.add_child(row)

# ---------------- 造船所 ----------------
func show_shipyard() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("造船所 — 船・武器の購入(下取りあり)", 22))
	var tier := GameState.current_island
	content.add_child(_h("船", 18))
	for sid in Database.ships:
		var s: Dictionary = Database.ships[sid]
		if int(s.range) > tier:
			continue  # 先の島でしか売らない
		var owned: bool = sid == GameState.ship_id
		var cost := maxi(int(s.price) - int(GameState.ship().trade), 0)
		var line := "%s  食料%d 魚倉%d 装甲%d 武器枠%d 速%.0f" % [s.name, s.food, s.hold, s.armor, s.slots, s.speed]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lab := _p(line)
		lab.custom_minimum_size = Vector2(460, 0)
		row.add_child(lab)
		if owned:
			row.add_child(_p("[所有中]"))
		else:
			row.add_child(_btn("購入 %d" % cost, func():
				GameState.buy_ship(sid)
				show_shipyard()))
		content.add_child(row)

	content.add_child(_p(""))
	content.add_child(_h("武器スロット(クリックで装備変更)", 18))
	var slots := int(GameState.ship().slots)
	for i in slots:
		var cur: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
		var nm: String = Database.weapons[cur].name if (cur != "" and Database.weapons.has(cur)) else "空"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_p("スロット%d: %s" % [i + 1, nm]))
		for wid in Database.weapons:
			var w: Dictionary = Database.weapons[wid]
			row.add_child(_btn(w.name, func():
				GameState.equip_weapon(i, wid)
				show_shipyard()))
		row.add_child(_btn("外す", func():
			GameState.equip_weapon(i, "")
			show_shipyard()))
		content.add_child(row)

	content.add_child(_p(""))
	content.add_child(_h("衝角", 18))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	rrow.add_child(_p("現在: %s" % Database.rams[GameState.ram_id].name))
	for rid in Database.rams:
		var r: Dictionary = Database.rams[rid]
		rrow.add_child(_btn("%s(%d)" % [r.name, r.price], func():
			if rid == "none" or GameState.money >= int(Database.rams[rid].price):
				if rid != "none":
					GameState.add_money(-int(Database.rams[rid].price))
				GameState.ram_id = rid
				GameState.notice.emit("衝角: %s" % Database.rams[rid].name)
			else:
				GameState.notice.emit("資金が足りません")
			show_shipyard()))
	content.add_child(rrow)

# ---------------- 航路(ファストトラベル) ----------------
func show_travel() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("航路 — 既知の島へファストトラベル", 22))
	content.add_child(_p("食料が足りる既知の島へ移動できます(帰りのモブ襲撃なし)。"))
	for isle in Database.islands:
		if not GameState.unlocked_islands.has(isle.id):
			content.add_child(_p("・%s  [未開放 / 必要名声 %d]" % [isle.name, isle.fame_req]))
			continue
		if isle.id == GameState.current_island:
			content.add_child(_p("・%s  [現在地]" % isle.name))
			continue
		content.add_child(_btn("%s へ移動" % isle.name, func():
			emit_signal("fast_travel_requested", isle.id)))

# ---------------- helpers ----------------
func _item_name(id: String) -> String:
	if Database.fish.has(id): return Database.fish[id].name
	if Database.combat_mobs.has(id): return Database.combat_mobs[id].name
	if Database.lords.has(id): return Database.lords[id].name
	return id

func _item_image_path(id: String) -> String:
	if Database.fish.has(id): return "res://assets/images/fish_%s.png" % id
	if Database.combat_mobs.has(id): return "res://assets/images/mob_%s.png" % id
	if Database.lords.has(id): return "res://assets/images/lord_%s.png" % id
	if Database.pirates.has(id): return "res://assets/images/pirate_%s.png" % id
	return ""

# 生成画像をUI挿絵として表示(なければ空き枠)。立体モデルとは別に図鑑的に見せる。
func _portrait(id: String, h: float) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(h * 1.7, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.16, 0.2, 0.8)
	sb.set_corner_radius_all(6)
	holder.add_theme_stylebox_override("panel", sb)
	var path := _item_image_path(id)
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(h * 1.7, h)
		holder.add_child(tr)
	return holder

func _h(t: String, sz: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	return l

func _p(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b
