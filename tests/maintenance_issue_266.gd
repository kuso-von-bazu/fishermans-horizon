extends Node
## #266再2: 魚倉(hold)を共有者指定値に再調整。大型運搬艦は据え置き。巨大戦艦の価格を12万に引き上げ。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	var expect_hold := {
		"raft": 14, "skiff": 24, "cutter": 26, "corvette": 28, "hunter_h": 30,
		"hauler": 70, "frigate_l": 30, "frigate_h": 30, "cruiser": 30, "dread": 30,
	}
	for sid in expect_hold:
		var s: Dictionary = Database.ships[sid]
		check(int(s.hold) == int(expect_hold[sid]),
			"%s の魚倉が%dでない(実際%d)" % [sid, int(expect_hold[sid]), int(s.hold)])

	check(int(Database.ships["dread"].price) == 120000, "巨大戦艦の価格が120000でない(実際%d)" % int(Database.ships["dread"].price))

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_266_hold_price")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
