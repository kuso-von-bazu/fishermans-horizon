extends Node
## Database — ゲーム内の静的データ(船・武器・魚・モンスター・島)を保持するシングルトン。
## 企画書 "Fisherman's Horizon" に基づく。数値はMVP用のバランス初期値。

# ---------------------------------------------------------------------------
# 魚モブ(戦闘なしで漁獲可能) cap=魚倉キャパ消費, price=基準買取額, dist=主分布の島index
# ---------------------------------------------------------------------------
var fish := {
	"sardine":  {"name": "イワシ",   "cap": 1, "price": 20,  "home": 0, "color": Color(0.7,0.8,0.9)},
	"mackerel": {"name": "サバ",     "cap": 1, "price": 45,  "home": 0, "color": Color(0.4,0.6,0.8)},
	"bonito":   {"name": "カツオ",   "cap": 2, "price": 150, "home": 1, "color": Color(0.3,0.5,0.7)},
	"squid":    {"name": "イカ",     "cap": 2, "price": 130, "home": 1, "color": Color(0.9,0.8,0.85)},
	"octopus":  {"name": "タコ",     "cap": 2, "price": 160, "home": 2, "color": Color(0.8,0.4,0.45)},
	"grouper":  {"name": "クエ",     "cap": 1, "price": 300, "home": -1,"color": Color(0.55,0.4,0.3), "rare": true},
}

