extends Node
## GameState — 可変のゲーム進行状態(資金・名声・船・装備・積荷・現在地)を保持するシングルトン。
## 航海中の食料/装甲/魚倉は run_* 値で扱い、帰港で精算する。

signal stats_changed
signal money_changed(amount: int)
signal fame_changed(amount: int)
signal notice(text: String)

var money: int = 200
var fame: int = 0

var ship_id: String = "raft"
var weapons: Array[String] = ["gatling"]   # 装備中の武器id(最大slots)
var ram_id: String = "none"
var harpoon_debuff: String = "slip"        # 銛のデバフ種(造船所で設定・#37)

# --- クルー(#39): キャプテン含め5人まで=雇用は4人まで ---
# 各員: {name, job, hp, agi, sht, int_, vis}
var crew: Array = []
const CREW_MAX := 4
var jobs := {
	"sailor":    {"name": "水夫",     "hire": 100,  "wage": 15, "growth": {"hp": 1, "agi": 1, "sht": 1, "int_": 1, "vis": 1}, "desc": "低賃金。すべての基本ジョブ。均等にパラメータが伸びる"},
	"veteran":   {"name": "熟練水夫", "hire": 700,  "wage": 40, "growth": {"hp": 3, "agi": 1, "sht": 1, "int_": 1, "vis": 1}, "req": ["hp", 8], "desc": "中賃金。水夫の上位互換。均等に伸びるが特に体力がよく伸びる"},
	"marine":    {"name": "水兵",     "hire": 700,  "wage": 40, "growth": {"hp": 1, "agi": 2, "sht": 3, "int_": 0, "vis": 1}, "req": ["sht", 8], "desc": "中賃金。攻撃時に確率でクリティカルが出る。敏捷と射撃力がよく伸びる"},
	"navigator": {"name": "航海士",   "hire": 700,  "wage": 40, "growth": {"hp": 0, "agi": 1, "sht": 0, "int_": 3, "vis": 3}, "req": ["vis", 8], "desc": "中賃金。ソナー範囲を強化。知力と視力がよく伸びる"},
	"cook":      {"name": "料理人",   "hire": 700,  "wage": 40, "growth": {"hp": 0, "agi": 1, "sht": 1, "int_": 2, "vis": 1}, "req": ["int_", 6], "desc": "中賃金。食料の減少速度が低下。体力の伸びは悪いが他は水夫より少し伸びる"},
	"firstmate": {"name": "副船長",   "hire": 1500, "wage": 80, "growth": {"hp": 2, "agi": 2, "sht": 2, "int_": 2, "vis": 2}, "req": ["total", 40], "desc": "高賃金。特殊能力はないが高パラメータ。均等によく伸びる(同時に乗せられるのは1名まで)"},
}
const CREW_NAMES := ["ジン", "ハル", "カイ", "レン", "ソラ", "ウミ", "リク", "ナギ", "イサナ", "タツ", "シオン", "マキ"]

# #58: 副船長は同時に1名まで(雇用/ジョブチェンジ共通)
func has_firstmate() -> bool:
	for c in crew:
		if c.job == "firstmate":
			return true
	return false

func hire_crew(job_id: String) -> bool:
	if crew.size() >= CREW_MAX:
		notice.emit("船室が満員です(雇用は%d人まで)" % CREW_MAX)
		return false
	if job_id == "firstmate" and has_firstmate():
		notice.emit("副船長は同時に1名までです")
		return false
	var j: Dictionary = jobs[job_id]
	var cost := hire_cost(job_id)
	if money < cost:
		notice.emit("資金が足りません(契約金%d)" % cost)
		return false
	add_money(-cost)
	# #85再: 嵐越え(island>=2)以降の酒場はボーナス4倍+最低保証UPでより強力なクルー(水夫は据え置き)
	var bm := hire_bonus_mult(job_id)
	var high := current_island >= 2 and job_id != "sailor"
	var base := 1 if job_id == "sailor" else (5 if high else 3)   # 最低保証の底上げ
	var m := {
		"name": _unique_crew_name(),
		"job": job_id,
		"hp": base + randi_range(0, 2 * bm), "agi": base + randi_range(0, 2 * bm),
		"sht": base + randi_range(0, 2 * bm), "int_": base + randi_range(0, 2 * bm),
		"vis": base + randi_range(0, 2 * bm),
	}
	# #85: 上位ジョブは「ジョブチェンジに必要な値」を最低保証+ランダム上乗せ(嵐越え以降は4倍)
	if j.has("req"):
		var req: Array = j.req
		if req[0] == "total":
			var target := int(req[1]) + randi_range(0, 8 * bm)
			var keys := ["hp", "agi", "sht", "int_", "vis"]
			while int(m.hp) + int(m.agi) + int(m.sht) + int(m.int_) + int(m.vis) < target:
				var k: String = keys[randi() % keys.size()]
				m[k] = int(m[k]) + 1
		else:
			m[req[0]] = int(req[1]) + randi_range(0, 4 * bm)
	crew.append(m)
	notice.emit("%s(%s)を雇用" % [m.name, j.name])
	stats_changed.emit()
	return true

