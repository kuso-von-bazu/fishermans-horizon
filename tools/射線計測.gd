extends Node
## 射線遮断の発生率を陣形×艦数で実測する(コンサルレポート②の根拠)
## 使い方: godot --headless tools/射線計測.tscn
const World2 = preload("res://scripts2d/World2D.gd")

func blocked(offs: Array, n: int, dir: Vector2, dist: float) -> bool:
	for i in n:
		var rel: Vector2 = offs[i]
		var along := rel.dot(dir)
		if along <= 0.0 or along > dist:
			continue
		if absf(rel.cross(dir)) < 46.0:
			return true
	return false

func _ready() -> void:
	await get_tree().process_frame
	var names := {"line":"単横陣","column":"単縦陣","vee":"鋒矢陣","inv_vee":"鶴翼陣","echelon":"斜線陣","ring":"輪形陣"}
	for wid in ["gatling","cannon","harpoon"]:
		var rng: float = float(Database.weapons[wid].range) * 6.0 * 1.2
		print("PROBE === %s 射程%.0f ===" % [str(Database.weapons[wid].name), rng])
		for key in World2.FORMATION_OFFSETS:
			var offs: Array = World2.FORMATION_OFFSETS[key]
			var line := "PROBE %-6s" % str(names.get(key, key))
			for n in [1, 2, 3, 4]:
				var hit := 0
				var total := 720
				for i in total:
					var a := TAU * float(i) / float(total)
					if blocked(offs, n, Vector2.RIGHT.rotated(a), rng):
						hit += 1
				line += "  %d艦:%4.1f%%" % [n + 1, 100.0 * float(hit) / float(total)]
			print(line)
	get_tree().quit(0)
