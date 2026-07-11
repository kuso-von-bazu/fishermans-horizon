extends Area2D
## Projectile2D — 弾(ガトリング/大砲/銛/魚雷/敵弾)。魚雷は target を追尾。

const K := 6.0

var speed: float = 480.0
var dmg: float = 5.0
var life: float = 2.6
var slip: bool = false
var debuff: bool = false
var homing: bool = false
var fire: bool = false
var falloff: bool = false   # #63: ガトリング系は距離で威力減衰
var pirate_burn: float = 0.0   # #113/#117: 海賊船に炎上(スリップ)させる確率
var burn_chance: float = 0.0   # #72: 自機を炎上させる確率(ティアマット等)
var crit: bool = false         # #139: クリティカル(命中時にメッセージ)
var target: Node2D = null
var dir: Vector2 = Vector2.UP
var from_player: bool = true
var _t: float = 0.0
var _travel: float = 0.0
var _offscreen_t: float = 0.0   # #154: 画面外にいる時間

func setup(p_dir: Vector2, w: Dictionary, p_target: Node2D = null) -> void:
	dmg = float(w.get("dmg", 5))
	speed = (70.0 + float(w.get("dmg", 5)) * 0.3) * K * float(w.get("speed_mult", 1.0))   # #65: 弾速倍率
	slip = bool(w.get("slip", false))
	debuff = bool(w.get("debuff", false))
	homing = bool(w.get("homing", false))
	falloff = bool(w.get("falloff", false))
	pirate_burn = float(w.get("pirate_burn", 0.0))
	burn_chance = float(w.get("burn_chance", 0.0))
	crit = bool(w.get("crit", false))
	target = p_target
	dir = p_dir.normalized()
	# 見た目/当たり判定は全フラグ確定後に構築(add_child直後の_readyでは間に合わないため#78のバグ修正)
	_build_visual()

