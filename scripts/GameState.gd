extends Node
## GameState — 可変のゲーム進行状態(資金・名声・船・装備・積荷・現在地)を保持するシングルトン。
## 航海中の食料/装甲/魚倉は run_* 値で扱い、帰港で精算する。

signal stats_changed
signal money_changed(amount: int)
signal fame_changed(amount: int)
signal notice(text: String)

var money: int = 200
var fame: int = 0

# --- 船団(#196) ---
# fleet[0]=旗艦, fleet[1..4]=2番艦〜5番艦。各要素:
#   {ship_id: String, weapons: Array[String], crew: Array, armor: float, damaged: bool}
# ship_id / weapons / crew / run_armor は「旗艦のもの」を指すプロキシとして残し、
# 既存コード(クルー効果・武器発射・積荷など)をそのまま動かす。
var fleet: Array = []
var ship_stock: Array[String] = []        # 購入済みで船団に未編入の船
const FLEET_MAX := 5
# 陣形1〜4に割り当てた陣形id(航海中に1〜4キーで切替)
var formations: Array[String] = ["line", "column", "vee", "inv_vee"]
var formation_slot: int = 0               # 選択中の陣形(0〜3)
var target_ship: int = 0                  # #196: 酒場での雇用・造船所での武器購入の対象艦

func _f0() -> Dictionary:
	if fleet.is_empty():
		fleet.append(new_ship_entry("raft", ["gatling"]))
	return fleet[0]

# 船団の1隻ぶんの初期データ
func new_ship_entry(sid: String, wpns: Array = []) -> Dictionary:
	var w: Array[String] = []
	var slots := int(Database.ships[sid].slots)
	for i in slots:
		w.append(str(wpns[i]) if i < wpns.size() else "")
	# #196再: 衝角(ram)と銛の効果(harpoon)は艦ごとに持つ
	return {"ship_id": sid, "weapons": w, "crew": [], "armor": float(Database.ships[sid].armor),
		"damaged": false, "ram": "none", "harpoon": "slip"}

var ship_id: String:
	get:
		return str(_f0().ship_id)
	set(v):
		_f0().ship_id = v

var weapons: Array[String]:
	get:
		return _f0().weapons
	set(v):
		_f0().weapons = v

var crew: Array:
	get:
		return _f0().crew
	set(v):
		_f0().crew = v

var ram_id: String:                        # #196再: 旗艦の衝角
	get:
		return str(_f0().get("ram", "none"))
	set(v):
		_f0()["ram"] = v

var harpoon_debuff: String:                # 銛の効果(#37)。#196再: 艦ごと
	get:
		return str(_f0().get("harpoon", "slip"))
	set(v):
		_f0()["harpoon"] = v

