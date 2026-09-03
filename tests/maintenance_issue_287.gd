extends Node
## #287: 酒場の「この近海の主」一覧で、討伐済みの主の絵に赤い「Defeated」スタンプを
## 前面表示すること。未討伐の主には出ないこと。画像クリックで拡大表示するときは
## スタンプ自体を出さず、主本体の絵だけを表示することを確認する。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

const STAMP_PATH := "res://assets/images/ui_defeated_stamp.png"

func _find_row_for_lord(port, lid: String) -> HBoxContainer:
	for row in port.content.find_children("*", "HBoxContainer", true, false):
		for c in row.get_children():
			if c is PanelContainer:
				for gc in c.get_children():
					if gc is TextureRect and gc.texture and gc.texture.resource_path == "res://assets/images/lord_%s.png" % lid:
						return row
	return null

func _has_stamp(row: HBoxContainer) -> bool:
	for c in row.get_children():
		if c is PanelContainer:
			for gc in c.get_children():
				if gc is TextureRect and gc.texture and gc.texture.resource_path == STAMP_PATH:
					return true
	return false

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	check(ResourceLoader.exists(STAMP_PATH), "Defeated スタンプ画像が無い(%s)" % STAMP_PATH)

	var old_island := GameState.current_island
	var old_defeated: Array = GameState.defeated_lords.duplicate()
	var old_claimed: Array = GameState.claimed_lords.duplicate()

	GameState.current_island = 0   # 始まりの島: lords = sawshark, dumbo
	GameState.defeated_lords = ["sawshark"]
	GameState.claimed_lords = []

	var PortUIScript = preload("res://scripts/PortUI.gd")
	var port = PortUIScript.new()
	add_child(port)
	await get_tree().process_frame
	port.open()
	port._tavern_section = "lords"
	port.show_tavern()
	await get_tree().process_frame

	var row_sawshark := _find_row_for_lord(port, "sawshark")
	var row_dumbo := _find_row_for_lord(port, "dumbo")
	check(row_sawshark != null, "電動ノコギリザメの行が見つからない(テストの前提が崩れている)")
	check(row_dumbo != null, "ウミダンボの行が見つからない(テストの前提が崩れている)")
	if row_sawshark:
		check(_has_stamp(row_sawshark), "討伐済みの電動ノコギリザメにDefeatedスタンプが出ていない")
	if row_dumbo:
		check(not _has_stamp(row_dumbo), "未討伐のウミダンボにDefeatedスタンプが出てしまっている")

	# 拡大ポップアップはスタンプ無しの本体画像だけを表示する
	if row_sawshark:
		for c in row_sawshark.get_children():
			if c is PanelContainer:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				c.gui_input.emit(ev)
	await get_tree().process_frame
	check(port._img_popup != null, "拡大ポップアップが開いていない")
	if port._img_popup:
		var big: TextureRect = null
		for n in port._img_popup.find_children("*", "TextureRect", true, false):
			big = n
			break
		check(big != null and big.texture != null and big.texture.resource_path == "res://assets/images/lord_sawshark.png",
			"拡大ポップアップの画像が主体絵になっていない")

	port.queue_free()
	GameState.current_island = old_island
	GameState.defeated_lords = old_defeated
	GameState.claimed_lords = old_claimed

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_287_defeated_stamp")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