# #78: 攻撃の種類で弾の見た目(形+色)を大きく変えて見分けやすく。全体を拡大し暗い輪郭付き
func _build_visual() -> void:
	var poly := PackedVector2Array()
	var mcol := Color.WHITE
	var r := 4.0
	# #78再: 形・色の区別は維持。彩度を下げてシックな配色に。炎だけは火の玉状で例外
	if fire:
		# #78: 炎弾は火の玉状(進行方向=局所-Yが太く、後方が細い涙滴)。外=橙赤/内=黄の2色
		var drop := PackedVector2Array([
			Vector2(0, -9), Vector2(6, -4), Vector2(4.5, 2), Vector2(1.5, 11),
			Vector2(-1.5, 11), Vector2(-4.5, 2), Vector2(-6, -4)])
		var outline0 := Polygon2D.new()
		outline0.polygon = _scaled(drop, 1.4)
		outline0.color = Color(0, 0, 0, 0.55)
		add_child(outline0)
		var outer := Polygon2D.new()
		outer.polygon = drop
		outer.color = Color(0.85, 0.35, 0.12)   # 外炎(橙赤)
		add_child(outer)
		var inner := Polygon2D.new()
		inner.polygon = _scaled(PackedVector2Array([
			Vector2(0, -7), Vector2(3.2, -3), Vector2(2.2, 2), Vector2(0, 7),
			Vector2(-2.2, 2), Vector2(-3.2, -3)]), 1.0)
		inner.color = Color(1.0, 0.82, 0.35)     # 内炎(黄)
		add_child(inner)
		rotation = dir.angle() + PI / 2
		var colf := CollisionShape2D.new()
		var shf := CircleShape2D.new()
		shf.radius = 7.0
		colf.shape = shf
		add_child(colf)
		body_entered.connect(_on_hit)
		return
	if homing:
		# 魚雷: 細長いカプセル型(尾びれ付き)・くすんだ緑
		poly = PackedVector2Array([
			Vector2(-3, -9), Vector2(0, -12), Vector2(3, -9), Vector2(3, 7),
			Vector2(6, 12), Vector2(0, 9), Vector2(-6, 12), Vector2(-3, 7)])
		mcol = Color(0.42, 0.66, 0.46) if from_player else Color(0.55, 0.66, 0.34)
		r = 5.0
	elif falloff:
		# ガトリング: 細い曳光弾・くすんだ琥珀
		poly = PackedVector2Array([
			Vector2(-1.6, -8), Vector2(1.6, -8), Vector2(1.6, 8), Vector2(-1.6, 8)])
		mcol = Color(0.82, 0.74, 0.42) if from_player else Color(0.78, 0.6, 0.38)
		r = 3.0
	elif debuff:
		# 銛: 長い柄+返しのある穂先・くすんだ青緑
		poly = PackedVector2Array([
			Vector2(0, -13), Vector2(4, -6.5), Vector2(1.4, -6.5), Vector2(1.4, 11),
			Vector2(-1.4, 11), Vector2(-1.4, -6.5), Vector2(-4, -6.5)])
		mcol = Color(0.45, 0.62, 0.66)
		r = 4.5
	else:
		# 砲弾: 丸弾・くすんだ赤茶(自機)/暗赤(敵)
		for i in 12:
			var a := TAU * i / 12.0
			poly.append(Vector2(cos(a), sin(a)) * 6.0)
		mcol = Color(0.72, 0.45, 0.32) if from_player else Color(0.6, 0.3, 0.28)
		r = 6.0
	# 暗い輪郭(視認性UP)
	var outline := Polygon2D.new()
	outline.polygon = _scaled(poly, 1.45)
	outline.color = Color(0, 0, 0, 0.7)
	add_child(outline)
	var mesh := Polygon2D.new()
	mesh.polygon = poly
	mesh.color = mcol
	add_child(mesh)
	rotation = dir.angle() + PI / 2
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = r + 2.0
	col.shape = sh
	add_child(col)
	body_entered.connect(_on_hit)
	if homing:
		# 泡のトレイル(#30)
		var trail := CPUParticles2D.new()
		trail.amount = 20
		trail.lifetime = 0.6
		trail.initial_velocity_min = 4.0
		trail.initial_velocity_max = 14.0
		trail.scale_amount_min = 1.5
		trail.scale_amount_max = 3.0
		trail.color = Color(0.8, 0.95, 1.0, 0.6)
		add_child(trail)
		life = 4.0

func _scaled(poly: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * s)
	return out

func _physics_process(delta: float) -> void:
	_t += delta
	if homing:
		# #30再: 発射直後から急加速して直進し、敵に近づくほど弧を描いて追尾(蛇行なし)
		var accel_speed: float = speed * lerpf(0.45, 1.9, minf(_t / 0.5, 1.0))
		if is_instance_valid(target):
			var to_t: Vector2 = target.global_position - global_position
			var d: float = to_t.length()
			# 遠いうちはほぼ直進、近づくほど旋回力を上げて弧を描く
			var near: float = clampf(1.0 - d / (130.0 * K), 0.0, 1.0)
			var steer: float = lerpf(0.4, 9.0, near)
			dir = dir.lerp(to_t.normalized(), steer * delta).normalized()
		global_position += dir * accel_speed * delta
		rotation = dir.angle() + PI / 2   # #78: 魚雷は進行方向を向く
	else:
		global_position += dir * speed * delta
	_travel += speed * delta
	life -= delta
	# #154: 自機の弾は画面外に出てしばらくで消滅(離れすぎた敵に当てない)
	if from_player:
		var vp := get_viewport_rect().size
		var cam := get_viewport().get_camera_2d()
		if cam:
			var rel := global_position - (cam.global_position - vp * 0.5)
			var margin := 80.0
			if rel.x < -margin or rel.y < -margin or rel.x > vp.x + margin or rel.y > vp.y + margin:
				_offscreen_t += delta
				if _offscreen_t > 0.35:
					queue_free()
					return
			else:
				_offscreen_t = 0.0
	if life <= 0:
		queue_free()

