extends Node
## #265再16: 「すべての実績のバフ効果を現状の2倍にしてください」への対応。
## 対応前の各バフ値(倍率)からのズレ(1.0からの差)を2倍にした値と、
## 現在の Database.achievements の値が一致することを確認する。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

# 対応前(2倍にする前)のバフ値。#265再13時点のDatabase.gdから採取。
const OLD_BUFF := {
	"kill_narwhal": {"reload": 0.9940},
	"kill_seahunter": {"speed": 1.0069},
	"kill_ornithocheirus": {"ram": 1.0079},
	"kill_wyrm": {"shot_dmg": 1.0088},
	"kill_wyvern": {"shot_speed": 1.0098},
	"kill_kraken": {"flag_dmg_taken": 0.9893},
	"kill_starfish": {"fleet_dmg_taken": 0.9883},
	"kill_zaratan": {"reload": 0.9874},
	"kill_mermaid": {"speed": 1.0136},
	"kill_lamia": {"ram": 1.0145},
	"kill_zombie_fish": {"shot_dmg": 1.0155},
	"kill_moon_jelly": {"shot_speed": 1.0164},
	"kill_killer_shell": {"flag_dmg_taken": 0.9826},
	"kill_carabos": {"fleet_dmg_taken": 0.9817},
	"kill_merman": {"reload": 0.9807},
	"kill_charybdis": {"speed": 1.0202},
	"kill_amphiptere": {"ram": 1.0212},
	"kill_dagon": {"shot_dmg": 1.0221},
	"kill_zahhak": {"shot_speed": 1.0231},
	"kill_tiamat": {"flag_dmg_taken": 0.9760},
	"bounty_hunter": {"shot_dmg": 1.0080},
	"lord_sawshark": {"reload": 0.9960},
	"lord_dumbo": {"speed": 1.0045},
	"lord_whale": {"ram": 1.0051},
	"lord_walrus": {"shot_dmg": 1.0056},
	"lord_aspidochelone": {"shot_speed": 1.0061},
	"lord_legion": {"flag_dmg_taken": 0.9933},
	"lord_undine": {"fleet_dmg_taken": 0.9928},
	"lord_siren": {"reload": 0.9923},
	"lord_night_emperor": {"speed": 1.0083},
	"lord_wraith": {"ram": 1.0088},
	"lord_kraken_lord": {"shot_dmg": 1.0093},
	"lord_griffon": {"shot_speed": 1.0099},
	"lord_hydra": {"flag_dmg_taken": 0.9896},
	"lord_quetzal": {"fleet_dmg_taken": 0.9891},
	"lord_gemini": {"reload": 0.9889},
	"lord_reaper": {"speed": 1.0110},
	"lord_ghost": {"reload": 0.9885},
	"lord_leviathan": {"speed": 1.0120},
	"charge_all": {"ram": 1.0150},
	"weapon_master": {"shot_dmg": 1.0140},
	"mixed_fleet": {"speed": 1.0130},
	"battle_fleet": {"fleet_dmg_taken": 0.9880},
	"master_one": {"shot_speed": 1.0130},
	"master_all": {"reload": 0.9800},
	"fame_max": {"shot_dmg": 1.0300},
	"rich": {"flag_dmg_taken": 0.9800},
	"all_fish": {"speed": 1.0060},
	"relic100": {"reload": 0.9960},
	"true_sea_ruler": {"reload": 0.9850, "speed": 1.0150, "ram": 1.0150, "shot_dmg": 1.0200, "shot_speed": 1.0200, "flag_dmg_taken": 0.9800, "fleet_dmg_taken": 0.9850},
	"ultimate_player": {"reload": 0.9800, "speed": 1.0200, "ram": 1.0210, "shot_dmg": 1.0300, "shot_speed": 1.0230, "flag_dmg_taken": 0.9760, "fleet_dmg_taken": 0.9820},
}

func _ready() -> void:
	check(Database.achievements.size() == OLD_BUFF.size(), "実績数がテスト前提(%d件)と一致しない(%d件)" % [OLD_BUFF.size(), Database.achievements.size()])

	for a in Database.achievements:
		var aid: String = str(a.id)
		if not OLD_BUFF.has(aid):
			check(false, "%s の対応前バフ値がテストに登録されていない" % aid)
			continue
		var old_buff: Dictionary = OLD_BUFF[aid]
		var new_buff: Dictionary = a.get("buff", {})
		check(new_buff.size() == old_buff.size(), "%s のバフのステータス数が変わっている" % aid)
		for key in old_buff.keys():
			var old_v: float = old_buff[key]
			var expect: float = 1.0 + (old_v - 1.0) * 2.0
			var actual: float = float(new_buff.get(key, -1.0))
			check(absf(actual - expect) < 0.0001,
				"%s.%s: 期待値%.4f(旧%.4fの2倍)に対し実際は%.4f" % [aid, key, expect, old_v, actual])

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK issue_265_re12_all_buffs_doubled")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
