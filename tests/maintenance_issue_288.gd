extends Node
## #288: ボスラッシュの装甲回復量。
## #288再: 段階固定(5/10/15%)をやめ、ボスごとの個別指定になった。
##   ①〜④=5% / ⑤〜⑦=6% / ⑧〜⑩=8% / ⑪=10% / ⑫=12% / ⑬=14% / ⑭=16% /
##   ⑮=17% / ⑯=18% / ⑰=19% / ⑱=20%
##   ⑲レヴィアタンは撃破でクリアなので回復しない。
##
## 以前のテストは判定式をテスト側に写して確かめており、実装を見ていなかった。
## ここでは World2D の表そのものを読む。

const World2 = preload("res://scripts2d/World2D.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	# 倒したボスの通し番号 -> 回復率(ご指定の値)
	# #288再2: 雪夜の主(⑯ジェミニ・⑰死神)の追加で⑮以降が変わった
	var want := {
		1: 0.05, 2: 0.05, 3: 0.05, 4: 0.05,
		5: 0.06, 6: 0.06, 7: 0.06,
		8: 0.08, 9: 0.08, 10: 0.08,
		11: 0.10, 12: 0.12, 13: 0.14, 14: 0.16,
		15: 0.17, 16: 0.18, 17: 0.19, 18: 0.20,
	}
	check(World2.BR_HEAL_PCT.size() == want.size(),
		"回復量の表の件数が%dでない(%d)" % [want.size(), World2.BR_HEAL_PCT.size()])
	for n in want:
		var idx: int = int(n) - 1
		if idx < 0 or idx >= World2.BR_HEAL_PCT.size():
			check(false, "%d体目の回復量が表に無い" % int(n))
			continue
		var got: float = float(World2.BR_HEAL_PCT[idx])
		check(is_equal_approx(got, float(want[n])),
			"%d体目撃破後の回復量が%.0f%%でない(%.0f%%)" % [int(n), float(want[n]) * 100.0, got * 100.0])

	# ⑰レヴィアタンは表に入れない(撃破=クリアで回復しない)
	check(World2.BR_HEAL_PCT.size() == World2.BOSS_RUSH_ORDER.size() - 1,
		"レヴィアタンの分まで回復量の表に入っている")

	# ボスの並びがご指定どおりであること(回復率は通し番号で引くので、並びが崩れると全部ずれる)
	# #288再2: ⑯ジェミニ・⑰死神を追加(幽霊船・レヴィアタンは1つずつ後ろへ)
	var order := ["sawshark", "dumbo", "whale", "walrus", "aspidochelone", "undine",
		"night_emperor", "legion", "siren", "wraith", "king", "kraken_lord",
		"hydra", "griffon", "quetzal", "gemini", "reaper", "ghost", "leviathan"]
	check(World2.BOSS_RUSH_ORDER.size() == order.size(),
		"ボスの数が%dでない(%d)" % [order.size(), World2.BOSS_RUSH_ORDER.size()])
	for i in mini(order.size(), World2.BOSS_RUSH_ORDER.size()):
		var spec: Dictionary = World2.BOSS_RUSH_ORDER[i]
		check(str(spec.id) == order[i],
			"%d体目のボスが %s でない(%s)" % [i + 1, order[i], str(spec.id)])

	# ⑪海賊王の取り巻きは 海賊(大)×1・海賊(中)×1 で固定
	var king: Dictionary = World2.BOSS_RUSH_ORDER[10]
	var esc: Array = king.get("escorts", [])
	check(esc.size() == 2, "海賊王の取り巻きが2隻でない(%d隻)" % esc.size())
	check(esc.count("dread") == 1, "海賊王の取り巻きに海賊(大)が1隻でない(%d隻)" % esc.count("dread"))
	check(esc.count("corsair") == 1, "海賊王の取り巻きに海賊(中)が1隻でない(%d隻)" % esc.count("corsair"))

	# GameState.heal_fleet_percent が実際に指定割合だけ回復させること
	if not GameState.load_game():
		GameState.fleet = [{"kind": "start", "armor": 0}]
	var mx := float(GameState.max_armor_of(0))
	for pct in [0.06, 0.12, 0.20]:
		GameState.fleet[0]["armor"] = 0.0
		GameState.heal_fleet_percent(float(pct))
		var healed := float(GameState.fleet[0]["armor"])
		check(absf(healed - mx * float(pct)) < 0.01,
			"heal_fleet_percent(%.2f)の回復量が最大装甲の%.0f%%でない(got %f, want %f)"
				% [float(pct), float(pct) * 100.0, healed, mx * float(pct)])

	# ---------------- #248再: 北の孤島の造船所に軽/重フリゲートを追加 ----------------
	var north := 8   # 北の孤島
	check(str(Database.island(north).name).contains("北"),
		"島%dが北の孤島でない(%s)" % [north, str(Database.island(north).name)])
	for sid in ["corvette", "hunter_h", "hauler", "frigate_l", "frigate_h"]:
		check(Database.shop_has_ship(north, str(sid)),
			"北の孤島で %s が買えない" % str(sid))
	# 追加指定の無い船まで並ばないこと(ラインナップを絞る意図は保つ)
	for sid2 in ["cruiser", "dread", "raft"]:
		check(not Database.shop_has_ship(north, str(sid2)),
			"北の孤島で %s まで売られている" % str(sid2))

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_288/heal_table/boss_order/king_escorts/north_isle_ships")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
