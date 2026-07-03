extends Node2D
## FishSchool2D — 魚群(見下ろし2D)。生成スプライトの魚が回遊。E長押しで漁獲。

var fish_id: String = "sardine"
var remaining: int = 5
var fish_timer: float = 0.0
const FISH_TIME := 0.7
var label: Label
var _fishes: Array = []   # {node, base:Vector2, phase:float}
var _t: float = 0.0

func setup(id: String, count: int) -> void:
	fish_id = id
	remaining = count

func _ready() -> void:
	add_to_group("fishable")
	var def: Dictionary = Database.fish_def(fish_id)
	var rare: bool = def.get("rare", false)
	var tex := _load_tex()
	var n: int = 1 if rare else clampi(remaining, 3, 6)
	var target_w := 34.0 + float(def.cap) * 10.0
	if rare:
		target_w = 60.0
	for i in n:
		var f := Sprite2D.new()
		if tex:
			f.texture = tex
			f.scale = Vector2.ONE * (target_w / maxf(float(tex.get_width()), 1.0))
		else:
			f.texture = _placeholder(def.get("color", Color(0.7, 0.8, 0.9)))
			f.scale = Vector2.ONE * (target_w / 48.0)
		var base := Vector2(randf_range(-34, 34), randf_range(-34, 34))
		f.position = base
		add_child(f)
		_fishes.append({"node": f, "base": base, "phase": randf() * TAU})
	label = Label.new()
	label.text = "%s 群れ" % def.get("name", fish_id)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 1, 1))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.position = Vector2(-60, -74)
	label.custom_minimum_size = Vector2(120, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)

func _load_tex() -> Texture2D:
	var path := "res://assets/images/fish_%s.png" % fish_id
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _placeholder(c: Color) -> Texture2D:
	var img := Image.create(48, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 24:
		for x in 48:
			if absf(x - 24) / 24.0 + absf(y - 12) / 12.0 < 1.0:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	_t += delta
	for fd in _fishes:
		var node: Sprite2D = fd.node
		if not is_instance_valid(node):
			continue
		var ph: float = fd.phase
		var off := Vector2(sin(_t * 0.8 + ph), cos(_t * 0.8 + ph)) * 14.0
		node.position = fd.base + off
		node.flip_h = cos(_t * 0.8 + ph) > 0.0   # 進行方向に応じて左右反転

func try_fish(delta: float) -> String:
	if remaining <= 0:
		return ""
	fish_timer += delta
	if fish_timer >= FISH_TIME:
		fish_timer = 0.0
		remaining -= 1
		if _fishes.size() > 1:
			var last = _fishes.pop_back()
			if is_instance_valid(last.node):
				last.node.queue_free()
		if remaining <= 0:
			label.text = "(枯渇)"
		else:
			label.text = "%s 群れ x%d" % [Database.fish_def(fish_id).get("name", fish_id), remaining]
		return fish_id
	return ""

func depleted() -> bool:
	return remaining <= 0