# #85再: 嵐越えの島(island>=2)以降は契約金3倍・上乗せ4倍。ただし水夫は据え置き
func hire_cost(job_id: String) -> int:
	var mult := 3 if (current_island >= 2 and job_id != "sailor") else 1
	return int(jobs[job_id].hire) * mult

func hire_bonus_mult(job_id: String = "") -> int:
	return 4 if (current_island >= 2 and job_id != "sailor") else 1

# 使われていない名前を選ぶ(#52)。尽きたら「二代目〜」。
func _unique_crew_name() -> String:
	var used := []
	for c in crew:
		used.append(c.name)
	var avail := CREW_NAMES.filter(func(n): return not used.has(n))
	if not avail.is_empty():
		return avail[randi() % avail.size()]
	var base: String = CREW_NAMES[randi() % CREW_NAMES.size()]
	var i := 2
	while used.has("%s(%d)" % [base, i]):
		i += 1
	return "%s(%d)" % [base, i]

# 解雇(#48)
func fire_crew(m: Dictionary) -> void:
	crew.erase(m)
	notice.emit("%s を解雇した" % m.name)
	stats_changed.emit()

func can_jobchange(m: Dictionary, job_id: String) -> bool:
	var j: Dictionary = jobs[job_id]
	if not j.has("req") or m.job == job_id:
		return false
	if job_id == "firstmate" and has_firstmate():
		return false   # #58: 副船長は同時に1名まで
	if m.get("changed", false) and job_id != "firstmate":
		return false   # #49: 1度だけ。ただし副船長へは2度目も可(#58)
	var req: Array = j.req
	if req[0] == "total":
		return int(m.hp) + int(m.agi) + int(m.sht) + int(m.int_) + int(m.vis) >= int(req[1])
	return int(m.get(req[0], 0)) >= int(req[1])

func jobchange(m: Dictionary, job_id: String) -> void:
	m.job = job_id
	m.changed = true   # #49
	notice.emit("%s は %s にジョブチェンジ!" % [m.name, jobs[job_id].name])
	stats_changed.emit()

# 帰港ごとの成長(ジョブの伸びに沿って+)
const STAT_MAX := 50   # #140再: 各パラメータの上限

func grow_crew() -> void:
	for m in crew:
		var g: Dictionary = jobs[m.job].growth
		for k in g:
			var cur := int(m[k])
			# #153再: 30を超えると上限(50)に近づくほど伸びにくい
			var falloff := 1.0
			if cur > 30:
				falloff = clampf(1.0 - float(cur - 30) / float(STAT_MAX - 30), 0.05, 1.0)
			if randf() < (0.5 + float(g[k]) * 0.18) * 0.8 * falloff:   # #153: 成長速度8割+高値で逓減
				m[k] = mini(cur + maxi(int(g[k]), 0), STAT_MAX)   # #140: 上限50

func crew_wages() -> int:
	# #125: 到達した島が増えるごとに賃金が少しずつ上昇(最遠到達島に比例)
	var reached := 0
	for iid in visited_islands:
		reached = maxi(reached, int(iid))
	var mult := 1.0 + 0.25 * float(reached)
	if reached >= 3:
		mult += 0.75   # #125再: 果ての島到達後はさらに賃金上昇
	var total := 0.0
	for m in crew:
		total += float(jobs[m.job].wage) * mult
	return int(round(total))

func _crew_sum(stat: String) -> int:
	var s := 0
	for m in crew:
		s += int(m.get(stat, 0))
	return s

# --- クルー効果 ---
func food_drain_mult() -> float:   # 体力+料理人: 燃料(食料)減少を低下
	var m := 1.0 / (1.0 + 0.02 * _crew_sum("hp"))
	for c in crew:
		if c.job == "cook":
			m *= 0.85
	return m

