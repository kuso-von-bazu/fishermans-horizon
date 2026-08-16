extends CanvasLayer
## PortUI — 帰港中の港メニュー。魚市場/酒場/造船所/出港/ファストトラベル。

signal set_sail_requested
signal fast_travel_requested(island_id: int)

var panel: PanelContainer
var content: VBoxContainer
var header: Label
var _root: Control
var _toast_box: VBoxContainer   # #160: トーストを縦に積んで重ならないようにする

var _fleet_tab: Button   # #196: 編成タブ(潮鳴りの島以降だけ表示)
var _scroll: ScrollContainer   # #211: 画面サイズに追従させる
var _img_popup: Control        # #211再2: 挿絵の拡大表示
var _fuel_estimate: Label      # #232: ガイド先までの推定燃料消費
var _tavern_section: String = "bounty"   # #231: 賞金・換金が既定
var _shipyard_weapon_slot: int = -1
var _fleet_card_pick: int = -1
const OverlayMenus := preload("res://scripts/OverlayMenus.gd")

func _ready() -> void:
	layer = 20
	visible = false
	_build()
	GameState.notice.connect(func(t):
		if visible:
			_refresh_header()
			_show_toast(t))   # #123: 資金不足などの通知を港でも表示

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
	panel.custom_minimum_size = Vector2(1100, 620)   # #211再: 実際は _fit_panel で画面に合わせる
	center.add_child(panel)
	# #211: 画面が小さい場合もパネルが画面外へはみ出さないように追従させる
	get_viewport().size_changed.connect(_fit_panel)

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
	_fleet_tab = _btn("編成", show_fleet)   # #196: 潮鳴りの島以降のみ表示
	tabs.add_child(_fleet_tab)
	tabs.add_child(_btn("航路", show_travel))
	tabs.add_child(_btn("討伐記録", show_bestiary))   # #177
	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(tab_spacer)
	# #235再: 「⚙」は環境によって豆腐になるので生成した歯車画像を使う
	var settings_btn := OverlayMenus.icon_button("gear", "音量設定")
	settings_btn.custom_minimum_size = Vector2(52, 38)
	settings_btn.pressed.connect(func(): OverlayMenus.show_settings(_root))
	tabs.add_child(settings_btn)
	# #236再: 港からも早見表を開けるようにする(タイトル・航海中と同じ導線)
	var help_btn := OverlayMenus.icon_button("help", "操作・武器 早見表")
	help_btn.custom_minimum_size = Vector2(52, 38)
	help_btn.pressed.connect(func(): OverlayMenus.show_help(_root))
	tabs.add_child(help_btn)

	var sep := HSeparator.new()
	vb.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1060, 410)
	# #211: 横スクロールを無効にしていたため、造船所など横に長い行があると
	# パネル自体が画面幅を超えて広がり、フルスクリーンで右側が見切れていた。
	# 自動横スクロールにすると、パネル幅は固定のまま行だけがスクロールする。
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vb.add_child(scroll)
	_scroll = scroll
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	# #232: ガイド設定中は出港前に必要燃料を概算表示
	_fuel_estimate = _p("")
	_fuel_estimate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_fuel_estimate)
	# 出港ボタン(常時下部)
	var sail := _btn("出港する", func(): emit_signal("set_sail_requested"))
	sail.add_theme_color_override("font_color", Color(1, 1, 0.6))
	vb.add_child(sail)

# #211再: 港のウインドウは画面の広さに合わせて大きくする。
# 横に長い行(造船所・討伐記録など)も収まるので横スクロールは基本的に不要。
# それでも収まらない場合だけ自動で横スクロールが出る(見切れは起きない)。
func _fit_panel() -> void:
	if panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var sz := vp.get_visible_rect().size
	var w: float = clampf(sz.x - 40.0, 360.0, 1680.0)
	var h: float = clampf(sz.y - 40.0, 300.0, 960.0)
	panel.custom_minimum_size = Vector2(w, h)
	if _scroll:
		_scroll.custom_minimum_size = Vector2(w - 40.0, h - 210.0)

func open(arrival := false) -> void:
	_fit_panel()
	if _fleet_tab:
		_fleet_tab.visible = GameState.fleet_enabled()   # #196
	# #231再: 酒場のサブタブは記憶せず、寄港のたびに「賞金・換金」へ戻す
	# (港に入って最初にやる操作は賞金受領のため)
	_tavern_section = "bounty"
	_shipyard_weapon_slot = -1
	_fleet_card_pick = -1
	_crew_pick = {}   # #231再3
	visible = true
	_refresh_header()
	show_market()
	if arrival:
		_show_arrival_banner()   # #104: 寄港メッセージ

