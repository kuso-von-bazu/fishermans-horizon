extends Node
## #265再8: 「真の海の王者」のように複数ステータスにまたがるバフを選択すると、
## 「選択中のバフ: ○○(A、B、C...)」の1行が折り返し無しのLabelで長大化し、
## 実績メニューに横スクロールが出ていた(過去の確認は"fame_max"=単一バフの選択でしか
## 撮影しておらず、複数バフの選択状態を撮っていなかったため見逃していた)。
## 折り返しを有効にして、選んだバフの内容によらず横幅が広がらないことを確認する。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# 「真の海の王者」は7ステータスにまたがるバフを持つ(最も長くなるケース)
	var ruler := Database.achievement("true_sea_ruler")
	check(not ruler.is_empty(), "真の海の王者が定義されていない")
	check(int(ruler.get("buff", {}).size()) >= 5, "真の海の王者のバフが想定より少ない(テストの前提が崩れている)")

	var old_achieved: Dictionary = GameState.achieved.duplicate(true)
	var old_badge := GameState.badge_id
	GameState.achieved["true_sea_ruler"] = true
	GameState.badge_id = "true_sea_ruler"

	var PortUIScript = preload("res://scripts/PortUI.gd")
	var ui = PortUIScript.new()
	add_child(ui)
	await get_tree().process_frame
	ui.open()
	ui.show_achievements()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var scroll: ScrollContainer = ui._scroll
	var hbar := scroll.get_h_scroll_bar()
	check(not hbar.visible, "複数ステータスのバフを選択すると実績メニューに横スクロールが出る")
	check(ui.content.get_combined_minimum_size().x <= scroll.size.x + 1.0,
		"実績メニューの内容幅(%.0f)がスクロール枠(%.0f)を超えている" % [ui.content.get_combined_minimum_size().x, scroll.size.x])

	ui.queue_free()
	GameState.achieved = old_achieved
	GameState.badge_id = old_badge

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_265_multi_buff_no_hscroll")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
