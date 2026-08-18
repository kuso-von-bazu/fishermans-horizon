extends CharacterBody2D
## Enemy2D — 主/戦闘モブ/海賊(見下ろし2D)。Codex生成の透過スプライトを本体に使用。
## 円形HPゲージ(#21)は _draw で描画。挙動は3D版Enemyを踏襲:
## 海賊=遠隔+近接(#9)、ヒュドラ=回復する炎、レヴィアタン=津波/薙ぎ払い、番い(#5相当は討伐管理)。

const K := 6.0
# #223: 近海の主の近接攻撃力の一律倍率
const LORD_MELEE_MULT := 1.2

var kind: String = "mob"
var id: String = "narwhal"
var def: Dictionary = {}
var hp: float = 50.0
var max_hp: float = 50.0
var dmg: float = 5.0
var ranged: bool = false
var aerial: bool = false
var speed: float = 42.0
var attack_range: float = 54.0
var attack_cd: float = 1.4
var _atk_timer: float = 0.0
var _slip: float = 0.0
var _debuff_t: float = 0.0
var _debuff_kind: String = ""
var _debuff_power: float = 0.0   # #114: 銛の重ねがけ強度(減衰加算)
var _debuff_stacks: int = 0
var _aggro: bool = false        # #32: 発見で加速
var _wander_dir: Vector2 = Vector2.RIGHT
var _wander_t: float = 0.0
var sprite: Sprite2D
var _shadow: Sprite2D
var _flame: CPUParticles2D    # #136: 炎上(海賊)
var _debuff_fx: CPUParticles2D # #137: デバフ表示
var _debuff_fx_kind: String = ""
var _dead: bool = false        # #148: 撃破処理の多重実行防止
var _tex_side: Texture2D    # #26: 移動方向でドット絵を切替(横/正面/後ろ姿)
var _tex_front: Texture2D
var _tex_back: Texture2D
var _facing: String = "side"
var _facing_cd: float = 0.0   # #187再: 向き切替のクールダウン(パタつき防止)
var _target_w: float = 90.0
var player: Node2D
var pair_partner: Node = null
var is_escort: bool = false   # #67: 主の取り巻き(上限・デスポーン免除)
var escorts: Array = []       # #118: この主の取り巻き参照(全滅で引き撃ち)
var _bob: float = 0.0
var _radius: float = 40.0
var _base_radius: float = 40.0        # #190再: shrink_hp で縮める前の当たり判定半径
var _hit_shape: CircleShape2D = null
var locked: bool = false   # 魚雷ロック対象の表示(#16)
var _offscreen_t: float = 0.0   # #166: 画面外にいる時間(モブ/海賊は一定時間で消滅し枠を空ける)
var _spin: float = 0.0          # #190: 回転する敵(オニヒトデ/アスピドケロン)の現在角
var _charge_t: float = 0.0      # #190: 突進/休憩サイクルの残り秒(アスピドケロン)
var _charging: bool = true      # #190: true=突進(高速), false=休憩(低速)
var _burst_t: float = 0.0       # #65再2: 通常攻撃とは別系統の「バラマキ弾」までの残り秒

func setup(p_kind: String, p_id: String) -> void:
	kind = p_kind
	id = p_id
	match kind:
		"mob": def = Database.combat_mobs[id]
		"pirate": def = Database.pirates[id]
		"lord": def = Database.lords[id]
	# #202: 出現する海域に応じて敵(主・戦闘モブ・海賊・海賊王)のHPを一律で引き上げる。
	# 1の位は切り上げ(=10の倍数へ繰り上げ)。
	hp = float(Database.scaled_hp(float(def.hp), GameState.current_island))
	max_hp = hp
	dmg = float(def.dmg)
	ranged = bool(def.get("ranged", false))
	aerial = bool(def.get("aerial", false))
	# #73: 海賊王は出現海域が先の島ほど強化(hp/dmg)
	if id == "king":
		var tier := 1.0 + 0.4 * float(GameState.current_island)
		hp = ceilf(hp * tier / 10.0) * 10.0
		max_hp = hp
		dmg *= (1.0 + 0.2 * float(GameState.current_island))
	var base_speed: float = float(def.get("speed", 5.0 if kind == "lord" else 7.0))
	speed = base_speed * K * 1.2   # #84: 全敵の移動速度20%アップ
	# #88: 遠隔を持たない戦闘モブはさらに素早く(接近戦を仕掛けやすく)
	if kind == "mob" and not ranged:
		speed *= 1.25
	# #69/#72: reach=触腕などで攻撃射程が伸びる。#74/#86/#87: 遠隔持ちはかなり遠くから撃つ
	var rng := 9.0
	if kind == "lord":
		rng = 95.0   # #86: 主はさらに遠距離から射撃
	elif bool(def.get("ranged", false)):
		rng = 68.0   # #87: 遠隔モブもより遠距離から
	attack_range = rng * K * float(def.get("reach", 1.0)) * float(def.get("range_mult", 1.0))   # #163/#72: より遠距離から遠隔
	# #55: 海賊は高頻度射撃。#70: ワイアーム等は def の atk_cd を優先
	var cd_default := 0.55 if kind == "pirate" else 1.4
	attack_cd = float(def.get("atk_cd", cd_default))

func _ready() -> void:
	add_to_group("enemy")
	_bob = randf() * TAU
	# 目標サイズ(px): 強いほど大きい
	var target_w := 90.0
	match kind:
		"pirate": target_w = clampf(85.0 + max_hp * 0.05, 95.0, 160.0)
		"mob": target_w = clampf(52.0 + max_hp * 0.06, 55.0, 120.0)   # #33: 小さめ(#69以降の強モブは大きめ)
		"lord": target_w = clampf(110.0 + max_hp * 0.05, 140.0, 380.0)
	target_w *= float(def.get("size_mult", 1.0))   # #180: 個別の見た目サイズ調整(当たり判定も連動)
	_radius = target_w * 0.40
	_target_w = target_w
	attack_range += _radius
	# 本体スプライト(生成画像。なければ色付き楕円)
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # ドット絵をくっきり
	var tex := _load_tex()
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2.ONE * _tex_scale(tex)   # #26再: 最長辺基準で統一
	else:
		sprite.texture = _placeholder(def.get("color", Color(0.7, 0.3, 0.3)))
		sprite.scale = Vector2.ONE * (target_w / 64.0)
	add_child(sprite)
	# #26: 正面/後ろ姿のドット絵(あれば移動方向で切替)
	_tex_side = tex
	_tex_front = _load_dir_tex("front")
	_tex_back = _load_dir_tex("back")
	# 空中の敵は影を落として浮遊感(#torpedo不可)
	if aerial and tex:
		_shadow = Sprite2D.new()
		_shadow.texture = tex
		_shadow.scale = sprite.scale * 0.9
		_shadow.modulate = Color(0, 0.1, 0.2, 0.3)
		_shadow.position = Vector2(18, 26)
		_shadow.z_index = -1
		add_child(_shadow)
		sprite.position.y = -14
	# 衝突
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = _radius
	col.shape = sh
	add_child(col)
	_base_radius = _radius
	_hit_shape = sh
	# 名前ラベル
	var lbl := Label.new()
	lbl.text = def.name
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(1, 0.75, 0.75) if kind != "mob" else Color(0.8, 1, 0.8))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.position = Vector2(-target_w * 0.5, -_radius - 40)
	lbl.custom_minimum_size = Vector2(target_w, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	var ps := get_tree().get_first_node_in_group("player")
	if ps:
		player = ps
		# #184再2: リアリティのため、プレイヤーと敵はすり抜けず物理的に衝突する(#184のすり抜けを撤回)
	# #149再3: 敵は専用レイヤー(2)に置き、敵同士では衝突しない。
	# ティアマットのジグザグ移動がレヴィアタン等を押してしまう問題の対策。
	# 島・障害物・プレイヤー(レイヤー1)とは従来どおり衝突する。
	collision_layer = 2
	# #227再2: 敵同士(2)・僚艦(4)との衝突は撤回し、元のすり抜けへ戻す
	collision_mask = 1
	# #150: 空中の敵は島の当たり判定を無視(島と重なって追う)
	if aerial:
		collision_mask = 0
	# #136: 海賊の炎上 / #137: デバフのエフェクト用パーティクル
	_flame = _make_particles(Color(1.0, 0.85, 0.35, 0.9), Color(0.7, 0.15, 0.05, 0.0))
	add_child(_flame)
	_debuff_fx = _make_particles(Color(0.4, 0.9, 0.4, 0.9), Color(0.4, 0.9, 0.4, 0.0))
	add_child(_debuff_fx)

# #137: デバフ種別ごとの色(毒=緑/麻痺=黄/衰弱=紫/鈍化=青)
func _set_debuff_fx_color(kind_str: String) -> void:
	var c := Color(0.4, 0.9, 0.4)
	match kind_str:
		"slip": c = Color(0.35, 0.9, 0.35)    # 毒=緑
		"atkfreq": c = Color(1.0, 0.9, 0.3)   # 麻痺=黄
		"atk": c = Color(0.7, 0.4, 0.9)       # 衰弱=紫
		"speed": c = Color(0.4, 0.75, 1.0)    # 鈍化=青
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 0.9))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	_debuff_fx.color_ramp = g