# ---------------------------------------------------------------------------
# 戦闘モブ(倒せば漁獲可能) hp/dmg/cap/price + flags
# ---------------------------------------------------------------------------
var combat_mobs := {
	# #96再: 販売額は従前(初期値)の約2割引き。#26再: face_left=元画像が左向き→反転条件を逆に
	"narwhal":       {"name": "ユニコーン",     "hp": 110, "dmg": 6,  "cap": 3, "price": 120, "ranged": false, "aerial": false, "speed": 8.0,  "face_left": true, "color": Color(0.85,0.85,0.9)},
	"seahunter":     {"name": "シーハンター",   "hp": 250, "dmg": 12,  "cap": 4, "price": 256, "ranged": false, "aerial": false, "speed": 9.0,  "face_left": true, "color": Color(0.2,0.2,0.25)},
	"ornithocheirus":{"name": "オルニケイトス", "hp": 160, "dmg": 11, "cap": 3, "price": 224, "ranged": false, "aerial": true,  "speed": 21.0, "dodge": 0.10, "dodge_pass": true, "face_left": true, "color": Color(0.7,0.6,0.4)},
	"wyrm":          {"name": "ワイアーム",     "hp": 400, "dmg": 18, "cap": 4, "price": 400, "ranged": true,  "aerial": false, "speed": 7.0,  "atk_cd": 0.8, "face_left": true, "color": Color(0.6,0.2,0.2)},
	# #69: 潮鳴り以降の強モブ。reach=触腕の射程倍率, entangle=被弾で討伐まで鈍足
	"kraken":        {"name": "クラーケン",     "hp": 700, "dmg": 24, "cap": 6, "price": 720,  "ranged": false, "aerial": false, "speed": 8.5,  "reach": 2.2, "entangle": true, "color": Color(0.5,0.2,0.45)},
	"wyvern":        {"name": "ワイバーン",     "hp": 800, "dmg": 26, "cap": 6, "price": 800, "ranged": true,  "aerial": false, "speed": 9.5,  "atk_cd": 1.1, "face_left": true, "color": Color(0.7,0.15,0.15)},
	# #190: 月下の島の強モブ。starfish=回転しながら星形弾を多数ばら撒く, zaratan=離れた距離から波の範囲近接
	"starfish":      {"name": "オニヒトデ",     "hp": 620, "dmg": 20, "cap": 5, "price": 640, "ranged": true,  "aerial": false, "speed": 6.0,  "atk_cd": 1.7, "range_mult": 1.7, "spin": 2.2, "scatter": 12, "star_shot": true, "way": 0, "shot_dmg_mult": 0.42, "shot_speed_mult": 0.75, "death_shot": {"count": 26, "mode": "radial", "shape": "star", "speeds": [1.0], "dmg_mult": 0.35}, "color": Color(0.75,0.3,0.35)},
	"zaratan":       {"name": "ザラタン",       "hp": 900, "dmg": 28, "cap": 6, "price": 720, "ranged": false, "aerial": false, "speed": 11.0, "atk_cd": 1.9, "reach": 3.0, "wave_melee": true, "face_left": true, "death_shot": {"count": 1, "mode": "aim", "dmg_mult": 0.7}, "color": Color(0.55,0.35,0.25)},
	# #71: 嵐越え以降。merman=群れ+俊敏+好戦的, charybdis=渦潮+確率回避。#98再: マーマンHP350
	"merman":        {"name": "マーマン",       "hp": 350, "dmg": 16, "cap": 2, "price": 304,  "ranged": false, "aerial": false, "speed": 13.0, "size_mult": 0.8, "group": 3, "aggro": 1400.0, "face_left": true, "color": Color(0.25,0.55,0.4)},
	# #71再: カリュブディスの能力を全体的に強化
	"charybdis":     {"name": "カリュブディス", "hp": 1050, "dmg": 31, "cap": 8, "price": 960, "ranged": true,  "aerial": false, "speed": 11.0,  "dodge": 0.20, "entangle": true, "aim_color": Color(0.12,0.18,0.48), "death_shot": {"count": 18, "mode": "shotgun", "spread": 0.5, "speeds": [0.55, 0.95, 1.45], "dmg_mult": 0.22, "shape": "grain", "color": Color(0.12,0.18,0.48)}, "color": Color(0.15,0.3,0.45)},
	# #71: 嵐越え以降。amphiptere=空中(魚雷ロック不可)+近接のみ+高速で追尾(竜×蛇の有翼)
	"amphiptere":    {"name": "アンフィプテレ", "hp": 780, "dmg": 32, "cap": 6, "price": 760, "ranged": false, "aerial": true, "speed": 19.0, "aggro": 1300.0, "dodge": 0.10, "dodge_pass": true, "face_left": true, "color": Color(0.45,0.2,0.5)},
	# #72再: 果ての島。tiamat=空中(魚雷ロック不可)+俊敏+高火力+炎上弾+低回避, dagon=触腕+絡め+毒+高速。強化
	# #167: ティアマットの遠隔弾はヒュドラの炎弾と同じ見た目(fire_look。挙動はburn_chance据え置き)
	"tiamat":        {"name": "ティアマット",   "hp": 1350, "dmg": 33, "cap": 10, "price": 1440, "ranged": true, "aerial": true, "speed": 14.5, "atk_cd": 0.7, "range_mult": 1.3, "dodge": 0.20, "dodge_pass": true, "burn_chance": 0.6, "fire_look": true, "zigzag": true, "zigzag_amp": 7.5, "way_choices": [1,1,1,2,3], "face_left": true, "color": Color(0.15,0.12,0.2)},
	"dagon":         {"name": "ダゴン",         "hp": 1250, "dmg": 34, "cap": 9,  "price": 1280, "ranged": true, "aerial": false, "speed": 12.5, "reach": 2.5, "range_mult": 0.55, "atk_cd": 1.5, "shoot_moving": true, "shot_poison": true, "aim_shape": "ellipse", "aim_color": Color(0.62,0.28,0.82), "entangle": true, "poison": true, "size_mult": 0.85, "color": Color(0.3,0.5,0.35)},
	# #72再: ザッハーク。銀色の神々しい竜。空中(魚雷ロック不可)+俊敏+高火力、密度の高い3way弾(aim_tight)、攻撃回避率15%(回避時は弾が後方へ抜ける)。#72再々: ギザギザ移動廃止+より積極的に遠隔(atk_cd短縮/range_mult延長)
	# #239: 星霜の島(tier2)。mermaid=引き撃ち+米粒弾ばら撒き, lamia=針状の1〜4way
	"mermaid":       {"name": "マーメイド",     "hp": 560, "dmg": 18, "cap": 4, "price": 600, "ranged": true,  "aerial": false, "speed": 12.0, "atk_cd": 1.1, "kite": true, "size_mult": 0.7, "scatter_aim": true, "scatter": 9, "scatter_speeds": [0.55, 0.95], "small_shot": true, "way": 0, "shot_dmg_mult": 0.30, "shot_speed_mult": 0.8, "face_left": true, "color": Color(0.35,0.7,0.75)},
	"lamia":         {"name": "ラミア",         "hp": 620, "dmg": 21, "cap": 4, "price": 620, "ranged": true,  "aerial": false, "speed": 11.5, "atk_cd": 1.25, "size_mult": 0.72, "way_choices": [1,2,3,4], "aim_tight": true, "needle_shot": true, "shot_dmg_mult": 0.55, "face_left": true, "color": Color(0.55,0.35,0.65)},
	# #239: 常闇の島(tier2)。zombie_fish=群れで高速体当たり, moon_jelly=長リーチ近接+毒+鈍化
	"zombie_fish":   {"name": "ゾンビウオ",     "hp": 300, "dmg": 17, "cap": 2, "price": 300, "ranged": false, "aerial": false, "speed": 16.5, "size_mult": 0.65, "group": 3, "aggro": 1500.0, "face_left": true, "color": Color(0.5,0.55,0.5)},
	"moon_jelly":    {"name": "ムーンジェリー", "hp": 820, "dmg": 24, "cap": 5, "price": 660, "ranged": false, "aerial": false, "speed": 8.0,  "reach": 2.6, "entangle": true, "poison": true, "color": Color(0.7,0.75,0.95)},
	# #239: 海嘯の島(tier3)。killer_shell=不動+打ち返し弾+挟んで鈍化, carabos=移動遠隔+長リーチ近接
	"killer_shell":  {"name": "キラーシェル",   "hp": 1600, "dmg": 30, "cap": 7, "price": 1000, "ranged": true, "aerial": false, "speed": 0.0, "atk_cd": 1.35, "stationary": true, "range_mult": 1.6, "way": 2, "aim_tight": true, "shot_dmg_mult": 0.5, "reach": 1.6, "entangle": true, "color": Color(0.6,0.5,0.35)},
	"carabos":       {"name": "カーラボス",     "hp": 1150, "dmg": 27, "cap": 6, "price": 900, "ranged": true,  "aerial": false, "speed": 11.0, "atk_cd": 1.2, "reach": 2.2, "shoot_moving": true, "way_choices": [1,2], "face_left": true, "color": Color(0.75,0.35,0.3)},
	"zahhak":        {"name": "ザッハーク",     "hp": 1480, "dmg": 30, "cap": 10, "price": 1560, "ranged": true, "aerial": true, "speed": 15.5, "atk_cd": 0.95, "range_mult": 1.3, "dodge": 0.15, "dodge_pass": true, "way": 3, "aim_tight": true, "shot_speed_mult": 0.8, "fire_look": true, "flame_color": Color(0.95,0.97,1.0), "burst": {"count": 14, "spread": 1.10, "speeds": [0.95, 1.45], "dmg_mult": 0.22, "color": Color(0.95,0.97,1.0), "every": [4.5, 7.5]}, "face_left": true, "color": Color(0.82,0.85,0.92)},
}

# 島tierごとの戦闘モブ出現重み(#38/#69/#71/#72/#75)。
# #75: 潮鳴り以降はユニコーン/シーハンター/オルニケイトスを外し強モブのみ。
var mob_weights := [
	{"narwhal": 0.55, "seahunter": 0.25, "ornithocheirus": 0.15, "wyrm": 0.05},
	{"wyrm": 0.45, "kraken": 0.35, "wyvern": 0.20},
	{"kraken": 0.22, "wyvern": 0.18, "starfish": 0.32, "zaratan": 0.28},                                  # #190: 月下の島。オニヒトデ/ザラタンが主役
	{"kraken": 0.18, "wyvern": 0.16, "merman": 0.18, "charybdis": 0.16, "amphiptere": 0.16, "starfish": 0.08, "zaratan": 0.08},   # #75/#71: 嵐越え以降はワイアーム非出現+アンフィプテレ
	{"merman": 0.15, "charybdis": 0.15, "tiamat": 0.2, "dagon": 0.2, "amphiptere": 0.12, "zahhak": 0.18}, # #75再/#71: 果てはクラーケン/ワイバーンも非出現。#72再: ザッハーク追加
	# #239: 追加した島(index 5=星霜 / 6=常闇 / 7=海嘯)。**islands と同じ並び順で持つこと**
	{"mermaid": 0.34, "lamia": 0.30, "kraken": 0.20, "wyvern": 0.16},                                     # 星霜(tier2)
	{"zombie_fish": 0.36, "moon_jelly": 0.30, "kraken": 0.18, "wyvern": 0.16},                            # 常闇(tier2)
	{"killer_shell": 0.24, "carabos": 0.26, "merman": 0.16, "charybdis": 0.14, "amphiptere": 0.12, "kraken": 0.08},  # 海嘯(tier3)
]

