extends Node
## #241: 出港時のワンポイントヒント。島ごとに「何回目の出港か」で出し分ける。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()

	# --- 始まりの島: 1回目・2回目は固定 ---
	GameState.current_island = 0
	GameState.fame = 0
	check(GameState.next_departure_hint() == "まずは漁をして資金を稼ごう。", "始まりの島の初出港ヒントが違う")
	check(GameState.next_departure_hint().contains("酒場で雇用"), "始まりの島の2回目ヒントが違う")

	# 3・4回目はランダム(表に載っているもの)
	var tbl: Dictionary = Database.departure_hint_table(0)
	var pool: Array = tbl.get("random", [])
	for i in 2:
		var h := GameState.next_departure_hint()
		check(pool.has(h), "始まりの島の3〜4回目がランダム表に無い: %s" % h)

	# 5回目は名声ヒント(at5)
	check(GameState.next_departure_hint() == str(tbl["at5"]), "始まりの島の5回目ヒントが違う")

	# --- 名声22以上になった後の初回は最優先で1度だけ ---
	GameState.fame = 22
	check(GameState.next_departure_hint() == str(tbl["fame22"]), "名声22到達後のヒントが出ない")
	check(GameState.hint_fame22_used, "名声22ヒントの使用済みフラグが立たない")
	var again := GameState.next_departure_hint()
	check(again != str(tbl["fame22"]), "名声22ヒントが2回出ている")

	# --- 名声ヒントは「3回目以降」「5回目」より優先(最初に該当した回で出る) ---
	GameState.reset_all()
	GameState.current_island = 0
	GameState.fame = 30
	GameState.next_departure_hint()   # 1回目=固定
	GameState.next_departure_hint()   # 2回目=固定
	check(GameState.next_departure_hint() == str(tbl["fame22"]),
		"名声を満たしていても3回目で名声ヒントが出ない(ランダムに食われている)")
	# 5回目に到達しても、既に出したので at5 が出る
	GameState.next_departure_hint()   # 4回目
	check(GameState.next_departure_hint() == str(tbl["at5"]),
		"名声ヒントを出した後の5回目が at5 でない")

	# --- 潮鳴りの島: 1〜3回目固定・5回目はスキル ---
	GameState.reset_all()
	GameState.current_island = 1
	var t1: Dictionary = Database.departure_hint_table(1)
	for n in [1, 2, 3]:
		check(GameState.next_departure_hint() == str(t1.fixed[n]), "潮鳴りの%d回目が固定ヒントでない" % n)
	GameState.next_departure_hint()   # 4回目=ランダム
	check(GameState.next_departure_hint() == str(t1["at5"]), "潮鳴りの5回目がスキルのヒントでない")

	# --- 星霜・常闇は月下と同じ内容 ---
	for isle in [5, 6]:
		check(Database.departure_hint_table(isle) == Database.departure_hint_table(2),
			"島%d のヒントが月下と同じでない" % isle)

	# --- 島ごとに回数が独立していること ---
	GameState.reset_all()
	GameState.current_island = 0
	GameState.next_departure_hint()
	GameState.current_island = 1
	var first_of_1 := GameState.next_departure_hint()
	check(first_of_1 == str(Database.departure_hint_table(1).fixed[1]),
		"島をまたぐと出港回数が混ざっている")

	# --- 全島にヒントが定義されていること(未定義だと無言になる) ---
	for isle2 in Database.islands:
		var t: Dictionary = Database.departure_hint_table(int(isle2.id))
		check(not t.is_empty(), "島 %s にヒントが無い" % str(isle2.name))
		check(not (t.get("random", []) as Array).is_empty(), "島 %s のランダムヒントが空" % str(isle2.name))
	# 空文字が混ざっていないか
	for key in Database.departure_hints:
		var t2: Dictionary = Database.departure_hints[key]
		for fx in (t2.get("fixed", {}) as Dictionary).values():
			check(str(fx).strip_edges() != "", "島%s の固定ヒントが空" % str(key))
		for r in (t2.get("random", []) as Array):
			check(str(r).strip_edges() != "", "島%s のランダムヒントに空文字" % str(key))

	# --- セーブ・ロードで出港回数が保たれること(キーが文字列化する罠) ---
	GameState.reset_all()
	GameState.current_island = 0
	GameState.next_departure_hint()
	GameState.next_departure_hint()
	GameState.save_game()
	GameState.reset_all()
	check(GameState.load_game(), "セーブのロードに失敗")
	check(int(GameState.departures.get(0, 0)) == 2,
		"ロード後に出港回数が復元されない(%s)" % str(GameState.departures))
	GameState.current_island = 0
	var after := GameState.next_departure_hint()
	check(after != "まずは漁をして資金を稼ごう。", "ロード後に初出港ヒントへ戻ってしまう")

	# --- HUDに表示できること ---
	var HUD = preload("res://scripts2d/HUD2D.gd")
	var hud := CanvasLayer.new()
	hud.set_script(HUD)
	add_child(hud)
	await get_tree().process_frame
	hud.show_departure_hint("テスト")
	check(hud._hint_box.visible, "ヒントが表示されない")
	# #241再: 資金/名声と同じ半透明グレーの枠に入っていること
	var panel: PanelContainer = null
	for c in hud._hint_box.get_children():
		if c is PanelContainer:
			panel = c
	check(panel != null, "ヒントに枠(PanelContainer)が付いていない")
	if panel != null:
		var sb: StyleBox = panel.get_theme_stylebox("panel")
		check(sb is StyleBoxFlat, "ヒントの枠に背景スタイルが無い")
		if sb is StyleBoxFlat:
			var bg: Color = (sb as StyleBoxFlat).bg_color
			check(bg.a > 0.2 and bg.a < 0.9, "ヒントの枠が半透明でない(a=%.2f)" % bg.a)
	check(hud.lbl_hint.text == "ヒント：テスト", "ヒントの書式が「ヒント：〇〇」でない(%s)" % hud.lbl_hint.text)
	hud.show_departure_hint("")   # 空なら何もしない
	check(hud.lbl_hint.text == "ヒント：テスト", "空文字でヒントが上書きされた")
	hud.free()

	# --- #241再2: ヒントログ ---
	GameState.reset_all()
	GameState.current_island = 0
	check(GameState.hint_log.is_empty(), "初期状態でヒントログが空でない")
	var h1 := GameState.next_departure_hint()
	var h2 := GameState.next_departure_hint()
	check(GameState.hint_log.size() == 2, "表示したヒントが記録されない(%d)" % GameState.hint_log.size())
	# 新しい順(先頭が直近)
	check(str(GameState.hint_log[0].text) == h2, "ヒントログが新しい順でない")
	check(str(GameState.hint_log[1].text) == h1, "ヒントログの2件目が古い方でない")
	check(str(GameState.hint_log[0].island) == "始まりの島", "ヒントログに島名が入っていない")
	# 上限を超えても古いものから捨てる
	for i in 60:
		GameState.next_departure_hint()
	check(GameState.hint_log.size() <= GameState.HINT_LOG_MAX,
		"ヒントログが上限(%d)を超えている(%d)" % [GameState.HINT_LOG_MAX, GameState.hint_log.size()])
	# セーブ・ロードで保たれる
	GameState.save_game()
	var keep := str(GameState.hint_log[0].text)
	GameState.reset_all()
	check(GameState.load_game(), "セーブのロードに失敗")
	check(not GameState.hint_log.is_empty() and str(GameState.hint_log[0].text) == keep,
		"ロード後にヒントログが復元されない")

	# 早見表に「直近のヒント」とヒントログボタンが出ること
	var Overlay = preload("res://scripts/OverlayMenus.gd")
	var host := Control.new()
	add_child(host)
	GameState.at_sea = false
	Overlay.show_help(host)
	var txt := ""
	for n2 in host.find_children("*", "Label", true, false):
		txt += n2.text
	for n3 in host.find_children("*", "RichTextLabel", true, false):
		txt += n3.text
	check(txt.contains("直近のヒント"), "早見表に直近のヒント枠が無い")
	check(txt.contains(keep), "早見表に直近のヒント本文が出ていない")
	var has_log_btn := false
	for b2 in host.find_children("*", "Button", true, false):
		if b2.text == "ヒントログ":
			has_log_btn = true
	check(has_log_btn, "早見表にヒントログボタンが無い")

	# ヒントログ画面が新しい順に並ぶこと
	Overlay.show_hint_log(host)
	var logtxt := ""
	for n4 in host.find_children("*", "RichTextLabel", true, false):
		logtxt += n4.text
	check(logtxt.contains(keep), "ヒントログに直近のヒストが出ていない")
	var lines: Array = logtxt.split("
")
	if lines.size() >= 2:
		check(str(lines[0]).contains(keep), "ヒントログの先頭が直近のヒントでない")
	var has_back := false
	for b3 in host.find_children("*", "Button", true, false):
		if b3.text == "早見表へ戻る":
			has_back = true
	check(has_back, "ヒントログから早見表へ戻れない")
	host.free()

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK departure_hints/hint_log")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