# #123: 通知トースト(資金不足など)を港画面下部に一時表示
func _show_toast(text: String) -> void:
	if _root == null or text.strip_edges() == "":
		return
	# #160: トーストは専用VBoxに積み上げて、連続表示でも重ならないようにする
	if _toast_box == null or not is_instance_valid(_toast_box):
		_toast_box = VBoxContainer.new()
		_toast_box.anchor_left = 0.0
		_toast_box.anchor_right = 1.0
		# #211再3: 出港ボタン(画面下部)と重ならないよう上へずらす
		_toast_box.anchor_top = 0.58
		_toast_box.anchor_bottom = 0.76
		_toast_box.alignment = BoxContainer.ALIGNMENT_END
		_toast_box.add_theme_constant_override("separation", 4)
		_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_toast_box)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

# #104: 寄港したことがわかる一時バナー
func _show_arrival_banner() -> void:
	var lbl := Label.new()
	lbl.text = "%s に寄港した" % Database.island(GameState.current_island).name
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.04
	lbl.anchor_bottom = 0.04
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tw.tween_callback(lbl.queue_free)

func close() -> void:
	visible = false

func _refresh_header() -> void:
	var def: Dictionary = Database.island(GameState.current_island)
	header.text = "%s    資金:%d  名声:%d  魚倉:%d/%d" % [
		def.name, GameState.money, GameState.fame,
		GameState.used_hold(), GameState.max_hold()]
	_update_fuel_estimate()

func _update_fuel_estimate() -> void:
	if _fuel_estimate == null:
		return
	var g: Dictionary = GameState.guide_target
	if g.is_empty():
		_fuel_estimate.text = ""
		return
	var cp: Vector3 = Database.island(GameState.current_island).pos
	var from := Vector2(cp.x, cp.z)
	var dest := from
	var target_weather := ""
	if str(g.get("kind", "")) == "island":
		var iid := int(g.get("id", -1))
		if iid < 0 or iid >= Database.islands.size():
			_fuel_estimate.text = ""
			return
		var p: Vector3 = Database.island(iid).pos
		dest = Vector2(p.x, p.z)
		target_weather = str(Database.island(iid).get("weather", ""))
	else:
		var lid := str(g.get("id", ""))
		if not Database.lords.has(lid):
			_fuel_estimate.text = ""
			return
		var ld: Dictionary = Database.lords[lid]
		var p: Vector3 = Database.island(int(ld.island)).pos
		var a := deg_to_rad(float(ld.get("dir", 0)))
		dest = Vector2(p.x, p.z) + Vector2(sin(a), -cos(a)) * 375.0 * float(ld.get("spawn_dist_mult", 1.0))
		target_weather = str(Database.island(int(ld.island)).get("weather", ""))
	var speed := maxf(float(GameState.ship().speed), 1.0)
	var needed := from.distance_to(dest) / speed * 1.5 * GameState.food_drain_mult()
	if target_weather == "blizzard":
		needed *= 1.2
	var pct := int(ceil(needed / maxf(GameState.max_food(), 1.0) * 100.0))
	_fuel_estimate.text = "目的地までの推定消費: 約%d%%%s" % [pct, "  【燃料不足】" if pct > 100 else ""]
	_fuel_estimate.add_theme_color_override("font_color", Color(1.0, 0.3, 0.28) if pct > 100 else Color(0.9, 0.92, 0.72))

