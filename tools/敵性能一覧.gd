extends Node
## 戦闘モブ・海賊・近海の主の性能一覧を実データから書き出す(#262/#263)
## 使い方: godot --headless tools/敵性能一覧.tscn
const World2 = preload("res://scripts2d/World2D.gd")

## その敵が初めて出現する島(mob_weights を進行順に見て最初に載っている島)
func first_island_of(mob_id: String) -> int:
	for isle in Database.islands_in_order():
		var idx := int(isle.id)
		if idx < Database.mob_weights.size() and Database.mob_weights[idx].has(mob_id):
			return idx
	return -1

## 取り巻きの説明。World2D._spawn_escorts の分岐に対応させる
func escort_text(lord_id: String, isle: int) -> String:
	if bool(Database.lords.get(lord_id, {}).get("no_escort", false)):
		return "なし"
	var fixed := {
		"leviathan": ["zahhak", "tiamat", "dagon"],
		"aspidochelone": ["starfish", "zaratan"],
		"legion": ["starfish", "zaratan"],
		"hydra": ["zahhak", "tiamat"],
		"quetzal": ["zahhak", "tiamat"],
		"kraken_lord": ["zahhak", "tiamat"],
		"griffon": ["zahhak", "tiamat"],
		"undine": ["mermaid", "mermaid"],
		"siren": ["lamia", "lamia"],
	}
	if fixed.has(lord_id):
		var count := {}
		for m in (fixed[lord_id] as Array):
			count[m] = int(count.get(m, 0)) + 1
		var parts: Array = []
		for m2 in count:
			parts.append("%s×%d" % [str(Database.combat_mobs[str(m2)].name), int(count[m2])])
		return " , ".join(parts)
	# それ以外は、その海域の戦闘モブから2体(マーマン・ゾンビウオは除く)
	var pool: Array = []
	if isle < Database.mob_weights.size():
		for k in Database.mob_weights[isle]:
			if str(k) != "merman" and str(k) != "zombie_fish":
				pool.append(str(Database.combat_mobs[str(k)].name))
	return "その海域のモブ2体(%s から)" % " / ".join(pool)

func atk_interval(def: Dictionary, kind: String) -> float:
	return float(def.get("atk_cd", 0.55 if kind == "pirate" else 1.4))

