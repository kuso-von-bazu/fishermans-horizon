extends Node
## Database — ゲーム内の静的データ(船・武器・魚・モンスター・島)を保持するシングルトン。
## 企画書 "Fisherman's Horizon" に基づく。数値はMVP用のバランス初期値。

# ---------------------------------------------------------------------------
# 魚モブ(戦闘なしで漁獲可能) cap=魚倉キャパ消費, price=基準買取額, dist=主分布の島index
# ---------------------------------------------------------------------------
var fish := {
	"sardine":  {"name": "イワシ",   "cap": 1, "price": 20,  "home": 0, "color": Color(0.7,0.8,0.9)},
	"mackerel": {"name": "サバ",     "cap": 2, "price": 45,  "home": 0, "color": Color(0.4,0.6,0.8)},
	"bonito":   {"name": "カツオ",   "cap": 3, "price": 90,  "home": 1, "color": Color(0.3,0.5,0.7)},
	"squid":    {"name": "イカ",     "cap": 2, "price": 70,  "home": 1, "color": Color(0.9,0.8,0.85)},
	"octopus":  {"name": "タコ",     "cap": 2, "price": 80,  "home": 2, "color": Color(0.8,0.4,0.45)},
	"grouper":  {"name": "クエ",     "cap": 1, "price": 300, "home": -1,"color": Color(0.55,0.4,0.3), "rare": true},
}

# ---------------------------------------------------------------------------
# 戦闘モブ(倒せば漁獲可能) hp/dmg/cap/price + flags
# ---------------------------------------------------------------------------
var combat_mobs := {
	"narwhal":       {"name": "ユニコーン",     "hp": 60,  "dmg": 4,  "cap": 3, "price": 150, "ranged": false, "aerial": false, "color": Color(0.85,0.85,0.9)},
	"seahunter":     {"name": "シーハンター",   "hp": 140, "dmg": 8,  "cap": 4, "price": 320, "ranged": false, "aerial": false, "color": Color(0.2,0.2,0.25)},
	"ornithocheirus":{"name": "オルニケイトス", "hp": 90,  "dmg": 7,  "cap": 3, "price": 280, "ranged": false, "aerial": true,  "color": Color(0.7,0.6,0.4)},
	"wyrm":          {"name": "ワイアーム",     "hp": 220, "dmg": 12, "cap": 4, "price": 500, "ranged": true,  "aerial": false, "color": Color(0.6,0.2,0.2)},
}

# ---------------------------------------------------------------------------
# 近海の主(ボス) 主は対応する島でしか売れない。bounty=賞金, cap=魚倉圧迫
# ---------------------------------------------------------------------------
var lords := {
	"sawshark":  {"name": "電動ノコギリザメ",         "hp": 400,  "dmg": 14, "cap": 8,  "price": 800,  "bounty": 1500,  "island": 0, "ranged": false, "aerial": false, "pair": false},
	"dumbo":     {"name": "ウミダンボ",               "hp": 550,  "dmg": 12, "cap": 9,  "price": 1000, "bounty": 2000,  "island": 0, "ranged": false, "aerial": false, "pair": false},
	"whale":     {"name": "ヒゲマッコウナガスクジラ", "hp": 900,  "dmg": 18, "cap": 14, "price": 1800, "bounty": 3500,  "island": 1, "ranged": false, "aerial": false, "pair": false},
	"walrus":    {"name": "ギガントセイウチ",         "hp": 480,  "dmg": 16, "cap": 7,  "price": 1200, "bounty": 4000,  "island": 1, "ranged": false, "aerial": false, "pair": true},
	"hydra":     {"name": "ヒュドラ",                 "hp": 1100, "dmg": 20, "cap": 12, "price": 2400, "bounty": 6000,  "island": 2, "ranged": true,  "aerial": false, "pair": false},
	"quetzal":   {"name": "ケツァルコアトル",         "hp": 1300, "dmg": 22, "cap": 13, "price": 3000, "bounty": 8000,  "island": 2, "ranged": false, "aerial": true,  "pair": false},
	"leviathan": {"name": "レヴィアタン",             "hp": 4000, "dmg": 35, "cap": 25, "price": 9999, "bounty": 50000, "island": 3, "ranged": true,  "aerial": false, "pair": false},
}

# ---------------------------------------------------------------------------
# 海賊(首だけ持ち帰る=魚倉を圧迫しない) bounty で換金
# ---------------------------------------------------------------------------
var pirates := {
	"raider":   {"name": "海賊(小)", "hp": 120, "dmg": 7,  "bounty": 200,  "fame": 1, "ranged": true, "color": Color(0.4,0.3,0.2)},
	"corsair":  {"name": "海賊(中)", "hp": 260, "dmg": 10, "bounty": 500,  "fame": 2, "ranged": true, "color": Color(0.35,0.25,0.15)},
	"dread":    {"name": "海賊(大)", "hp": 500, "dmg": 15, "bounty": 1200, "fame": 4, "ranged": true, "color": Color(0.25,0.18,0.1)},
}

