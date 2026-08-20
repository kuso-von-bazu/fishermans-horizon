extends Node
## 武器の性能一覧を実データから書き出す(#260)
## 使い方: godot --headless tools/武器一覧.tscn
func _ready() -> void:
	await get_tree().process_frame
	var out := "| 武器 | 種別 | 単発火力 | 連射間隔(秒) | 毎秒火力 | 弾数 | リロード(秒) | 1弾倉の総火力 | 射程 | 価格 | 販売島 |\n"
	out += "|---|---|---|---|---|---|---|---|---|---|---|\n"
	for wid in Database.weapons:
		var w: Dictionary = Database.weapons[wid]
		var dmg := float(w.dmg)
		var cd := float(w.cooldown)
		var mag := int(w.mag)
		var rl := float(w.reload)
		var dps := dmg / maxf(cd, 0.0001)
		var mag_total := dmg * float(mag)
		# 弾倉を撃ち切ってリロードするまでの実効毎秒火力
		var cycle := cd * float(mag) + rl
		var sustained := mag_total / maxf(cycle, 0.0001)
		var where := "全島"
		if w.has("only_island"):
			where = str(Database.island(int(w.only_island)).name) + "のみ"
		elif int(w.get("tier", 0)) > 0:
			where = "tier%d以上の島" % int(w.get("tier", 0))
		out += "| %s | %s | %.0f | %.2f | %.0f | %d | %.1f | %.0f | %d | %d | %s |\n" % [
			str(w.name), ("エイム" if str(w.kind) == "aim" else "ロックオン"),
			dmg, cd, dps, mag, rl, mag_total, int(w.range), int(w.price), where]
	out += "\n(毎秒火力=単発火力÷連射間隔、1弾倉の総火力=単発火力×弾数)\n"
	out += "\n### 弾倉1本を撃ち切ってリロードし終えるまでの実効毎秒火力\n\n"
	out += "| 武器 | 撃ち切り時間(秒) | +リロード | 実効毎秒火力 |\n|---|---|---|---|\n"
	for wid2 in Database.weapons:
		var w2: Dictionary = Database.weapons[wid2]
		var burst := float(w2.cooldown) * float(int(w2.mag))
		var cyc := burst + float(w2.reload)
		out += "| %s | %.1f | %.1f | %.0f |\n" % [str(w2.name), burst, cyc,
			float(w2.dmg) * float(int(w2.mag)) / maxf(cyc, 0.0001)]
	out += "\n### 衝角\n\n| 衝角 | 攻撃力 | 価格 |\n|---|---|---|\n"
	for rid in Database.rams:
		var r: Dictionary = Database.rams[rid]
		out += "| %s | %d | %d |\n" % [str(r.name), int(r.dmg), int(r.price)]
	var f := FileAccess.open("user://weapons_dump.md", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("DUMP_PATH:", ProjectSettings.globalize_path("user://weapons_dump.md"))
	get_tree().quit(0)
