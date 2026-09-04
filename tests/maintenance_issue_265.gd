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


	# ---------------- #265再12: ウェポンマスターは「装備したことがある」で達成 ----------------
	# 従来は「船団が同時に全種類を装備している」必要があり、
	# スロット数の都合で満たしにくかった。装備歴で達成するように変更した。
	GameState.reset_all()
	GameState.achieved = {}
	GameState.weapons_ever = {}
	check(not GameState._fleet_achievement("weapon_master"), "何も装備していないのに達成している")
	# 1種類ずつ「装備したことがある」を積み上げる(同時装備はしない)
	var all_w: Array = Database.weapons.keys()
	for i in all_w.size() - 1:
		GameState.note_weapon_equipped(str(all_w[i]))
	check(not GameState._fleet_achievement("weapon_master"),
		"最後の1種類が未装備なのに達成している(%d/%d)" % [GameState.weapons_ever.size(), all_w.size()])
	GameState.note_weapon_equipped(str(all_w[all_w.size() - 1]))
	check(GameState._fleet_achievement("weapon_master"),
		"全種類を装備したことがあるのに達成しない(%d/%d)" % [GameState.weapons_ever.size(), all_w.size()])

	# 外した後も達成が取り消されないこと(「したことがある」なので)
	for e in GameState.fleet:
		for i2 in e.weapons.size():
			e.weapons[i2] = ""
	check(GameState._fleet_achievement("weapon_master"), "武器を外したら達成が取り消された")

	# セーブに持ち越されること(持ち越さないと再開で達成が消える)
	var gsrc := FileAccess.get_file_as_string("res://scripts/GameState.gd")
	check(gsrc.contains('"weapons_ever": weapons_ever'), "装備歴がセーブに含まれていない")
	check(gsrc.contains('data.get("weapons_ever"'), "装備歴がセーブから読み戻されていない")

	# 説明文も新しい条件になっていること
	var wm: Dictionary = Database.achievement("weapon_master")
	check(str(wm.get("desc", "")).contains("したことがある"),
		"ウェポンマスターの説明が古い条件のまま(%s)" % str(wm.get("desc", "")))

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_265_multi_buff_no_hscroll/weapon_master_ever")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
