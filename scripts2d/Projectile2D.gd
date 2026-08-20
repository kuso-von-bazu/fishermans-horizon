extends Area2D
## Projectile2D — 弾(ガトリング/大砲/銛/魚雷/敵弾)。魚雷は target を追尾。

const K := 6.0

var speed: float = 480.0
var dmg: float = 5.0
var life: float = 2.6
var slip: bool = false
var debuff: bool = false
var debuff_kind: String = ""   # #196再: 銛の効果は撃った艦の設定を使う
var homing: bool = false
var fire: bool = false
var falloff: bool = false   # #63: ガトリング系は距離で威力減衰
var pirate_burn: float = 0.0   # #113/#117: 海賊船に炎上(スリップ)させる確率
var burn_chance: float = 0.0   # #72: 自機を炎上させる確率(ティアマット等)
var crit: bool = false         # #139: クリティカル(命中時にメッセージ)
var fire_look: bool = false    # #167: 見た目だけ炎弾(挙動は通常)
var shape: String = ""         # #65再: "ellipse"等の弾形状指定
var bcolor: Color = Color(0, 0, 0, 0)   # #65再: 弾のカスタム色(alpha>0で有効)
var spread_homing: bool = false   # #65再: 発射後に扇状へ広がってから急加速して追尾
var poison_only: bool = false     # #194: 直接ダメージ無しで毒のスリップのみ与える弾(ダゴン)
var flame_color: Color = Color(0, 0, 0, 0)   # #72再: 炎弾の色替え(ザッハーク=白い炎)
var target: Node2D = null
var dir: Vector2 = Vector2.UP
var from_player: bool = true
var _t: float = 0.0
var _travel: float = 0.0
var _offscreen_t: float = 0.0   # #154: 画面外にいる時間
var _dangerous_to_player: bool = false   # #233: 現在軌道が旗艦へ向かう敵弾
var pierce: bool = false          # #248: 槍砲。命中しても消えず敵を貫通する
var _pierced: Array = []          # 同じ敵に多重ヒットしないよう記録
var cluster: int = 0              # #248: クラスター魚雷。発射後すぐこの数へ分裂する
var _cluster_def: Dictionary = {}
var _cluster_t: float = 0.0
# #239再6: 音符弾。進行方向へ回さず立てたまま、左右に蛇行しながら飛ぶ
var upright: bool = false
var wave_amp: float = 0.0
var wave_freq: float = 0.0
var _wave_ph: float = 0.0
var stream: float = 0.0   # #251: 放射系。この距離を飛ぶと消える(短いリーチ)
var _aerial_told: bool = false   # #106再: 空中の敵をすり抜けた案内は弾ごとに1回だけ
var art: String = ""   # #251再: 弾の絵(指定時は図形の代わりに画像を出す。当たり判定は図形のまま)
# #248再2: クラスター魚雷の子。広く分かれてから収束し、一度外したら引き返さない
var no_uturn: bool = false
var turn_min: float = 0.4
var turn_max: float = 9.0
var home_delay: float = 0.0   # #248再2: この秒数は追尾せず直進(広がってから追い始める)

