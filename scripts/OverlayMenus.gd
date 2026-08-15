extends RefCounted
## タイトル・港・航海HUDで共有する設定／操作早見表モーダル。

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

static func _base(parent: Control, title: String) -> Dictionary:
	var old := parent.get_node_or_null("SharedOverlay")
	if old:
		old.queue_free()
	var overlay := Control.new()
	overlay.name = "SharedOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	parent.add_child(overlay)
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
	panel.custom_minimum_size = Vector2(780, 500)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.09, 0.14, 0.98)
	style.border_color = Color(0.35, 0.7, 0.82)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	box.add_child(heading)
	return {"overlay": overlay, "box": box}

static func _close_button(box: VBoxContainer, overlay: Control) -> void:
	var close := Button.new()
	close.text = "閉じる"
	close.custom_minimum_size = Vector2(180, 46)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(overlay.queue_free)
	box.add_child(close)

static func show_settings(parent: Control) -> void:
	var ui := _base(parent, "音量設定")
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
		slider.custom_minimum_size = Vector2(430, 42)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var setter: Callable = setting[2]
		slider.value_changed.connect(func(value: float): setter.call(value))
		row.add_child(slider)
		box.add_child(row)
	var note := Label.new()
	note.text = "設定は自動保存され、次回起動時にも引き継がれます。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color(0.72, 0.82, 0.9))
	box.add_child(note)
	_close_button(box, ui.overlay)

static func show_help(parent: Control) -> void:
	var ui := _base(parent, "操作・武器 早見表")
	var box: VBoxContainer = ui.box
	var help := Label.new()
	help.text = HELP_TEXT
	help.add_theme_font_size_override("font_size", 19)
	help.add_theme_color_override("font_color", Color(0.88, 0.93, 0.98))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(help)
	_close_button(box, ui.overlay)