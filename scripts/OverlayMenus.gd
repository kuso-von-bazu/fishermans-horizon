extends RefCounted
## タイトル・港・航海HUDで共有する設定／操作早見表モーダル。

# #241再5: 検証用。ポーズを実際に解除した回数(画面の移動では増えないこと)
static var unpause_count: int = 0

const HELP_TEXT := """【操作】
W / S　前進・後進
A / D　旋回
マウス　照準
左クリック　射撃／敵をクリックしてロックオン
右クリック　魚雷（ロックオン時のみ）
マウスホイール　ロックオン対象の切替
E　漁／寄港（漁は長押しゲージ）
R　長押しで直近の島へ帰還
1〜4　陣形変更（潮鳴りの島到達後・2隻以上）
5　陣形スキル

【武器】
ガトリングガン　弾幕向け。遠距離では威力が低下。
大砲　単発高火力。海賊船を炎上させやすい。
銛　毒を塗り、生物へ弱体効果を与える。
魚雷　ロック対象を追尾。味方をすり抜けるが空中の敵には無効。
衝角　体当たりで攻撃。空中の敵には無効。"""

# #235再/#236再: 「⚙」「?」はフォントに字形が無い環境で豆腐(文字化け)になるため、
# 生成した画像(画像生成\UIアイコン生成.py)をボタンのアイコンとして使う。
# タイトル・港・航海HUDの3か所で同じ見た目にそろえる。
static func icon_button(kind: String, tip: String, icon_px := 26) -> Button:
	var b := Button.new()
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	var path := "res://assets/images/ui_%s.png" % kind
	if ResourceLoader.exists(path):
		b.icon = load(path)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", icon_px)
	else:
		b.text = "?" if kind == "help" else "設定"   # 画像が無い時の保険
	return b

# #241再3: オーバーレイ内のボタンから別のオーバーレイへ移るとき、
# その場で切り替えると _base() の old.free() が「今まさにシグナルを処理している
# ボタン自身の祖先」を解放してしまい、入力を受け付けなくなる(操作不能)。
# 必ず次フレームまで遅らせてから切り替える。
static func _defer(parent: Control, which: String) -> void:
	if parent == null or parent.get_tree() == null:
		return
	parent.get_tree().process_frame.connect(func():
		if not is_instance_valid(parent):
			return
		match which:
			"help": show_help(parent)
			"log": show_hint_log(parent)
			"last": show_last_hint(parent)
	, CONNECT_ONE_SHOT)

static func _base(parent: Control, title: String, want_h := 500.0) -> Dictionary:
	var old := parent.get_node_or_null("SharedOverlay")
	if old:
		# #236再: queue_free だと解放(=ポーズ解除)がこの関数の後になり、
		# 新しいオーバーレイを出した直後にポーズが解けてしまう。即時解放する。
		# #241再5: ただし「別のオーバーレイへ移るための解放」ではポーズを
		# 解いてはいけない。ほんの一瞬でも解除するとBGMが鳴ってしまう
		# (音声は別スレッドで動くため、1フレーム未満でも音が出る)。
		old.set_meta("suppress_unpause", true)
		old.free()
	var overlay := Control.new()
	overlay.name = "SharedOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	# #236再: 表示中はゲームを止める。オーバーレイ自身は止まらないよう
	# ALWAYS にしておく(閉じるボタンとスライダーは動かす必要がある)。
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	# #236再3/#235再2: ポーズするのは**航海中だけ**にする。
	# タイトル・港で止めるとBGMまで途切れて違和感が出るため。
	# 音量設定はスライダーを動かしながら音量を確かめたいので、
	# 開いている間もBGMが鳴っている必要がある(設定は港とタイトルからのみ開く)。
	var want_pause: bool = GameState.at_sea
	if want_pause:
		overlay.tree_exiting.connect(func():
			# #241再5: 画面の移動中(次のオーバーレイを出すための解放)では解除しない
			if overlay.has_meta("suppress_unpause"):
				return
			if is_instance_valid(parent) and parent.get_tree():
				parent.get_tree().paused = false
				unpause_count += 1)
	parent.add_child(overlay)
	if want_pause and parent.get_tree():
		parent.get_tree().paused = true
	parent.move_child(overlay, parent.get_child_count() - 1)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	# #235再/#236再: 画面が低いとパネルが縦にはみ出して「閉じる」が見切れるため、
	# パネルはビューポートに収まる大きさに抑え、本文だけをスクロールさせる。
	var vp: Vector2 = parent.get_viewport().get_visible_rect().size
	var pw: float = clampf(vp.x - 60.0, 360.0, 900.0)
	var ph: float = clampf(vp.y - 60.0, 260.0, 720.0)
	var panel_h: float = minf(want_h, ph)
	panel.custom_minimum_size = Vector2(pw, panel_h)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.09, 0.14, 0.98)
	style.border_color = Color(0.35, 0.7, 0.82)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	# 外枠(見出し / 本文スクロール / 閉じる)。閉じるは常に見える位置へ固定する。
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	outer.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(pw - 52.0, maxf(panel_h - 160.0, 120.0))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return {"overlay": overlay, "box": box, "outer": outer}

