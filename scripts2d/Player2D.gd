extends CharacterBody2D
## Player2D — 見下ろし2Dのプレイヤー船。戦車的操作(W/S前後・A/D旋回)。
## rotation=0 で船首は上(-Y)。forward = Vector2.UP.rotated(rotation)。
## 照準はマウスカーソル位置(World2D側で取得)。

const K := 6.0   # 3D数値→2D píxel換算(速度など)

var max_speed: float = 66.0
var accel: float = 40.0
var turn_speed: float = 1.2
var control_enabled: bool = true
var entanglers: Array = []   # #69/#72: 絡めてきた敵。討伐(無効化)まで鈍足
var _ram_cd: float = 0.0
var _wake: CPUParticles2D
var _flame: CPUParticles2D   # #136: 炎上アニメ
var _sc: float = 1.0
var _body_pts: PackedVector2Array

func _ready() -> void:
	add_to_group("player")
	max_speed = float(GameState.ship().speed) * K
	_build_visual()

# 蒸気船のドット絵(#28)。真上から見た16x30。文字→色のピクセルマップ。
# H=鉄殻 h=鉄殻明 D=甲板 F=煙突 R=赤帯 W=白トリム B=橋 .=透明
const SHIP_MAP := [
	"......HHHH......",
	".....HhhhhH.....",
	"....HhDDDDhH....",
	"...HhDDDDDDhH...",
	"..HhDDWWWWDDhH..",
	"..HhDWDDDDWDhH..",
	".HhDDWDBBDWDDhH.",
	".HhDDWDBBDWDDhH.",
	".HhDDWDDDDWDDhH.",
	".HhDDDFFFFDDDhH.",
	".HhDDFFRRFFDDhH.",
	".HhDDFFRRFFDDhH.",
	".HhDDDFFFFDDDhH.",
	".HhDDDDDDDDDDhH.",
	".HhDDWWWWWWDDhH.",
	".HhDDWDDDDWDDhH.",
	".HhDDWDDDDWDDhH.",
	".HhDDWWWWWWDDhH.",
	".HhDDDDDDDDDDhH.",
	".HhDDDDDDDDDDhH.",
	".HhhDDDDDDDDhhH.",
	"..HhDDDDDDDDhH..",
	"..HhhDDDDDDhhH..",
	"...HhhDDDDhhH...",
	"....HhhhhhhH....",
	".....HHHHHH.....",
]
const PIX := {
	"H": Color(0.16, 0.18, 0.22), "h": Color(0.32, 0.35, 0.40),
	"D": Color(0.58, 0.46, 0.32), "F": Color(0.10, 0.10, 0.12),
	"R": Color(0.75, 0.20, 0.15), "W": Color(0.85, 0.85, 0.80),
	"B": Color(0.35, 0.55, 0.62),
	"G": Color(0.30, 0.33, 0.36), "Y": Color(0.80, 0.66, 0.25),  # G=砲鉄 Y=積荷
	"g": Color(0.30, 0.55, 0.35), "P": Color(0.45, 0.30, 0.18),  # g=緑帯 P=古木
}

# #130: 船ごとに描き分けたドット絵(見た目を差別化)。未定義はSHIP_MAP(弩級)。
const SHIP_MAPS := {
	# 粗末な漁船: 小さな木の筏(煙突なし・古木)
	"raft": [
		"...PPPP...",
		"..PDDDDP..",
		".PDDDDDDP.",
		".PDWDDWDP.",
		".PDDDDDDP.",
		".PDDDDDDP.",
		".PDWDDWDP.",
		".PDDDDDDP.",
		"..PDDDDP..",
		"...PPPP...",
	],
	# 武装スキフ: 小型・船首に砲1門
	"skiff": [
		"...HHHH...",
		"..HhGGhH..",
		".HhDDDDhH.",
		".HhDWWDhH.",
		".HhDWWDhH.",
		".HhDFFDhH.",
		".HhDRRDhH.",
		".HhDDDDhH.",
		".HhDDDDhH.",
		"..HhDDhH..",
		"..HhDDhH..",
		"...HHHH...",
	],
	# 外洋カッター: すらりとした船体・単煙突・尖った船首
	"cutter": [
		"....HH....",
		"...HhhH...",
		"..HhWWhH..",
		"..HhDDhH..",
		".HhDWWDhH.",
		".HhDBBDhH.",
		".HhDFFDhH.",
		".HhDRRDhH.",
		".HhDFFDhH.",
		".HhDDDDhH.",
		".HhDWWDhH.",
		".HhDDDDhH.",
		"..HhDDhH..",
		"..HhhhH...",
		"...HHH....",
	],
	# コルベット: 軍艦・双煙突・舷側砲
	"corvette": [
		"....HHHH....",
		"...HhhhhH...",
		"..HhDWWDhH..",
		".HhGDWWDGhH.",
		".HhDDBBDDhH.",
		".HhDFFFFDhH.",
		".HhDFRRFDhH.",
		".HhGDFFDGhH.",
		".HhDDWWDDhH.",
		".HhDDDDDDhH.",
		".HhGDDDDGhH.",
		"..HhDDDDhH..",
		"..HhhDDhhH..",
		"...HhhhhH...",
		"....HHHH....",
	],
	# 猟特化フリゲート: 細長い・緑帯・銛座
	"hunter_h": [
		"....GG....",
		"...HggH...",
		"..HhgghH..",
		"..HhDDhH..",
		".HhDggDhH.",
		".HhDWWDhH.",
		".HhDFFDhH.",
		".HhDggDhH.",
		".HhDFFDhH.",
		".HhDWWDhH.",
		".HhDggDhH.",
		".HhDDDDhH.",
		"..HhDDhH..",
		"..HhgghH..",
		"...HggH...",
		"....HH....",
	],
	# 大型運搬艦: 幅広・積荷(黄)コンテナ・ずんぐり
	"hauler": [
		"..HHHHHHHH..",
		".HhhhhhhhhH.",
		".HhDDDDDDhH.",
		".HhYYDDYYhH.",
		".HhYYDDYYhH.",
		".HhDDFFDDhH.",
		".HhDDRRDDhH.",
		".HhYYDDYYhH.",
		".HhYYDDYYhH.",
		".HhDDDDDDhH.",
		".HhhDDDDhhH.",
		"..HHHHHHHH..",
	],
}

