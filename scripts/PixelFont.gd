extends RefCounted
## PixelFont — #278(提案3): ゲーム内の「数値・見出し・敵名」に使う日本語ピクセルフォント。
##
## PixelMplus12(M+ BITMAP FONTS License / 商用利用・再配布可)を assets/fonts に同梱。
## 説明文・ヒントなどの長文は可読性を優先して従来どおり NotoSansJP のままにする。
##
## ドット絵として綺麗に出すため、アンチエイリアス・サブピクセル配置・ヒンティングを
## すべて切り、字面が 12px の整数倍になるサイズへ丸めて使う。

const PATH := "res://assets/fonts/PixelMplus12-Regular.ttf"
const BASE := 12   # PixelMplus12 の素の字面

static var _font: FontFile = null

static func font() -> FontFile:
	if _font == null and ResourceLoader.exists(PATH):
		var f: FontFile = load(PATH)
		if f != null:
			f = f.duplicate()   # 読み込み設定を書き換えるのでコピーを持つ
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			f.hinting = TextServer.HINTING_NONE
			f.force_autohinter = false
			f.multichannel_signed_distance_field = false
			_font = f
	return _font

# 指定サイズに最も近い 12px の整数倍(最低12px)。半端な大きさだとドットがにじむ
static func snap(size: int) -> int:
	return maxi(BASE, int(round(float(size) / float(BASE))) * BASE)

# ラベル等にピクセルフォントを当てる。フォントが無い環境では何もしない(従来表示)
static func apply(node: Control, size: int = 0) -> void:
	var f := font()
	if f == null or node == null:
		return
	node.add_theme_font_override("font", f)
	var want := size
	if want <= 0:
		want = int(node.get_theme_font_size("font"))
	node.add_theme_font_size_override("font_size", snap(want))
