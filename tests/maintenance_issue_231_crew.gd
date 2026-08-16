extends Node
## #231再3: 編成画面のクルー操作をクリック方式へ変更した件の検証。
## クルーを選択 → 「空き」で移動 / 別のクルーで交代 / 同じ船なら並び替え。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _mk(nm: String, job := "sailor") -> Dictionary:
	return {"name": nm, "job": job, "hp": 5, "agi": 5, "sht": 5, "int_": 5, "vis": 5}

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()
	GameState.fleet = [
		GameState.new_ship_entry("raft", ["gatling"]),
		GameState.new_ship_entry("raft", ["gatling"]),
	]
	GameState.fleet[0].crew = [_mk("A"), _mk("B")]
	GameState.fleet[1].crew = [_mk("C")]

	var Port = preload("res://scripts/PortUI.gd")
	var port := CanvasLayer.new()
	port.set_script(Port)
	add_child(port)
	await get_tree().process_frame
	GameState.visited_islands = [0, 1]
	port.open()
	port.show_fleet()
	await get_tree().process_frame

	# --- 空きスロットが表示されること(これが無いと空いている船へ移せない) ---
	var empties := 0
	for n in port.content.find_children("*", "RichTextLabel", true, false):
		if str(n.text).contains("(空き)"):
			empties += 1
	# 旗艦2名/2番艦1名 → 空きは (4-2)+(4-1)=5
	check(empties == 5, "空きスロットの数が合わない(%d / 期待5)" % empties)

	# --- 別の船へ移動: A を選んで 2番艦の空きをクリック ---
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	check(not port._crew_pick.is_empty(), "クルーを選択できていない")
	port._on_crew_slot_clicked(1)
	check(GameState.fleet[0].crew.size() == 1 and GameState.fleet[1].crew.size() == 2,
		"空きスロットへの移動ができていない(%d / %d)" % [GameState.fleet[0].crew.size(), GameState.fleet[1].crew.size()])
	check(port._crew_pick.is_empty(), "移動後に選択が解除されていない")

	# --- 別の船のクルーと交代 ---
	GameState.fleet[0].crew = [_mk("A")]
	GameState.fleet[1].crew = [_mk("C")]
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	port._on_crew_clicked(1, GameState.fleet[1].crew[0])
	check(str(GameState.fleet[0].crew[0].name) == "C" and str(GameState.fleet[1].crew[0].name) == "A",
		"別の船のクルーと交代できていない(%s / %s)" % [GameState.fleet[0].crew[0].name, GameState.fleet[1].crew[0].name])

	# --- 満員の船との交代(以前は専用ダイアログが要った) ---
	GameState.fleet[0].crew = [_mk("A")]
	GameState.fleet[1].crew = [_mk("W"), _mk("X"), _mk("Y"), _mk("Z")]
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	port._on_crew_clicked(1, GameState.fleet[1].crew[2])   # Y と交代
	check(str(GameState.fleet[0].crew[0].name) == "Y", "満員の船のクルーと交代できていない(%s)" % GameState.fleet[0].crew[0].name)
	check(GameState.fleet[1].crew.size() == 4, "交代後に満員の船の人数が変わっている(%d)" % GameState.fleet[1].crew.size())
	var names: Array = []
	for c in GameState.fleet[1].crew:
		names.append(str(c.name))
	check(names.has("A") and not names.has("Y"), "交代の入れ替わりが正しくない(%s)" % str(names))

	# --- 同じ船の中での並び替え ---
	GameState.fleet[0].crew = [_mk("P"), _mk("Q"), _mk("R")]
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])   # P
	port._on_crew_clicked(0, GameState.fleet[0].crew[2])   # R
	check(str(GameState.fleet[0].crew[0].name) == "R" and str(GameState.fleet[0].crew[2].name) == "P",
		"同じ船の中で並び替えできていない(%s,%s,%s)" % [GameState.fleet[0].crew[0].name, GameState.fleet[0].crew[1].name, GameState.fleet[0].crew[2].name])
	check(str(GameState.fleet[0].crew[1].name) == "Q", "並び替えで無関係のクルーが動いた")

	# --- 同じクルーをもう一度押したら選択解除 ---
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	check(port._crew_pick.is_empty(), "同じクルーを再クリックしても選択が解除されない")

	# --- 副船長は1隻に1名の制約が維持されること ---
	GameState.fleet[0].crew = [_mk("F1", "firstmate")]
	GameState.fleet[1].crew = [_mk("F2", "firstmate")]
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	port._on_crew_slot_clicked(1)   # 副船長がいる船へ移そうとする
	check(GameState.fleet[1].crew.size() == 1, "副船長が1隻に2名乗ってしまった(%d名)" % GameState.fleet[1].crew.size())

	# --- 寄港のたびに選択状態が残らないこと ---
	port._crew_pick = {"ship": 0, "member": GameState.fleet[0].crew[0]}
	port.open()
	check(port._crew_pick.is_empty(), "寄港しても前回の選択が残っている")

	port.free()
	if failures.is_empty():
		print("MAINTENANCE_TEST_OK crew_click_move/swap/reorder/deselect/firstmate")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
