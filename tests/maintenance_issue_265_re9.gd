extends Node
## #265再9: 「真の海の王者」の実績を選択/解除すると、上の「選択中のバフ」行の
## 折り返し行数が変わり、それより下の行がすべてずれて実績メニューが上下に
## スクロールしたように見えていた。押した行がビューポート内で同じ位置に
## 留まるよう、再構築後にスクロール量を補正したことを確認する。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _btn_of(r: Control) -> Button:
	for c in r.get_children():
		if c is Button:
			return c
	return null

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var old_achieved: Dictionary = GameState.achieved.duplicate(true)
	var old_badge := GameState.badge_id
	# 実績メニューを実際にスクロールさせるため、いくつも達成済みにしておく
	GameState.achieved = {}
	for a in Database.achievements:
		GameState.achieved[str(a.id)] = true
	GameState.badge_id = ""

	var PortUIScript = preload("res://scripts/PortUI.gd")
	var ui = PortUIScript.new()
	add_child(ui)
	await get_tree().process_frame
	ui.open()
	ui.show_achievements()
	await get_tree().process_frame
	await get_tree().process_frame

	check(ui._ach_rows.has("true_sea_ruler"), "「真の海の王者」の行が見つからない(テストの前提が崩れている)")
	var scroll: ScrollContainer = ui._scroll
	var max_v: float = maxf(0.0, ui.content.get_combined_minimum_size().y - scroll.size.y)
	check(max_v > 40.0, "実績メニューがスクロールするほど長くなっていない(テストの前提が崩れている)")

	# 「真の海の王者」の行が見える位置までスクロールしておく
	var row: Control = ui._ach_rows["true_sea_ruler"]
	scroll.scroll_vertical = int(clampf(row.position.y - 100.0, 0.0, max_v))
	await get_tree().process_frame

	var btn := _btn_of(row)
	check(btn != null, "「真の海の王者」の選択ボタンが見つからない")

	# ---- 選択: ボタンを押しても、その行のビューポート内の位置が変わらないこと ----
	var before_y: float = row.position.y - scroll.scroll_vertical
	btn.pressed.emit()
	for i in 6:
		await get_tree().process_frame

	check(GameState.badge_id == "true_sea_ruler", "「真の海の王者」が選択されていない")
	check(ui._ach_rows.has("true_sea_ruler"), "選択後に行の参照が失われている")
	var row2: Control = ui._ach_rows["true_sea_ruler"]
	var after_y: float = row2.position.y - scroll.scroll_vertical
	check(absf(after_y - before_y) <= 2.0,
		"選択すると行の見た目の位置がずれる(選択前%.1f→選択後%.1f)" % [before_y, after_y])

	# ---- 解除: 同様に位置が変わらないこと ----
	var btn2 := _btn_of(row2)
	check(btn2 != null, "選択後の「選択を解除」ボタンが見つからない")
	var before_y2: float = row2.position.y - scroll.scroll_vertical
	btn2.pressed.emit()
	for i in 6:
		await get_tree().process_frame

	check(GameState.badge_id == "", "「真の海の王者」の選択が解除されていない")
	var row3: Control = ui._ach_rows["true_sea_ruler"]
	var after_y2: float = row3.position.y - scroll.scroll_vertical
	check(absf(after_y2 - before_y2) <= 2.0,
		"解除すると行の見た目の位置がずれる(解除前%.1f→解除後%.1f)" % [before_y2, after_y2])

	ui.queue_free()
	GameState.achieved = old_achieved
	GameState.badge_id = old_badge

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_265_re9_ach_scroll_stable")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