static func _close_button(ui: Dictionary, overlay: Control) -> void:
	var close := Button.new()
	close.text = "閉じる"
	close.custom_minimum_size = Vector2(180, 46)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(overlay.queue_free)
	(ui.outer as VBoxContainer).add_child(close)   # スクロール外=常に見える

static func show_settings(parent: Control) -> void:
	# #235再: 中身が2行しかないので、パネルは低めにして間延びを防ぐ
	# #278(提案4): 画面シェイクのON/OFFを足したので少し高くする
	var ui := _base(parent, "設定", 400.0)
	var box: VBoxContainer = ui.box
	for setting in [["BGM", Audio.bgm_volume(), Audio.set_bgm_volume], ["効果音", Audio.sfx_volume(), Audio.set_sfx_volume]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var label := Label.new()
		label.text = str(setting[0])
		label.custom_minimum_size = Vector2(120, 42)
		label.add_theme_font_size_override("font_size", 22)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = float(setting[1])
		slider.custom_minimum_size = Vector2(380, 42)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)
		# #235再: つまみの位置だけでは分かりにくいので数値も出す
		var val := Label.new()
		val.text = "%d%%" % int(round(float(setting[1]) * 100.0))
		val.custom_minimum_size = Vector2(70, 42)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_font_size_override("font_size", 22)
		val.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
		row.add_child(val)
		var setter: Callable = setting[2]
		slider.value_changed.connect(func(value: float):
			setter.call(value)
			val.text = "%d%%" % int(round(value * 100.0)))
		box.add_child(row)
	# #278(提案4): 画面シェイク。既定はONで、酔う場合はここで切れる
	var shake_row := HBoxContainer.new()
	shake_row.add_theme_constant_override("separation", 18)
	var shake_label := Label.new()
	shake_label.text = "画面シェイク"
	shake_label.custom_minimum_size = Vector2(180, 42)
	shake_label.add_theme_font_size_override("font_size", 22)
	shake_row.add_child(shake_label)
	var shake_check := CheckBox.new()
	shake_check.text = "被弾・撃破で画面を揺らす"
	shake_check.button_pressed = GameState.screen_shake
	shake_check.add_theme_font_size_override("font_size", 20)
	shake_check.toggled.connect(func(on: bool): GameState.set_screen_shake(on))
	shake_row.add_child(shake_check)
	box.add_child(shake_row)

	var note := Label.new()
	note.text = "設定は自動保存され、次回起動時にも引き継がれます。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color(0.72, 0.82, 0.9))
	box.add_child(note)
	_close_button(ui, ui.overlay)