func _make_particles(c0: Color, c1: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 16
	p.lifetime = 0.7
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = _radius * 0.7
	p.direction = Vector2(0, -1)
	p.gravity = Vector2(0, -60)
	p.spread = 30.0
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	p.z_index = 3
	return p

# #190: ザラタンの範囲近接。攻撃が届く範囲を白い波の輪で示し、広がりながら消える
func _wave_ring(radius: float) -> void:
	var ring := Line2D.new()
	ring.width = 7.0
	ring.default_color = Color(0.92, 0.98, 1.0, 0.85)
	ring.closed = true
	var pts := PackedVector2Array()
	for i in 36:
		var a := TAU * i / 36.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	ring.z_index = 4
	get_parent().add_child(ring)
	ring.global_position = global_position
	ring.scale = Vector2.ONE * 0.3
	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE, 0.32)
	tw.tween_property(ring, "modulate:a", 0.0, 0.5)
	var t := get_tree().create_timer(0.7)
	t.timeout.connect(func(): if is_instance_valid(ring): ring.queue_free())

# #156: 薙ぎ払いの水しぶきエフェクト。攻撃方向へ扇状に飛沫を飛ばし、視覚的に薙ぎ払いを示す
func _nagiharai_splash(dir: Vector2, reach: float) -> void:
	var p := CPUParticles2D.new()
	p.z_index = 4
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 40
	p.lifetime = 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = _radius * 0.8
	p.direction = dir
	p.spread = 55.0   # 攻撃方向を中心に扇状
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = reach * 1.6
	p.initial_velocity_max = reach * 3.2
	p.damping_min = reach * 2.0
	p.damping_max = reach * 3.5
	p.scale_amount_min = 4.0
	p.scale_amount_max = 9.0
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.98, 1.0, 0.95))    # 白い飛沫
	g.set_color(1, Color(0.55, 0.75, 0.9, 0.0))     # 水色に消える
	p.color_ramp = g
	get_parent().add_child(p)
	p.global_position = global_position + dir * _radius
	# 一定時間後に自動破棄
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func _load_tex() -> Texture2D:
	# ドット絵版(#26)優先。なければ元画像。
	var pixel := "res://assets/images/pixel/%s_%s.png" % [kind, id]
	if ResourceLoader.exists(pixel):
		return load(pixel)
	var path := "res://assets/images/%s_%s.png" % [kind, id]
	if ResourceLoader.exists(path):
		return load(path)
	return null

# #26: 正面(front)/後ろ姿(back)のドット絵。無ければnull(横向きのまま)
func _load_dir_tex(suffix: String) -> Texture2D:
	var p := "res://assets/images/pixel/%s_%s_%s.png" % [kind, id, suffix]
	if ResourceLoader.exists(p):
		return load(p)
	return null

# #26再: テクスチャの最長辺を target_w に合わせるスケール(向き違いでもサイズを統一)
func _tex_scale(t: Texture2D) -> float:
	var longest := maxf(float(t.get_width()), float(t.get_height()))
	return _target_w / maxf(longest, 1.0)

# #190: 現在のテクスチャ本来の表示スケール(shrink_hpで縮める際の基準)
func _base_scale() -> float:
	if sprite and sprite.texture:
		return _tex_scale(sprite.texture)
	return _target_w / 64.0

# #26: 移動方向に応じて 横/正面(南向き)/後ろ姿(北向き) を切り替える
func _update_facing(move_dir: Vector2) -> void:
	if sprite == null or move_dir.length() < 0.01:
		return
	# #190: 回転する敵(オニヒトデ/アスピドケロン)は向きの概念がないので横向き固定・反転なし
	if float(def.get("spin", 0.0)) > 0.0:
		return
	# #118: ケツァル等は常に正面(プレイヤー向き)固定で不自然な切替を防ぐ
	if bool(def.get("always_front", false)):
		if _facing != "front" and _tex_front != null:
			_facing = "front"
			sprite.texture = _tex_front
			sprite.scale = Vector2.ONE * _tex_scale(_tex_front)
			sprite.flip_h = false
		return
	var ny: float = move_dir.normalized().y
	# #187再: ヒステリシス。今の向きから抜けるには大きく傾く必要があり、境界付近でのパタつきを防ぐ
	var want := _facing
	match _facing:
		"back":
			if ny > -0.45:
				want = "front" if ny > 0.7 else "side"
		"front":
			if ny < 0.45:
				want = "back" if ny < -0.7 else "side"
		_:
			if ny < -0.7:
				want = "back"    # 北へ=画面奥へ→後ろ姿
			elif ny > 0.7:
				want = "front"   # 南へ=画面手前へ→正面
	var t: Texture2D = _tex_side
	match want:
		"back":
			t = _tex_back
		"front":
			t = _tex_front
	if t == null:
		want = "side"
		t = _tex_side
	# #187再: 切替直後は一定時間ロックして、瞬時に何度も切り替わる不自然さをなくす
	if want != _facing and t != null and _facing_cd <= 0.0:
		_facing = want
		_facing_cd = 0.45
		sprite.texture = t
		# #26再: 幅でなく最長辺で正規化し、横向きと同じ表示サイズに揃える(縦長の正面ビューが巨大化しないように)
		sprite.scale = Vector2.ONE * _tex_scale(t)
		if _shadow:
			_shadow.texture = t
			_shadow.scale = sprite.scale * 0.9
	# 左右反転は横向きのときだけ。#26再: 元画像が左向きの種は反転条件を逆に
	# #187再: 不感帯を広げ(0.1→0.3)、反転もクールダウン中は据え置いてパタつきを防ぐ
	if _facing != "side":
		sprite.flip_h = false   # 正面/後ろ姿は反転しない(従来動作)
	elif absf(move_dir.normalized().x) > 0.3:
		var face_left := bool(def.get("face_left", false))
		var want_flip: bool = (move_dir.x < 0.0) != face_left
		if want_flip != sprite.flip_h and _facing_cd <= 0.0:
			sprite.flip_h = want_flip
			_facing_cd = 0.45
	if _shadow:
		_shadow.flip_h = sprite.flip_h