func _ready() -> void:
	await get_tree().process_frame
	var out := "## 戦闘能力があるモブ\n\n"
	out += "| 敵 | 基礎HP | 初出の島 | その島でのHP | 攻撃力 | 攻撃間隔(秒) | 速度 | 遠隔 | 空中 |\n"
	out += "|---|---|---|---|---|---|---|---|---|\n"
	# ザッハーク・ティアマットは指定により果ての島(4)扱い
	var forced := {"zahhak": 4, "tiamat": 4}
	for mid in Database.combat_mobs:
		var d: Dictionary = Database.combat_mobs[mid]
		var isle: int = int(forced.get(mid, first_island_of(mid)))
		var iname := "(未出現)" if isle < 0 else str(Database.island(isle).name)
		var hp := "-" if isle < 0 else str(Database.scaled_hp(float(d.hp), isle))
		out += "| %s | %d | %s | %s | %d | %.2f | %.1f | %s | %s |\n" % [
			str(d.name), int(d.hp), iname, hp, int(d.dmg), atk_interval(d, "mob"),
			float(d.get("speed", 10.0)),
			("○" if bool(d.get("ranged", false)) else "-"),
			("○" if bool(d.get("aerial", false)) else "-")]

	out += "\n## 海賊\n\n"
	out += "| 敵 | 基礎HP | 初出の島 | その島でのHP | 攻撃力 | 攻撃間隔(秒) | 速度 |\n|---|---|---|---|---|---|---|\n"
	# 海賊の格 → その格が最初に出る島
	var pirate_first := {}
	for isle2 in Database.islands_in_order():
		var idx2 := int(isle2.id)
		var top: String = ["raider", "corsair", "dread", "dread", "dread"][Database.tier_of(idx2)]
		if not pirate_first.has(top):
			pirate_first[top] = idx2
	for pid in Database.pirates:
		if pid == "king":
			continue
		var pd: Dictionary = Database.pirates[pid]
		var pi: int = int(pirate_first.get(pid, 0))
		out += "| %s | %d | %s | %d | %d | %.2f | %.1f |\n" % [
			str(pd.name), int(pd.hp), str(Database.island(pi).name),
			Database.scaled_hp(float(pd.hp), pi), int(pd.dmg),
			atk_interval(pd, "pirate"), float(pd.get("speed", 10.0))]

	out += "\n## 海賊王(出現する海域ごと)\n\n"
	out += "| 島 | HP | 攻撃力 | 攻撃間隔(秒) | 速度 | 随伴艦 |\n|---|---|---|---|---|---|\n"
	var kd: Dictionary = Database.pirates["king"]
	var w := Node2D.new()
	w.set_script(World2)
	for isle3 in Database.islands_in_order():
		var idx3 := int(isle3.id)
		var top3: String = w._sea_pirate_top(idx3)
		var rank: int = World2.PIRATE_RANKS.find(top3)
		var names: Array = []
		for r in range(rank + 1):
			names.append(str(Database.pirates[str(World2.PIRATE_RANKS[r])].name))
		out += "| %s | %d | %d | %.2f | %.1f | 必ず1〜3隻。うち1隻は必ず %s、残りは %s から |\n" % [
			str(isle3.name), Database.scaled_hp(float(kd.hp), idx3), int(kd.dmg),
			atk_interval(kd, "pirate"), float(kd.get("speed", 10.0)),
			str(Database.pirates[top3].name), " / ".join(names)]
	w.free()

	out += "\n## 近海の主\n\n"
	out += "| 主 | 島 | その島でのHP | 攻撃力 | 攻撃間隔(秒) | 速度 | 取り巻き |\n|---|---|---|---|---|---|---|\n"
	for isle4 in Database.islands_in_order():
		var idx4 := int(isle4.id)
		for lid in (isle4.get("lords", []) as Array):
			var ld: Dictionary = Database.lords[str(lid)]
			var esc := escort_text(str(lid), idx4)
			var extra := ""
			if bool(ld.get("pair", false)):
				extra = " (番いで2体)"
			out += "| %s%s | %s | %d | %d | %.2f | %.1f | %s |\n" % [
				str(ld.name), extra, str(isle4.name),
				Database.lord_hp(str(lid), idx4), int(ld.dmg),
				atk_interval(ld, "lord"), float(ld.get("speed", 10.0)), esc]
	out += "\n## 島ごとの戦闘能力があるモブの出現割合(#75)\n\n"
	for isle5 in Database.islands_in_order():
		var idx5 := int(isle5.id)
		if idx5 >= Database.mob_weights.size():
			continue
		var parts5: Array = []
		for k5 in Database.mob_weights[idx5]:
			parts5.append("%s %.0f%%" % [str(Database.combat_mobs[str(k5)].name), 100.0 * float(Database.mob_weights[idx5][k5])])
		out += "- **%s**(tier%d): %s\n" % [str(isle5.name), Database.tier_of(idx5), " / ".join(parts5)]
	out += "\n### モブごとの出現する島\n\n| 敵 | 出現する島 |\n|---|---|\n"
	for mid5 in Database.combat_mobs:
		var where5: Array = []
		for isle6 in Database.islands_in_order():
			var idx6 := int(isle6.id)
			if idx6 < Database.mob_weights.size() and Database.mob_weights[idx6].has(mid5):
				where5.append(str(isle6.name))
		out += "| %s | %s |\n" % [str(Database.combat_mobs[mid5].name),
			("(通常出現なし。主の取り巻きのみ)" if where5.is_empty() else " / ".join(where5))]

	var f := FileAccess.open("user://enemies_dump.md", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("DUMP_PATH:", ProjectSettings.globalize_path("user://enemies_dump.md"))
	get_tree().quit(0)
