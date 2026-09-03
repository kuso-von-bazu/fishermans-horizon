extends Node
## #265再10: 「真の海の王者」の実績を選択すると、スクロール量の補正が
## 反映されるまでの数フレーム、古いスクロール位置のまま新しい(ずれた)
## レイアウトが一瞬描画され、それが高速な上下スクロールに見えていた。
## 補正が終わるまでスクロール領域自体を透明にして、そのジャンプを
## 画面に出さないようにしたことを確認する。

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
	check(is_equal_approx(scroll.modulate.a, 1.0), "選択前のスクロール領域が透明になっている")

	var row: Control = ui._ach_rows["true_sea_ruler"]
	var btn := _btn_of(row)
	check(btn != null, "「真の海の王者」の選択ボタンが見つからない")

	# ---- 選択直後: 補正が終わるまでスクロール領域が透明であること(ジャンプを隠す) ----
	btn.pressed.emit()
	check(is_equal_approx(scroll.modulate.a, 0.0),
		"選択直後にスクロール領域が透明になっていない(補正前のずれた見た目が見えてしまう)")

	for i in 6:
		await get_tree().process_frame

	check(GameState.badge_id == "true_sea_ruler", "「真の海の王者」が選択されていない")
	check(is_equal_approx(scroll.modulate.a, 1.0),
		"補正完了後にスクロール領域が不透明に戻っていない")

	ui.queue_free()
	GameState.achieved = old_achieved
	GameState.badge_id = old_badge

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_265_re10_ach_scroll_hidden_jump")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