func pick_mob(tier: int) -> String:
	var w: Dictionary = mob_weights[clampi(tier, 0, mob_weights.size() - 1)]
	var r := randf()
	var acc := 0.0
	for id in w:
		acc += w[id]
		if r <= acc:
			return id
	return "narwhal"

# 銛のデバフ効果(#37)。造船所で選択して主にのみ付与。
# #91: 各デバフ効果を全体的に弱体化
var harpoon_debuffs := {
	"slip":  {"name": "毒(スリップ)",   "desc": "継続ダメージ(弱)"},
	"atkfreq": {"name": "麻痺(攻撃頻度減)", "desc": "攻撃間隔1.35倍"},
	"atk":   {"name": "衰弱(攻撃力減)", "desc": "与ダメージ22%減"},
	"speed": {"name": "鈍化(移動速度減)", "desc": "移動28%減"},
}

# ---------------------------------------------------------------------------
# 近海の主(ボス) 主は対応する島でしか売れない。bounty=賞金, cap=魚倉圧迫
# ---------------------------------------------------------------------------
# #208: 主の売値(price)と賞金(bounty)を引き上げ
# #65: 全主が遠隔攻撃を持つ。way=同時弾数(扇状), homing=追跡弾, radial=全方向, homing_count=追跡弾数
var lords := {
	"sawshark":  {"name": "電動ノコギリザメ",         "hp": 730,  "dmg": 21, "cap": 8,  "price": 800,  "bounty": 1500,  "fame": 8,  "island": 0, "ranged": true, "aerial": false, "pair": false, "speed": 9.5, "way": 1, "shot_speed_mult": 0.6, "dir": 0, "face_left": true, "lore": "旧人類の狂気が生んだ悲しきモンスター。"},   # #189: 3way→1way
	"dumbo":     {"name": "ウミダンボ",               "hp": 1000, "dmg": 18, "cap": 9,  "price": 1200, "bounty": 2500,  "fame": 10, "island": 0, "ranged": true, "aerial": false, "pair": false, "speed": 7.5, "way": 1, "shot_speed_mult": 0.6, "dir": 135, "lore": "大きな耳で器用に泳ぐ。旧大陸が極度の海面上昇で沈没していく中、海に適応した象。"},   # #189: 3way→1way
	"whale":     {"name": "ヒゲマッコウナガスクジラ", "hp": 1330, "dmg": 27, "cap": 14, "price": 2700, "bounty": 4500,  "fame": 16, "island": 1, "ranged": true, "aerial": false, "pair": false, "speed": 8.5, "way": 3, "homing": true, "projectile_speed_mult": 0.8, "burst": {"count": 16, "spread": 0.42, "speeds": [0.55, 0.9], "dmg_mult": 0.22, "color": Color(0.55,0.85,0.95), "every": [5.0, 8.5]}, "dir": 45, "face_left": true, "lore": "富栄養化の影響で体長は50メートルにも達する。"},
	"walrus":    {"name": "ギガントセイウチ",         "hp": 870,  "dmg": 24, "cap": 7,  "price": 1800, "bounty": 6000,  "fame": 18, "island": 1, "ranged": true, "aerial": false, "pair": true, "speed": 8.5,  "way": 3, "spawn_dist_mult": 1.35, "projectile_speed_mult": 0.8, "burst": {"count": 15, "spread": 0.45, "speeds": [0.55, 0.95, 1.45], "dmg_mult": 0.22, "color": Color(0.62,0.45,0.28), "every": [5.0, 8.5]}, "dir": 225, "lore": "おしどり夫婦でいつも夫婦で行動している。"},
	# #190: 月下の島の主。aspidochelone=高速回転しつつ弾をばら撒きながら体当たり(charge_cycleで緩急)
	"aspidochelone": {"name": "アスピドケロン",       "hp": 3650, "dmg": 38, "cap": 12, "price": 5000, "bounty": 13000,  "fame": 22, "island": 2, "ranged": true,  "aerial": false, "pair": false, "speed": 13.5, "atk_cd": 0.6, "spin": 5.0, "scatter": 14, "way": 0, "shot_dmg_mult": 0.5, "shot_speed_mult": 0.8, "charge_cycle": true, "melee_mult": 1.4, "dir": 180, "color": Color(0.35,0.5,0.4), "lore": "島と間違えて上陸した船乗りが、目を覚ましたアスピドケロンに丸呑みされたという伝説がある。"},
	# #190: legion=小魚の群れが大魚の陣形。被弾で陣形が縮み(shrink_hp)、複数箇所(multi_origin)から小型弾を大量発射
	"legion":    {"name": "レギオン",                 "hp": 5500, "dmg": 30, "cap": 13, "price": 7000, "bounty": 20000,  "fame": 24, "island": 2, "ranged": true,  "aerial": false, "pair": false, "speed": 10.5, "atk_cd": 0.9, "multi_origin": 5, "way": 3, "aim_tight": true, "scatter": 10, "scatter_speeds": [0.55, 0.95, 1.5], "small_shot": true, "shot_dmg_mult": 0.32, "shot_speed_mult": 0.85, "shrink_hp": 0.45, "size_mult": 1.3, "face_left": true, "dir": 315, "color": Color(0.5,0.65,0.75), "lore": "縄張り争いに勝利するため、群知能を身に着けた小魚の群れ。"},
	# #239: 星霜の島(island 5)。ウンディーネ=好戦的でない引き撃ち+密度が変わる米粒弾、セイレーン=蛇行する音符弾
	"undine":    {"name": "ウンディーネ",             "hp": 3400, "dmg": 34, "cap": 12, "price": 4800, "bounty": 12000, "fame": 22, "island": 5, "ranged": true, "aerial": false, "pair": false, "speed": 11.5, "atk_cd": 0.85, "kite": true, "no_melee": true, "scatter_aim": true, "scatter": 12, "scatter_var": true, "scatter_speeds": [0.5, 0.9, 1.4], "small_shot": true, "way": 0, "shot_dmg_mult": 0.42, "shot_speed_mult": 0.8, "aim_color": Color(0.62,0.86,0.98), "dir": 0, "lore": "近海の守り神とされてきたが、現人類との不幸な行き違いから賞金首となった。あまり好戦的ではない。"},
	"siren":     {"name": "セイレーン",               "hp": 3200, "dmg": 33, "cap": 11, "price": 4600, "bounty": 11500, "fame": 22, "island": 5, "ranged": true, "aerial": false, "pair": false, "speed": 12.5, "atk_cd": 1.0, "no_melee": true, "size_mult": 0.8, "way_choices": [3,4], "note_shot": true, "zigzag": true, "zigzag_amp": 9.0, "shot_dmg_mult": 0.6, "shot_speed_mult": 0.85, "aim_color": Color(0.95,0.8,0.95), "dir": 315, "lore": "美しい歌で船乗りを惑わす。"},
	# #239: 常闇の島(island 6)。夜の帝王=被ダメで分裂(中→小)、レイス=撃つ→消える→別の場所へ
	"night_emperor": {"name": "夜の帝王",             "hp": 3900, "dmg": 36, "cap": 13, "price": 5200, "bounty": 13500, "fame": 24, "island": 6, "ranged": true, "aerial": false, "pair": false, "speed": 10.0, "atk_cd": 0.9, "scatter_aim": true, "scatter": 11, "scatter_speeds": [0.55, 1.45], "small_shot": true, "way": 0, "shot_dmg_mult": 0.45, "aim_color": Color(0.72,0.6,0.95), "split": {"into": "night_bat_medium", "count": 2, "at_hp": 0.5}, "dir": 180, "lore": "コウモリの群れが集まるにつれ、この姿となっていったという目撃情報がある。"},
	"night_bat_medium": {"name": "夜の帝王(中)",      "hp": 1100, "dmg": 24, "cap": 4,  "price": 1200, "bounty": 0, "fame": 0, "island": 6, "ranged": true, "aerial": true, "pair": false, "speed": 14.0, "atk_cd": 1.1, "scatter_aim": true, "scatter": 7, "small_shot": true, "way": 0, "shot_dmg_mult": 0.4, "size_mult": 0.6, "aim_color": Color(0.72,0.6,0.95), "split": {"into": "night_bat_small", "count": 2, "at_hp": 0.5}, "is_split": true, "no_cargo": true, "lore": "夜の帝王が分裂した中型のコウモリ。"},
	"night_bat_small":  {"name": "夜の帝王(小)",      "hp": 420,  "dmg": 16, "cap": 2,  "price": 500,  "bounty": 0, "fame": 0, "island": 6, "ranged": false, "aerial": true, "pair": false, "speed": 18.0, "size_mult": 0.4, "is_split": true, "no_cargo": true, "lore": "夜の帝王が分裂した小型のコウモリ。すべて倒さないと討伐にならない。"},
	"wraith":    {"name": "レイス",                   "hp": 3600, "dmg": 35, "cap": 0,  "price": 0,    "bounty": 13000, "fame": 24, "island": 6, "ranged": true, "aerial": false, "pair": false, "speed": 9.0, "atk_cd": 1.3, "no_melee": true, "size_mult": 0.78, "way_choices": [1,2,3,4], "aim_tight": true, "shot_dmg_mult": 0.62, "blink": {"every": [2.6, 4.0], "dist": [420.0, 900.0]}, "no_cargo": true, "aim_color": Color(0.55,0.9,0.85), "dir": 225, "lore": "顔はうかがい知れないが、ボロ布から覗く目だけは怪しく光っている。"},
	# #239: 海嘯の島(island 7)。オクトパス=最寄り船狙いの多段近接、グリフォン=空中のヒットアンドアウェイ
	"kraken_lord": {"name": "オクトパス",             "hp": 6200, "dmg": 40, "cap": 14, "price": 9000, "bounty": 26000, "fame": 30, "island": 7, "ranged": true, "aerial": false, "pair": false, "speed": 10.5, "atk_cd": 1.15, "reach": 3.4, "multi_melee": [2, 3], "target_nearest": true, "entangle": true, "shoot_moving": true, "way_choices": [1,2,3], "shot_dmg_mult": 0.55, "dir": 90, "color": Color(0.55,0.55,0.58), "lore": "灰色の体と黒色の目を持つ不気味な姿をしたタコ。"},
	"griffon":   {"name": "グリフォン",               "hp": 5800, "dmg": 42, "cap": 13, "price": 8600, "bounty": 25000, "fame": 30, "island": 7, "ranged": true, "aerial": true,  "pair": false, "speed": 14.5, "atk_cd": 1.0, "kite": true, "way": 5, "aim_tight": true, "homing_count": 1, "shot_dmg_mult": 0.6, "burst": {"count": 20, "mode": "radial", "speeds": [1.0], "dmg_mult": 0.28, "color": Color(0.95,0.9,0.6), "every": [5.0, 8.0]}, "aim_color": Color(0.95,0.9,0.6), "dir": 270, "lore": "馬の胴体にワシの頭と翼を持つ魔獣。"},
	# #110/#111: ヒュドラ/ケツァル/レヴィアタンを強化。#65: 弾幕(way/homing_count/radial_count)と確定炎上(burn_fire)
	"hydra":     {"name": "ヒュドラ",                 "hp": 6800, "dmg": 46, "cap": 12, "price": 11000, "bounty": 30000,  "fame": 25, "island": 3, "ranged": true,  "aerial": false, "pair": false, "speed": 8.5, "way": 7, "fire": true, "burn_fire": true, "homing_count": 2, "burst": {"count": 20, "spread": 1.15, "speeds": [0.55, 0.95, 1.45], "dmg_mult": 0.22, "color": Color(0.88,0.25,0.18), "every": [5.5, 9.0]}, "dir": 90, "lore": "旧人類が神を作り出す過程で生まれた失敗作。"},
	# #111再: HP4500。#65再: 5wayを狭い扇(aim_tight)+黄色い楕円弾、追跡弾は扇状に広がってから急加速(spread_homing)
	"quetzal":   {"name": "ケツァルコアトル",         "hp": 7500, "dmg": 50, "cap": 13, "price": 13000, "bounty": 36000,  "fame": 30, "island": 3, "ranged": true, "aerial": true,  "pair": false, "speed": 13.0, "way": 5, "aim_tight": true, "aim_shape": "ellipse", "aim_color": Color(0.95,0.85,0.2), "homing_count": 2, "spread_homing": true, "dodge": 0.10, "dodge_pass": true, "kite": true, "burst": {"count": 16, "spread": 0.42, "speeds": [0.55, 0.9], "dmg_mult": 0.22, "color": Color(0.95,0.85,0.2), "every": [4.5, 7.5], "kite_only": true}, "always_front": true, "dir": 270, "lore": "空中から攻撃してくるので、衝角による攻撃や魚雷でのロックオンは不可能。旧人類がレヴィアタンへの対抗策として創造したが、彼らはそれぞれ空と海を荒らしまわるばかりであった。"},
	# #187: 果ての島の主(レヴィアタンの前に戦う想定)。挙動は海賊王準拠=ガトリング/大砲/魚雷から2つを同時使用。
	# HPが2/3以下で引き撃ち(kite_hp)。銛のデバフ無効(no_debuff)。取り巻きなし。
	"ghost":     {"name": "幽霊船",                   "hp": 10000, "dmg": 43, "cap": 20, "price": 7000, "bounty": 68000, "fame": 45, "island": 4, "ranged": true,  "aerial": false, "pair": false, "speed": 13.0, "atk_cd": 0.9, "volley_pool": ["gatling", "cannon", "torpedo"], "volley_pick": 2, "kite": true, "kite_hp": 0.667, "no_debuff": true, "no_escort": true, "dodge": 0.15, "dodge_pass": true, "size_mult": 0.72, "no_cargo": true, "dir": 239, "spawn_dist_mult": 1.6, "face_left": true, "color": Color(0.55,0.75,0.8), "lore": "レヴィアタンに轟沈させられた過去の勇士の魂が、いつしか幽霊船の形をとり辺りを彷徨うようになった。"},
	# #155: 出現方角を果ての島の東(dir=90)。#65: 追跡弾速0.5。#110再: 速度10.5。#163: range_mult=1.6でより遠距離から。#65再: 照準3wayを緑の楕円弾に、追跡弾は扇状に広がってから急加速(spread_homing)。#112再: 説明文(バイオテクノロジー→テクノロジー)
	"leviathan": {"name": "レヴィアタン",             "hp": 13400, "dmg": 47, "cap": 25, "price": 9999, "bounty": 100000, "fame": 60, "island": 4, "ranged": true,  "aerial": false, "pair": false, "speed": 10.5, "range_mult": 1.6, "spawn_dist_mult": 1.75, "radial": true, "radial_count": 24, "way": 3, "aim_tight": true, "aim_shape": "ellipse", "aim_color": Color(0.35,0.95,0.4), "shot_speed_mult": 0.8, "homing_speed_mult": 0.5, "shot_dmg_mult": 0.7, "homing_count": 4, "spread_homing": true, "dir": 90, "face_left": true, "lore": "旧人類が創り出した神。神の領域に達した旧人類のテクノロジーは神をも創造したが、皮肉にもそれは人類種の天敵となり、残されたわずかな陸地を除いて人類の生存可能領域はなくなった。"},
}