func _clear() -> void:
	_close_image_popup()   # #211再2
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
	content.add_child(_h("酒場", 22))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for spec in [["bounty", "賞金・換金"], ["crew", "クルー"], ["lords", "主の情報"]]:
		var section_id: String = spec[0]
		var b := _btn(str(spec[1]), func():
			_tavern_section = section_id
			show_tavern())
		if _tavern_section == section_id:
			b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
		tabs.add_child(b)
	content.add_child(tabs)
	var isle := GameState.current_island
	if _tavern_section == "bounty":
		var lord_total := 0
		for lid in GameState.defeated_lords:
			if Database.lords[lid].island == isle:
				lord_total += int(Database.lords[lid].bounty)
		var head_total := 0
		for pid in GameState.heads:
			head_total += int(Database.pirates[pid].bounty) * int(GameState.heads[pid])
		content.add_child(_h("賞金・換金", 18))
		content.add_child(_p("討伐済みの主の賞金(この島で受領可): %d" % lord_total))
		content.add_child(_p("海賊の首の賞金: %d" % head_total))
		content.add_child(_p("旧文明の遺産: %d" % GameState.relics))
		content.add_child(_btn("賞金・換金を受け取る", func():
			GameState.claim_bounties()
			show_tavern()))
		return
	if _tavern_section == "crew":
		content.add_child(_h("クルー(船団計%d名)" % GameState.all_crew().size(), 18))
		for fi in GameState.fleet.size():
			if GameState.fleet.size() > 1:
				content.add_child(_p("【%s】%d/%d名" % [GameState.fleet_label(fi), GameState.fleet[fi].crew.size(), GameState.CREW_MAX]))
			for m in GameState.fleet[fi].crew:
				var j: Dictionary = GameState.jobs[m.job]
				var row := HBoxContainer.new()
				var info := RichTextLabel.new()
				info.bbcode_enabled = true
				info.fit_content = true
				info.scroll_active = false
				info.custom_minimum_size = Vector2(390, 0)
				info.add_theme_font_size_override("normal_font_size", 18)
				info.text = "%s [%s] %s %s %s %s %s" % [m.name, j.name, _stat_bb("体", int(m.hp)), _stat_bb("敏", int(m.agi)), _stat_bb("射", int(m.sht)), _stat_bb("知", int(m.int_)), _stat_bb("視", int(m.vis))]
				row.add_child(info)
				for jid in GameState.jobs:
					if GameState.can_jobchange(m, jid):
						var job_id: String = jid
						row.add_child(_btn("→%s" % GameState.jobs[job_id].name, func():
							GameState.jobchange(m, job_id)
							show_tavern()))
				row.add_child(_btn("解雇", func():
					GameState.fire_crew(m)
					show_tavern()))
				content.add_child(row)
		if GameState.fleet.size() > 1:
			var target_row := HBoxContainer.new()
			target_row.add_child(_p("雇用先: %s" % GameState.fleet_label(GameState.target_ship)))
			for i in GameState.fleet.size():
				var target_i := i
				target_row.add_child(_btn(GameState.fleet_label(i), func():
					GameState.target_ship = target_i
					show_tavern()))
			content.add_child(target_row)
		content.add_child(_p("雇用(上位ジョブは規定値以上でジョブチェンジ可能):"))
		for jid in GameState.jobs:
			var job_id: String = jid
			var j2: Dictionary = GameState.jobs[job_id]
			var cost := GameState.hire_cost(job_id)
			var hrow := HBoxContainer.new()
			hrow.add_child(_money_btn("%s(%d)" % [j2.name, cost], cost, func():
				GameState.hire_crew(job_id)
				show_tavern()))
			var dsc := _p(str(j2.get("desc", "")))
			dsc.custom_minimum_size = Vector2(540, 0)
			hrow.add_child(dsc)
			content.add_child(hrow)
		content.add_child(_p("効果: 体力=燃料減少↓ 敏捷=被ダメ減 射撃=威力↑ 知力=デバフ強化 視力=ソナー範囲↑"))
		return
	content.add_child(_h("この近海の主", 18))
	for lid in Database.island(isle).get("lords", []):
		var ld: Dictionary = Database.lords[lid]
		var st := "討伐済" if (GameState.claimed_lords.has(lid) or GameState.defeated_lords.has(lid)) else "未討伐"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_portrait(lid, 72))
		var compass: String = Database.compass(float(ld.get("dir", 0)))
		var info := _rt("%s
HP:%d  賞金:%d  [%s]
情報: 港の【%s】の沖にいるらしい
%s" % [ld.name, Database.scaled_hp(float(ld.hp), isle), ld.bounty, st, compass, str(ld.get("lore", ""))])
		# #231再2: autowrap付きの Label は行間が大きく開いてしまい、
		# 「項目ごとに1行あいている」ように見える。早見表(#236再)と同じく
		# RichTextLabel + fit_content にすると内容ぴったりの行間になる。
		info.custom_minimum_size = Vector2(380, 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(info)
		if st == "未討伐":
			var lid2: String = lid
			var lname: String = ld.name
			var guiding: bool = GameState.guide_target.get("kind", "") == "lord" and str(GameState.guide_target.get("id", "")) == lid2
			row.add_child(_btn("ガイド解除" if guiding else "ガイド設定", func():
				if guiding:
					GameState.guide_target = {}
				else:
					GameState.guide_target = {"kind": "lord", "id": lid2}
					GameState.notice.emit("%s へのガイドを設定" % lname)
				show_tavern()))
		content.add_child(row)

# ---------------- 討伐記録(#177) ----------------
func show_bestiary() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("討伐記録", 22))
	var known := 0
	for e in Database.bestiary:
		if GameState.kill_count(e.kind, e.id) > 0:
			known += 1
	content.add_child(_p("討伐: %d / %d 種" % [known, Database.bestiary.size()]))
	for e in Database.bestiary:
		var cnt: int = GameState.kill_count(e.kind, e.id)
		var d: Dictionary = Database.enemy_def(e.kind, e.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		if cnt > 0:
			row.add_child(_portrait(e.id, 72))
			# #202: 今いる海域のHP倍率を反映した値を表示
			var stat := "HP:%d  攻撃:%d" % [Database.scaled_hp(float(d.get("hp", 0)), GameState.current_island), int(d.get("dmg", 0))]
			if d.has("speed"):
				stat += "  速度:%d" % int(d.get("speed", 0))
			if e.kind == "pirate":
				stat += "  賞金:%d" % int(d.get("bounty", 0))
			# #231再2: autowrap付き Label は行間が開くので RichTextLabel を使う
			var info := _rt("%s  討伐数:%d\n%s\n%s" % [str(d.get("name", "?")), cnt, stat, str(e.get("desc", ""))])
			info.custom_minimum_size = Vector2(500, 0)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # #231再2: 挿絵の高さに引き伸ばされて行間が開くのを防ぐ
			row.add_child(info)
		else:
			row.add_child(_unknown_portrait(72))
			var info := _rt("？？？\n未討伐")
			info.custom_minimum_size = Vector2(500, 0)
			info.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # #231再2
			row.add_child(info)
		content.add_child(row)

# #177: 未討伐の敵の枠(「？」を表示)
func _unknown_portrait(h: float) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(h * 1.7, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.15, 0.8)
	sb.set_corner_radius_all(6)
	holder.add_theme_stylebox_override("panel", sb)
	var q := Label.new()
	q.text = "？"
	q.add_theme_font_size_override("font_size", 40)
	q.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(q)
	return holder

# ---------------- 造船所 ----------------
func show_shipyard() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("造船所 — 船・武器の購入", 22))
	content.add_child(_p("購入した船はストックされます。編成メニューで船団に組み込んでください。"))
	var tier := Database.tier_of(GameState.current_island)   # #239: 販売解禁は tier で判定
	content.add_child(_h("船", 18))
	for sid in Database.ships:
		var s: Dictionary = Database.ships[sid]
		if int(s.range) > tier:
			continue  # 先の島でしか売らない
		var cost := GameState.ship_buy_cost(sid)   # #196: 下取り無し・購入した船はストックへ
		var line := "%s  燃料%d 魚倉%d 装甲%d 武器枠%d 速%.0f" % [s.name, s.food, s.hold, s.armor, s.slots, s.speed]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lab := _p(line)
		lab.custom_minimum_size = Vector2(460, 0)
		row.add_child(lab)
		row.add_child(_money_btn("購入 %d" % cost, cost, func():
			GameState.buy_ship(sid)
			show_shipyard()))
		content.add_child(row)

	content.add_child(_p(""))
	content.add_child(_h("武器スロット — 付替は差額制・現装備は8割下取り", 18))
	# #196: どの艦の武器を買うかを先に選ぶ
	var tgt: int = clampi(GameState.target_ship, 0, GameState.fleet.size() - 1)
	if GameState.fleet.size() > 1:
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		trow.add_child(_p("対象: %s" % GameState.fleet_label(tgt)))
		for fi in GameState.fleet.size():
			var ti: int = fi
			trow.add_child(_btn(GameState.fleet_label(fi), func():
				GameState.target_ship = ti
				show_shipyard()))
		content.add_child(trow)
	var tship: Dictionary = GameState.fleet[tgt]
	var twp: Array = tship.weapons
	var slots := int(Database.ships[str(tship.ship_id)].slots)
	for i in slots:
		var slot_i := i
		var cur: String = str(twp[i]) if i < twp.size() else ""
		var nm: String = Database.weapons[cur].name if (cur != "" and Database.weapons.has(cur)) else "空"
		var slot_btn := _btn("▼ スロット%d: %s" % [i + 1, nm], func():
			_shipyard_weapon_slot = -1 if _shipyard_weapon_slot == slot_i else slot_i
			show_shipyard())
		slot_btn.custom_minimum_size = Vector2(460, 38)
		content.add_child(slot_btn)
		if _shipyard_weapon_slot != i:
			continue
		var trade_in := int(float(Database.weapons[cur].price) * 0.8) if (cur != "" and Database.weapons.has(cur)) else 0
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		for wid in Database.weapons:
			if wid == cur:
				continue
			var weapon_id: String = wid
			var w: Dictionary = Database.weapons[weapon_id]
			if int(w.get("tier", 0)) > tier:
				continue
			var cost := int(w.price) - trade_in
			var switch_cost := cost
			var line := HBoxContainer.new()
			var price_text := "%d" % cost if cost >= 0 else "+%d返金" % -cost
			var desc := _p("%s  価格:%s  — %s" % [w.name, price_text, str(w.get("desc", ""))])
			desc.custom_minimum_size = Vector2(700, 0)
			desc.add_theme_color_override("font_color", Color(1.0, 0.68, 0.68) if cost >= 0 else Color(0.65, 1.0, 0.72))
			line.add_child(desc)
			line.add_child(_money_btn("装備する", maxi(cost, 0), func():
				GameState.add_money(-switch_cost)
				GameState.equip_weapon_on(tgt, slot_i, weapon_id)
				_shipyard_weapon_slot = -1
				show_shipyard()))
			list.add_child(line)
		if cur != "":
			list.add_child(_btn("外す(+%d返金)" % trade_in, func():
				GameState.add_money(trade_in)
				GameState.equip_weapon_on(tgt, slot_i, "")
				_shipyard_weapon_slot = -1
				show_shipyard()))
		content.add_child(list)

	# 銛のデバフ設定(#37): 主にのみ適用
	content.add_child(_p(""))
	content.add_child(_h("銛の効果設定(近海の主・戦闘モブに有効、重ねるほど効果増(逓減あり) / 海賊には無効)", 18))
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	drow.add_child(_p("%s の現在: %s" % [GameState.fleet_label(tgt), Database.harpoon_debuffs[str(tship.get("harpoon", "slip"))].name]))
	for did in Database.harpoon_debuffs:
		var d: Dictionary = Database.harpoon_debuffs[did]
		drow.add_child(_btn(d.name, func():
			tship["harpoon"] = did      # #196再: 対象艦ごとに設定
			GameState.notice.emit("%s の銛の効果: %s(%s)" % [GameState.fleet_label(tgt), d.name, d.desc])
			show_shipyard()))
	content.add_child(drow)

	content.add_child(_p(""))
	content.add_child(_h("衝角(対象: %s)" % GameState.fleet_label(tgt), 18))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	rrow.add_child(_p("%s の現在: %s" % [GameState.fleet_label(tgt), Database.rams[str(tship.get("ram", "none"))].name]))
	for rid in Database.rams:
		var r: Dictionary = Database.rams[rid]
		if int(r.get("tier", 0)) > tier:
			continue   # #102: 上位衝角は対応する島以降でのみ販売
		if rid == str(tship.get("ram", "none")):
			rrow.add_child(_p("[%s 装着中]" % r.name))   # #205: 同じ衝角は買えない
			continue
		rrow.add_child(_money_btn("%s(%d)" % [r.name, r.price], int(r.price), func():
			if rid == "none" or GameState.money >= int(Database.rams[rid].price):
				if rid != "none":
					GameState.add_money(-int(Database.rams[rid].price))
				tship["ram"] = rid      # #196再: 対象艦ごとに設定
				GameState.notice.emit("%s の衝角: %s" % [GameState.fleet_label(tgt), Database.rams[rid].name])
			else:
				GameState.notice.emit("資金が足りません")
			show_shipyard()))
	content.add_child(rrow)

	# #198: 造船所の最下段に武器の説明
	content.add_child(_p(""))
	content.add_child(_h("武器の説明", 18))
	for line in [
		"・ガトリングガン  弾幕を張るのに向いた武装。距離が離れると威力が低下する。",
		"・大砲  単発高火力の大砲。海賊船を炎上させやすい。",
		"・銛  様々な種類の毒を塗ることができ、生物に有効。",
		"・魚雷  敵をクリックしてロックオンし、右クリックで発射。僚艦に射線が遮られていても発射可能。空中の敵には発射できない。",
		"・衝角  体当たりで攻撃する。空中の敵には攻撃できない。",
	]:
		content.add_child(_p(line))

# ---------------- 航路(ファストトラベル) ----------------
func show_travel() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("航路 — 既知の島へファストトラベル", 22))
	content.add_child(_p("到達済みの島へ移動できます。未到達の島へは方角を頼りに自力で航行してください。"))
	var here: Vector3 = Database.island(GameState.current_island).pos
	for isle in Database.islands:
		if isle.id == GameState.current_island:
			content.add_child(_p("・%s  [現在地]" % isle.name))
			continue
		# 現在地から見た島の方角(Issue #22)
		var d: Vector3 = isle.pos - here
		var deg: float = rad_to_deg(atan2(d.x, -d.z))
		var compass: String = Database.compass(deg)
		var dist: int = int(d.length())
		if GameState.visited_islands.has(isle.id):
			content.add_child(_btn("%s へ移動  (方角:%s)" % [isle.name, compass], func():
				emit_signal("fast_travel_requested", isle.id)))
		elif GameState.unlocked_islands.has(isle.id):
			# #60: 未到達の島へのガイド(ソナー外周に赤い印)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(_p("・%s  [未到達]  方角:【%s】 約%dの距離 — 自力航行で到達可" % [isle.name, compass, dist]))
			var iid: int = int(isle.id)
			var guiding: bool = GameState.guide_target.get("kind", "") == "island" and int(GameState.guide_target.get("id", -1)) == iid
			var iname: String = isle.name
			row.add_child(_btn("ガイド解除" if guiding else "ガイド設定", func():
				if guiding:
					GameState.guide_target = {}
					GameState.notice.emit("ガイドを解除した")
				else:
					GameState.guide_target = {"kind": "island", "id": iid}
					GameState.notice.emit("%s へのガイドを設定(ソナー外周の赤い印)" % iname)
				show_travel()))
			content.add_child(row)
		else:
			content.add_child(_p("・%s  [未開放 / 必要名声 %d]  方角:【%s】" % [isle.name, isle.fame_req, compass]))
	# #219: 名声の稼ぎ方を最後に案内する
	content.add_child(_p(""))
	content.add_child(_p("名声は近海の主を討伐したり、海賊を撃退することで稼ぐことができます。"))

