extends Node
## #292/#291/#265再13/#288再2: 「始めから」での実績リセット、航路メニューの文言、
## 雪夜の島の主の実績とボスラッシュへの追加。

const World2 = preload("res://scripts2d/World2D.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	# ---------------- #292: 「始めから」で主討伐の実績が残らない ----------------
	# 実績はセーブと別ファイルに持つため、何もしないと前のデータの分が残っていた。
	GameState.achieved = {}
	GameState.badge_id = ""
	var lord_ids: Array = []
	for a in Database.achievements:
		if str(a.get("check", "")) == "lord":
			lord_ids.append(str(a.id))
	check(lord_ids.size() >= 18, "主討伐の実績が18件未満(%d)" % lord_ids.size())
	# 全実績を達成済みにしてから「始めから」相当の処理を通す
	for a2 in Database.achievements:
		GameState.achieved[str(a2.id)] = true
	GameState.badge_id = str(lord_ids[0])
	GameState.reset_lord_achievements()
	for lid in lord_ids:
		check(not GameState.is_achieved(lid), "%s が達成済みのまま残っている" % lid)
	# 他のすべてが条件の実績も、条件を満たさなくなるので外れること
	for a3 in Database.achievements:
		if str(a3.get("check", "")) == "all":
			check(not GameState.is_achieved(str(a3.id)),
				"%s が達成済みのまま残っている(主の実績が外れたのに)" % str(a3.id))
	# 主討伐と無関係な実績は残ること(まとめて消していないこと)
	check(GameState.is_achieved("kill_narwhal"), "討伐数の実績まで消えている")
	check(GameState.is_achieved("true_sea_ruler"), "ボスラッシュの実績まで消えている")
	# 外した実績をバッヂに選んでいたら、その選択も外れること
	check(GameState.badge_id == "", "外した実績がバッヂに選ばれたまま(%s)" % GameState.badge_id)
	# もう一度倒せば達成し直せること
	GameState.defeated_lords = ["sawshark"]
	GameState.check_achievements()
	check(GameState.is_achieved("lord_sawshark"), "倒し直しても実績が達成されない")

	# 「始めから」の経路がこの処理を通ること
	var wsrc := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	var hs := wsrc.find("func _on_title_start")
	check(hs != -1, "_on_title_start が見つからない")
	if hs != -1:
		var he := wsrc.find("\nfunc ", hs)
		var body: String = wsrc.substr(hs, (he - hs) if he != -1 else 1200)
		check(body.contains("GameState.reset_lord_achievements()"),
			"「始めから」で主討伐の実績を戻していない")
		check(body.contains("GameState.reset_all()"),
			"「始めから」で状態を初期化していない")

	# ---------------- #291: 航路メニューの案内を1行目に続ける ----------------
	var psrc := FileAccess.get_file_as_string("res://scripts/PortUI.gd")
	check(psrc.contains("自力で航行してください。名声は近海の主を討伐したり、海賊を撃退することで稼ぐことができます。"),
		"航路メニューの名声の案内が1行目に続いていない")
	check(not psrc.contains('content.add_child(_p("名声は近海の主を討伐したり'),
		"名声の案内が別行として残っている")

	# ---------------- #265再13: ジェミニ狩り・死神狩り ----------------
	var ids: Array = []
	for a4 in Database.achievements:
		ids.append(str(a4.id))
	for want in ["lord_gemini", "lord_reaper"]:
		check(ids.has(want), "実績 %s が無い" % want)
	if ids.has("lord_gemini") and ids.has("lord_reaper") and ids.has("lord_quetzal") and ids.has("lord_ghost"):
		# 並びはケツァルコアトル狩りと幽霊船狩りの間
		check(ids.find("lord_quetzal") < ids.find("lord_gemini")
			and ids.find("lord_gemini") < ids.find("lord_reaper")
			and ids.find("lord_reaper") < ids.find("lord_ghost"),
			"ジェミニ狩り・死神狩りの並びがケツァルと幽霊船の間でない")
	for aid2 in ["lord_gemini", "lord_reaper"]:
		var ad: Dictionary = Database.achievement(aid2)
		check(str(ad.get("check", "")) == "lord", "%s の判定が主の討伐でない" % aid2)
		check(ResourceLoader.exists(str(ad.get("icon", ""))), "%s のバッヂ絵が無い" % aid2)
		# バフはケツァル(0.9891 / 幽霊船0.9885)の間に収まり、既存の値を動かしていないこと
		check((ad.buff as Dictionary).size() == 1, "%s のバフが1種類でない" % aid2)
	check(is_equal_approx(float(Database.achievement("lord_quetzal").buff.fleet_dmg_taken), 0.9891),
		"ケツァルコアトル狩りのバフが変わっている")
	check(is_equal_approx(float(Database.achievement("lord_ghost").buff.reload), 0.9885),
		"幽霊船狩りのバフが変わっている")
	# アルティメットプレーヤーは「他のすべて」なので、追加分も自動で条件に入る
	GameState.achieved = {}
	for a5 in Database.achievements:
		if str(a5.get("check", "")) != "all":
			GameState.achieved[str(a5.id)] = true
	GameState.achieved.erase("lord_gemini")
	var ult := ""
	for a6 in Database.achievements:
		if str(a6.get("check", "")) == "all":
			ult = str(a6.id)
	check(ult != "", "アルティメットプレーヤーが見つからない")
	check(not GameState._achievement_met(Database.achievement(ult)),
		"ジェミニ狩りが未達成なのにアルティメットプレーヤーを達成できる")
	GameState.achieved["lord_gemini"] = true
	check(GameState._achievement_met(Database.achievement(ult)),
		"すべて達成してもアルティメットプレーヤーにならない")

	# ---------------- #288再2: ボスラッシュに⑯⑰を追加 ----------------
	var order := ["sawshark", "dumbo", "whale", "walrus", "aspidochelone", "undine",
		"night_emperor", "legion", "siren", "wraith", "king", "kraken_lord",
		"hydra", "griffon", "quetzal", "gemini", "reaper", "ghost", "leviathan"]
	check(World2.BOSS_RUSH_ORDER.size() == order.size(),
		"ボスの数が%dでない(%d)" % [order.size(), World2.BOSS_RUSH_ORDER.size()])
	for i in mini(order.size(), World2.BOSS_RUSH_ORDER.size()):
		check(str(World2.BOSS_RUSH_ORDER[i].id) == order[i],
			"%d体目のボスが %s でない(%s)" % [i + 1, order[i], str(World2.BOSS_RUSH_ORDER[i].id)])
	# 回復量(ご指定の値)
	var want := {
		1: 0.05, 2: 0.05, 3: 0.05, 4: 0.05,
		5: 0.06, 6: 0.06, 7: 0.06,
		8: 0.08, 9: 0.08, 10: 0.08,
		11: 0.10, 12: 0.12, 13: 0.14, 14: 0.16,
		15: 0.17, 16: 0.18, 17: 0.19, 18: 0.20,
	}
	check(World2.BR_HEAL_PCT.size() == want.size(),
		"回復量の表が%d件でない(%d)" % [want.size(), World2.BR_HEAL_PCT.size()])
	for n in want:
		var idx: int = int(n) - 1
		if idx < 0 or idx >= World2.BR_HEAL_PCT.size():
			check(false, "%d体目の回復量が表に無い" % int(n))
			continue
		check(is_equal_approx(float(World2.BR_HEAL_PCT[idx]), float(want[n])),
			"%d体目撃破後の回復量が%.0f%%でない(%.0f%%)"
				% [int(n), float(want[n]) * 100.0, float(World2.BR_HEAL_PCT[idx]) * 100.0])
	# ⑲レヴィアタンは撃破でクリアなので表に入れない
	check(World2.BR_HEAL_PCT.size() == World2.BOSS_RUSH_ORDER.size() - 1,
		"レヴィアタンの分まで回復量の表に入っている")
	# ⑪海賊王の取り巻きは 大×1・中×1 のまま
	var king: Dictionary = World2.BOSS_RUSH_ORDER[10]
	check((king.get("escorts", []) as Array) == ["dread", "corsair"],
		"海賊王の取り巻きが 大×1・中×1 でない")

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_292/route_text/new_lord_achievements/boss_rush_new")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