func _build_ship_texture(with_ram: bool, ram_steel: bool) -> ImageTexture:
	var map: Array = SHIP_MAPS.get(GameState.ship_id, SHIP_MAP)   # #130: 船ごとの絵
	var w: int = map[0].length()
	var h := map.size()
	var ram_rows := 6 if with_ram else 0
	var img := Image.create(w, h + ram_rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 衝角(#36/#43): 船首(進行方向)に尖った二等辺三角形
	if with_ram:
		var rc := Color(0.78, 0.82, 0.88) if ram_steel else Color(0.5, 0.46, 0.4)
		var cx := w / 2
		for ry in ram_rows:
			# ry=0(先端)は幅1、下へ行くほど広がる二等辺三角形
			var half: int = int(round(float(ry) / float(ram_rows - 1) * 3.0))
			for x in range(cx - half - 1, cx + half + 1):
				if x >= 0 and x < w:
					img.set_pixel(x, ry, rc)
	for y in h:
		var row: String = map[y]
		for x in w:
			var ch := row[x]
			if PIX.has(ch):
				img.set_pixel(x, y + ram_rows, PIX[ch])
	return ImageTexture.create_from_image(img)

func _build_visual() -> void:
	var sc := _ship_scale()
	_sc = sc
	var with_ram: bool = GameState.ram_id != "none"
	var sprite := Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = _build_ship_texture(with_ram, GameState.ram_id == "steel")
	sprite.scale = Vector2.ONE * 3.4 * sc
	add_child(sprite)
	# 衝突形状
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 13.0 * sc
	cap.height = 60.0 * sc
	col.shape = cap
	add_child(col)
	# 煙突の煙(蒸気らしくゆったり・遠ざかるほど薄く消える #131)
	var smoke := CPUParticles2D.new()
	smoke.amount = 18
	smoke.lifetime = 3.4
	smoke.local_coords = false          # 世界座標に残してたなびかせる
	smoke.position = Vector2(0, -6 * sc)
	smoke.direction = Vector2(0, 1)
	smoke.spread = 18.0
	smoke.initial_velocity_min = 3.0    # ゆっくり噴き上がる
	smoke.initial_velocity_max = 9.0
	smoke.damping_min = 3.0             # だんだん失速
	smoke.damping_max = 6.0
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 5.0
	var scurve := Curve.new()           # 遠ざかる(時間経過)ほど大きく広がる
	scurve.add_point(Vector2(0.0, 0.6))
	scurve.add_point(Vector2(1.0, 2.2))
	smoke.scale_amount_curve = scurve
	var sramp := Gradient.new()         # 遠ざかるほど薄く消える
	sramp.set_color(0, Color(0.88, 0.88, 0.9, 0.45))
	sramp.set_color(1, Color(0.9, 0.9, 0.92, 0.0))
	smoke.color_ramp = sramp
	add_child(smoke)
	# 航跡(#132: 船幅に応じた幅+通過経路に残る)。世界座標に残す
	_wake = CPUParticles2D.new()
	_wake.amount = 64
	_wake.lifetime = 3.2
	_wake.local_coords = false
	_wake.position = Vector2(0, 42 * sc)
	_wake.direction = Vector2(0, 1)
	_wake.spread = 8.0
	_wake.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_wake.emission_rect_extents = Vector2(11.0 * sc, 2.0)   # 船幅に応じた幅
	_wake.initial_velocity_min = 4.0
	_wake.initial_velocity_max = 14.0
	_wake.damping_min = 2.0
	_wake.damping_max = 4.0
	_wake.scale_amount_min = 2.5
	_wake.scale_amount_max = 6.0
	var wramp := Gradient.new()
	wramp.set_color(0, Color(0.9, 0.97, 1.0, 0.5))
	wramp.set_color(1, Color(0.9, 0.97, 1.0, 0.0))
	_wake.color_ramp = wramp
	add_child(_wake)
	# #136: 炎上アニメ(炎上中のみ噴く。船上で揺らめく炎)
	_flame = CPUParticles2D.new()
	_flame.amount = 22
	_flame.lifetime = 0.7
	_flame.emitting = false
	_flame.position = Vector2(0, 0)
	_flame.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_flame.emission_rect_extents = Vector2(14.0 * sc, 22.0 * sc)
	_flame.direction = Vector2(0, -1)
	_flame.gravity = Vector2(0, -80)
	_flame.spread = 20.0
	_flame.initial_velocity_min = 20.0
	_flame.initial_velocity_max = 50.0
	_flame.scale_amount_min = 2.0
	_flame.scale_amount_max = 5.0
	var framp := Gradient.new()
	framp.set_color(0, Color(1.0, 0.85, 0.35, 0.9))
	framp.set_color(1, Color(0.7, 0.15, 0.05, 0.0))
	_flame.color_ramp = framp
	_flame.z_index = 5
	add_child(_flame)
	for side in [-1.0, 1.0]:
		var spray := CPUParticles2D.new()
		spray.amount = 16
		spray.lifetime = 0.8
		spray.position = Vector2(side * 12 * sc, -20 * sc)
		spray.direction = Vector2(side, 0.4)
		spray.spread = 30.0
		spray.initial_velocity_min = 20.0
		spray.initial_velocity_max = 46.0
		spray.scale_amount_min = 1.5
		spray.scale_amount_max = 3.5
		spray.color = Color(0.95, 1.0, 1.0, 0.4)
		add_child(spray)

func _ship_scale() -> float:
	return clampf(0.9 + float(GameState.ship().armor) / 1500.0, 0.9, 1.8)

func rebuild_visual() -> void:
	for c in get_children():
		c.queue_free()
	max_speed = float(GameState.ship().speed) * K
	_build_visual()

func forward() -> Vector2:
	return Vector2.UP.rotated(rotation)

# #69/#72: 触腕持ちの敵に絡めとられた(討伐まで鈍足)
func add_entangler(e: Node) -> void:
	if not entanglers.has(e):
		entanglers.append(e)
		GameState.notice.emit("触腕に絡めとられた! 討伐するまで速度低下")

func _physics_process(delta: float) -> void:
	if _ram_cd > 0.0:
		_ram_cd -= delta
	if not control_enabled:
		velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
		move_and_slide()
		return
	var throttle := 0.0
	var steer := 0.0
	if Input.is_action_pressed("throttle_up"):
		throttle += 1.0
	if Input.is_action_pressed("throttle_down"):
		throttle -= 0.6
	if Input.is_action_pressed("turn_left"):
		steer -= 1.0
	if Input.is_action_pressed("turn_right"):
		steer += 1.0
	# #69/#72: 触腕に絡めとられている間は最高速度が下がる(相手の討伐で解除)
	entanglers = entanglers.filter(func(e): return is_instance_valid(e))
	var eff_max: float = max_speed * (0.55 if not entanglers.is_empty() else 1.0)
	var spd := velocity.length()
	var steer_factor: float = clampf(spd / maxf(eff_max, 1.0), 0.2, 1.0)
	rotation += steer * turn_speed * steer_factor * delta
	velocity = velocity.move_toward(forward() * throttle * eff_max, accel * delta)
	move_and_slide()
	if _flame:
		_flame.emitting = GameState.burn_t > 0.0   # #136: 炎上中だけ炎
	if _wake:
		_wake.emitting = spd > max_speed * 0.15
		# #132: バック時は船の前方に航跡が残る
		var reversing := velocity.dot(forward()) < -1.0
		_wake.position = Vector2(0, -44 * _sc) if reversing else Vector2(0, 42 * _sc)
		_wake.direction = Vector2(0, -1) if reversing else Vector2(0, 1)
	_handle_ram()

func _handle_ram() -> void:
	if _ram_cd > 0.0:
		return
	if GameState.docking_locked:
		return   # #101: 大破/寄港確定後は衝角も無効
	var rd := float(Database.rams[GameState.ram_id].dmg)
	if rd <= 0.0 or velocity.length() < 3.0 * K:
		return
	for i in get_slide_collision_count():
		var col = get_slide_collision(i).get_collider()
		if col and col.is_in_group("enemy") and col.has_method("take_hit"):
			if col.get("aerial") == true:
				continue   # #56: 空中の敵(オルニケイトス等)に衝角は届かない
			var ram_dmg := rd * (0.5 + velocity.length() / maxf(max_speed, 1.0))
			col.take_hit(ram_dmg, false, false)
			# #54: 突撃の手応え(通知+ノックバック+強い音)
			GameState.notice.emit("衝角の一撃! %d ダメージ" % int(ram_dmg))
			if col is CharacterBody2D:
				col.velocity += velocity.normalized() * 220.0
			Audio.play("sfx_cannon", -6.0, 1.3)
			_ram_cd = 0.8
			return
