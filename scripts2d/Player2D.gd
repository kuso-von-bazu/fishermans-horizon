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
var _bump_cd: float = 0.0   # #193: 障害物の接触ダメージのクールダウン
var _wake: CPUParticles2D
var _smoke: CPUParticles2D   # #131: 蒸気(移動方向と逆向きに流す)
var _sprays: Array = []      # #144: 舷側のしぶき
var _charge_sprays: Array = []   # #224再: 突撃中の大きなしぶき(左右)
var _dmg_smokes: Array = []  # #178: 損傷時の黒煙(複数個所)
var _dmg_state: int = -1     # #178: 0=無/1=小(装甲1/4未満)/2=大(大破)。差分更新用
var _flame: CPUParticles2D   # #136: 炎上アニメ
var _sc: float = 1.0
var _half_w: float = 30.0    # #132/#144: 船の見た目の半幅(px)
var _half_h: float = 42.0    # #164: 船の見た目の半高(px)。航跡を船尾に隙間なく出すため
var _body_pts: PackedVector2Array
var _label: Label   # #212再: 「旗艦」表示(船と一緒に回らないよう毎フレーム逆回転)
# #224: 陣形スキル
var charge_t: float = 0.0        # 突撃の残り秒。>0の間は3倍速で直進し敵を貫く
var _charge_hit: Array = []      # 1回の突撃で同じ敵に多重ヒットしないための記録
var volley_queue: Array = []     # 一斉射撃の残弾 [{slot, left, timer}]
var volley_target: Node2D = null

func _ready() -> void:
	add_to_group("player")
	# #184再2/#149再3: 敵は専用レイヤー2にいるので、プレイヤーはレイヤー1+2と衝突する
	# (敵同士は衝突しないまま。#184のすり抜けは撤回してリアリティを戻す)
	collision_layer = 1
	collision_mask = 3
	max_speed = GameState.fleet_speed() * K   # #196: 船団は最も遅い船に合わせる
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
# #130再: 1マップドットあたりの表示スケール(旧3.4/1.5。ドット数を1.5倍にしたため footprint は不変)
const PIX_SCALE := 2.27