func _placeholder(c: Color) -> Texture2D:
	var img := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 40:
		for x in 64:
			var d := Vector2((x - 32) / 32.0, (y - 20) / 20.0).length()
			if d < 1.0:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# 戻り値: 0=命中, 1=回避(弾は消える), 2=回避(弾は後方へ通過)
# #224再2: 包囲射撃(鶴翼陣)の間だけ、この敵の回避を無効にする
var _no_dodge_t: float = 0.0
var _counter_t: float = 0.0   # #239再8: 打ち返し弾のクールダウン

func suppress_dodge(secs: float) -> void:
	_no_dodge_t = maxf(_no_dodge_t, secs)

# #239: 夜の帝王の分裂。HPが規定割合を切ったら、指定の敵へ分かれて自分は消える。
# 分裂で生まれた個体は「元の主の討伐扱い」にするため split_root に元IDを持たせる。
var split_root: String = ""
var _split_done: bool = false

func _try_split() -> bool:
	if _split_done or not def.has("split"):
		return false
	var sp: Dictionary = def.split
	if hp / maxf(max_hp, 1.0) > float(sp.get("at_hp", 0.5)):
		return false
	_split_done = true
	var world := get_parent()
	if world == null or not world.has_method("spawn_split"):
		return false
	world.spawn_split(self, str(sp.get("into", "")), int(sp.get("count", 2)))
	GameState.notice.emit("%s が分裂した!" % def.name)
	_dead = true          # 分裂は撃破ではない(賞金・漁獲物を出さない)
	queue_free()
	return true

# #239: レイスのテレポート。撃つ→消える→別の場所へ現れる
func _tick_blink(delta: float) -> void:
	if not def.has("blink") or not _aggro or not is_instance_valid(player):
		return
	_blink_t -= delta
	if _blink_t > 0.0:
		return
	var bl: Dictionary = def.blink
	var iv: Array = bl.get("every", [2.6, 4.0])
	_blink_t = randf_range(float(iv[0]), float(iv[1]))
	var dr: Array = bl.get("dist", [420.0, 900.0])
	var ang := randf() * TAU
	var dest: Vector2 = player.global_position + Vector2(cos(ang), sin(ang)) * randf_range(float(dr[0]), float(dr[1]))
	# #239再6: 瞬間移動するとロックオンが外れる(消える瞬間に解除する)
	var w := get_parent()
	if w and w.has_method("release_lock_on"):
		w.release_lock_on(self)
	# #239再4: 瞬間移動の直前に急速に透明化してから飛ぶ(消えて現れる演出)
	if sprite:
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func():
			if is_instance_valid(self):
				global_position = dest)
		tw.tween_property(sprite, "modulate:a", 1.0, 0.30)
	else:
		global_position = dest
var _blink_t: float = 2.0

func take_hit(amount: float, slip: bool, debuff: bool, no_dodge: bool = false, debuff_kind: String = "") -> int:
	if _no_dodge_t > 0.0:
		no_dodge = true   # #224再2: 包囲射撃の対象は回避できない
	# #71/#111/#72: カリュブディス/ケツァル/ティアマット等は一定確率で攻撃をかわす。魚雷(no_dodge)は必中
	if not no_dodge and float(def.get("dodge", 0.0)) > 0.0 and randf() < float(def.get("dodge", 0.0)):
		if sprite:
			sprite.modulate = Color(0.5, 0.7, 1.6)
			var tw0 := create_tween()
			tw0.tween_property(sprite, "modulate", Color.WHITE, 0.25)
		GameState.notice.emit("%s が攻撃を回避!" % def.name)
		return 2 if bool(def.get("dodge_pass", false)) else 1
	# #128: 遠隔攻撃を受けたら視界外でも即座に発見状態になり追ってくる
	_aggro = true
	# #188: 番い(ギガントセイウチ)は片方が攻撃されると、もう片方も気づいて襲ってくる
	if is_instance_valid(pair_partner):
		pair_partner._aggro = true
	# #239再8: counter_shot=撃たれたときだけ撃ち返す(秒数=打ち返しの最短間隔)
	var ccd := float(def.get("counter_shot", 0.0))
	if ccd > 0.0 and _counter_t <= 0.0 and not _dead:
		_counter_t = ccd
		_ranged_attack(bool(def.get("fire", false)))
	var mult := 1.25 if _debuff_t > 0.0 else 1.0
	hp -= amount * mult
	if hp > 0.0 and _try_split():
		return 0   # #239: 分裂した(この個体は消える)
	if slip and kind == "pirate":
		_slip += amount * 0.6
	# #37再: 銛デバフは主+戦闘モブに有効(海賊は無効)。#114: 複数ヒットで減衰しつつ増加、最後のヒットから4.5秒
	if debuff and (kind == "lord" or kind == "mob") and not bool(def.get("no_debuff", false)):   # #187: 幽霊船は銛デバフ無効
		_debuff_kind = debuff_kind if debuff_kind != "" else GameState.harpoon_debuff   # #196再: 撃った艦の設定
		_debuff_power += 0.6 * pow(0.55, float(_debuff_stacks))
		_debuff_stacks += 1
		_debuff_t = 4.5 * GameState.debuff_dur_mult()
		if _debuff_kind == "slip":
			_slip += amount * (0.65 + 0.40 * _debuff_power)   # #37再々: 毒を強化
	elif debuff and bool(def.get("no_debuff", false)):
		# #187再2: 無効だと分かるように表示(頻繁に出しすぎないよう時々)
		if randf() < 0.34:
			GameState.notice.emit("%s には銛のデバフが効かない!" % def.name)
	# 被弾フラッシュ
	if sprite:
		sprite.modulate = Color(2.2, 1.2, 1.2)
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.18)
	queue_redraw()
	if hp <= 0:
		_die()
	return 0