func setup(p_dir: Vector2, w: Dictionary, p_target: Node2D = null) -> void:
	# #149再3/#196: レイヤー1(自機/島/障害物)+2(敵)+4(僚艦) をすべて見る
	collision_mask = 7
	dmg = float(w.get("dmg", 5))
	speed = (70.0 + float(w.get("dmg", 5)) * 0.3) * K * float(w.get("speed_mult", 1.0))   # #65: 弾速倍率
	if from_player:
		speed *= GameState.formation_passive("shot_speed")   # #224再2: 斜線陣
	else:
		add_to_group("enemy_shot")   # #224再2: 防御弾幕(輪形陣)の迎撃対象
	if GameState.active_weather == "storm" and not GameState.boss_rush:
		speed *= 0.9   # #232: 嵐は敵味方とも遠隔弾速-10%
	slip = bool(w.get("slip", false))
	debuff = bool(w.get("debuff", false))
	debuff_kind = str(w.get("debuff_kind", ""))
	homing = bool(w.get("homing", false))
	falloff = bool(w.get("falloff", false))
	pirate_burn = float(w.get("pirate_burn", 0.0))
	burn_chance = float(w.get("burn_chance", 0.0))
	crit = bool(w.get("crit", false))
	fire_look = bool(w.get("fire_look", false))
	shape = str(w.get("shape", ""))
	bcolor = w.get("bcolor", Color(0, 0, 0, 0))
	spread_homing = bool(w.get("spread_homing", false))
	pierce = bool(w.get("pierce", false))
	stream = float(w.get("stream", 0.0))
	art = str(w.get("art", ""))
	no_uturn = bool(w.get("no_uturn", false))
	turn_min = float(w.get("turn_min", 0.4))
	turn_max = float(w.get("turn_max", 9.0))
	home_delay = float(w.get("home_delay", 0.0))
	upright = bool(w.get("upright", false))
	wave_amp = float(w.get("wave_amp", 0.0))
	wave_freq = float(w.get("wave_freq", 0.0))
	_wave_ph = randf() * TAU
	cluster = int(w.get("cluster", 0))
	if cluster > 0:
		_cluster_def = w.duplicate()      # 分裂後の子はこの定義から作る(分裂はしない)
		_cluster_def.erase("cluster")
	# #248: 乱射砲はエイム方向から少しずれて飛ぶ
	var spray := float(w.get("spray", 0.0))
	if spray > 0.0:
		p_dir = p_dir.rotated(randf_range(-spray, spray))
	poison_only = bool(w.get("poison_only", false))
	flame_color = w.get("flame_color", Color(0, 0, 0, 0))
	target = p_target
	dir = p_dir.normalized()
	# #158: 敵の遠隔弾は距離が離れても消えないよう寿命を延長(引き撃ち対策)
	if not from_player and not homing:
		life = 9.0
	# 見た目/当たり判定は全フラグ確定後に構築(add_child直後の_readyでは間に合わないため#78のバグ修正)
	_build_visual()