func damage_cut() -> float:        # 敏捷: 被ダメカット(最大40%)
	return minf(0.015 * _crew_sum("agi"), 0.40)

func attack_mult() -> float:       # 射撃力: 攻撃威力バフ
	return 1.0 + 0.02 * _crew_sum("sht")

func crit_chance() -> float:       # 水兵: クリティカル(#82/#83: 低め+人数で逓減)
	var n := 0
	for m in crew:
		if m.job == "marine":
			n += 1
	var c := 0.0
	for i in n:
		c += 0.05 * pow(0.8, i)   # 1人目5% 2人目+4% 3人目+3.2%…
	return minf(c, 0.25)

func debuff_dur_mult() -> float:   # 知力: デバフ強化(持続延長)
	return 1.0 + 0.05 * _crew_sum("int_")

func lock_range_mult() -> float:   # 視力+航海士: ロック距離延長
	var m := 1.0 + 0.03 * _crew_sum("vis")
	for c in crew:
		if c.job == "navigator":
			m *= 1.2
	return m

# 被ダメの集約(敏捷カット適用)。#64: 確率で炎上(時間制スリップ)
func damage_player(amount: float) -> void:
	if docking_locked:
		return   # #105: 寄港確定後は被弾しない
	run_armor = maxf(run_armor - amount * (1.0 - damage_cut()), 0.0)
	if at_sea and amount >= 3.0 and burn_t <= 0.0 and randf() < 0.12:
		burn_t = 4.5
		burn_dps = 2.5 + amount * 0.12
		notice.emit("船が炎上! しばらくスリップダメージ")
	stats_changed.emit()

# #65: 確定炎上(ヒュドラの炎7way/レヴィアタンの薙ぎ払いなど)。必ずburn_tを起こす。#143: 4.5秒で解除
func ignite(dps := 4.0) -> void:
	if docking_locked:
		return
	burn_t = 4.5
	burn_dps = dps
	notice.emit("船が炎上! しばらくスリップダメージ")

# #72: ダゴンの毒液。一定時間スリップダメージ
func apply_poison(dur: float, dps: float) -> void:
	if docking_locked:
		return   # #105
	if poison_t <= 0.0:
		notice.emit("毒液を浴びた! しばらくスリップダメージ")
	poison_t = maxf(poison_t, dur)
	poison_dps = dps

# 炎上/毒の時間経過処理(Worldの航海ループから毎フレーム)
func tick_slips(delta: float) -> void:
	if burn_t > 0.0:
		burn_t -= delta
		run_armor = maxf(run_armor - burn_dps * delta, 0.0)
	if poison_t > 0.0:
		poison_t -= delta
		run_armor = maxf(run_armor - poison_dps * delta, 0.0)

# 大破時: 0〜2人ロスト(#97: 起きやすく最大2人)
func wreck_lose_crew() -> String:
	if crew.is_empty():
		return ""
	var count := 0
	if randf() < 0.5:            # #97再: 50%で1人以上
		count = 1
		if randf() < 0.4:        # うち40%で2人
			count = 2
	count = mini(count, crew.size())
	if count == 0:
		return ""
	var lost := []
	for i in count:
		var idx := randi() % crew.size()
		var m: Dictionary = crew[idx]
		lost.append("%s(%s)" % [m.name, jobs[m.job].name])
		crew.remove_at(idx)
	stats_changed.emit()
	return "、".join(lost)

# 積荷: item_id -> 個数(魚倉キャパは Database の cap で計算)
var cargo: Dictionary = {}
# 海賊の首: pirate_id -> 個数(魚倉を圧迫しない)。遺産も別管理。
var heads: Dictionary = {}
var relics: int = 0   # 旧文明の遺産(換金待ち)の総額

var current_island: int = 0
var unlocked_islands: Array[int] = [0]   # 名声で入港可能になった島
var visited_islands: Array[int] = [0]    # 実際に寄港して到達した島(ファストトラベル可・Issue #19)
var defeated_lords: Array[String] = []   # 討伐済みで賞金未受領
var claimed_lords: Array[String] = []    # 賞金受領済み
var guide_target: Dictionary = {}        # #60/#61: ソナーガイド {"kind":"island"|"lord","id":...}
var has_departed: bool = false            # #168: 一度でも出港したか(初回出港のみ燃料費無料)