# 方位(度・北=0=-Z, 時計回り)を八方位の日本語に
func compass(deg: float) -> String:
	var names := ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
	var i := int(round(fmod(deg, 360.0) / 45.0)) % 8
	return names[i]

# 方位角(度)→ 単位方向ベクトル(北=-Z)
func dir_vec(deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(sin(a), 0, -cos(a))

# ---------------------------------------------------------------------------
# 海賊(首だけ持ち帰る=魚倉を圧迫しない) bounty で換金
# ---------------------------------------------------------------------------
var pirates := {
	# #20再: 海賊討伐の賞金を減額前(小200/中500/大1200)へ戻す
	# #66: wpn=遠隔攻撃の種類(gatling=連射弾/cannon=砲弾/torpedo=追尾魚雷/all=全部+衝角)
	# #66: 中はガトリング3連+大砲、大はガトリング3連+追尾魚雷を同時に撃つ(volley)
	# #179再: 大/海賊王は元画像が左向き→face_leftで反転。小/中は元から正しい向きなので付けない
	"raider":   {"name": "海賊(小)", "hp": 220, "dmg": 11,  "bounty": 200,  "fame": 1, "ranged": true, "wpn": "gatling", "color": Color(0.4,0.3,0.2)},
	"corsair":  {"name": "海賊(中)", "hp": 450, "dmg": 16, "bounty": 500, "fame": 2, "ranged": true, "volley": ["gatling", "cannon"],  "color": Color(0.35,0.25,0.15)},
	"dread":    {"name": "海賊(大)", "hp": 900, "dmg": 24, "bounty": 1200, "fame": 4, "ranged": true, "volley": ["gatling", "torpedo"], "face_left": true, "color": Color(0.25,0.18,0.1)},
	# #73: レアスポーンの強敵。かつてFisherman's Horizonを目指し、心折れて海賊に落ちた男。
	# hp/dmgは出現海域(island)に応じてEnemy2Dで強化。
	"king":     {"name": "海賊王",   "hp": 2200, "dmg": 28, "bounty": 4000, "fame": 30, "ranged": true, "wpn": "all", "volley_pool": ["cannon", "gatling", "torpedo"], "volley_pick": 2, "speed": 12.0, "atk_cd": 0.6, "shoot_moving": true, "always_aggro": true, "face_left": true, "color": Color(0.1,0.08,0.1)},
}

# #177: 討伐記録(図鑑)。戦闘能力があるモブ及び海賊のみ(近海の主は酒場で別掲)。
# 並び順・図鑑用の説明文を定義。def/画像/討伐数は kind+id で引く。
var bestiary := [
	{"kind": "mob", "id": "narwhal",        "desc": "もはや人類を恐れることはなくなったイッカク。"},
	{"kind": "mob", "id": "seahunter",      "desc": "もはや人類を恐れることはなくなったシャチ。"},
	{"kind": "mob", "id": "ornithocheirus", "desc": "ケツァルコアトルの幼体のようだが繁殖方法は不明。"},
	{"kind": "mob", "id": "wyrm",           "desc": "ヒュドラの幼体のようだが繁殖方法は不明。"},
	{"kind": "mob", "id": "wyvern",         "desc": "ワイアームが少し成長した姿。"},
	{"kind": "mob", "id": "kraken",         "desc": "海面に進出してきたダイオウイカ。"},
	# #190: 月下の島の強モブ
	{"kind": "mob", "id": "starfish",       "desc": "繁殖時には大量のクローンを生み出すが、その繁殖行為が近くを通る船の脅威になる。"},
	{"kind": "mob", "id": "zaratan",        "desc": "特に味噌が美味。"},
	{"kind": "mob", "id": "merman",         "desc": "人類が海に適応しようとしてバイオテクノロジーに頼った成れの果ての姿。"},
	{"kind": "mob", "id": "charybdis",      "desc": "本体は海中に身を潜め、海面からは巨大な渦潮しか見えないが、本体は蛇のような姿をしている。"},
	{"kind": "mob", "id": "amphiptere",     "desc": "翼はあるが足がなく、上半身は竜、下半身は蛇のような見た目をしている。"},
	{"kind": "mob", "id": "dagon",          "desc": "旧人類の異端派が何らかの方法で創造した神だと考えられている。"},
	{"kind": "mob", "id": "zahhak",         "desc": "見た目は銀色の神々しいドラゴンだが、実態は人類を見境なく襲う獣。"},
	{"kind": "mob", "id": "tiamat",         "desc": "他の竜族は旧人類が創造しその後暴走したものだが、ティアマットは由来が不明。"},
	# #239: 星霜/常闇/海嘯の島の新モブ(説明文はレビュアー指定)
	{"kind": "mob", "id": "mermaid",        "desc": "下半身のみを食し、上半身を食べることは禁忌とされている。特に不老不死の効能があるわけではない。"},
	{"kind": "mob", "id": "lamia",          "desc": "下半身のみを食し、上半身を食べることは禁忌とされている。"},
	{"kind": "mob", "id": "zombie_fish",    "desc": "腐敗し、骨が見えているにもかかわらずいまだ動き回る魚。"},
	{"kind": "mob", "id": "moon_jelly",     "desc": "毒針を取り除けば独特な触感が特徴の食材となる。"},
	{"kind": "mob", "id": "killer_shell",   "desc": "危険な貝だが、巨大な真珠を狙う船乗りが後を絶たない。"},
	{"kind": "mob", "id": "carabos",        "desc": "巨大で長い触角をもつエビ。"},
	{"kind": "pirate", "id": "raider",      "desc": "近海を荒らす小物の海賊。"},
	{"kind": "pirate", "id": "corsair",     "desc": "近海を荒らす海賊。"},
	{"kind": "pirate", "id": "dread",       "desc": "近海を荒らす名の通った海賊。"},
	{"kind": "pirate", "id": "king",        "desc": "かつてはFisherman's Horizonを目指していたが、あまりの困難さに心が折れ海賊に身を落とした。"},
]

# #177: kind+id から敵の定義(def)を引く(討伐記録用)
func enemy_def(kind: String, id: String) -> Dictionary:
	if kind == "pirate":
		return pirates.get(id, {})
	return combat_mobs.get(id, {})

# ---------------------------------------------------------------------------
# 武器 slot=4まで装備。ram は別枠(衝角)。
# #203: speed_mult=プレイヤーが撃つ弾の速度倍率(敵の同名武器には影響しない)
# kind: aim / lock
# ---------------------------------------------------------------------------
var weapons := {
	"gatling": {"name": "ガトリングガン", "kind": "aim",  "speed_mult": 0.85, "dmg": 3,  "cooldown": 0.08, "reload": 1.0, "mag": 40, "range": 120, "price": 500,  "slip": false, "debuff": false, "homing": false, "falloff": true, "sfx": "sfx_gun",     "desc": "単発威力小・連射力大。遠距離では威力減衰(#63)"},
	"cannon":  {"name": "大砲",           "kind": "aim",  "speed_mult": 0.7,  "dmg": 35, "cooldown": 1.4,  "reload": 1.6, "mag": 4,  "range": 140, "price": 1200, "slip": true,  "debuff": false, "homing": false, "pirate_burn": 0.7, "sfx": "sfx_cannon",  "desc": "単発威力大・連射小。海賊船に高確率で炎上(スリップ)"},
	"harpoon": {"name": "銛",             "kind": "aim",  "speed_mult": 0.6,  "dmg": 18, "cooldown": 1.0,  "reload": 1.2, "mag": 6,  "range": 100, "price": 900,  "slip": false, "debuff": true,  "homing": false, "sfx": "sfx_harpoon", "desc": "中威力。主・戦闘モブにデバフ付与(毒/弱体)"},
	"torpedo": {"name": "魚雷",           "kind": "lock", "speed_mult": 0.8,  "dmg": 22, "cooldown": 0.9,  "reload": 2.0, "mag": 8,  "range": 160, "price": 1500, "slip": false, "debuff": false, "homing": true,  "pirate_burn": 0.35, "sfx": "sfx_torpedo", "desc": "ロックオンで追尾。空中の敵には不可。海賊船に確率で炎上"},
	# #102: 嵐越え(tier>=3)以降で買える上位互換。#190: 月下の島の追加で嵐越えがindex3へ。新種は増やさず各武器の強化版
	"gatling2":{"name": "重ガトリング砲", "kind": "aim",  "speed_mult": 0.85, "dmg": 4,  "cooldown": 0.07, "reload": 0.9, "mag": 55, "range": 145, "price": 5000, "slip": false, "debuff": false, "homing": false, "falloff": true, "tier": 3, "sfx": "sfx_gun",     "desc": "ガトリングの上位。連射・射程・弾数を強化"},
	"cannon2": {"name": "大口径カノン砲", "kind": "aim",  "speed_mult": 0.7,  "dmg": 46, "cooldown": 1.25, "reload": 1.4, "mag": 5,  "range": 165, "price": 6500, "slip": true,  "debuff": false, "homing": false, "pirate_burn": 0.7, "tier": 3, "sfx": "sfx_cannon",  "desc": "大砲の上位。単発威力・射程を強化"},
	"harpoon2":{"name": "強化銛砲",       "kind": "aim",  "speed_mult": 0.6,  "dmg": 24, "cooldown": 0.85, "reload": 1.0, "mag": 9,  "range": 125, "price": 5500, "slip": false, "debuff": true,  "homing": false, "tier": 3, "sfx": "sfx_harpoon", "desc": "銛の上位。連射・デバフ効率を強化"},
	"torpedo2":{"name": "追尾魚雷改",     "kind": "lock", "speed_mult": 0.8,  "dmg": 30, "cooldown": 0.8,  "reload": 1.7, "mag": 10, "range": 195, "price": 8000, "slip": false, "debuff": false, "homing": true,  "pirate_burn": 0.35, "tier": 3, "sfx": "sfx_torpedo", "desc": "魚雷の上位。追尾・射程・弾数を強化"},
}

var rams := {
	"none":  {"name": "なし",       "dmg": 0,   "price": 0},
	# #170: 衝角の攻撃力を全体的に強化
	"iron":  {"name": "鉄製衝角",   "dmg": 65,  "price": 600},
	"steel": {"name": "鋼鉄衝角",   "dmg": 150,  "price": 2000},
	# #102: 嵐越え(tier>=3)以降の上位衝角。#190: 月下の島の追加で嵐越えがindex3へ
	"tungsten": {"name": "超硬タングステン衝角", "dmg": 300, "price": 7000, "tier": 3},
}

# ---------------------------------------------------------------------------
# 船 food=食料積載, hold=魚倉, armor=装甲, slots=武器スロット, range=航行可能な最遠島index
# ---------------------------------------------------------------------------
var ships := {
	"raft":     {"name": "粗末な漁船",     "food": 100, "hold": 12,  "armor": 60,   "slots": 1, "range": 0, "speed": 11.0, "price": 0,     "trade": 0},
	"skiff":    {"name": "武装スキフ",     "food": 140, "hold": 22,  "armor": 140,  "slots": 2, "range": 0, "speed": 11.5, "price": 1500,  "trade": 1000},
	# #157再々: 燃料(food)を共有者指定値に再調整
	"cutter":   {"name": "外洋カッター",   "food": 150, "hold": 30,  "armor": 260,  "slots": 3, "range": 1, "speed": 12.0, "price": 9000,   "trade": 3500},
	# #190: rangeは「販売が解禁される島index」。月下の島(2)の追加でコルベット以降を1つずつ後ろへずらす
	"corvette": {"name": "コルベット",     "food": 200, "hold": 40,  "armor": 480,  "slots": 4, "range": 2, "speed": 12.5, "price": 32000,  "trade": 12000},   # #190: 月下の島で追加
	# #228: 猟特化フリゲートを駆逐艦へ改称。快速艦は後退時の減速が緩やか(reverse=0.9)
	"hunter_h": {"name": "駆逐艦",         "food": 170, "hold": 32,  "armor": 600,  "slots": 4, "range": 3, "speed": 15.0, "price": 50000,  "trade": 18000, "reverse": 0.9},
	"hauler":   {"name": "大型運搬艦",     "food": 240, "hold": 70,  "armor": 720,  "slots": 4, "range": 3, "speed": 11.0, "price": 50000,  "trade": 18000},
	# #228: 果ての島での追加順は軽→重→快速→巨大。visualは既存のフリゲート/快速艦の船影を共用する
	"frigate_l":{"name": "軽フリゲート",   "food": 250, "hold": 35,  "armor": 800,  "slots": 4, "range": 4, "speed": 16.0, "price": 70000,  "trade": 25000, "reverse": 0.9, "visual": "hunter_h"},
	"frigate_h":{"name": "重フリゲート",   "food": 280, "hold": 40,  "armor": 900,  "slots": 4, "range": 4, "speed": 15.0, "price": 90000,  "trade": 32000, "reverse": 0.9, "visual": "cruiser"},
	# #151/#228: 巡洋戦艦を快速戦艦へ改称。低装甲・高速・中型・後退が得意
	"cruiser":  {"name": "快速戦艦",       "food": 300, "hold": 45,  "armor": 1000, "slots": 4, "range": 4, "speed": 14.5, "price": 110000, "trade": 40000, "reverse": 0.9},
	"dread":    {"name": "巨大戦艦",       "food": 350, "hold": 55,  "armor": 1300, "slots": 4, "range": 4, "speed": 13.0, "price": 110000, "trade": 40000},
}

# ---------------------------------------------------------------------------
# 島 fame_req=入港に必要な名声, price_mult=遠隔ほど高額買取, lords/spawn
# #206: 漁獲物の売値を一律引き上げ(潮鳴り1.3倍 月下1.5倍 嵐越え2倍 果て3倍)
# ---------------------------------------------------------------------------
# #239: 島を3つ追加(星霜/常闇=月下と同格, 海嘯=嵐越えと同格)。
# **既存の島indexは動かさず末尾に追加する**(indexを挿入するとセーブ・各所の
# index比較・配列長がまとめて壊れるため。#190でその苦労をしている)。
# 代わりに各島へ `tier`(進行段階)を持たせ、強さ・価格帯・解禁判定は
# indexではなく tier で見る。tier: 0始まり 1潮鳴り 2月下級 3嵐越え級 4果て
var islands := [
	{"id": 0, "name": "始まりの島",   "tier": 0, "fame_req": 0,   "price_mult": 1.0, "pos": Vector3(0, 0, 0),       "spawn": ["sardine","mackerel"], "lords": ["sawshark","dumbo"]},
	# #174/#200: 次の島到達に必要な名声を全体的に引き上げ(その島の主だけでは足りず、海賊狩りが要る水準)
	{"id": 1, "name": "潮鳴りの島",   "tier": 1, "fame_req": 22,   "price_mult": 2.08, "pos": Vector3(900, 0, -300),  "spawn": ["bonito","squid","mackerel"], "lords": ["whale","walrus"]},   # #57再: 元の距離に戻す
	# #190: 3つ目の島。砂漠とわずかな緑地。近海は常に夜(weather="night")
	{"id": 2, "name": "月下の島",     "tier": 2, "fame_req": 70,  "price_mult": 3.0, "pos": Vector3(1700, 0, 200),  "spawn": ["squid","octopus","bonito"], "lords": ["aspidochelone","legion"], "weather": "night"},
	# #190: 月下の島の追加に伴い、嵐越え・果ては従来よりさらに遠方へ。#191/#192: 近海の天候演出
	{"id": 3, "name": "嵐越えの島",   "tier": 3, "fame_req": 175,  "price_mult": 4.8, "pos": Vector3(2600, 0, 900),  "spawn": ["octopus","squid","bonito"], "lords": ["hydra","quetzal"], "weather": "storm"},
	{"id": 4, "name": "果ての島",     "tier": 4, "fame_req": 272,  "price_mult": 10.8, "pos": Vector3(3600, 0, 300), "spawn": ["octopus","bonito"], "lords": ["ghost","leviathan"], "weather": "blizzard"},   # #187: 幽霊船はレヴィアタンの上(先に戦う想定)
	# #239: 月下の島と同格(tier 2)。星霜=月下の北、常闇=月下の南
	{"id": 5, "name": "星霜の島",     "tier": 2, "fame_req": 70,  "price_mult": 3.0, "pos": Vector3(1700, 0, -700), "spawn": ["squid","octopus","bonito"], "lords": ["undine","siren"], "weather": "starry"},
	{"id": 6, "name": "常闇の島",     "tier": 2, "fame_req": 70,  "price_mult": 3.0, "pos": Vector3(1700, 0, 1100), "spawn": ["squid","octopus","bonito"], "lords": ["night_emperor","wraith"], "weather": "dark"},
	# #239: 嵐越えの島と同格(tier 3)。海嘯=嵐越えの南
	{"id": 7, "name": "海嘯の島",     "tier": 3, "fame_req": 175, "price_mult": 4.8, "pos": Vector3(2600, 0, 1900), "spawn": ["octopus","squid","bonito"], "lords": ["kraken_lord","griffon"], "weather": "surge"},
]

# #202: 出現海域ごとの敵HP倍率(始まり=等倍 / 潮鳴り1.5 / 月下1.9 / 嵐越え2.7 / 果て3.3)。
# 1の位は切り上げて10の倍数にする。Enemy2Dの実HPと、酒場・討伐記録の表示で共用する。
# #224再: 突撃は衝角を積んでいなくても船体の体当たりとして一定のダメージが入る。
# 衝角なしの時だけこの値を使う(鉄の衝角65より弱い=衝角を積む価値は残る)
const HULL_RAM_DMG := 30.0

# #202再3: 潮鳴りの島(tier1)以降の敵HPを一律2%引き上げ(始まりの島は据え置き)。
#   1.5→1.53 / 1.9→1.938 / 2.7→2.754 / 3.3→3.366
const HP_TIER_MULT := [1.0, 1.53, 1.938, 2.754, 3.366]

# #202再2: 桁数で丸め方を変える。
#   3桁以下 … そのまま / 4桁 … 十の位を切り上げ(=100の倍数へ切り上げ) / 5桁以上 … 999以下を切り捨て
func scaled_hp(base: float, island_idx: int) -> int:
	var m: float = HP_TIER_MULT[clampi(tier_of(island_idx), 0, HP_TIER_MULT.size() - 1)]   # #239: tierで引く
	var v := int(round(base * m))
	if v < 1000:
		return v
	if v < 10000:
		return int(ceilf(float(v) / 100.0) * 100.0)
	return int(floorf(float(v) / 1000.0) * 1000.0)

func island(idx: int) -> Dictionary:
	return islands[clampi(idx, 0, islands.size() - 1)]

# #239: 島の進行段階。強さ・価格帯・販売解禁・雇用条件は index ではなく tier で見る
# (島を末尾に追加してもこれらが壊れないようにするため)
# #239再: 航路メニューなどで見せる並び順(進行順)。
# islands の並びは「index を動かさない」都合で追加順になっているため、
# 表示は tier 順 → 同じ tier 内は本来の攻略順(月下→星霜→常闇 / 嵐越え→海嘯)にする。
const ISLAND_ORDER := [0, 1, 2, 5, 6, 3, 7, 4]

func islands_in_order() -> Array:
	var out: Array = []
	for i in ISLAND_ORDER:
		if int(i) < islands.size():
			out.append(islands[int(i)])
	# 定義漏れがあっても取りこぼさないよう、未掲載の島は末尾へ足す
	for isle in islands:
		if not out.has(isle):
			out.append(isle)
	return out

func tier_of(idx: int) -> int:
	return int(island(idx).get("tier", clampi(idx, 0, 4)))

func fish_def(id: String) -> Dictionary:
	return fish.get(id, {})

# 指定の島で売れる単価(遠隔地の漁獲ほど高額)。home島の主魚は基準、他島ではprice_mult適用。
func sale_price(item_id: String, at_island: int) -> int:
	var mult: float = island(at_island).price_mult
	if fish.has(item_id):
		var f: Dictionary = fish[item_id]
		if f.get("rare", false):
			return int(f.price * maxf(1.0, mult))  # レア魚はどの島でも高い
		return int(f.price * mult)
	if combat_mobs.has(item_id):
		return int(combat_mobs[item_id].price * mult)
	if lords.has(item_id):
		# 主は対応する島でしか売れない
		if lords[item_id].island == at_island:
			return int(lords[item_id].price)
		return 0
	return 0