# #78: 攻撃の種類で弾の見た目(形+色)を大きく変えて見分けやすく。全体を拡大し暗い輪郭付き
func _build_visual() -> void:
	var poly := PackedVector2Array()
	var mcol := Color.WHITE
	var r := 4.0
	# #78再: 形・色の区別は維持。彩度を下げてシックな配色に。炎だけは火の玉状で例外
	if fire or fire_look:   # #167: fire_look=見た目だけ炎弾
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
		outer.color = flame_color if flame_color.a > 0.0 else Color(0.85, 0.35, 0.12)   # #72再: flame_colorで色替え
		add_child(outer)
		var inner := Polygon2D.new()
		inner.polygon = _scaled(PackedVector2Array([
			Vector2(0, -7), Vector2(3.2, -3), Vector2(2.2, 2), Vector2(0, 7),
			Vector2(-2.2, 2), Vector2(-3.2, -3)]), 1.0)
		inner.color = (flame_color.lerp(Color.WHITE, 0.55) if flame_color.a > 0.0 else Color(1.0, 0.82, 0.35))     # 内炎
		add_child(inner)
		rotation = dir.angle() + PI / 2
		var colf := CollisionShape2D.new()
		var shf := CircleShape2D.new()
		shf.radius = 7.0
		colf.shape = shf
		add_child(colf)
		body_entered.connect(_on_hit)
		return
	if shape == "ellipse_s":
		# #65再2: 小型の楕円弾(主のバラマキ用)。色はbcolorで指定
		for i in 14:
			var ae := TAU * i / 14.0
			poly.append(Vector2(cos(ae) * 2.4, sin(ae) * 5.2))
		mcol = Color(0.8, 0.8, 0.8)
		r = 3.4
	elif shape == "grain":
		# #71再: 小型の米粒状(カリュブディスの打ち返し弾)
		for i in 12:
			var ag := TAU * i / 12.0
			poly.append(Vector2(cos(ag) * 2.0, sin(ag) * 4.4))
		mcol = Color(0.8, 0.8, 0.8)
		r = 3.0
	elif shape == "star":
		# #190: オニヒトデの星形弾(5角星)。回転しながら飛ぶので進行方向へは向けない
		for i in 10:
			var a := TAU * i / 10.0 - PI / 2.0
			var rr: float = 8.5 if i % 2 == 0 else 3.6
			poly.append(Vector2(cos(a), sin(a)) * rr)
		mcol = Color(0.86, 0.62, 0.30)
		r = 5.5
	elif shape == "small":
		# #190: レギオンの小型弾(小魚が吐く小さな水弾)
		# #190再2: 少しだけ大きく(縦横ともおよそ1.25倍)
		for i in 10:
			var a := TAU * i / 10.0
			poly.append(Vector2(cos(a) * 3.3, sin(a) * 5.3))
		mcol = Color(0.62, 0.78, 0.86)
		r = 4.0
	elif shape == "lance_spear":
		# #248再2: 槍砲。鋭く尖った細長い槍。他の弾より大きめ
		poly = PackedVector2Array([
			Vector2(0, -22.0), Vector2(3.4, -11.0), Vector2(2.4, 6.0), Vector2(1.4, 16.0),
			Vector2(-1.4, 16.0), Vector2(-2.4, 6.0), Vector2(-3.4, -11.0)])
		mcol = Color(0.78, 0.80, 0.86)
		r = 7.0
	elif shape == "flame_jet":
		# #251: 火炎放射器。先が太く後ろが細い炎の粒。飛ぶほど広がるので少し大きめ
		poly = PackedVector2Array([
			Vector2(0, -7.5), Vector2(4.6, -2.6), Vector2(3.4, 3.0), Vector2(1.2, 8.2),
			Vector2(-1.2, 8.2), Vector2(-3.4, 3.0), Vector2(-4.6, -2.6)])
		mcol = Color(0.98, 0.55, 0.16)
		r = 6.0
	elif shape == "frost_jet":
		# #251: 冷気放射器。角張った氷片
		poly = PackedVector2Array([
			Vector2(0, -7.0), Vector2(3.2, -3.4), Vector2(4.2, 2.2), Vector2(0, 7.6),
			Vector2(-4.2, 2.2), Vector2(-3.2, -3.4)])
		mcol = Color(0.72, 0.93, 1.0)
		r = 5.6
	elif shape == "needle":
		# #239: ラミアの針状弾。細長く鋭い菱形で、進行方向へ向く
		poly.append(Vector2(0, -11.0))
		poly.append(Vector2(2.2, 0))
		poly.append(Vector2(0, 6.0))
		poly.append(Vector2(-2.2, 0))
		mcol = Color(0.82, 0.72, 0.95)
		r = 4.0
	elif shape == "note":
		# #239: セイレーンの音符弾。丸い符頭と縦の符幹(蛇行しながら飛ぶ)
		# #239再9: 符頭の円と符幹を1つの多角形として並べると自己交差して
		# 三角形分割に失敗し、弾が一切描画されなかった。図形の和で単純な輪郭を作る。
		var head := PackedVector2Array()
		for i in 14:
			var a := TAU * i / 14.0
			head.append(Vector2(cos(a) * 5.2 - 1.6, sin(a) * 4.2 + 3.4))
		var stem := PackedVector2Array([
			Vector2(1.4, -8.6), Vector2(3.0, -8.6), Vector2(3.0, 3.4), Vector2(1.4, 3.4)])
		var merged := Geometry2D.merge_polygons(head, stem)
		poly = merged[0] if merged.size() > 0 else head
		mcol = Color(0.96, 0.82, 0.98)
		r = 5.0
	elif shape == "ellipse":
		# #65再: 細長い楕円弾(長軸=進行方向=プレイヤー向き)。色はbcolorで指定
		for i in 16:
			var a := TAU * i / 16.0
			poly.append(Vector2(cos(a) * 3.4, sin(a) * 8.0))
		mcol = bcolor if bcolor.a > 0.0 else Color(0.8, 0.8, 0.8)
		r = 5.0
	elif homing:
		# 魚雷: 細長いカプセル型(尾びれ付き)・くすんだ緑
		poly = PackedVector2Array([
			Vector2(-3.6, -10.8), Vector2(0, -14.4), Vector2(3.6, -10.8), Vector2(3.6, 8.4),
			Vector2(7.2, 14.4), Vector2(0, 10.8), Vector2(-7.2, 14.4), Vector2(-3.6, 8.4)])   # #78再: 少しだけ大きく
		mcol = Color(0.42, 0.66, 0.46) if from_player else Color(0.55, 0.66, 0.34)
		r = 6.0
	elif falloff:
		# #78再: ガトリング=細長い銃弾の形(先端が尖り、後端は平ら)。大きさは従来と同程度
		poly = PackedVector2Array([
			Vector2(0, -9.0), Vector2(1.5, -5.5), Vector2(1.7, 6.5), Vector2(1.2, 8.0),
			Vector2(-1.2, 8.0), Vector2(-1.7, 6.5), Vector2(-1.5, -5.5)])
		mcol = Color(0.82, 0.74, 0.42) if from_player else Color(0.78, 0.6, 0.38)
		r = 3.0
	elif debuff:
		# 銛: 長い柄+返しのある穂先・くすんだ青緑
		poly = PackedVector2Array([
			Vector2(0, -15.5), Vector2(4.8, -7.8), Vector2(1.7, -7.8), Vector2(1.7, 13.2),
			Vector2(-1.7, 13.2), Vector2(-1.7, -7.8), Vector2(-4.8, -7.8)])   # #78再: 少しだけ大きく
		mcol = Color(0.45, 0.62, 0.66)
		r = 5.4
	else:
		# 砲弾: 丸弾・くすんだ赤茶(自機)/暗赤(敵)
		for i in 12:
			var a := TAU * i / 12.0
			poly.append(Vector2(cos(a), sin(a)) * 7.2)   # #78再: 少しだけ大きく
		mcol = Color(0.72, 0.45, 0.32) if from_player else Color(0.6, 0.3, 0.28)
		r = 7.2
	# #71再: bcolor指定があれば形状によらず色を上書き(紺色のカリュブディス弾など)
	if bcolor.a > 0.0:
		mcol = bcolor
	# 暗い輪郭(視認性UP)
	var outline := Polygon2D.new()
	outline.polygon = _scaled(poly, 1.45)
	outline.color = Color(0, 0, 0, 0.7)
	add_child(outline)
	# #251再: art 指定があれば図形の代わりに絵を出す(輪郭・当たり判定はそのまま)
	var art_tex: Texture2D = null
	if art != "" and ResourceLoader.exists(art):
		art_tex = load(art)
	if art_tex != null:
		outline.visible = false
		var spr := Sprite2D.new()
		spr.texture = art_tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var longest: float = float(maxi(art_tex.get_width(), art_tex.get_height()))
		spr.scale = Vector2.ONE * ((r + 2.0) * 2.6 / maxf(longest, 1.0))
		add_child(spr)
	else:
		var mesh := Polygon2D.new()
		mesh.polygon = poly
		mesh.color = mcol
		add_child(mesh)
	if not upright:
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
		# #248再2: クラスター魚雷の子は広がってから収束するぶん飛行距離が長い
		if home_delay > 0.0:
			life = 7.0

