extends Node
## #285: 果ての島(最終島)に到達した後は「次の島」の概念が無いため、
## 燃料が半分を切った際の通知/強制帰還メッセージを出さないようにする。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	check(str(Database.island(4).name) == "果ての島", "island(4)が果ての島でない(テストの前提が崩れている)")

	var src := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	var half_i := src.find("elif GameState.run_food <= GameState.max_food() * 0.5:")
	check(half_i >= 0, "燃料半分の判定(elif)が見つからない")
	var guard_i := src.find("Database.island(GameState.current_island).name != \"果ての島\"", half_i)
	check(guard_i > half_i, "燃料半分判定の直後に果ての島の除外ガードが無い")
	# ガードの内側に、従来の「次の島へ行けるか」判定と強制帰還の両方が包まれていること
	var onward_i := src.find("_can_voyage_onward() and _has_onward_island()", guard_i)
	var forced_i := src.find("燃料が半分を切った", guard_i)
	check(onward_i > guard_i and onward_i < forced_i, "ガードの内側に食料選択ダイアログの判定が無い")
	check(forced_i > guard_i, "ガードの内側に強制帰還メッセージが無い")

	# 燃料切れ(0)の強制帰還は果ての島でも従来通り出ること(このガードの対象外)
	var empty_i := src.find("燃料が尽きた! 直近の島へ強制帰還")
	check(empty_i >= 0 and empty_i < half_i, "燃料切れ(0)の強制帰還が燃料半分の判定より前に無い(=果ての島ガードの影響を受けていない)")

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_285_no_half_fuel_at_final_island")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
