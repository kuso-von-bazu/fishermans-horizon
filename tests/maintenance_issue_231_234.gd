extends Node

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_all()
	GameState.fleet = [
		GameState.new_ship_entry("raft", ["gatling"]),
		GameState.new_ship_entry("raft", ["gatling"]),
	]
	var marine := {"name":"試験水兵","job":"marine","hp":1,"agi":1,"sht":8,"int_":0,"vis":1}
	GameState.fleet[0].crew = [marine.duplicate(true)]
	GameState.fleet[1].crew = [marine.duplicate(true), marine.duplicate(true)]
	check(absf(GameState.crit_chance() - 0.05) < 0.0001, "旗艦の水兵1名は5%")
	check(absf(GameState.crit_chance_of(1) - 0.09) < 0.0001, "僚艦の水兵2名は9%")
	check(GameState.crit_chance_of(99) == 0.0, "範囲外の艦は0%")

	var Projectile = preload("res://scripts2d/Projectile2D.gd")
	var w := {"dmg":10.0,"speed_mult":1.0}
	GameState.boss_rush = false
	GameState.active_weather = ""
	var p0 := Area2D.new(); p0.set_script(Projectile); add_child(p0); p0.setup(Vector2.RIGHT,w)
	var normal_speed: float = p0.speed
	GameState.active_weather = "storm"
	var p1 := Area2D.new(); p1.set_script(Projectile); add_child(p1); p1.setup(Vector2.RIGHT,w)
	check(absf(p1.speed / normal_speed - 0.9) < 0.0001, "嵐の弾速は敵味方共通で90%")
	var target_player := Node2D.new()
	target_player.add_to_group("player")
	target_player.global_position = Vector2(300, 0)
	add_child(target_player)
	p1.from_player = false
	p1.global_position = Vector2.ZERO
	p1.dir = Vector2.RIGHT
	p1._update_danger_outline()
	check(p1._dangerous_to_player, "旗艦へ向かう敵弾だけ危険輪郭")
	p1.dir = Vector2.UP
	p1._update_danger_outline()
	check(not p1._dangerous_to_player, "外れる敵弾には危険輪郭を付けない")

	var Fish = preload("res://scripts2d/FishSchool2D.gd")
	var fs := Node2D.new(); fs.set_script(Fish); fs.setup("sardine",3); add_child(fs)
	await get_tree().process_frame
	var caught: Array = fs.catch_fish(2)
	check(caught.size() == 2 and fs.remaining == 1, "光る帯の漁獲は2倍")
	check(not fs.depleted(), "残数1では未枯渇")

	GameState.money = 0
	var Port = preload("res://scripts/PortUI.gd")
	var port := CanvasLayer.new(); port.set_script(Port); add_child(port)
	await get_tree().process_frame
	GameState.guide_target = {"kind":"island", "id":1}
	port.open()
	check(port._fuel_estimate.text.contains("推定消費"), "ガイド設定中は出港前燃料見積もりを表示")
	check(port._tavern_section == "bounty", "酒場の既定サブタブは賞金・換金")
	port._tavern_section = "crew"
	port.show_tavern()
	await get_tree().process_frame
	var disabled_money := 0
	for node in port.content.find_children("*","Button",true,false):
		if node.disabled:
			disabled_money += 1
	check(disabled_money > 0, "資金不足の雇用ボタンは事前に無効")
	port.show_shipyard()
	port._shipyard_weapon_slot = 0
	port.show_shipyard()
	await get_tree().process_frame
	check(port.content.find_children("*","VBoxContainer",true,false).size() > 0, "武器選択はスロット下の1列一覧")
	port.show_fleet()
	await get_tree().process_frame
	var cards := 0
	for node in port.content.get_children():
		if node is PanelContainer:
			cards += 1
	check(cards >= GameState.fleet.size(), "船団の各艦がカード表示")
	var fleet_text := ""
	for node in port.content.find_children("*", "Label", true, false):
		fleet_text += node.text
	check(not fleet_text.contains("陣形 —"), "潮鳴り到達前は編成画面に陣形を表示しない")
	GameState.visited_islands = [0, 1]
	port.show_fleet()
	await get_tree().process_frame
	fleet_text = ""
	for node in port.content.find_children("*", "Label", true, false):
		fleet_text += node.text
	check(fleet_text.contains("陣形 —"), "潮鳴り到達後は編成画面に陣形を表示")

	var World = preload("res://scripts2d/World2D.gd")
	var world := Node2D.new()
	world.set_script(World)
	world.phase = "sea"
	GameState.formation_slot = 0
	GameState.visited_islands = [0]
	world._set_formation_slot(2)
	check(GameState.formation_slot == 0, "潮鳴り到達前は陣形キーを無効化")
	GameState.visited_islands = [0, 1]
	GameState.fleet = [GameState.fleet[0]]
	world._set_formation_slot(2)
	check(GameState.formation_slot == 0, "旗艦1隻時は陣形キーを無効化")
	world.free()

	var old_bgm := Audio.bgm_volume()
	var old_sfx := Audio.sfx_volume()
	Audio.set_bgm_volume(0.37)
	Audio.set_sfx_volume(0.42)
	check(absf(Audio.bgm_volume() - 0.37) < 0.001, "BGM音量を個別設定")
	check(absf(Audio.sfx_volume() - 0.42) < 0.001, "効果音量を個別設定")
	Audio.set_bgm_volume(old_bgm)
	Audio.set_sfx_volume(old_sfx)
	var Overlay = preload("res://scripts/OverlayMenus.gd")
	var overlay_host := Control.new()
	add_child(overlay_host)
	Overlay.show_settings(overlay_host)
	check(overlay_host.find_children("*", "HSlider", true, false).size() == 2, "音量設定はBGM・効果音の2スライダー")
	overlay_host.get_node("SharedOverlay").free()
	Overlay.show_help(overlay_host)
	var help_text := ""
	# #236再: 本文は RichTextLabel(Labelの派生ではない)なので両方から集める
	for node in overlay_host.find_children("*", "Label", true, false):
		help_text += node.text
	for node in overlay_host.find_children("*", "RichTextLabel", true, false):
		help_text += node.text
	check(help_text.contains("W / S") and help_text.contains("ガトリングガン") and help_text.contains("5　陣形スキル"), "早見表に操作と武器説明を掲載")

	var names := ["lord_undine","lord_siren","lord_night_emperor","lord_night_bat_medium","lord_night_bat_small","lord_wraith","lord_kraken_lord","lord_griffon","mob_mermaid","mob_lamia","mob_zombie_fish","mob_moon_jelly","mob_killer_shell","mob_carabos"]
	# #274/#277/#239再8: 横向き1枚だけを使う敵(side_only)は正面/背面を持たない
	var side_only_arts := ["mob_moon_jelly", "mob_killer_shell", "lord_ghost", "mob_charybdis"]
	for n in names:
		for suffix in ["", "_front", "_back"]:
			var base := "res://assets/images/pixel/%s%s.png" % [n,suffix]
			if suffix != "" and side_only_arts.has(n):
				check(not ResourceLoader.exists(base), "横向き1枚のみのはず: "+base)
				continue
			check(ResourceLoader.exists(base), "画像なし: "+base)
			var sprite_image := Image.load_from_file(base)
			check(not sprite_image.is_empty() and sprite_image.get_used_rect().has_area(), "透明・空画像: "+base)
		var art_path := "res://assets/images/%s.png" % n
		check(ResourceLoader.exists(art_path), "挿絵なし: "+n)
		var art_image := Image.load_from_file(art_path)
		check(not art_image.is_empty() and art_image.get_used_rect().has_area(), "空の挿絵: "+n)
	# 元の一枚絵も残っていないこと(残っているとドット絵の一括再生成で復活する)
	for n2 in side_only_arts:
		for suffix2 in ["_front", "_back"]:
			var src2 := "res://assets/images/%s%s.png" % [n2, suffix2]
			check(not ResourceLoader.exists(src2), "一枚絵が残っている(再生成で復活する): "+src2)

	if failures.is_empty():
		print("MAINTENANCE_TEST_OK crit/weather/fishing/port/formations/audio/help/assets")
		get_tree().quit(0)
	else:
		print("MAINTENANCE_TEST_FAILED ", failures)
		get_tree().quit(1)
