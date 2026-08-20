extends Node2D
## LosOverlay2D — #256: 旗艦の射線が僚艦に遮られていることを画面上で伝える。
## ・遮っている僚艦を赤く縁取る
## ・旗艦から僚艦までの射線を赤い破線で描く
## ・マウス位置に赤い照準を出す(撃つ前に分かる)
## 判定そのものは World2D 側が持ち、ここは受け取った結果を描くだけ。

var blocker: Node2D = null      # 射線を遮っている僚艦(なければ null)
var origin: Vector2 = Vector2.ZERO   # 旗艦の位置
var aim: Vector2 = Vector2.ZERO      # マウス位置

func set_state(p_blocker: Node2D, p_origin: Vector2, p_aim: Vector2) -> void:
	blocker = p_blocker
	origin = p_origin
	aim = p_aim
	queue_redraw()

func _draw() -> void:
	if blocker == null or not is_instance_valid(blocker):
		return
	var red := Color(1.0, 0.25, 0.2, 0.85)
	# 旗艦 → 遮っている僚艦 の赤い破線
	var to: Vector2 = blocker.global_position - origin
	var d := to.length()
	if d > 1.0:
		var dir := to / d
		var seg := 14.0
		var t := 0.0
		while t < d:
			var a: Vector2 = origin + dir * t
			var b: Vector2 = origin + dir * minf(t + seg * 0.55, d)
			draw_line(a, b, red, 2.0)
			t += seg
	# 遮っている僚艦の赤い縁取り
	draw_arc(blocker.global_position, 44.0, 0.0, TAU, 32, red, 3.0)
	# マウス位置の赤い照準(撃つ前に「撃てない」と分かる)
	draw_arc(aim, 13.0, 0.0, TAU, 24, red, 2.0)
	for s in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(aim + s * 7.0, aim + s * 19.0, red, 2.0)