func _physics_process(delta: float) -> void:
	if _no_dodge_t > 0.0:
		_no_dodge_t = maxf(_no_dodge_t - delta, 0.0)   # #224再2: 包囲射撃の回避無効
	if _counter_t > 0.0:
		_counter_t = maxf(_counter_t - delta, 0.0)   # #239再8: 打ち返し弾のクールダウン
	_tick_blink(delta)   # #239: レイスのテレポート
	if _slip > 0.0:
		var tick: float = minf(_slip, 8.0 * delta)
		hp -= tick
		_slip -= tick
		queue_redraw()
		if hp <= 0:
			_die()
			return
	if _facing_cd > 0.0:
		_facing_cd -= delta   # #187再: 向き切替クールダウン
	_tick_burst(delta)        # #65再2/#72再: 一定でないタイミングのバラマキ弾
	_update_line_of_fire()    # #193再3: 島・障害物で射線が遮られていないか
	if _debuff_t > 0.0:
		_debuff_t -= delta
		if _debuff_t <= 0.0:
			_debuff_kind = ""
			_debuff_power = 0.0   # #114: 効果切れで重ねがけリセット
			_debuff_stacks = 0
	# #136: 海賊の炎上表示(スリップ被害中)
	if _flame:
		_flame.emitting = kind == "pirate" and _slip > 0.5
	# #137: デバフ種別に応じたエフェクト
	if _debuff_fx:
		var want_fx := _debuff_kind if _debuff_t > 0.0 else ""
		if want_fx != _debuff_fx_kind:
			_debuff_fx_kind = want_fx
			if want_fx != "":
				_set_debuff_fx_color(want_fx)
		_debuff_fx.emitting = want_fx != ""
	# 泳ぎアニメ(#26): 揺れ+伸縮でドット絵を動かす
	_bob += delta * (2.6 if _aggro else 1.4)
	if sprite:
		var spin_rate: float = float(def.get("spin", 0.0))
		if spin_rate > 0.0:
			# #190: 回転する敵。突進中(_charging)はさらに速く回る
			_spin += delta * spin_rate * (1.6 if (_charging and _aggro) else 1.0)
			sprite.rotation = _spin
		else:
			sprite.rotation = sin(_bob * 0.7) * 0.06
		var squash := 1.0 + sin(_bob * 2.0) * 0.05
		var base_s: float = sprite.scale.x
		sprite.scale.y = absf(base_s) * squash
		# #190: レギオンは被弾で小魚が減り、陣形(見た目)が縮む
		var shrink: float = float(def.get("shrink_hp", 0.0))
		if shrink > 0.0:
			var f: float = lerpf(shrink, 1.0, clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0))
			var b: float = _base_scale() * f
			sprite.scale.x = b
			sprite.scale.y = b * squash
			# #190再: 見た目が縮んだぶん当たり判定(と近接の間合い)も縮める
			_radius = _base_radius * f
			if _hit_shape:
				_hit_shape.radius = _radius
	if not is_instance_valid(player):
		return
	var to: Vector2 = player.global_position - global_position
	var dist := to.length()
	# #32: 普段はゆっくり徘徊、発見(索敵圏内)で加速して追跡。#71: マーマンは索敵が広く好戦的
	var aggro_range: float = float(def.get("aggro", 900.0 if kind == "lord" else 640.0))
	# #73再: always_aggro(海賊王)は出現位置に関わらず必ずプレイヤーに気づいて追ってくる
	if not _aggro and (dist < aggro_range or bool(def.get("always_aggro", false))):
		_aggro = true
	var eff_speed := speed
	# #190: charge_cycle=突進と休憩を繰り返して動きに緩急をつける(アスピドケロン)
	if bool(def.get("charge_cycle", false)):
		_charge_t -= delta
		if _charge_t <= 0.0:
			_charging = not _charging
			_charge_t = randf_range(2.2, 3.4) if _charging else randf_range(1.4, 2.2)
		eff_speed *= 1.35 if _charging else 0.35
	if _debuff_kind == "speed":
		eff_speed *= 1.0 - 0.55 * clampf(_debuff_power, 0.0, 1.0)   # #37再々: 鈍化を強化   # #91/#114 鈍化(重ねがけで増加/減衰)
	var move_dir: Vector2
	var face_dir := Vector2.ZERO   # #187再: 見た目の向きを別管理(引き撃ち中は常にプレイヤーの逆を向く)
	if bool(def.get("stationary", false)):
		# #239: キラーシェルはその場から動かない(向きだけプレイヤーへ)
		velocity = Vector2.ZERO
		move_and_slide()
		_update_facing(to.normalized())
		if dist <= attack_range:
			_attack(delta, dist)
		return
	if _aggro:
		move_dir = to.normalized()
		# #118: ケツァル等は取り巻きを全滅させると引き撃ち(射程内では距離を取りつつ撃つ)
		# #187: kite_hp指定時はHPが一定割合以下になってから引き撃ちを試みる(幽霊船=2/3以下)
		var kite_ok: bool = hp / maxf(max_hp, 1.0) <= float(def.get("kite_hp", 1.0))
		if bool(def.get("kite", false)) and kite_ok and (bool(def.get("kite_always", false)) or _escorts_cleared()) and dist < attack_range * 0.85:
			move_dir = -to.normalized()
			# 島の迂回で進行方向が揺れても、見た目はプレイヤーの真逆で固定する
			face_dir = -to.normalized()
		# #149再: ティアマット等はプレイヤーを追いつつさらに大きくジグザグに移動
		elif bool(def.get("zigzag", false)):
			var perp := move_dir.rotated(PI / 2)
			move_dir = (move_dir + perp * sin(_bob * 1.8) * float(def.get("zigzag_amp", 4.2))).normalized()   # #149再2: 振幅はdefで調整
		# #193再3: 射線が島・障害物で遮られている遠隔敵は、横へ回り込んで射線を通す
		if ranged and _cover_blocked:
			move_dir = _flank_dir(move_dir)
		# #150: 地上の敵は島を迂回して追う(島から離れる向きを混ぜる)
		if not aerial:
			move_dir = _avoid_islands(move_dir)
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 4.5)
			_wander_dir = Vector2.RIGHT.rotated(randf() * TAU)
		move_dir = _wander_dir
		if not aerial:
			move_dir = _avoid_islands(move_dir)   # #193再: 徘徊中も障害物に引っかからないよう迂回
		eff_speed *= 0.3
	# スプライトの向き(#26: 横/正面/後ろ姿の切替+左右反転)
	_update_facing(face_dir if face_dir != Vector2.ZERO else move_dir)
	var melee_r0: float = _radius + (12.0 if kind == "lord" else 9.0) * K * float(def.get("reach", 1.0))
	var mate_near: bool = _melee_victim(melee_r0) != null   # #222: 近接圏の僚艦
	if not _aggro:
		velocity = move_dir * eff_speed
	elif dist > attack_range and not mate_near:
		velocity = move_dir * eff_speed
	else:
		# #94: 主は射程内でも停止せずプレイヤーを追いながら撃つ。近接圏では減速
		var melee_r: float = _radius + (12.0 if kind == "lord" else 9.0) * K * float(def.get("reach", 1.0))
		if kind == "lord" and dist > melee_r:
			velocity = move_dir * eff_speed * 0.75
		elif (kind == "mob" or kind == "pirate") and (bool(def.get("zigzag", false)) or bool(def.get("shoot_moving", false))) and dist > melee_r:
			velocity = move_dir * eff_speed * 0.85   # #149再: ティアマット等は移動(ジグザグ)しながら遠隔攻撃
		else:
			velocity = velocity.move_toward(Vector2.ZERO, eff_speed)
		_attack(delta, dist)
	move_and_slide()
	_check_offscreen_despawn(delta)

# #166: 戦闘モブ・海賊は画面外に一定時間出ると消滅して出現枠を空ける。
# 近海の主・主の取り巻き・海賊王は対象外。
func _check_offscreen_despawn(delta: float) -> void:
	if kind == "lord" or is_escort:
		return
	if kind == "pirate" and id == "king":
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var rel: Vector2 = global_position - (cam.global_position - vp * 0.5)
	var m := 360.0   # #166再: 消滅する距離を少し離す(画面外の余白を広げる)
	if rel.x < -m or rel.y < -m or rel.x > vp.x + m or rel.y > vp.y + m:
		_offscreen_t += delta
		if _offscreen_t > 6.0:
			queue_free()
	else:
		_offscreen_t = 0.0

# #222: 旗艦を追う挙動はそのままに、近接圏に入った僚艦がいればそちらを殴る。
# (旗艦に追いつけていないのに、隣にいる僚艦を無視するのが不自然だったため)
func _melee_victim(melee_r: float) -> Node2D:
	var best: Node2D = null
	var best_d := melee_r
	for m in get_tree().get_nodes_in_group("fleet_ship"):
		if not is_instance_valid(m):
			continue
		var d: float = global_position.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best

