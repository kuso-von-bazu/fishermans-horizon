extends Node
## GameState — 可変のゲーム進行状態(資金・名声・船・装備・積荷・現在地)を保持するシングルトン。
## 航海中の食料/装甲/魚倉は run_* 値で扱い、帰港で精算する。

signal stats_changed
signal money_changed(amount: int)
signal fame_changed(amount: int)
signal notice(text: String)
# #265再3: 実績を達成した瞬間にバッヂ絵を大きく見せるための通知(HUDが受ける)
signal achievement_unlocked(aid: String)

var money: int = 200
var fame: int = 0

# --- 船団(#196) ---
# fleet[0]=旗艦, fleet[1..4]=2番艦〜5番艦。各要素:
#   {ship_id: String, weapons: Array[String], crew: Array, armor: float, damaged: bool}
# ship_id / weapons / crew / run_armor は「旗艦のもの」を指すプロキシとして残し、
# 既存コード(クルー効果・武器発射・積荷など)をそのまま動かす。
var fleet: Array = []
var ship_stock: Array[String] = []        # 購入済みで船団に未編入の船
# #240: 船から降ろしたクルーの待機場所。ここにいる間は賃金も成長も発生しない
var crew_stock: Array = []
# #241: 島ごとの出港回数(ワンポイントヒントの出し分けに使う)と、
# 「名声22以上になった後の初回」ヒントを出したかどうか
var departures: Dictionary = {}
var hint_fame22_used: bool = false
# #241再2: 実際に表示したヒントの履歴(新しいものが先頭)。早見表から見返せる
var hint_log: Array = []
const HINT_LOG_MAX := 40
const FLEET_MAX := 5
# 陣形1〜4に割り当てた陣形id(航海中に1〜4キーで切替)
var formations: Array[String] = ["line", "column", "vee", "inv_vee"]
var formation_slot: int = 0               # 選択中の陣形(0〜3)
var target_ship: int = 0                  # #196: 酒場での雇用・造船所での武器購入の対象艦

# #224再2: 陣形ごとの常時効果(パッシブ)。倍率なので 1.0 が「効果なし」。
# 陣形は船団の仕組みなので、旗艦1隻のときは適用しない(切替もできないため)。
const FORMATION_PASSIVE := {
	"line":    {"reload": 0.90},            # 単横陣: 全艦のリロード時間 -10%
	"column":  {"speed": 1.05},             # 単縦陣: 前進最高速 +5%
	"vee":     {"ram": 1.15},               # 鋒矢陣: 衝角・体当たりダメージ +15%
	"inv_vee": {"shot_dmg": 1.10},          # 鶴翼陣: 遠隔攻撃ダメージ +10%
	"echelon": {"shot_speed": 1.10},        # 斜線陣: 弾速 +10%
	"ring":    {"flag_dmg_taken": 0.90},    # 輪形陣: 旗艦の被ダメージ -10%
}
const FORMATION_PASSIVE_TEXT := {
	"line": "全艦のリロード時間 -10%",
	"column": "前進最高速 +5%",
	"vee": "衝角・体当たりダメージ +15%",
	"inv_vee": "遠隔攻撃ダメージ +10%",
	"echelon": "弾速 +10%",
	"ring": "旗艦の被ダメージ -10%",
}

# #224: 陣形ごとのスキル
# #224再2: 鋒矢/鶴翼/斜線/輪形に固有スキルを実装(単横・単縦は据え置き)
const FORMATION_SKILLS := {
	# #224再: 単横陣と単縦陣のスキルを入れ替え(単横陣=一斉射撃20秒 / 単縦陣=突撃15秒)
	"line":    {"name": "一斉射撃", "kind": "volley", "cd": 20.0,
		"desc": "全艦が弾倉の半分を3倍の速さで撃ち込む"},
	"column":  {"name": "突撃",     "kind": "charge", "cd": 15.0,
		"desc": "全艦が最高速の3倍で直進し、敵を貫いて体当たりする"},
	"vee":     {"name": "楔の突撃", "kind": "wedge",  "cd": 17.0,
		"desc": "突撃中、旗艦の衝角ダメージ1.5倍。命中した敵を後方へ押し込む"},
	"inv_vee": {"name": "包囲射撃", "kind": "encircle", "cd": 25.0,
		"desc": "ロック中の敵へ各艦が0.5秒間隔で時間差斉射。その間、対象の回避を無効化"},
	"echelon": {"name": "速射態勢", "kind": "rapid",  "cd": 22.0,
		"desc": "5秒間、全艦の弾倉が減らない(リロードが発生しない)"},
	"ring":    {"name": "防御弾幕", "kind": "barrier", "cd": 25.0,
		"desc": "3秒間、輪の内側に入った敵弾を迎撃して消す"},
}

