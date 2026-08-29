extends RefCounted
## Juice2D — #278(提案4/提案6): 打撃感と夜の光の共通ヘルパー。
##
## ・撃破の破片(その敵のドット絵から拾った色の矩形パーティクル)
## ・砲口炎・爆発・炎上中の敵に付ける PointLight2D(夜の海域だけ)
##
## 光は「弾1発ごと」に付けると負荷も画面のうるささも跳ね上がるので、
## 同時に出せる数と発生間隔をここで絞る。

# 光のテクスチャ(中心が白く外へ向かって透明になる円)。使い回すので一度だけ作る
static var _light_tex: Texture2D = null
# 破片の粒(白い正方形)。テクスチャを与えないと環境によっては描画されないので必ず持たせる
static var _square_tex: Texture2D = null
# 同時に存在する一時的な光の数と、直近の発生時刻(ミリ秒)
static var _glow_count: int = 0
static var _last_glow_ms: int = 0
const MAX_GLOW := 8          # 同時に出せる一時的な光
const GLOW_INTERVAL_MS := 55 # 砲口炎の最短間隔(ガトリングで光が埋まらないように)

static func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_light_tex = t
	return _light_tex

static func square_texture() -> Texture2D:
	if _square_tex == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_square_tex = ImageTexture.create_from_image(img)
	return _square_tex

# 航行中の海域が夜(月下・星霜・常闇)かどうか。夜以外では光を出さない
static func night_sea(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var w := node.get_tree().get_first_node_in_group("world2d")
	return w != null and w.has_method("is_night_sea") and w.is_night_sea()

static func make_light(color: Color, energy: float, radius: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = light_texture()
	l.color = color
	l.energy = energy
	l.texture_scale = radius / 64.0   # テクスチャは128px角(半径64)
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.z_index = 6
	return l

# 一瞬だけ光る(砲口炎・爆発)。夜の海域でのみ、数と間隔を絞って出す。
static func glow(parent: Node, pos: Vector2, color: Color, energy: float, radius: float, dur: float, throttle := true) -> void:
	if parent == null or not parent.is_inside_tree() or not night_sea(parent):
		return
	var now := Time.get_ticks_msec()
	if throttle and (now - _last_glow_ms < GLOW_INTERVAL_MS or _glow_count >= MAX_GLOW):
		return
	_last_glow_ms = now
	_glow_count += 1
	var l := make_light(color, energy, radius)
	parent.add_child(l)
	l.global_position = pos
	var tw := parent.get_tree().create_tween()
	tw.tween_property(l, "energy", 0.0, dur)
	tw.tween_callback(func():
		_glow_count -= 1
		if is_instance_valid(l):
			l.queue_free())

# #278(提案4): 撃破の破片。敵のドット絵から色を拾った矩形の粒を飛ばす。
# 煙・航跡と同じ「大きなドット」(scale 3〜8)の流儀に合わせている。
static func debris(parent: Node, pos: Vector2, tex: Texture2D, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var cols := sample_colors(tex)
	for i in cols.size():
		var p := CPUParticles2D.new()
		p.texture = square_texture()   # 8px角の白い正方形=ドット絵の破片
		p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 10
		p.lifetime = 0.55
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = radius * 0.6
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = radius * 2.0
		p.initial_velocity_max = radius * 6.0
		p.damping_min = radius * 2.0
		p.damping_max = radius * 5.0
		p.scale_amount_min = 0.5   # 8px角 × 0.5〜1.1 = 4〜9px の粒
		p.scale_amount_max = 1.1
		p.spread = 180.0           # 全方位へ散る
		p.direction = Vector2(0, -1)
		var g := Gradient.new()
		var c: Color = cols[i]
		g.set_color(0, Color(c.r, c.g, c.b, 1.0))
		g.set_color(1, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, 0.0))
		p.color_ramp = g
		p.z_index = 4
		parent.add_child(p)
		p.global_position = pos
		p.emitting = true   # ツリーに入れて位置を決めてから噴かせる
		var t := parent.get_tree().create_timer(1.2)
		t.timeout.connect(func(): if is_instance_valid(p): p.queue_free())

# ドット絵から代表色を数点拾う(不透明な画素だけ・明るい順)
static func sample_colors(tex: Texture2D, want := 3) -> Array:
	var out: Array = []
	if tex == null:
		return [Color(0.9, 0.9, 0.9)]
	var img := tex.get_image()
	if img == null:
		return [Color(0.9, 0.9, 0.9)]
	var w := img.get_width()
	var h := img.get_height()
	var found: Array = []
	var step := maxi(1, int(min(w, h) / 12))
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a > 0.6 and (c.r + c.g + c.b) > 0.15:
				found.append(c)
	if found.is_empty():
		return [Color(0.9, 0.9, 0.9)]
	found.sort_custom(func(a, b): return (a.r + a.g + a.b) > (b.r + b.g + b.b))
	# 明るい方・中ほど・暗い方から1つずつ拾って色幅を持たせる
	for i in want:
		out.append(found[mini(int(float(found.size() - 1) * float(i) / maxf(float(want - 1), 1.0)), found.size() - 1)])
	return out