# 近接ダメージを対象へ与える(僚艦なら僚艦の装甲へ)
func _damage_victim(amount: float, victim: Node2D) -> void:
	# #237再2: 寄港確定後は音も演出も出さない。_attack にガードを入れたが、
	# 多段近接(multi_melee)の2段目以降はタイマーで遅れて発火するため、
	# 発火時点で寄港していると被弾音だけが鳴っていた(「たまに鳴る」の正体)。
	# 入口ではなくダメージ処理そのものを塞ぐ。
	if GameState.docking_locked or _dead:
		return
	if victim == null:
		_damage_player(amount)
		return
	if victim.has_method("take_damage"):
		victim.take_damage(amount)
	if bool(def.get("poison", false)) and victim.has_method("apply_poison"):
		victim.apply_poison(6.0, 4.0)
	Audio.play("sfx_hit", -9.0)   # #47再2: 被ダメ音を少し小さく

func _attack(delta: float, dist: float) -> void:
	# #237: 寄港確定後は近接攻撃もしない。
	# 従来は _ranged_attack にしかガードが無く、近接圏の敵はダメージこそ
	# GameState.damage_player 側で無効化されるものの、被弾音だけが鳴っていた。
	if GameState.docking_locked:
		return
	_atk_timer -= delta
	if _atk_timer > 0:
		return
	_atk_timer = attack_cd
	if _debuff_kind == "atkfreq":
		_atk_timer *= 1.0 + 0.5 * _debuff_power   # #91/#114 麻痺: 攻撃間隔増(重ねがけで増加/減衰)
	# #239再8: no_attack=自分からは仕掛けない(キラーシェルは撃たれたときだけ打ち返す)
	if bool(def.get("no_attack", false)):
		return
	var eff_dmg := dmg
	if _debuff_kind == "atk":
		eff_dmg *= 1.0 - 0.35 * clampf(_debuff_power, 0.0, 1.0)  # #91/#114 衰弱: 与ダメ減
	# #74: 遠隔持ちは attack_range(遠距離)で撃ち、近接圏(melee_r)に入られたら近接
	var melee_r: float = _radius + (12.0 if kind == "lord" else 9.0) * K * float(def.get("reach", 1.0))
	if kind == "lord":
		# #239: no_melee=近接を一切しない主(ウンディーネ/セイレーン/レイス)
		if bool(def.get("no_melee", false)):
			_ranged_attack(bool(def.get("fire", false)))
			return
		# #239: multi_melee=多段ヒットする長リーチ近接(オクトパス)
		if def.has("multi_melee") and (dist <= melee_r or _melee_victim(melee_r) != null):
			var mm: Array = def.multi_melee
			var hits := int(mm[randi() % mm.size()])
			var victim := _melee_victim(melee_r)
			for k in hits:
				if k == 0:
					_damage_victim(eff_dmg, victim)
				else:
					var vv := victim
					get_tree().create_timer(0.16 * float(k)).timeout.connect(func():
						if is_instance_valid(self) and not _dead:
							_damage_victim(eff_dmg * 0.8, vv if is_instance_valid(vv) else null))
			GameState.notice.emit("%s の%d段攻撃!" % [def.name, hits])
			return
		# #65: 全主が遠隔攻撃。近距離では従来の近接/固有技
		if id == "leviathan" and dist <= melee_r:   # #156再: 薙ぎ払いのヒット距離は通常の近接攻撃と同じに戻す
			var atk_dir := (player.global_position - global_position).normalized()
			_nagiharai_splash(atk_dir, melee_r)   # #156: 攻撃方向へしぶきエフェクト
			_damage_player(eff_dmg * 1.3 * LORD_MELEE_MULT)   # #223
			GameState.ignite(5.0)   # #65: 薙ぎ払いは必ず炎上
			GameState.notice.emit("レヴィアタンの薙ぎ払い!")
			if randf() < 0.4:   # #161: 近接圏でも時折遠隔攻撃を織り交ぜる
				_ranged_attack(false)
		elif dist <= melee_r or _melee_victim(melee_r) != null:
			# #190: melee_mult=体当たりなど近接が強い主(アスピドケロン)
			var victim := _melee_victim(melee_r)   # #222: 近接圏の僚艦を優先
			var mm := float(def.get("melee_mult", 1.0))
			if mm > 1.0:
				var tgt_pos: Vector2 = victim.global_position if victim != null else player.global_position
				_nagiharai_splash((tgt_pos - global_position).normalized(), melee_r)
				GameState.notice.emit("%s の体当たり!" % def.name)
			_damage_victim(eff_dmg * mm * LORD_MELEE_MULT, victim)   # #223: 主の近接は一律1.2倍
			# #223: レヴィアタン以外の主も、近接圏で時々遠隔攻撃を織り交ぜる
			if randf() < 0.4:
				_ranged_attack(bool(def.get("fire", false)))
		else:
			_ranged_attack(bool(def.get("fire", false)))
	elif kind == "pirate":
		# #77: 海賊は近接圏では近接攻撃もする
		var pv := _melee_victim(melee_r)   # #222
		if dist <= melee_r or pv != null:
			if str(def.get("wpn", "")) == "all":
				_damage_victim(eff_dmg * 1.6, pv)   # #73: 海賊王の衝角突撃
				GameState.notice.emit("海賊王の衝角突撃!")
			else:
				_damage_victim(eff_dmg, pv)
		else:
			_ranged_attack(false)
	elif ranged:
		var rv := _melee_victim(melee_r)   # #222
		if dist <= melee_r or rv != null:
			_damage_victim(eff_dmg, rv)
		else:
			_ranged_attack(false)
	elif dist <= attack_range or _melee_victim(melee_r) != null:
		# #190: wave_melee=離れた距離からの範囲近接(ザラタン)。攻撃範囲を波の輪で表示
		if bool(def.get("wave_melee", false)):
			_wave_ring(attack_range)
		_damage_victim(eff_dmg, _melee_victim(attack_range))   # #222

# #65/#66: way=扇状同時弾, homing=追跡弾を追加, wpn=gatling(3連小弾)/torpedo(追尾)/cannon
func _ranged_attack(is_fire: bool) -> void:
	if GameState.docking_locked:
		return   # #121: 寄港確定/寄港中は敵は遠隔攻撃をしない(紛らわしさ解消)
	if _cover_blocked:
		return   # #193再3: 島・障害物で射線が遮られている間は撃たない(回り込んでから撃つ)
	var eff_dmg := dmg
	if _debuff_kind == "atk":
		eff_dmg *= 1.0 - 0.35 * clampf(_debuff_power, 0.0, 1.0)   # #91/#114
	# #199: 船団を組んでいる場合、たまに2〜5番艦を狙う
	var aim: Node2D = _aim_target()
	var base_dir := (aim.global_position - global_position).normalized()
	# #187: volley_pool から volley_pick 個をランダムに選んで同時発射(幽霊船=3種中2種)
	if def.has("volley_pool"):
		var pool: Array = (def.volley_pool as Array).duplicate()
		pool.shuffle()
		for i in mini(int(def.get("volley_pick", 2)), pool.size()):
			_fire_weapon(str(pool[i]), eff_dmg, base_dir, is_fire, aim)
		return
	# #66: volley=複数武器を同時発射(海賊中/大)
	if def.has("volley"):
		for wp in def.volley:
			_fire_weapon(str(wp), eff_dmg, base_dir, is_fire, aim)
		return
	var wpn := str(def.get("wpn", ""))
	if wpn == "all":
		wpn = ["cannon", "gatling", "torpedo"][randi() % 3]   # #73: 海賊王は全武装
	_fire_weapon(wpn, eff_dmg, base_dir, is_fire, aim)