# --- クルー(#39): キャプテン含め5人まで=雇用は4人まで ---
# 各員: {name, job, hp, agi, sht, int_, vis}。船団の各艦がそれぞれ最大CREW_MAX名を乗せる。
const CREW_MAX := 4
var jobs := {
	"sailor":    {"name": "水夫",     "hire": 100,  "wage": 15, "growth": {"hp": 1, "agi": 1, "sht": 1, "int_": 1, "vis": 1}, "desc": "低賃金。すべての基本ジョブ。均等にパラメータが伸びる"},
	"veteran":   {"name": "熟練水夫", "hire": 700,  "wage": 40, "growth": {"hp": 3, "agi": 1, "sht": 1, "int_": 1, "vis": 1}, "req": ["hp", 8], "desc": "中賃金。水夫の上位互換。均等に伸びるが特に体力がよく伸びる"},
	"marine":    {"name": "水兵",     "hire": 700,  "wage": 40, "growth": {"hp": 1, "agi": 2, "sht": 3, "int_": 0, "vis": 1}, "req": ["sht", 8], "desc": "中賃金。攻撃時に確率でクリティカルが出る。敏捷と射撃力がよく伸びる"},
	"navigator": {"name": "航海士",   "hire": 700,  "wage": 40, "growth": {"hp": 0, "agi": 1, "sht": 0, "int_": 3, "vis": 3}, "req": ["vis", 8], "desc": "中賃金。ソナー範囲を強化。知力と視力がよく伸びる"},
	"cook":      {"name": "料理人",   "hire": 700,  "wage": 40, "growth": {"hp": 0, "agi": 1, "sht": 1, "int_": 2, "vis": 1}, "req": ["int_", 6], "desc": "中賃金。食料の減少速度が低下。体力の伸びは悪いが他は水夫より少し伸びる"},
	"firstmate": {"name": "副船長",   "hire": 1500, "wage": 80, "growth": {"hp": 2, "agi": 2, "sht": 2, "int_": 2, "vis": 2}, "req": ["total", 40], "desc": "高賃金。特殊能力はないが高パラメータ。均等によく伸びる(同時に乗せられるのは1名まで)"},
}
# #52再: 名前が尽きないよう50パターン用意
const CREW_NAMES := [
	"ジン", "ハル", "カイ", "レン", "ソラ", "ウミ", "リク", "ナギ", "イサナ", "タツ",
	"シオン", "マキ", "アオ", "ミナト", "シキ", "ホクト", "スイ", "カナタ", "ミオ", "トワ",
	"ハヤテ", "ユウ", "セナ", "リョウ", "アサヒ", "クロ", "シラベ", "ノゾミ", "イオ", "ツバサ",
	"コハク", "サザナミ", "シグレ", "オキ", "ヒビキ", "アカネ", "ミサキ", "タイガ", "ルカ", "ナルミ",
	"スミレ", "ハクア", "キリ", "ヨウ", "サギリ", "アユム", "シンジュ", "トウカ", "ミズキ", "ソウマ",
]

# #58: 副船長は同時に1名まで(雇用/ジョブチェンジ共通)
# #196: 副船長は「1隻につき」1名まで。既定は編成対象の艦を見る
func has_firstmate() -> bool:
	return has_firstmate_on(clampi(target_ship, 0, maxi(fleet.size() - 1, 0)))

func hire_crew(job_id: String) -> bool:
	var ti := clampi(target_ship, 0, maxi(fleet.size() - 1, 0))   # #196: 選択中の艦へ乗せる
	var tcrew: Array = fleet[ti].crew
	if tcrew.size() >= CREW_MAX:
		notice.emit("%s は満員です(1隻%d人まで)" % [fleet_label(ti), CREW_MAX])
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
	# #85再: 嵐越え(island>=3)以降の酒場はボーナス4倍+最低保証UPでより強力なクルー(水夫は据え置き)。#190: 月下の島の追加で嵐越えがindex3へ
	var bm := hire_bonus_mult(job_id)
	var high := current_island >= 3 and job_id != "sailor"
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
	tcrew.append(m)
	notice.emit("%s に %s(%s)を雇用" % [fleet_label(ti), m.name, j.name])
	stats_changed.emit()
	return true

# #85再: 嵐越えの島(island>=3)以降は契約金3倍・上乗せ4倍。ただし水夫は据え置き。#190: 月下の島(index2)は潮鳴りまでと同条件
func hire_cost(job_id: String) -> int:
	var mult := 3 if (current_island >= 3 and job_id != "sailor") else 1
	return int(jobs[job_id].hire) * mult

func hire_bonus_mult(job_id: String = "") -> int:
	return 4 if (current_island >= 3 and job_id != "sailor") else 1

# 使われていない名前を選ぶ(#52)。尽きたら「二代目〜」。
func _unique_crew_name() -> String:
	var used := []
	for e in fleet:            # #196: 船団全体で名前が重複しないように
		for c in e.crew:
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
	for e in fleet:            # #196: どの艦に乗っていても解雇できる
		e.crew.erase(m)
	notice.emit("%s を解雇した" % m.name)
	stats_changed.emit()

