extends Node
## #284 / #209再: レヴィアタン討伐と旗艦大破がほぼ同時になったとき、
## 討伐の瞬間から旗艦を無敵にして大破処理(強制帰還/Boss Rush失敗)を封じる。

const World2 = preload("res://scripts2d/World2D.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	# ---------------- ボスラッシュ: 最後のボス(レヴィアタン)撃破の瞬間に無敵化 ----------------
	var world := Node2D.new()
	world.set_script(World2)
	# _ready を走らせない(hud/player等の依存を避け、_br_ 系の内部状態だけを直接検証する)
	world._br_wait = 0.0
	world._br_active = true
	world._br_pair = false
	world._br_boss = null       # 解放済み(=倒した)扱い
	world._br_boss2 = null
	world._br_split_root = ""
	world.enemies = []
	world._br_index = World2.BOSS_RUSH_ORDER.size() - 1   # 最後の1体(レヴィアタン)を倒す直前
	world._br_won = false
	world._br_update(0.016)
	check(world._br_index == World2.BOSS_RUSH_ORDER.size(), "最後のボス撃破で_br_indexが進まない")
	check(world._br_won, "レヴィアタン討伐の瞬間に_br_wonが立たない")

	# _br_won が立っていれば、旗艦の装甲が0でも _br_fail() は何もしない(無敵)
	world._returning = false
	GameState.docking_locked = false
	world._br_fail()
	check(not world._returning, "討伐直後なのに_br_fail()がBoss Rush失敗処理を始めてしまう")
	check(not GameState.docking_locked, "討伐直後なのに_br_fail()がdocking_lockedを立ててしまう")

	# 通常のボス撃破(最後以外)では_br_wonは立たない(無敵化は最終ボスのみ)
	var world2 := Node2D.new()
	world2.set_script(World2)
	world2._br_wait = 0.0
	world2._br_active = true
	world2._br_pair = false
	world2._br_boss = null
	world2._br_boss2 = null
	world2._br_split_root = ""
	world2.enemies = []
	world2._br_index = 0
	world2._br_won = false
	world2._br_update(0.016)
	check(not world2._br_won, "最後のボス以外の撃破でも_br_wonが立ってしまう")

	# ---------------- 本編: レヴィアタン討伐で_victory_shownが立ったら大破処理をしない ----------------
	# _physics_process 内は "_check_victory() → if _victory_shown: return → 強制帰還判定" の順に
	# なっているはずで、討伐直後は強制帰還判定へ進めない。実行順序をソースで直接確かめる。
	var src := FileAccess.get_file_as_string("res://scripts2d/World2D.gd")
	var vic_i := src.find("_check_victory()   # #159")
	var guard_i := src.find("if _victory_shown:", vic_i)
	guard_i = src.find("return   # #284", guard_i) if guard_i >= 0 else -1
	var armor_i := src.find("if GameState.run_armor <= 0.0:", vic_i)
	armor_i = src.find("_forced_return", armor_i) if armor_i >= 0 else -1
	check(vic_i >= 0, "本編の_check_victory()呼び出しが見つからない")
	check(guard_i > vic_i, "_check_victory()の直後に_victory_shownガードが無い")
	check(armor_i > guard_i, "_victory_shownガードが強制帰還判定より後にある")

	# ボスラッシュ側の大破判定にも _br_won のガードが付いていること
	var br_fail_call_i := src.find("if GameState.run_armor <= 0.0 and not _br_won:")
	check(br_fail_call_i >= 0, "ボスラッシュの大破判定に_br_wonのガードが無い")

	world.free()
	world2.free()

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_284")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
