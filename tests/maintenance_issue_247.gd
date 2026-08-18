extends Node
## #247: 島ごとの造船所ラインナップ(先の島では下位の品を店頭から下げる)。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

# その島の造船所に並ぶ船/武器のidを実際のUIから集める
func _listed(port: CanvasLayer, isle: int) -> Dictionary:
	GameState.current_island = isle
	GameState.money = 99999999
	# 武器はスロットを開かないと一覧が出ない仕様なので、スロット1を開いた状態にする
	port._shipyard_weapon_slot = 0
	port.show_shipyard()
	await get_tree().process_frame
	var txt := ""
	for n in port.content.find_children("*", "Label", true, false):
		txt += n.text + "\n"
	for n in port.content.find_children("*", "Button", true, false):
		txt += n.text + "\n"
	var ships: Array = []
	for sid in Database.ships:
		if txt.contains(str(Database.ships[sid].name)):
			ships.append(sid)
	# 武器は「名前  価格:○○」の形で並ぶ。最下段の固定説明文(「・ガトリングガン …」)を
	# 拾わないよう、価格つきの行だけを販売中とみなす。
	var weapons: Array = []
	for wid in Database.weapons:
		if txt.contains("%s  価格:" % str(Database.weapons[wid].name)):
			weapons.append(wid)
	return {"ships": ships, "weapons": weapons}

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()
	GameState.unlocked_islands.assign(range(Database.islands.size()))
	# 装備中の武器は「付け替え候補」から除かれるため、判定を濁さないよう外しておく
	for wi in GameState.fleet[0].weapons.size():
		GameState.fleet[0].weapons[wi] = ""
	var Port = preload("res://scripts/PortUI.gd")
	var port := CanvasLayer.new()
	port.set_script(Port)
	add_child(port)
	await get_tree().process_frame
	port.open()

	# レビュアー指定の「削除する」品目
	var want_gone := {
		3: {"ships": ["raft", "skiff", "cutter", "hauler"], "weapons": ["cannon2", "torpedo2"]},
		7: {"ships": ["raft", "skiff", "cutter", "hunter_h"], "weapons": ["gatling2", "harpoon2"]},
		4: {"ships": ["raft", "skiff", "cutter"], "weapons": ["gatling", "cannon", "harpoon", "torpedo"]},
	}
	for isle in want_gone:
		var got: Dictionary = await _listed(port, int(isle))
		for sid in want_gone[isle].ships:
			check(not (got.ships as Array).has(str(sid)),
				"島%d で %s が売られている(削除指定)" % [isle, str(Database.ships[sid].name)])
		for wid in want_gone[isle].weapons:
			check(not (got.weapons as Array).has(str(wid)),
				"島%d で %s が売られている(削除指定)" % [isle, str(Database.weapons[wid].name)])
		# 全部消えて買えなくなっていないこと
		check(not (got.ships as Array).is_empty(), "島%d の造船所に船が1隻も無い" % isle)
		check(not (got.weapons as Array).is_empty(), "島%d の造船所に武器が1つも無い" % isle)

	# 指定のない島は従来どおり(始まり=粗末な漁船が買える)
	var isle0: Dictionary = await _listed(port, 0)
	check((isle0.ships as Array).has("raft"), "始まりの島から粗末な漁船が消えている")
	check((isle0.weapons as Array).has("gatling"), "始まりの島からガトリングガンが消えている")

	# 果ての島でも上位武器4種は買えること(下位4種だけを外す指定なので)
	var isle4: Dictionary = await _listed(port, 4)
	for wid2 in ["gatling2", "cannon2", "harpoon2", "torpedo2"]:
		check((isle4.weapons as Array).has(wid2), "果ての島で %s が買えない" % wid2)
	# 嵐越えでは上位のうち残る2種が買えること
	var isle3: Dictionary = await _listed(port, 3)
	for wid3 in ["gatling2", "harpoon2"]:
		check((isle3.weapons as Array).has(wid3), "嵐越えで %s が買えない" % wid3)
	# 海嘯では上位のうち残る2種が買えること
	var isle7: Dictionary = await _listed(port, 7)
	for wid4 in ["cannon2", "torpedo2"]:
		check((isle7.weapons as Array).has(wid4), "海嘯で %s が買えない" % wid4)

	# 除外表のidが実在すること(タイプミスで無効化されるのを防ぐ)
	for isle2 in Database.SHOP_EXCLUDE:
		var ex: Dictionary = Database.SHOP_EXCLUDE[isle2]
		check(int(isle2) < Database.islands.size(), "除外表に存在しない島id %s" % str(isle2))
		for sid2 in ex.get("ships", []):
			check(Database.ships.has(str(sid2)), "除外表に存在しない船 %s" % str(sid2))
		for wid5 in ex.get("weapons", []):
			check(Database.weapons.has(str(wid5)), "除外表に存在しない武器 %s" % str(wid5))

	port.free()
	if failures.is_empty():
		print("MAINTENANCE_TEST_OK shop_lineup")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