func _scaled(poly: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * s)
	return out

func _physics_process(delta: float) -> void:
	_t += delta
	if cluster > 0:
		_cluster_t += delta
		if _cluster_t >= 0.28:
			_split_cluster()
			return
	if shape == "star":
		rotation += delta * 5.0   # #190: 星形弾はくるくる回りながら飛ぶ
	if homing and spread_homing:
		# #65再: 前半は低速で初期方向(扇状)へ広がり、後半で急加速しながら船へ追尾
		if _t < 0.55:
			global_position += dir * speed * 0.32 * delta
		else:
			var acc: float = speed * lerpf(0.6, 2.4, minf((_t - 0.55) / 0.5, 1.0))
			if is_instance_valid(target):
				var tt: Vector2 = target.global_position - global_position
				dir = dir.lerp(tt.normalized(), 7.0 * delta).normalized()
			global_position += dir * acc * delta
		rotation = dir.angle() + PI / 2
	elif homing:
		# #30再: 発射直後から急加速して直進し、敵に近づくほど弧を描いて追尾(蛇行なし)
		var accel_speed: float = speed * lerpf(0.45, 1.9, minf(_t / 0.5, 1.0))
		if is_instance_valid(target) and _t >= home_delay:
			var to_t: Vector2 = target.global_position - global_position
			var d: float = to_t.length()
			# #248再2: 一度大きく外した弾は引き返さない(目標を捨てて直進する)
			if no_uturn and dir.dot(to_t.normalized()) < -0.17:
				target = null
			else:
				# 遠いうちはほぼ直進、近づくほど旋回力を上げて弧を描く
				var near: float = clampf(1.0 - d / (130.0 * K), 0.0, 1.0)
				var steer: float = lerpf(turn_min, turn_max, near)
				dir = dir.lerp(to_t.normalized(), steer * delta).normalized()
		global_position += dir * accel_speed * delta
		rotation = dir.angle() + PI / 2   # #78: 魚雷は進行方向を向く
	else:
		global_position += dir * speed * delta
		# #239再6: 蛇行(進行方向に対して左右へ振れながら進む)
		if wave_amp > 0.0:
			_wave_ph += delta * wave_freq
			global_position += dir.orthogonal() * cos(_wave_ph) * wave_amp * delta
	_travel += speed * delta
	if stream > 0.0 and _travel > stream:
		queue_free()   # #251: 放射系はリーチ外で消える
		return
	_update_danger_outline()
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

