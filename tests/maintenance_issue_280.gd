extends Node
## #265再4 / #280: 今回の反映を検証する。
##
## ・#265再4 実績メニューの文言修正・見出し「討伐」・討伐数の緩和(30→20 / ゾンビウオ90→60)
## ・#280   帰還長押し中に燃料半減ダイアログで帰港すると「帰還まで○秒」が残るバグ

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()

	# ---------------- #265再4: 討伐の達成条件 ----------------
	# 通常のモブは20体、ゾンビウオは60体、マーマンは90体(据え置き)
	var want_need := {"zombie_fish": 60, "merman": 90}
	var mob_count := 0
	for a in Database.achievements:
		if str(a.get("group", "")) != "kill" or str(a.get("check", "")) != "mob":
			continue
		mob_count += 1
		var tgt := str(a.target)
		var need := int(a.need)
		var want: int = int(want_need.get(tgt, 20))
		check(need == want, "%s の討伐数が %d でない(%d)" % [str(a.name), want, need])
		# 説明文の体数も達成条件と一致していること
		check(str(a.desc).contains("を%d体討伐" % need),
			"%s の説明が達成条件と合っていない: %s" % [str(a.name), str(a.desc)])
	check(mob_count == 20, "討伐(モブ)の実績が20件でない(%d)" % mob_count)

	# バウンティハンターは据え置き(海賊100隻・海賊王2隻)
	var bh := Database.achievement("bounty_hunter")
	check(int(bh.need) == 100, "バウンティハンターの海賊が100隻でない(%d)" % int(bh.need))
	check(_src("res://scripts/GameState.gd").contains('kill_count("pirate", "king") >= 2'),
		"バウンティハンターの海賊王が2隻でない")

	# 実際に20体倒せば達成し、19体では達成しないこと
	GameState.achieved = {}
	for i in 19:
		GameState.record_kill("mob", "narwhal")
	check(not GameState.is_achieved("kill_narwhal"), "19体で実績が達成されてしまう")
	GameState.record_kill("mob", "narwhal")
	check(GameState.is_achieved("kill_narwhal"), "20体で実績が達成されない")
	# ゾンビウオは60体
	GameState.achieved = {}
	for i in 59:
		GameState.record_kill("mob", "zombie_fish")
	check(not GameState.is_achieved("kill_zombie_fish"), "ゾンビウオが59体で達成されてしまう")
	GameState.record_kill("mob", "zombie_fish")
	check(GameState.is_achieved("kill_zombie_fish"), "ゾンビウオが60体で達成されない")

	# ---------------- #265再4: 実績メニューの文言 ----------------
	var psrc := _src("res://scripts/PortUI.gd")
	check(psrc.contains('"kill": "討伐",'), "実績の見出しが「討伐」になっていない")
	check(not psrc.contains("戦闘能力があるモブ・海賊"), "見出しに旧い注釈が残っている")
	check(psrc.contains("達成した実績を選択するとバフ効果を得られる。"), "実績メニューの説明が新しい文言でない")
	check(not psrc.contains("航海中に名声の右へバッヂが出て小さなバフが付く"), "実績メニューの旧い説明が残っている")

	# ---------------- #280: 「帰還まで○秒」が残らない ----------------
	var hud := preload("res://scripts2d/HUD2D.gd").new()
	add_child(hud)
	await get_tree().process_frame
	var hint: String = str(hud.lbl_return.text)
	check(hint.contains("長押し"), "帰還ヒントの初期表示がおかしい: " + hint)
	hud.set_return_progress(0.6)
	check(str(hud.lbl_return.text).begins_with("帰還まで"), "長押し中に進捗が出ない")

	var world = preload("res://scripts2d/World2D.gd").new()
	world.hud = hud
	world._return_hold = 1.8
	world._clear_return_hold()
	check(float(world._return_hold) == 0.0, "帰還長押しの進捗が戻らない")
	check(str(hud.lbl_return.text) == hint, "HUDの「帰還まで○秒」が消えない: " + str(hud.lbl_return.text))
	world.free()
	hud.queue_free()

	# 寄港・出港・燃料半減ダイアログのいずれでも必ず消していること
	var wsrc := _src("res://scripts2d/World2D.gd")
	for fn in ["_enter_dock", "_on_set_sail", "_show_food_choice"]:
		var head := wsrc.find("func %s(" % fn)
		check(head != -1, "%s が見つからない" % fn)
		var tail := wsrc.find("\nfunc ", head)
		var body := wsrc.substr(head, (tail - head) if tail != -1 else 400)
		check(body.contains("_clear_return_hold()"), "%s で帰還長押しの表示を消していない" % fn)

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK kill_need/ach_text/return_label")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
