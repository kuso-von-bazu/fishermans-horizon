extends Node
## 船の性能一覧を実データから書き出す(#266)
## 使い方: godot --headless tools/船性能一覧.tscn
const PlayerS = preload("res://scripts2d/Player2D.gd")

func _ready() -> void:
	await get_tree().process_frame
	var out := "| 船 | 装甲 | 燃料 | 魚倉 | 武器スロット | 衝角 | 速度 | 後退 | 見た目の倍率 | 価格 | 下取り | 解禁される島 |\n"
	out += "|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for sid in Database.ships:
		var d: Dictionary = Database.ships[sid]
		# 解禁: range=販売が始まる島のtier。SHOP_ONLY/SHOP_EXCLUDE で個別に外れる島もある
		var unlock := "最初から"
		var r := int(d.get("range", 0))
		if r > 0:
			for isle in Database.islands_in_order():
				if Database.tier_of(int(isle.id)) >= r and Database.shop_has_ship(int(isle.id), sid):
					unlock = str(isle.name) + "から"
					break
		# 見た目の倍率(Player2D._ship_scale と同じ式)
		var extra := 1.0
		if sid == "cruiser":
			extra = 1.15
		elif sid == "dread":
			extra = 0.76
		var scale: float = clampf(0.9 + float(d.armor) / 1500.0, 0.9, 1.8) * extra
		out += "| %s | %d | %d | %d | %d | %s | %.1f | %s | %.2f | %d | %d | %s |\n" % [
			str(d.name), int(d.armor), int(d.food), int(d.hold), int(d.slots),
			("○" if int(d.slots) > 0 else "-"),
			float(d.speed),
			("速い(0.9)" if d.has("reverse") else "普通"),
			scale, int(d.price), int(d.get("trade", 0)), unlock]

	out += "\n### 販売していない島\n\n"
	for sid2 in Database.ships:
		var miss: Array = []
		for isle2 in Database.islands_in_order():
			var idx := int(isle2.id)
			if Database.tier_of(idx) < int(Database.ships[sid2].get("range", 0)):
				continue   # そもそも解禁前
			if not Database.shop_has_ship(idx, sid2):
				miss.append(str(isle2.name))
		if not miss.is_empty():
			out += "- **%s**: %s では扱っていない\n" % [str(Database.ships[sid2].name), " / ".join(miss)]

	out += "\n### 1隻あたりの費用対効果\n\n"
	out += "| 船 | 価格 | 装甲/1万G | 魚倉/1万G | 速度 | 装甲×速度 |\n|---|---|---|---|---|---|\n"
	for sid3 in Database.ships:
		var d3: Dictionary = Database.ships[sid3]
		var pr := maxf(float(d3.price), 1.0)
		out += "| %s | %d | %.0f | %.1f | %.1f | %.0f |\n" % [str(d3.name), int(d3.price),
			float(d3.armor) / pr * 10000.0, float(d3.hold) / pr * 10000.0,
			float(d3.speed), float(d3.armor) * float(d3.speed)]
	var f := FileAccess.open("user://ships_dump.md", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("DUMP_PATH:", ProjectSettings.globalize_path("user://ships_dump.md"))
	get_tree().quit(0)