# #248: クラスター魚雷。右斜め前・正面・左斜め前へ分かれてから、それぞれが敵を追う
func _split_cluster() -> void:
	var n := cluster
	cluster = 0
	var parent := get_parent()
	if parent == null:
		queue_free()
		return
	# #248再2: 子は「本体の威力を等分」し、より広い扇へ分かれてから収束する
	var cdef := _cluster_def.duplicate()
	cdef["dmg"] = float(_cluster_def.get("dmg", 0.0)) / float(maxi(n, 1))
	cdef["no_uturn"] = true
	cdef["home_delay"] = 0.72   # まず広がってから追い始める(近い敵には左右が届かない)
	for i in n:
		var t: float = (float(i) / float(maxi(n - 1, 1))) * 2.0 - 1.0 if n > 1 else 0.0
		var child := Area2D.new()
		child.set_script(get_script())
		parent.add_child(child)
		child.global_position = global_position
		child.from_player = from_player
		child.setup(dir.rotated(t * deg_to_rad(55.0)), cdef, target)
	queue_free()

func _update_danger_outline() -> void:
	var was := _dangerous_to_player
	_dangerous_to_player = false
	if not from_player:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty() and is_instance_valid(players[0]):
			var rel: Vector2 = players[0].global_position - global_position
			var along := rel.dot(dir)
			_dangerous_to_player = along > 0.0 and along < 900.0 and absf(rel.cross(dir)) < 30.0
	if was != _dangerous_to_player:
		queue_redraw()

func _draw() -> void:
	if _dangerous_to_player:
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(1.0, 0.92, 0.48, 0.95), 3.0)

