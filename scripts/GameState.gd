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

# --- 航海中ランタイム値(出港でリセット) ---
var run_food: float = 0.0
var run_armor: float = 0.0
var fire_burn: float = 0.0   # ヒュドラの炎=時間経過で回復するスリップ被害
var at_sea: bool = false

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
	run_food = max_food()
	run_armor = max_armor()
	fire_burn = 0.0
	stats_changed.emit()

# ヒュドラの炎: 装甲を削るが fire_burn に蓄積し、World 側で時間回復する
func apply_fire(amount: float) -> void:
	run_armor = maxf(run_armor - amount, 0.0)
	fire_burn += amount
	stats_changed.emit()

# 炎被害の自然回復(World の航海ループから毎フレーム呼ぶ)
func regen_fire(delta: float) -> void:
	if fire_burn <= 0.0:
		return
	var heal: float = minf(fire_burn, 7.0 * delta)
	run_armor = minf(run_armor + heal, max_armor())
	fire_burn -= heal

# 漁獲を魚倉へ。入りきらなければ false。
func add_cargo(id: String, cap_needed: int = -1) -> bool:
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

func buy_ship(new_id: String) -> bool:
	var cost := int(Database.ships[new_id].price) - int(ship().trade)
	cost = maxi(cost, 0)
	if money < cost:
		notice.emit("資金が足りません")
		return false
	add_money(-cost)
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