# #130: 船ごとに描き分けたドット絵(見た目を差別化)。未定義はSHIP_MAP(弩級)。
# #130再: 船ごとに船らしいドット絵へ描き分け(ドット数を増やして精細化)。bow=上。
const SHIP_MAPS := {
	# #186再: 粗末な漁船=笹の葉のように細長い小舟(船首・船尾が尖り、中央がいちばん広い)
	"raft": [
		".....H.....",
		"....HhH....",
		"....HDH....",
		"...HhDhH...",
		"...HDDDH...",
		"..HhDDDhH..",
		"..HDDDDDH..",
		"..HDWWWDH..",
		"..HDWBWDH..",
		"..HDWWWDH..",
		"..HDDDDDH..",
		"..HDDPDDH..",
		"..HDDDDDH..",
		"..HhDDDhH..",
		"...HDDDH...",
		"...HhDhH...",
		"....HDH....",
		"....HhH....",
		".....H.....",
	],
	# 武装スキフ: 尖った船首・前部砲・船橋・小煙突
	"skiff": [
		"........H........",
		".......HDH.......",
		"......HhDhH......",
		".....HhDDDhH.....",
		"....HhDGGGDhH....",
		"...HhDDDFDDDhH...",
		"...HhDDDDDDDhH...",
		"...HhDDDDDDDhH...",
		"...HhDWWWWWDhH...",
		"...HhDDBBBDDhH...",
		"...HhDDDDDDDhH...",
		"...HhDDDFDDDhH...",
		"...HhDDDDDDDhH...",
		"....HhDDDDDhH....",
		".....HhWWWhH.....",
		"......HhDhH......",
		".......HDH.......",
		"........H........",
		"........H........",
	],
	# 外洋カッター: すらりとした快速艇・単煙突
	"cutter": [
		".......H.......",
		".......H.......",
		"......HDH......",
		".....HhDhH.....",
		"....HhDDDhH....",
		"...HhDWWWDhH...",
		"...HhDDDDDhH...",
		"...HhDBBBDhH...",
		"...HhDDDDDhH...",
		"...HhDDFDDhH...",
		"...HhDDFDDhH...",
		"...HhDDDDDhH...",
		"...HhDDDDDhH...",
		"...HhDWWWDhH...",
		"...HhDDDDDhH...",
		"...HhDDDDDhH...",
		"....HhDDDhH....",
		".....HhDhH.....",
		"......HDH......",
		".......H.......",
		".......H.......",
		".......H.......",
		".......H.......",
	],
	# コルベット: 双煙突・艦橋・舷側砲の軍艦
	"corvette": [
		".........H.........",
		"........HDH........",
		".......HhDhH.......",
		"......HhDDDhH......",
		".....HhDDDDDhH.....",
		"....HhDDGGGDDhH....",
		"...HhDDDDFDDDDhH...",
		"...HhDDDDDDDDDhH...",
		"...HhDDWWWWWDDhH...",
		"...HhDDDBBBDDDhH...",
		"...GhDDDDDDDDDhG...",
		"...HhDDDDFDDDDhH...",
		"...HhDDDDFDDDDhH...",
		"...GhDDDDDDDDDhG...",
		"...HhDDDDFDDDDhH...",
		"....HhDDDFDDDhH....",
		".....HhDDDDDhH.....",
		"......HhGGGhH......",
		".......HhDhH.......",
		"........HDH........",
		".........H.........",
	],
	# 猟特化フリゲート: 緑帯・船首の銛座・細長い船体
	"hunter_h": [
		".......H.......",
		".......H.......",
		"......HDH......",
		".....HgggH.....",
		"....HhDGDhH....",
		"...HhDDDDDhH...",
		"...HhDDDDDhH...",
		"...HhDWWWDhH...",
		"...HhDBBBDhH...",
		"...HhDDDDDhH...",
		"...HhDDFDDhH...",
		"...HhDDFDDhH...",
		"...HhDDDDDhH...",
		"...HhDgggDhH...",
		"...HhDDDDDhH...",
		"...HhDDDDDhH...",
		"...HhDDDDDhH...",
		"...HhDWWWDhH...",
		"....HhDDDhH....",
		".....HhDhH.....",
		"......ggg......",
		".......H.......",
		".......H.......",
		".......H.......",
		".......H.......",
	],
	# 巡洋戦艦: 鋭い船体・前後の主砲塔・単煙突
	"cruiser": [
		".......H.......",
		".......H.......",
		"......HDH......",
		".....HhDhH.....",
		"....HhDDDhH....",
		"....HhGGGhH....",
		"...HhDDFDDhH...",
		"...HhDDDDDhH...",
		"...HhDWWWDhH...",
		"...HhDBBBDhH...",
		"...HhDDDDDhH...",
		"...HhDDFDDhH...",
		"...HhDDFDDhH...",
		"...HhDDDDDhH...",
		"...HhDDDDDhH...",
		"...HhDWWWDhH...",
		"...HhDDDDDhH...",
		"....HhDDDhH....",
		"....HhGGGhH....",
		".....HhDhH.....",
		"......HDH......",
		".......H.......",
		".......H.......",
		".......H.......",
		".......H.......",
	],
	# 大型運搬艦: 幅広・積荷(黄)コンテナ・ずんぐり
	"hauler": [
		"......HhDDDhH......",
		"....HhDDDDDDDhH....",
		"..HhDDDDDDDDDDDhH..",
		".HhDDDDDDDDDDDDDhH.",
		".HhDDYYYDDDYYYDDhH.",
		".HhDDYYYDDDYYYDDhH.",
		".HhDDDDDDDDDDDDDhH.",
		".HhDDYYYDDDYYYDDhH.",
		".HhDDYYYDDDYYYDDhH.",
		".HhDDDDDDDDDDDDDhH.",
		".HhDDYYYDDDYYYDDhH.",
		".HhDDYYYDDDYYYDDhH.",
		".HhDDDDDDDDDDDDDhH.",
		".HhDDDDDWWWDDDDDhH.",
		"..HhDDDDBBBDDDDhH..",
		"....HhDDDFDDDhH....",
		".....HhDDDDDhH.....",
		"......HhDDDhH......",
	],
	# 弩級戦艦: 主砲塔4基・艦橋・双煙突・舷側副砲の長大な装甲艦(丸い艦尾)
	"dread": [
		"...........H...........",
		"...........H...........",
		"..........HDH..........",
		".........HhDhH.........",
		"........HhDDDhH........",
		".......HhDDDDDhH.......",
		"......HhDDDFDDDhH......",
		".....HhDDDGGGDDDhH.....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDDDFDDDDDhH....",
		"....HhDDDDGGGDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDWWWWWDDDhH....",
		"....HhDDDDBBBDDDDhH....",
		"....GhDDDDDDDDDDDhG....",
		"....HhDDDDDFDDDDDhH....",
		"....HhDDDDDFDDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....GhDDDDDDDDDDDhG....",
		"....HhDDDDDFDDDDDhH....",
		"....HhDDDDDFDDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDWWWWWDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDDGGGDDDDhH....",
		"....HhDDDDDFDDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		"....HhDDDDGGGDDDDhH....",
		"....HhDDDDDFDDDDDhH....",
		"....HhDDDDDDDDDDDhH....",
		".....HhDDDDDDDDDhH.....",
		"......HhDDDDDDDhH......",
		"......HhDDDDDDDhH......",
		".......HhDDDDDhH.......",
		".......HhDDDDDhH.......",
		"........HhDDDhH........",
	],
}