# #199: 遠隔攻撃の狙い先。船団の僚艦がいるときは3割の確率でそちらを狙う
func _aim_target() -> Node2D:
	# #239: target_nearest=旗艦ではなく最も近い船を優先して狙う(オクトパス)
	if bool(def.get("target_nearest", false)):
		var best: Node2D = player
		var bd := 1e18
		if is_instance_valid(player):
			bd = global_position.distance_to(player.global_position)
		for m2 in get_tree().get_nodes_in_group("fleet_ship"):
			if not is_instance_valid(m2):
				continue
			var d2: float = global_position.distance_to(m2.global_position)
			if d2 < bd:
				bd = d2
				best = m2
		return best
	var mates := get_tree().get_nodes_in_group("fleet_ship")
	if not mates.is_empty() and randf() < 0.3:
		var m = mates[randi() % mates.size()]
		if is_instance_valid(m):
			return m
	return player

# #238: 海賊(海賊王含む)と幽霊船の遠隔攻撃に、プレイヤーと同じ武器の効果音を鳴らす。
# 生物の主・モブは武器を使わないので対象外(鳴らすと海が騒がしくなりすぎる)。
# 自機の攻撃音(-8dB)より控えめにして、自分の射撃と混ざらないようにする。
const ENEMY_WPN_SFX := {
	"gatling": "sfx_gun",
	"cannon": "sfx_cannon",
	"torpedo": "sfx_torpedo",
}

func _fire_weapon(wpn: String, eff_dmg: float, base_dir: Vector2, is_fire: bool, aim: Node2D = null) -> void:
	if aim == null:
		aim = player
	if kind == "pirate" or id == "ghost":
		var nm := str(ENEMY_WPN_SFX.get(wpn, "sfx_cannon"))   # wpn未指定の海賊は砲撃扱い
		Audio.play(nm, -14.0, randf_range(0.93, 1.05))
	match wpn:
		"gatling":
			for i in 3:
				_shoot(base_dir.rotated(randf_range(-0.07, 0.07)), {"dmg": eff_dmg * 0.35, "falloff": true}, false)
		"torpedo":
			_shoot(base_dir, {"dmg": eff_dmg, "homing": true}, false, aim)
		_:
			# #65再: leviathan=全方向弾(radial)+照準の密な3way(aim_tight)+追跡弾。hydra=炎7way+追跡弾。他主=way
			var has_radial := bool(def.get("radial", false))
			var dm := float(def.get("shot_dmg_mult", 1.0))       # #65: 攻撃力倍率
			var ss := float(def.get("shot_speed_mult", 1.0))     # #65: 全方位/照準弾の弾速倍率
			var hs := float(def.get("homing_speed_mult", 1.0))   # #65: 追跡弾の弾速倍率
			if has_radial:
				var count := int(def.get("radial_count", 12))
				for i in count:
					_shoot(Vector2.RIGHT.rotated(TAU * i / count), {"dmg": eff_dmg * dm, "speed_mult": ss}, is_fire)
			# 照準の扇状弾(radialと併用可)。aim_tight=密な狭い扇。#65再: aim_shape/aim_colorで楕円弾など見た目指定
			var way := int(def.get("way", 0 if has_radial else 1))
			# #72再: way_choices指定時は毎回そこから選ぶ(ティアマット=時々2way/3way)
			var way_pool: Array = def.get("way_choices", [])
			if not way_pool.is_empty():
				way = int(way_pool[randi() % way_pool.size()])
			var spread_step: float = float(def.get("aim_spread", 0.10 if bool(def.get("aim_tight", false)) else 0.20))
			var aim_shape := str(def.get("aim_shape", ""))
			var aim_color = def.get("aim_color", null)
			# #190: multi_origin=陣形の複数箇所から同時発射(レギオン)。既定は本体1箇所のみ
			var origins := _shot_origins()
			for org in origins:
				for i in way:
					var off: float = (float(i) - float(way - 1) / 2.0) * spread_step
					var w := {"dmg": eff_dmg * dm, "speed_mult": ss}
					if aim_shape != "":
						w["shape"] = aim_shape
					if aim_color != null:
						w["bcolor"] = aim_color
					if bool(def.get("star_shot", false)):
						w["shape"] = "star"
					elif bool(def.get("small_shot", false)):
						w["shape"] = "small"
					elif bool(def.get("needle_shot", false)):
						w["shape"] = "needle"   # #239: ラミア
					elif bool(def.get("note_shot", false)):
						w["shape"] = "note"     # #239: セイレーン
						# #239再6: 音符は立てたまま、左右に蛇行させる
						w["upright"] = true
						w["wave_amp"] = float(def.get("shot_wave_amp", 150.0))
						w["wave_freq"] = float(def.get("shot_wave_freq", 7.0))
					_shoot(base_dir.rotated(off), w, is_fire, null, org)
			# #190: scatter=無作為な方向へばら撒く弾(オニヒトデ/アスピドケロン/レギオン)
			var scatter := int(def.get("scatter", 0))
			# #239: scatter_var=ばら撒きの密度が毎回変わる(高密度/中密度/低密度)
			if scatter > 0 and bool(def.get("scatter_var", false)):
				scatter = int(round(float(scatter) * [0.45, 0.75, 1.25][randi() % 3]))
			# #190再: scatter_speeds指定時は低速/中速/高速を順に混ぜて撒く(レギオン)
			var sp_pool: Array = def.get("scatter_speeds", [])
			# #239: scatter_aim=全方位ではなく「プレイヤーの方向へ」扇状に撒く
			var scatter_aim := bool(def.get("scatter_aim", false))
			var scatter_cone: float = float(def.get("scatter_cone", 0.85))
			for i in scatter:
				var sd: Vector2
				if scatter_aim:
					sd = base_dir.rotated(randf_range(-scatter_cone, scatter_cone))
				else:
					sd = Vector2.RIGHT.rotated(TAU * (float(i) + randf()) / float(maxi(scatter, 1)))
				var smul: float = float(sp_pool[i % sp_pool.size()]) if not sp_pool.is_empty() else randf_range(0.82, 1.18)
				var ws := {"dmg": eff_dmg * dm, "speed_mult": ss * smul}
				if aim_color != null:
					ws["bcolor"] = aim_color   # #239: 弾の色をdefで指定できるように
				if bool(def.get("star_shot", false)):
					ws["shape"] = "star"
				elif bool(def.get("small_shot", false)):
					ws["shape"] = "small"
				_shoot(sd, ws, is_fire, null, origins[i % origins.size()])
			# #65再: spread_homing=発射後に扇状(左右)へ広がってから急加速して追尾
			var spread_h := bool(def.get("spread_homing", false))
			var hc := int(def.get("homing_count", 1 if bool(def.get("homing", false)) else 0))
			for h in hc:
				var hd: Vector2
				if spread_h and hc > 1:
					hd = base_dir.rotated((float(h) - float(hc - 1) / 2.0) * 0.5)
				else:
					hd = base_dir.rotated(randf_range(-0.3, 0.3))
				var wh := {"dmg": eff_dmg * 0.8 * dm, "homing": true, "speed_mult": hs}
				if spread_h:
					wh["spread_homing"] = true
				_shoot(hd, wh, is_fire, aim)

