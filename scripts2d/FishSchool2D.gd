extends Node2D
## FishSchool2D — 魚群(見下ろし2D)。生成スプライトの魚が回遊。E長押しで漁獲。

var fish_id: String = "sardine"
var remaining: int = 5
var fish_timer: float = 0.0
const FISH_TIME := 0.7
var label: Label
var _fishes: Array = []   # {node, base:Vector2, phase:float}
var _t: float = 0.0
var _splash: CPUParticles2D   # #213: 網縄漁の水しぶき
var _splash_t: float = 0.0    # 漁をしている間だけ噴かせるための残り時間

func setup(id: String, count: int) -> void:
	fish_id = id
	remaining = count

func _ready() -> void:
	add_to_group("fishable")
	_build_splash()
	var def: Dictionary = Database.fish_def(fish_id)
	var rare: bool = def.get("rare", false)
	var tex := _load_tex()
	var n: int = 1 if rare else clampi(remaining, 3, 6)
	var target_w := 34.0 + float(def.cap) * 10.0
	if rare:
		target_w = 60.0
	for i in n:
		var f := Sprite2D.new()
		f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	# ドット絵版(#26)優先
	var pixel := "res://assets/images/pixel/fish_%s.png" % fish_id
	if ResourceLoader.exists(pixel):
		return load(pixel)
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
	# #213: 漁をしている間だけ水しぶきを出す(やめたら少し余韻を残して止める)
	if _splash_t > 0.0:
		_splash_t -= delta
		if _splash and not _splash.emitting:
			_splash.emitting = true
	elif _splash and _splash.emitting:
		_splash.emitting = false
	for fd in _fishes:
		var node: Sprite2D = fd.node
		if not is_instance_valid(node):
			continue
		var ph: float = fd.phase
		var off := Vector2(sin(_t * 0.8 + ph), cos(_t * 0.8 + ph)) * 14.0
		node.position = fd.base + off
		node.flip_h = cos(_t * 0.8 + ph) > 0.0   # 進行方向に応じて左右反転

# #213: 網縄漁の演出。魚群のまわりにざぶざぶと水しぶきを上げる
func _build_splash() -> void:
	_splash = CPUParticles2D.new()
	_splash.emitting = false
	_splash.amount = 34
	_splash.lifetime = 0.55
	_splash.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_splash.emission_sphere_radius = 46.0
	_splash.direction = Vector2(0, -1)
	_splash.spread = 55.0
	_splash.gravity = Vector2(0, 220.0)     # 上がって落ちる=しぶきらしく
	_splash.initial_velocity_min = 70.0
	_splash.initial_velocity_max = 170.0
	_splash.scale_amount_min = 2.5
	_splash.scale_amount_max = 6.0
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 1.0, 1.0, 0.9))
	g.set_color(1, Color(0.6, 0.85, 0.95, 0.0))
	_splash.color_ramp = g
	_splash.z_index = 3
	add_child(_splash)

func try_fish(delta: float) -> String:
	if remaining <= 0:
		return ""
	_splash_t = 0.18        # #213: 漁の間だけ水しぶきを出す
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
