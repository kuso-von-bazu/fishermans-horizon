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
var _debuff_kind: String = ""
var _aggro: bool = false        # #32: 発見で加速
var _wander_dir: Vector2 = Vector2.RIGHT
var _wander_t: float = 0.0
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
	var base_speed: float = float(def.get("speed", 5.0 if kind == "lord" else 7.0))
	speed = base_speed * K * 1.2   # #84: 全敵の移動速度20%アップ
	# #69/#72: reach=触腕などで攻撃射程が伸びる。#74: 遠隔持ちはかなり遠くから撃つ
	var rng := 9.0
	if kind == "lord":
		rng = 60.0
	elif bool(def.get("ranged", false)):
		rng = 45.0
	attack_range = rng * K * float(def.get("reach", 1.0))
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
	_radius = target_w * 0.40
	attack_range += _radius
	# 本体スプライト(生成画像。なければ色付き楕円)
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # ドット絵をくっきり
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
	# ドット絵版(#26)優先。なければ元画像。
	var pixel := "res://assets/images/pixel/%s_%s.png" % [kind, id]
	if ResourceLoader.exists(pixel):
		return load(pixel)
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
	# #71: カリュブディス等は一定確率で攻撃をかわす(渦に潜る)
	if float(def.get("dodge", 0.0)) > 0.0 and randf() < float(def.get("dodge", 0.0)):
		if sprite:
			sprite.modulate = Color(0.5, 0.7, 1.6)
			var tw0 := create_tween()
			tw0.tween_property(sprite, "modulate", Color.WHITE, 0.25)
		return
	var mult := 1.25 if _debuff_t > 0.0 else 1.0
	hp -= amount * mult
	if slip and kind == "pirate":
		_slip += amount * 0.6
	if debuff and kind == "lord":
		_debuff_kind = GameState.harpoon_debuff
		_debuff_t = 6.0 * GameState.debuff_dur_mult()
		if _debuff_kind == "slip":
			_slip += amount * 0.8
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
		if _debuff_t <= 0.0:
			_debuff_kind = ""
	# 泳ぎアニメ(#26): 揺れ+伸縮でドット絵を動かす
	_bob += delta * (2.6 if _aggro else 1.4)
	if sprite:
		sprite.rotation = sin(_bob * 0.7) * 0.06
		var squash := 1.0 + sin(_bob * 2.0) * 0.05
		var base_s: float = sprite.scale.x
		sprite.scale.y = absf(base_s) * squash
	if not is_instance_valid(player):
		return
	var to: Vector2 = player.global_position - global_position
	var dist := to.length()
	# #32: 普段はゆっくり徘徊、発見(索敵圏内)で加速して追跡。#71: マーマンは索敵が広く好戦的
	var aggro_range: float = float(def.get("aggro", 900.0 if kind == "lord" else 640.0))
	if not _aggro and dist < aggro_range:
		_aggro = true
	var eff_speed := speed
	if _debuff_kind == "speed":
		eff_speed *= 0.55   # #37 鈍化
	var move_dir: Vector2
	if _aggro:
		move_dir = to.normalized()
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 4.5)
			_wander_dir = Vector2.RIGHT.rotated(randf() * TAU)
		move_dir = _wander_dir
		eff_speed *= 0.3
	# スプライトの向き(移動方向に左右反転・#26)
	if sprite and absf(move_dir.x) > 0.1:
		sprite.flip_h = move_dir.x < 0.0
		if _shadow:
			_shadow.flip_h = sprite.flip_h
	if not _aggro:
		velocity = move_dir * eff_speed
	elif dist > attack_range:
		velocity = move_dir * eff_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, eff_speed)
		_attack(delta, dist)
	move_and_slide()

