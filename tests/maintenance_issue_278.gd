extends Node
## #278/#279/#266/#265再3/#258再4/#273再/#239: 今回の反映をまとめて検証する。
##
## ・#278 見た目の向上(提案1〜7)
## ・#279 夜の海域の専用BGM
## ・#266 船の燃料値
## ・#265再3 実績達成トースト
## ・#258再4 燃料節約の逓減
## ・#273再 幽霊船だけ逃げる向きで引き撃ち
## ・#239 グリフォンの説明文

const PixelFont = preload("res://scripts/PixelFont.gd")
const Juice = preload("res://scripts2d/Juice2D.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()

	# ---------------- #239: グリフォンの説明文 ----------------
	var glore := str(Database.lords["griffon"].lore)
	check(glore.begins_with("獅子の胴体"), "グリフォンの説明が獅子の胴体になっていない: " + glore)
	check(not glore.contains("馬の胴体"), "馬の胴体が残っている")

	# ---------------- #266: 船の燃料(food) ----------------
	var want_food := {"cutter": 140, "corvette": 160, "hunter_h": 150, "hauler": 170,
		"frigate_l": 180, "frigate_h": 190, "cruiser": 200, "dread": 220}
	for sid in want_food:
		check(int(Database.ships[sid].food) == int(want_food[sid]),
			"%s の燃料が指定値でない(%d)" % [str(Database.ships[sid].name), int(Database.ships[sid].food)])
	check(int(Database.ships["raft"].food) == 100 and int(Database.ships["skiff"].food) == 140,
		"指定外の船の燃料が変わっている")

	# ---------------- #279: 夜の海域の専用BGM ----------------
	check(Audio.BGM_FILES.has("bgm_night"), "bgm_night が登録されていない")
	check(ResourceLoader.exists(Audio.BGM_FILES["bgm_night"]), "夜.mp3 が無い")
	check(Audio._bgm_stream("bgm_night") != null, "夜のBGMを読み込めない")
	var world := preload("res://scripts2d/World2D.gd").new()
	for isle in Database.islands.size():
		GameState.current_island = isle
		var want := "bgm_night" if (isle == 2 or isle == 5 or isle == 6) else "bgm_sea"
		check(world._sea_bgm() == want,
			"島%d の航海BGMが違う(期待:%s / 実際:%s)" % [isle, want, world._sea_bgm()])
	world.free()

	# ---------------- #273再: 幽霊船だけ逃げる向きで引き撃ち ----------------
	check(bool(Database.lords["ghost"].get("kite_face_move", false)), "幽霊船が kite_face_move でない")
	for lid in Database.lords:
		if lid == "ghost":
			continue
		check(not bool(Database.lords[lid].get("kite_face_move", false)),
			"幽霊船以外(%s)が kite_face_move になっている" % lid)
	var esrc := _src("res://scripts2d/Enemy2D.gd")
	check(esrc.contains('if not bool(def.get("kite_face_move", false)):'),
		"引き撃ちの向きに kite_face_move の分岐が無い")

	# ---------------- #258再4: 燃料節約の逓減を少し強く ----------------
	var gsrc := _src("res://scripts/GameState.gd")
	check(gsrc.contains("18.0 + 7.0 * log(1.0 + (h - 18.0) / 7.0)"), "逓減の式が#258再4のものでない")
	GameState.reset_all()
	GameState.fleet[0].crew = [{"name": "a", "job": "veteran", "hp": 20, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var m20: float = GameState.food_drain_mult()
	GameState.fleet[0].crew = [{"name": "b", "job": "veteran", "hp": 100, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var m100: float = GameState.food_drain_mult()
	GameState.fleet[0].crew = [{"name": "c", "job": "veteran", "hp": 200, "agi": 0, "sht": 0, "int_": 0, "vis": 0}]
	var m200: float = GameState.food_drain_mult()
	check(absf((1.0 - m100) * 100.0 - 41.7) < 0.5,
		"体力100の節約が41.7ポイント付近でない(%.1f)" % ((1.0 - m100) * 100.0))
	check((m20 - m100) * 100.0 > 10.0, "体力20→100の差が小さすぎる(%.1fpt)" % ((m20 - m100) * 100.0))
	check((m100 - m200) * 100.0 < (m20 - m100) * 100.0, "逓減が効いていない")

	# ---------------- #265再3: 実績達成トースト ----------------
	check(GameState.has_signal("achievement_unlocked"), "achievement_unlocked シグナルが無い")
	check(gsrc.contains("achievement_unlocked.emit(aid)"), "実績達成時にシグナルを出していない")
	var toast := get_node_or_null("/root/AchievementToast")
	check(toast != null, "AchievementToast が autoload されていない")
	if toast != null:
		check(int(toast.get("layer")) > 20, "トーストが港UI(layer20)より前に出ない")
		check(absf(float(toast.POPUP_SEC) - 0.8) < 0.001, "トーストが0.8秒でない")
		toast._on_unlocked("lord_leviathan")
		await get_tree().process_frame
		var texts := ""
		var has_icon := false
		for n in toast.find_children("*", "Label", true, false):
			texts += str(n.text) + "/"
		for n in toast.find_children("*", "TextureRect", true, false):
			if n.texture != null:
				has_icon = true
		check(has_icon, "トーストにバッヂ絵が出ていない")
		check(texts.contains("レヴィアタン狩り"), "トーストに実績名が出ていない: " + texts)

	# ---------------- #278 提案1: 海のドット絵化 ----------------
	var osrc := _src("res://shaders/ocean2d.gdshader")
	check(osrc.contains("uniform float px_size"), "海に px_size が無い")
	check(osrc.contains("uniform float color_levels"), "海に color_levels が無い")
	check(osrc.contains("world = floor(world / pxs) * pxs"), "ワールド座標が量子化されていない")
	check(osrc.contains("col = floor(col * color_levels + 0.5) / color_levels"), "出力色が段階化されていない")
	check(not osrc.contains("length(SCREEN_UV - vec2(0.18, 0.13))"), "月の光が量子化前の座標のまま")
	var wsrc := _src("res://shaders/weather2d.gdshader")
	check(wsrc.contains("uniform float px_size"), "天候(雨・雪)が量子化されていない")

	# ---------------- #278 提案2: 島のドット絵化 ----------------
	for i in Database.islands.size():
		var ip := "res://assets/images/pixel/island_%d.png" % i
		check(ResourceLoader.exists(ip), "島のドット絵が無い: " + ip)
		var im := Image.load_from_file(ip)
		check(maxi(im.get_width(), im.get_height()) >= 200, "島のドット絵が小さい: " + ip)
		check(im.get_pixel(0, 0).a < 0.5 and im.get_pixel(im.get_width() - 1, 0).a < 0.5,
			"島のドット絵の背景が抜けていない: " + ip)
	var isrc := _src("res://scripts2d/Island2D.gd")
	check(isrc.contains("assets/images/pixel/island_%d.png"), "Island2D が島のドット絵を読んでいない")
	check(isrc.contains("_draw_dock_ring()"), "入港圏の破線が描かれない")

	# ---------------- #278 提案3: ピクセルフォント ----------------
	check(ResourceLoader.exists(PixelFont.PATH), "PixelMplus が同梱されていない")
	check(FileAccess.file_exists("res://assets/fonts/PixelMplus_LICENSE_E.txt"), "フォントのライセンスが同梱されていない")
	check(PixelFont.font() != null, "ピクセルフォントを読み込めない")
	if PixelFont.font() != null:
		check(PixelFont.font().antialiasing == TextServer.FONT_ANTIALIASING_NONE, "アンチエイリアスが切れていない")
	check(PixelFont.snap(22) == 24 and PixelFont.snap(12) == 12 and PixelFont.snap(3) == 12,
		"フォントサイズが12pxの整数倍に丸められていない")
	var hsrc := _src("res://scripts2d/HUD2D.gd")
	check(hsrc.contains("lbl_money = _pxlabel"), "資金がピクセルフォントでない")
	check(hsrc.contains("lbl_fame = _pxlabel"), "名声がピクセルフォントでない")
	check(hsrc.contains("lbl_food_val = _pxlabel"), "燃料の数値がピクセルフォントでない")
	check(hsrc.contains("var ammo := _pxlabel"), "残弾がピクセルフォントでない")
	check(hsrc.contains("lbl_hint = _label"), "長文のヒントまでピクセルフォントになっている")
	check(hsrc.contains("sb.set_corner_radius_all(0)") and hsrc.contains("sb.shadow_size = 2"),
		"HUDパネルがドットの枠線になっていない")

	# ---------------- #278 提案4/5: 打撃感・演出ズーム ----------------
	var w2 := _src("res://scripts2d/World2D.gd")
	check(w2.contains("func screen_shake("), "画面シェイクが無い")
	check(w2.contains("func hit_stop("), "ヒットストップが無い")
	check(w2.contains("func zoom_punch("), "演出ズームが無い")
	check(w2.contains("get_tree().create_timer(dur, true, false, true)"),
		"ヒットストップの復帰タイマーが time_scale の影響を受けてしまう")
	check(w2.contains("screen_shake(3.0, 0.15)"), "被弾時のシェイクが無い")
	check(w2.contains("zoom_punch(1.1, 0.2)"), "一斉射撃の演出ズームが無い")
	check(esrc.contains("w0.hit_stop(0.05, 0.05)"), "撃破時のヒットストップが無い")
	check(esrc.contains("Juice.debris("), "撃破の破片が無い")
	var shake_was := GameState.screen_shake
	GameState.set_screen_shake(true)
	GameState.screen_shake = false
	GameState.load_display_settings()
	check(GameState.screen_shake == true, "画面シェイクの設定が保存されない")
	GameState.set_screen_shake(false)
	GameState.screen_shake = true
	GameState.load_display_settings()
	check(GameState.screen_shake == false, "画面シェイクのOFFが保存されない")
	GameState.set_screen_shake(shake_was)   # テストで遊ぶ側の設定を書き換えない
	# #278 追加要望: 一度も触っていないとき(設定ファイル/項目が無いとき)の既定はON
	check(gsrc.contains("var screen_shake: bool = true"), "画面シェイクの既定がONでない")
	check(gsrc.contains('cfg.get_value("display", "screen_shake", true)'),
		"設定ファイルに項目が無いときの既定がONでない")
	check(_src("res://scripts/OverlayMenus.gd").contains("画面シェイク"), "設定メニューに画面シェイクが無い")
	var cols := Juice.sample_colors(load("res://assets/images/pixel/lord_leviathan.png"))
	check(cols.size() >= 3, "破片の色を拾えていない")

	# ---------------- #278 提案6: 夜の光 ----------------
	check(Juice.light_texture() != null, "光のテクスチャを作れない")
	var probe := Juice.make_light(Color.WHITE, 1.0, 100.0)
	check(probe is PointLight2D, "PointLight2D を使っていない")
	probe.free()
	check(w2.contains("func is_night_sea()"), "夜の海域の判定が無い")
	for bid in ["night_emperor", "night_bat_medium", "night_bat_small"]:
		check(Database.lords[bid].has("eye_glow"), "%s の目の光が設定されていない" % bid)
		check(Database.lords[bid].has("eye_glow_fb"), "%s の正面/背面の目の位置が無い" % bid)
	var psrc := _src("res://scripts2d/Projectile2D.gd")
	check(psrc.contains("Juice.glow(get_parent(), global_position"), "砲口炎の光が無い")
	check(psrc.contains('if kind == "explosion":'), "爆発の光が無い")
	check(Juice.GLOW_INTERVAL_MS > 0 and Juice.MAX_GLOW > 0, "光の数・間隔が絞られていない")

	# ---------------- #278 提案7: 小さな生気 ----------------
	check(osrc.contains("uniform float island_r[10]"), "海岸の白波の設定が無い")
	check(osrc.contains("col = mix(col, crest_color, clamp(band * flick * 0.6, 0.0, 1.0));"), "海岸の白波が描かれない")
	check(w2.contains('ocean_mat.set_shader_parameter("island_r", irad)'), "白波の半径が渡されていない")
	check(_src("res://scripts2d/Player2D.gd").contains("_hull.rotation = sin(_roll) * amp"), "旗艦のロールが無い")
	check(_src("res://scripts2d/Escort2D.gd").contains("_hull.rotation = sin(_roll) * amp"), "僚艦のロールが無い")
	check(_src("res://scripts2d/FishSchool2D.gd").contains("func _fish_jump()"), "魚の跳ねが無い")
	check(ResourceLoader.exists("res://assets/audio/sfx_horn.wav"), "汽笛が無い")
	check(w2.contains("func port_transition("), "入港・出港のフェードが無い")
	check(w2.contains('Audio.play("sfx_horn"'), "入港・出港で汽笛が鳴らない")

	# ---------------- #278再3: 汽笛を提供のmp3に差し替え/ガイド文字のフォントを戻す ----------------
	check(ResourceLoader.exists("res://assets/audio/汽笛.mp3"), "共有者提供の汽笛.mp3が無い")
	var asrc := _src("res://scripts/Audio.gd")
	check(asrc.contains('"sfx_horn": "res://assets/audio/汽笛.mp3"'), "汽笛が共有者提供のmp3に差し替わっていない")
	check(not hsrc.contains('lbl_guide = _pxlabel'), "ソナー下のガイド文字にピクセルフォントの指定が残っている")

	# ---------------- #278再5: 入港時は汽笛を鳴らさない/ガイド文字拡大/HUD透過/ボタン統一 ----------------
	check(w2.contains("port_transition(false)   # #278再4: 入港時は汽笛を鳴らさない"),
		"入港時に汽笛を鳴らさない実装が無い")
	# 出港側(_on_set_sail)は従来どおり汽笛つきで port_transition() を呼ぶ
	var sail_idx := w2.find("func _on_set_sail(")
	check(sail_idx != -1 and w2.substr(sail_idx, 300).contains("port_transition()"),
		"出港時の汽笛つき演出が無い")
	check(hsrc.contains('lbl_guide = _label("", 16)'), "ガイド文字が拡大されていない")
	check(hsrc.contains("lbl_guide.offset_left = -420"), "ガイド文字の幅が広げられていない(見切れ対策)")
	# 拡大後も最長の主の名前(ヒゲマッコウナガスクジラ)を含む文言がボックス幅に収まること
	var guide_font := ThemeDB.fallback_font
	var worst_guide := "ガイド: ヒゲマッコウナガスクジラ まで 約9990"
	var guide_w: float = guide_font.get_string_size(worst_guide, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	check(guide_w <= 404.0, "ガイド文字が最長ケースでボックス幅(404px)を超えて見切れる恐れがある(%.1fpx)" % guide_w)
	check(hsrc.contains("const PANEL_BG_ALPHA := 0.35"), "HUDパネルの透過度が下がっていない")
	check(hsrc.contains("func _style_btn("), "陣形・スキル・?ボタン用の共通スタイル関数が無い")
	check(hsrc.contains("_style_btn(help_btn)"), "?ボタンが資金・名声ウインドウと同じ見た目になっていない")
	check(hsrc.contains("_style_btn(b)   # #278再5"), "陣形ボタンが資金・名声ウインドウと同じ見た目になっていない")
	check(hsrc.contains("_style_btn(_skill_btn)"), "スキルボタンの既定が資金・名声ウインドウと同じ見た目になっていない")
	check(hsrc.contains("_style_btn(_skill_btn, Color(1.0, 0.2, 0.15))"), "スキルボタンの使用可能時の赤枠が無い")

	# ---------------- #232再8: 「大漁!獲得量2倍」表示の短縮 ----------------
	check(hsrc.contains("func show_catch_bonus(text: String, hold := 0.4)"), "大漁表示の保持時間が短縮されていない")
	check(hsrc.contains('tw.tween_property(lbl_catch, "modulate:a", 0.0, 0.3)'), "大漁表示のフェード時間が短縮されていない")

	# ---------------- #265再7: 実績「選択を解除」ボタンで横スクロールが出ないように ----------------
	var portsrc := _src("res://scripts/PortUI.gd")
	check(portsrc.contains("const ACH_BTN_W := 130.0"), "実績の選択ボタンの固定幅が無い")
	check(portsrc.contains("info.custom_minimum_size = Vector2(420, 0)"), "実績の説明欄の幅が詰められていない")
	check(portsrc.contains("b.custom_minimum_size = Vector2(ACH_BTN_W, 0)"),
		"「選択」/「選択を解除」ボタンの幅が統一されていない")

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK griffon/ship_fuel/night_bgm/ghost_kite/fuel_taper/ach_toast/pixel_sea/pixel_island/pixel_font/juice/night_light/small_life/no_horn_on_dock/guide_size/hud_transparency/btn_style/catch_toast_short/ach_btn_width")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
