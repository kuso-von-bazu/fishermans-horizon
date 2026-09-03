extends Node
## #265再11: 錦衣玉食の達成条件を資金500000到達→資金1000000到達に引き上げる。
## 説明文と実際の判定閾値の両方が1000000になっていることを確認する。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	var a = Database.achievement("rich")
	check(a != null, "「錦衣玉食」の実績データが見つからない")
	if a:
		check(a.desc.find("1000000") != -1, "説明文が資金1000000到達になっていない(%s)" % a.desc)
		check(a.desc.find("500000") == -1, "説明文に旧しきい値500000が残っている(%s)" % a.desc)

	var old_money: int = GameState.money
	var old_achieved: Dictionary = GameState.achieved.duplicate(true)
	GameState.achieved.erase("rich")

	GameState.money = 999999
	check(not GameState._achievement_met(a), "資金999999で「錦衣玉食」が達成してしまっている")

	GameState.money = 1000000
	check(GameState._achievement_met(a), "資金1000000で「錦衣玉食」が達成していない")

	GameState.money = old_money
	GameState.achieved = old_achieved

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_265_re11_rich_threshold_1000000")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