# #196: そのクルーが乗っている艦のindex(見つからなければ0)
func ship_index_of_crew(m: Dictionary) -> int:
	for i in fleet.size():
		if fleet[i].crew.has(m):
			return i
	return 0

func can_jobchange(m: Dictionary, job_id: String) -> bool:
	var j: Dictionary = jobs[job_id]
	if not j.has("req") or m.job == job_id:
		return false
	if job_id == "firstmate" and has_firstmate_on(ship_index_of_crew(m)):
		return false   # #58/#196: 副船長は1隻につき1名まで
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
	for m in all_crew():       # #196: 船団全員が成長
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
	for m in all_crew():       # #196: 船団全員に賃金
		total += float(jobs[m.job].wage) * mult
	return int(round(total))

# #196: 船団に乗っている全クルー
func all_crew() -> Array:
	var out: Array = []
	for e in fleet:
		for m in e.crew:
			out.append(m)
	return out

# 「旗艦」「2番艦」…の呼び名
func fleet_label(i: int) -> String:
	return "旗艦" if i == 0 else "%d番艦" % (i + 1)

func _crew_sum(stat: String) -> int:
	var s := 0
	for m in crew:
		s += int(m.get(stat, 0))
	return s

# --- クルー効果 ---
func food_drain_mult() -> float:   # 体力+料理人: 燃料(食料)減少を低下
	# #183: 体力10までは線形、10超はlog逓減(体力を伸ばしても燃料減少効果が頭打ちに近づく)
	var h := float(_crew_sum("hp"))
	var eff := h if h <= 10.0 else 10.0 + log(1.0 + (h - 10.0))
	var m := 1.0 / (1.0 + 0.02 * eff)
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

# #201: 自動ロックオン廃止に伴い、視力の効果は「ソナーの探知範囲」に変更。
# 視力が高いほど広範囲の敵・漁獲物・旧文明の遺産をソナーに表示できる。
func sonar_range_mult() -> float:   # 視力+航海士: ソナー範囲拡大
	# #201再: 向上幅を従来の半分に(視力3%→1.5%, 航海士+20%→+10%)
	var m := 1.0 + 0.015 * _crew_sum("vis")
	for c in crew:
		if c.job == "navigator":
			m *= 1.1
	return m

func lock_range_mult() -> float:   # #201: ロック距離は視力に依存しない
	return 1.0

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
var kills: Dictionary = {}                # #177: 討伐記録 "kind:id" -> 討伐数(999カンスト)
var guide_target: Dictionary = {}        # #60/#61: ソナーガイド {"kind":"island"|"lord","id":...}
var has_departed: bool = false            # #168: 一度でも出港したか(初回出港のみ燃料費無料)

# #168: 出港時に徴収する燃料費。船の定価の0.5%(小数点以下切り上げ)。粗末な漁船は5固定
func fuel_cost() -> int:
	if ship_id == "raft":
		return 5
	return int(ceil(float(ship().price) * 0.005))

# --- 航海中ランタイム値(出港でリセット) ---
var run_food: float = 0.0
var run_armor: float:      # #196: 旗艦の装甲。2番艦以降は fleet[i].armor
	get:
		return float(_f0().armor)
	set(v):
		_f0().armor = v
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
	fleet = [new_ship_entry("raft", ["gatling"])]   # #196
	ship_stock = []
	formations = ["line", "column", "vee", "inv_vee"]
	formation_slot = 0
	cargo = {}
	heads = {}
	relics = 0
	current_island = 0
	unlocked_islands = [0]
	visited_islands = [0]
	defeated_lords = []
	claimed_lords = []
	kills = {}
	guide_target = {}
	has_departed = false   # #168
	fire_burn = 0.0
	dock_reset()