# #63: より近い距離(22*K)から線形減衰、最低35%まで
func _eff_dmg() -> float:
	if not falloff:
		return dmg
	var factor: float = clampf(1.0 - maxf(_travel - 22.0 * K, 0.0) / (60.0 * K) * 0.65, 0.35, 1.0)
	return dmg * factor

func _on_hit(body: Node) -> void:
	if from_player and body.is_in_group("enemy"):
		# #101: 大破/寄港確定後は飛行中の弾も敵に当てない(討伐・賞金取得を防ぐ)
		if GameState.docking_locked:
			queue_free()
			return
		# #106: 魚雷(homing)は空中の敵をすり抜ける(他の敵への射線上でも当てない)
		if homing and body.get("aerial") == true:
			return
		if body.has_method("take_hit"):
			var res: int = body.take_hit(_eff_dmg(), slip, debuff, homing)   # #71: 魚雷(homing)は必中(no_dodge)
			if res == 2:
				return   # #111: 回避(弾は後方へそのまま通過)
			if res == 0:
				Audio.play("sfx_enemy_hit", -9.0)
				if crit:
					GameState.notice.emit("クリティカル!")   # #139: 命中時に表示
				var ekind = body.get("kind")
				var killed: bool = float(body.get("hp")) <= 0.0   # #116: とどめ判定
				# #113/#117: 海賊船に確率で炎上(スリップ)。主・モブは生き物なので対象外
				if pirate_burn > 0.0 and ekind == "pirate" and randf() < pirate_burn and body.has_method("ignite_slip"):
					body.ignite_slip(dmg * 0.8)
					_spawn_effect("fire", body.global_position)
				# #115: 大砲/魚雷の着弾は派手な爆発
				if homing or (not falloff and not debuff and not fire):
					_spawn_effect("explosion", body.global_position)
				# #116再: 血しぶきは主・モブにとどめを刺したときのみ(大きめ)
				if killed and (ekind == "lord" or ekind == "mob"):
					_spawn_effect("blood_big", body.global_position)
		queue_free()
	elif not from_player and body.is_in_group("player"):
		if fire:
			GameState.damage_player(_eff_dmg())   # #143: 通常ダメージ+炎上(永続チャンクなし)
			GameState.ignite(4.0)   # #65: ヒュドラの炎弾は被弾で必ず炎上(4.5秒)
		else:
			GameState.damage_player(_eff_dmg())   # 敏捷カット込み
			if burn_chance > 0.0 and randf() < burn_chance:
				GameState.ignite(4.0)   # #72: ティアマット等の弾は高確率で炎上
		# #115: 海賊の大砲/魚雷が自機に当たると派手な爆発
		if homing or (not falloff and not debuff and not fire):
			_spawn_effect("explosion", global_position)
		Audio.play("sfx_hit", -6.0)
		queue_free()
	elif body.is_in_group("island_body"):
		queue_free()

# #115/#116: 着弾エフェクト(爆発/炎/血しぶき)を親に生成(弾の消滅後も残す)
func _spawn_effect(kind: String, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.5
	get_parent().add_child(p)
	p.global_position = pos
	match kind:
		"explosion":
			p.amount = 24
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 200.0
			p.scale_amount_min = 3.0
			p.scale_amount_max = 7.0
			p.color = Color(1.0, 0.6, 0.15)
		"fire":
			p.amount = 14
			p.initial_velocity_min = 20.0
			p.initial_velocity_max = 70.0
			p.direction = Vector2(0, -1)
			p.gravity = Vector2(0, -40)
			p.scale_amount_min = 2.5
			p.scale_amount_max = 5.0
			p.color = Color(1.0, 0.4, 0.1)
		"blood":
			p.amount = 10
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 90.0
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.0
			p.color = Color(0.7, 0.05, 0.08)
		"blood_big":   # #116再: とどめ用の大きな血しぶき
			p.amount = 28
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 180.0
			p.scale_amount_min = 3.5
			p.scale_amount_max = 8.0
			p.color = Color(0.65, 0.04, 0.06)
	# 一定時間後に自動削除
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(p.queue_free)