func _attack(delta: float, dist: float) -> void:
	_atk_timer -= delta
	if _atk_timer > 0:
		return
	_atk_timer = attack_cd
	if _debuff_kind == "atkfreq":
		_atk_timer *= 1.7   # #37 麻痺: 攻撃間隔増
	var eff_dmg := dmg
	if _debuff_kind == "atk":
		eff_dmg *= 0.6      # #37 衰弱: 与ダメ減
	# #74: 遠隔持ちは attack_range(遠距離)で撃ち、近接圏(melee_r)に入られたら近接
	var melee_r: float = _radius + (12.0 if kind == "lord" else 9.0) * K * float(def.get("reach", 1.0))
	if kind == "lord":
		# #65: 全主が遠隔攻撃。近距離では従来の近接/固有技
		if id == "leviathan" and dist <= melee_r * 1.4:
			_damage_player(eff_dmg * 1.3)
			GameState.notice.emit("レヴィアタンの薙ぎ払い!")
		elif dist <= melee_r:
			_damage_player(eff_dmg)
		else:
			_ranged_attack(id == "hydra")
	elif kind == "pirate":
		# #77: 海賊は近接圏では近接攻撃もする
		if dist <= melee_r:
			if str(def.get("wpn", "")) == "all":
				_damage_player(eff_dmg * 1.6)   # #73: 海賊王の衝角突撃
				GameState.notice.emit("海賊王の衝角突撃!")
			else:
				_damage_player(eff_dmg)
		else:
			_ranged_attack(false)
	elif ranged:
		if dist <= melee_r:
			_damage_player(eff_dmg)
		else:
			_ranged_attack(false)
	elif dist <= attack_range:
		_damage_player(eff_dmg)

# #65/#66: way=扇状同時弾, homing=追跡弾を追加, wpn=gatling(3連小弾)/torpedo(追尾)/cannon
func _ranged_attack(is_fire: bool) -> void:
	var eff_dmg := dmg
	if _debuff_kind == "atk":
		eff_dmg *= 0.6
	var base_dir := (player.global_position - global_position).normalized()
	var wpn := str(def.get("wpn", ""))
	if wpn == "all":
		wpn = ["cannon", "gatling", "torpedo"][randi() % 3]   # #73: 海賊王は全武装
	match wpn:
		"gatling":
			for i in 3:
				_shoot(base_dir.rotated(randf_range(-0.07, 0.07)), {"dmg": eff_dmg * 0.35, "falloff": true}, false)
		"torpedo":
			_shoot(base_dir, {"dmg": eff_dmg, "homing": true}, false, player)
		_:
			var way := int(def.get("way", 1))
			for i in way:
				var off: float = (float(i) - float(way - 1) / 2.0) * 0.22
				_shoot(base_dir.rotated(off), {"dmg": eff_dmg}, is_fire)
			if bool(def.get("homing", false)):
				_shoot(base_dir, {"dmg": eff_dmg * 0.8, "homing": true}, is_fire, player)

func _shoot(d: Vector2, w: Dictionary, is_fire: bool, tgt: Node2D = null) -> void:
	var proj := Area2D.new()
	proj.set_script(preload("res://scripts2d/Projectile2D.gd"))
	get_parent().add_child(proj)
	proj.global_position = global_position
	proj.from_player = false
	proj.fire = is_fire
	proj.setup(d, w, tgt)

func _damage_player(amount: float) -> void:
	GameState.damage_player(amount)   # 敏捷カット込み(クルー#39)
	# #69/#72: 触腕に絡めとられる(討伐まで鈍足) / 毒液スリップ
	if bool(def.get("entangle", false)) and is_instance_valid(player) and player.has_method("add_entangler"):
		player.add_entangler(self)
	if bool(def.get("poison", false)):
		GameState.apply_poison(6.0, 4.0)
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
				var lord_fame := int(def.get("fame", 0))   # #50: 主討伐で名声
				if lord_fame > 0:
					GameState.add_fame(lord_fame)
				GameState.notice.emit("近海の主 %s を討伐! 名声+%d 賞金は酒場で受領" % [def.name, lord_fame])
	queue_free()