# #65再2/#72再: 通常攻撃とは別系統の「バラマキ弾」。
# def.burst = {count, spread(rad), speeds[](弾速倍率の混在), dmg_mult, color, shape,
#              every:[最短,最長](一定でないタイミング), kite_only(引き撃ち移行後のみ)}
# 通常攻撃より頻度が低くなるよう every は攻撃間隔よりかなり長く取る。
func _tick_burst(delta: float) -> void:
	if not def.has("burst"):
		return
	var b: Dictionary = def.burst
	if _burst_t <= 0.0:
		_burst_t = randf_range(float(b.every[0]), float(b.every[1]))
		return   # 出現直後にいきなり撃たないよう、最初は間隔を置くだけ
	_burst_t -= delta
	if _burst_t > 0.0:
		return
	_burst_t = randf_range(float(b.every[0]), float(b.every[1]))
	if not _aggro or GameState.docking_locked or not is_instance_valid(player):
		return
	if player.global_position.distance_to(global_position) > attack_range * 1.15:
		return
	if _cover_blocked:
		return   # #193再3: 射線が遮られている間は撃たない
	# #65再: ケツァルは引き撃ちモードへ移行してからのみ撃つ
	if bool(b.get("kite_only", false)) and not (_escorts_cleared() and hp / maxf(max_hp, 1.0) <= float(def.get("kite_hp", 1.0))):
		return
	_fire_spray(b, (_aim_target().global_position - global_position).normalized())

# バラマキ弾の実射出。扇状に散らし、速度を speeds から順に混ぜる
func _fire_spray(b: Dictionary, base_dir: Vector2) -> void:
	var count := int(b.get("count", 12))
	var spread := float(b.get("spread", 0.5))
	var speeds: Array = b.get("speeds", [1.0])
	var shp := str(b.get("shape", "ellipse_s"))
	for i in count:
		var t: float = (float(i) / float(maxi(count - 1, 1))) - 0.5   # -0.5..0.5
		var d := base_dir.rotated(t * spread * 2.0 + randf_range(-0.05, 0.05))
		var w := {
			"dmg": dmg * float(b.get("dmg_mult", 0.22)),
			"speed_mult": float(speeds[i % speeds.size()]),
			"shape": shp,
			"burst": true,   # _shoot の一括付与(炎/毒)から除外するための目印
		}
		if b.has("color"):
			w["bcolor"] = b.color
		_shoot(d, w, false)

# #190再2/#71再: 撃墜された瞬間の「打ち返し弾」。
# def.death_shot = {count, mode:"radial"|"aim"|"shotgun", spread, speeds[], dmg_mult, shape, color}
func _fire_death_shot() -> void:
	if not def.has("death_shot") or GameState.docking_locked or not is_instance_valid(player):
		return
	var d: Dictionary = def.death_shot
	var to_p := (player.global_position - global_position).normalized()
	match str(d.get("mode", "shotgun")):
		"radial":
			var n := int(d.get("count", 12))
			var speeds: Array = d.get("speeds", [1.0])
			for i in n:
				var w := {
					"dmg": dmg * float(d.get("dmg_mult", 0.3)),
					"speed_mult": float(speeds[i % speeds.size()]),
					"shape": str(d.get("shape", "ellipse_s")),
					"burst": true,
				}
				if d.has("color"):
					w["bcolor"] = d.color
				_shoot(Vector2.RIGHT.rotated(TAU * i / n), w, false)
		"aim":
			for i in int(d.get("count", 1)):
				var w2 := {"dmg": dmg * float(d.get("dmg_mult", 0.6)), "shape": str(d.get("shape", "")), "burst": true}
				if d.has("color"):
					w2["bcolor"] = d.color
				_shoot(to_p, w2, false)
		_:
			_fire_spray(d, to_p)   # ショットガン状(バラマキと同じ散らし方)

# #190: 弾の発射位置(本体からのオフセット)。multi_origin指定時は陣形上に散らす
func _shot_origins() -> Array:
	var n := int(def.get("multi_origin", 1))
	if n <= 1:
		return [Vector2.ZERO]
	var out: Array = []
	for i in n:
		var a: float = TAU * float(i) / float(n) + _bob * 0.35
		out.append(Vector2(cos(a), sin(a)) * _radius * 0.7)
	return out

func _shoot(d: Vector2, w: Dictionary, is_fire: bool, tgt: Node2D = null, origin_off: Vector2 = Vector2.ZERO) -> void:
	# #72: ティアマット等は遠隔弾に高確率の炎上を付与
	if float(def.get("burn_chance", 0.0)) > 0.0 and not w.has("homing"):
		w["burn_chance"] = float(def.get("burn_chance", 0.0))
	# #194: ダゴンの遠隔弾は直接ダメージ無し・毒のスリップのみ(バラマキ弾には付けない)
	if bool(def.get("shot_poison", false)) and not w.has("homing") and not w.has("burst"):
		w["poison_only"] = true
	# #167: ティアマット等は弾の見た目だけヒュドラの炎弾と同じに(挙動はburn_chanceのまま)
	if bool(def.get("fire_look", false)) and not w.has("homing") and not w.has("burst"):
		w["fire_look"] = true
		if def.has("flame_color"):
			w["flame_color"] = def.flame_color   # #72再: ザッハークの白い炎など
	# #65: 弾速倍率(_fire_weaponで明示指定済みならそのまま)
	if not w.has("speed_mult") and float(def.get("shot_speed_mult", 1.0)) != 1.0 and not w.has("homing"):
		w["speed_mult"] = float(def.get("shot_speed_mult", 1.0))
	# #230: 敵ごとの全弾共通倍率。通常弾・追尾弾・バラマキ弾の個別倍率を保ったまま一律調整する。
	var all_speed_mult := float(def.get("projectile_speed_mult", 1.0))
	if all_speed_mult != 1.0:
		w["speed_mult"] = float(w.get("speed_mult", 1.0)) * all_speed_mult
	var proj := Area2D.new()
	proj.set_script(preload("res://scripts2d/Projectile2D.gd"))
	get_parent().add_child(proj)
	proj.global_position = global_position + origin_off
	proj.from_player = false
	proj.fire = is_fire
	proj.setup(d, w, tgt)

# #113/#117: 海賊船に炎上(スリップ被害)を与える
func ignite_slip(amount: float) -> void:
	if kind != "pirate":
		return
	_slip += amount
	if sprite:
		sprite.modulate = Color(1.8, 0.9, 0.5)
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.3)

# #193再3: 島や障害物で射線が遮られていないかを毎フレーム判定する。
# 遮られている間、遠隔敵は撃たずに遮蔽物の横へ回り込む。
var _cover_at: Vector2 = Vector2.ZERO
var _cover_blocked: bool = false

func _update_line_of_fire() -> void:
	_cover_blocked = false
	_cover_at = Vector2.ZERO
	if not is_instance_valid(player) or not ranged:
		return
	var to: Vector2 = player.global_position - global_position
	var dist := to.length()
	if dist < 1.0:
		return
	var dir := to / dist
	# 島(当たり判定の半径100)と障害物(実効半径)を見る
	for isle in get_tree().get_nodes_in_group("island_body"):
		if is_instance_valid(isle) and _segment_hits(isle.global_position, 100.0, dir, dist):
			_cover_blocked = true
			_cover_at = isle.global_position
			return
	for ob in get_tree().get_nodes_in_group("obstacle"):
		if not is_instance_valid(ob):
			continue
		var orad: float = float(ob.get("radius")) if ob.get("radius") != null else 50.0
		if _segment_hits(ob.global_position, orad * 0.8, dir, dist):
			_cover_blocked = true
			_cover_at = ob.global_position
			return