func formation_id() -> String:
	return str(formations[clampi(formation_slot, 0, formations.size() - 1)])

# 現在の陣形のパッシブ倍率。船団が2隻以上のときだけ効く。
func formation_passive(key: String) -> float:
	if fleet.size() <= 1:
		return 1.0
	var t: Dictionary = FORMATION_PASSIVE.get(formation_id(), {})
	return float(t.get(key, 1.0))

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
	var high := Database.tier_of(current_island) >= 3 and job_id != "sailor"   # #239
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

# #267: 漂流者の救出。空き枠があればクルーとして加わり、無ければ謝礼を受け取る。
#   ジョブはその海域の酒場で雇える顔ぶれから選ぶが、
#   水夫(弱すぎる)と副船長(1隻1名の制約)は除く。
const CASTAWAY_JOBS := ["veteran", "marine", "navigator", "cook"]

func rescue_castaway() -> String:
	var job_id: String = CASTAWAY_JOBS[randi() % CASTAWAY_JOBS.size()]
	var j: Dictionary = jobs[job_id]
	# 空きのある艦を探す(旗艦から順に)
	var slot := -1
	for i in sailing_ships():
		if fleet[i].crew.size() < CREW_MAX:
			slot = i
			break
	if slot < 0:
		# 枠が無ければ謝礼(その海域で雇う額と同額)
		var reward := hire_cost(job_id)
		add_money(reward)
		var msg := "漂流者を救出! 乗る枠が無く、謝礼 %d を受け取った" % reward
		notice.emit(msg)
		return msg
	# 酒場と同じ手順でクルーを作る(契約金は取らない)
	var bm := hire_bonus_mult(job_id)
	var high: bool = Database.tier_of(current_island) >= 3
	var base: int = 5 if high else 3
	var m := {
		"name": _unique_crew_name(),
		"job": job_id,
		"hp": base + randi_range(0, 2 * bm), "agi": base + randi_range(0, 2 * bm),
		"sht": base + randi_range(0, 2 * bm), "int_": base + randi_range(0, 2 * bm),
		"vis": base + randi_range(0, 2 * bm),
	}
	if j.has("req"):
		var req: Array = j.req
		m[req[0]] = int(req[1]) + randi_range(0, 4 * bm)
	(fleet[slot].crew as Array).append(m)
	stats_changed.emit()
	var msg2 := "漂流者を救出! %s(%s)が %s に乗り込んだ" % [m.name, j.name, fleet_label(slot)]
	notice.emit(msg2)
	return msg2

# #267: 漂流貨物。全海域の漁獲物からランダムに1種、5〜10匹ぶんを積む。
#   魚倉の空きを超える分は積めない(空き<1匹ぶんなら1匹も積めないことがある)。
func collect_drifting_cargo() -> String:
	var ids: Array = []
	for fid in Database.fish:
		ids.append(str(fid))
	if ids.is_empty():
		return ""
	var id: String = ids[randi() % ids.size()]
	var want := randi_range(5, 10)
	var got := 0
	for k in want:
		if not add_cargo(id):
			break   # 魚倉に入らなくなったら打ち切り
		got += 1
	var nm: String = str(Database.fish[id].name)
	var msg3 := ""
	if got == 0:
		msg3 = "漂流貨物を回収したが、魚倉に空きが無かった(%s)" % nm
	elif got < want:
		msg3 = "漂流貨物から %s を%d匹回収(魚倉が満杯で%d匹は積めなかった)" % [nm, got, want - got]
	else:
		msg3 = "漂流貨物から %s を%d匹回収!" % [nm, got]
	notice.emit(msg3)
	return msg3

# #85再: 嵐越えの島(island>=3)以降は契約金3倍・上乗せ4倍。ただし水夫は据え置き。#190: 月下の島(index2)は潮鳴りまでと同条件
func hire_cost(job_id: String) -> int:
	var mult := 3 if (Database.tier_of(current_island) >= 3 and job_id != "sailor") else 1   # #239
	return int(jobs[job_id].hire) * mult