func _spawn_critical_text(pos: Vector2) -> void:
	var world := get_parent()
	if world == null:
		return
	var l := Label.new()
	l.text = "クリティカル!"
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.15))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.0, 0.95))
	l.position = pos - Vector2(76, 42)
	l.z_index = 80
	world.add_child(l)
	var tw := world.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 42.0, 0.75)
	tw.tween_property(l, "modulate:a", 0.0, 0.75)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)

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
			# #106再: すり抜けた理由が分からないと不具合に見えるので1回だけ知らせる
			if from_player and not _aerial_told:
				_aerial_told = true
				GameState.notice.emit("魚雷は空中の敵には当たらない!")
			return
		if pierce and _pierced.has(body.get_instance_id()):
			return   # #248: 貫通弾は同じ敵に二重に当てない
		if body.has_method("take_hit"):
			if pierce:
				_pierced.append(body.get_instance_id())
			var res: int = body.take_hit(_eff_dmg(), slip, debuff, homing, debuff_kind)   # #71: 魚雷(homing)は必中(no_dodge)
			if res == 2:
				return   # #111: 回避(弾は後方へそのまま通過)
			if res == 0:
				Audio.play("sfx_enemy_hit", -18.0)   # #47再2: 与ダメ音をさらに小さく
				if crit:
					_spawn_critical_text(body.global_position)   # #233: トーストではなく命中位置へ表示
					Audio.play("sfx_crit", -4.0)   # #233再: 着弾音を土台にした専用の高音SFX
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
		if pierce:
			return   # #248: 槍砲は敵を貫通して飛び続ける
		queue_free()
	elif not from_player and body.is_in_group("player"):
		# #237: 寄港確定後はダメージだけでなく音・演出も出さない
		# (damage_player は docking_locked で早期returnするが、以前は
		#  被弾音・爆発・被弾方向フラッシュだけが鳴り続けていた)
		if GameState.docking_locked:
			queue_free()
			return
		var world := get_parent()
		if world and world.has_method("show_damage_direction"):
			world.show_damage_direction(global_position)
		if fire:
			GameState.damage_player(_eff_dmg())   # #143: 通常ダメージ+炎上(永続チャンクなし)
			GameState.ignite(4.0)   # #65: ヒュドラの炎弾は被弾で必ず炎上(4.5秒)
		elif poison_only:
			GameState.apply_poison(6.0, 4.0)   # #194: ダゴンの弾は直接ダメージ無し・毒のスリップのみ
		else:
			GameState.damage_player(_eff_dmg())   # 敏捷カット込み
			if burn_chance > 0.0 and randf() < burn_chance:
				GameState.ignite(4.0)   # #72: ティアマット等の弾は高確率で炎上
		# #115: 海賊の大砲/魚雷が自機に当たると派手な爆発
		if homing or (not falloff and not debuff and not fire):
			_spawn_effect("explosion", global_position)
		Audio.play("sfx_hit", -10.0)   # #47再2: 被ダメ音も少し小さく
		queue_free()
	elif not from_player and body.is_in_group("fleet_ship"):
		# #196: 敵弾は僚艦にも当たる(装甲0でその艦だけ離脱)
		# #215: 旗艦と同様に炎上・毒のスリップも入る
		if GameState.docking_locked:   # #237: 寄港確定後は僚艦の被弾音も鳴らさない
			queue_free()
			return
		if fire and body.has_method("ignite"):
			body.take_damage(_eff_dmg())
			body.ignite(4.0)
		elif poison_only and body.has_method("apply_poison"):
			body.apply_poison(6.0, 4.0)   # ダゴンの弾は直接ダメージ無し
		elif body.has_method("take_damage"):
			body.take_damage(_eff_dmg())
			if burn_chance > 0.0 and randf() < burn_chance and body.has_method("ignite"):
				body.ignite(4.0)
		Audio.play("sfx_hit", -13.0)   # #47再2: 僚艦の被ダメ音も少し小さく
		queue_free()
	elif from_player and body.is_in_group("fleet_ship"):
		return   # 味方の弾は僚艦をすり抜ける(フレンドリーファイア無し)
	elif body.is_in_group("island_body"):
		queue_free()
	elif body.is_in_group("obstacle"):
		queue_free()   # #193: 岩礁・流氷は敵味方どちらの弾も止める(障害物は壊れない)

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
