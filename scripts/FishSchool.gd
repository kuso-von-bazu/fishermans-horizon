extends Node3D
const Models = preload("res://scripts/Models.gd")
## FishSchool — 魚群。複数の立体魚が群れて泳ぐ。近づいて漁(interact長押し)で漁獲する。

var fish_id: String = "sardine"
var remaining: int = 5
var fish_timer: float = 0.0
const FISH_TIME := 0.7
var label: Label3D
var _fishes: Array = []      # {node, base:Vector3, phase:float}
var _t: float = 0.0

func setup(id: String, count: int) -> void:
	fish_id = id
	remaining = count

func _ready() -> void:
	add_to_group("fishable")
	add_to_group("sonar_fish")
	var def: Dictionary = Database.fish_def(fish_id)
	var col: Color = def.get("color", Color(0.6, 0.7, 0.85))
	var rare: bool = def.get("rare", false)
	var fish_len: float = 1.6 if def.cap >= 3 else (1.2 if def.cap == 2 else 0.9)
	if rare:
		fish_len = 1.8
	# 群れ(レア魚は1匹、それ以外は複数)
	var n: int = 1 if rare else clampi(remaining, 3, 7)
	for i in n:
		var f := Models.fish(col, fish_len)
		var base := Vector3(randf_range(-2.5, 2.5), randf_range(-0.6, 0.6), randf_range(-2.5, 2.5))
		f.position = base
		f.rotation.y = randf() * TAU
		add_child(f)
		_fishes.append({"node": f, "base": base, "phase": randf() * TAU})
	label = Label3D.new()
	label.text = "%s 群れ" % def.get("name", fish_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.6
	label.modulate = Color(0.9, 1.0, 1.0)
	label.outline_size = 6
	label.font_size = 32
	label.no_depth_test = true
	add_child(label)

func _process(delta: float) -> void:
	_t += delta
	for fd in _fishes:
		var node: Node3D = fd.node
		if not is_instance_valid(node):
			continue
		# ゆらゆら遊泳: 円を描きつつ上下に揺れる
		var ph: float = fd.phase
		var off := Vector3(sin(_t * 0.8 + ph) * 0.6, sin(_t * 1.6 + ph) * 0.25, cos(_t * 0.8 + ph) * 0.6)
		node.position = fd.base + off
		node.rotation.y += delta * 0.8

func try_fish(delta: float) -> String:
	if remaining <= 0:
		return ""
	fish_timer += delta
	if fish_timer >= FISH_TIME:
		fish_timer = 0.0
		remaining -= 1
		# 獲られた分、見た目の魚を減らす
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