func hire_bonus_mult(job_id: String = "") -> int:
	return 4 if (Database.tier_of(current_island) >= 3 and job_id != "sailor") else 1   # #239

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
				# #153再2: 30超はさらに上がりにくく(従来の逓減を2乗)
				# #153再3: 2乗すると49で0.0025まで落ち、49→50へ実質成長しなくなるため
				# 伸びやすさの下限を0.03とする(#153再4)。必ず上限50へ到達できる
				falloff = maxf(pow(clampf(1.0 - float(cur - 30) / float(STAT_MAX - 30), 0.0, 1.0), 2.0), 0.03)
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
	# #183: 体力は一定までは線形、それ以降はlogで逓減(伸ばしても頭打ちに近づく)
	# #258再3: 参照を旗艦から船団全体へ広げ、あわせて逓減を緩めた。
	#   旗艦のみ(合計20〜28程度)から船団全体(60〜140程度)へ変わるので、
	#   従来の式のままだと増えたぶんがほとんど効かない(20→100で2.6ptしか動かない)。
	#   線形の範囲を10→20へ広げ、log側も8倍に伸ばして効き続けるようにする。
	# #258再4: 逓減の効き方を少しだけ強くする(線形20→18、log側8.0→7.0)。
	#   体力の合計が多い船団ほど削れ幅が大きくなる(合計20で-0.3pt、100で-2.2pt、
	#   280で-2.4pt)。低体力の序盤はほぼ据え置きで、伸ばしたときの頭打ちだけが早まる。
	var h := 0.0
	for i in sailing_ships():
		for c in fleet[i].crew:
			h += float(c.get("hp", 0))
	var eff := h if h <= 18.0 else 18.0 + 7.0 * log(1.0 + (h - 18.0) / 7.0)
	var m := 1.0 / (1.0 + 0.02 * eff)
	# #258再2: 料理人は船団全体で数える。1人目0.85、2人目以降は効果が逓減する
	#   (0.85 → 0.90 → 0.94 …)。多数積んでも頭打ちになるようにしている。
	var cooks := 0
	for i in sailing_ships():
		for c in fleet[i].crew:
			if c.job == "cook":
				cooks += 1
	for k in cooks:
		m *= 1.0 - 0.15 * pow(0.65, float(k))
	return m

func damage_cut() -> float:        # 敏捷: 被ダメカット(最大40%)
	return minf(0.015 * _crew_sum("agi"), 0.40)

func attack_mult() -> float:       # 射撃力: 攻撃威力バフ
	return 1.0 + 0.02 * _crew_sum("sht")

func crit_chance() -> float:       # 水兵: クリティカル(#82/#83: 低め+人数で逓減)
	return crit_chance_of(0)

# #83再: 旗艦だけでなく各僚艦も、その艦に乗っている水兵で同じ確率を計算する。
func crit_chance_of(idx: int) -> float:
	var n := 0
	if idx < 0 or idx >= fleet.size():
		return 0.0
	for m in fleet[idx].crew:
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
	# #201再2: 視力1ポイントあたり1%(航海士の補正+10%は据え置き)
	var m := 1.0 + 0.01 * _crew_sum("vis")
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
	run_armor = maxf(run_armor - amount * (1.0 - damage_cut()) * formation_passive("flag_dmg_taken") * badge_mult("flag_dmg_taken") * badge_mult("fleet_dmg_taken"), 0.0)   # #224再2: 輪形陣
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
# #265: 実績。achieved=達成した実績id / badge_id=選択中のバッヂ / relic_count=遺産の入手個数
#   caught_fish=これまでに漁獲した魚のid(全種類の達成判定に使う)
var achieved: Dictionary = {}
var badge_id: String = ""
var relic_count: int = 0
var caught_fish: Dictionary = {}
var charge_all_tungsten: bool = false   # 突撃!の達成条件(発動時に判定して立てる)


