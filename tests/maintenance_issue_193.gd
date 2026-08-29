extends Node
## #193再5: 障害物(岩礁・流氷)をドット絵で表現。
## ・pixel/obs_reef.png / pixel/obs_ice.png が存在すること
## ・Obstacle2D が存在するときはそれをSprite2Dとして使い、無いときは従来の_draw代用が効くこと

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	check(ResourceLoader.exists("res://assets/images/pixel/obs_reef.png"), "岩礁のドット絵が無い")
	check(ResourceLoader.exists("res://assets/images/pixel/obs_ice.png"), "流氷のドット絵が無い")

	var ObstacleScript = preload("res://scripts2d/Obstacle2D.gd")
	for kind in ["reef", "ice"]:
		var o := StaticBody2D.new()
		o.set_script(ObstacleScript)
		o.setup(kind)
		add_child(o)
		await get_tree().process_frame
		var sprite: Sprite2D = o.get("_sprite")
		check(sprite != null, "%s にドット絵のSprite2Dが付いていない" % kind)
		if sprite != null:
			check(sprite.texture != null, "%s のスプライトにテクスチャが無い" % kind)
			var tex: Texture2D = sprite.texture
			var longest: float = maxf(float(tex.get_width()), float(tex.get_height()))
			var shown: float = longest * sprite.scale.x
			var r: float = float(o.radius)
			check(absf(shown - r * 2.1) < 0.5, "%s の表示サイズが半径に対して不自然(%.1f vs %.1f)" % [kind, shown, r * 2.1])
		o.queue_free()

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK obstacle_pixel_art")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
