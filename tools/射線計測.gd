extends Node
## 射線遮断の発生率を陣形×艦数で実測する(コンサルレポート②の根拠)
## 使い方: godot --headless tools/射線計測.tscn
## 出力:
##  (1) 陣形×艦数ごとの「撃てない方位の割合」(現行=判定幅46px・旗艦中心から発射)
##  (2) 改善案の比較: 舷側発射(原点±30px) / 判定幅32px / 併用
const World2 = preload("res://scripts2d/World2D.gd")

func blocked_from(origin: Vector2, offs: Array, n: int, dir: Vector2, half: float, dist: float) -> bool:
	for i in n:
		var rel: Vector2 = (offs[i] as Vector2) - origin
		var along := rel.dot(dir)
		if along <= 0.0 or along > dist:
			continue
		if absf(rel.cross(dir)) < half:
			return true
	return false

## origins: 射線と直交する向きへの発射原点のずらし幅の候補。どれか1つでも通れば発射可
func pct(offs: Array, n: int, half: float, origins: Array, dist: float) -> float:
	var total := 1440
	var hit := 0
	for i in total:
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / float(total))
		var all_blocked := true
		for off in origins:
			if not blocked_from(dir.orthogonal() * float(off), offs, n, dir, half, dist):
				all_blocked = false
				break
		if all_blocked:
			hit += 1
	return 100.0 * float(hit) / float(total)

func _ready() -> void:
	await get_tree().process_frame
	var names := {"line":"単横陣","column":"単縦陣","vee":"鋒矢陣","inv_vee":"鶴翼陣","echelon":"斜線陣","ring":"輪形陣"}
	var dist: float = float(Database.weapons["gatling"].range) * 6.0 * 1.2
	print("PROBE === 現行(判定幅46px・中心発射) 撃てない方位の割合 ===")
	for key in World2.FORMATION_OFFSETS:
		var offs: Array = World2.FORMATION_OFFSETS[key]
		var line := "PROBE %-6s" % str(names.get(key, key))
		for n in [1, 2, 3, 4]:
			line += "  %d艦:%4.1f%%" % [n + 1, pct(offs, n, 46.0, [0.0], dist)]
		print(line)
	print("PROBE === 改善案の比較(5艦) ===")
	print("PROBE %-6s %8s %8s %8s %8s" % ["陣形", "現行46", "舷側±30", "幅32", "併用"])
	for key2 in World2.FORMATION_OFFSETS:
		var offs2: Array = World2.FORMATION_OFFSETS[key2]
		print("PROBE %-6s %7.1f%% %7.1f%% %7.1f%% %7.1f%%" % [str(names.get(key2, key2)),
			pct(offs2, 4, 46.0, [0.0], dist),
			pct(offs2, 4, 46.0, [0.0, 30.0, -30.0], dist),
			pct(offs2, 4, 32.0, [0.0], dist),
			pct(offs2, 4, 32.0, [0.0, 30.0, -30.0], dist)])
	get_tree().quit(0)