# #185: 装備武器を甲板上に小さく表現するドット絵(魚雷は表現しない)。bow=上=銃口。
# B=筐体 b=銃身 s=細身シャフト m=銃口 I=砲口 t=真鍮の銛先
const WPN_PIX := {
	"B": Color(0.15, 0.16, 0.19), "b": Color(0.28, 0.30, 0.34),
	"s": Color(0.58, 0.60, 0.66), "m": Color(0.45, 0.46, 0.50),
	"I": Color(0.60, 0.62, 0.68), "t": Color(0.78, 0.62, 0.32),
}
const WPN_MAPS := {
	# ガトリング: 3連の細い銃身
	"gatling": [
		"m.m.m",
		"b.b.b",
		"b.b.b",
		"BBBBB",
		"BBBBB",
		".BBB.",
		".BBB.",
	],
	# 大砲: 太い単装砲身
	"cannon": [
		"..I..",
		".bbb.",
		".bbb.",
		".bbb.",
		"BBBBB",
		"BBBBB",
		".BBB.",
	],
	# 銛: 細長い銛と銛先(かえし)+発射架
	"harpoon": [
		"..t..",
		".ttt.",
		"..s..",
		"..s..",
		"..s..",
		".BBB.",
		".BBB.",
	],
}

func _weapon_texture(wid: String) -> ImageTexture:
	var m: Array = WPN_MAPS.get(wid, [])
	if m.is_empty():
		return null
	var ww: int = m[0].length()
	var wh := m.size()
	var img := Image.create(ww, wh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in wh:
		var row: String = m[y]
		for x in ww:
			var ch := row[x]
			if WPN_PIX.has(ch):
				img.set_pixel(x, y, WPN_PIX[ch])
	return ImageTexture.create_from_image(img)

func _build_ship_texture(with_ram: bool, ram_steel: bool) -> ImageTexture:
	var map: Array = SHIP_MAPS.get(GameState.ship_id, SHIP_MAP)   # #130: 船ごとの絵
	var w: int = map[0].length()
	var h := map.size()
	# #36再2: 衝角のサイズを船体に比例させる。船幅(実際の最大ビーム)を走査。
	var beam := 0
	for row in map:
		var lo := -1
		var hi := -1
		for x in w:
			if row[x] != ".":
				if lo < 0:
					lo = x
				hi = x
		if lo >= 0:
			beam = maxi(beam, hi - lo + 1)
	# #36再3: 衝角=細長い二等辺三角形。長さ≈船長の1/4、根元の全幅≈船幅の1/2(半幅=船幅の1/4)。
	# 底辺を船首にめり込ませ、船のグラフィックを手前(上書き)に描いて一体的に見せる。
	var ram_extend := int(round(float(h) / 4.0)) if with_ram else 0   # 船首から前方へ突き出す長さ(≈船長の1/4)
	var embed := int(round(float(h) / 6.0)) if with_ram else 0         # 船体へめり込む深さ(幅広の根元を船内へ隠す)
	var img := Image.create(w, h + ram_extend, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 衝角を先に描画(このあと船を上書き=船が手前に来る)
	if with_ram:
		var rc := Color(0.78, 0.82, 0.88) if ram_steel else Color(0.5, 0.46, 0.4)
		var rc_edge := rc.darkened(0.28)
		var cx := w / 2
		var base_half := float(beam) / 4.0          # 根元の半幅=船幅の1/4(全幅=1/2)
		var ram_len := ram_extend + embed
		for ry in ram_len:
			var t: float = float(ry) / float(maxi(ram_len - 1, 1))   # 0=先端 .. 1=根元(船体内)
			var half: int = int(round(base_half * pow(t, 1.25)))      # 細長い二等辺三角形(先端へ鋭角)
			for x in range(cx - half, cx + half + 1):
				if x >= 0 and x < w:
					var edge: bool = half >= 2 and (x == cx - half or x == cx + half)
					img.set_pixel(x, ry, rc_edge if edge else rc)
	# 船体(衝角の根元を覆う=一体化。船の全景を優先表示)
	for y in h:
		var row: String = map[y]
		for x in w:
			var ch := row[x]
			if PIX.has(ch):
				img.set_pixel(x, y + ram_extend, PIX[ch])
	return ImageTexture.create_from_image(img)

func _build_visual() -> void:
	var sc := _ship_scale()
	_sc = sc
	# #132/#144: 船の見た目の半幅(px)を算出して航跡幅・舷側しぶき位置に使う
	var map: Array = SHIP_MAPS.get(GameState.ship_id, SHIP_MAP)
	var mw: int = map[0].length()
	# #130再: 透明パディングを除いた実際の船体の縁を走査し、舷側しぶき/航跡を船体の縁に密着させる
	var half_cols := 0.0
	for row in map:
		for x in mw:
			if row[x] != ".":
				half_cols = maxf(half_cols, absf(float(x) + 0.5 - float(mw) / 2.0))
	_half_w = half_cols * PIX_SCALE * sc
	# #164: 実際の船体の半高(px)。透明パディング1px分を除いて船尾に隙間なく航跡を出す
	_half_h = (float(map.size()) / 2.0 - 1.0) * PIX_SCALE * sc
	var with_ram: bool = GameState.ram_id != "none"
	var sprite := Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = _build_ship_texture(with_ram, GameState.ram_id == "steel")
	sprite.scale = Vector2.ONE * PIX_SCALE * sc
	sprite.z_index = 2   # #164再: 船体を航跡・煙より前面に描画し、重なりの不自然さをなくす
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
	smoke.z_index = 3   # #164再2: 煙は船体より前面に描画(船体z=2の上)
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

	# #224再: 突撃中だけ舷側へ大きく跳ね上がるしぶき(通常のしぶきよりずっと派手)
	_charge_sprays = []
	for side2 in [-1.0, 1.0]:
		var cs := CPUParticles2D.new()
		cs.emitting = false
		cs.amount = 90
		cs.lifetime = 0.5
		# 船に張り付く座標系にして、舷側で大きく割れる波として見せる
		cs.local_coords = true
		cs.position = Vector2(side2 * _half_w * 0.9, 2 * sc)
		cs.direction = Vector2(side2, 0.62).normalized()   # #224再3: 斜め後ろへ跳ねる
		cs.spread = 34.0
		cs.gravity = Vector2.ZERO
		cs.initial_velocity_min = 55.0
		cs.initial_velocity_max = 135.0
		cs.damping_min = 90.0
		cs.damping_max = 150.0
		cs.scale_amount_min = 10.0
		cs.scale_amount_max = 22.0
		var cramp := Gradient.new()
		cramp.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
		cramp.set_color(1, Color(0.70, 0.90, 1.0, 0.0))
		cs.color_ramp = cramp
		cs.z_index = 3
		add_child(cs)
		_charge_sprays.append(cs)

	# #212再: 僚艦と同じく「旗艦」ラベルを表示
	var lbl := Label.new()
	lbl.text = "旗艦"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 4
	add_child(lbl)
	_label = lbl
	# #178: 損傷時の黒煙(装甲1/4未満で小さな黒煙・大破で大きな黒煙)。船の複数個所から噴く。
	_dmg_smokes = []
	var dmg_pts := [
		Vector2(-_half_w * 0.30, -_half_h * 0.55),  # 船首寄り
		Vector2( _half_w * 0.35, -_half_h * 0.05),  # 中央右舷
		Vector2(-_half_w * 0.10,  _half_h * 0.45),  # 船尾寄り
	]
	for p in dmg_pts:
		var ds := CPUParticles2D.new()
		ds.amount = 18
		ds.lifetime = 1.8
		ds.emitting = false
		ds.local_coords = false            # 世界座標に残す→船が進むと後方へたなびく
		ds.position = p
		ds.spread = 30.0
		ds.direction = Vector2(0, -1)      # 上へ立ち上る
		ds.gravity = Vector2(0, -30)
		ds.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		ds.emission_sphere_radius = 3.0 * _sc
		ds.initial_velocity_min = 6.0
		ds.initial_velocity_max = 16.0
		ds.scale_amount_min = 2.0
		ds.scale_amount_max = 4.5
		var dcurve := Curve.new()          # 立ち上りながら膨らむ
		dcurve.add_point(Vector2(0.0, 0.7))
		dcurve.add_point(Vector2(1.0, 2.2))
		ds.scale_amount_curve = dcurve
		var dramp := Gradient.new()        # 黒煙(濃い黒→薄れて消える)
		dramp.set_color(0, Color(0.12, 0.12, 0.13, 0.75))
		dramp.set_color(1, Color(0.18, 0.18, 0.2, 0.0))
		ds.color_ramp = dramp
		ds.z_index = 4
		add_child(ds)
		_dmg_smokes.append(ds)

	# #185: 装備中の武器を甲板上に小さく表現(魚雷は表現しない)。船首→船尾に沿って配置。
	var shown: Array = []
	for wid in GameState.weapons:
		if wid == null:
			continue
		var ws := str(wid)
		if ws != "" and ws != "torpedo" and WPN_MAPS.has(ws):
			shown.append(ws)
	var n := shown.size()
	for i in n:
		var wtex := _weapon_texture(shown[i])
		if wtex == null:
			continue
		var wsp := Sprite2D.new()
		wsp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wsp.texture = wtex
		wsp.scale = Vector2.ONE * PIX_SCALE * sc * 0.62   # 船と比べて小さめ
		var fy: float = -0.5 if n == 1 else lerpf(-0.52, 0.42, float(i) / float(n - 1))
		wsp.position = Vector2(0, fy * _half_h)   # 中心線に沿って甲板上へ
		wsp.z_index = 3   # 船体(z=2)より前面
		add_child(wsp)

func _ship_scale() -> float:
	# #151再: 巡洋戦艦は見た目・当たり判定を一回り大きく
	var extra: float = 1.15 if GameState.ship_id == "cruiser" else 1.0
	return clampf(0.9 + float(GameState.ship().armor) / 1500.0, 0.9, 1.8) * extra

func rebuild_visual() -> void:
	_dmg_state = -1   # #178: 損傷煙の状態を作り直し後に再評価させる
	for c in get_children():
		c.queue_free()
	max_speed = GameState.fleet_speed() * K   # #196: 船団は最も遅い船に合わせる
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
	if _bump_cd > 0.0:
		_bump_cd -= delta
	if not control_enabled:
		velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
		move_and_slide()
		queue_redraw()
		if _label:
			_label.rotation = -rotation
			_label.position = Vector2(-60, -_half_h - 34).rotated(-rotation)
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
	# #224再: 突撃でトップスピードに乗っている間は方向転換できない
	if charge_t <= 0.0:
		rotation += steer * turn_speed * steer_factor * delta
	velocity = velocity.move_toward(forward() * throttle * eff_max, accel * delta)
	# #184再2: 敵とは物理的に衝突する(すり抜けを撤回)。
	# 高速な敵に押し出されて最高速度を超える件は別途対応予定。
	# #224: 突撃中は向いている方向へ3倍速で直進し、敵をすり抜ける
	if charge_t > 0.0:
		charge_t -= delta
		velocity = forward() * max_speed * 3.0
		collision_mask = 1          # 敵レイヤー(2)を外して貫通
		if charge_t <= 0.0:
			collision_mask = 3
			_charge_hit.clear()
			# #224再2: 突撃が終わった瞬間に通常の最高速度まで落とす。
			# 慣性で旗艦だけ先へ進むと、上限が戻った僚艦が置いていかれるため
			velocity = velocity.limit_length(eff_max)
	# #224再: 突撃中だけ舷側の大しぶきを噴かせる
	for cs in _charge_sprays:
		if is_instance_valid(cs):
			cs.emitting = charge_t > 0.0
	move_and_slide()
	if charge_t > 0.0:
		_charge_pierce()
	_tick_volley(delta)      # #224: 一斉射撃
	_check_obstacle_bump()   # #193: 岩礁・流氷に接触で小ダメージ(障害物は壊れない)
	queue_redraw()           # #212再: 装甲ゲージの更新
	if _label:
		# ラベルは船と一緒に回ると裏返るので、常に画面上向き・船の真上に置く
		_label.rotation = -rotation
		_label.position = Vector2(-60, -_half_h - 34).rotated(-rotation)
	if _flame:
		_flame.emitting = GameState.burn_t > 0.0   # #136: 炎上中だけ炎
	# #178: 損傷黒煙。装甲1/4未満で小さな黒煙、大破(装甲0)で大きな黒煙を複数個所から。
	if _dmg_smokes.size() > 0:
		var frac := GameState.run_armor / maxf(GameState.max_armor(), 1.0)
		var st := 2 if GameState.run_armor <= 0.0 else (1 if frac < 0.25 else 0)
		if st != _dmg_state:
			_dmg_state = st
			for ds in _dmg_smokes:
				ds.emitting = st != 0
				if st == 2:      # 大破=大きな黒煙
					ds.amount = 26
					ds.scale_amount_min = 4.0
					ds.scale_amount_max = 8.0
					ds.initial_velocity_max = 22.0
				else:            # 小さな黒煙(st==1)。st==0はemitting=falseなので値は不問
					ds.amount = 18
					ds.scale_amount_min = 2.0
					ds.scale_amount_max = 4.5
					ds.initial_velocity_max = 16.0
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

# #193: 海上の障害物(岩礁/流氷)への接触判定。障害物は消滅せず、船だけが小ダメージを受ける。
# 擦り続けている間ずっと減り続けないよう、接触ダメージにはクールダウンを置く。
func _check_obstacle_bump() -> void:
	if _bump_cd > 0.0:
		return
	if GameState.docking_locked:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o := c.get_collider()
		if o == null or not (o is Node) or not (o as Node).is_in_group("obstacle"):
			continue
		# 勢いよくぶつかるほど痛い。粗末な漁船でも弩級戦艦でも「かすり傷」で収まるよう装甲比で決める
		var impact: float = clampf(velocity.length() / maxf(max_speed, 1.0), 0.0, 1.0)
		var dmg: float = clampf(GameState.max_armor() * 0.012, 3.0, 20.0) * (0.6 + 0.8 * impact)
		GameState.damage_player(dmg)
		var nm := "流氷" if str(o.get("kind")) == "ice" else "岩礁"
		GameState.notice.emit("%s に接触! %d ダメージ" % [nm, int(dmg)])
		Audio.play("sfx_hit", -6.0, 0.8)
		_bump_cd = 1.2
		return

# #224: 突撃で貫いた敵に衝角ダメージ(1回の突撃につき同じ敵へは1度だけ)
func _charge_pierce() -> void:
	# #224再: 衝角なしでも船体の体当たりとして一定のダメージが入る
	var rd := float(Database.rams[GameState.ram_id].dmg)
	var by_hull := rd <= 0.0
	if by_hull:
		rd = Database.HULL_RAM_DMG
	var reach := 34.0 * _sc
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		if e.get("aerial") == true or _charge_hit.has(e.get_instance_id()):
			continue
		var er: float = float(e.get("_radius")) if e.get("_radius") != null else 30.0
		if global_position.distance_to(e.global_position) > reach + er:
			continue
		_charge_hit.append(e.get_instance_id())
		var dmg := rd * (0.5 + velocity.length() / maxf(max_speed, 1.0))
		e.take_hit(dmg, false, false)
		GameState.notice.emit("突撃の%s! %d ダメージ" % ["体当たり" if by_hull else "衝角", int(dmg)])
		Audio.play("sfx_cannon", -6.0, 1.3)

# #224: 一斉射撃。装備中の各武器から、弾倉の半分(切り上げ)を3倍のレートでロック中の敵へ撃つ
func start_volley(target: Node2D) -> void:
	volley_target = target
	volley_queue.clear()
	var slots := int(GameState.ship().slots)
	for i in slots:
		var wid: String = GameState.weapons[i] if i < GameState.weapons.size() else ""
		if wid == "" or not Database.weapons.has(wid):
			continue
		var w: Dictionary = Database.weapons[wid]
		volley_queue.append({"slot": i, "left": int(ceil(float(w.mag) / 2.0)), "timer": 0.0})

func _tick_volley(delta: float) -> void:
	if volley_queue.is_empty():
		return
	# #224再: 非ロックオン時(volley_target が null)は前方へ撃つので中断しない。
	# ロック対象がいたのに消えた場合だけ打ち切る
	if volley_target != null and not is_instance_valid(volley_target):
		volley_queue.clear()
		return
	for q in volley_queue:
		q.timer -= delta
		if q.timer > 0.0 or int(q.left) <= 0:
			continue
		var wid: String = GameState.weapons[int(q.slot)]
		var w: Dictionary = Database.weapons[wid]
		q.timer = float(w.cooldown) / 3.0      # 通常の3倍のレート
		q.left = int(q.left) - 1
		_fire_volley_shot(w)
	volley_queue = volley_queue.filter(func(q): return int(q.left) > 0)

func _fire_volley_shot(w: Dictionary) -> void:
	# #224再: ロック中はロック対象へ、非ロック時は船の前方へ
	var dir := forward() if volley_target == null else (volley_target.global_position - global_position).normalized()
	var w2 := w.duplicate()
	w2["debuff_kind"] = GameState.harpoon_debuff
	w2.dmg = float(w.dmg) * GameState.attack_mult()
	Audio.play(str(w.get("sfx", "sfx_gun")), -12.0, randf_range(0.95, 1.05))
	var proj := Area2D.new()
	proj.set_script(preload("res://scripts2d/Projectile2D.gd"))
	get_parent().add_child(proj)
	proj.global_position = global_position + dir * 40.0
	proj.from_player = true
	# 味方はすり抜ける(Projectile2D側で from_player かつ fleet_ship は素通り)
	proj.setup(dir, w2, volley_target if str(w.kind) == "lock" else null)

# #212再: 僚艦と同じ円形の装甲ゲージ(上から時計回り。残量で緑→赤)
func _draw() -> void:
	var frac := clampf(GameState.run_armor / maxf(GameState.max_armor(), 1.0), 0.0, 1.0)
	var r := maxf(_half_w, _half_h) + 10.0
	draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	if frac > 0.0:
		var col := Color(1, 0.2, 0.15).lerp(Color(0.35, 1.0, 0.4), frac)
		draw_arc(Vector2.ZERO, r, -PI / 2, -PI / 2 + TAU * frac, 40, col, 5.0)

func _handle_ram() -> void:
	if _ram_cd > 0.0:
		return
	if GameState.docking_locked:
		return   # #101: 大破/寄港確定後は衝角も無効
	var rd := float(Database.rams[GameState.ram_id].dmg)
	if rd <= 0.0 or velocity.length() < 3.0 * K:
		return
	# #54再: バック中は衝角ダメージなし。正面から突撃したときだけ当たる
	if velocity.dot(forward()) <= 0.0:
		return
	# 衝角は近接判定で当てる(船首の正面にいる敵のみ突く)
	var reach := 28.0 * _sc
	var vdir := forward()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		if e.get("aerial") == true:
			continue   # #56: 空中の敵(オルニケイトス等)に衝角は届かない
		var to: Vector2 = e.global_position - global_position
		var er: float = float(e.get("_radius")) if e.get("_radius") != null else 30.0
		if to.length() > reach + er:
			continue
		if vdir.dot(to.normalized()) < 0.3:
			continue   # 前方(突撃方向)にいる敵だけを衝角で突く
		var ram_dmg := rd * (0.5 + velocity.length() / maxf(max_speed, 1.0))
		e.take_hit(ram_dmg, false, false)
		# #54: 突撃の手応え(通知+ノックバック+強い音)
		GameState.notice.emit("衝角の一撃! %d ダメージ" % int(ram_dmg))
		if e is CharacterBody2D:
			e.velocity += velocity.normalized() * 220.0
		Audio.play("sfx_cannon", -6.0, 1.3)
		_ram_cd = 0.8
		return
