extends Node
## #248 北の孤島 / #249 リロード速度 / #241再2 ヒント / #239再5 ウンディーネ引き撃ち
## #209再10 ボスラッシュ(分裂・海賊王の取り巻き) / #197再3 海賊王の随伴艦

const Isle = preload("res://scripts2d/Island2D.gd")
const World2 = preload("res://scripts2d/World2D.gd")
const Proj = preload("res://scripts2d/Projectile2D.gd")

const OUTER := 8   # 北の孤島の island index

var failures: Array[String] = []

# 画像の四辺のうち、最も不透明画素で埋まっている辺の割合(1.0=その辺で完全に切れている)
func _edge_fill(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var top := 0
	var bottom := 0
	for x in w:
		if img.get_pixel(x, 0).a > 0.06:
			top += 1
		if img.get_pixel(x, h - 1).a > 0.06:
			bottom += 1
	var left := 0
	var right := 0
	for y in h:
		if img.get_pixel(0, y).a > 0.06:
			left += 1
		if img.get_pixel(w - 1, y).a > 0.06:
			right += 1
	return maxf(maxf(float(top) / float(w), float(bottom) / float(w)),
		maxf(float(left) / float(h), float(right) / float(h)))

# 不透明画素のかたまりが何個あるか(体から離れた断片の検出)。8近傍で数える
func _stray_blob_max(img: Image) -> int:
	# 不透明画素の連結成分を数え、最大(=本体)を除いた中で最大の面積を返す。
	# 生成画像に焼き付いた額縁の直線や、体から離れた断片はここに現れる。
	# しきい値0.4: ドット絵化でアルファは0/255に2値化されるので、
	#   薄いアルファでつながって見える誤検出を避けられる。
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var sizes: Array[int] = []
	for y in h:
		for x in w:
			var key := y * w + x
			if img.get_pixel(x, y).a < 0.4 or seen.has(key):
				continue
			var n := 0
			var stack: Array = [key]
			seen[key] = true
			while not stack.is_empty():
				var k: int = stack.pop_back()
				n += 1
				var cy: int = k / w
				var cx: int = k % w
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var ny: int = cy + dy
						var nx: int = cx + dx
						if ny < 0 or nx < 0 or ny >= h or nx >= w:
							continue
						var nk := ny * w + nx
						if seen.has(nk) or img.get_pixel(nx, ny).a < 0.4:
							continue
						seen[nk] = true
						stack.append(nk)
			sizes.append(n)
	if sizes.size() < 2:
		return 0
	sizes.sort()
	return int(sizes[sizes.size() - 2])

func _blob_count(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var blobs := 0
	for y in h:
		for x in w:
			var key := y * w + x
			if img.get_pixel(x, y).a <= 0.06 or seen.has(key):
				continue
			blobs += 1
			var stack: Array = [key]
			seen[key] = true
			while not stack.is_empty():
				var k: int = stack.pop_back()
				var cy: int = k / w
				var cx: int = k % w
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var ny: int = cy + dy
						var nx: int = cx + dx
						if ny < 0 or nx < 0 or ny >= h or nx >= w:
							continue
						var nk := ny * w + nx
						if seen.has(nk) or img.get_pixel(nx, ny).a <= 0.06:
							continue
						seen[nk] = true
						stack.append(nk)
	return blobs

# #239再7: 背景の靄/板が焼き付いていないか。
# 背景の矩形があると、下半分の各行の左右の縁がぴたりと同じ列に揃う(=まっすぐな縦の縁)。
# 本来のシルエットなら縁は行ごとにばらつく。揃っている行の割合を返す。
func _straight_edge_ratio(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var lefts := {}
	var rights := {}
	var rows := 0
	for y in range(h / 2, h):
		var lx := -1
		var rx := -1
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				if lx < 0:
					lx = x
				rx = x
		if lx < 0:
			continue
		rows += 1
		lefts[lx] = int(lefts.get(lx, 0)) + 1
		rights[rx] = int(rights.get(rx, 0)) + 1
	if rows == 0:
		return 0.0
	var best := 0
	for k in lefts:
		best = maxi(best, int(lefts[k]))
	for k2 in rights:
		best = maxi(best, int(rights[k2]))
	return float(best) / float(rows)

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
		for line in txt.split(char(10)):
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
	check(str(isle.name) == "北の孤島", "島8が北の孤島でない(%s)" % str(isle.name))
	check(int(isle.fame_req) == 400, "到達に必要な名声が400でない(%d)" % int(isle.fame_req))
	check(Database.tier_of(OUTER) == 4, "北の孤島のtierが果ての島と同格でない")
	check((isle.get("lords", []) as Array).is_empty(), "北の孤島に主が設定されている")
	# 果ての島の北 = z が小さい側
	var fin: Vector3 = Database.island(4).pos
	check(isle.pos.z < fin.z, "北の孤島が果ての島の北にない")
	check(str(isle.get("weather", "")) == "flurry", "北の孤島の天候が flurry でない")
	# 見た目: 雪原(緑が無い)かつ小さい
	var pal: Dictionary = Isle.PALETTES[OUTER]
	check(float(pal.get("small", 1.0)) < 1.0, "北の孤島が小さく描かれない")
	var g: Color = pal.grass
	check(g.r > 0.7 and g.g > 0.7 and g.b > 0.7, "北の孤島の地面が雪原(白)でない")

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
	check(not pool.has("tiamat"), "北の孤島にティアマットが出る")
	check(not pool.has("zahhak"), "北の孤島にザッハークが出る")
	for want_mob in ["merman", "charybdis", "dagon", "amphiptere"]:
		check(pool.has(want_mob), "北の孤島に %s が出ない" % want_mob)

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
			check(sold, "北の孤島で %s が買えない" % sid)
		else:
			check(not sold, "北の孤島で %s が売られている" % sid)
	var want_weapons := ["spray", "lance", "cluster"]
	for wid in Database.weapons:
		var sold2: bool = (got.weapons as Array).has(wid)
		if want_weapons.has(wid):
			check(sold2, "北の孤島で %s が買えない" % wid)
		else:
			check(not sold2, "北の孤島で %s が売られている" % wid)
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
	check(not tavern_txt.contains("主の情報"), "北の孤島の酒場に「主の情報」が出ている")
	check(tavern_txt.contains("クルー"), "北の孤島の酒場にクルータブが無い")
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
	check(c_outer == GameState.hire_cost("marine"), "北の孤島のクルー雇用費が果ての島と違う")

	# ---------------- #249: リロード速度 ----------------
	var base: float = float(Database.weapons["gatling"].reload)
	# #249再: レビュアー再指定の倍率
	var want_reload := {
		"gatling": 1.0, "cannon": 1.6, "harpoon": 1.7, "torpedo": 2.0,
		"gatling2": 1.2, "cannon2": 1.8, "harpoon2": 1.9, "torpedo2": 2.2,
		"spray": 1.4, "lance": 1.8, "cluster": 2.2,
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
	check(int(spray.mag) < int(g2.mag), "乱射砲の弾数が重ガトリング砲以上になっている")
	check(float(spray.get("spray", 0.0)) > 0.0, "乱射砲が散らばらない")
	var lance: Dictionary = Database.weapons["lance"]
	check(float(lance.dmg) > float(Database.weapons["harpoon2"].dmg), "槍砲の威力が強化銛砲を上回っていない")
	check(not bool(lance.get("debuff", false)), "槍砲にデバフが付いている")
	check(bool(lance.get("pierce", false)), "槍砲が貫通しない")
	check(float(lance.get("pirate_burn", 0.0)) == 0.0, "槍砲に炎上効果が付いている")
	check(int(lance.mag) > int(Database.weapons["cannon2"].mag), "槍砲の弾数が大口径カノン砲を上回っていない")
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
	check(r8.has("この島の近海に主はいないようだ。"), "北の孤島のヒント(主がいない)が無い")
	check(r8.has("この島では珍しい武器が売っている。"), "北の孤島のヒント(珍しい武器)が無い")
	var r4: Array = Database.departure_hint_table(4).get("random", [])
	check(r4.has("北の孤島では珍しい武器が売っているらしい。"), "果ての島のヒントに北の孤島の案内が無い")
	# 果ての島の3回目の出港ではランダム枠が使われる(=上のヒントが出うる)
	var seen3 := {}
	for i3 in 300:
		seen3[str(Database.pick_departure_hint(4, 3, 999, true).get("text", ""))] = true
	for got3 in seen3:
		check(r4.has(str(got3)), "果ての島の3回目にランダム枠以外が出た(%s)" % str(got3))
	check(seen3.has("北の孤島では珍しい武器が売っているらしい。"), "果ての島の3回目に北の孤島の案内が出ない")

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
	check(world._sea_pirate_top(8) == world._sea_pirate_top(4), "北の孤島の海賊の格が果てと違う")
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

	# ---------------- #239再6: セイレーンの弾 ----------------
	var pl := CharacterBody2D.new()
	pl.add_to_group("player")
	add_child(pl)
	pl.global_position = Vector2(400, 0)
	var siren := CharacterBody2D.new()
	siren.set_script(Enemy)
	siren.setup("lord", "siren")
	add_child(siren)
	await get_tree().process_frame
	siren.player = pl
	var ways := {}
	var shapes := {}
	var upright_ok := true
	var wave_ok := true
	var dirs_seen := {}
	for t3 in 12:
		for c3 in get_children():
			if c3 is Area2D:
				c3.free()
		await get_tree().process_frame
		siren._ranged_attack(false)
		await get_tree().process_frame
		var n3 := 0
		for c4 in get_children():
			if not (c4 is Area2D):
				continue
			n3 += 1
			shapes[str(c4.get("shape"))] = true
			if not bool(c4.get("upright")):
				upright_ok = false
			if float(c4.get("wave_amp")) <= 0.0:
				wave_ok = false
			dirs_seen[snappedf(c4.get("dir").angle(), 0.001)] = true
		ways[n3] = true
	check(shapes.size() == 1 and shapes.has("note"), "セイレーンの弾が音符型でない(%s)" % str(shapes.keys()))
	check(upright_ok, "音符弾が進行方向へ回転してしまい音符に見えない")
	check(wave_ok, "音符弾が蛇行しない")
	var max_way := 0
	for k3 in ways:
		max_way = maxi(max_way, int(k3))
	check(max_way >= 3, "セイレーンの弾が3way以上にならない(最大%d)" % max_way)
	check(dirs_seen.size() >= 3, "セイレーンの弾がすべて同じ向きに飛んでいる")
	# 蛇行が実際に軌道を曲げるか(直進弾との横方向のずれで見る)
	var straight := Area2D.new()
	straight.set_script(Proj)
	add_child(straight)
	straight.from_player = false
	straight.setup(Vector2.RIGHT, {"dmg": 1.0, "shape": "note"})
	var wavy := Area2D.new()
	wavy.set_script(Proj)
	add_child(wavy)
	wavy.from_player = false
	wavy.setup(Vector2.RIGHT, {"dmg": 1.0, "shape": "note", "upright": true, "wave_amp": 170.0, "wave_freq": 7.5})
	# 蛇行の位相は弾ごとに乱数なので、ずれの最大値で見る(1周ぶん動かす)
	wavy._wave_ph = 0.0   # 位相を固定して測る
	var max_gap := 0.0
	for f3 in 40:
		await get_tree().physics_frame
		max_gap = maxf(max_gap, absf(wavy.global_position.y - straight.global_position.y))
	check(max_gap > 5.0, "蛇行弾が直進弾と同じ軌道(最大ずれ%.2f)" % max_gap)
	check(absf(straight.rotation) > 0.0001 and absf(wavy.rotation) < 0.0001, "upright の有無で弾の向きが変わらない")
	straight.free()
	wavy.free()
	siren.free()

	# ---------------- #239再6: レイスの瞬間移動でロックが外れる ----------------
	var w2 := Node2D.new()
	w2.set_script(World2)
	add_child(w2)
	var wr := CharacterBody2D.new()
	wr.set_script(Enemy)
	wr.setup("lord", "wraith")
	w2.add_child(wr)
	await get_tree().process_frame
	wr.player = pl
	wr._aggro = true
	w2._set_lock(wr)
	check(w2.lock_target == wr and wr.locked, "レイスをロックできない")
	wr._blink_t = 0.0
	wr._tick_blink(0.016)
	check(w2.lock_target == null, "レイスが瞬間移動してもロックが外れない")
	check(not wr.locked, "ロック解除後もロック表示が残る")
	w2.free()
	pl.free()

	# ---------------- #239再6: オクトパスの画像 ----------------
	for suf in ["", "_front", "_back"]:
		var ip := "res://assets/images/pixel/lord_kraken_lord%s.png" % suf
		check(ResourceLoader.exists(ip), "オクトパスのドット絵が無い: " + ip)
		var img := Image.load_from_file(ip)
		check(not img.is_empty() and img.get_used_rect().has_area(), "オクトパスのドット絵が空: " + ip)
		# 画面端で切れていないこと(外周1pxに不透明画素が無い)
		var rect := img.get_used_rect()
		check(rect.position.x > 0 and rect.position.y > 0
			and rect.end.x < img.get_width() and rect.end.y < img.get_height(),
			"オクトパスのドット絵が端で切れている: " + ip)
		# 体から離れた断片が無いこと(不透明画素の連結成分が1つ)
		check(_blob_count(img) == 1, "オクトパスのドット絵に体から離れた部分がある: " + ip)
		var src := "res://assets/images/lord_kraken_lord%s.png" % suf
		check(ResourceLoader.exists(src), "オクトパスの挿絵が無い: " + src)
		var simg := Image.load_from_file(src)
		# 挿絵は透過処理で外接矩形にトリミングされるため、端に接すること自体は正常。
		# 「生成時に切れた」場合は辺に沿って不透明画素がずらりと並ぶので、その割合で見る。
		check(_edge_fill(simg) < 0.5,
			"オクトパスの挿絵が端で切り落とされている(辺の%.0f%%が不透明): %s" % [_edge_fill(simg) * 100.0, src])

	# 航海中の描画で、灰色のプレースホルダではなく実際のドット絵が使われること
	var oct := CharacterBody2D.new()
	oct.set_script(Enemy)
	oct.setup("lord", "kraken_lord")
	add_child(oct)
	await get_tree().process_frame
	check(oct.sprite != null and oct.sprite.texture != null, "オクトパスにスプライトが無い")
	var tex_path := ""
	if oct.sprite and oct.sprite.texture:
		tex_path = str(oct.sprite.texture.resource_path)
	check(tex_path.contains("lord_kraken_lord"),
		"航海中のオクトパスがドット絵を読めずプレースホルダになっている(%s)" % tex_path)
	oct.free()

	# ---------------- #209再11: ボスラッシュ中は名声の通知を出さない ----------------
	var notices: Array = []
	var cb := func(t: String): notices.append(t)
	GameState.notice.connect(cb)
	GameState.reset_all()
	GameState.boss_rush = true
	GameState.add_fame(9999)
	check(notices.is_empty(), "ボスラッシュ中に名声の通知が出た: %s" % str(notices))
	GameState.reset_all()
	GameState.boss_rush = false
	GameState.add_fame(9999)
	var fame_notices: Array = notices.filter(func(t): return str(t).contains("名声が轟いた"))
	check(not fame_notices.is_empty(), "通常時に名声の通知が出なくなった")
	# 討伐メッセージにも名声・賞金の文言が出ないこと(分裂する主の分岐を含む)
	GameState.notice.disconnect(cb)
	for br in [true, false]:
		GameState.reset_all()
		GameState.boss_rush = br
		var msgs: Array = []
		var cb2 := func(t: String): msgs.append(t)
		GameState.notice.connect(cb2)
		# 夜の帝王の分裂体を1体だけ置き、それを倒して「元の主の討伐」を発生させる
		var bat := CharacterBody2D.new()
		bat.set_script(Enemy)
		bat.setup("lord", "night_bat_small")
		bat.split_root = "night_emperor"
		add_child(bat)
		bat.add_to_group("enemy")
		await get_tree().process_frame
		bat._die()
		await get_tree().process_frame
		var joined := "".join(msgs)
		if br:
			check(not joined.contains("名声"), "ボスラッシュの討伐メッセージに名声が出た: %s" % str(msgs))
			check(not joined.contains("賞金"), "ボスラッシュの討伐メッセージに賞金が出た: %s" % str(msgs))
			check(joined.contains("討伐"), "ボスラッシュで討伐メッセージ自体が出ない: %s" % str(msgs))
		else:
			check(joined.contains("名声"), "通常時に名声の文言が消えた: %s" % str(msgs))
		GameState.notice.disconnect(cb2)
	GameState.boss_rush = false

	# ---------------- #239再7: レイスのドット絵に背景の白いもやが無いこと ----------------
	for suf2 in ["", "_front", "_back"]:
		var wp := "res://assets/images/pixel/lord_wraith%s.png" % suf2
		check(ResourceLoader.exists(wp), "レイスのドット絵が無い: " + wp)
		var wimg := Image.load_from_file(wp)
		var ratio := _straight_edge_ratio(wimg)
		check(ratio < 0.6, "レイスのドット絵の下半身に背景の板(白いもや)が残っている(縁の%.0f%%が直線): %s" % [ratio * 100.0, wp])

	# ---------------- #250: 潮鳴りの島の強い日射し ----------------
	check(str(Database.island(1).get("weather", "")) == "sunny", "潮鳴りの島の天候が sunny でない")
	check(str(Database.island(0).get("weather", "")) == "", "始まりの島に天候が付いた(比較対象なので素のままであること)")
	var w3 := Node2D.new()
	w3.set_script(World2)
	var p_sun: Dictionary = w3._weather_params("sunny")
	var p_none: Dictionary = w3._weather_params("")
	check(float(p_sun.get("sunlight", 0.0)) > 0.0, "sunny に日射しのパラメータが無い")
	check(float(p_none.get("sunlight", 0.0)) == 0.0, "天候なしの海域に日射しが入っている")
	check(float(p_sun.get("night", 0.0)) == 0.0 and float(p_sun.get("rough", 0.0)) == 0.0,
		"sunny に夜・荒波が混ざっている")
	# 天候の補間対象に sunlight が含まれていること(含まれないと海域をまたいでも切り替わらない)。
	# 潮鳴りの島の真上に旗艦を置き、実際に _update_weather を回して確かめる。
	var sea_player := CharacterBody2D.new()
	add_child(w3)
	await get_tree().process_frame
	# _ready() で自前の海が組まれるので、旗艦の差し替えは初期化のあとに行う
	w3.add_child(sea_player)
	w3.player = sea_player
	sea_player.global_position = w3.island_pos(1)
	w3.phase = "sea"
	w3._weather_name = ""
	w3._weather_cur = w3._weather_params("")
	for f4 in 8:
		w3._update_weather(1.5)
	check(float(w3._weather_cur.get("sunlight", 0.0)) > 0.5,
		"潮鳴りの海域にいても日射しが反映されない(%.2f)" % float(w3._weather_cur.get("sunlight", 0.0)))
	# 始まりの島へ移ると日射しが引いていくこと
	sea_player.global_position = w3.island_pos(0)
	for f5 in 12:
		w3._update_weather(1.5)
	check(float(w3._weather_cur.get("sunlight", 0.0)) < 0.2,
		"始まりの島の海域でも日射しが残っている(%.2f)" % float(w3._weather_cur.get("sunlight", 0.0)))
	w3.free()
	# シェーダ側に uniform と反射の実装があること
	var shader_src := FileAccess.get_file_as_string("res://shaders/ocean2d.gdshader")
	check(shader_src.contains("uniform float sunlight"), "海面シェーダに sunlight の uniform が無い")
	check(shader_src.contains("col += vec3(1.0, 0.94, 0.74) * (sun_disc * 0.85 + sun_path * sbroken * 0.85) * sunlight;"),
		"海面シェーダで太陽の反射(光の道)が海面の色に加算されていない")
	check(shader_src.contains("col *= 1.0 + sunlight * 0.26;"), "海面シェーダで日射しによる明るさの底上げが無い")

	# ---------------- #239再8: ドット絵の左右の向き ----------------
	# 絵がどちら向きに描かれているかは face_left で宣言する。
	# 触腕/翼などが伸びている側が進行方向。左右を取り違えると航海中に後ろ向きに泳ぐ。
	check(bool(Database.lords["kraken_lord"].get("face_left", false)),
		"オクトパスの絵は左向き(触腕が左)なので face_left が要る")
	# #239再8: 横向きの絵を再生成し、頭と触角が左を向く絵になった
	check(bool(Database.combat_mobs["carabos"].get("face_left", false)),
		"カーラボスの絵は左向き(頭と触角が左)なので face_left が要る")
	# 実際に左右へ動かしたとき、反転が絵の向きと噛み合うこと
	var pl2 := CharacterBody2D.new()
	pl2.add_to_group("player")
	add_child(pl2)
	for spec3 in [["lord", "kraken_lord", true], ["mob", "carabos", true], ["lord", "wraith", true], ["lord", "griffon", true], ["lord", "night_emperor", true], ["lord", "night_bat_medium", false], ["lord", "night_bat_small", false]]:
		var e3 := CharacterBody2D.new()
		e3.set_script(Enemy)
		e3.setup(str(spec3[0]), str(spec3[1]))
		add_child(e3)
		await get_tree().process_frame
		e3._facing = "side"
		e3._facing_cd = 0.0
		e3._update_facing(Vector2.LEFT)
		var flip_left: bool = e3.sprite.flip_h
		# 左へ進むとき: 右向きの絵は反転する / 左向きの絵は反転しない
		check(flip_left == (not bool(spec3[2])),
			"%s が左へ進むときの反転が絵の向きと合っていない" % str(spec3[1]))
		e3.free()

	# ---------------- #239再8: キラーシェルは打ち返しのみ ----------------
	var ks := CharacterBody2D.new()
	ks.set_script(Enemy)
	ks.setup("mob", "killer_shell")
	add_child(ks)
	await get_tree().process_frame
	ks.player = pl2
	# 近接圏の外・射程の内(遠隔で撃つはずの距離)に置く
	var ks_far: float = float(ks._radius) + 400.0
	check(ks.attack_range > ks_far, "テストの距離取りが射程外(range=%.0f)" % ks.attack_range)
	pl2.global_position = ks.global_position + Vector2(ks_far, 0.0)
	var before := 0
	for c5 in get_children():
		if c5 is Area2D:
			before += 1
	for f6 in 20:
		ks._attack(0.2, ks_far)
	await get_tree().process_frame
	var after := 0
	for c6 in get_children():
		if c6 is Area2D:
			after += 1
	check(after == before, "キラーシェルが自分から遠隔攻撃している(弾%d発)" % (after - before))
	# 近接圏に入られても自分からは殴らない
	var hp_before := GameState.run_armor
	for f7 in 10:
		ks._attack(0.2, float(ks._radius) + 10.0)
	check(is_equal_approx(GameState.run_armor, hp_before), "キラーシェルが自分から近接攻撃している")
	# 撃たれたら打ち返す
	ks.take_hit(10.0, false, false)
	await get_tree().process_frame
	var after2 := 0
	for c7 in get_children():
		if c7 is Area2D:
			after2 += 1
	check(after2 > after, "キラーシェルが撃たれても打ち返さない")
	# 連射で撃たれても打ち返しは間隔を置く
	var mid := after2
	ks.take_hit(10.0, false, false)
	await get_tree().process_frame
	var after3 := 0
	for c8 in get_children():
		if c8 is Area2D:
			after3 += 1
	check(after3 == mid, "打ち返し弾にクールダウンが効いていない")
	ks.free()
	pl2.free()

	# ---------------- #251: 南の孤島 ----------------
	const SOUTH := 9
	var si: Dictionary = Database.island(SOUTH)
	check(str(si.name) == "南の孤島", "島9が南の孤島でない(%s)" % str(si.name))
	check(Database.tier_of(SOUTH) == Database.tier_of(6), "南の孤島が常闇の島と同格でない")
	check(int(si.fame_req) == int(Database.island(6).fame_req), "到達に必要な名声が常闇と違う")
	check((si.get("lords", []) as Array).is_empty(), "南の孤島に主が設定されている")
	check(si.pos.z > Database.island(6).pos.z, "南の孤島が常闇の島の南にない")
	check(str(si.get("weather", "")) == str(Database.island(1).get("weather", "")),
		"南の孤島の演出が潮鳴りの島と違う")
	var spal: Dictionary = Isle.PALETTES[SOUTH]
	check(float(spal.get("small", 1.0)) < 1.0, "南の孤島が小さく描かれない")
	var sg: Color = spal.grass
	check(sg.g > sg.r and sg.g > sg.b, "南の孤島の地面が草原(緑)でない")
	# 近海のモブは月下・星霜・常闇に出るものだけ
	var allowed := {}
	for isle_i2 in [2, 5, 6]:
		for mw_id in Database.mob_weights[isle_i2]:
			allowed[mw_id] = true
	var south_pool := {}
	for i5 in 600:
		south_pool[Database.pick_mob(SOUTH)] = true
	for mid2 in south_pool:
		check(allowed.has(mid2), "南の孤島に他の海域の敵(%s)が出る" % str(mid2))
	# #75再: クラーケン・ワイバーンは南の孤島から外れたので、それ以外を確かめる
	for mid3 in allowed:
		if str(mid3) == "kraken" or str(mid3) == "wyvern":
			check(not south_pool.has(mid3), "南の孤島から %s が外れていない" % str(mid3))
			continue
		check(south_pool.has(mid3), "南の孤島に %s が出ない" % str(mid3))
	# 造船所: 船は同格の島と同じ、武器は専用2種のみ
	var got_s: Dictionary = await _listed(port, SOUTH)
	var got_ref: Dictionary = await _listed(port, 6)
	(got_s.ships as Array).sort()
	(got_ref.ships as Array).sort()
	check(got_s.ships == got_ref.ships, "南の孤島の船の品揃えが常闇と違う(%s / %s)" % [str(got_s.ships), str(got_ref.ships)])
	var want_w2 := ["flamer", "chiller"]
	for wid5 in Database.weapons:
		var sold3: bool = (got_s.weapons as Array).has(wid5)
		if want_w2.has(wid5):
			check(sold3, "南の孤島で %s が買えない" % wid5)
		else:
			check(not sold3, "南の孤島で %s が売られている" % wid5)
	for other2 in [0, 1, 2, 3, 4, 5, 6, 7, 8]:
		for wid6 in want_w2:
			check(not Database.shop_has_weapon(other2, wid6), "島%d で %s が売られている" % [other2, wid6])
	# 酒場: 主がいないので主の情報タブが出ない
	GameState.current_island = SOUTH
	port._tavern_section = "lords"
	port.show_tavern()
	await get_tree().process_frame
	var st_txt := ""
	for n2 in port.content.find_children("*", "Button", true, false):
		st_txt += n2.text + "
"
	check(not st_txt.contains("主の情報"), "南の孤島の酒場に「主の情報」が出ている")
	# クルーの雇用条件は同格の島と同じ
	var c_south := GameState.hire_cost("marine")
	GameState.current_island = 6
	check(c_south == GameState.hire_cost("marine"), "南の孤島のクルー雇用費が常闇と違う")

	# ---------------- #251: 放射系の武器 ----------------
	var gat: Dictionary = Database.weapons["gatling"]
	for wid7 in ["flamer", "chiller"]:
		var fw: Dictionary = Database.weapons[wid7]
		check(float(fw.stream) > 0.0, "%s にリーチの上限が無い" % wid7)
		check(float(fw.cooldown) < float(gat.cooldown), "%s が押しっぱなしで連続放射にならない" % wid7)
		check(float(fw.spray) > 0.0, "%s が扇状に広がらない" % wid7)
		check(absf(float(fw.dmg) / float(gat.dmg) - 1.5) < 0.35, "%s の威力がガトリングの1.5倍程度でない" % wid7)
		check(absf(float(fw.mag) / float(gat.mag) - 1.5) < 0.35, "%s の弾数がガトリングの1.5倍程度でない" % wid7)
		check(absf(float(fw.reload) - float(gat.reload) * 2.2) < 0.001, "%s のリロードがガトリングの2.2倍でない" % wid7)
	check(float(Database.weapons["flamer"].pirate_burn) >= 1.0, "火炎放射器が海賊船を確実に炎上させない")
	check(str(Database.weapons["chiller"].debuff_kind) == "chill", "冷気放射器のデバフが chill でない")
	check(float(Database.weapons["chiller"].get("pirate_burn", 0.0)) == 0.0, "冷気放射器に炎上が付いている")
	# 銛の効果設定で冷気のデバフ種別が上書きされないこと(旗艦・僚艦の両方)
	GameState.harpoon_debuff = "slip"
	var w_world := Node2D.new()
	w_world.set_script(World2)
	var crewed: Dictionary = w_world._crewed(Database.weapons["chiller"])
	check(str(crewed.get("debuff_kind", "")) == "chill",
		"冷気放射器のデバフが銛の設定で上書きされている(%s)" % str(crewed.get("debuff_kind", "")))
	var crewed_h: Dictionary = w_world._crewed(Database.weapons["harpoon"])
	check(str(crewed_h.get("debuff_kind", "")) == "slip", "銛のデバフ設定が効かなくなった")
	w_world.free()
	var esc_src := FileAccess.get_file_as_string("res://scripts2d/Escort2D.gd")
	check(esc_src.count("if not w.has(\"debuff_kind\"):") == 2,
		"僚艦の発射経路でデバフ種別の上書きを避けていない")
	# リーチ外で消えること
	var host2 := Node2D.new()
	add_child(host2)
	var fp := Area2D.new()
	fp.set_script(Proj)
	host2.add_child(fp)
	fp.from_player = true
	fp.setup(Vector2.RIGHT, Database.weapons["flamer"].duplicate())
	var reach: float = float(Database.weapons["flamer"].stream)
	var last_travel := 0.0
	var gone := false
	for f8 in 200:
		if not is_instance_valid(fp) or fp.is_queued_for_deletion():
			gone = true
			break
		last_travel = float(fp._travel)
		await get_tree().physics_frame
	# 寿命で消えたのではなく、指定のリーチで消えたことを距離で確かめる
	check(gone, "火炎がリーチ外でも消えない")
	check(last_travel > reach * 0.85 and last_travel < reach * 1.15,
		"火炎が消える距離がリーチと違う(%.0f / 指定%.0f)" % [last_travel, reach])
	host2.free()
	# 冷気は鈍化と麻痺の両方を与える
	# 攻撃間隔と移動速度の両方が実際に落ちること
	var chill_pl := CharacterBody2D.new()
	chill_pl.add_to_group("player")
	add_child(chill_pl)
	var atk_timers: Array = []
	var moved: Array = []
	for chilled in [false, true]:
		var ce := CharacterBody2D.new()
		ce.set_script(Enemy)
		ce.setup("mob", "kraken")
		add_child(ce)
		await get_tree().process_frame
		ce.player = chill_pl
		ce._aggro = true
		ce.global_position = Vector2.ZERO
		chill_pl.global_position = Vector2(3000, 0)   # 遠くに置いて追いかけさせる
		if chilled:
			ce.take_hit(1.0, false, true, false, "chill")
			check(ce._debuff_kind == "chill", "冷気のデバフが敵に入らない")
		# 攻撃間隔
		ce._atk_timer = 0.0
		ce._attack(0.0, 10.0)
		atk_timers.append(float(ce._atk_timer))
		# 移動距離
		ce.global_position = Vector2.ZERO
		for f9 in 20:
			await get_tree().physics_frame
		moved.append(ce.global_position.length())
		ce.free()
	check(float(atk_timers[1]) > float(atk_timers[0]) * 1.05,
		"冷気で攻撃頻度が落ちない(%.2f → %.2f)" % [float(atk_timers[0]), float(atk_timers[1])])
	check(float(moved[1]) < float(moved[0]) * 0.95,
		"冷気で移動速度が落ちない(%.1f → %.1f)" % [float(moved[0]), float(moved[1])])
	chill_pl.free()

	# ---------------- #241再3: 南の孤島のヒント ----------------
	var r9: Array = Database.departure_hint_table(SOUTH).get("random", [])
	check(r9.has("この島の近海に主はいないようだ。"), "南の孤島のヒント(主がいない)が無い")
	check(r9.has("この島では珍しい武器が売っている。"), "南の孤島のヒント(珍しい武器)が無い")
	for from_isle in [2, 5, 6]:
		var rr: Array = Database.departure_hint_table(from_isle).get("random", [])
		check(rr.has("南の孤島では珍しい武器が売っているらしい。"),
			"島%d のヒントに南の孤島の案内が無い" % from_isle)

	# ---------------- 全島の総ざらい(島を増やしたときの取りこぼし検出) ----------------
	# 島に連動する配列・パレット・天候・ヒントに抜けがあると、その島に入った瞬間に
	# 落ちたり無言で別の島の値を使ってしまうので、全島ぶんまとめて確かめる。
	var w5 := Node2D.new()
	w5.set_script(World2)
	for isl in Database.islands.size():
		var d5: Dictionary = Database.island(isl)
		check(int(d5.id) == isl, "島%d の id が添字と食い違う(%d)" % [isl, int(d5.id)])
		check(str(d5.name) != "", "島%d に名前が無い" % isl)
		check(isl < Database.mob_weights.size(), "島%d ぶんの mob_weights が無い" % isl)
		var wsum := 0.0
		for k5 in Database.mob_weights[isl]:
			wsum += float(Database.mob_weights[isl][k5])
			check(Database.combat_mobs.has(k5), "島%d の出現表に未定義の敵(%s)" % [isl, str(k5)])
		check(absf(wsum - 1.0) < 0.02, "島%d の出現割合の合計が1でない(%.3f)" % [isl, wsum])
		check(isl < Isle.PALETTES.size(), "島%d ぶんの配色が無い" % isl)
		# 天候名が実装済みのものであること(未実装名だと無言で素の海になる)
		var wn := str(d5.get("weather", ""))
		if wn != "":
			var wp: Dictionary = w5._weather_params(wn)
			var any := false
			for k6 in wp:
				if k6 == "tint":
					any = any or (wp[k6] as Color).a > 0.001
				elif k6 == "moon":
					any = any or not is_equal_approx(float(wp[k6]), 1.0)
				else:
					any = any or absf(float(wp[k6])) > 0.001
			check(any, "島%d の天候 %s が未実装(何も起きない)" % [isl, wn])
		# 主がいる島は、その主の island がこの島を指していること
		for lid5 in (d5.get("lords", []) as Array):
			check(Database.lords.has(str(lid5)), "島%d に未定義の主(%s)" % [isl, str(lid5)])
			check(int(Database.lords[str(lid5)].island) == isl,
				"主 %s の所属島が %d でなく %d" % [str(lid5), isl, int(Database.lords[str(lid5)].island)])
		# 出港ヒントは全島にあること
		check(not (Database.departure_hint_table(isl).get("random", []) as Array).is_empty(),
			"島%d に出港ヒントが無い" % isl)
		# 造船所で最低1隻・1つは買えること(制限のかけ過ぎで空にならないように)
		var any_ship := false
		for sid5 in Database.ships:
			if Database.shop_has_ship(isl, sid5):
				any_ship = true
				break
		check(any_ship, "島%d の造船所に船が1隻も無い" % isl)
	w5.free()
	# 島の座標が重なっていないこと
	for a5 in Database.islands.size():
		for b5 in range(a5 + 1, Database.islands.size()):
			var pa: Vector3 = Database.island(a5).pos
			var pb: Vector3 = Database.island(b5).pos
			check(Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)) > 400.0,
				"島%d と島%d が近すぎる" % [a5, b5])

	# ---------------- #239再9: 弾の形が実際に描画できること ----------------
	# 自己交差した多角形は Polygon2D が三角形分割に失敗し、無言で「何も描かれない」。
	# 音符弾が実際にそうなっていたので、全形状ぶん機械的に確かめる。
	var shapes_all := ["", "note", "flame_jet", "frost_jet", "small", "needle", "star",
		"grain", "ellipse", "ellipse_s"]
	for shp in shapes_all:
		var sp := Area2D.new()
		sp.set_script(Proj)
		add_child(sp)
		sp.from_player = false
		sp.setup(Vector2.UP, {"dmg": 10.0, "shape": shp})
		await get_tree().process_frame
		var drawn := false
		for c9 in sp.get_children():
			if c9 is Polygon2D:
				var tri := Geometry2D.triangulate_polygon(c9.polygon)
				drawn = tri.size() > 0
				break
		check(drawn, "弾の形 \"%s\" が描画されない(多角形の三角形分割に失敗)" % shp)
		sp.free()

	# 島の海岸線と障害物の輪郭も、ランダム生成なので退化していないこと
	var IsleS = preload("res://scripts2d/Island2D.gd")
	for isl2 in Database.islands.size():
		var iv := StaticBody2D.new()
		iv.set_script(IsleS)
		iv.setup(isl2)
		add_child(iv)
		await get_tree().process_frame
		for base_r in [132.0, 112.0, 86.0, 52.0]:
			var coast: PackedVector2Array = iv._coast(base_r, float(IsleS.PALETTES[isl2].wob), 1)
			check(Geometry2D.triangulate_polygon(coast).size() > 0,
				"島%d の海岸線(半径%.0f)が描画できない" % [isl2, base_r])
		iv.free()
	var ObsS = preload("res://scripts2d/Obstacle2D.gd")
	for kind2 in ["reef", "ice"]:
		for t5 in 30:
			var ob := StaticBody2D.new()
			ob.set_script(ObsS)
			ob.setup(kind2)
			add_child(ob)
			await get_tree().process_frame
			check(Geometry2D.triangulate_polygon(ob._shape).size() > 0,
				"障害物(%s)の輪郭が描画できない" % kind2)
			ob.free()

	# ---------------- #248再2/#252: 魚雷まわり ----------------
	# クラスター魚雷の距離別のふるまい(レビュアー指定の①②③)
	var cl2: Dictionary = Database.weapons["cluster"]
	check(float(cl2.dmg) > float(Database.weapons["torpedo2"].dmg),
		"分裂前に当てたときの威力が追尾魚雷改を超えない")
	var cl_cases := [[80.0, 3], [300.0, 1], [900.0, 3]]
	for cse in cl_cases:
		var dist: float = float(cse[0])
		var want_hits: int = int(cse[1])
		var got_hits := 0
		var trials := 4
		for tr in trials:
			var tgt := CharacterBody2D.new()
			tgt.set_script(Enemy)
			tgt.setup("mob", "narwhal")
			add_child(tgt)
			await get_tree().process_frame
			tgt.global_position = Vector2(dist, 0.0)
			tgt.speed = 0.0
			tgt.is_escort = true
			tgt.hp = 99999.0
			# 物理サーバへ位置が反映される前に撃つと、離れていても当たってしまう
			for pw in 2:
				await get_tree().physics_frame
			var hp0: float = tgt.hp
			var cp := Area2D.new()
			cp.set_script(Proj)
			add_child(cp)
			cp.from_player = true
			cp.global_position = Vector2.ZERO
			cp.setup(Vector2.RIGHT, Database.weapons["cluster"].duplicate(), tgt)
			for f10 in 460:
				await get_tree().physics_frame
				if not is_instance_valid(tgt):
					break
				if hp0 - tgt.hp >= float(cl2.dmg) - 0.01:
					break
			var dealt: float = (hp0 - tgt.hp) if is_instance_valid(tgt) else 0.0
			got_hits += int(round(dealt / (float(cl2.dmg) / 3.0)))
			if is_instance_valid(tgt):
				tgt.free()
			for c10 in get_children():
				if c10 is Area2D:
					c10.free()
		var avg: float = float(got_hits) / float(trials)
		check(absf(avg - float(want_hits)) < 0.6,
			"クラスター魚雷 距離%.0f の命中が %d 発ぶんでない(実測%.1f)" % [dist, want_hits, avg])

	# #252: ロックオンしていないと魚雷系は撃てず、弾も減らない
	var w6 := Node2D.new()
	w6.set_script(World2)
	var src6 := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	check(src6.contains("if lock_target == null or not is_instance_valid(lock_target):"),
		"ロックオンしていないときに魚雷系を撃てないようにしていない")
	check(src6.count("if lock_target == null or not is_instance_valid(lock_target):") >= 2,
		"発射側と実処理側の両方でロックの有無を確認していない")
	w6.free()

	# ---------------- #254/#73再2: 海賊の攻撃力 ----------------
	check(int(Database.pirates["dread"].dmg) == 22, "海賊(大)の攻撃力が22でない(%d)" % int(Database.pirates["dread"].dmg))
	check(int(Database.pirates["king"].dmg) == 26, "海賊王の攻撃力が26でない(%d)" % int(Database.pirates["king"].dmg))

	# ---------------- #253: 波の音 ----------------
	check(ResourceLoader.exists(Audio.AMBIENT_FILE), "波の音の音源が無い: " + Audio.AMBIENT_FILE)
	check(Audio._ambient != null and Audio._ambient.stream != null, "波の音が読み込まれていない")
	if Audio._ambient and Audio._ambient.stream is AudioStreamMP3:
		check((Audio._ambient.stream as AudioStreamMP3).loop, "波の音がループしない")
	check(Audio.process_mode == Node.PROCESS_MODE_ALWAYS, "ポーズ中に波の音を止められない(Audioが動かない)")
	# 状態ごとの鳴り分け
	var was_paused := get_tree().paused
	Audio.ambient_enabled = true
	get_tree().paused = false
	await get_tree().process_frame
	check(Audio.ambient_playing(), "ゲーム中に波の音が鳴らない")
	get_tree().paused = true
	await get_tree().process_frame
	check(not Audio.ambient_playing(), "ポーズ中に波の音が止まらない")
	get_tree().paused = false
	await get_tree().process_frame
	check(Audio.ambient_playing(), "ポーズ解除後に波の音が戻らない")
	Audio.ambient_enabled = false
	await get_tree().process_frame
	check(not Audio.ambient_playing(), "オープニング・エンディングで波の音が止まらない")
	get_tree().paused = was_paused
	# タイトルへ戻る経路で必ず止めていること
	var wsrc := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	check(wsrc.count("Audio.ambient_enabled = false") >= 3,
		"タイトル・エンディングへ戻る経路の一部で波の音を止めていない")

	# ---------------- #241再4/#177再/#248再3/#255/#212再2/#243再 ----------------
	# #241再4: ヒントの文言
	for isl3 in [4]:
		var r_fin: Array = Database.departure_hint_table(isl3).get("random", [])
		check(r_fin.has("レヴィアタンの追尾弾は強力だ。銛のデバフ効果を活用しよう。"), "果ての島のヒント(追尾弾)が修正されていない")
		check(r_fin.has("レヴィアタンの遠隔攻撃は激しい。銛のデバフ効果を活用しよう。"), "果ての島のヒント(遠隔攻撃)が修正されていない")
		for bad in r_fin:
			check(not str(bad).contains("銛の麻痺効果"), "「銛の麻痺効果」の表記が残っている: %s" % str(bad))
	var r_storm: Array = Database.departure_hint_table(3).get("random", [])
	for bad2 in r_storm:
		check(not str(bad2).begins_with("カリュブディス"), "嵐越えのカリュブディスのヒントが残っている: %s" % str(bad2))

	# #177再: 討伐記録の並び(マーマン〜ティアマットはカーラボスと海賊(小)の間)
	var order_b: Array = []
	for e_b in Database.bestiary:
		order_b.append(str(e_b.id))
	var i_cara: int = order_b.find("carabos")
	var i_raider: int = order_b.find("raider")
	check(i_cara >= 0 and i_raider > i_cara, "討伐記録にカーラボス/海賊(小)が無い")
	var want_mid := ["merman", "charybdis", "amphiptere", "dagon", "zahhak", "tiamat"]
	check(order_b.slice(i_cara + 1, i_raider) == want_mid,
		"討伐記録の並びが指定と違う: %s" % str(order_b.slice(i_cara + 1, i_raider)))

	# #248再3: クラスター魚雷は分裂前後とも少し遅い
	check(float(Database.weapons["cluster"].speed_mult) < 0.55, "クラスター魚雷の速度が下がっていない")
	check(float(Database.weapons["cluster"].speed_mult) < float(Database.weapons["torpedo2"].speed_mult),
		"クラスター魚雷が追尾魚雷改より遅くない")

	# #255: 巨大戦艦は一回り小さい
	var PlayerS = preload("res://scripts2d/Player2D.gd")
	var psrc := FileAccess.get_file_as_string("res://scripts2d/Player2D.gd")
	check(psrc.contains("if GameState.ship_id == \"dread\":"), "旗艦の巨大戦艦が小さくなっていない")
	var esrc2 := FileAccess.get_file_as_string("res://scripts2d/Escort2D.gd")
	check(esrc2.contains("if ship_id == \"dread\":"), "僚艦の巨大戦艦が小さくなっていない")

	# #212再2: 旗艦ラベルの赤囲み
	check(psrc.contains("lbl.add_theme_stylebox_override(\"normal\", lbl_box)"), "旗艦ラベルに枠が付いていない")
	check(psrc.contains("lbl_box.border_color = Color(1.0, 0.25, 0.20, 0.95)"), "旗艦ラベルの枠が赤でない")

	# #243再: タイトル背景が進捗で変わる
	var TitleS = preload("res://scripts/TitleScreen.gd")
	var ttl := CanvasLayer.new()
	ttl.set_script(TitleS)
	add_child(ttl)
	await get_tree().process_frame
	var had_c := GameState.has_cleared()
	var had_br := GameState.has_cleared_boss_rush()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://cleared.dat"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://boss_rush_cleared.dat"))
	check(ttl.title_bg_stage() == 0, "討伐前のタイトル背景が初期段階でない")
	GameState.mark_cleared()
	check(ttl.title_bg_stage() == 1, "レヴィアタン討伐後にタイトル背景が変わらない")
	GameState.mark_boss_rush_cleared()
	check(ttl.title_bg_stage() == 2, "ボスラッシュ制覇後にタイトル背景が変わらない")
	ttl.show_title()
	await get_tree().process_frame
	check(ttl._night_sky != null and ttl._night_sky.visible, "制覇後のタイトルに星空が出ない")
	if not had_br:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://boss_rush_cleared.dat"))
	if not had_c:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://cleared.dat"))
	ttl.free()

	# ---------------- #248再4/#256/#257/#258/#259/#106再/#251再/#229 ----------------
	# #248再4: 島名の変更
	check(str(Database.island(8).name) == "北の孤島", "島8が北の孤島でない(%s)" % str(Database.island(8).name))
	var wsrc2 := FileAccess.get_file_as_string("res://scripts/Database.gd")
	check(not wsrc2.contains("外れの小島"), "旧名「外れの小島」が残っている")

	# #257: 舷側発射 — 中心が塞がっていても左右の舷から撃てる
	var w7 := Node2D.new()
	w7.set_script(World2)
	add_child(w7)
	await get_tree().process_frame
	var fp7 := CharacterBody2D.new()
	w7.add_child(fp7)
	w7.player = fp7
	fp7.global_position = Vector2.ZERO
	# 僚艦を「射線のすぐ脇」に置く(中心からは塞がるが、舷へずらせば通る)
	var esc7 := CharacterBody2D.new()
	w7.add_child(esc7)
	esc7.global_position = Vector2(95.0, 40.0)
	w7.escorts = [esc7]
	check(w7._line_blocker_from(Vector2.ZERO, Vector2.RIGHT, 800.0) == esc7, "中心からの射線が塞がっていない")
	var mz = w7._clear_muzzle(Vector2.RIGHT, 800.0)
	check(mz != null, "舷へずらせば通る場面で撃てない(舷側発射が効いていない)")
	if mz != null:
		check(absf((mz as Vector2).y) > 1.0, "発射原点が中心のまま(舷へずれていない)")
	# 僚艦が射線上に正対しているときは、どの舷からも撃てない(盾としての遮断は残す)
	esc7.global_position = Vector2(95.0, 0.0)
	check(w7._clear_muzzle(Vector2.RIGHT, 800.0) == null, "僚艦が正面に重なっているのに撃ててしまう")
	check(w7.BROADSIDE_OFFSET > 0.0, "舷側のオフセットが設定されていない")

	# #256: 撃てないことを伝える(トーストのクールダウンとオーバーレイ)
	var seen_msgs: Array = []
	var cb7 := func(t: String): seen_msgs.append(t)
	GameState.notice.connect(cb7)
	w7._los_toast_t = 0.0
	w7._notify_los_blocked("大砲")
	w7._notify_los_blocked("大砲")   # 連打しても2回目は出ない
	check(seen_msgs.size() == 1, "射線ブロックのトーストがクールダウンしていない(%d件)" % seen_msgs.size())
	check(str(seen_msgs[0]).contains("射線"), "トーストの文言が射線ブロックを示していない: %s" % str(seen_msgs[0]))
	GameState.notice.disconnect(cb7)
	var LosS = preload("res://scripts2d/LosOverlay2D.gd")
	var los := Node2D.new()
	los.set_script(LosS)
	add_child(los)
	los.set_state(esc7, Vector2.ZERO, Vector2(200, 0))
	check(los.blocker == esc7, "オーバーレイに遮っている僚艦が渡っていない")
	los.free()
	w7.free()

	# #258: 燃料は距離基準(止まっていれば減らない)
	var wsrc3 := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	check(wsrc3.contains("(_moved / _solo_px)"), "燃料消費が距離基準になっていない")
	check(not wsrc3.contains("run_food - delta * 1.5"), "時間基準の燃料消費が残っている")

	# #259: 律速艦の名前
	GameState.reset_all()
	check(str(GameState.slowest_ship_name()) == str(GameState.ship().name), "単艦のとき律速艦が旗艦でない")
	check(wsrc3.contains("が律速"), "出港時に船団速度を知らせていない")

	# #106再: 魚雷が空中の敵をすり抜けたときの案内
	var psrc2 := FileAccess.get_file_as_string("res://scripts2d/Projectile2D.gd")
	check(psrc2.contains("魚雷は空中の敵には当たらない!"), "空中の敵をすり抜けた案内が無い")
	check(psrc2.contains("_aerial_told"), "案内が弾ごとに1回だけになっていない")

	# #251再: 放射系の絵と持続音
	for fx in ["res://assets/images/pixel/fx_flame.png", "res://assets/images/pixel/fx_frost.png"]:
		check(ResourceLoader.exists(fx), "放射系の弾の絵が無い: " + fx)
	check(str(Database.weapons["flamer"].art).contains("fx_flame"), "火炎放射器に専用の絵が割り当たっていない")
	check(str(Database.weapons["chiller"].art).contains("fx_frost"), "冷気放射器に専用の絵が割り当たっていない")
	check(str(Database.weapons["flamer"].loop_sfx) == "sfx_flamer", "火炎放射器の持続音が設定されていない")
	check(str(Database.weapons["chiller"].loop_sfx) == "sfx_chiller", "冷気放射器の持続音が設定されていない")
	for lk in ["sfx_flamer", "sfx_chiller"]:
		check(Audio.LOOP_FILES.has(lk), "持続音の音源が登録されていない: " + lk)
		check(ResourceLoader.exists(str(Audio.LOOP_FILES[lk])), "持続音の音源が無い: " + str(Audio.LOOP_FILES[lk]))
	# 当たり判定は絵ではなく従来の図形のまま
	var fxp := Area2D.new()
	fxp.set_script(Proj)
	add_child(fxp)
	fxp.from_player = true
	fxp.setup(Vector2.RIGHT, Database.weapons["flamer"].duplicate())
	await get_tree().process_frame
	var has_shape := false
	for c11 in fxp.get_children():
		if c11 is CollisionShape2D:
			has_shape = c11.shape != null
	check(has_shape, "絵に置き換えたら当たり判定が無くなった")
	fxp.free()

	# #229: 追加した漁獲物と出現海域
	var want_fish := {"turtle": [250, 3], "lobster": [200, 2], "anglerfish": [140, 2], "conger": [190, 2]}
	for fid in want_fish:
		check(Database.fish.has(fid), "漁獲物 %s が無い" % fid)
		if Database.fish.has(fid):
			check(int(Database.fish[fid].price) == int(want_fish[fid][0]), "%s の基準価格が違う" % fid)
			check(int(Database.fish[fid].cap) == int(want_fish[fid][1]), "%s の魚倉占有が違う" % fid)
			check(ResourceLoader.exists("res://assets/images/pixel/fish_%s.png" % fid), "%s の絵が無い" % fid)
	var want_spawn := {
		9: ["turtle"],
		8: ["marlin"],
		4: ["octopus", "squid", "bonito", "anglerfish", "conger", "lobster", "turtle", "marlin"],
	}
	for isl4 in want_spawn:
		var got_sp: Array = (Database.island(int(isl4)).get("spawn", []) as Array).duplicate()
		got_sp.sort()
		var exp_sp: Array = (want_spawn[isl4] as Array).duplicate()
		exp_sp.sort()
		check(got_sp == exp_sp, "島%d の漁獲物が指定と違う: %s" % [int(isl4), str(got_sp)])
	for isl5 in [2, 5, 6]:
		check((Database.island(isl5).get("spawn", []) as Array).has("anglerfish"), "島%d にアンコウが出ない" % isl5)
	for isl6 in [3, 7]:
		check((Database.island(isl6).get("spawn", []) as Array).has("conger"), "島%d にアナゴが出ない" % isl6)

	# #255再: 巨大戦艦をさらに一回り小さく
	check(psrc.contains("extra = 0.76"), "巨大戦艦がさらに小さくなっていない")

	# ---------------- #251再2/#187再3/#229再 ----------------
	# #251再2: 放射音は「押している間ずっと」鳴らす(連射の合間で止めない)
	var w8 := Node2D.new()
	w8.set_script(World2)
	add_child(w8)
	await get_tree().process_frame
	GameState.reset_all()
	GameState.fleet[0].ship_id = "corvette"   # 武器スロットのある船
	GameState.fleet[0].weapons[0] = "flamer"
	w8.slot_cooldowns = [0.0, 0.0, 0.0, 0.0]
	check(w8._loop_sfx_wanted(true) == "sfx_flamer", "押している間に放射音が鳴らない")
	check(w8._loop_sfx_wanted(false) == "", "押していないのに放射音が鳴る")
	# 1発ごとのクールダウン中(=連射の合間)でも鳴らし続ける
	w8.slot_cooldowns[0] = float(Database.weapons["flamer"].cooldown)
	check(w8._loop_sfx_wanted(true) == "sfx_flamer", "連射の合間で放射音が止まる")
	# リロード中は止める
	w8.slot_cooldowns[0] = float(Database.weapons["flamer"].reload)
	check(w8._loop_sfx_wanted(true) == "", "リロード中も放射音が鳴り続ける")
	# 放射系でない武器では鳴らさない
	GameState.fleet[0].weapons[0] = "gatling"
	w8.slot_cooldowns[0] = 0.0
	check(w8._loop_sfx_wanted(true) == "", "放射系でない武器で放射音が鳴る")
	w8.free()

	# #187再3: 「デバフが効かない」の案内は時間で間引く
	var gh := CharacterBody2D.new()
	gh.set_script(Enemy)
	gh.setup("lord", "ghost")
	add_child(gh)
	await get_tree().process_frame
	var told: Array = []
	var cb8 := func(t: String):
		if str(t).contains("デバフが効かない"):
			told.append(t)
	GameState.notice.connect(cb8)
	# 幽霊船は15%で回避し、回避すると案内の手前で返る。no_dodge=true で確実に当てる
	for k8 in 30:
		gh.take_hit(1.0, false, true, true)   # 銛で連打
	check(told.size() == 1, "デバフ無効の案内が間引かれていない(30発で%d回)" % told.size())
	check(gh._no_debuff_told_t > 0.0, "案内のクールダウンが働いていない")
	# 時間が経てばまた出る
	gh._no_debuff_told_t = 0.0
	gh.take_hit(1.0, false, true, true)
	check(told.size() == 2, "時間が経っても案内が出ない")
	GameState.notice.disconnect(cb8)
	check(Enemy.NO_DEBUFF_TOLD_CD >= 5.0, "案内の間隔が短すぎる")
	gh.free()

	# #229再: カジキマグロ
	check(Database.fish.has("marlin"), "カジキマグロが無い")
	check(int(Database.fish["marlin"].price) == 270, "カジキマグロの基準価格が違う")
	check(int(Database.fish["marlin"].cap) == 4, "カジキマグロの魚倉占有が違う")
	check(ResourceLoader.exists("res://assets/images/pixel/fish_marlin.png"), "カジキマグロの絵が無い")
	var sp8: Array = (Database.island(8).get("spawn", []) as Array)
	check(sp8 == ["marlin"], "北の孤島の漁獲物がカジキマグロのみでない: %s" % str(sp8))
	var sp4: Array = (Database.island(4).get("spawn", []) as Array).duplicate()
	sp4.sort()
	var exp4: Array = ["octopus", "squid", "bonito", "anglerfish", "conger", "lobster", "turtle", "marlin"]
	exp4.sort()
	check(sp4 == exp4, "果ての島の漁獲物が指定と違う: %s" % str(sp4))

	# ---------------- #156再2: レヴィアタンの薙ぎ払いが弾を払い落とす ----------------
	var lv := CharacterBody2D.new()
	lv.set_script(Enemy)
	lv.setup("lord", "leviathan")
	add_child(lv)
	await get_tree().process_frame
	lv.global_position = Vector2.ZERO
	# 射程内の自機の弾3発と、射程外の1発、敵弾1発を置く
	var near_shots: Array = []
	for k9 in 3:
		var sp9 := Area2D.new()
		sp9.set_script(Proj)
		add_child(sp9)
		sp9.from_player = true
		sp9.setup(Vector2.RIGHT, {"dmg": 5.0})
		sp9.global_position = Vector2(20.0 * float(k9), 0.0)
		near_shots.append(sp9)
	var far_shot := Area2D.new()
	far_shot.set_script(Proj)
	add_child(far_shot)
	far_shot.from_player = true
	far_shot.setup(Vector2.RIGHT, {"dmg": 5.0})
	far_shot.global_position = Vector2(4000.0, 0.0)
	var enemy_shot := Area2D.new()
	enemy_shot.set_script(Proj)
	add_child(enemy_shot)
	enemy_shot.from_player = false
	enemy_shot.setup(Vector2.RIGHT, {"dmg": 5.0})
	enemy_shot.global_position = Vector2(10.0, 0.0)
	await get_tree().process_frame
	check(near_shots[0].is_in_group("player_shot"), "自機の弾がグループに登録されていない")
	var swept: int = int(lv._sweep_away_shots(120.0))
	check(swept == 3, "薙ぎ払いが射程内の弾を払い落とさない(%d発)" % swept)
	await get_tree().process_frame
	check(is_instance_valid(far_shot) and not far_shot.is_queued_for_deletion(), "射程外の弾まで消えた")
	check(is_instance_valid(enemy_shot) and not enemy_shot.is_queued_for_deletion(), "敵の弾まで消えた")
	far_shot.free()
	enemy_shot.free()
	lv.free()
	# 薙ぎ払いの処理から実際に呼ばれていること
	var esrc3 := FileAccess.get_file_as_string("res://scripts2d/Enemy2D.gd")
	check(esrc3.contains("_sweep_away_shots(melee_r)"), "薙ぎ払いから弾の払い落としが呼ばれていない")

	# ---------------- #258再/#260再/#261 ----------------
	# #258再: 停泊中も15%は消費する
	var wsrc4 := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	check(wsrc4.contains("IDLE_FUEL_RATE"), "停泊中の燃料消費が実装されていない")
	check(absf(World2.IDLE_FUEL_RATE - 0.15) < 0.001, "停泊中の消費が15%%でない(%.2f)" % World2.IDLE_FUEL_RATE)
	check(wsrc4.contains("(1.0 - IDLE_FUEL_RATE)"), "航行中のぶんが距離基準で加算されていない")

	# #260再: 武器のバランス調整(レビュアー指定値)
	var want260 := {
		"spray": {"dmg": 5.0, "mag": 50.0, "reload": 1.4},
		"lance": {"dmg": 28.0, "mag": 9.0},
		"harpoon": {"dmg": 20.0, "mag": 7.0, "reload": 1.7},
		"cannon": {"dmg": 38.0},
		"cannon2": {"dmg": 51.0},
		"harpoon2": {"reload": 1.9},
		"torpedo2": {"dmg": 32.0},
		"flamer": {"dmg": 4.0, "reload": 2.2},
		"chiller": {"dmg": 4.0, "reload": 2.2},
	}
	for wid9 in want260:
		for fld in want260[wid9]:
			var got9 := float(Database.weapons[wid9][fld])
			var exp9 := float(want260[wid9][fld])
			check(absf(got9 - exp9) < 0.001, "%s の %s が %.1f でない(%.2f)" % [wid9, fld, exp9, got9])
	# リロード倍率(#249再)の整合も保つ
	var base9 := float(Database.weapons["gatling"].reload)
	check(absf(float(Database.weapons["harpoon"].reload) - base9 * 1.7) < 0.001, "銛のリロードが基準の1.7倍でない")

	# #261: 回避はクリティカルと同じ枠で命中位置へ出す
	var esrc4 := FileAccess.get_file_as_string("res://scripts2d/Enemy2D.gd")
	check(esrc4.contains("_spawn_float_text(get_parent(), global_position, \"回避!\"")," 回避が浮き上がる表示になっていない")
	check(not esrc4.contains("が攻撃を回避!"), "回避のトースト表示が残っている")
	var psrc4 := FileAccess.get_file_as_string("res://scripts2d/Projectile2D.gd")
	check(psrc4.contains("static func _spawn_float_text"), "浮き上がる表示が共用化されていない")
	check(psrc4.contains("_spawn_float_text(world, pos, \"クリティカル!\""), "クリティカルが共用の表示を使っていない")
	# 実際に回避すると表示が出る(トーストは出ない)
	var dg := CharacterBody2D.new()
	dg.set_script(Enemy)
	dg.setup("mob", "charybdis")   # dodge を持つ敵
	add_child(dg)
	await get_tree().process_frame
	var toasts: Array = []
	var cb9 := func(t: String):
		if str(t).contains("回避"):
			toasts.append(t)
	GameState.notice.connect(cb9)
	var before9 := get_child_count()
	for k10 in 60:
		dg.take_hit(1.0, false, false)
	await get_tree().process_frame
	check(toasts.is_empty(), "回避でトーストが出ている: %s" % str(toasts))
	check(get_child_count() > before9, "回避しても浮き上がる表示が出ない")
	GameState.notice.disconnect(cb9)
	for c12 in get_children():
		if c12 is Label:
			c12.free()
	dg.free()

	# ---------------- #264/#256再/#262再/#263再 ----------------
	# #264: 撃てなかったときに弾を消費しない
	var wsrc5 := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	check(wsrc5.contains("func _fire_aim(w: Dictionary) -> bool:"), "_fire_aim が発射の成否を返さない")
	check(wsrc5.contains("if _fire_aim(w):"), "撃てたときだけ弾を減らす形になっていない")
	check(wsrc5.contains("return false   # #264"), "遮断時に false を返していない")
	# 実際に、射線が塞がっていると弾が減らないこと
	var w10 := Node2D.new()
	w10.set_script(World2)
	add_child(w10)
	await get_tree().process_frame
	var pl10 := CharacterBody2D.new()
	w10.add_child(pl10)
	w10.player = pl10
	pl10.global_position = Vector2.ZERO
	# 実際に狙う向き(マウスの位置は環境で変わるので実行時に求める)
	var aim_dir: Vector2 = (w10.get_global_mouse_position() - pl10.global_position).normalized()
	var eb10 := CharacterBody2D.new()
	w10.add_child(eb10)
	eb10.global_position = pl10.global_position + aim_dir * 95.0   # 真正面=どの舷からも塞がる
	w10.escorts = [eb10]
	check(w10._clear_muzzle(aim_dir, 864.0) == null, "テストの配置が射線を塞げていない")
	var fired: bool = w10._fire_aim(Database.weapons["gatling"].duplicate())
	check(not fired, "射線が塞がっているのに発射できた")
	eb10.global_position = pl10.global_position - aim_dir * 4000.0   # 背後へ退避
	var fired2: bool = w10._fire_aim(Database.weapons["gatling"].duplicate())
	check(fired2, "射線が空いているのに発射できない")
	w10.free()

	# #256再: 照準は常時表示(塞がっていなくても出る)
	var LosS2 = preload("res://scripts2d/LosOverlay2D.gd")
	var lsrc := FileAccess.get_file_as_string("res://scripts2d/LosOverlay2D.gd")
	check(lsrc.contains("if active:"), "照準の常時表示が実装されていない")
	check(lsrc.contains("aim_col"), "照準の色が塞がりの有無で変わらない")
	var los2 := Node2D.new()
	los2.set_script(LosS2)
	add_child(los2)
	los2.set_state(null, Vector2.ZERO, Vector2(100, 0), true)
	check(los2.active and los2.blocker == null, "塞がっていないときも照準を出す状態になっていない")
	los2.set_state(null, Vector2.ZERO, Vector2.ZERO, false)
	check(not los2.active, "航海中以外でも照準が出る")
	los2.free()

	# #262再/#263再: 指定されたHPと攻撃間隔
	check(Database.scaled_hp(float(Database.combat_mobs["killer_shell"].hp), 7) == 3900,
		"キラーシェルの海嘯の島でのHPが3900でない(%d)" % Database.scaled_hp(float(Database.combat_mobs["killer_shell"].hp), 7))
	check(Database.scaled_hp(float(Database.combat_mobs["zombie_fish"].hp), 6) == 900,
		"ゾンビウオの常闇の島でのHPが900でない(%d)" % Database.scaled_hp(float(Database.combat_mobs["zombie_fish"].hp), 6))
	check(absf(float(Database.lords["undine"].atk_cd) - 0.65) < 0.001,
		"ウンディーネの攻撃間隔が0.65でない(%.2f)" % float(Database.lords["undine"].atk_cd))

	# ---------------- #75再/#258再2/#266/#267/#265 ----------------
	# #75再: 出現海域の変更
	var want_islands := {
		"kraken": ["潮鳴りの島", "月下の島", "星霜の島", "常闇の島"],
		"wyvern": ["潮鳴りの島", "月下の島", "星霜の島", "常闇の島"],
		"killer_shell": ["海嘯の島", "果ての島", "北の孤島"],
		"carabos": ["海嘯の島", "果ての島", "北の孤島"],
	}
	for sp_id in want_islands:
		var got_isles: Array = []
		for isle7 in Database.islands_in_order():
			var idx7 := int(isle7.id)
			if idx7 < Database.mob_weights.size() and Database.mob_weights[idx7].has(sp_id):
				got_isles.append(str(isle7.name))
		got_isles.sort()
		var exp_isles: Array = (want_islands[sp_id] as Array).duplicate()
		exp_isles.sort()
		check(got_isles == exp_isles, "%s の出現海域が指定と違う: %s" % [sp_id, str(got_isles)])
	# 全島の出現割合は合計1
	for isl8 in Database.mob_weights.size():
		var sum8 := 0.0
		for k8 in Database.mob_weights[isl8]:
			sum8 += float(Database.mob_weights[isl8][k8])
		check(absf(sum8 - 1.0) < 0.02, "島%d の出現割合の合計が1でない(%.3f)" % [isl8, sum8])

	# #258再2: 燃料タンクは船団の平均 / 料理人は船団全体で逓減
	GameState.reset_all()
	var solo_food: float = GameState.max_food()
	check(absf(solo_food - float(GameState.ship().food)) < 0.01, "単艦の燃料が旗艦の値と違う")
	# 2番艦に燃料の多い船を足すと平均が上がる
	GameState.fleet.append(GameState.new_ship_entry("hauler", []))
	GameState.fleet[1].crew = [{"name": "副", "job": "firstmate", "hp": 1, "agi": 1, "sht": 1, "int_": 1, "vis": 1}]
	var two_food: float = GameState.max_food()
	var expect_avg: float = (float(Database.ships["raft"].food) + float(Database.ships["hauler"].food)) / 2.0
	check(absf(two_food - expect_avg) < 0.01, "燃料タンクが船団の平均でない(%.1f / 期待%.1f)" % [two_food, expect_avg])
	# 料理人: 1人目より2人目の上乗せが小さい(逓減)
	GameState.reset_all()
	var m0: float = GameState.food_drain_mult()
	GameState.fleet[0].crew = [{"name": "料1", "job": "cook", "hp": 0, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var m1: float = GameState.food_drain_mult()
	GameState.fleet[0].crew.append({"name": "料2", "job": "cook", "hp": 0, "agi": 0, "sht": 0, "int_": 0, "vis": 0})
	var m2: float = GameState.food_drain_mult()
	check(m1 < m0, "料理人1人で燃料消費が減らない")
	check(m2 < m1, "料理人2人目で燃料消費が減らない")
	check((m1 - m2) < (m0 - m1), "料理人の効果が逓減していない(1人目%.4f 2人目%.4f)" % [m0 - m1, m1 - m2])
	# 2番艦の料理人も効く
	GameState.reset_all()
	GameState.fleet.append(GameState.new_ship_entry("cutter", []))
	GameState.fleet[1].crew = [{"name": "副", "job": "firstmate", "hp": 1, "agi": 1, "sht": 1, "int_": 1, "vis": 1},
		{"name": "料", "job": "cook", "hp": 0, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	check(GameState.food_drain_mult() < 1.0, "2番艦の料理人が効いていない")

	# #267: 漂流者・漂流貨物
	var FlotS = preload("res://scripts2d/Flotsam2D.gd")
	for fx in ["res://assets/images/pixel/fx_castaway.png", "res://assets/images/pixel/fx_cargo.png"]:
		check(ResourceLoader.exists(fx), "漂流物の絵が無い: " + fx)
	GameState.reset_all()
	# 枠に空きがあればクルーになる
	GameState.fleet[0].crew = []
	var before_crew: int = (GameState.fleet[0].crew as Array).size()
	GameState.rescue_castaway()
	check((GameState.fleet[0].crew as Array).size() == before_crew + 1, "漂流者がクルーにならない")
	var jb: String = str((GameState.fleet[0].crew as Array)[0].job)
	check(jb != "sailor" and jb != "firstmate", "漂流者に水夫/副船長が出た(%s)" % jb)
	# 枠が無ければ謝礼
	GameState.fleet[0].crew = []
	for k11 in GameState.CREW_MAX:
		GameState.fleet[0].crew.append({"name": "満%d" % k11, "job": "veteran", "hp": 1, "agi": 1, "sht": 1, "int_": 1, "vis": 1})
	var money_before: int = GameState.money
	GameState.rescue_castaway()
	check(GameState.money > money_before, "枠が無いのに謝礼が出ない")
	check((GameState.fleet[0].crew as Array).size() == GameState.CREW_MAX, "満員なのにクルーが増えた")
	# 漂流貨物: 魚倉の空きぶんだけ積む
	GameState.reset_all()
	GameState.cargo = {}
	GameState.collect_drifting_cargo()
	var total_cargo := 0
	for cid in GameState.cargo:
		total_cargo += int(GameState.cargo[cid])
	check(total_cargo > 0, "漂流貨物から何も得られない")
	check(GameState.used_hold() <= GameState.max_hold(), "漂流貨物で魚倉があふれた")

	# #265: 実績
	check(Database.achievements.size() == 47, "実績の数が47でない(%d)" % Database.achievements.size())
	check(GameState.FAME_MAX == 999, "名声のカンストが999でない")
	GameState.reset_all()
	GameState.add_fame(99999)
	check(GameState.fame == 999, "名声がカンストしない(%d)" % GameState.fame)
	# バフの大きさが陣形を大きく下回る
	var max_pct := 0.0
	for a9 in Database.achievements:
		for k9 in (a9.buff as Dictionary):
			max_pct = maxf(max_pct, absf(float(a9.buff[k9]) - 1.0) * 100.0)
	check(max_pct <= 3.0 + 0.001, "バッヂのバフが3%%を超えている(%.1f%%)" % max_pct)
	check(max_pct * 2.0 < 15.0, "バッヂのバフが陣形(最大15%)に近すぎる")
	# グループごとの最大値の並び (5)>=(1)>=(4)>=(3)>=(2)>=(6)>=(7)
	var gmax := {}
	for a10 in Database.achievements:
		var g10 := str(a10.group)
		for k10 in (a10.buff as Dictionary):
			gmax[g10] = maxf(float(gmax.get(g10, 0.0)), absf(float(a10.buff[k10]) - 1.0) * 100.0)
	var order10 := ["wealth", "kill", "crew", "fleet", "lord", "fish", "relic"]
	for i10 in range(order10.size() - 1):
		var hi10 := float(gmax[order10[i10]])
		var lo10 := float(gmax[order10[i10 + 1]])
		check(hi10 >= lo10 - 0.001, "バフの大きさの並びが指定と違う(%s %.1f%% < %s %.1f%%)" % [order10[i10], hi10, order10[i10 + 1], lo10])
	# 討伐系は番号が進むほど効果が大きい
	var prev := -1.0
	for a11 in Database.achievements:
		if str(a11.group) != "kill" or str(a11.id) == "bounty_hunter":
			continue
		var pct11 := 0.0
		for k11b in (a11.buff as Dictionary):
			pct11 = absf(float(a11.buff[k11b]) - 1.0) * 100.0
		check(pct11 >= prev - 0.001, "討伐実績の効果が単調に増えていない(%s)" % str(a11.id))
		prev = pct11
	# バッヂ効果が実際に倍率へ効く
	GameState.reset_all()
	GameState.achieved = {}
	GameState.badge_id = ""
	check(is_equal_approx(GameState.badge_mult("reload"), 1.0), "バッヂ未選択なのに倍率がかかる")
	var pick := ""
	for a12 in Database.achievements:
		if (a12.buff as Dictionary).has("reload"):
			pick = str(a12.id)
			break
	check(pick != "", "リロード系のバッヂが無い")
	GameState.achieved[pick] = true
	GameState.select_badge(pick)
	check(GameState.badge_mult("reload") < 1.0, "バッヂを選んでも倍率が変わらない")
	GameState.select_badge(pick)   # 同じものを選び直すと解除
	check(GameState.badge_id == "", "同じバッヂを選び直しても解除されない")
	# 未達成のバッヂは選べない
	GameState.achieved = {}
	GameState.select_badge(pick)
	check(GameState.badge_id == "", "未達成のバッヂが選べてしまう")
	# 討伐で実績が達成される
	GameState.reset_all()
	GameState.achieved = {}
	for k12 in 30:
		GameState.record_kill("mob", "narwhal")
	check(GameState.is_achieved("kill_narwhal"), "討伐30体で実績が達成されない")
	# 主の討伐で実績が達成される(エンディング直行でも残るよう即保存)
	GameState.defeated_lords.append("leviathan")
	GameState.check_achievements()
	check(GameState.is_achieved("lord_leviathan"), "レヴィアタン討伐の実績が達成されない")
	check(FileAccess.file_exists(GameState.ACHIEVE_PATH), "実績が別ファイルへ保存されていない")
	# 全実績の絵が存在する
	for a13 in Database.achievements:
		var ic := str(a13.get("icon", ""))
		check(ic != "" and ResourceLoader.exists(ic), "実績 %s の絵が無い: %s" % [str(a13.id), ic])

	# ---------------- #269/#266再/#75再2/#273/#265再/#270-272/画像修正 ----------------
	# #269: 造船所の速度表示は小数1桁
	var psrc5 := FileAccess.get_file_as_string("res://scripts/PortUI.gd")
	check(psrc5.contains("速%.1f"), "造船所の速度が小数で表示されない")
	check(not psrc5.contains("速%.0f"), "船の速度に整数表示が残っている(敵の「速度:%d」は対象外)")

	# #266再: 大型運搬艦の速度12.0 / 駆逐艦の価格60000
	check(is_equal_approx(float(Database.ships["hauler"].speed), 12.0), "大型運搬艦の速度が12.0でない")
	check(int(Database.ships["hunter_h"].price) == 60000, "駆逐艦の価格が60000でない")

	# #75再2: 海嘯の島の顔ぶれ
	var kaisho: Dictionary = Database.mob_weights[7]
	for k_gone in ["charybdis", "amphiptere"]:
		check(not kaisho.has(k_gone), "海嘯の島から %s が外れていない" % k_gone)
	for k_add in ["moon_jelly", "starfish"]:
		check(kaisho.has(k_add), "海嘯の島に %s が追加されていない" % k_add)

	# #273: ウンディーネは引き撃ち中も船団の側を向く
	var esrc5 := FileAccess.get_file_as_string("res://scripts2d/Enemy2D.gd")
	check(esrc5.contains("face_dir = to.normalized()"), "引き撃ち中に船団の側を向いていない")
	check(not esrc5.contains("face_dir = -to.normalized()"), "引き撃ち中に背を向ける記述が残っている")

	# #265再: バフの弱体化と達成条件の緩和
	check(is_equal_approx(float(Database.achievement("rich").buff["flag_dmg_taken"]), 0.98), "錦衣玉食が-2.0%でない")
	check(is_equal_approx(float(Database.achievement("master_one").buff["shot_speed"]), 1.013), "極めし者が+1.3%でない")
	check(is_equal_approx(float(Database.achievement("master_all").buff["reload"]), 0.98), "極めし者達が-2.0%でない")
	check(int(Database.achievement("bounty_hunter").need) == 100, "バウンティハンターの条件が100隻でない")
	var gsrc5 := FileAccess.get_file_as_string("res://scripts/GameState.gd")
	check(gsrc5.contains('kill_count("pirate", "king") >= 2'), "海賊王の条件が2隻に緩和されていない")
	# バッヂ枠のサイズ統一
	check(psrc5.contains("func _unknown_badge"), "未達成のバッヂ枠が専用になっていない")
	check(psrc5.contains("_unknown_badge(44)"), "未達成の枠がバッヂと同じサイズになっていない")
	check(psrc5.contains("STRETCH_KEEP_ASPECT_CENTERED"), "バッヂのアスペクト比が保たれない")

	# #270-272 と 画像修正: ドット絵の精細化と透過
	for hi_id in ["lord_sawshark", "lord_walrus", "lord_dumbo", "mob_moon_jelly", "pirate_king", "lord_night_emperor"]:
		var ip5 := "res://assets/images/pixel/%s.png" % hi_id
		check(ResourceLoader.exists(ip5), "ドット絵が無い: " + ip5)
		var im5 := Image.load_from_file(ip5)
		# 高精細化: 長辺が180pxであること(従来は48px)
		check(maxi(im5.get_width(), im5.get_height()) >= 180, "%s のドット絵が精細でない(%dx%d)" % [hi_id, im5.get_width(), im5.get_height()])
		# 透過が効いていること(外周が不透明で埋まっていない)
		check(_edge_fill(im5) < 0.5, "%s の背景の透過が失敗している(辺の%.0f%%が不透明)" % [hi_id, _edge_fill(im5) * 100.0])

	# ---------------- #258再3: 体力は船団全体を参照し、逓減を緩める ----------------
	GameState.reset_all()
	GameState.fleet[0].crew = []
	var base_m: float = GameState.food_drain_mult()
	# 旗艦のクルーの体力が効く
	GameState.fleet[0].crew = [{"name": "甲", "job": "veteran", "hp": 10, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var flag_m: float = GameState.food_drain_mult()
	check(flag_m < base_m, "旗艦の体力で燃料消費が減らない")
	# 2番艦のクルーの体力も効く(船団全体を参照)
	GameState.fleet.append(GameState.new_ship_entry("cutter", []))
	GameState.fleet[1].crew = [{"name": "副", "job": "firstmate", "hp": 1, "agi": 1, "sht": 1, "int_": 1, "vis": 1},
		{"name": "乙", "job": "veteran", "hp": 10, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var fleet_m: float = GameState.food_drain_mult()
	check(fleet_m < flag_m, "2番艦の体力が燃料節約に効いていない")
	# 逓減が緩んでいること: 体力20→100 で節約が大きく伸びる(従来は2.6ptしか動かなかった)
	var gsrc6 := FileAccess.get_file_as_string("res://scripts/GameState.gd")
	check(gsrc6.contains("20.0 + 8.0 * log(1.0 + (h - 20.0) / 8.0)"), "逓減の式が緩められていない")
	check(not gsrc6.contains("10.0 + log(1.0 + (h - 10.0))"), "従来の逓減の式が残っている")
	# 実測: 体力20と体力100の差が10ポイント以上あること
	GameState.reset_all()
	GameState.fleet[0].crew = [{"name": "a", "job": "veteran", "hp": 20, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var m20: float = GameState.food_drain_mult()
	GameState.fleet[0].crew = [{"name": "b", "job": "veteran", "hp": 100, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var m100: float = GameState.food_drain_mult()
	check((m20 - m100) * 100.0 > 10.0,
		"体力20→100の差が小さすぎる(%.1fポイント)" % ((m20 - m100) * 100.0))
	# 頭打ちは残っている(体力100→200では大きく動かない)
	GameState.fleet[0].crew = [{"name": "c", "job": "veteran", "hp": 200, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var m200: float = GameState.food_drain_mult()
	check((m100 - m200) * 100.0 < (m20 - m100) * 100.0, "逓減が効かなくなっている")

	# ---------------- #274/#277/#239再8: 横向き1枚のみ+左右反転 ----------------
	var SideEnemy = preload("res://scripts2d/Enemy2D.gd")
	for spec14 in [["lord", "ghost"], ["mob", "killer_shell"], ["mob", "moon_jelly"], ["mob", "charybdis"]]:
		var k14 := str(spec14[0])
		var i14 := str(spec14[1])
		var d14: Dictionary = Database.enemy_def(k14, i14)
		check(bool(d14.get("side_only", false)), "%s に side_only が付いていない" % i14)
		# 正面/背面のドット絵は残っていない(残っていると再生成で復活してしまう)
		for sfx14 in ["front", "back"]:
			var pp14 := "res://assets/images/pixel/%s_%s_%s.png" % [k14, i14, sfx14]
			check(not ResourceLoader.exists(pp14), "%s が残っている(横向き1枚のみのはず)" % pp14)
		# 北へ動かしても横向きのまま。左右へ動かすと反転する
		var en14 = SideEnemy.new()
		en14.setup(k14, i14)
		add_child(en14)
		await get_tree().process_frame
		var base_tex14: Texture2D = en14.sprite.texture
		# 絵が再生成されて前後の画像が復活した状況を模す
		en14._tex_front = load("res://assets/images/pixel/mob_narwhal.png")
		en14._tex_back = load("res://assets/images/pixel/mob_narwhal.png")
		en14._update_facing(Vector2.UP)
		check(en14.sprite.texture == base_tex14, "%s が後ろ姿へ切り替わった" % i14)
		en14._update_facing(Vector2.DOWN)
		check(en14.sprite.texture == base_tex14, "%s が正面へ切り替わった" % i14)
		en14._facing_cd = 0.0
		en14._update_facing(Vector2.LEFT)
		var flip_left14: bool = en14.sprite.flip_h
		en14._facing_cd = 0.0
		en14._update_facing(Vector2.RIGHT)
		check(flip_left14 != en14.sprite.flip_h, "%s が左右で反転しない" % i14)
		en14.queue_free()
	# 比較対象: side_only でない敵は従来どおり後ろ姿へ切り替わる
	var norm14 = SideEnemy.new()
	norm14.setup("mob", "narwhal")
	add_child(norm14)
	await get_tree().process_frame
	var nbase14: Texture2D = norm14.sprite.texture
	norm14._facing_cd = 0.0
	norm14._update_facing(Vector2.UP)
	check(norm14.sprite.texture != nbase14, "通常の敵が後ろ姿へ切り替わらなくなっている")
	norm14.queue_free()

	# ---------------- #265再2: バッヂ画像は元画像の大きさに関わらず枠へ収まる ----------------
	var oversized := 0
	for a15 in Database.achievements:
		var ic15 := str(a15.get("icon", ""))
		if ic15 == "" or not ResourceLoader.exists(ic15):
			continue
		var w15 = port._badge_icon(a15, 44.0)
		add_child(w15)
		var ms15: Vector2 = w15.get_combined_minimum_size()
		if ms15.x > 44.5 or ms15.y > 44.5:
			oversized += 1
			if oversized == 1:
				check(false, "%s のバッヂが枠(44px)を超える(%.0fx%.0f)" % [str(a15.id), ms15.x, ms15.y])
		w15.queue_free()
	check(oversized == 0, "枠に収まらないバッヂが %d 件ある" % oversized)
	# 未達成の「?」も同じ枠
	var unk15 = port._unknown_badge(44.0)
	add_child(unk15)
	check(unk15.get_combined_minimum_size() == Vector2(44, 44), "未達成の枠が44px角でない")
	unk15.queue_free()
	# 航海中のHUDのバッヂも枠に収まる
	var hud15 := CanvasLayer.new()
	hud15.set_script(preload("res://scripts2d/HUD2D.gd"))
	add_child(hud15)
	await get_tree().process_frame
	hud15.badge_icon.texture = load("res://assets/images/pixel/lord_undine.png")
	var hms15: Vector2 = hud15.badge_icon.get_combined_minimum_size()
	check(hms15.x <= 28.5 and hms15.y <= 28.5,
		"名声の右のバッヂが枠(28px)を超える(%.0fx%.0f)" % [hms15.x, hms15.y])
	hud15.queue_free()

	# ---------------- #275/#276/#271再/#239再8: 再生成したドット絵 ----------------
	# 高精細(長辺180px以上)・背景の透過・額縁の直線や体から離れた断片が無いこと
	for rid in ["lord_griffon", "lord_griffon_front", "lord_griffon_back",
		"lord_night_emperor", "lord_night_emperor_front", "lord_night_emperor_back",
		"lord_night_bat_medium", "lord_night_bat_medium_front", "lord_night_bat_medium_back",
		"lord_night_bat_small", "lord_night_bat_small_front", "lord_night_bat_small_back",
		"lord_walrus", "lord_walrus_front", "lord_walrus_back",
		"lord_wraith", "lord_wraith_front", "lord_wraith_back", "mob_carabos"]:
		var rp := "res://assets/images/pixel/%s.png" % rid
		check(ResourceLoader.exists(rp), "ドット絵が無い: " + rp)
		if not ResourceLoader.exists(rp):
			continue
		var rimg := Image.load_from_file(rp)
		check(maxi(rimg.get_width(), rimg.get_height()) >= 180,
			"%s のドット絵が精細でない(%dx%d)" % [rid, rimg.get_width(), rimg.get_height()])
		check(_edge_fill(rimg) < 0.5, "%s の背景が抜けていない(辺の%.0f%%が不透明)" % [rid, _edge_fill(rimg) * 100.0])
		# 額縁の直線は本体から独立した細長い塊として残るので、面積で検出できる
		var stray := _stray_blob_max(rimg)
		check(stray < 30, "%s に体から離れた塊がある(面積%dpx)" % [rid, stray])

	# 再生成した横向きの絵は左向き。反転の登録が絵と噛み合っていること
	for lid in ["wraith", "griffon", "carabos", "night_emperor"]:
		var ldef: Dictionary = Database.enemy_def("lord", lid)
		if ldef.is_empty():
			ldef = Database.combat_mobs.get(lid, {})
		check(bool(ldef.get("face_left", false)), "%s の絵は左向きなのに face_left が付いていない" % lid)
	for rid2 in ["night_bat_medium", "night_bat_small"]:
		check(not bool(Database.lords[rid2].get("face_left", false)), "%s は右向きの絵なので face_left は不要" % rid2)

	port.free()
	if failures.is_empty():
		print("MAINTENANCE_TEST_OK outer_isle/shop/tavern/reload/weapons/hints/undine/bossrush/king_escorts/legion_hitbox/king_range/siren_notes/wraith_lock/octopus_art/wraith_haze/sunny_sea/facing/killer_shell/south_isle/streams/all_islands/bullet_shapes/cluster_range/torpedo_lock/pirate_dmg/ambient/hints2/bestiary/title_bg/flagship_label/broadside/los_toast/fuel_dist/fleet_speed/fx_art/new_fish/loop_sfx/no_debuff_toast/marlin/sweep_shots/idle_fuel/weapon_balance/dodge_text/ammo_guard/crosshair/hp_tuning/spawn_islands/fuel_avg/flotsam/achievements/ship_ui/kaisho/kite_face/badge_size/hi_res/fleet_hp/side_only/badge_fit/regen_art")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