var current_island: int = 0
var unlocked_islands: Array[int] = [0]   # 名声で入港可能になった島
var visited_islands: Array[int] = [0]    # 実際に寄港して到達した島(ファストトラベル可・Issue #19)
var defeated_lords: Array[String] = []   # 討伐済みで賞金未受領
var claimed_lords: Array[String] = []    # 賞金受領済み
# #265再12: これまでに一度でも装備した武器のID。実績「ウェポンマスター」は
#   「同時に全種類」ではなく「全種類を装備したことがある」で達成するため、
#   船団の現在の装備ではなくこちらを見る(セーブに持ち越す)。
var weapons_ever: Dictionary = {}
var kills: Dictionary = {}                # #177: 討伐記録 "kind:id" -> 討伐数(999カンスト)
var guide_target: Dictionary = {}        # #60/#61: ソナーガイド {"kind":"island"|"lord","id":...}
var has_departed: bool = false            # #168: 一度でも出港したか(初回出港のみ燃料費無料)
var active_weather: String = ""           # #232: 現在海域の天候効果。見た目とは別に倍率計算で参照

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
	crew_stock = []
	departures = {}
	hint_fame22_used = false
	hint_log = []
	formations = ["line", "column", "vee", "inv_vee"]
	formation_slot = 0
	cargo = {}
	heads = {}
	relics = 0
	relic_count = 0
	caught_fish = {}
	charge_all_tungsten = false
	current_island = 0
	unlocked_islands = [0]
	visited_islands = [0]
	defeated_lords = []
	claimed_lords = []
	kills = {}
	guide_target = {}
	has_departed = false   # #168
	active_weather = ""
	fire_burn = 0.0
	dock_reset()

# ---------------- オートセーブ(#93) ----------------
# ---------------------------------------------------------------------------
# #278(提案4): 画面シェイクの設定。打撃感を既定で味わえるよう既定はONで、
# 酔う場合は歯車アイコンの設定メニューから切れる。音量と同じくファイルへ即保存する。
# ---------------------------------------------------------------------------
const DISPLAY_SETTINGS_PATH := "user://display_settings.cfg"
var screen_shake: bool = true
var pad_mode: bool = false   # #293: ゲーム進行とは別に保存する操作方式

func load_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DISPLAY_SETTINGS_PATH) == OK:
		screen_shake = bool(cfg.get_value("display", "screen_shake", true))
		pad_mode = bool(cfg.get_value("input", "pad_mode", false))

func set_screen_shake(on: bool) -> void:
	screen_shake = on
	_save_display_settings()

func set_pad_mode(on: bool) -> void:
	pad_mode = on
	_save_display_settings()

func _save_display_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(DISPLAY_SETTINGS_PATH)
	cfg.set_value("display", "screen_shake", screen_shake)
	cfg.set_value("input", "pad_mode", pad_mode)
	cfg.save(DISPLAY_SETTINGS_PATH)

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

# #209再2: ボスラッシュを制覇したか(タイトルの王冠表示用)。本編クリアとは別に持つ。
const BR_CLEARED_PATH := "user://boss_rush_cleared.dat"

func has_cleared_boss_rush() -> bool:
	return FileAccess.file_exists(BR_CLEARED_PATH)

