extends Node
## #281: 旧文明の遺産をドット絵で表現。
## ・pixel/fx_relic.png が存在すること
## ・Relic2D がそれをSprite2Dとして表示すること

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame

	check(ResourceLoader.exists("res://assets/images/pixel/fx_relic.png"), "旧文明の遺産のドット絵が無い")

	var RelicScript = preload("res://scripts2d/Relic2D.gd")
	var r := Area2D.new()
	r.set_script(RelicScript)
	r.setup(300)
	add_child(r)
	await get_tree().process_frame
	var sprite: Sprite2D = r.get("_sprite")
	check(sprite != null, "遺産にドット絵のSprite2Dが付いていない")
	if sprite != null:
		check(sprite.texture != null, "遺産のスプライトにテクスチャが無い")
	r.queue_free()

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK relic_pixel_art")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
