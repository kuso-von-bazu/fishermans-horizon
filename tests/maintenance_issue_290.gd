extends Node
## #290: 雪夜の島(island 10)と、その近海の主(ジェミニ・死神)の追加。

const World2 = preload("res://scripts2d/World2D.gd")
const Isle = preload("res://scripts2d/Island2D.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	var N := 10   # 雪夜の島

	# ---------------- 島そのもの ----------------
	var d: Dictionary = Database.island(N)
	check(str(d.name) == "雪夜の島", "島%dが雪夜の島でない(%s)" % [N, str(d.name)])
	check(int(d.tier) == 4, "雪夜の島のtierが4でない(%d)" % int(d.tier))
	check(str(d.weather) == "snownight", "雪夜の島の近海の天候が snownight でない")
	# 位置: 嵐越えの島(3)の北東。北=-Z / 東=+X
	var p3: Vector3 = Database.island(3).pos
	var p10: Vector3 = d.pos
	check(p10.x > p3.x, "雪夜の島が嵐越えの島より東でない")
	check(p10.z < p3.z, "雪夜の島が嵐越えの島より北でない")
	# 果ての島・北の孤島は雪夜の島の追加にあわせて北東へ動かした
	var p4: Vector3 = Database.island(4).pos
	var p8: Vector3 = Database.island(8).pos
	check(p4.x > p10.x, "果ての島が雪夜の島より東でない(奥に移動していない)")
	check(p8.x > p10.x, "北の孤島が雪夜の島より東でない")
	# 名声: 果ての島は引き上げ、北の孤島は据え置き
	check(int(d.fame_req) == 400, "雪夜の島の必要名声が400でない(%d)" % int(d.fame_req))
	check(int(Database.island(4).fame_req) == 480,
		"果ての島の必要名声が引き上がっていない(%d)" % int(Database.island(4).fame_req))
	check(int(Database.island(8).fame_req) == 400,
		"北の孤島の必要名声が据え置きでない(%d)" % int(Database.island(8).fame_req))
	check(int(Database.island(4).fame_req) > int(d.fame_req),
		"雪夜の島より果ての島が先に解放されてしまう")

	# 島数に連動する配列がすべて11個ぶんあること(足りないと先の島でクラッシュ/誤動作)
	check(Database.islands.size() == 11, "島が11でない(%d)" % Database.islands.size())
	check(Database.mob_weights.size() == 11, "mob_weights が11でない(%d)" % Database.mob_weights.size())
	check(Isle.PALETTES.size() == 11, "島の配色が11でない(%d)" % Isle.PALETTES.size())
	var osrc := FileAccess.get_file_as_string("res://shaders/ocean2d.gdshader")
	for u in ["islands[11]", "island_r[11]", "island_wob[11]", "island_seed[11]"]:
		check(osrc.contains(u), "海のシェーダの配列長が11でない: %s" % u)
	var wsrc := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	check(wsrc.contains('mini(Database.islands.size(), 11)'), "シェーダへ渡す島数が10のまま")
	check(wsrc.contains("9, 7, 8, 7][clampi(GameState.current_island, 0, 10)]"),
		"障害物の数の表が11島ぶんになっていない")

	# ---------------- 近海の内容 ----------------
	# 戦闘能力があるモブ(ご指定の5種のみ)
	var want_mobs := ["mermaid", "lamia", "moon_jelly", "killer_shell", "amphiptere"]
	var got_mobs: Array = Database.mob_weights[N].keys()
	got_mobs.sort()
	var exp_mobs := want_mobs.duplicate()
	exp_mobs.sort()
	check(got_mobs == exp_mobs, "雪夜の島の出現モブが指定と違う: %s" % str(got_mobs))
	# 戦闘能力がないモブ(イカ・アンコウ・アナゴ)
	var want_fish := ["squid", "anglerfish", "conger"]
	var got_fish: Array = (d.get("spawn", []) as Array).duplicate()
	got_fish.sort()
	want_fish.sort()
	check(got_fish == want_fish, "雪夜の島の漁獲対象が指定と違う: %s" % str(got_fish))

	# 造船所: 船はご指定の5隻のみ、武器は果ての島と同じ
	for sid in ["corvette", "hunter_h", "hauler", "frigate_l", "frigate_h"]:
		check(Database.shop_has_ship(N, sid), "雪夜の島で %s が買えない" % sid)
	for sid2 in ["cruiser", "dread", "raft", "skiff"]:
		check(not Database.shop_has_ship(N, sid2), "雪夜の島で %s まで売られている" % sid2)
	for wid in Database.weapons:
		check(Database.shop_has_weapon(N, str(wid)) == Database.shop_has_weapon(4, str(wid)),
			"雪夜の島の武器ラインナップが果ての島と違う: %s" % str(wid))

	# 出港ヒント(全島にあることを別テストが要求している)
	check(not (Database.departure_hint_table(N).get("random", []) as Array).is_empty(),
		"雪夜の島に出港ヒントが無い")

	# 航海BGMは月下・星霜・常闇と同じ「夜」
	check(World2.NIGHT_SEA_WEATHERS.has("snownight"),
		"雪夜の島の近海が夜の航海BGMの対象になっていない")

	# ---------------- 近海の主 ----------------
	check((d.get("lords", []) as Array) == ["gemini", "reaper"], "雪夜の島の主が指定と違う")
	for lid in ["gemini", "reaper"]:
		var ld: Dictionary = Database.lords[lid]
		check(int(ld.island) == N, "%s の所属島が雪夜の島でない" % lid)
		check(str(ld.get("lore", "")) != "", "%s の説明文が無い" % lid)

	# ジェミニ: 2体同時に出て両方倒すまで討伐にならない / 全方位20way / 打ち返し / 近接なし
	var gm: Dictionary = Database.lords["gemini"]
	check(bool(gm.get("pair", false)), "ジェミニが2体同時出現(pair)でない")
	check(bool(gm.get("radial", false)) and int(gm.get("radial_count", 0)) == 20,
		"ジェミニの全方位弾が20wayでない(%d)" % int(gm.get("radial_count", 0)))
	check(bool(gm.get("small_shot", false)), "ジェミニの弾が米粒型でない")
	check(float(gm.get("counter_shot", 0.0)) > 0.0, "ジェミニが打ち返し弾を撃たない")
	check(bool(gm.get("no_melee", false)), "ジェミニが近接攻撃をしてしまう")
	check(str(gm.lore) == "堕天した双子の天使。", "ジェミニの説明文が指定と違う")

	# 死神: 瞬間移動先が近接圏 / 通常の遠隔攻撃を持たない
	var rp: Dictionary = Database.lords["reaper"]
	check(rp.has("blink"), "死神が瞬間移動しない")
	var bd: Array = (rp.blink as Dictionary).get("dist", [999.0, 999.0])
	var wd: Array = (Database.lords["wraith"].blink as Dictionary).get("dist", [0.0, 0.0])
	check(float(bd[1]) < float(wd[0]),
		"死神の瞬間移動先がレイスより近くない(近接圏に来ない): %s" % str(bd))
	check(bool(rp.get("melee_only", false)), "死神が通常の遠隔攻撃を持ってしまっている")
	check(str(rp.lore) == "船乗りに死を運ぶ使者。", "死神の説明文が指定と違う")
	var esrc := FileAccess.get_file_as_string("res://scripts2d/Enemy2D.gd")
	check(esrc.contains('elif id == "reaper" and dist <= melee_r:'), "死神の大鎌の処理が無い")
	check(esrc.contains("_sweep_away_shots(melee_r)"), "大鎌がこちらの弾を払い落とさない")
	check(esrc.contains("var reap_n := 10"), "大鎌の斬撃から撃つ弾が10発でない")

	# 取り巻き(ジェミニ=ティアマット+ダゴン / 死神=ザッハーク+ダゴン)
	check(wsrc.contains('elif lord_id == "gemini":') and wsrc.contains('["tiamat", "dagon"]'),
		"ジェミニの取り巻きが指定と違う")
	check(wsrc.contains('elif lord_id == "reaper":') and wsrc.contains('["zahhak", "dagon"]'),
		"死神の取り巻きが指定と違う")

	# 絵(横向きは未生成のため保留。正面/背面はできていること)
	for suf in ["_front", "_back"]:
		check(ResourceLoader.exists("res://assets/images/pixel/lord_gemini%s.png" % suf),
			"ジェミニの%sの絵が無い" % suf)
	for suf2 in ["", "_front", "_back"]:
		check(ResourceLoader.exists("res://assets/images/pixel/lord_reaper%s.png" % suf2),
			"死神の%sの絵が無い" % suf2)

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_290/island/sea/shop/lords/escorts/art")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
