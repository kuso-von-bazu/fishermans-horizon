extends CharacterBody2D
## Enemy2D — 主/戦闘モブ/海賊(見下ろし2D)。Codex生成の透過スプライトを本体に使用。
## 円形HPゲージ(#21)は _draw で描画。挙動は3D版Enemyを踏襲:
## 海賊=遠隔+近接(#9)、ヒュドラ=回復する炎、レヴィアタン=津波/薙ぎ払い、番い(#5相当は討伐管理)。

const K := 6.0

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
var sprite: Sprite2D
var _shadow: Sprite2D
var player: Node2D
var pair_partner: Node = null
var _bob: float = 0.0
var _radius: float = 40.0
var locked: bool = false   # 魚雷ロック対象の表示(#16)

func setup(p_kind: String, p_id: String) -> void:
	kind = p_kind
	id = p_id
	match kind:
		"mob": def = Database.combat_mobs[id]
		"pirate": def = Database.pirates[id]
		"lord": def = Database.lords[id]
	hp = float(def.hp)
	max_hp = hp
	dmg = float(def.dmg)
	ranged = bool(def.get("ranged", false))
	aerial = bool(def.get("aerial", false))
	speed = (5.0 if kind == "lord" else 7.0) * K
	attack_range = (12.0 if kind == "lord" else 9.0) * K

func _ready() -> void:
	add_to_group("enemy")
	_bob = randf() * TAU
	# 目標サイズ(px): 強いほど大きい
	var target_w := 90.0
	match kind:
		"pirate": target_w = clampf(90.0 + max_hp * 0.12, 100.0, 170.0)
		"mob": target_w = clampf(70.0 + max_hp * 0.25, 80.0, 150.0)
		"lord": target_w = clampf(120.0 + max_hp * 0.06, 150.0, 380.0)
	_radius = target_w * 0.45
	attack_range += _radius
	# 本体スプライト(生成画像。なければ色付き楕円)
	sprite = Sprite2D.new()
	var tex := _load_tex()
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2.ONE * (target_w / maxf(float(tex.get_width()), 1.0))
	else:
		sprite.texture = _placeholder(def.get("color", Color(0.7, 0.3, 0.3)))
		sprite.scale = Vector2.ONE * (target_w / 64.0)
	add_child(sprite)
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

func _load_tex() -> Texture2D:
	var path := "res://assets/images/%s_%s.png" % [kind, id]
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _placeholder(c: Color) -> Texture2D:
	var img := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 40:
		for x in 64:
			var d := Vector2((x - 32) / 32.0, (y - 20) / 20.0).length()
			if d < 1.0:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func take_hit(amount: float, slip: bool, debuff: bool) -> void:
	var mult := 1.25 if _debuff_t > 0.0 else 1.0
	hp -= amount * mult
	if slip and kind == "pirate":
		_slip += amount * 0.6
	if debuff and kind == "lord":
		_debuff_t = 6.0
	# 被弾フラッシュ
	if sprite:
		sprite.modulate = Color(2.2, 1.2, 1.2)
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.18)
	queue_redraw()
	if hp <= 0:
		_die()

func _physics_process(delta: float) -> void:
	if _slip > 0.0:
		var tick: float = minf(_slip, 8.0 * delta)
		hp -= tick
		_slip -= tick
		queue_redraw()
		if hp <= 0:
			_die()
			return
	if _debuff_t > 0.0:
		_debuff_t -= delta
	# 揺れ
	_bob += delta * 1.8
	if sprite:
		sprite.rotation = sin(_bob * 0.7) * 0.05
	if not is_instance_valid(player):
		return
	var to: Vector2 = player.global_position - global_position
	var dist := to.length()
	# スプライトの向き(左右反転のみ。海図イラスト風)
	if sprite and absf(to.x) > 4.0:
		sprite.flip_h = to.x < 0.0
		if _shadow:
			_shadow.flip_h = sprite.flip_h
	if dist > attack_range:
		velocity = to.normalized() * speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed)
		_attack(delta, dist)
	move_and_slide()

func _attack(delta: float, dist: float) -> void:
	_atk_timer -= delta
	if _atk_timer > 0:
		return
	_atk_timer = attack_cd
	if id == "leviathan":
		if dist <= attack_range * 1.4:
			_damage_player(dmg * 1.3)
			GameState.notice.emit("レヴィアタンの薙ぎ払い!")
		else:
			_damage_player(dmg)
			GameState.notice.emit("レヴィアタンの津波!")
	elif id == "hydra":
		_ranged_attack(true)
	elif ranged:
		if dist <= attack_range * 0.6:
			_damage_player(dmg)
		else:
			_ranged_attack(false)
	elif dist <= attack_range:
		_damage_player(dmg)

func _ranged_attack(is_fire: bool) -> void:
	var proj := Area2D.new()
	proj.set_script(preload("res://scripts2d/Projectile2D.gd"))
	get_parent().add_child(proj)
	proj.global_position = global_position
	proj.from_player = false
	proj.fire = is_fire
	proj.setup((player.global_position - global_position).normalized(), {"dmg": dmg})

func _damage_player(amount: float) -> void:
	GameState.run_armor = maxf(GameState.run_armor - amount, 0.0)
	GameState.stats_changed.emit()
	Audio.play("sfx_hit", -5.0)

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
	match kind:
		"mob":
			if not GameState.add_cargo(id):
				GameState.notice.emit("%s を仕留めたが魚倉が満杯" % def.name)
		"pirate":
			GameState.add_head(id)
			GameState.add_fame(int(def.get("fame", 1)))
			GameState.notice.emit("%s を撃退(首を確保 / 名声+%d)" % [def.name, int(def.get("fame", 1))])
		"lord":
			if GameState.free_hold() >= int(def.cap):
				GameState.add_cargo(id, int(def.cap))
			var is_pair: bool = bool(def.get("pair", false))
			var partner_alive: bool = is_pair and is_instance_valid(pair_partner) and not pair_partner.is_queued_for_deletion()
			if is_pair and partner_alive:
				GameState.notice.emit("番いの片割れ %s を倒した。もう1体も討て!" % def.name)
			else:
				if not GameState.defeated_lords.has(id) and not GameState.claimed_lords.has(id):
					GameState.defeated_lords.append(id)
				GameState.notice.emit("近海の主 %s を討伐! 賞金は酒場で受領" % def.name)
	queue_free()
