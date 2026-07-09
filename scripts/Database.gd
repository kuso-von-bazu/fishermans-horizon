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
	"ornithocheirus":{"name": "オルニケイトス", "hp": 160, "dmg": 11, "cap": 3, "price": 224, "ranged": false, "aerial": true,  "speed": 21.0, "color": Color(0.7,0.6,0.4)},
	"wyrm":          {"name": "ワイアーム",     "hp": 400, "dmg": 18, "cap": 4, "price": 400, "ranged": true,  "aerial": false, "speed": 7.0,  "atk_cd": 0.8, "face_left": true, "color": Color(0.6,0.2,0.2)},
	# #69: 潮鳴り以降の強モブ。reach=触腕の射程倍率, entangle=被弾で討伐まで鈍足
	"kraken":        {"name": "クラーケン",     "hp": 700, "dmg": 24, "cap": 6, "price": 720,  "ranged": false, "aerial": false, "speed": 8.5,  "reach": 2.2, "entangle": true, "color": Color(0.5,0.2,0.45)},
	"wyvern":        {"name": "ワイバーン",     "hp": 800, "dmg": 26, "cap": 6, "price": 800, "ranged": true,  "aerial": false, "speed": 9.5,  "atk_cd": 1.1, "face_left": true, "color": Color(0.7,0.15,0.15)},
	# #71: 嵐越え以降。merman=群れ+俊敏+好戦的, charybdis=渦潮+確率回避。#98再: マーマンHP350
	"merman":        {"name": "マーマン",       "hp": 350, "dmg": 16, "cap": 2, "price": 304,  "ranged": false, "aerial": false, "speed": 13.0, "group": 3, "aggro": 1400.0, "face_left": true, "color": Color(0.25,0.55,0.4)},
	"charybdis":     {"name": "カリュブディス", "hp": 900, "dmg": 28, "cap": 8, "price": 960, "ranged": true,  "aerial": false, "speed": 9.5,  "dodge": 0.333, "entangle": true, "color": Color(0.15,0.3,0.45)},
	# #71: 嵐越え以降。amphiptere=空中(魚雷ロック不可)+近接のみ+高速で追尾(竜×蛇の有翼)
	"amphiptere":    {"name": "アンフィプテレ", "hp": 780, "dmg": 32, "cap": 6, "price": 760, "ranged": false, "aerial": true, "speed": 15.0, "aggro": 1300.0, "color": Color(0.45,0.2,0.5)},
	# #72再: 果ての島。tiamat=空中(魚雷ロック不可)+俊敏+高火力+炎上弾+低回避, dagon=触腕+絡め+毒+高速。強化
	"tiamat":        {"name": "ティアマット",   "hp": 1600, "dmg": 42, "cap": 10, "price": 1440, "ranged": true, "aerial": true, "speed": 16.0, "atk_cd": 1.0, "dodge": 0.15, "dodge_pass": true, "burn_chance": 0.6, "zigzag": true, "face_left": true, "color": Color(0.15,0.12,0.2)},
	"dagon":         {"name": "ダゴン",         "hp": 1500, "dmg": 40, "cap": 9,  "price": 1280, "ranged": false, "aerial": false, "speed": 10.0, "reach": 2.5, "entangle": true, "poison": true, "color": Color(0.3,0.5,0.35)},
}