# ---------------------------------------------------------------------------
# 武器 slot=4まで装備。ram は別枠(衝角)。
# kind: aim / lock
# ---------------------------------------------------------------------------
var weapons := {
	"gatling": {"name": "ガトリングガン", "kind": "aim",  "dmg": 3,  "cooldown": 0.08, "reload": 1.0, "mag": 40, "range": 120, "price": 500,  "slip": false, "debuff": false, "homing": false, "sfx": "sfx_gun",     "desc": "単発威力小・連射力大。弾幕で継続ダメージ"},
	"cannon":  {"name": "大砲",           "kind": "aim",  "dmg": 35, "cooldown": 1.4,  "reload": 1.6, "mag": 4,  "range": 140, "price": 1200, "slip": true,  "debuff": false, "homing": false, "sfx": "sfx_cannon",  "desc": "単発威力大・連射小。海賊船にスリップ(漏水/火災)"},
	"harpoon": {"name": "銛",             "kind": "aim",  "dmg": 18, "cooldown": 1.0,  "reload": 1.2, "mag": 6,  "range": 100, "price": 900,  "slip": false, "debuff": true,  "homing": false, "sfx": "sfx_harpoon", "desc": "中威力。主にデバフ付与(毒/弱体)"},
	"torpedo": {"name": "魚雷",           "kind": "lock", "dmg": 22, "cooldown": 0.9,  "reload": 2.0, "mag": 8,  "range": 160, "price": 1500, "slip": false, "debuff": false, "homing": true,  "sfx": "sfx_torpedo", "desc": "ロックオンで追尾。空中の敵には不可"},
}

var rams := {
	"none":  {"name": "なし",       "dmg": 0,   "price": 0},
	"iron":  {"name": "鉄製衝角",   "dmg": 40,  "price": 600},
	"steel": {"name": "鋼鉄衝角",   "dmg": 90,  "price": 2000},
}

# ---------------------------------------------------------------------------
# 船 food=食料積載, hold=魚倉, armor=装甲, slots=武器スロット, range=航行可能な最遠島index
# ---------------------------------------------------------------------------
var ships := {
	"raft":     {"name": "粗末な漁船",     "food": 100, "hold": 12,  "armor": 60,   "slots": 1, "range": 0, "speed": 11.0, "price": 0,     "trade": 0},
	"skiff":    {"name": "武装スキフ",     "food": 140, "hold": 18,  "armor": 140,  "slots": 2, "range": 0, "speed": 11.5, "price": 1500,  "trade": 1000},
	"cutter":   {"name": "外洋カッター",   "food": 260, "hold": 30,  "armor": 260,  "slots": 3, "range": 1, "speed": 12.0, "price": 5000,  "trade": 3500},
	"corvette": {"name": "コルベット",     "food": 360, "hold": 40,  "armor": 480,  "slots": 4, "range": 2, "speed": 12.5, "price": 14000, "trade": 9000},
	"hunter_h": {"name": "猟特化フリゲート","food": 320, "hold": 32,  "armor": 600,  "slots": 4, "range": 2, "speed": 13.5, "price": 22000, "trade": 14000},
	"hauler":   {"name": "大型運搬艦",     "food": 420, "hold": 70,  "armor": 520,  "slots": 4, "range": 2, "speed": 11.0, "price": 22000, "trade": 14000},
	"dread":    {"name": "弩級戦艦",       "food": 520, "hold": 60,  "armor": 1100, "slots": 4, "range": 3, "speed": 13.0, "price": 60000, "trade": 40000},
}

# ---------------------------------------------------------------------------
# 島 fame_req=入港に必要な名声, price_mult=遠隔ほど高額買取, lords/spawn
# ---------------------------------------------------------------------------
var islands := [
	{"id": 0, "name": "始まりの島",   "fame_req": 0,   "price_mult": 1.0, "pos": Vector3(0, 0, 0),       "spawn": ["sardine","mackerel"], "lords": ["sawshark","dumbo"]},
	{"id": 1, "name": "潮鳴りの島",   "fame_req": 5,   "price_mult": 1.6, "pos": Vector3(900, 0, -300),  "spawn": ["bonito","squid","mackerel"], "lords": ["whale","walrus"]},
	{"id": 2, "name": "嵐越えの島",   "fame_req": 20,  "price_mult": 2.4, "pos": Vector3(1500, 0, 600),  "spawn": ["octopus","squid","bonito"], "lords": ["hydra","quetzal"]},
	{"id": 3, "name": "果ての島",     "fame_req": 60,  "price_mult": 3.6, "pos": Vector3(2400, 0, -200), "spawn": ["octopus","bonito"], "lords": ["leviathan"]},
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