# #168: 出港時に徴収する燃料費。船の定価の0.5%(小数点以下切り上げ)。粗末な漁船は5固定
func fuel_cost() -> int:
	if ship_id == "raft":
		return 5
	return int(ceil(float(ship().price) * 0.005))

# --- 航海中ランタイム値(出港でリセット) ---
var run_food: float = 0.0
var run_armor: float = 0.0
var fire_burn: float = 0.0   # ヒュドラの炎=時間経過で回復するスリップ被害
var burn_t: float = 0.0      # #64: 炎上の残り秒数
var burn_dps: float = 0.0
var poison_t: float = 0.0    # #72: 毒の残り秒数
var poison_dps: float = 0.0
var at_sea: bool = false
var docking_locked: bool = false   # #101/#105: 寄港確定後は被弾・積荷取得を無効化

# ゲーム全体を初期状態へ(勝利後のリスタート用。オートロードはシーンreloadで消えないため)
func reset_all() -> void:
	money = 200
	fame = 0
	ship_id = "raft"
	weapons = ["gatling"]
	ram_id = "none"
	cargo = {}
	heads = {}
	relics = 0
	current_island = 0
	unlocked_islands = [0]
	visited_islands = [0]
	defeated_lords = []
	claimed_lords = []
	guide_target = {}
	has_departed = false   # #168
	fire_burn = 0.0
	crew = []
	harpoon_debuff = "slip"
	dock_reset()