# 自分→プレイヤーの線分が、中心center・半径radiusの円と交差するか
func _segment_hits(center: Vector2, radius: float, dir: Vector2, dist: float) -> bool:
	var rel: Vector2 = center - global_position
	var along := rel.dot(dir)
	if along <= 0.0 or along >= dist:
		return false          # 後方、またはプレイヤーより遠い
	return absf(rel.cross(dir)) < radius

# 遮蔽物の横へ回り込むための横方向ステアリング
func _flank_dir(move_dir: Vector2) -> Vector2:
	var away: Vector2 = global_position - _cover_at
	if away.length() < 1.0:
		return move_dir
	var perp := away.rotated(PI / 2).normalized()
	if move_dir.dot(perp) < 0.0:
		perp = -perp          # 進行方向に近い側へ回り込む
	return (move_dir + perp * 1.6).normalized()

# #150: 島を迂回するステアリング。近い島から離れる+接線方向を混ぜて回り込む
# #193再: 海上の障害物(岩礁/流氷)も同じ仕組みで迂回し、引っかかって動けなくなるのを防ぐ
func _avoid_islands(move_dir: Vector2) -> Vector2:
	var result := move_dir
	for isle in get_tree().get_nodes_in_group("island_body"):
		if not is_instance_valid(isle):
			continue
		result = _steer_around(result, isle.global_position, 360.0 + _radius)
	for ob in get_tree().get_nodes_in_group("obstacle"):
		if not is_instance_valid(ob):
			continue
		var orad: float = float(ob.get("radius")) if ob.get("radius") != null else 50.0
		result = _steer_around(result, ob.global_position, orad + _radius + 70.0)
	return result.normalized()

# 指定の点から離れる反発+接線(進行方向に近い側へ回り込む)を合成する
func _steer_around(move_dir: Vector2, center: Vector2, avoid_r: float) -> Vector2:
	var away: Vector2 = global_position - center
	var d := away.length()
	if d >= avoid_r or d <= 1.0:
		return move_dir
	var strength: float = clampf(1.0 - d / avoid_r, 0.0, 1.0)
	var tangent: float = 1.0 if move_dir.dot(away.rotated(PI / 2)) >= 0.0 else -1.0
	return move_dir + (away.normalized() * 0.8 + away.rotated(PI / 2).normalized() * tangent * 0.9) * strength

# #118: 取り巻きが全滅したか
func _escorts_cleared() -> bool:
	for e in escorts:
		if is_instance_valid(e):
			return false
	return true

func _damage_player(amount: float) -> void:
	if GameState.docking_locked or _dead:
		return   # #237再2: 遅延して発火した攻撃で音・演出が出ないように
	GameState.damage_player(amount)   # 敏捷カット込み(クルー#39)
	# #69/#72: 触腕に絡めとられる(討伐まで鈍足) / 毒液スリップ
	if bool(def.get("entangle", false)) and is_instance_valid(player) and player.has_method("add_entangler"):
		player.add_entangler(self)
	if bool(def.get("poison", false)):
		GameState.apply_poison(6.0, 4.0)
	# #233再: 遠隔弾だけでなく近接攻撃でも被弾方向を知らせる(体当たり・薙ぎ払い・触腕)
	var world := get_parent()
	if world and world.has_method("show_damage_direction"):
		world.show_damage_direction(global_position)
	Audio.play("sfx_hit", -9.0)   # #47再2: 被ダメ音を少し小さく

func _draw() -> void:
	# 円形HPゲージ(#21): 上から時計回り。残量で緑→赤
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var r := _radius + 10.0
	draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(0, 0, 0, 0.35), 5.0)
	if frac > 0.0:
		var col := Color(1, 0.2, 0.15).lerp(Color(0.35, 1.0, 0.4), frac)
		draw_arc(Vector2.ZERO, r, -PI / 2, -PI / 2 + TAU * frac, 40, col, 5.0)
	# 魚雷ロック中の赤リング(#16)
	if locked:
		draw_arc(Vector2.ZERO, r + 9.0, 0, TAU, 40, Color(1, 0.15, 0.1, 0.9), 3.0)

func _process(_d: float) -> void:
	queue_redraw()   # ロックリング等の即時反映(軽量)

func _die() -> void:
	if _dead:
		return   # #148: 同一フレームの多重ヒットで名声/首を重複取得しないよう1回だけ
	_dead = true
	_fire_death_shot()   # #190再2/#71再: 撃墜された瞬間の打ち返し弾
	GameState.record_kill(kind, id)   # #177: 討伐記録(モブ・海賊のみ加算)
	match kind:
		"mob":
			if not GameState.add_cargo(id):
				GameState.notice.emit("%s を仕留めたが魚倉が満杯" % def.name)
		"pirate":
			GameState.add_head(id)
			GameState.add_fame(int(def.get("fame", 1)))
			if GameState.boss_rush:
				GameState.notice.emit("%s を撃退!" % def.name)   # #209再2
			else:
				GameState.notice.emit("%s を撃退(首を確保 / 名声+%d)" % [def.name, int(def.get("fame", 1))])
		"lord":
			# #187再2: 幽霊船など no_cargo の主は漁獲物にならない(魚倉を消費しない)
			if not bool(def.get("no_cargo", false)) and GameState.free_hold() >= int(def.cap):
				GameState.add_cargo(id, int(def.cap))
			# #239: 分裂した個体(夜の帝王の中/小コウモリ)は、まだ生き残りがいる間は
			# 討伐にならない。全滅した時点で「元の主」を討伐したものとして扱う。
			if split_root != "":
				var rest := 0
				for o in get_tree().get_nodes_in_group("enemy"):
					if o == self or not is_instance_valid(o) or o.is_queued_for_deletion():
						continue
					if str(o.get("split_root")) == split_root:
						rest += 1
				if rest > 0:
					GameState.notice.emit("%s を倒した(残り%d体)" % [def.name, rest])
					queue_free()
					return
				var rd: Dictionary = Database.lords.get(split_root, {})
				if not GameState.defeated_lords.has(split_root) and not GameState.claimed_lords.has(split_root):
					GameState.defeated_lords.append(split_root)
				var rf := int(rd.get("fame", 0))
				if rf > 0:
					GameState.add_fame(rf)
				# #209再11: ボスラッシュでは名声・賞金の案内を出さない(分裂する主の分岐が漏れていた)
				if GameState.boss_rush:
					GameState.notice.emit("近海の主 %s を討伐!" % str(rd.get("name", "?")))
				else:
					GameState.notice.emit("近海の主 %s を討伐! 名声+%d 賞金は酒場で受領" % [str(rd.get("name", "?")), rf])
				queue_free()
				return
			var is_pair: bool = bool(def.get("pair", false))
			var partner_alive: bool = is_pair and is_instance_valid(pair_partner) and not pair_partner.is_queued_for_deletion()
			if is_pair and partner_alive:
				GameState.notice.emit("番いの片割れ %s を倒した。もう1体も討て!" % def.name)
			else:
				if not GameState.defeated_lords.has(id) and not GameState.claimed_lords.has(id):
					GameState.defeated_lords.append(id)
				var lord_fame := int(def.get("fame", 0))   # #50: 主討伐で名声
				if lord_fame > 0:
					GameState.add_fame(lord_fame)
				if GameState.boss_rush:
					GameState.notice.emit("近海の主 %s を討伐!" % def.name)   # #209再2
				else:
					GameState.notice.emit("近海の主 %s を討伐! 名声+%d 賞金は酒場で受領" % [def.name, lord_fame])
	queue_free()
