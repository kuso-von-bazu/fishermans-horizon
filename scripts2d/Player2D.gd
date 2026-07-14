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
var _smoke: CPUParticles2D   # #131: 蒸気(移動方向と逆向きに流す)
var _sprays: Array = []      # #144: 舷側のしぶき
var _flame: CPUParticles2D   # #136: 炎上アニメ
var _sc: float = 1.0
var _half_w: float = 30.0    # #132/#144: 船の見た目の半幅(px)
var _half_h: float = 42.0    # #164: 船の見た目の半高(px)。航跡を船尾に隙間なく出すため
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
		"...HhhH...",
		"....HH....",
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
	# 巡洋戦艦: 細長く鋭い船体・単砲塔・後退が得意
	"cruiser": [
		"....HH....",
		"...HhhH...",
		"..HhWWhH..",
		".HhGWWGhH.",
		".HhDBBDhH.",
		".HhDWWDhH.",
		".HhDFFDhH.",
		".HhDRRDhH.",
		".HhDFFDhH.",
		".HhDWWDhH.",
		".HhGDDGhH.",
		".HhDDDDhH.",
		"..HhDDhH..",
		"..HhWWhH..",
		"...HhhH...",
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
	# #162: 弩級戦艦。より戦艦らしく=中心線に主砲塔3基(前/中/後)・艦橋・煙突を配した細長い装甲艦
	"dread": [
		"......HHHH......",
		".....HhhhhH.....",
		"....HhDDDDhH....",
		"...HhDDDDDDhH...",
		"..HhDDGGGGDDhH..",
		"..HhDGWWWWGDhH..",
		"..HhDDGGGGDDhH..",
		"..HhDDDBBDDDhH..",
		"..HhDDGBBGDDhH..",
		"..HhDDDGGDDDhH..",
		"..HhDDDGGDDDhH..",
		"..HhDDGGGGDDhH..",
		"..HhDGWWWWGDhH..",
		"..HhDDGGGGDDhH..",
		"..HhDDDBBDDDhH..",
		"..HhDDGGGGDDhH..",
		"..HhDGWWWWGDhH..",
		"..HhDDGGGGDDhH..",
		"..HhDDDDDDDDhH..",
		".HhhDDDDDDDDhhH.",
		".HhDDDDDDDDDDhH.",
		"..HhhDDDDDDhhH..",
		"...HhhDDDDhhH...",
		"....HhhhhhhH....",
		".....HHHHHH.....",
	],
}

