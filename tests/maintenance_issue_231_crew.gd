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

	# --- #231再4: 交代したクルーは「元いた位置」へ入る(末尾に寄らない) ---
	GameState.fleet[0].crew = [_mk("A1"), _mk("A2"), _mk("A3")]
	GameState.fleet[1].crew = [_mk("B1"), _mk("B2"), _mk("B3")]
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])   # A1(先頭)
	port._on_crew_clicked(1, GameState.fleet[1].crew[2])   # B3(3番目)
	check(str(GameState.fleet[0].crew[0].name) == "B3", "交代相手が元の位置(先頭)に入っていない(%s)" % GameState.fleet[0].crew[0].name)
	check(str(GameState.fleet[1].crew[2].name) == "A1", "交代相手が元の位置(3番目)に入っていない(%s)" % GameState.fleet[1].crew[2].name)
	check(str(GameState.fleet[0].crew[1].name) == "A2" and str(GameState.fleet[1].crew[0].name) == "B1",
		"交代で無関係のクルーの並びが動いた")

	# --- #231再4: 交代でも副船長は1隻に1名まで(以前は交代経由で2名置けた) ---
	GameState.fleet[0].crew = [_mk("S1", "firstmate"), _mk("N1")]
	GameState.fleet[1].crew = [_mk("S2", "firstmate"), _mk("N2")]
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])   # 旗艦の副船長
	port._on_crew_clicked(1, GameState.fleet[1].crew[1])   # 2番艦の一般クルーと交代しようとする
	var fm := 0
	for c2 in GameState.fleet[1].crew:
		if str(c2.job) == "firstmate":
			fm += 1
	check(fm <= 1, "交代で1隻に副船長が%d名になった" % fm)
	# 副船長どうしの交代は通ること
	port._crew_pick = {}
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	port._on_crew_clicked(1, GameState.fleet[1].crew[0])
	check(str(GameState.fleet[0].crew[0].name) == "S2", "副船長どうしの交代ができない")

	# --- #240: 船団から外すとクルーはストックへ ---
	GameState.crew_stock = []
	GameState.fleet = [GameState.new_ship_entry("raft"), GameState.new_ship_entry("raft")]
	GameState.fleet[1].crew = [_mk("K1"), _mk("K2")]
	check(GameState.fleet_remove(1), "クルーが乗っていると船団から外せない")
	check(GameState.fleet.size() == 1, "船団から外れていない")
	check(GameState.crew_stock.size() == 2, "外した船のクルーがストックへ移っていない(%d)" % GameState.crew_stock.size())

	# --- #240: ストック → 空きへ乗せる(どちらを先に選んでもよい) ---
	GameState.fleet = [GameState.new_ship_entry("raft"), GameState.new_ship_entry("raft")]
	GameState.crew_stock = [_mk("T1")]
	port._crew_pick = {}
	port._on_crew_clicked(-1, GameState.crew_stock[0])   # ストックを先に選ぶ
	port._on_crew_slot_clicked(1)
	check(GameState.fleet[1].crew.size() == 1 and GameState.crew_stock.is_empty(),
		"ストックから船へ乗せられない(船%d / ストック%d)" % [GameState.fleet[1].crew.size(), GameState.crew_stock.size()])

	# 船 → ストックへ降ろす(空きを先に押す順でも動く)
	port._crew_pick = {}
	port._on_crew_clicked(1, GameState.fleet[1].crew[0])
	port._on_crew_slot_clicked(-1)
	check(GameState.crew_stock.size() == 1 and GameState.fleet[1].crew.is_empty(),
		"船からストックへ降ろせない")

	# --- #240: ストックと乗員の交代(どちらを先に選んでも同じ結果) ---
	for first_stock in [true, false]:
		GameState.fleet = [GameState.new_ship_entry("raft")]
		GameState.fleet[0].crew = [_mk("ON")]
		GameState.crew_stock = [_mk("OFF")]
		port._crew_pick = {}
		if first_stock:
			port._on_crew_clicked(-1, GameState.crew_stock[0])
			port._on_crew_clicked(0, GameState.fleet[0].crew[0])
		else:
			port._on_crew_clicked(0, GameState.fleet[0].crew[0])
			port._on_crew_clicked(-1, GameState.crew_stock[0])
		check(str(GameState.fleet[0].crew[0].name) == "OFF" and str(GameState.crew_stock[0].name) == "ON",
			"ストックとの交代に失敗(先にストックを選んだ=%s)" % str(first_stock))

	# --- #240: ストックのクルーは賃金の対象外 ---
	GameState.fleet = [GameState.new_ship_entry("raft")]
	GameState.fleet[0].crew = [_mk("W1")]
	GameState.crew_stock = [_mk("W2"), _mk("W3")]
	check(GameState.all_crew().size() == 1, "ストックのクルーが乗員として数えられている(%d)" % GameState.all_crew().size())

	# --- #240再: 「空き」を先にクリックしてからクルーを選ぶ順でも動く ---
	# 船の空き → 別の船のクルー
	GameState.fleet = [GameState.new_ship_entry("raft"), GameState.new_ship_entry("raft")]
	GameState.fleet[1].crew = [_mk("M1")]
	GameState.crew_stock = []
	port._crew_pick = {}
	port._on_crew_slot_clicked(0)                        # 旗艦の空きを先に押す
	check(bool(port._crew_pick.get("slot", false)), "空きを先に押しても選択されない")
	port._on_crew_clicked(1, GameState.fleet[1].crew[0]) # 2番艦のクルーを押す
	check(GameState.fleet[0].crew.size() == 1 and GameState.fleet[1].crew.is_empty(),
		"空き→クルーの順で移動できない(旗艦%d / 2番艦%d)" % [GameState.fleet[0].crew.size(), GameState.fleet[1].crew.size()])
	check(port._crew_pick.is_empty(), "移動後に選択が残っている")

	# 船の空き → ストックのクルー
	GameState.fleet = [GameState.new_ship_entry("raft")]
	GameState.crew_stock = [_mk("M2")]
	port._crew_pick = {}
	port._on_crew_slot_clicked(0)
	port._on_crew_clicked(-1, GameState.crew_stock[0])
	check(GameState.fleet[0].crew.size() == 1 and GameState.crew_stock.is_empty(),
		"空き→ストックのクルーの順で乗せられない")

	# ストックの空き → 船のクルー(降ろす)
	GameState.fleet = [GameState.new_ship_entry("raft")]
	GameState.fleet[0].crew = [_mk("M3")]
	GameState.crew_stock = []
	port._crew_pick = {}
	port._on_crew_slot_clicked(-1)                       # 「ストックへ降ろす」を先に押す
	port._on_crew_clicked(0, GameState.fleet[0].crew[0])
	check(GameState.crew_stock.size() == 1 and GameState.fleet[0].crew.is_empty(),
		"ストックの空き→クルーの順で降ろせない")

	# 空きを押したあと別の空きを押したら、選び直しになる(操作不能にならない)
	GameState.fleet = [GameState.new_ship_entry("raft"), GameState.new_ship_entry("raft")]
	port._crew_pick = {}
	port._on_crew_slot_clicked(0)
	port._on_crew_slot_clicked(1)
	check(bool(port._crew_pick.get("slot", false)) and int(port._crew_pick.ship) == 1,
		"空き→空きで選び直しになっていない")
	port._crew_pick = {}

	# --- #239再: 航路の並び順が進行順であること ---
	var order: Array = []
	for isle in Database.islands_in_order():
		order.append(str(isle.name))
	# #239再2: 海嘯 → 嵐越え の順(レビュアー指定で入れ替え)
	var want := ["始まりの島", "潮鳴りの島", "月下の島", "星霜の島", "常闇の島", "海嘯の島", "嵐越えの島", "果ての島"]
	check(order == want, "航路の並び順が指定と違う: %s" % str(order))
	check(order.size() == Database.islands.size(), "並び順に載っていない島がある")

	port.free()
	if failures.is_empty():
		print("MAINTENANCE_TEST_OK crew_click/swap_pos/firstmate/stock/slot_first/island_order")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