# 島tierごとの戦闘モブ出現重み(#38/#69/#71/#72/#75)。
# #75: 潮鳴り以降はユニコーン/シーハンター/オルニケイトスを外し強モブのみ。
var mob_weights := [
	{"narwhal": 0.55, "seahunter": 0.25, "ornithocheirus": 0.15, "wyrm": 0.05},
	{"wyrm": 0.45, "kraken": 0.35, "wyvern": 0.20},
	{"kraken": 0.24, "wyvern": 0.20, "merman": 0.20, "charybdis": 0.18, "amphiptere": 0.18},              # #75/#71: 嵐越え以降はワイアーム非出現+アンフィプテレ
	{"merman": 0.2, "charybdis": 0.2, "tiamat": 0.2, "dagon": 0.2, "amphiptere": 0.2},                    # #75再/#71: 果てはクラーケン/ワイバーンも非出現
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
# #65: 全主が遠隔攻撃を持つ。way=同時弾数(扇状), homing=追跡弾, radial=全方向, homing_count=追跡弾数
var lords := {
	"sawshark":  {"name": "電動ノコギリザメ",         "hp": 730,  "dmg": 21, "cap": 8,  "price": 800,  "bounty": 1500,  "fame": 8,  "island": 0, "ranged": true, "aerial": false, "pair": false, "speed": 9.5, "way": 3, "dir": 0, "face_left": true, "lore": "旧人類の狂気が生んだ悲しきモンスター。"},
	"dumbo":     {"name": "ウミダンボ",               "hp": 1000, "dmg": 18, "cap": 9,  "price": 1000, "bounty": 2000,  "fame": 10, "island": 0, "ranged": true, "aerial": false, "pair": false, "speed": 7.5, "way": 3, "dir": 135, "lore": "大きな耳で器用に泳ぐ。旧大陸が極度の海面上昇で沈没していく中、海に適応した象。地上の象は絶滅しており、現生人類にとって象は海の動物。"},
	"whale":     {"name": "ヒゲマッコウナガスクジラ", "hp": 1640, "dmg": 27, "cap": 14, "price": 1800, "bounty": 3500,  "fame": 16, "island": 1, "ranged": true, "aerial": false, "pair": false, "speed": 8.5, "way": 3, "homing": true, "dir": 45, "face_left": true, "lore": "富栄養化の影響で体長は50メートルにも達する。"},
	"walrus":    {"name": "ギガントセイウチ",         "hp": 870,  "dmg": 24, "cap": 7,  "price": 1200, "bounty": 4000,  "fame": 18, "island": 1, "ranged": true, "aerial": false, "pair": true, "speed": 8.5,  "way": 3, "dir": 225, "lore": "おしどり夫婦でいつも夫婦で行動している。"},
	# #110/#111: ヒュドラ/ケツァル/レヴィアタンを強化。#65: 弾幕(way/homing_count/radial_count)と確定炎上(burn_fire)
	"hydra":     {"name": "ヒュドラ",                 "hp": 3200, "dmg": 46, "cap": 12, "price": 2400, "bounty": 6000,  "fame": 25, "island": 2, "ranged": true,  "aerial": false, "pair": false, "speed": 8.5, "way": 7, "fire": true, "burn_fire": true, "homing_count": 2, "dir": 90, "lore": "旧人類が神を作り出す過程で生まれた失敗作。口から炎を吐いて攻撃してくる。"},
	"quetzal":   {"name": "ケツァルコアトル",         "hp": 3600, "dmg": 50, "cap": 13, "price": 3000, "bounty": 8000,  "fame": 30, "island": 2, "ranged": true, "aerial": true,  "pair": false, "speed": 13.0, "way": 5, "homing_count": 2, "dodge": 0.12, "dodge_pass": true, "kite": true, "always_front": true, "dir": 270, "lore": "空中から攻撃してくるので、魚雷でのロックオンは不可能。旧人類がレヴィアタンへの対抗策として創造したが、彼らはそれぞれ空と海を荒らしまわるばかりであった。"},
	"leviathan": {"name": "レヴィアタン",             "hp": 6800, "dmg": 50, "cap": 25, "price": 9999, "bounty": 50000, "fame": 60, "island": 3, "ranged": true,  "aerial": false, "pair": false, "speed": 9.0, "radial": true, "radial_count": 18, "homing_count": 4, "dir": 180, "face_left": true, "lore": "旧人類が創り出した神。神の領域に達した旧人類のバイオテクノロジーは神をも創造したが、皮肉にもそれは人類種の天敵となり、残されたわずかな陸地を除いて人類の生存可能領域はなくなった。"},
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
	# #66: wpn=遠隔攻撃の種類(gatling=連射弾/cannon=砲弾/torpedo=追尾魚雷/all=全部+衝角)
	# #66: 中はガトリング3連+大砲、大はガトリング3連+追尾魚雷を同時に撃つ(volley)
	"raider":   {"name": "海賊(小)", "hp": 220, "dmg": 11,  "bounty": 90,  "fame": 1, "ranged": true, "wpn": "gatling", "color": Color(0.4,0.3,0.2)},
	"corsair":  {"name": "海賊(中)", "hp": 450, "dmg": 16, "bounty": 220, "fame": 2, "ranged": true, "volley": ["gatling", "cannon"],  "color": Color(0.35,0.25,0.15)},
	"dread":    {"name": "海賊(大)", "hp": 900, "dmg": 24, "bounty": 500, "fame": 4, "ranged": true, "volley": ["gatling", "torpedo"], "color": Color(0.25,0.18,0.1)},
	# #73: レアスポーンの強敵。かつてFisherman's Horizonを目指し、心折れて海賊に落ちた男。
	# hp/dmgは出現海域(island)に応じてEnemy2Dで強化。
	"king":     {"name": "海賊王",   "hp": 2200, "dmg": 28, "bounty": 4000, "fame": 30, "ranged": true, "wpn": "all", "speed": 12.0, "atk_cd": 0.9, "color": Color(0.1,0.08,0.1)},
}

# ---------------------------------------------------------------------------
# 武器 slot=4まで装備。ram は別枠(衝角)。
# kind: aim / lock
# ---------------------------------------------------------------------------
var weapons := {
	"gatling": {"name": "ガトリングガン", "kind": "aim",  "dmg": 3,  "cooldown": 0.08, "reload": 1.0, "mag": 40, "range": 120, "price": 500,  "slip": false, "debuff": false, "homing": false, "falloff": true, "sfx": "sfx_gun",     "desc": "単発威力小・連射力大。遠距離では威力減衰(#63)"},
	"cannon":  {"name": "大砲",           "kind": "aim",  "dmg": 35, "cooldown": 1.4,  "reload": 1.6, "mag": 4,  "range": 140, "price": 1200, "slip": true,  "debuff": false, "homing": false, "pirate_burn": 0.7, "sfx": "sfx_cannon",  "desc": "単発威力大・連射小。海賊船に高確率で炎上(スリップ)"},
	"harpoon": {"name": "銛",             "kind": "aim",  "dmg": 18, "cooldown": 1.0,  "reload": 1.2, "mag": 6,  "range": 100, "price": 900,  "slip": false, "debuff": true,  "homing": false, "sfx": "sfx_harpoon", "desc": "中威力。主・戦闘モブにデバフ付与(毒/弱体)"},
	"torpedo": {"name": "魚雷",           "kind": "lock", "dmg": 22, "cooldown": 0.9,  "reload": 2.0, "mag": 8,  "range": 160, "price": 1500, "slip": false, "debuff": false, "homing": true,  "pirate_burn": 0.35, "sfx": "sfx_torpedo", "desc": "ロックオンで追尾。空中の敵には不可。海賊船に確率で炎上"},
	# #102: 嵐越え(tier>=2)以降で買える上位互換。新種は増やさず各武器の強化版
	"gatling2":{"name": "重ガトリング砲", "kind": "aim",  "dmg": 4,  "cooldown": 0.07, "reload": 0.9, "mag": 55, "range": 145, "price": 5000, "slip": false, "debuff": false, "homing": false, "falloff": true, "tier": 2, "sfx": "sfx_gun",     "desc": "ガトリングの上位。連射・射程・弾数を強化"},
	"cannon2": {"name": "大口径カノン砲", "kind": "aim",  "dmg": 46, "cooldown": 1.25, "reload": 1.4, "mag": 5,  "range": 165, "price": 6500, "slip": true,  "debuff": false, "homing": false, "pirate_burn": 0.7, "tier": 2, "sfx": "sfx_cannon",  "desc": "大砲の上位。単発威力・射程を強化"},
	"harpoon2":{"name": "強化銛砲",       "kind": "aim",  "dmg": 24, "cooldown": 0.85, "reload": 1.0, "mag": 9,  "range": 125, "price": 5500, "slip": false, "debuff": true,  "homing": false, "tier": 2, "sfx": "sfx_harpoon", "desc": "銛の上位。連射・デバフ効率を強化"},
	"torpedo2":{"name": "追尾魚雷改",     "kind": "lock", "dmg": 30, "cooldown": 0.8,  "reload": 1.7, "mag": 10, "range": 195, "price": 8000, "slip": false, "debuff": false, "homing": true,  "pirate_burn": 0.35, "tier": 2, "sfx": "sfx_torpedo", "desc": "魚雷の上位。追尾・射程・弾数を強化"},
}

var rams := {
	"none":  {"name": "なし",       "dmg": 0,   "price": 0},
	"iron":  {"name": "鉄製衝角",   "dmg": 40,  "price": 600},
	"steel": {"name": "鋼鉄衝角",   "dmg": 90,  "price": 2000},
	# #102: 嵐越え(tier>=2)以降の上位衝角
	"tungsten": {"name": "超硬タングステン衝角", "dmg": 180, "price": 7000, "tier": 2},
}

# ---------------------------------------------------------------------------
# 船 food=食料積載, hold=魚倉, armor=装甲, slots=武器スロット, range=航行可能な最遠島index
# ---------------------------------------------------------------------------
var ships := {
	"raft":     {"name": "粗末な漁船",     "food": 100, "hold": 12,  "armor": 60,   "slots": 1, "range": 0, "speed": 11.0, "price": 0,     "trade": 0},
	"skiff":    {"name": "武装スキフ",     "food": 140, "hold": 18,  "armor": 140,  "slots": 2, "range": 0, "speed": 11.5, "price": 1500,  "trade": 1000},
	"cutter":   {"name": "外洋カッター",   "food": 260, "hold": 30,  "armor": 260,  "slots": 3, "range": 1, "speed": 12.0, "price": 9000,   "trade": 3500},
	"corvette": {"name": "コルベット",     "food": 360, "hold": 40,  "armor": 480,  "slots": 4, "range": 2, "speed": 12.5, "price": 32000,  "trade": 12000},
	"hunter_h": {"name": "猟特化フリゲート","food": 320, "hold": 32,  "armor": 600,  "slots": 4, "range": 2, "speed": 13.5, "price": 50000,  "trade": 18000},
	"hauler":   {"name": "大型運搬艦",     "food": 420, "hold": 70,  "armor": 720,  "slots": 4, "range": 2, "speed": 11.0, "price": 50000,  "trade": 18000},
	"dread":    {"name": "弩級戦艦",       "food": 520, "hold": 60,  "armor": 1100, "slots": 4, "range": 3, "speed": 13.0, "price": 110000, "trade": 40000},
	# #151: 巡洋戦艦。弩級と対。低装甲・高速・中型・後退が得意(reverse=後退速度倍率)
	"cruiser":  {"name": "巡洋戦艦",       "food": 460, "hold": 45,  "armor": 780,  "slots": 4, "range": 3, "speed": 14.5, "price": 110000, "trade": 40000, "reverse": 0.9},
}

# ---------------------------------------------------------------------------
# 島 fame_req=入港に必要な名声, price_mult=遠隔ほど高額買取, lords/spawn
# ---------------------------------------------------------------------------
var islands := [
	{"id": 0, "name": "始まりの島",   "fame_req": 0,   "price_mult": 1.0, "pos": Vector3(0, 0, 0),       "spawn": ["sardine","mackerel"], "lords": ["sawshark","dumbo"]},
	{"id": 1, "name": "潮鳴りの島",   "fame_req": 12,   "price_mult": 1.6, "pos": Vector3(900, 0, -300),  "spawn": ["bonito","squid","mackerel"], "lords": ["whale","walrus"]},   # #57再: 元の距離に戻す
	{"id": 2, "name": "嵐越えの島",   "fame_req": 45,  "price_mult": 2.4, "pos": Vector3(1500, 0, 600),  "spawn": ["octopus","squid","bonito"], "lords": ["hydra","quetzal"]},
	{"id": 3, "name": "果ての島",     "fame_req": 120,  "price_mult": 3.6, "pos": Vector3(2400, 0, -200), "spawn": ["octopus","bonito"], "lords": ["leviathan"]},
]

func island(idx: int) -> Dictionary:
	return islands[clampi(idx, 0, islands.size() - 1)]

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