func mark_boss_rush_cleared() -> void:
	var f := FileAccess.open(BR_CLEARED_PATH, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()

# #265再5: ボスラッシュを1度でもプレイしたか(実績「真の海の王者」の表示解禁用)。
const BR_PLAYED_PATH := "user://boss_rush_played.dat"

func has_played_boss_rush() -> bool:
	return FileAccess.file_exists(BR_PLAYED_PATH)

func mark_boss_rush_played() -> void:
	var f := FileAccess.open(BR_PLAYED_PATH, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()

# #209再2: ボスを1体倒すごとに船団の全艦が最大装甲の5%回復する
func heal_fleet_percent(pct: float) -> void:
	for i in fleet.size():
		var mx := float(max_armor_of(i))
		var cur := float(fleet[i].get("armor", mx))
		fleet[i]["armor"] = minf(cur + mx * pct, mx)
	stats_changed.emit()

func save_game() -> void:
	var data := {
		"money": money, "fame": fame,
		"fleet": fleet, "ship_stock": ship_stock, "crew_stock": crew_stock,          # #196/#240
		"departures": departures, "hint_fame22_used": hint_fame22_used, "hint_log": hint_log,   # #241
		"formations": formations, "formation_slot": formation_slot,
		"ram_id": ram_id, "harpoon_debuff": harpoon_debuff,
		"cargo": cargo, "heads": heads, "relics": relics,
		"current_island": current_island,
		"unlocked_islands": unlocked_islands, "visited_islands": visited_islands,
		"defeated_lords": defeated_lords, "claimed_lords": claimed_lords,
		"kills": kills, "relic_count": relic_count, "caught_fish": caught_fish,   # #265
		"weapons_ever": weapons_ever,   # #265再12
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
	crew_stock = data.get("crew_stock", [])   # #240
	departures = _to_int_key_dict(data.get("departures", {}))   # #241
	hint_fame22_used = bool(data.get("hint_fame22_used", false))
	hint_log = data.get("hint_log", [])   # #241再2
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
	relic_count = int(data.get("relic_count", 0))   # #265
	weapons_ever = data.get("weapons_ever", {})   # #265再12
	caught_fish = data.get("caught_fish", {})
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

# #241: JSONに保存するとキーが文字列になるので、キーもintへ戻す
# (島indexで引くため。文字列のままだと出港回数が毎回0に戻ってしまう)
func _to_int_key_dict(d) -> Dictionary:
	var out := {}
	for k in d:
		out[int(str(k))] = int(d[k])
	return out

func ship() -> Dictionary:
	return Database.ships[ship_id]

# #258再2: 燃料タンクは船団の平均。2〜5番艦の燃料値も残量に効く。
#   (魚倉は合計だが、燃料は「積める量の平均」なので合計にはしない)
func max_food() -> float:
	var total := float(ship().food)
	var n := 1
	for i in sailing_ships():
		if i == 0:
			continue   # 旗艦は上で数えている
		total += float(ship_def_of(i).food)
		n += 1
	return total / float(n)

# #196再: 魚倉のキャパシティは船団に組み込んでいる全船の合計
func max_hold() -> int:
	var t := 0
	for e in fleet:
		t += int(Database.ships[str(e.ship_id)].hold)
	return t

func max_armor() -> float:
	return float(ship().armor)

# #209再2: 船団の任意の艦の最大装甲(僚艦も同じく船の定義値)
func max_armor_of(i: int) -> float:
	if i < 0 or i >= fleet.size():
		return 0.0
	return float(Database.ships[str(fleet[i].ship_id)].armor)

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

# #237再4: 敵が攻撃してよい状態か。
#   従来 docking_locked は「寄港が確定してから完了するまで」しか true でなく、
#   港にいる間は false に戻っていた。そのため居残った敵が港で攻撃を続け、
#   ダメージは入らないのに被弾音だけが鳴っていた(カーラボスで報告)。
#   いまは出港(set_sail)まで解除しないので、港にいる間は常に false を返す。
func combat_active() -> bool:
	return not docking_locked

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
	if Database.fish.has(id):
		caught_fish[id] = true   # #265: 実績「渭川漁父」用(魚だけ数える)
		check_achievements()
	stats_changed.emit()
	return true

func add_head(pirate_id: String) -> void:
	heads[pirate_id] = int(heads.get(pirate_id, 0)) + 1
	stats_changed.emit()

# #177: 討伐記録。戦闘モブ・海賊の討伐数を種別+idで加算(999カンスト)
# #265: 実績の達成判定・バッヂ効果・保存
func is_achieved(aid: String) -> bool:
	return bool(achieved.get(aid, false))

# 実績の進捗 [現在値, 必要値]
func achievement_progress(a: Dictionary) -> Array:
	match str(a.get("check", "")):
		"mob":
			return [kill_count("mob", str(a.target)), int(a.need)]
		"lord":
			return [1 if (defeated_lords.has(str(a.target)) or claimed_lords.has(str(a.target))) else 0, 1]
		"pirate_all":
			return [kill_count("pirate", "raider") + kill_count("pirate", "corsair") + kill_count("pirate", "dread"), int(a.need)]
		"relic":
			return [relic_count, int(a.need)]
		"fish":
			return [caught_fish.size(), Database.fish.size()]
	return [1 if is_achieved(str(a.id)) else 0, 1]

# その敵を1体でも倒したか(名前を出してよいか)。(3)〜(7)は最初から名前を出す
func achievement_revealed(a: Dictionary) -> bool:
	if is_achieved(str(a.id)):
		return true
	match str(a.get("check", "")):
		"mob":
			return kill_count("mob", str(a.target)) > 0
		"lord":
			return defeated_lords.has(str(a.target)) or claimed_lords.has(str(a.target))
		"pirate_all":
			return kill_count("pirate", "raider") + kill_count("pirate", "corsair") + kill_count("pirate", "dread") > 0
		"boss_rush":
			return has_played_boss_rush()
	return true

func check_achievements() -> Array:
	var newly: Array = []
	for a in Database.achievements:
		var aid := str(a.id)
		if is_achieved(aid):
			continue
		if _achievement_met(a):
			achieved[aid] = true
			newly.append(aid)
			if not boss_rush:
				notice.emit("実績達成: %s" % str(a.name))   # #209: ボスラッシュ中は出さない
				achievement_unlocked.emit(aid)              # #265再3: バッヂ絵の演出
	if not newly.is_empty():
		_save_achievements()   # レヴィアタン討伐で即エンディングでも残るよう即保存
	return newly

func _achievement_met(a: Dictionary) -> bool:
	match str(a.get("check", "")):
		"mob":
			return kill_count("mob", str(a.target)) >= int(a.need)
		"lord":
			return defeated_lords.has(str(a.target)) or claimed_lords.has(str(a.target))
		"pirate_all":
			var p := kill_count("pirate", "raider") + kill_count("pirate", "corsair") + kill_count("pirate", "dread")
			return p >= int(a.need) and kill_count("pirate", "king") >= 2   # #265再: 3隻→2隻
		"relic":
			return relic_count >= int(a.need)
		"fish":
			return caught_fish.size() >= Database.fish.size()
		"wealth":
			if str(a.id) == "fame_max":
				return fame >= FAME_MAX
			return money >= 1000000
		"crew":
			return _crew_achievement(str(a.id))
		"fleet":
			return _fleet_achievement(str(a.id))
		"boss_rush":
			return has_cleared_boss_rush()
		"all":
			for other in Database.achievements:
				if str(other.id) != str(a.id) and not is_achieved(str(other.id)):
					return false
			return true
	return false

# パラメータのカンストは既存の STAT_MAX(=50)を使う
func _crew_maxed(c: Dictionary) -> bool:
	for k in ["hp", "agi", "sht", "int_", "vis"]:
		if int(c.get(k, 0)) >= STAT_MAX:
			return true
	return false

# 船団の最大隻数(実績の「5隻すべて」の基準)
func max_fleet_cap() -> int:
	return 5

func _crew_achievement(aid: String) -> bool:
	if aid == "master_one":
		for e in fleet:
			for c in e.crew:
				if _crew_maxed(c):
					return true
		return false
	if fleet.size() < max_fleet_cap():
		return false
	for e2 in fleet:
		var ok := false
		for c2 in e2.crew:
			if _crew_maxed(c2):
				ok = true
				break
		if not ok:
			return false
	return true

func _fleet_achievement(aid: String) -> bool:
	match aid:
		"charge_all":
			return charge_all_tungsten
		"weapon_master":
			# #265再12: 「同時に全種類」ではなく「全種類を装備したことがある」。
			#   船団の現在の装備も取り込んだうえで数える。
			_absorb_current_weapons()
			return weapons_ever.size() >= Database.weapons.size()
		"mixed_fleet":
			var want := {"hunter_h": false, "frigate_l": false, "frigate_h": false, "cruiser": false, "dread": false}
			for e2 in fleet:
				if want.has(str(e2.ship_id)):
					want[str(e2.ship_id)] = true
			for k in want:
				if not bool(want[k]):
					return false
			return true
		"battle_fleet":
			if fleet.size() < max_fleet_cap():
				return false
			for e3 in fleet:
				if str(e3.ship_id) != "cruiser" and str(e3.ship_id) != "dread":
					return false
			return true
	return false

# #265: 選択中のバッヂによる倍率。該当キーが無ければ1.0
func badge_mult(key: String) -> float:
	if badge_id == "" or not is_achieved(badge_id):
		return 1.0
	var a := Database.achievement(badge_id)
	if a.is_empty():
		return 1.0
	return float((a.get("buff", {}) as Dictionary).get(key, 1.0))

# バッヂを選ぶ(達成済みのみ)。同じidを選び直すと解除
func select_badge(aid: String) -> void:
	if aid != "" and not is_achieved(aid):
		return
	badge_id = "" if badge_id == aid else aid
	_save_achievements()
	stats_changed.emit()

# #292: 「始めから」を選んだときは、近海の主の討伐が条件の実績を未達成に戻す。
#   実績はセーブデータとは別ファイルに持っているため、新しく始めても
#   前のデータで討伐した主の実績が達成済みのまま残っていた。
#   主をもう一度倒せば達成し直せる。バッヂに選んでいた場合はその選択も外す。
#   他のすべての実績が条件の「アルティメットプレーヤー」も、条件を満たさなくなるので外す。
func reset_lord_achievements() -> void:
	var removed := false
	for a in Database.achievements:
		var aid := str(a.id)
		if str(a.get("check", "")) != "lord":
			continue
		if achieved.erase(aid):
			removed = true
			if badge_id == aid:
				badge_id = ""
	if removed:
		for a2 in Database.achievements:
			if str(a2.get("check", "")) == "all":
				if achieved.erase(str(a2.id)) and badge_id == str(a2.id):
					badge_id = ""
		_save_achievements()

# 実績はセーブデータとは別に保存する(レヴィアタン討伐→即エンディングでも残す)
const ACHIEVE_PATH := "user://achievements.dat"

func _save_achievements() -> void:
	var f := FileAccess.open(ACHIEVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"achieved": achieved, "badge": badge_id}))
	f.close()

func load_achievements() -> void:
	if not FileAccess.file_exists(ACHIEVE_PATH):
		return
	var f := FileAccess.open(ACHIEVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	achieved = d.get("achieved", {})
	badge_id = str(d.get("badge", ""))

func record_kill(kind: String, id: String) -> void:
	if kind != "mob" and kind != "pirate":
		return
	var key := "%s:%s" % [kind, id]
	kills[key] = mini(int(kills.get(key, 0)) + 1, 999)
	check_achievements()   # #265

# #177: 討伐数の取得(未討伐は0)
func kill_count(kind: String, id: String) -> int:
	return int(kills.get("%s:%s" % [kind, id], 0))

func add_relic(value: int) -> void:
	relics += value
	relic_count += 1   # #265: 実績「考古学者」用の入手個数
	check_achievements()
	notice.emit("旧文明の遺産を発見(+%d相当)" % value)
	stats_changed.emit()

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
	check_achievements()   # #265

# #265: 名声は FAME_MAX でカンストする
const FAME_MAX := 999

func add_fame(amount: int) -> void:
	fame = mini(fame + amount, FAME_MAX)
	fame_changed.emit(fame)
	check_achievements()   # #265
	# 名声で島を解放
	for isle in Database.islands:
		if fame >= isle.fame_req and not unlocked_islands.has(isle.id):
			unlocked_islands.append(isle.id)
			# #209再11: ボスラッシュは島を巡らないので、航路解放の通知は出さない
			if not boss_rush:
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
# #265再12: 装備したことのある武器として覚える。
#   セーブデータが古くて weapons_ever が無い場合に備え、読み込み時に
#   その時点の装備を取り込む(_absorb_current_weapons)。
func note_weapon_equipped(wid: String) -> void:
	if wid == "" or not Database.weapons.has(wid):
		return
	if not weapons_ever.has(wid):
		weapons_ever[wid] = true
		check_achievements()

# 現在の船団・旗艦の装備を「装備したことがある」に取り込む
func _absorb_current_weapons() -> void:
	for e in fleet:
		for w in e.weapons:
			if str(w) != "" and Database.weapons.has(str(w)):
				weapons_ever[str(w)] = true
	for w2 in weapons:
		if str(w2) != "" and Database.weapons.has(str(w2)):
			weapons_ever[str(w2)] = true

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
		note_weapon_equipped(wid)   # #265再12
		stats_changed.emit()

func equip_weapon(slot: int, wid: String) -> void:
	while weapons.size() < int(ship().slots):
		weapons.append("")
	if slot >= 0 and slot < int(ship().slots):
		weapons[slot] = wid
		note_weapon_equipped(wid)   # #265再12
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
	return clampi(Database.tier_of(current_island) + 1, 1, FLEET_MAX)   # #239: tier基準

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

# #259: 船団速度を決めている船(律速艦)の名前。旗艦が最も遅ければ旗艦を返す。
func slowest_ship_name() -> String:
	var sp := float(ship().speed)
	var who := str(ship().name)
	for i in sailing_ships():
		var d: Dictionary = ship_def_of(i)
		if float(d.speed) < sp:
			sp = float(d.speed)
			who = str(d.name)
	return who

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
	# #240: クルーが乗っていても、そのクルーをストックへ移して船を外せるようにする
	var moved := 0
	for m in (e.crew as Array).duplicate():
		crew_stock.append(m)
		moved += 1
	e.crew.clear()
	if moved > 0:
		notice.emit("クルー%d名をストックへ移した" % moved)
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

# #240: ストックのクルーを船の空きへ乗せる
func crew_stock_to_ship(stock_idx: int, ship_idx: int) -> bool:
	if stock_idx < 0 or stock_idx >= crew_stock.size():
		return false
	if ship_idx < 0 or ship_idx >= fleet.size():
		return false
	var m: Dictionary = crew_stock[stock_idx]
	if fleet[ship_idx].crew.size() >= CREW_MAX:
		notice.emit("その船は満員です(%d名まで)" % CREW_MAX)
		return false
	if str(m.job) == "firstmate" and has_firstmate_on(ship_idx):
		notice.emit("副船長は1隻に1名までです")
		return false
	crew_stock.remove_at(stock_idx)
	fleet[ship_idx].crew.append(m)
	notice.emit("%s を %s に乗せた" % [str(m.name), fleet_label(ship_idx)])
	stats_changed.emit()
	return true

# #240: 船のクルーをストックへ降ろす
func crew_ship_to_stock(ship_idx: int, member: Dictionary) -> bool:
	if ship_idx < 0 or ship_idx >= fleet.size():
		return false
	if not fleet[ship_idx].crew.has(member):
		return false
	fleet[ship_idx].crew.erase(member)
	crew_stock.append(member)
	notice.emit("%s をストックへ降ろした" % str(member.name))
	stats_changed.emit()
	return true

# #240: ストックのクルーと、船に乗っているクルーを入れ替える
func crew_stock_swap(stock_idx: int, ship_idx: int, member: Dictionary) -> bool:
	if stock_idx < 0 or stock_idx >= crew_stock.size():
		return false
	if ship_idx < 0 or ship_idx >= fleet.size():
		return false
	var c: Array = fleet[ship_idx].crew
	var ii := c.find(member)
	if ii < 0:
		return false
	var m: Dictionary = crew_stock[stock_idx]
	# 副船長1隻1名(相手が副船長なら入れ替わるので問題ない)
	if str(m.job) == "firstmate" and str(member.job) != "firstmate" and has_firstmate_on(ship_idx):
		notice.emit("副船長は1隻に1名までです")
		return false
	c[ii] = m                       # #231再4: 元いた位置へ入れる
	crew_stock[stock_idx] = member
	notice.emit("%s と %s を交代した" % [str(member.name), str(m.name)])
	stats_changed.emit()
	return true

# #241: 出港時のワンポイントヒント。呼ぶたびに出港回数を1つ進めて、
# その回に出すヒントを返す(該当がなければ空文字)。
func next_departure_hint() -> String:
	var isle := current_island
	var n := int(departures.get(isle, 0)) + 1
	departures[isle] = n
	var h: Dictionary = Database.pick_departure_hint(isle, n, fame, hint_fame22_used)
	if h.is_empty():
		return ""
	if bool(h.get("fame22", false)):
		hint_fame22_used = true
	var txt := str(h.get("text", ""))
	# #241再2: 実際に表示したものだけを新しい順で記録する
	if txt != "":
		hint_log.push_front({"island": Database.island(isle).name, "text": txt})
		while hint_log.size() > HINT_LOG_MAX:
			hint_log.pop_back()
	return txt

# #231再3: 同じ船の中でクルーの並び順を入れ替える(編成画面のクリック方式で使う)
func reorder_crew(ship_idx: int, a: Dictionary, b: Dictionary) -> bool:
	if ship_idx < 0 or ship_idx >= fleet.size():
		return false
	var c: Array = fleet[ship_idx].crew
	var ia := c.find(a)
	var ib := c.find(b)
	if ia < 0 or ib < 0 or ia == ib:
		return false
	c[ia] = b
	c[ib] = a
	notice.emit("%s と %s の並びを入れ替えた" % [a.name, b.name])
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
	# #231再4: 交代でも副船長1隻1名の制約を守る。移動(move_crew)にはあったが
	# 交代側に無く、副船長どうし以外の交代で1隻に2名置けてしまっていた。
	if str(a.job) == "firstmate" and str(b.job) != "firstmate" and has_firstmate_on(to_idx):
		notice.emit("副船長は1隻に1名までです")
		return false
	if str(b.job) == "firstmate" and str(a.job) != "firstmate" and has_firstmate_on(from_idx):
		notice.emit("副船長は1隻に1名までです")
		return false
	# #231再4: 末尾へ足すのではなく「元いた位置」へ入れる(並びが崩れないように)
	var ia := ca.find(a)
	var ib := cb.find(b)
	ca[ia] = b
	cb[ib] = a
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
