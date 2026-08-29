extends Node
## #265再6: 実績「真の海の王者」(ボスラッシュ制覇)「アルティメットプレーヤー」(全実績制覇)の追加。
## 「その他」見出しを一番下に配置。「バッヂ効果」→「バフ効果」「選択中のバッヂ」→「選択中のバフ」への置換。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	# ---------------- 文言: バッヂ効果→バフ効果 / 選択中のバッヂ→選択中のバフ ----------------
	var psrc := FileAccess.get_file_as_string("res://scripts/PortUI.gd")
	check(not psrc.contains("バッヂ効果"), "「バッヂ効果」の表記が実績メニューに残っている")
	check(psrc.contains("バフ効果"), "「バフ効果」の表記が無い")
	check(not psrc.contains("選択中のバッヂ"), "「選択中のバッヂ」の表記が残っている")
	check(psrc.contains("選択中のバフ"), "「選択中のバフ」の表記が無い")

	# ---------------- 「その他」見出しが一番下 ----------------
	var keys: Array = []
	for g in PortUIScriptGroupNames():
		keys.append(g)
	check(keys.size() > 0 and str(keys[keys.size() - 1]) == "other", "「その他」見出しが一番下にない: %s" % str(keys))
	check(str(PortUIScriptGroupNames()["other"]) == "その他", "「その他」見出しの表記が違う")

	# ---------------- 実績データ: 真の海の王者 / アルティメットプレーヤー ----------------
	var ruler := Database.achievement("true_sea_ruler")
	check(not ruler.is_empty(), "真の海の王者が定義されていない")
	check(str(ruler.get("group", "")) == "other", "真の海の王者のグループが「その他」でない")
	check(str(ruler.get("check", "")) == "boss_rush", "真の海の王者の判定種別がboss_rushでない")

	var ult := Database.achievement("ultimate_player")
	check(not ult.is_empty(), "アルティメットプレーヤーが定義されていない")
	check(str(ult.get("group", "")) == "other", "アルティメットプレーヤーのグループが「その他」でない")
	check(str(ult.get("check", "")) == "all", "アルティメットプレーヤーの判定種別がallでない")

	check(Database.achievements.size() == 49, "実績の総数が49件でない(%d)" % Database.achievements.size())
	check(ResourceLoader.exists(str(ruler.get("icon", ""))), "真の海の王者のバッヂ絵が無い")
	check(ResourceLoader.exists(str(ult.get("icon", ""))), "アルティメットプレーヤーのバッヂ絵が無い")

	# ---------------- 表示条件: 1度でもボスラッシュに入るまでは？？？？？ ----------------
	var had_played := GameState.has_played_boss_rush()
	var had_cleared := GameState.has_cleared_boss_rush()
	var played_path := ProjectSettings.globalize_path("user://boss_rush_played.dat")
	var cleared_path := ProjectSettings.globalize_path("user://boss_rush_cleared.dat")
	DirAccess.remove_absolute(played_path)
	DirAccess.remove_absolute(cleared_path)

	var old_achieved: Dictionary = GameState.achieved.duplicate(true)
	GameState.achieved = {}

	check(not GameState.achievement_revealed(ruler), "ボスラッシュ未プレイなのに真の海の王者が見えている")
	GameState.mark_boss_rush_played()
	check(GameState.achievement_revealed(ruler), "ボスラッシュを1度プレイしても真の海の王者が見えない")
	check(not GameState._achievement_met(ruler), "クリアしていないのに真の海の王者が達成扱い")
	GameState.mark_boss_rush_cleared()
	check(GameState._achievement_met(ruler), "ボスラッシュ制覇後も真の海の王者が達成されない")

	# ---------------- アルティメットプレーヤー: 他の48件すべて達成して初めて成立 ----------------
	GameState.achieved = {}
	for a in Database.achievements:
		if str(a.id) != "ultimate_player":
			GameState.achieved[str(a.id)] = true
	check(GameState._achievement_met(Database.achievement("ultimate_player")), "48件すべて達成してもアルティメットプレーヤーが成立しない")
	GameState.achieved.erase("true_sea_ruler")
	check(not GameState._achievement_met(Database.achievement("ultimate_player")), "1件未達成でもアルティメットプレーヤーが成立してしまう")

	# 後始末: テスト前の状態に戻す
	GameState.achieved = old_achieved
	DirAccess.remove_absolute(played_path)
	DirAccess.remove_absolute(cleared_path)
	if had_played:
		GameState.mark_boss_rush_played()
	if had_cleared:
		GameState.mark_boss_rush_cleared()

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK true_sea_ruler/ultimate_player/wording")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)

func PortUIScriptGroupNames() -> Dictionary:
	var PortUIScript = preload("res://scripts/PortUI.gd")
	return PortUIScript.ACH_GROUP_NAMES
