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
	_fleet_tab = _btn("編成", show_fleet)   # #196: 潮鳴りの島以降のみ表示
	tabs.add_child(_fleet_tab)
	tabs.add_child(_btn("航路", show_travel))
	tabs.add_child(_btn("討伐記録", show_bestiary))   # #177

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
	var sail := _btn("出港する", func(): emit_signal("set_sail_requested"))
	sail.add_theme_color_override("font_color", Color(1, 1, 0.6))
	vb.add_child(sail)

func open(arrival := false) -> void:
	if _fleet_tab:
		_fleet_tab.visible = GameState.fleet_enabled()   # #196
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
		_toast_box.anchor_top = 0.78
		_toast_box.anchor_bottom = 0.92
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
	# クルー(#39): 雇用・一覧・ジョブチェンジ
	content.add_child(_p(""))
	content.add_child(_h("クルー(船団計%d名) — 出港ごとに賃金・帰港で成長・大破で失う恐れ" % GameState.all_crew().size(), 18))
	for _fi in GameState.fleet.size():
		if GameState.fleet.size() > 1:
			content.add_child(_p("【%s】%d/%d名" % [GameState.fleet_label(_fi), GameState.fleet[_fi].crew.size(), GameState.CREW_MAX]))
		for m in GameState.fleet[_fi].crew:
			var j: Dictionary = GameState.jobs[m.job]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			# #140再: 上限(STAT_MAX)に達したパラメータは黄色で表示(RichTextLabel)
			var info := RichTextLabel.new()
			info.bbcode_enabled = true
			info.fit_content = true
			info.scroll_active = false
			info.custom_minimum_size = Vector2(330, 0)
			info.add_theme_font_size_override("normal_font_size", 18)
			info.text = "%s [%s] %s %s %s %s %s" % [m.name, j.name,
				_stat_bb("体", int(m.hp)), _stat_bb("敏", int(m.agi)), _stat_bb("射", int(m.sht)),
				_stat_bb("知", int(m.int_)), _stat_bb("視", int(m.vis))]
			row.add_child(info)
			for jid in GameState.jobs:
				if GameState.can_jobchange(m, jid):
					row.add_child(_btn("→%s" % GameState.jobs[jid].name, func():
						GameState.jobchange(m, jid)
						show_tavern()))
			row.add_child(_btn("解雇", func():
				GameState.fire_crew(m)
				show_tavern()))
			content.add_child(row)
	# #196: どの艦に乗せるかを先に選ぶ
	if GameState.fleet.size() > 1:
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		trow.add_child(_p("雇用先: %s" % GameState.fleet_label(GameState.target_ship)))
		for i in GameState.fleet.size():
			var ti: int = i
			trow.add_child(_btn(GameState.fleet_label(i), func():
				GameState.target_ship = ti
				show_tavern()))
		content.add_child(trow)
	content.add_child(_p("雇用(※上位ジョブは規定パラメータ以上で1キャラにつき1度だけジョブチェンジも可能):"))
	# #107: 各ジョブの説明付きで雇用ボタンを縦に並べる
	for jid in GameState.jobs:
		var j2: Dictionary = GameState.jobs[jid]
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 10)
		hrow.add_child(_btn("%s(%d)" % [j2.name, GameState.hire_cost(jid)], func():
			GameState.hire_crew(jid)
			show_tavern()))
		var dsc := _p(str(j2.get("desc", "")))
		dsc.custom_minimum_size = Vector2(540, 0)
		hrow.add_child(dsc)
		content.add_child(hrow)
	if GameState.current_island >= 3:   # #190: 月下の島(2)は潮鳴りまでと同じ雇用条件
		content.add_child(_p("※この港は契約金3倍(水夫を除く)だが、他の港より格段に強力なクルーを雇用できる"))
	content.add_child(_p("効果: 体力=燃料減少↓ 敏捷=被ダメ減 射撃=威力↑ 知力=デバフ強化 視力=ソナー範囲↑"))

	content.add_child(_p(""))
	content.add_child(_h("この近海の主", 18))
	for lid in Database.island(isle).get("lords", []):
		var ld: Dictionary = Database.lords[lid]
		var st := "討伐済" if (GameState.claimed_lords.has(lid) or GameState.defeated_lords.has(lid)) else "未討伐"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_portrait(lid, 72))
		var compass: String = Database.compass(float(ld.get("dir", 0)))
		# #112: 主の説明(lore)を併記。長文は折り返して横幅が間延びしないようにする
		var info := _p("%s\nHP:%d  賞金:%d  [%s]\n情報: 港の【%s】の沖にいるらしい\n%s" % [ld.name, ld.hp, ld.bounty, st, compass, str(ld.get("lore", ""))])
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(380, 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		# #61: 未討伐の主へのガイド(ソナー外周に赤い印)
		if st == "未討伐":
			var lid2: String = lid
			var lname: String = ld.name
			var guiding: bool = GameState.guide_target.get("kind", "") == "lord" and str(GameState.guide_target.get("id", "")) == lid2
			row.add_child(_btn("ガイド解除" if guiding else "ガイド設定", func():
				if guiding:
					GameState.guide_target = {}
					GameState.notice.emit("ガイドを解除した")
				else:
					GameState.guide_target = {"kind": "lord", "id": lid2}
					GameState.notice.emit("%s へのガイドを設定(ソナー外周の赤い印)" % lname)
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
			var stat := "HP:%d  攻撃:%d" % [int(d.get("hp", 0)), int(d.get("dmg", 0))]
			if d.has("speed"):
				stat += "  速度:%d" % int(d.get("speed", 0))
			if e.kind == "pirate":
				stat += "  賞金:%d" % int(d.get("bounty", 0))
			var info := _p("%s  討伐数:%d\n%s\n%s" % [str(d.get("name", "?")), cnt, stat, str(e.get("desc", ""))])
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.custom_minimum_size = Vector2(500, 0)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
		else:
			row.add_child(_unknown_portrait(72))
			var info := _p("？？？\n未討伐")
			info.custom_minimum_size = Vector2(500, 0)
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
	var tier := GameState.current_island
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
		row.add_child(_btn("購入 %d" % cost, func():
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
		var cur: String = str(twp[i]) if i < twp.size() else ""
		var nm: String = Database.weapons[cur].name if (cur != "" and Database.weapons.has(cur)) else "空"
		var trade_in := int(float(Database.weapons[cur].price) * 0.8) if (cur != "" and Database.weapons.has(cur)) else 0
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_p("スロット%d: %s" % [i + 1, nm]))
		for wid in Database.weapons:
			if wid == cur:
				continue
			var w: Dictionary = Database.weapons[wid]
			if int(w.get("tier", 0)) > tier:
				continue   # #102: 上位武器は対応する島以降でのみ販売
			var cost := int(w.price) - trade_in   # #34再: 負なら返金(下位武器への付替)
			var wlabel := ("%s(%d)" % [w.name, cost]) if cost >= 0 else ("%s(+%d返金)" % [w.name, -cost])
			row.add_child(_btn(wlabel, func():
				if cost > GameState.money:
					GameState.notice.emit("資金が足りません(必要%d)" % cost)
				else:
					GameState.add_money(-cost)   # costが負なら返金
					GameState.equip_weapon_on(tgt, i, wid)   # #196: 選択中の艦へ装備
				show_shipyard()))
		if cur != "":
			row.add_child(_btn("外す(+%d)" % trade_in, func():
				GameState.add_money(trade_in)
				GameState.equip_weapon_on(tgt, i, "")
				show_shipyard()))
		content.add_child(row)

	# 銛のデバフ設定(#37): 主にのみ適用
	content.add_child(_p(""))
	content.add_child(_h("銛の効果設定(近海の主・戦闘モブに有効 / 海賊には無効)", 18))
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
		rrow.add_child(_btn("%s(%d)" % [r.name, r.price], func():
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
		"・大砲  単発高火力の大砲。",
		"・銛  様々な種類の毒を塗ることができ、生物に有効。",
		"・魚雷  僚艦に射線が遮られていても発射可能。空中の敵には発射できない。",
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

# #140再: パラメータ表記。上限到達で黄色に
# ---------------- 編成(#196) ----------------
const FORMATION_NAMES := {
	"line": "横並び", "column": "縦並び", "vee": "V字型", "inv_vee": "逆V字型", "echelon": "斜線陣",
}

func show_fleet() -> void:
	_refresh_header()
	_clear()
	content.add_child(_h("編成 — 船団(最大%d隻/この島では%d隻まで)" % [GameState.FLEET_MAX, GameState.max_fleet()], 22))
	content.add_child(_p("1隻目が旗艦。旗艦が大破すると船団ごと強制帰還します。2番艦以降は副船長を1名乗せると出港できます。"))
	var repair := GameState.fleet_repair_cost()
	if repair > 0:
		content.add_child(_p("※離脱した船の修理費 %d が次の出港時にかかります" % repair))

	# --- 船団の各艦 ---
	content.add_child(_p(""))
	content.add_child(_h("船団", 18))
	for i in GameState.fleet.size():
		var e: Dictionary = GameState.fleet[i]
		var sd: Dictionary = Database.ships[str(e.ship_id)]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ok := GameState.can_sail(i)
		var lab := _p("%s: %s  装甲%d 速%.0f 武器枠%d  クルー%d/%d %s" % [
			GameState.fleet_label(i), sd.name, sd.armor, sd.speed, sd.slots,
			e.crew.size(), GameState.CREW_MAX,
			"" if ok else "【副船長がいないため出港不可】"])
		lab.custom_minimum_size = Vector2(520, 0)
		row.add_child(lab)
		var idx := i
		if i > 0:
			row.add_child(_btn("旗艦と交代", func():
				GameState.fleet_swap(0, idx)
				show_fleet()))
			row.add_child(_btn("船団から外す", func():
				GameState.fleet_remove(idx)
				show_fleet()))
		content.add_child(row)
		# 乗員(他の艦へ移せる)
		for m in e.crew.duplicate():
			var crow := HBoxContainer.new()
			crow.add_theme_constant_override("separation", 6)
			var info := _p("    %s [%s] 体%d 敏%d 射%d 知%d 視%d" % [
				m.name, GameState.jobs[m.job].name, int(m.hp), int(m.agi), int(m.sht), int(m.int_), int(m.vis)])
			info.custom_minimum_size = Vector2(420, 0)
			crow.add_child(info)
			for j in GameState.fleet.size():
				if j == idx:
					continue
				var to := j
				var mem: Dictionary = m
				crow.add_child(_btn("→%s" % GameState.fleet_label(to), func():
					# #196再3: 乗り換え先が満員なら「誰と交代するか」を聞く
					if GameState.fleet[to].crew.size() >= GameState.CREW_MAX:
						_crew_swap = {"from": idx, "member": mem, "to": to}
					else:
						GameState.move_crew(idx, mem, to)
					show_fleet()))
			content.add_child(crow)
			# 交代相手の選択(この乗員を移そうとしていて、行き先が満員のとき)
			if not _crew_swap.is_empty() and _crew_swap.member == m:
				var tgt_i: int = int(_crew_swap.to)
				var srow2 := HBoxContainer.new()
				srow2.add_theme_constant_override("separation", 6)
				srow2.add_child(_p("      %s は満員です。交代する相手を選んでください:" % GameState.fleet_label(tgt_i)))
				for om in GameState.fleet[tgt_i].crew.duplicate():
					var other: Dictionary = om
					srow2.add_child(_btn("%s(%s)" % [om.name, GameState.jobs[om.job].name], func():
						GameState.swap_crew(int(_crew_swap.from), _crew_swap.member, tgt_i, other)
						_crew_swap = {}
						show_fleet()))
				srow2.add_child(_btn("やめる", func():
					_crew_swap = {}
					show_fleet()))
				content.add_child(srow2)
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
		content.add_child(wrow)

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

	# --- 陣形 ---
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

var _weapon_pick: Dictionary = {}   # #196: 武器交換の選択中スロット
var _crew_swap: Dictionary = {}     # #196再3: 満員の船へ乗り換える際の交代待ち

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
