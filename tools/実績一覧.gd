extends Node
## 実績とバッヂ効果の一覧を実データから書き出す(#265)
## 使い方: godot --headless tools/実績一覧.tscn
const PortS = preload("res://scripts/PortUI.gd")

func buff_text(a: Dictionary) -> String:
	var buff: Dictionary = a.get("buff", {})
	for k in buff:
		var v := float(buff[k])
		var pct: float = absf(v - 1.0) * 100.0
		match str(k):
			"reload":
				return "船団のリロード時間 -%.1f%%" % pct
			"speed":
				return "前進最高速 +%.1f%%" % pct
			"ram":
				return "衝角・体当たりダメージ +%.1f%%" % pct
			"shot_dmg":
				return "遠隔攻撃ダメージ +%.1f%%" % pct
			"shot_speed":
				return "弾速 +%.1f%%" % pct
			"flag_dmg_taken":
				return "旗艦の被ダメージ -%.1f%%" % pct
			"fleet_dmg_taken":
				return "船団の被ダメージ -%.1f%%" % pct
	return "-"

func buff_pct(a: Dictionary) -> float:
	var buff: Dictionary = a.get("buff", {})
	for k in buff:
		return absf(float(buff[k]) - 1.0) * 100.0
	return 0.0

func _ready() -> void:
	await get_tree().process_frame
	var group_names := {
		"kill": "(1) 討伐数による実績",
		"lord": "(2) 近海の主の討伐による実績",
		"fleet": "(3) 編成による実績",
		"crew": "(4) クルーの育成による実績",
		"wealth": "(5) 資金・名声による実績",
		"fish": "(6) 漁による実績",
		"relic": "(7) 旧文明の遺物による実績",
	}
	var out := "実績は全%d件。バッヂ効果は陣形のパッシブ(5〜15%%)を大きく下回る 0.4〜3.0%% に収めている。\n" % Database.achievements.size()
	for g in group_names:
		var rows: Array = []
		for a in Database.achievements:
			if str(a.group) == str(g):
				rows.append(a)
		if rows.is_empty():
			continue
		var lo := 999.0
		var hi := 0.0
		for r in rows:
			lo = minf(lo, buff_pct(r))
			hi = maxf(hi, buff_pct(r))
		out += "\n## %s (%d件 / 効果 %.1f%%〜%.1f%%)\n\n" % [str(group_names[g]), rows.size(), lo, hi]
		out += "| # | 実績 | 達成条件 | バッヂ効果 | バッヂの絵 |\n|---|---|---|---|---|\n"
		var i := 0
		for r2 in rows:
			i += 1
			var icon := str(r2.get("icon", ""))
			var icon_txt := "専用の絵"
			if icon.contains("/mob_") or icon.contains("/lord_") or icon.contains("/pirate_"):
				icon_txt = "その敵のドット絵"
			out += "| %d | %s | %s | %s | %s |\n" % [i, str(r2.name), str(r2.desc), buff_text(r2), icon_txt]
	out += "\n## 効果の大きさの並び(最大値で比較)\n\n"
	out += "| グループ | 最大の効果 |\n|---|---|\n"
	for g2 in group_names:
		var hi2 := 0.0
		for a2 in Database.achievements:
			if str(a2.group) == str(g2):
				hi2 = maxf(hi2, buff_pct(a2))
		if hi2 > 0.0:
			out += "| %s | %.1f%% |\n" % [str(group_names[g2]), hi2]
	out += "\n参考: 陣形のパッシブは 単横陣リロード-10% / 単縦陣速度+5% / 鋒矢陣衝角+15% /"
	out += " 鶴翼陣遠隔+10% / 斜線陣弾速+10% / 輪形陣旗艦被ダメ-10%。\n"
	var f := FileAccess.open("user://achievements_dump.md", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("DUMP_PATH:", ProjectSettings.globalize_path("user://achievements_dump.md"))
	get_tree().quit(0)
