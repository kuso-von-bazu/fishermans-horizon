extends Node
## #288: ボスラッシュの装甲回復量を3段階に変更。
## ①〜④=5%、⑤〜⑩=10%、⑪〜⑯=15%回復する(_br_indexは撃破数=1始まり)。

const World2 = preload("res://scripts2d/World2D.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _heal_pct_for(idx: int) -> float:
	if idx >= World2.BR_HEAL_BIG_FROM:
		return 0.15
	elif idx >= World2.BR_HEAL_MID_FROM:
		return 0.10
	else:
		return 0.05

func _ready() -> void:
	await get_tree().process_frame

	check(World2.BR_HEAL_MID_FROM == 5, "10%%に切り替わる位置が⑤でない(%d)" % World2.BR_HEAL_MID_FROM)
	check(World2.BR_HEAL_BIG_FROM == 11, "15%%に切り替わる位置が⑪でない(%d)" % World2.BR_HEAL_BIG_FROM)

	# ①〜④(index 1..4) = 5%
	for i in range(1, 5):
		check(_heal_pct_for(i) == 0.05, "%d体目撃破後の回復量が5%%でない" % i)
	# ⑤〜⑩(index 5..10) = 10%
	for i in range(5, 11):
		check(_heal_pct_for(i) == 0.10, "%d体目撃破後の回復量が10%%でない" % i)
	# ⑪〜⑯(index 11..16) = 15%
	for i in range(11, 17):
		check(_heal_pct_for(i) == 0.15, "%d体目撃破後の回復量が15%%でない" % i)

	# GameState.heal_fleet_percent が実際に指定割合だけ回復させることを確認
	if not GameState.load_game():
		GameState.fleet = [{"kind": "start", "armor": 0}]
	var mx := float(GameState.max_armor_of(0))
	GameState.fleet[0]["armor"] = 0.0
	GameState.heal_fleet_percent(0.15)
	var healed := float(GameState.fleet[0]["armor"])
	check(absf(healed - mx * 0.15) < 0.01, "heal_fleet_percent(0.15)の回復量が最大装甲の15%%でない(got %f, want %f)" % [healed, mx * 0.15])

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_288")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
