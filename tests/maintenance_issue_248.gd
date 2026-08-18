extends Node
## #248 外れの小島 / #249 リロード速度 / #241再2 ヒント / #239再5 ウンディーネ引き撃ち
## #209再10 ボスラッシュ(分裂・海賊王の取り巻き) / #197再3 海賊王の随伴艦

const Isle = preload("res://scripts2d/Island2D.gd")
const World2 = preload("res://scripts2d/World2D.gd")
const Proj = preload("res://scripts2d/Projectile2D.gd")

const OUTER := 8   # 外れの小島の island index

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
	# #249再: レビュアー再指定の倍率
	var want_reload := {
		"gatling": 1.0, "cannon": 1.6, "harpoon": 1.8, "torpedo": 2.0,
		"gatling2": 1.2, "cannon2": 1.8, "harpoon2": 2.0, "torpedo2": 2.2,
		"spray": 1.2, "lance": 1.8, "cluster": 2.2,
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
	for f3 in 12:
		await get_tree().physics_frame
	check(absf(wavy.global_position.y - straight.global_position.y) > 1.0,
		"蛇行弾が直進弾と同じ軌道(%.2f)" % absf(wavy.global_position.y - straight.global_position.y))
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
	check(not bool(Database.combat_mobs["carabos"].get("face_left", false)),
		"カーラボスの絵は右向き(頭が右)なので face_left は付けない")
	# 実際に左右へ動かしたとき、反転が絵の向きと噛み合うこと
	var pl2 := CharacterBody2D.new()
	pl2.add_to_group("player")
	add_child(pl2)
	for spec3 in [["lord", "kraken_lord", true], ["mob", "carabos", false]]:
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
	for mid3 in allowed:
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
		check(absf(float(fw.reload) - float(gat.reload) * 2.0) < 0.001, "%s のリロードがガトリングの2倍でない" % wid7)
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

	port.free()
	if failures.is_empty():
		print("MAINTENANCE_TEST_OK outer_isle/shop/tavern/reload/weapons/hints/undine/bossrush/king_escorts/legion_hitbox/king_range/siren_notes/wraith_lock/octopus_art/wraith_haze/sunny_sea/facing/killer_shell/south_isle/streams/all_islands/bullet_shapes")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