static func show_help(parent: Control) -> void:
	var ui := _base(parent, "操作・武器 早見表")
	var box: VBoxContainer = ui.box
	# #236再: Label をスクロール内に置くと行間が間延びするため、
	# PortUI と同じ RichTextLabel + fit_content で内容ぴったりの高さにする。
	var help := RichTextLabel.new()
	help.bbcode_enabled = false
	help.fit_content = true
	help.scroll_active = false
	help.text = HELP_TEXT
	help.add_theme_font_size_override("normal_font_size", 19)
	help.add_theme_color_override("default_color", Color(0.88, 0.93, 0.98))
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(help)

	# #241再3: 直近のヒントは早見表とは**別ウインドウ**にする(レビュアー指定)。
	# 早見表からはボタンで移動できるようにしておく。
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var last_btn := Button.new()
	last_btn.text = "直近のヒント"
	last_btn.custom_minimum_size = Vector2(190, 42)
	last_btn.add_theme_font_size_override("font_size", 19)
	last_btn.focus_mode = Control.FOCUS_NONE
	last_btn.pressed.connect(func(): _defer(parent, "last"))
	row.add_child(last_btn)
	var log_btn := Button.new()
	log_btn.text = "ヒントログ"
	log_btn.custom_minimum_size = Vector2(190, 42)
	log_btn.add_theme_font_size_override("font_size", 19)
	log_btn.focus_mode = Control.FOCUS_NONE
	log_btn.pressed.connect(func(): _defer(parent, "log"))
	row.add_child(log_btn)
	(ui.outer as VBoxContainer).add_child(row)
	_close_button(ui, ui.overlay)

# #241再3: 直近に表示されたヒントだけを見る専用ウインドウ
static func show_last_hint(parent: Control) -> void:
	var ui := _base(parent, "直近のヒント", 320.0)
	var box: VBoxContainer = ui.box
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = false
	rt.fit_content = true
	rt.scroll_active = false
	if GameState.hint_log.is_empty():
		rt.text = "まだヒントは表示されていません。"
	else:
		var latest: Dictionary = GameState.hint_log[0]
		rt.text = "ヒント：%s" % str(latest.get("text", ""))   # #241再4: 島名は出さない
	rt.add_theme_font_size_override("normal_font_size", 20)
	rt.add_theme_color_override("default_color", Color(0.95, 0.98, 1.0))
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(rt)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 10)
	var to_log := Button.new()
	to_log.text = "ヒントログ"
	to_log.custom_minimum_size = Vector2(190, 42)
	to_log.add_theme_font_size_override("font_size", 19)
	to_log.focus_mode = Control.FOCUS_NONE
	to_log.pressed.connect(func(): _defer(parent, "log"))
	row2.add_child(to_log)
	var to_help := Button.new()
	to_help.text = "早見表へ戻る"
	to_help.custom_minimum_size = Vector2(190, 42)
	to_help.add_theme_font_size_override("font_size", 19)
	to_help.focus_mode = Control.FOCUS_NONE
	to_help.pressed.connect(func(): _defer(parent, "help"))
	row2.add_child(to_help)
	(ui.outer as VBoxContainer).add_child(row2)
	_close_button(ui, ui.overlay)

# #241再2: これまで実際に表示されたヒントの一覧(上から新しい順)
static func show_hint_log(parent: Control) -> void:
	var ui := _base(parent, "ヒントログ")
	var box: VBoxContainer = ui.box
	if GameState.hint_log.is_empty():
		var none := Label.new()
		none.text = "まだヒントは表示されていません。"
		none.add_theme_font_size_override("font_size", 19)
		none.add_theme_color_override("font_color", Color(0.8, 0.86, 0.92))
		box.add_child(none)
	else:
		var lines: Array = []
		for e in GameState.hint_log:
			lines.append("・%s" % str(e.get("text", "")))   # #241再4: 島名は出さない
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = false
		rt.fit_content = true
		rt.scroll_active = false
		rt.text = "\n".join(lines)
		rt.add_theme_font_size_override("normal_font_size", 18)
		rt.add_theme_color_override("default_color", Color(0.9, 0.95, 1.0))
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(rt)
	# 早見表へ戻れるようにする
	var back := Button.new()
	back.text = "早見表へ戻る"
	back.custom_minimum_size = Vector2(200, 42)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 19)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): _defer(parent, "help"))
	(ui.outer as VBoxContainer).add_child(back)
	_close_button(ui, ui.overlay)