# ---------------- オートセーブ(#93) ----------------
const SAVE_PATH := "user://save.json"
# #190: 月下の島を index2 に挿入したので、それ以前(world未設定)のセーブは島indexを1つ後ろへずらす
const WORLD_VERSION := 190

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# #209: 一度でもエンディングに到達したか(ボスラッシュ解放用)。
# 本編のセーブ(クリア直前の船団)を上書きしないよう別ファイルで持つ。
const CLEARED_PATH := "user://cleared.dat"
var boss_rush: bool = false        # ボスラッシュ中(燃料・魚倉の概念なし)

func has_cleared() -> bool:
	return FileAccess.file_exists(CLEARED_PATH)

func mark_cleared() -> void:
	var f := FileAccess.open(CLEARED_PATH, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()

func save_game() -> void:
	var data := {
		"money": money, "fame": fame,
		"fleet": fleet, "ship_stock": ship_stock,          # #196
		"formations": formations, "formation_slot": formation_slot,
		"ram_id": ram_id, "harpoon_debuff": harpoon_debuff,
		"cargo": cargo, "heads": heads, "relics": relics,
		"current_island": current_island,
		"unlocked_islands": unlocked_islands, "visited_islands": visited_islands,
		"defeated_lords": defeated_lords, "claimed_lords": claimed_lords,
		"kills": kills,
		"guide_target": guide_target, "has_departed": has_departed,
		"world": WORLD_VERSION,   # #190: 島構成のバージョン(島を挿入したらセーブの島indexを移行する)
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
	relics = int(data.get("relics", 0))
	current_island = int(data.get("current_island", 0))
	# #196: 船団。旧セーブ(ship_id/weapons/crew)は1隻の船団として読み込む
	fleet = []
	for e in data.get("fleet", []):
		var w: Array[String] = []
		for x in e.get("weapons", []):
			w.append(str(x))
		fleet.append({
			"ship_id": str(e.get("ship_id", "raft")), "weapons": w,
			"crew": _load_crew(e.get("crew", [])),
			"armor": float(e.get("armor", 0.0)), "damaged": bool(e.get("damaged", false)),
			# #204: 衝角と銛の効果は艦ごとの設定。復元漏れがあったので明示的に読み込む
			"ram": str(e.get("ram", "none")), "harpoon": str(e.get("harpoon", "slip")),
		})
	if fleet.is_empty():
		var w0: Array[String] = []
		for x in data.get("weapons", ["gatling"]):
			w0.append(str(x))
		fleet.append(new_ship_entry(str(data.get("ship_id", "raft"))))
		if not w0.is_empty():
			fleet[0].weapons = w0
		fleet[0].crew = _load_crew(data.get("crew", []))
		# 旧セーブは衝角・銛が全体設定だったので旗艦へ引き継ぐ
		fleet[0]["ram"] = str(data.get("ram_id", "none"))
		fleet[0]["harpoon"] = str(data.get("harpoon_debuff", "slip"))
	ship_stock.assign(_to_str_array(data.get("ship_stock", [])))
	formations.assign(_to_str_array(data.get("formations", ["line", "column", "vee", "inv_vee"])))
	formation_slot = int(data.get("formation_slot", 0))
	unlocked_islands.assign(_to_int_array(data.get("unlocked_islands", [0])))
	visited_islands.assign(_to_int_array(data.get("visited_islands", [0])))
	defeated_lords.assign(data.get("defeated_lords", []))
	claimed_lords.assign(data.get("claimed_lords", []))
	guide_target = data.get("guide_target", {})
	has_departed = bool(data.get("has_departed", true))   # #168: 既存セーブは出港済み扱い
	# #190: 4島時代のセーブは 嵐越え=2/果て=3 だったので、月下の島の挿入ぶんだけ後ろへ寄せる
	if int(data.get("world", 0)) < 190:
		current_island = _shift_island(current_island)
		var ui: Array[int] = []
		for i in unlocked_islands:
			ui.append(_shift_island(i))
		unlocked_islands.assign(ui)
		var vi: Array[int] = []
		for i in visited_islands:
			vi.append(_shift_island(i))
		visited_islands.assign(vi)
		if str(guide_target.get("kind", "")) == "island":
			guide_target["id"] = _shift_island(int(guide_target.get("id", 0)))
		# 挿入された月下の島は旧セーブに存在しないので、名声が足りていればこの場で解放する
		for isle in Database.islands:
			if fame >= int(isle.fame_req) and not unlocked_islands.has(int(isle.id)):
				unlocked_islands.append(int(isle.id))
		unlocked_islands.sort()
	# 辞書の数値はJSONでfloat化するのでintへ戻す
	cargo = _to_int_dict(data.get("cargo", {}))
	heads = _to_int_dict(data.get("heads", {}))
	kills = _to_int_dict(data.get("kills", {}))   # #177: 討伐記録
	dock_reset()
	stats_changed.emit()
	return true

# #190: 旧セーブの島index(0始まり/1潮鳴り/2嵐越え/3果て)を新しい5島構成へ移す
func _shift_island(i: int) -> int:
	return i + 1 if i >= 2 else i

# #196: セーブのクルー配列を復元
func _load_crew(arr) -> Array:
	var out: Array = []
	for c in arr:
		out.append({
			"name": str(c.get("name", "?")), "job": str(c.get("job", "sailor")),
			"hp": int(c.get("hp", 1)), "agi": int(c.get("agi", 1)),
			"sht": int(c.get("sht", 1)), "int_": int(c.get("int_", 1)),
			"vis": int(c.get("vis", 1)), "changed": bool(c.get("changed", false)),
		})
	return out

func _to_str_array(a) -> Array:
	var out := []
	for v in a:
		out.append(str(v))
	return out

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

# #196再: 魚倉のキャパシティは船団に組み込んでいる全船の合計
func max_hold() -> int:
	var t := 0
	for e in fleet:
		t += int(Database.ships[str(e.ship_id)].hold)
	return t

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
	_restore_fleet_armor()
	stats_changed.emit()

# #196: 船団全艦の装甲を満タンに戻す
func _restore_fleet_armor() -> void:
	for e in fleet:
		e["armor"] = float(Database.ships[str(e.ship_id)].armor)

func set_sail() -> void:
	at_sea = true
	docking_locked = false   # #105: 出港で解除
	run_food = max_food()
	_restore_fleet_armor()
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
	if boss_rush:
		return true   # #209: ボスラッシュは魚倉の概念なし
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

# #177: 討伐記録。戦闘モブ・海賊の討伐数を種別+idで加算(999カンスト)
func record_kill(kind: String, id: String) -> void:
	if kind != "mob" and kind != "pirate":
		return
	var key := "%s:%s" % [kind, id]
	kills[key] = mini(int(kills.get(key, 0)) + 1, 999)

# #177: 討伐数の取得(未討伐は0)
func kill_count(kind: String, id: String) -> int:
	return int(kills.get("%s:%s" % [kind, id], 0))

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

# #196: 指定した艦のスロットへ装備
func equip_weapon_on(idx: int, slot: int, wid: String) -> void:
	if idx < 0 or idx >= fleet.size():
		return
	var e: Dictionary = fleet[idx]
	var slots := int(Database.ships[str(e.ship_id)].slots)
	var w: Array = e.weapons
	while w.size() < slots:
		w.append("")
	if slot >= 0 and slot < slots:
		w[slot] = wid
		stats_changed.emit()

func equip_weapon(slot: int, wid: String) -> void:
	while weapons.size() < int(ship().slots):
		weapons.append("")
	if slot >= 0 and slot < int(ship().slots):
		weapons[slot] = wid
		stats_changed.emit()

func ship_trade_in() -> int:
	# #51再: 下取りは現在の船の定価の80%
	return int(float(ship().price) * 0.8)

# #196: 船は乗り換えでなく購入=ストックへ追加になったので、下取り無しの定価
func ship_buy_cost(new_id: String) -> int:
	return int(Database.ships[new_id].price)

func buy_ship(new_id: String) -> bool:
	var cost := ship_buy_cost(new_id)
	if cost > money:
		notice.emit("資金が足りません")
		return false
	add_money(-cost)
	ship_stock.append(new_id)   # #196: 購入した船はストックされ、編成メニューで船団へ組み込む
	notice.emit("%s を購入(ストックへ)" % Database.ships[new_id].name)
	stats_changed.emit()
	return true

# ---------------- 船団(#196) ----------------
# 島が進むごとに組める隻数が増える(潮鳴り=2隻 … 果て=5隻)
func max_fleet() -> int:
	return clampi(current_island + 1, 1, FLEET_MAX)

# #196再: 始まりの島でも編成メニューを使える(ここで買ってストックした船を扱えるように)
func fleet_enabled() -> bool:
	return true

func ship_def_of(i: int) -> Dictionary:
	return Database.ships[str(fleet[i].ship_id)]

# 2番艦以降は副船長が1名乗っていないと出港できない
func has_firstmate_on(idx: int) -> bool:
	for c in fleet[idx].crew:
		if c.job == "firstmate":
			return true
	return false

func can_sail(idx: int) -> bool:
	return idx == 0 or has_firstmate_on(idx)

# 出港できる艦(旗艦+副船長を乗せた僚艦)のindex一覧
func sailing_ships() -> Array:
	var out: Array = []
	for i in fleet.size():
		if can_sail(i):
			out.append(i)
	return out

# 船団の移動速度は最も遅い船に合わせる
func fleet_speed() -> float:
	var sp := float(ship().speed)
	for i in sailing_ships():
		sp = minf(sp, float(ship_def_of(i).speed))
	return sp

func fleet_add(stock_idx: int) -> bool:
	if stock_idx < 0 or stock_idx >= ship_stock.size():
		return false
	if fleet.size() >= max_fleet():
		notice.emit("この島で組める船団は%d隻までです" % max_fleet())
		return false
	var sid: String = ship_stock[stock_idx]
	ship_stock.remove_at(stock_idx)
	fleet.append(new_ship_entry(sid))
	notice.emit("%s を船団に加えた" % Database.ships[sid].name)
	stats_changed.emit()
	return true

# #196再: ストックの船と、すでに船団に組み込んでいる船を交換する
# 乗員・武器・衝角・銛の設定はその船に紐づくので、船体だけを入れ替える
func fleet_exchange(fleet_idx: int, stock_idx: int) -> bool:
	if fleet_idx < 0 or fleet_idx >= fleet.size():
		return false
	if stock_idx < 0 or stock_idx >= ship_stock.size():
		return false
	var e: Dictionary = fleet[fleet_idx]
	var new_sid: String = ship_stock[stock_idx]
	var old_sid: String = str(e.ship_id)
	var new_slots := int(Database.ships[new_sid].slots)
	ship_stock[stock_idx] = old_sid
	e.ship_id = new_sid
	e.armor = float(Database.ships[new_sid].armor)
	# 武器スロット数を新しい船に合わせる(あふれた武器は外れる)
	var w: Array = e.weapons
	while w.size() < new_slots:
		w.append("")
	while w.size() > new_slots:
		w.pop_back()
	notice.emit("%s を %s と交換した" % [Database.ships[old_sid].name, Database.ships[new_sid].name])
	stats_changed.emit()
	return true

func fleet_remove(idx: int) -> bool:
	if idx <= 0 or idx >= fleet.size():
		return false   # 旗艦は外せない
	var e: Dictionary = fleet[idx]
	if not e.crew.is_empty():
		notice.emit("先にクルーを降ろしてください")
		return false
	ship_stock.append(str(e.ship_id))
	fleet.remove_at(idx)
	notice.emit("%s を船団から外した(ストックへ)" % Database.ships[str(e.ship_id)].name)
	stats_changed.emit()
	return true

# 旗艦と僚艦、僚艦同士の入れ替え
func fleet_swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= fleet.size() or b >= fleet.size():
		return
	var t = fleet[a]
	fleet[a] = fleet[b]
	fleet[b] = t
	notice.emit("配置を入れ替えた")
	stats_changed.emit()

func sell_stock(stock_idx: int) -> void:
	if stock_idx < 0 or stock_idx >= ship_stock.size():
		return
	var sid: String = ship_stock[stock_idx]
	var gain := int(float(Database.ships[sid].price) * 0.8)   # 定価の80%で売却
	ship_stock.remove_at(stock_idx)
	add_money(gain)
	notice.emit("%s を売却(+%d)" % [Database.ships[sid].name, gain])
	stats_changed.emit()

# クルーを船から船へ移す
func move_crew(from_idx: int, member: Dictionary, to_idx: int) -> bool:
	if from_idx == to_idx or to_idx < 0 or to_idx >= fleet.size():
		return false
	if fleet[to_idx].crew.size() >= CREW_MAX:
		notice.emit("その船は満員です(%d名まで)" % CREW_MAX)
		return false
	if str(member.job) == "firstmate" and has_firstmate_on(to_idx):
		notice.emit("副船長は1隻に1名までです")
		return false
	fleet[from_idx].crew.erase(member)
	fleet[to_idx].crew.append(member)
	stats_changed.emit()
	return true

# #196再3: 満員の船へ乗り換えるとき、相手のクルーと入れ替える
func swap_crew(from_idx: int, a: Dictionary, to_idx: int, b: Dictionary) -> bool:
	if from_idx == to_idx or from_idx < 0 or to_idx < 0:
		return false
	if from_idx >= fleet.size() or to_idx >= fleet.size():
		return false
	var ca: Array = fleet[from_idx].crew
	var cb: Array = fleet[to_idx].crew
	if not ca.has(a) or not cb.has(b):
		return false
	ca.erase(a)
	cb.erase(b)
	ca.append(b)
	cb.append(a)
	notice.emit("%s と %s を交代した" % [a.name, b.name])
	stats_changed.emit()
	return true

# 武器を船同士で交換(スロット単位)
func swap_weapon(a_idx: int, a_slot: int, b_idx: int, b_slot: int) -> void:
	var wa: Array = fleet[a_idx].weapons
	var wb: Array = fleet[b_idx].weapons
	if a_slot >= wa.size() or b_slot >= wb.size():
		return
	var t: String = wa[a_slot]
	wa[a_slot] = wb[b_slot]
	wb[b_slot] = t
	stats_changed.emit()

# #196: 離脱した船の修理費(次回出港時に徴収)。定価の4%
func fleet_repair_cost() -> int:
	var total := 0
	for e in fleet:
		if bool(e.get("damaged", false)):
			total += int(float(Database.ships[str(e.ship_id)].price) * 0.04)
	return total

func clear_fleet_damage() -> void:
	for e in fleet:
		e["damaged"] = false

# 僚艦の離脱時: 旗艦の大破より低い確率でクルーを失う
func detach_lose_crew(idx: int) -> String:
	var c: Array = fleet[idx].crew
	if c.is_empty() or randf() >= 0.35:   # #196再7: 22%→35%(旗艦の大破50%よりは低い)
		return ""
	var m: Dictionary = c[randi() % c.size()]
	c.erase(m)
	stats_changed.emit()
	return "%s(%s)" % [m.name, jobs[m.job].name]

# 指定の船のクルー合計値(僚艦の攻撃力などに使う)
func crew_sum_of(idx: int, stat: String) -> int:
	var t := 0
	for m in fleet[idx].crew:
		t += int(m.get(stat, 0))
	return t

func attack_mult_of(idx: int) -> float:
	return 1.0 + 0.02 * crew_sum_of(idx, "sht")