# ---------------- オートセーブ(#93) ----------------
const SAVE_PATH := "user://save.json"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var data := {
		"money": money, "fame": fame, "ship_id": ship_id,
		"weapons": weapons, "ram_id": ram_id, "harpoon_debuff": harpoon_debuff,
		"crew": crew, "cargo": cargo, "heads": heads, "relics": relics,
		"current_island": current_island,
		"unlocked_islands": unlocked_islands, "visited_islands": visited_islands,
		"defeated_lords": defeated_lords, "claimed_lords": claimed_lords,
		"guide_target": guide_target, "has_departed": has_departed,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	money = int(data.get("money", 200))
	fame = int(data.get("fame", 0))
	ship_id = str(data.get("ship_id", "raft"))
	ram_id = str(data.get("ram_id", "none"))
	harpoon_debuff = str(data.get("harpoon_debuff", "slip"))
	relics = int(data.get("relics", 0))
	current_island = int(data.get("current_island", 0))
	weapons.assign(data.get("weapons", ["gatling"]))
	unlocked_islands.assign(_to_int_array(data.get("unlocked_islands", [0])))
	visited_islands.assign(_to_int_array(data.get("visited_islands", [0])))
	defeated_lords.assign(data.get("defeated_lords", []))
	claimed_lords.assign(data.get("claimed_lords", []))
	guide_target = data.get("guide_target", {})
	has_departed = bool(data.get("has_departed", true))   # #168: 既存セーブは出港済み扱い
	# 辞書の数値はJSONでfloat化するのでintへ戻す
	cargo = _to_int_dict(data.get("cargo", {}))
	heads = _to_int_dict(data.get("heads", {}))
	crew = []
	for c in data.get("crew", []):
		crew.append({
			"name": str(c.get("name", "?")), "job": str(c.get("job", "sailor")),
			"hp": int(c.get("hp", 1)), "agi": int(c.get("agi", 1)),
			"sht": int(c.get("sht", 1)), "int_": int(c.get("int_", 1)),
			"vis": int(c.get("vis", 1)), "changed": bool(c.get("changed", false)),
		})
	dock_reset()
	stats_changed.emit()
	return true

func _to_int_array(a) -> Array:
	var out := []
	for v in a:
		out.append(int(v))
	return out

func _to_int_dict(d) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out

func ship() -> Dictionary:
	return Database.ships[ship_id]

func max_food() -> float:
	return float(ship().food)

func max_hold() -> int:
	return int(ship().hold)

func max_armor() -> float:
	return float(ship().armor)

func used_hold() -> int:
	var total := 0
	for id in cargo:
		var c := _cap_of(id)
		total += c * int(cargo[id])
	return total

func _cap_of(id: String) -> int:
	if Database.fish.has(id):
		return int(Database.fish[id].cap)
	if Database.combat_mobs.has(id):
		return int(Database.combat_mobs[id].cap)
	if Database.lords.has(id):
		return int(Database.lords[id].cap)
	return 1

func free_hold() -> int:
	return max_hold() - used_hold()

# 帰港中(港にいる)状態に初期化
func dock_reset() -> void:
	at_sea = false
	run_food = max_food()
	run_armor = max_armor()
	stats_changed.emit()

func set_sail() -> void:
	at_sea = true
	docking_locked = false   # #105: 出港で解除
	run_food = max_food()
	run_armor = max_armor()
	fire_burn = 0.0
	burn_t = 0.0
	poison_t = 0.0
	stats_changed.emit()

# ヒュドラの炎: 装甲を削る。#143: 装甲は回復させない(0で確実に大破するように永続ダメージ化)
func apply_fire(amount: float) -> void:
	if docking_locked:
		return   # #105
	run_armor = maxf(run_armor - amount, 0.0)
	stats_changed.emit()

# #143: 装甲の自然回復は廃止(炎ダメージが回復して大破しない不具合の解消)
func regen_fire(_delta: float) -> void:
	pass

# 漁獲を魚倉へ。入りきらなければ false。
func add_cargo(id: String, cap_needed: int = -1) -> bool:
	if docking_locked:
		return false   # #101: 大破/寄港確定後は積荷に入れない
	var need := cap_needed if cap_needed >= 0 else _cap_of(id)
	if free_hold() < need:
		notice.emit("魚倉が満杯です")
		return false
	cargo[id] = int(cargo.get(id, 0)) + 1
	stats_changed.emit()
	return true

func add_head(pirate_id: String) -> void:
	heads[pirate_id] = int(heads.get(pirate_id, 0)) + 1
	stats_changed.emit()

func add_relic(value: int) -> void:
	relics += value
	notice.emit("旧文明の遺産を発見(+%d相当)" % value)
	stats_changed.emit()

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func add_fame(amount: int) -> void:
	fame += amount
	fame_changed.emit(fame)
	# 名声で島を解放
	for isle in Database.islands:
		if fame >= isle.fame_req and not unlocked_islands.has(isle.id):
			unlocked_islands.append(isle.id)
			notice.emit("名声が轟いた: %s への航路が開けた" % isle.name)

# 魚市場で全積荷を売却
func sell_all() -> int:
	var earned := 0
	for id in cargo.keys():
		var qty := int(cargo[id])
		var unit := Database.sale_price(id, current_island)
		if unit <= 0:
			continue  # 主は対応島でないと売れない
		earned += unit * qty
		cargo.erase(id)
	if earned > 0:
		add_money(earned)
		Audio.play("sfx_sell")
		notice.emit("漁獲を売却: +%d" % earned)
	stats_changed.emit()
	return earned

# 酒場: 賞金(主)・海賊首・遺産の精算
func claim_bounties() -> int:
	var total := 0
	# 主の賞金(対応島でのみ受領)
	for lid in defeated_lords.duplicate():
		if Database.lords[lid].island == current_island:
			total += int(Database.lords[lid].bounty)
			defeated_lords.erase(lid)
			claimed_lords.append(lid)
	# 海賊の首
	for pid in heads.keys():
		total += int(Database.pirates[pid].bounty) * int(heads[pid])
	heads.clear()
	# 遺産
	total += relics
	relics = 0
	if total > 0:
		add_money(total)
		notice.emit("賞金・換金: +%d" % total)
	stats_changed.emit()
	return total

func equip_weapon(slot: int, wid: String) -> void:
	while weapons.size() < int(ship().slots):
		weapons.append("")
	if slot >= 0 and slot < int(ship().slots):
		weapons[slot] = wid
		stats_changed.emit()

func ship_trade_in() -> int:
	# #51再: 下取りは現在の船の定価の80%
	return int(float(ship().price) * 0.8)

func ship_buy_cost(new_id: String) -> int:
	# 差額。下取りが購入額を上回れば負(=返金)
	return int(Database.ships[new_id].price) - ship_trade_in()

func buy_ship(new_id: String) -> bool:
	var cost := ship_buy_cost(new_id)   # #51再: 負なら返金
	if cost > money:
		notice.emit("資金が足りません")
		return false
	add_money(-cost)   # costが負なら資金が増える(返金)
	ship_id = new_id
	# スロット数に武器配列を合わせる
	var slots := int(ship().slots)
	weapons.resize(slots)
	for i in slots:
		if weapons[i] == null or weapons[i] == "":
			weapons[i] = "gatling" if i == 0 else ""
	dock_reset()
	notice.emit("%s を購入" % ship().name)
	return true
