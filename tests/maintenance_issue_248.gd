extends Node
## #248 外れの小島 / #249 リロード速度 / #241再2 ヒント / #239再5 ウンディーネ引き撃ち
## #209再10 ボスラッシュ(分裂・海賊王の取り巻き) / #197再3 海賊王の随伴艦

const Isle = preload("res://scripts2d/Island2D.gd")
const World2 = preload("res://scripts2d/World2D.gd")
const Proj = preload("res://scripts2d/Projectile2D.gd")

const OUTER := 8   # 外れの小島の island index

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

# その島の造船所に並ぶ船/武器のidを実際のUIから集める(#247と同じ手順)
func _listed(port: CanvasLayer, isle: int) -> Dictionary:
	GameState.current_island = isle
	GameState.money = 99999999
	port._shipyard_weapon_slot = 0
	port.show_shipyard()
	await get_tree().process_frame
	var txt := ""
	for n in port.content.find_children("*", "Label", true, false):
		txt += n.text + "\n"
	for n in port.content.find_children("*", "Button", true, false):
		txt += n.text + "\n"
	var ships: Array = []
	for sid in Database.ships:
		if txt.contains(str(Database.ships[sid].name)):
			ships.append(sid)
	# 「魚雷  価格:」は「クラスター魚雷  価格:」にも部分一致するので、行頭一致で判定する
	var weapons: Array = []
	for wid in Database.weapons:
		var head := "%s  価格:" % str(Database.weapons[wid].name)
		for line in txt.split("
"):
			if line.strip_edges().begins_with(head):
				weapons.append(wid)
				break
	return {"ships": ships, "weapons": weapons}

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()
	GameState.unlocked_islands.assign(range(Database.islands.size()))
	for wi in GameState.fleet[0].weapons.size():
		GameState.fleet[0].weapons[wi] = ""

	# ---------------- #248: 島そのもの ----------------
	var isle: Dictionary = Database.island(OUTER)
	check(str(isle.name) == "外れの小島", "島8が外れの小島でない(%s)" % str(isle.name))
	check(int(isle.fame_req) == 400, "到達に必要な名声が400でない(%d)" % int(isle.fame_req))
	check(Database.tier_of(OUTER) == 4, "外れの小島のtierが果ての島と同格でない")
	check((isle.get("lords", []) as Array).is_empty(), "外れの小島に主が設定されている")
	# 果ての島の北 = z が小さい側
	var fin: Vector3 = Database.island(4).pos
	check(isle.pos.z < fin.z, "外れの小島が果ての島の北にない")
	check(str(isle.get("weather", "")) == "flurry", "外れの小島の天候が flurry でない")
	# 見た目: 雪原(緑が無い)かつ小さい
	var pal: Dictionary = Isle.PALETTES[OUTER]
	check(float(pal.get("small", 1.0)) < 1.0, "外れの小島が小さく描かれない")
	var g: Color = pal.grass
	check(g.r > 0.7 and g.g > 0.7 and g.b > 0.7, "外れの小島の地面が雪原(白)でない")

	# 天候効果は果ての島と同じ(=燃料消費+20%)だが、雪の見た目は弱い
	var world := Node2D.new()
	world.set_script(World2)
	var wb: Dictionary = world._weather_params("blizzard")
	var wf: Dictionary = world._weather_params("flurry")
	check(float(wf.snow) > 0.0 and float(wf.snow) < float(wb.snow), "flurry の雪が吹雪より弱くない")
	check(is_equal_approx(float(wf.rough), float(wb.rough)), "flurry の荒波が吹雪と違う")

	# ---------------- #248: 近海のモブ ----------------
	var pool := {}
	for i in 400:
		pool[Database.pick_mob(OUTER)] = true
	check(not pool.has("tiamat"), "外れの小島にティアマットが出る")
	check(not pool.has("zahhak"), "外れの小島にザッハークが出る")
	for want_mob in ["merman", "charybdis", "dagon", "amphiptere"]:
		check(pool.has(want_mob), "外れの小島に %s が出ない" % want_mob)

	# ---------------- #248: 造船所 ----------------
	var Port = preload("res://scripts/PortUI.gd")
	var port := CanvasLayer.new()
	port.set_script(Port)
	add_child(port)
	await get_tree().process_frame
	port.open()
	var got: Dictionary = await _listed(port, OUTER)
	var want_ships := ["corvette", "hunter_h", "hauler"]
	for sid in Database.ships:
		var sold: bool = (got.ships as Array).has(sid)
		if want_ships.has(sid):
			check(sold, "外れの小島で %s が買えない" % sid)
		else:
			check(not sold, "外れの小島で %s が売られている" % sid)
	var want_weapons := ["spray", "lance", "cluster"]
	for wid in Database.weapons:
		var sold2: bool = (got.weapons as Array).has(wid)
		if want_weapons.has(wid):
			check(sold2, "外れの小島で %s が買えない" % wid)
		else:
			check(not sold2, "外れの小島で %s が売られている" % wid)
	# 専用武器は他の島では買えない
	for other in [0, 1, 2, 3, 4, 5, 6, 7]:
		for wid2 in want_weapons:
			check(not Database.shop_has_weapon(other, wid2), "島%d で %s が売られている" % [other, wid2])

	# ---------------- #248: 酒場 ----------------
	# 主がいないので「主の情報」タブごと出ない
	GameState.current_island = OUTER
	port._tavern_section = "lords"
	port.show_tavern()
	await get_tree().process_frame
	var tavern_txt := ""
	for n in port.content.find_children("*", "Button", true, false):
		tavern_txt += n.text + "\n"
	check(not tavern_txt.contains("主の情報"), "外れの小島の酒場に「主の情報」が出ている")
	check(tavern_txt.contains("クルー"), "外れの小島の酒場にクルータブが無い")
	# 主がいる島では従来どおり出る
	GameState.current_island = 4
	port.show_tavern()
	await get_tree().process_frame
	var tavern_txt2 := ""
	for n in port.content.find_children("*", "Button", true, false):
		tavern_txt2 += n.text + "\n"
	check(tavern_txt2.contains("主の情報"), "果ての島の酒場から「主の情報」が消えた")
	# クルーの雇用条件は嵐越え・海嘯・果てと同じ(tier>=3の割増)
	GameState.current_island = OUTER
	var c_outer := GameState.hire_cost("marine")
	GameState.current_island = 4
	check(c_outer == GameState.hire_cost("marine"), "外れの小島のクルー雇用費が果ての島と違う")

	# ---------------- #249: リロード速度 ----------------
	var base: float = float(Database.weapons["gatling"].reload)
	var want_reload := {
		"gatling": 1.0, "cannon": 1.1, "harpoon": 1.2, "torpedo": 1.3,
		"gatling2": 1.2, "cannon2": 1.2, "harpoon2": 1.4, "torpedo2": 1.6,
		"spray": 1.2, "lance": 1.2, "cluster": 1.6,
	}
	for wid3 in want_reload:
		var got_r: float = float(Database.weapons[wid3].reload)
		check(absf(got_r - base * float(want_reload[wid3])) < 0.0001,
			"%s のリロードが基準の%.1f倍でない(%.2f)" % [wid3, want_reload[wid3], got_r])

	# ---------------- #248: 新武器の性能 ----------------
	var spray: Dictionary = Database.weapons["spray"]
	var g2: Dictionary = Database.weapons["gatling2"]
	check(is_equal_approx(float(spray.cooldown), float(g2.cooldown)), "乱射砲の連射速度が重ガトリング砲と違う")
	check(float(spray.dmg) > float(g2.dmg), "乱射砲の単発威力が重ガトリング砲を超えていない")
	check(int(spray.mag) == int(g2.mag), "乱射砲の弾数が重ガトリング砲と違う")
	check(float(spray.get("spray", 0.0)) > 0.0, "乱射砲が散らばらない")
	var lance: Dictionary = Database.weapons["lance"]
	check(is_equal_approx(float(lance.dmg), float(Database.weapons["harpoon2"].dmg)), "槍砲の威力が強化銛砲と違う")
	check(not bool(lance.get("debuff", false)), "槍砲にデバフが付いている")
	check(bool(lance.get("pierce", false)), "槍砲が貫通しない")
	check(float(lance.get("pirate_burn", 0.0)) == 0.0, "槍砲に炎上効果が付いている")
	check(int(lance.mag) == int(Database.weapons["cannon2"].mag), "槍砲の弾数が大口径カノン砲と違う")
	var cl: Dictionary = Database.weapons["cluster"]
	check(int(cl.get("cluster", 0)) == 3, "クラスター魚雷が3発に分裂しない")
	check(float(cl.dmg) * 3.0 > float(Database.weapons["torpedo2"].dmg), "全弾命中でも追尾魚雷改を超えない")
	check(float(cl.speed_mult) < float(Database.weapons["torpedo"].speed_mult), "クラスター魚雷が魚雷より遅くない")
	check(int(cl.mag) == int(Database.weapons["torpedo2"].mag), "クラスター魚雷の弾数が追尾魚雷改と違う")

	# 実際に分裂するか(親が消え、3発の子が残る)
	var host := Node2D.new()
	add_child(host)
	var p := Area2D.new()
	p.set_script(Proj)
	host.add_child(p)
	p.from_player = true
	p.setup(Vector2.RIGHT, Database.weapons["cluster"].duplicate())
	for f in 40:
		await get_tree().physics_frame
	var kids := 0
	for c in host.get_children():
		if is_instance_valid(c) and c != p and not c.is_queued_for_deletion():
			kids += 1
	check(kids == 3, "クラスター魚雷が3発に分かれない(%d)" % kids)
	var still_cluster := 0
	for c2 in host.get_children():
		if is_instance_valid(c2) and c2 != p and int(c2.get("cluster")) > 0:
			still_cluster += 1
	check(still_cluster == 0, "分裂後の子がさらに分裂しようとしている")

	# ---------------- #241再2: ヒント ----------------
	var t8: Dictionary = Database.departure_hint_table(OUTER)
	var r8: Array = t8.get("random", [])
	check(r8.has("この島の近海に主はいないようだ。"), "外れの小島のヒント(主がいない)が無い")
	check(r8.has("この島では珍しい武器が売っている。"), "外れの小島のヒント(珍しい武器)が無い")
	var r4: Array = Database.departure_hint_table(4).get("random", [])
	check(r4.has("外れの小島では珍しい武器が売っているらしい。"), "果ての島のヒントに外れの小島の案内が無い")
	# 果ての島の3回目の出港ではランダム枠が使われる(=上のヒントが出うる)
	var seen3 := {}
	for i3 in 300:
		seen3[str(Database.pick_departure_hint(4, 3, 999, true).get("text", ""))] = true
	for got3 in seen3:
		check(r4.has(str(got3)), "果ての島の3回目にランダム枠以外が出た(%s)" % str(got3))
	check(seen3.has("外れの小島では珍しい武器が売っているらしい。"), "果ての島の3回目に外れの小島の案内が出ない")

	# ---------------- #239再5: ウンディーネの引き撃ち ----------------
	var un: Dictionary = Database.lords["undine"]
	check(bool(un.get("kite", false)) and bool(un.get("kite_always", false)),
		"ウンディーネが取り巻きの生死に関わらず引き撃ちしない")

	# ---------------- #209再10: ボスラッシュ ----------------
	for spec in World2.BOSS_RUSH_ORDER:
		if str(spec.id) == "king":
			check((spec.get("escorts", []) as Array) == ["dread", "dread", "corsair"],
				"ボスラッシュの海賊王の取り巻きが 大×2・中×1 でない")
	# 分裂する主は、分裂体が残っている間は撃破扱いにしない
	check(Database.lords["night_emperor"].has("split"), "夜の帝王が分裂しない")
	world._br_split_root = "night_emperor"
	world.enemies = []
	check(not world._br_split_alive(), "分裂体がいないのに生存判定")
	var fake := Node2D.new()
	fake.set_script(preload("res://tests/split_child_stub.gd"))
	fake.split_root = "night_emperor"
	world.enemies = [fake]
	check(world._br_split_alive(), "分裂体が残っているのに撃破扱いになる")
	fake.free()

	# ---------------- #197再3: 海賊王の随伴艦 ----------------
	for isle_i in [0, 1, 2, 3, 4, 5, 6, 7, 8]:
		var top: String = world._sea_pirate_top(isle_i)
		var rank_top: int = World2.PIRATE_RANKS.find(top)
		for trial in 40:
			var grp: Array = world._king_group(isle_i)
			check(grp.size() >= 1 and grp.size() <= 3, "島%d で随伴艦が1〜3隻でない(%d)" % [isle_i, grp.size()])
			check(grp.has(top), "島%d の随伴艦にその海域の海賊が含まれない" % isle_i)
			for pid in grp:
				check(World2.PIRATE_RANKS.find(str(pid)) <= rank_top,
					"島%d の随伴艦に格上の海賊(%s)が混ざっている" % [isle_i, str(pid)])
	# 海域の格は island index ではなく tier で決まる(同格の島どうしで一致する)
	check(world._sea_pirate_top(5) == world._sea_pirate_top(2), "星霜の海賊の格が月下と違う")
	check(world._sea_pirate_top(6) == world._sea_pirate_top(2), "常闇の海賊の格が月下と違う")
	check(world._sea_pirate_top(7) == world._sea_pirate_top(3), "海嘯の海賊の格が嵐越えと違う")
	check(world._sea_pirate_top(8) == world._sea_pirate_top(4), "外れの小島の海賊の格が果てと違う")
	world.free()

	# ---------------- #190再: レギオンは縮むと当たり判定も縮む ----------------
	var Enemy = preload("res://scripts2d/Enemy2D.gd")
	var leg := CharacterBody2D.new()
	leg.set_script(Enemy)
	leg.setup("lord", "legion")
	add_child(leg)
	await get_tree().process_frame
	var r_full: float = leg._hit_shape.radius
	check(r_full > 0.0, "レギオンの当たり判定が無い")
	leg.hp = leg.max_hp * 0.02      # ほぼ壊滅=最小まで縮んだ状態
	for f2 in 3:
		await get_tree().process_frame
	var r_small: float = leg._hit_shape.radius
	check(r_small < r_full * 0.75, "レギオンが縮んでも当たり判定が小さくならない(%.1f→%.1f)" % [r_full, r_small])
	# 近接の間合いも一緒に縮む(_radius を見ているため)
	check(leg._radius < r_full, "縮んだあとも近接の間合いが元のまま")
	leg.free()

	# ---------------- #73再: 海賊王は遠くから撃つ ----------------
	var king := CharacterBody2D.new()
	king.set_script(Enemy)
	king.setup("pirate", "king")
	add_child(king)
	await get_tree().process_frame
	var dread := CharacterBody2D.new()
	dread.set_script(Enemy)
	dread.setup("pirate", "dread")
	add_child(dread)
	await get_tree().process_frame
	check(king.attack_range > dread.attack_range * 1.3,
		"海賊王の射程が他の海賊とほとんど変わらない(%.0f / %.0f)" % [king.attack_range, dread.attack_range])
	check(bool(Database.pirates["king"].get("shoot_moving", false)), "海賊王が移動しながら撃たない")
	king.free()
	dread.free()

	port.free()
	if failures.is_empty():
		print("MAINTENANCE_TEST_OK outer_isle/shop/tavern/reload/weapons/hints/undine/bossrush/king_escorts/legion_hitbox/king_range")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
