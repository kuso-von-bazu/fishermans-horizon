extends Node
## #239: 新島3つ(星霜/常闇/海嘯)と、新モブ6種・新主6体の検証。
## 島を末尾に追加する設計のため、index に依存する箇所が壊れていないかを重点的に見る。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()

	# --- 島の定義 ---
	check(Database.islands.size() == 8, "島が8つでない(%d)" % Database.islands.size())
	var want_tier := {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 2, 6: 2, 7: 3}
	for idx in want_tier:
		check(Database.tier_of(int(idx)) == int(want_tier[idx]),
			"島%d の tier が %d でない(%d)" % [idx, want_tier[idx], Database.tier_of(int(idx))])
	# 既存の島indexが動いていないこと(動くと旧セーブが壊れる)
	check(str(Database.island(2).name) == "月下の島", "既存の島indexがずれている(2番=%s)" % Database.island(2).name)
	check(str(Database.island(3).name) == "嵐越えの島", "既存の島indexがずれている(3番=%s)" % Database.island(3).name)
	check(str(Database.island(4).name) == "果ての島", "既存の島indexがずれている(4番=%s)" % Database.island(4).name)
	check(str(Database.island(5).name) == "星霜の島", "5番が星霜の島でない")
	check(str(Database.island(6).name) == "常闇の島", "6番が常闇の島でない")
	check(str(Database.island(7).name) == "海嘯の島", "7番が海嘯の島でない")

	# 島数に連動する配列が8つぶんあること(足りないと先の島でクラッシュ/誤動作)
	check(Database.mob_weights.size() == 8, "mob_weights が8つでない(%d)" % Database.mob_weights.size())
	var Isle = preload("res://scripts2d/Island2D.gd")
	check(Isle.PALETTES.size() == 8, "島の配色が8つでない(%d)" % Isle.PALETTES.size())
	# 出現重みの合計がほぼ1(偏っていると特定の敵しか出ない)
	for i in Database.mob_weights.size():
		var sum := 0.0
		for k in Database.mob_weights[i]:
			sum += float(Database.mob_weights[i][k])
			check(Database.combat_mobs.has(str(k)), "島%d の出現表に未定義のモブ %s" % [i, str(k)])
		check(absf(sum - 1.0) < 0.02, "島%d の出現重み合計が1でない(%.3f)" % [i, sum])
	# 各島で実際に抽選できること
	for i in Database.islands.size():
		var got := Database.pick_mob(i)
		check(Database.combat_mobs.has(got), "島%d で抽選したモブが未定義(%s)" % [i, got])

	# --- 新モブ・新主の定義 ---
	for m in ["mermaid", "lamia", "zombie_fish", "moon_jelly", "killer_shell", "carabos"]:
		check(Database.combat_mobs.has(m), "モブ %s が未定義" % m)
		check(ResourceLoader.exists("res://assets/images/pixel/mob_%s.png" % m), "モブ %s のドット絵がない" % m)
	for l in ["undine", "siren", "night_emperor", "night_bat_medium", "night_bat_small", "wraith", "kraken_lord", "griffon"]:
		check(Database.lords.has(l), "主 %s が未定義" % l)
	# 島定義の lords が実在すること(タイプミスで主が出現しなくなる)
	for isle in Database.islands:
		for lid in isle.get("lords", []):
			check(Database.lords.has(str(lid)), "島 %s の主 %s が未定義" % [str(isle.name), str(lid)])
			check(int(Database.lords[str(lid)].island) == int(isle.id),
				"主 %s の island が所属島と食い違う" % str(lid))
	# 討伐記録に新モブが載っていること
	var listed := {}
	for e in Database.bestiary:
		listed[str(e.id)] = true
	for m2 in ["mermaid", "lamia", "zombie_fish", "moon_jelly", "killer_shell", "carabos"]:
		check(listed.has(m2), "討伐記録に %s が載っていない" % m2)

	# --- 名声要件(レビュアー指定の到達条件を満たすか) ---
	# tier0/1の主4体 + tier2の主のうち下位4体 で嵐越え/海嘯へ「あと少し」届く水準
	var t01 := 0
	var t2: Array = []
	var t3: Array = []
	for lid2 in Database.lords:
		var ld: Dictionary = Database.lords[lid2]
		var f := int(ld.get("fame", 0))
		if f <= 0:
			continue
		var tr := Database.tier_of(int(ld.island))
		if tr <= 1: t01 += f
		elif tr == 2: t2.append(f)
		elif tr == 3: t3.append(f)
	t2.sort()
	t3.sort()
	check(t2.size() == 6, "tier2の主が6体でない(%d)" % t2.size())
	check(t3.size() == 4, "tier3の主が4体でない(%d)" % t3.size())
	var low4 := 0
	for i in mini(4, t2.size()):
		low4 += int(t2[i])
	var low3 := 0
	for i in mini(3, t3.size()):
		low3 += int(t3[i])
	var storm_req := int(Database.island(3).fame_req)
	var end_req := int(Database.island(4).fame_req)
	# 主だけでは届かず(=海賊狩りが要る)、かつ現実的な差に収まっていること
	check(t01 + low4 < storm_req, "嵐越えが主4体だけで解放されてしまう(%d >= %d)" % [t01 + low4, storm_req])
	check(storm_req - (t01 + low4) <= 60, "嵐越えに必要な海賊狩りが多すぎる(あと%d)" % (storm_req - (t01 + low4)))
	check(t01 + low4 + low3 < end_req, "果てが主だけで解放されてしまう")
	check(end_req - (t01 + low4 + low3) <= 60, "果てに必要な海賊狩りが多すぎる(あと%d)" % (end_req - (t01 + low4 + low3)))
	check(int(Database.island(7).fame_req) == storm_req, "海嘯の名声要件が嵐越えと違う")
	check(int(Database.island(5).fame_req) == int(Database.island(2).fame_req), "星霜の名声要件が月下と違う")
	check(int(Database.island(6).fame_req) == int(Database.island(2).fame_req), "常闇の名声要件が月下と違う")

	# --- tier で判定していること(indexのままだと新島で誤動作する) ---
	GameState.current_island = 5   # 星霜(tier2) = 潮鳴りまでと同じ雇用条件
	check(GameState.hire_cost("veteran") == int(GameState.jobs["veteran"].hire),
		"星霜の島で契約金が3倍になっている(tier判定できていない)")
	check(GameState.max_fleet() == 3, "星霜の島の船団上限がtier基準でない(%d)" % GameState.max_fleet())
	GameState.current_island = 7   # 海嘯(tier3) = 嵐越えと同じ
	check(GameState.hire_cost("veteran") == int(GameState.jobs["veteran"].hire) * 3,
		"海嘯の島で契約金が3倍になっていない")
	check(GameState.max_fleet() == 4, "海嘯の島の船団上限がtier基準でない(%d)" % GameState.max_fleet())
	# 敵HPの海域倍率も tier で引くこと(星霜=月下と同じ、海嘯=嵐越えと同じ)
	check(Database.scaled_hp(1000.0, 5) == Database.scaled_hp(1000.0, 2), "星霜のHP倍率が月下と違う")
	check(Database.scaled_hp(1000.0, 7) == Database.scaled_hp(1000.0, 3), "海嘯のHP倍率が嵐越えと違う")
	GameState.current_island = 0

	# --- 天候(星霜=星の反射・月なし / 常闇=月なし / 海嘯=雨なし荒波) ---
	var World = preload("res://scripts2d/World2D.gd")
	var w := Node2D.new()
	w.set_script(World)
	var starry: Dictionary = w._weather_params("starry")
	var dark: Dictionary = w._weather_params("dark")
	var surge: Dictionary = w._weather_params("surge")
	var night: Dictionary = w._weather_params("night")
	var storm: Dictionary = w._weather_params("storm")
	check(float(night.moon) > 0.5, "月下の海面から月の反射が消えている")
	check(float(starry.night) > 0.5 and float(starry.moon) < 0.01 and float(starry.stars) > 0.5,
		"星霜: 夜+月なし+星ありになっていない")
	check(float(dark.night) > 0.5 and float(dark.moon) < 0.01 and float(dark.stars) < 0.01,
		"常闇: 夜+月なしになっていない")
	check(float(surge.rain) < 0.01 and float(surge.rough) > 0.5, "海嘯: 雨なし荒波になっていない")
	check(float(storm.rain) > 0.5, "嵐越えの雨が消えている")
	w.free()

	# --- 新しい挙動フラグが実際に読まれるか(定義漏れの検出) ---
	var Enemy = preload("res://scripts2d/Enemy2D.gd")
	check(Database.lords["undine"].get("no_melee", false), "ウンディーネが近接を試みる設定になっている")
	check(Database.lords["siren"].get("no_melee", false), "セイレーンが近接を試みる設定になっている")
	check(Database.lords["wraith"].get("no_melee", false), "レイスが近接を試みる設定になっている")
	check(Database.lords["wraith"].has("blink"), "レイスにテレポート設定がない")
	check(Database.lords["night_emperor"].get("split", {}).get("into", "") == "night_bat_medium", "夜の帝王の分裂先が中型でない")
	check(Database.lords["night_bat_medium"].get("split", {}).get("into", "") == "night_bat_small", "中型の分裂先が小型でない")
	check(not Database.lords["night_bat_small"].has("split"), "小型がさらに分裂する設定になっている")
	check(Database.lords["kraken_lord"].get("target_nearest", false), "オクトパスが最寄り船を狙わない")
	check(Database.lords["kraken_lord"].has("multi_melee"), "オクトパスの多段近接が未設定")
	check(Database.lords["griffon"].get("aerial", false), "グリフォンが空中でない")
	check(Database.combat_mobs["killer_shell"].get("stationary", false), "キラーシェルが移動する設定になっている")
	check(Database.combat_mobs["zombie_fish"].get("group", 0) >= 2, "ゾンビウオが群れで出ない")
	check(Database.combat_mobs["moon_jelly"].get("poison", false) and Database.combat_mobs["moon_jelly"].get("entangle", false),
		"ムーンジェリーの毒・鈍化が未設定")

	# 分裂個体は賞金・漁獲物を出さない(元の主でのみ受け取る)
	for sid in ["night_bat_medium", "night_bat_small"]:
		check(int(Database.lords[sid].get("bounty", 1)) == 0, "%s に賞金が設定されている(二重取得になる)" % sid)
		check(bool(Database.lords[sid].get("no_cargo", false)), "%s が魚倉を消費する設定になっている" % sid)

	# 実際に生成できること(setupで落ちないか)
	for spec in [["mob", "mermaid"], ["mob", "lamia"], ["mob", "zombie_fish"], ["mob", "moon_jelly"],
			["mob", "killer_shell"], ["mob", "carabos"], ["lord", "undine"], ["lord", "siren"],
			["lord", "night_emperor"], ["lord", "night_bat_medium"], ["lord", "night_bat_small"],
			["lord", "wraith"], ["lord", "kraken_lord"], ["lord", "griffon"]]:
		var e := CharacterBody2D.new()
		e.set_script(Enemy)
		e.setup(str(spec[0]), str(spec[1]))
		add_child(e)
		await get_tree().process_frame
		check(e.hp > 0.0, "%s の生成に失敗(HP=%.1f)" % [str(spec[1]), e.hp])
		e.free()

	# --- #202再3: 潮鳴り(tier1)以降の敵HPを一律2%引き上げ。始まりの島は据え置き ---
	var base_mult := [1.0, 1.5, 1.9, 2.7, 3.3]   # 引き上げ前の値
	check(is_equal_approx(Database.HP_TIER_MULT[0], 1.0), "始まりの島のHP倍率が変わっている")
	for t in range(1, 5):
		# #202再3(+2%)と再4(+3%)の累計 = 1.02 * 1.03
		var want: float = float(base_mult[t]) * 1.02 * 1.03
		check(absf(float(Database.HP_TIER_MULT[t]) - want) < 0.0005,
			"tier%d のHP倍率が累計引き上げ後の値でない(%.5f / 期待%.5f)" % [t, Database.HP_TIER_MULT[t], want])

	# --- #239再2: 航路の並び(海嘯 → 嵐越え の順) ---
	var order2: Array = []
	for isle3 in Database.islands_in_order():
		order2.append(str(isle3.name))
	check(order2 == ["始まりの島", "潮鳴りの島", "月下の島", "星霜の島", "常闇の島", "海嘯の島", "嵐越えの島", "果ての島"],
		"航路の並びが指定と違う: %s" % str(order2))

	# --- #242: 武器の説明文 ---
	check(not str(Database.weapons["gatling"].desc).contains("#63"), "ガトリングの説明に #63 が残っている")
	check(str(Database.weapons["harpoon"].desc) == "中威力。生物にデバフ付与", "銛の説明が指定と違う: %s" % Database.weapons["harpoon"].desc)

	# --- #209再9: ボスラッシュの構成 ---
	var World2 = preload("res://scripts2d/World2D.gd")
	var want_order := ["sawshark", "dumbo", "whale", "walrus", "aspidochelone", "undine",
		"night_emperor", "legion", "siren", "wraith", "king", "kraken_lord",
		"hydra", "griffon", "quetzal", "ghost", "leviathan"]
	var got_order: Array = []
	for spec in World2.BOSS_RUSH_ORDER:
		got_order.append(str(spec.id))
	check(got_order == want_order, "ボスラッシュの出現順が指定と違う: %s" % str(got_order))
	check(World2.BOSS_RUSH_ORDER.size() == 17, "ボスラッシュのボス数が17でない(%d)" % World2.BOSS_RUSH_ORDER.size())
	# 海賊王の取り巻きは 大×1・中×1 で固定
	for spec2 in World2.BOSS_RUSH_ORDER:
		if str(spec2.id) == "king":
			check((spec2.get("escorts", []) as Array) == ["dread", "corsair"],
				"海賊王の取り巻きが 大×1・中×1 でない")
	# ⑩まで5%、⑪から10%
	check(World2.BR_HEAL_BIG_FROM == 10, "回復量が10%%に切り替わる位置が⑪でない(index %d)" % World2.BR_HEAL_BIG_FROM)
	# 登場する主・海賊がすべて定義済みであること(タイプミスで出現しなくなる)
	for spec3 in World2.BOSS_RUSH_ORDER:
		if str(spec3.kind) == "lord":
			check(Database.lords.has(str(spec3.id)), "ボスラッシュの主 %s が未定義" % str(spec3.id))
		else:
			check(Database.pirates.has(str(spec3.id)), "ボスラッシュの海賊 %s が未定義" % str(spec3.id))

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK islands/tier/mobs/lords/fame/weather/behaviours/hp2pct/order/weapons/bossrush")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
