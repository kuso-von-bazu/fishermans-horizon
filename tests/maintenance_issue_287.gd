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


	# ---------------- #237再4: 港にいる間は敵が攻撃せず、居残りもしない ----------------
	# 従来の docking_locked は「寄港が確定してから完了するまで」しか true にならず、
	# 港にいる間は false に戻っていた。そのため居残った敵が港で近接攻撃を続け、
	# ダメージは入らないのに被弾音だけが鳴っていた(カーラボスで報告)。
	GameState.docking_locked = true      # 寄港確定〜港にいる間
	check(not GameState.combat_active(), "港にいるのに敵が攻撃してよい判定になっている")
	GameState.docking_locked = false     # 出港で解除
	check(GameState.combat_active(), "航海中なのに敵が攻撃できない判定になっている")

	# 敵側が docking_locked を直接見ていないこと(港で素通りする原因だった)
	var esrc := FileAccess.get_file_as_string("res://scripts2d/Enemy2D.gd")
	check(not esrc.contains("GameState.docking_locked"),
		"敵が docking_locked を直接見ている(港にいる間はガードが効かない)")

	# 実際に港の状態で近接ダメージ処理を叩いても、何も起きないこと
	var EnemyS2 = preload("res://scripts2d/Enemy2D.gd")
	var foe := CharacterBody2D.new()
	foe.set_script(EnemyS2)
	foe.setup("mob", "carabos")
	add_child(foe)
	await get_tree().process_frame
	GameState.docking_locked = true
	var armor_before: float = GameState.run_armor
	foe._damage_victim(50.0, null)
	check(is_equal_approx(GameState.run_armor, armor_before),
		"港にいるのに敵の近接攻撃が通っている")
	GameState.docking_locked = false
	foe.queue_free()

	# 寄港完了でロックを解除していないこと(解除すると港でガードが切れる)
	var w2s := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	var dh := w2s.find("func _enter_dock(")
	if dh != -1:
		var dt := w2s.find("\nfunc ", dh)
		var db: String = w2s.substr(dh, (dt - dh) if dt != -1 else 2000)
		check(not db.contains("docking_locked = false"),
			"_enter_dock がロックを解除している(港で敵のガードが切れる)")

	# 掃除が enemies 配列頼みでないこと(配列から漏れた個体が居残るのを防ぐ)
	var wsrc := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	var ci := wsrc.find("func _clear_sea_actors")
	check(ci != -1, "_clear_sea_actors が見つからない")
	if ci != -1:
		var ce := wsrc.find("\nfunc ", ci)
		var body: String = wsrc.substr(ci, (ce - ci) if ce != -1 else 1200)
		check(body.contains("get_children()") and body.contains("EnemyScript"),
			"敵の掃除が enemies 配列頼みのまま(配列から漏れた敵が港に残る)")

	# ---------------- #287再3: Defeatedスタンプの文字を大きく ----------------
	var stamp_src := FileAccess.get_file_as_string("res://画像生成/討伐済みスタンプ生成.py")
	check(stamp_src.contains("int(78 * SS)"), "スタンプの文字が78ptになっていない")

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_287_defeated_stamp/stamp_size/port_no_attack/enemy_cleanup")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