func _build_ship_texture(with_ram: bool, ram_steel: bool) -> ImageTexture:
	var map: Array = SHIP_MAPS.get(GameState.ship_id, SHIP_MAP)   # #130: 船ごとの絵
	var w: int = map[0].length()
	var h := map.size()
	var ram_rows := 11 if with_ram else 0   # #36再: より細長く鋭角に
	var img := Image.create(w, h + ram_rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 衝角(#36/#43): 船首(進行方向)に細長く鋭い二等辺三角形
	if with_ram:
		var rc := Color(0.78, 0.82, 0.88) if ram_steel else Color(0.5, 0.46, 0.4)
		var cx := w / 2
		for ry in ram_rows:
			# ry=0(先端)は幅0、根元でも幅2程度の鋭角(細長い)
			var half: int = int(floor(float(ry) / float(ram_rows - 1) * 2.0))
			for x in range(cx - half, cx + half + 1):
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
	# #132/#144: 船の見た目の半幅(px)を算出して航跡幅・舷側しぶき位置に使う
	var map: Array = SHIP_MAPS.get(GameState.ship_id, SHIP_MAP)
	var mw: int = map[0].length()
	_half_w = (float(mw) / 2.0 - 1.0) * 3.4 * sc
	# #164: 実際の船体の半高(px)。透明パディング1px分を除いて船尾に隙間なく航跡を出す
	_half_h = (float(map.size()) / 2.0 - 1.0) * 3.4 * sc
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
	# 煙突の煙(#131再: さらにゆっくり・ほぼ静止して世界座標に残し、船が進むと後方へたなびく)
	var smoke := CPUParticles2D.new()
	smoke.amount = 20
	smoke.lifetime = 3.8
	smoke.local_coords = false          # 世界座標に残す→船の後方へたなびく
	smoke.position = Vector2(0, -6 * sc)
	smoke.spread = 180.0
	smoke.gravity = Vector2.ZERO
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 5.0 * sc
	smoke.initial_velocity_min = 0.0    # 完全に静止=その場で膨らみ、船が進むと後方へ残る
	smoke.initial_velocity_max = 0.0
	smoke.scale_amount_min = 4.0        # #131再: 見やすい大きなドット
	smoke.scale_amount_max = 8.0
	var scurve := Curve.new()           # 時間経過でさらに大きく広がる
	scurve.add_point(Vector2(0.0, 0.6))
	scurve.add_point(Vector2(1.0, 2.6))
	smoke.scale_amount_curve = scurve
	var sramp := Gradient.new()         # 遠ざかるほど薄く消える
	sramp.set_color(0, Color(0.88, 0.88, 0.9, 0.42))
	sramp.set_color(1, Color(0.9, 0.9, 0.92, 0.0))
	smoke.color_ramp = sramp
	add_child(smoke)
	_smoke = smoke
	# 航跡(#132再: ほぼ静止した泡を世界座標に残し、通過経路に沿って残す)
	_wake = CPUParticles2D.new()
	_wake.amount = 70
	_wake.lifetime = 3.2
	_wake.local_coords = false
	_wake.position = Vector2(0, _half_h)   # #164: 船尾に隙間なく(実際の船体半高)
	_wake.spread = 12.0
	_wake.gravity = Vector2.ZERO
	_wake.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_wake.emission_rect_extents = Vector2(_half_w, 1.5)   # #132: 船の横幅に合わせる
	_wake.initial_velocity_min = 0.0    # その場に残す(経路に沿う)
	_wake.initial_velocity_max = 3.0
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
	# 舷側のしぶき(#144: 経路に沿って残す=世界座標・ほぼ静止。バック時は非表示)
	_sprays = []
	for side in [-1.0, 1.0]:
		var spray := CPUParticles2D.new()
		spray.amount = 16
		spray.lifetime = 1.0
		spray.local_coords = false
		spray.position = Vector2(side * _half_w, -10 * sc)   # #144: 船の左右の縁から
		spray.spread = 60.0
		spray.gravity = Vector2.ZERO
		spray.initial_velocity_min = 4.0
		spray.initial_velocity_max = 12.0
		spray.scale_amount_min = 1.5
		spray.scale_amount_max = 3.5
		var spr_ramp := Gradient.new()
		spr_ramp.set_color(0, Color(0.95, 1.0, 1.0, 0.45))
		spr_ramp.set_color(1, Color(0.95, 1.0, 1.0, 0.0))
		spray.color_ramp = spr_ramp
		add_child(spray)
		_sprays.append(spray)

func _ship_scale() -> float:
	# #151再: 巡洋戦艦は見た目・当たり判定を一回り大きく
	var extra: float = 1.15 if GameState.ship_id == "cruiser" else 1.0
	return clampf(0.9 + float(GameState.ship().armor) / 1500.0, 0.9, 1.8) * extra

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
		throttle -= float(GameState.ship().get("reverse", 0.6))   # #151: 後退が得意な船(巡洋戦艦)は倍率大
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
	if _smoke:
		# #131: 蒸気は移動方向と逆向き(=船の後方)へ流す。世界座標の重力で押す
		_smoke.gravity = -velocity * 0.7
	var reversing := velocity.dot(forward()) < -1.0
	if _wake:
		_wake.emitting = spd > max_speed * 0.15
		# #132: バック時は船の前方に航跡が残る
		_wake.position = Vector2(0, -_half_h) if reversing else Vector2(0, _half_h)   # #164: 船尾に密着
		_wake.direction = Vector2(0, -1) if reversing else Vector2(0, 1)
	# #144: 舷側しぶきは前進中のみ(バック時は非表示)
	for spray in _sprays:
		spray.emitting = spd > max_speed * 0.2 and not reversing
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