# #140再: パラメータ表記。上限到達で黄色に
# ---------------- 編成(#196) ----------------
const FORMATION_NAMES := {
	# #216: 陣形の呼び名
	"line": "単横陣", "column": "単縦陣", "vee": "鋒矢陣", "inv_vee": "鶴翼陣", "echelon": "斜線陣",
	"ring": "輪形陣",   # #196再8
}

func show_fleet() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("編成 — 船団(最大%d隻/この島では%d隻まで)" % [GameState.FLEET_MAX, GameState.max_fleet()], 22))
	content.add_child(_p("1隻目が旗艦。旗艦が大破すると船団ごと強制帰還します。2番艦以降は副船長を1名乗せると出港できます。"))
	content.add_child(_p("クルーをクリックして選び、移動先の「空き」か、交代したい相手をクリックしてください(同じ船の中なら並び替えになります)。"))
	var repair := GameState.fleet_repair_cost()
	if repair > 0:
		content.add_child(_p("※離脱した船の修理費 %d が次の出港時にかかります" % repair))

	# --- 船団の各艦 ---
	content.add_child(_p(""))
	content.add_child(_h("船団(船速は船団の最も遅い船に依存する、クリックしロックオンした敵を僚艦は自動的に攻撃する)", 18))
	for i in GameState.fleet.size():
		var e: Dictionary = GameState.fleet[i]
		var sd: Dictionary = Database.ships[str(e.ship_id)]
		var idx := i
		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.10, 0.16, 0.21, 0.94)
		card_style.set_corner_radius_all(9)
		card_style.set_content_margin_all(10)
		card_style.border_width_left = 3
		card_style.border_width_right = 3
		card_style.border_width_top = 3
		card_style.border_width_bottom = 3
		card_style.border_color = Color(1.0, 0.86, 0.3) if _fleet_card_pick == i else Color(0.26, 0.48, 0.58)
		card.add_theme_stylebox_override("panel", card_style)
		card.tooltip_text = "クリックで入れ替える艦を選択"
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if _fleet_card_pick < 0:
					_fleet_card_pick = idx
				elif _fleet_card_pick == idx:
					_fleet_card_pick = -1
				else:
					GameState.fleet_swap(_fleet_card_pick, idx)
					_fleet_card_pick = -1
				show_fleet())
		content.add_child(card)
		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 5)
		card.add_child(card_box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ok := GameState.can_sail(i)
		var lab := _p("%s: %s  装甲%d 速%.0f 武器枠%d  クルー%d/%d %s" % [
			GameState.fleet_label(i), sd.name, sd.armor, sd.speed, sd.slots,
			e.crew.size(), GameState.CREW_MAX,
			"" if ok else "【副船長がいないため出港不可】"])
		lab.custom_minimum_size = Vector2(680, 0)
		row.add_child(lab)
		row.add_child(_btn("【1枚目に選択中】" if _fleet_card_pick == i else "この艦カードを選択", func():
			if _fleet_card_pick < 0:
				_fleet_card_pick = idx
			elif _fleet_card_pick == idx:
				_fleet_card_pick = -1
			else:
				GameState.fleet_swap(_fleet_card_pick, idx)
				_fleet_card_pick = -1
			show_fleet()))
		if i > 0:
			row.add_child(_btn("船団から外す", func():
				GameState.fleet_remove(idx)
				_fleet_card_pick = -1
				show_fleet()))
		card_box.add_child(row)
		# 乗員(#231再3: クリック方式)
		# 1回目のクリックでそのクルーを選択、2回目のクリックで
		#   ・別のクルー → 交代(同じ船なら並び替え)
		#   ・「空き」   → その船へ移動
		# 満員の船へ移すときも、交代相手をそのままクリックすればよい。
		for m in e.crew.duplicate():
			var mem: Dictionary = m
			var picked: bool = (not _crew_pick.is_empty()) and _crew_pick.member == m
			var label := "%s [%s] %s %s %s %s %s" % [m.name, GameState.jobs[m.job].name,
				_stat_bb("体", int(m.hp)), _stat_bb("敏", int(m.agi)), _stat_bb("射", int(m.sht)),
				_stat_bb("知", int(m.int_)), _stat_bb("視", int(m.vis))]
			var cb := _crew_button(label, picked, func():
				_on_crew_clicked(idx, mem))
			card_box.add_child(cb)
		# 空きスロット(移動先として押せる)。これが無いと「空いている船へ移す」操作ができない
		for _s in range(e.crew.size(), GameState.CREW_MAX):
			var eb := _crew_button("(空き)", false, func():
				_on_crew_slot_clicked(idx))
			eb.add_theme_color_override("font_color", Color(0.6, 0.68, 0.75))
			card_box.add_child(eb)
		# 武器スロット(他の艦と交換)
		var wrow := HBoxContainer.new()
		wrow.add_theme_constant_override("separation", 6)
		wrow.add_child(_p("    武器:"))
		for sidx in e.weapons.size():
			var wid: String = str(e.weapons[sidx])
			var wn: String = Database.weapons[wid].name if Database.weapons.has(wid) else "空"
			var sl: int = sidx
			wrow.add_child(_btn("%d:%s" % [sidx + 1, wn], func():
				if _weapon_pick.is_empty():
					_weapon_pick = {"ship": idx, "slot": sl}       # 1回目=交換元を選択
				else:
					GameState.swap_weapon(int(_weapon_pick.ship), int(_weapon_pick.slot), idx, sl)
					_weapon_pick = {}                              # 2回目=交換を実行
					GameState.notice.emit("武器を入れ替えた")
				show_fleet()))
		if not _weapon_pick.is_empty() and int(_weapon_pick.ship) == idx:
			wrow.add_child(_p("← 交換元を選択中。交換先のスロットを押してください"))
			wrow.add_child(_btn("選択解除", func():
				_weapon_pick = {}
				show_fleet()))
		card_box.add_child(wrow)

	# --- ストック ---
	content.add_child(_p(""))
	content.add_child(_h("ストック(購入済み・未編入)", 18))
	if GameState.ship_stock.is_empty():
		content.add_child(_p("ストックはありません。造船所で購入した船がここに入ります。"))
	for i in GameState.ship_stock.size():
		var sid: String = GameState.ship_stock[i]
		var sd2: Dictionary = Database.ships[sid]
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		var slab := _p("%s  装甲%d 速%.0f 武器枠%d" % [sd2.name, sd2.armor, sd2.speed, sd2.slots])
		slab.custom_minimum_size = Vector2(420, 0)
		srow.add_child(slab)
		var si := i
		srow.add_child(_btn("船団に加える", func():
			GameState.fleet_add(si)
			show_fleet()))
		# #196再: すでに船団に組み込んでいる船と交換する
		for fi in GameState.fleet.size():
			var f_idx: int = fi
			srow.add_child(_btn("%sと交換" % GameState.fleet_label(fi), func():
				GameState.fleet_exchange(f_idx, si)
				show_fleet()))
		srow.add_child(_btn("売却(+%d)" % int(float(sd2.price) * 0.8), func():
			GameState.sell_stock(si)
			show_fleet()))
		content.add_child(srow)

	# --- 陣形 --- (#224: 潮鳴りの島へ実際に到達するまでは存在を表示しない)
	if GameState.visited_islands.has(1):
		content.add_child(_p(""))
		content.add_child(_h("陣形 — 航海中に 1〜4 キー(または画面のボタン)で切替", 18))
		content.add_child(_p("陣形1が出港時のデフォルトです。"))
		for slot in 4:
			var frow := HBoxContainer.new()
			frow.add_theme_constant_override("separation", 6)
			frow.add_child(_p("陣形%d: %s" % [slot + 1, FORMATION_NAMES.get(str(GameState.formations[slot]), "?")]))
			for fid in FORMATION_NAMES:
				var sl2 := slot
				var f := str(fid)
				frow.add_child(_btn(str(FORMATION_NAMES[fid]), func():
					GameState.formations[sl2] = f
					GameState.notice.emit("陣形%d を %s に設定" % [sl2 + 1, FORMATION_NAMES[f]])
					show_fleet()))
			content.add_child(frow)
		# #224再2: 陣形ごとの「常時効果 / スキル名 / 効果 / CD」を一覧で示す
		content.add_child(_p(""))
		content.add_child(_h("陣形の効果", 18))
		for fid2 in FORMATION_NAMES:
			var f2 := str(fid2)
			var sk: Dictionary = GameState.FORMATION_SKILLS.get(f2, {})
			content.add_child(_rt("【%s】常時: %s\n  スキル「%s」(CD %d秒): %s" % [
				str(FORMATION_NAMES[f2]),
				str(GameState.FORMATION_PASSIVE_TEXT.get(f2, "-")),
				str(sk.get("name", "-")), int(sk.get("cd", 0)), str(sk.get("desc", "-"))]))
		content.add_child(_p("※常時効果は船団が2隻以上のときに働きます。スキルは航海中に5キー(または画面のボタン)。"))

var _weapon_pick: Dictionary = {}   # #196: 武器交換の選択中スロット
var _crew_pick: Dictionary = {}     # #231再3: 選択中のクルー {"ship": int, "member": Dictionary}

# #231再3: クルー1人ぶんのボタン。選択中は枠を光らせる
func _crew_button(bb_text: String, picked: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(560, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if picked:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.20, 0.30, 0.20, 0.95)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2)
		sb.border_color = Color(1.0, 0.9, 0.4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
	# 能力値の色分け(黄色=上限)を出すため、文字はRichTextLabelを重ねて描く
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.text = ("▶ " if picked else "    ") + bb_text
	rt.set_anchors_preset(Control.PRESET_FULL_RECT)
	rt.offset_left = 8
	rt.offset_top = 4
	b.add_child(rt)
	return b

# クルーをクリックしたとき
func _on_crew_clicked(ship_idx: int, member: Dictionary) -> void:
	if _crew_pick.is_empty():
		_crew_pick = {"ship": ship_idx, "member": member}
		GameState.notice.emit("%s を選択(移動先か、交代する相手をクリック)" % str(member.name))
		show_fleet()
		return
	var from_i: int = int(_crew_pick.ship)
	var a: Dictionary = _crew_pick.member
	if a == member:
		_crew_pick = {}          # 同じ人をもう一度押したら選択解除
		show_fleet()
		return
	if from_i == ship_idx:
		GameState.reorder_crew(ship_idx, a, member)   # 同じ船の中なら並び替え
	else:
		GameState.swap_crew(from_i, a, ship_idx, member)
	_crew_pick = {}
	show_fleet()

# 「空き」をクリックしたとき=その船へ移動
func _on_crew_slot_clicked(ship_idx: int) -> void:
	if _crew_pick.is_empty():
		return
	var from_i: int = int(_crew_pick.ship)
	if from_i != ship_idx:
		GameState.move_crew(from_i, _crew_pick.member, ship_idx)
	_crew_pick = {}
	show_fleet()

var _crew_swap: Dictionary = {}     # #196再3: 満員の船へ乗り換える際の交代待ち(現在は未使用)

func _stat_bb(label: String, v: int) -> String:
	if v >= GameState.STAT_MAX:
		return "[color=yellow]%s%d[/color]" % [label, v]
	return "%s%d" % [label, v]

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
		# #211再: expand_mode を指定しないと TextureRect の最小サイズが元画像サイズになり、
		# ウインドウを広げた際に挿絵が巨大化してしまう。指定サイズを最小として扱わせる。
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(h * 1.7, h)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
		# #211再2: 挿絵をクリックすると拡大表示する
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.tooltip_text = "クリックで拡大"
		var tex_path := path
		holder.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_image_popup(tex_path))
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return holder

# #211再2: 挿絵の拡大表示(どこかをクリック/Escで閉じる)
func _show_image_popup(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	if _img_popup:
		_img_popup.queue_free()
	_img_popup = Control.new()
	_img_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_img_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_img_popup.z_index = 100
	_root.add_child(_img_popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img_popup.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img_popup.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(vb)
	var big := TextureRect.new()
	big.texture = load(path)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size
	big.custom_minimum_size = Vector2(minf(vp.x * 0.8, 900.0), minf(vp.y * 0.75, 620.0))
	vb.add_child(big)
	var hint := _p("クリックで閉じる")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)
	_img_popup.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_image_popup())

func _close_image_popup() -> void:
	if _img_popup:
		_img_popup.queue_free()
		_img_popup = null

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

func _money_btn(t: String, cost: int, cb: Callable) -> Button:
	var b := _btn(t, cb)
	b.add_theme_color_override("font_color", Color(1.0, 0.68, 0.68))
	b.disabled = cost > GameState.money
	if b.disabled:
		b.modulate = Color(0.55, 0.55, 0.58, 0.85)
		b.tooltip_text = "資金が足りません(必要%d)" % cost
	return b

# #231再2: 複数行の説明用。autowrap付き Label は行間が大きく開くので、
# 内容ぴったりの高さになる RichTextLabel を使う(#236再の早見表と同じ対処)。
func _rt(t: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = false
	r.fit_content = true
	r.scroll_active = false
	r.text = t
	r.add_theme_font_size_override("normal_font_size", 17)
	r.add_theme_color_override("default_color", Color.WHITE)
	return r

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 17)
	# #231: 収入(売却・下取り・返金)は淡緑、支出(価格つき)は淡赤に色分けする。
	if t.contains("売却") or t.contains("受け取る") or t.contains("返金") or t.contains("(+"):
		b.add_theme_color_override("font_color", Color(0.65, 1.0, 0.72))
	elif _is_cost_label(t):
		b.add_theme_color_override("font_color", Color(1.0, 0.72, 0.68))
	b.pressed.connect(cb)
	return b

# #231: 「購入 9000」「大砲(1200)」のように金額を伴うボタンか(=支出)を判定する。
# 「鋼鉄衝角(+1600)」のような返金表記は呼び出し側で先に緑へ振り分けている。
func _is_cost_label(t: String) -> bool:
	if t.begins_with("購入"):
		return true
	var open := t.rfind("(")
	var close := t.rfind(")")
	if open == -1 or close <= open + 1:
		return false
	return t.substr(open + 1, close - open - 1).is_valid_int()
