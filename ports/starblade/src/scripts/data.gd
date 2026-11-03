extends RefCounted
## Inventory and persistent progression. Scene state is deliberately not serialized.

const SAVE_VERSION: int = 2
const Heroes = preload("res://scripts/heroes.gd")
const Talents = preload("res://scripts/talents.gd")
const SHOP_GEAR_IDS := ["gear_blade_green","gear_blade_blue","gear_blade_purple","gear_armor_green","gear_armor_blue","gear_armor_purple","gear_charm_green","gear_charm_blue","gear_charm_purple"]
const WEAPONS: Dictionary = {
	"spear": {"name":"星铸长矛", "subtitle":"VARATHA / 主动长矛", "desc":"J 刺击 / 蓄力旋转 · K 投掷召回。祝福与锤子改变招式；不携带自动飞剑。", "family":"spear", "damage":25.0, "interval":0.3, "count":0, "range":3.6, "color":"ffd18b", "price":0},
	"needle": {"name":"流光", "family":"flying", "subtitle":"NEEDLE / 均衡剑阵", "desc":"三柄轻型飞剑。J 逐柄射出，落地插剑；剑阵打空后再按 J 全数召回。", "damage":18.0, "interval":0.72, "count":3, "range":8.0, "color":"64e8ff", "price":0},
	"arc": {"name":"雷隼", "family":"flying", "subtitle":"ARC / 高频剑阵", "desc":"四柄高频飞剑，射速更快，命中电弧连锁邻近目标。", "damage":13.0, "interval":0.48, "count":4, "range":8.5, "color":"bda1ff", "price":450},
	"heavy": {"name":"断岳", "family":"flying", "subtitle":"BREAKER / 重型剑阵", "desc":"两柄远距重剑，自带一次贯穿，命中触发范围震荡。", "damage":36.0, "interval":1.02, "count":2, "range":10.0, "color":"ffc36b", "price":850}
}
const ITEMS: Dictionary = {
	"scrap": {"name":"合金碎片", "w":1, "h":1, "value":35, "color":"9cb1bc", "desc":"常见回收材料。出售获取信用点，用于解锁英雄天赋或购买装备。"},
	"circuit": {"name":"精密电路", "w":1, "h":1, "value":85, "color":"65e8d0", "desc":"精密电子元件，可带回基地交易。"},
	"cell": {"name":"能量电池", "w":1, "h":2, "value":110, "color":"7bdcff", "desc":"高能回收电池。带回基地出售，积累信用点解锁英雄天赋或购买装备。"},
	"medkit": {"name":"医疗模块", "w":2, "h":1, "value":90, "color":"8cecbb", "desc":"撤离后自动制成一支随行修复剂。"},
	"relic": {"name":"量子遗物", "w":2, "h":2, "value":420, "color":"c9a3ff", "desc":"高价值科研遗物。及时撤离才能保住收益。"},
	"core": {"name":"反应炉核心", "w":2, "h":2, "value":600, "color":"ffc16a", "desc":"主线回收目标。带回基地提交，领取 900 信用点。"},
	"key": {"name":"中枢门禁卡", "w":1, "h":1, "value":160, "color":"ffb879", "desc":"稀有访问凭证，带回后保存在永久仓库。"},
	"cache": {"name":"密封战利品箱", "w":2, "h":2, "value":180, "color":"ffb85c", "desc":"带回基地后拆解，获得两件随机物资。"},
	"gear_blade_white": {"name":"制式剑芯", "w":1,"h":2,"value":80,"color":"d6e0e5","rarity":0,"rarity_id":"white","rarity_name":"普通","tier":0,"slot":"blade","bonuses":{"damage":0.06},"desc":"剑芯 / 伤害 +6%。带回大厅装配，战败会遗失。"},
	"gear_blade_green": {"name":"校准剑芯", "w":1,"h":2,"value":160,"color":"83e99b","rarity":1,"rarity_id":"green","rarity_name":"精良","tier":1,"slot":"blade","bonuses":{"damage":0.12},"desc":"剑芯 / 伤害 +12%。带回大厅装配，战败会遗失。"},
	"gear_blade_blue": {"name":"裂光剑芯", "w":1,"h":2,"value":300,"color":"68b9ff","rarity":2,"rarity_id":"blue","rarity_name":"稀有","tier":2,"slot":"blade","bonuses":{"damage":0.20,"haste":-0.03},"desc":"剑芯 / 伤害 +20%，攻速 -3%。重型振荡结构。"},
	"gear_blade_purple": {"name":"虚空剑芯", "w":1,"h":2,"value":550,"color":"c396ff","rarity":3,"rarity_id":"purple","rarity_name":"史诗","tier":3,"slot":"blade","bonuses":{"damage":0.30,"crit":0.04,"haste":-0.04},"desc":"剑芯 / 伤害 +30%，暴击 +4%，攻速 -4%。"},
	"gear_blade_gold": {"name":"天穹剑芯", "w":1,"h":2,"value":1000,"color":"ffcb69","rarity":4,"rarity_id":"gold","rarity_name":"传说","tier":4,"slot":"blade","bonuses":{"damage":0.42,"crit":0.08,"haste":-0.05},"desc":"剑芯 / 伤害 +42%，暴击 +8%，攻速 -5%。"},
	"gear_armor_white": {"name":"制式护甲", "w":2,"h":2,"value":90,"color":"d6e0e5","rarity":0,"rarity_id":"white","rarity_name":"普通","tier":0,"slot":"armor","bonuses":{"hp":8.0},"desc":"护甲 / 生命上限 +8。带回大厅后装配。"},
	"gear_armor_green": {"name":"纤维护甲", "w":2,"h":2,"value":180,"color":"83e99b","rarity":1,"rarity_id":"green","rarity_name":"精良","tier":1,"slot":"armor","bonuses":{"hp":16.0},"desc":"护甲 / 生命上限 +16。轻型复合纤维。"},
	"gear_armor_blue": {"name":"磁流护甲", "w":2,"h":2,"value":330,"color":"68b9ff","rarity":2,"rarity_id":"blue","rarity_name":"稀有","tier":2,"slot":"armor","bonuses":{"hp":28.0,"speed":-0.02},"desc":"护甲 / 生命上限 +28，移速 -2%。"},
	"gear_armor_purple": {"name":"相位护甲", "w":2,"h":2,"value":600,"color":"c396ff","rarity":3,"rarity_id":"purple","rarity_name":"史诗","tier":3,"slot":"armor","bonuses":{"hp":42.0,"speed":-0.03},"desc":"护甲 / 生命上限 +42，移速 -3%。"},
	"gear_armor_gold": {"name":"不朽护甲", "w":2,"h":2,"value":1100,"color":"ffcb69","rarity":4,"rarity_id":"gold","rarity_name":"传说","tier":4,"slot":"armor","bonuses":{"hp":60.0,"speed":-0.04},"desc":"护甲 / 生命上限 +60，移速 -4%。"},
	"gear_charm_white": {"name":"制式回路", "w":1,"h":2,"value":75,"color":"d6e0e5","rarity":0,"rarity_id":"white","rarity_name":"普通","tier":0,"slot":"charm","bonuses":{"haste":0.04},"desc":"回路 / 攻速 +4%。带回大厅装配。"},
	"gear_charm_green": {"name":"迅捷回路", "w":1,"h":2,"value":150,"color":"83e99b","rarity":1,"rarity_id":"green","rarity_name":"精良","tier":1,"slot":"charm","bonuses":{"haste":0.08,"speed":0.02},"desc":"回路 / 攻速 +8%，移速 +2%。"},
	"gear_charm_blue": {"name":"超频回路", "w":1,"h":2,"value":280,"color":"68b9ff","rarity":2,"rarity_id":"blue","rarity_name":"稀有","tier":2,"slot":"charm","bonuses":{"haste":0.13,"crit":0.03,"speed":0.03},"desc":"回路 / 攻速 +13%，暴击 +3%，移速 +3%。"},
	"gear_charm_purple": {"name":"星辉回路", "w":1,"h":2,"value":520,"color":"c396ff","rarity":3,"rarity_id":"purple","rarity_name":"史诗","tier":3,"slot":"charm","bonuses":{"haste":0.19,"crit":0.06,"speed":0.05},"desc":"回路 / 攻速 +19%，暴击 +6%，移速 +5%。"},
	"gear_charm_gold": {"name":"永恒回路", "w":1,"h":2,"value":950,"color":"ffcb69","rarity":4,"rarity_id":"gold","rarity_name":"传说","tier":4,"slot":"charm","bonuses":{"haste":0.27,"crit":0.10,"speed":0.07},"desc":"回路 / 攻速 +27%，暴击 +10%，移速 +7%。"}
}
const SKILLS: Array = [
	{"id":"extra", "name":"万剑归宗", "desc":"剑阵扩容：额外 +1 柄飞剑，一轮可多射一剑。", "tag":"剑阵 · 扩容", "color":"66e6ff"},
	{"id":"haste", "name":"超频协议", "desc":"射击间隔缩短 18%，飞剑出射与召回速度 +20%。", "tag":"剑阵 · 射速", "color":"78ddff"},
	{"id":"power", "name":"锋刃重铸", "desc":"飞剑与长矛伤害提高 25%。", "tag":"火力 · 强化", "color":"ffba73"},
	{"id":"chain", "name":"电弧连锁", "desc":"命中时向附近敌人传递电弧伤害。", "tag":"异能 · 连锁", "color":"baa6ff"},
	{"id":"frost", "name":"零度禁锢", "desc":"飞剑命中使敌人暂时减速。", "tag":"异能 · 控制", "color":"81eeef"},
	{"id":"leech", "name":"纳米回收", "desc":"击杀敌人回复少量生命。", "tag":"生存 · 续航", "color":"91e9b6"},
	{"id":"shield", "name":"相位装甲", "desc":"增加 25 护盾，脱离受击 4 秒后逐渐恢复。", "tag":"生存 · 防护", "color":"81bbff"},
	{"id":"dash", "name":"跃迁引擎", "desc":"闪避冷却缩短，位移更灵活。", "tag":"机动 · 闪避", "color":"9bdcff"},
	{"id":"magnet", "name":"御剑索敌", "desc":"飞剑自动追踪附近敌人，瞄准辅助更宽；射程与祝福拾取范围增加。", "tag":"剑阵 · 追踪", "color":"8cedd6"},
	{"id":"crit", "name":"弱点解析", "desc":"提高暴击率，暴击造成双倍伤害。", "tag":"剑阵 · 暴击", "color":"ffd18b"},
	{"id":"repair", "name":"紧急重构", "desc":"生命上限 +15，修复 35 生命，持续缓慢再生。", "tag":"生存 · 修复", "color":"92ebba"},
	{"id":"penetrate", "name":"共振冲击", "desc":"剑击产生小范围冲击，伤及周围敌人。", "tag":"异能 · 群攻", "color":"f6a278"},
	{"id":"pierce", "name":"穿云剑意", "desc":"飞剑额外贯穿 1 名敌人后继续飞行。", "tag":"剑阵 · 贯穿", "color":"9ff3ff"},
	{"id":"ricochet", "name":"折光弹射", "desc":"飞剑命中后弹射至 6.5 米内另一名敌人。", "tag":"剑阵 · 弹射", "color":"c7a8ff"},
	{"id":"recall_cut", "name":"归鞘斩", "desc":"召回飞剑造成全额伤害（基础为 35%），横扫归途上的敌人。", "tag":"剑阵 · 召回", "color":"7ff0c4"},
	{"id":"quickdraw", "name":"拔剑式", "desc":"剑阵满载时射出的第一剑必定暴击。", "tag":"剑阵 · 首击", "color":"ffe08a"},
	{"id":"bloom", "name":"剑冢", "desc":"落地的飞剑每 0.5 秒灼伤周围 1.7 米内的敌人。", "tag":"剑阵 · 领域", "color":"ffc36b"},
	{"id":"salvo", "name":"幻影双生", "desc":"每次射击额外射出一柄贯穿的幻影剑，造成 50% 伤害。", "tag":"剑阵 · 分身", "color":"d6f6ff"}
]

var profile: Dictionary = {}
var bag: Array = []
var secure: String = ""
var bag_cols: int = 5
var save_path: String
var active: bool = false
var interrupted_run: bool = false
var last_error: String = ""
var last_result: Dictionary = {}

func _init(path: String = "user://profile.json") -> void:
	save_path = path
	profile = _defaults()

func _defaults() -> Dictionary:
	return {"version":SAVE_VERSION, "hero":Heroes.DEFAULT_ID, "talents":Talents.defaults(), "credits":650, "weapon":"spear", "owned":["needle","spear"], "upgrades":{"pack":0,"reactor":0,"armor":0}, "stash":[], "meds":3, "runs":0,"extracts":0,"kills":0,"quest_claimed":false,"active_run":{},"equipped":{"blade":"","armor":"","charm":""},"best_stage":0}

func item(id: String) -> Dictionary:
	if not ITEMS.has(id):
		return {}
	var result: Dictionary = ITEMS[id].duplicate(true)
	result["id"] = id
	return result

func weapon() -> Dictionary:
	var id: String = str(profile.get("weapon", "needle"))
	var result: Dictionary = WEAPONS.get(id, WEAPONS.needle).duplicate(true)
	result["id"] = id
	return result

func load_profile() -> void:
	last_error = ""
	var loaded: Dictionary = _read_valid(save_path)
	if loaded.is_empty():
		loaded = _read_valid(save_path + ".bak")
	profile = loaded if not loaded.is_empty() else _defaults()
	var migrated: bool = int(profile.version) < SAVE_VERSION
	if migrated:
		# v1 pack levels cost 300/600 credits and 1/2 circuits. Refund once,
		# then stamp v2 in the same save as any interrupted-raid recovery.
		var old_level: int = int(profile.upgrades.get("pack", 0))
		var investment: int = old_level * (old_level + 1) / 2
		profile.credits = int(profile.credits) + 300 * investment
		for unused: int in investment:
			profile.stash.append("circuit")
		profile.version = SAVE_VERSION
	profile.upgrades.pack = 0 # Kept only for older callers; there is no pack upgrade.
	bag.clear()
	secure = ""
	active = false
	interrupted_run = false
	# Closing a live raid cannot duplicate the equipment that was put at risk.
	var interrupted: Dictionary = profile.get("active_run", {})
	if not interrupted.is_empty():
		interrupted_run = true
		var kept: String = str(interrupted.get("secure", ""))
		if ITEMS.has(kept):
			_store_extracted(kept)
		_lose_weapon(str(interrupted.get("weapon", "needle")))
		_lose_equipment()
		profile.runs = int(profile.runs) + 1
		profile["active_run"] = {}
	if migrated or interrupted_run:
		save_profile()

func _read_valid(path: String) -> Dictionary:
	var rel := _rel(path)
	if not FileAccess.file_exists("user://" + rel):
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string("user://" + rel)) != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {}
	var raw: Dictionary = parsed
	var version: Variant = raw.get("version", 0)
	if not (version is int or version is float) or not is_finite(float(version)):
		return {}
	if float(version) != floor(float(version)) or float(version) not in [1.0,float(SAVE_VERSION)]:
		return {}
	if not raw.get("stash", null) is Array or not raw.get("owned", null) is Array or not raw.get("upgrades", null) is Dictionary:
		return {}
	var clean: Dictionary = _defaults()
	clean.version = int(version)
	for key: String in ["credits", "meds", "runs", "extracts", "kills", "best_stage"]:
		var value: Variant = raw.get(key, clean[key])
		if not (value is int or value is float) or not is_finite(float(value)):
			return {}
		clean[key] = int(clampf(float(value), 0.0, 99999999.0))
	clean.quest_claimed = raw.get("quest_claimed", false) == true
	for kind: String in ["pack", "reactor", "armor"]:
		var upgrade_level: Variant = raw.upgrades.get(kind, 0)
		if not (upgrade_level is int or upgrade_level is float) or not is_finite(float(upgrade_level)):
			return {}
		clean.upgrades[kind] = int(clampf(float(upgrade_level),0.0,3.0 if kind != "pack" else 2.0))
	for id: Variant in raw.owned:
		if id is String and WEAPONS.has(id) and not clean.owned.has(id):
			clean.owned.append(id)
	var selected: String = str(raw.get("weapon", "needle"))
	clean.weapon = selected if clean.owned.has(selected) else "needle"
	var selected_hero := str(raw.get("hero",Heroes.DEFAULT_ID))
	clean.hero = selected_hero if Heroes.valid(selected_hero) else Heroes.DEFAULT_ID
	clean.talents = Talents.sanitize(raw.get("talents",{}))
	var raw_equipped: Variant = raw.get("equipped", {})
	if raw_equipped is Dictionary:
		for slot: String in ["blade", "armor", "charm"]:
			var id: String = str(raw_equipped.get(slot, ""))
			if ITEMS.has(id) and ITEMS[id].get("slot", "") == slot:
				clean.equipped[slot] = id
	for id: Variant in raw.stash:
		if id is String and ITEMS.has(id):
			clean.stash.append(id)
	if raw.get("active_run", {}) is Dictionary:
		clean.active_run = raw.get("active_run", {}).duplicate(true)
	# Extra plain-data fields (such as a corpse location) belong to the root controller.
	for key: Variant in raw:
		if not clean.has(key):
			clean[key] = raw[key]
	return clean

static func _rel(path: String) -> String:
	return path.trim_prefix("user://").replace("/", "_").replace("..", "_")

func save_profile() -> bool:
	last_error = ""
	profile["version"] = SAVE_VERSION
	# Platform port: saves stay inside user:// (IndexedDB on web) and never use absolute paths.
	var rel := _rel(save_path)
	var dir := DirAccess.open("user://")
	if dir == null:
		last_error = "无法打开存档目录"
		return false
	var file: FileAccess = FileAccess.open("user://" + rel + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "无法写入临时存档"
		return false
	file.store_string(JSON.stringify(profile))
	file.flush()
	file.close()
	if FileAccess.file_exists("user://" + rel) and not _read_valid(save_path).is_empty():
		var bak := FileAccess.open("user://" + rel + ".bak", FileAccess.WRITE)
		if bak != null:
			bak.store_string(FileAccess.get_file_as_string("user://" + rel)); bak.close()
	if FileAccess.file_exists("user://" + rel):
		dir.remove("user://" + rel)
	if dir.rename("user://" + rel + ".tmp", "user://" + rel) != OK:
		last_error = "替换存档失败"
		return false
	return true

func _commit(before: Dictionary) -> bool:
	if save_profile():
		return true
	profile = before
	return false

func select_weapon(id: String) -> bool:
	if active or not WEAPONS.has(id):
		return false
	var before: Dictionary = profile.duplicate(true)
	if not profile.owned.has(id):
		var price: int = int(WEAPONS[id].price)
		if int(profile.credits) < price:
			return false
		profile.credits = int(profile.credits) - price
		profile.owned.append(id)
	profile.weapon = id
	return _commit(before)

func hero() -> Dictionary:
	return Heroes.get_hero(str(profile.get("hero",Heroes.DEFAULT_ID)))

func select_hero(id: String) -> bool:
	if active or not Heroes.valid(id): return false
	if str(profile.get("hero",Heroes.DEFAULT_ID)) == id: return true
	var before: Dictionary = profile.duplicate(true)
	profile.hero = id
	return _commit(before)

func talent_tree(hero_id: String = "") -> Array:
	var selected := str(profile.get("hero",Heroes.DEFAULT_ID)) if hero_id.is_empty() else hero_id
	if not Heroes.valid(selected): return []
	var progress := Talents.sanitize(profile.get("talents",{}))
	var result: Array = Talents.tree(selected)
	for entry in result:
		var unlocked: bool = progress[selected][entry.id]
		var parent_ok: bool = str(entry.parent).is_empty() or progress[selected][entry.parent] == true
		entry["unlocked"] = unlocked
		entry["rank"] = 1 if unlocked else 0
		entry["available"] = not unlocked and parent_ok
		entry["price"] = int(entry.cost)
		entry["can_buy"] = not unlocked and parent_ok and not active and int(profile.credits) >= int(entry.cost)
		entry["reason"] = "已解锁" if unlocked else ("请返回大厅解锁" if active else ("需先解锁前置天赋" if not parent_ok else ("信用点不足" if int(profile.credits) < int(entry.cost) else "可解锁")))
	return result

func talent_bonuses(hero_id: String = "") -> Dictionary:
	var selected := str(profile.get("hero",Heroes.DEFAULT_ID)) if hero_id.is_empty() else hero_id
	return Talents.bonuses(selected,Talents.sanitize(profile.get("talents",{})))

func unlock_talent(hero_id: String, node_id: String) -> bool:
	last_error = ""
	if active:
		last_error = "战区内不能解锁永久天赋"; return false
	if not Heroes.valid(hero_id):
		last_error = "无效英雄"; return false
	var selected: Dictionary = {}
	for entry in talent_tree(hero_id):
		if entry.id == node_id: selected = entry; break
	if selected.is_empty():
		last_error = "无效天赋"; return false
	if not selected.can_buy:
		last_error = str(selected.reason); return false
	var before: Dictionary = profile.duplicate(true)
	profile["talents"] = Talents.sanitize(profile.get("talents",{}))
	profile.talents[hero_id][node_id] = true
	profile.credits = int(profile.credits)-int(selected.price)
	return _commit(before)

func shop_offers() -> Array:
	var result: Array = []
	for id in SHOP_GEAR_IDS:
		var offer := item(id)
		# Integer ceil(value * 1.6), avoiding floating-point rounding near integers.
		offer["price"] = (int(offer.value)*8+4)/5
		offer["can_buy"] = not active and int(profile.credits) >= int(offer.price)
		offer["reason"] = "请返回大厅购买" if active else ("信用点不足" if int(profile.credits) < int(offer.price) else "可购买")
		result.append(offer)
	return result

func buy_equipment(id: String) -> bool:
	last_error = ""
	if active:
		last_error = "战区内不能购买装备"; return false
	if id not in SHOP_GEAR_IDS:
		last_error = "该装备不在商店货架"; return false
	var price: int = (int(ITEMS[id].value)*8+4)/5
	if int(profile.credits) < price:
		last_error = "信用点不足"; return false
	var before: Dictionary = profile.duplicate(true)
	profile.credits = int(profile.credits)-price
	profile.stash.append(id)
	return _commit(before)

func equip_stash(index: int) -> bool:
	if active or index < 0 or index >= profile.stash.size():
		return false
	var id: String = str(profile.stash[index])
	if not ITEMS.has(id) or not ITEMS[id].has("slot"):
		return false
	var slot: String = ITEMS[id].slot
	var before: Dictionary = profile.duplicate(true)
	var previous: String = str(profile.equipped.get(slot, ""))
	profile.stash.remove_at(index)
	if ITEMS.has(previous):
		profile.stash.append(previous)
	profile.equipped[slot] = id
	return _commit(before)

func unequip_slot(slot: String) -> bool:
	if active or not profile.equipped.has(slot):
		return false
	var id: String = str(profile.equipped[slot])
	if not ITEMS.has(id):
		return false
	var before: Dictionary = profile.duplicate(true)
	profile.equipped[slot] = ""
	profile.stash.append(id)
	return _commit(before)

func equipment_bonuses() -> Dictionary:
	var result: Dictionary = {"damage":0.0,"hp":0.0,"crit":0.0,"haste":0.0,"speed":0.0}
	for slot: String in ["blade","armor","charm"]:
		var id: String = str(profile.equipped.get(slot, ""))
		if not ITEMS.has(id) or ITEMS[id].get("slot", "") != slot:
			continue
		var bonuses: Dictionary = ITEMS[id].get("bonuses", {})
		for key: String in bonuses:
			if result.has(key): result[key] = float(result[key]) + float(bonuses[key])
	return result

func _lose_equipment() -> void:
	profile.equipped = {"blade":"","armor":"","charm":""}

func upgrade_cost(kind: String) -> Dictionary:
	if kind not in ["reactor", "armor"]:
		return {}
	var level: int = int(profile.upgrades[kind])
	var maximum: int = 3
	if level >= maximum:
		return {"credits":0, "item":"", "count":0, "max":true, "label":"已满级", "materials":{}}
	var costs: Dictionary = {"reactor":[400,"cell",1],"armor":[250,"scrap",2]}
	var row: Array = costs[kind]
	var credits: int = int(row[0]) * (level + 1)
	var count: int = int(row[2]) * (level + 1)
	var material: String = str(row[1])
	return {"credits":credits, "item":material, "count":count, "max":false, "label":"%d 信用点 + %s ×%d" % [credits, ITEMS[material].name, count], "materials":{material:count}}

func stash_count(id: String) -> int:
	return profile.stash.count(id)

func upgrade(kind: String) -> bool:
	if active:
		return false
	var cost: Dictionary = upgrade_cost(kind)
	if cost.is_empty() or cost.get("max", false) or int(profile.credits) < int(cost.credits) or stash_count(cost.item) < int(cost.count):
		return false
	var before: Dictionary = profile.duplicate(true)
	profile.credits = int(profile.credits) - int(cost.credits)
	for unused: int in int(cost.count):
		profile.stash.erase(cost.item)
	profile.upgrades[kind] = int(profile.upgrades[kind]) + 1
	return _commit(before)

func sell_stash() -> int:
	if active:
		return 0
	var before: Dictionary = profile.duplicate(true)
	var total: int = 0
	var kept: Array = []
	for id: String in profile.stash:
		# Mission cores, access cards, and unopened containers remain available.
		if id in ["core", "key", "cache"] or ITEMS[id].has("slot"):
			kept.append(id)
		else:
			total += int(ITEMS[id].value)
	profile.stash = kept
	profile.credits = int(profile.credits) + total
	return total if _commit(before) else 0

func sell_item(index: int) -> int:
	if active or index < 0 or index >= profile.stash.size():
		return 0
	var id: String = str(profile.stash[index])
	if not ITEMS.has(id):
		return 0
	var before: Dictionary = profile.duplicate(true)
	var value: int = int(ITEMS[id].value)
	profile.stash.remove_at(index)
	profile.credits = int(profile.credits) + value
	return value if _commit(before) else 0

func buy_med() -> bool:
	if active or int(profile.credits) < 60:
		return false
	var before: Dictionary = profile.duplicate(true)
	profile.credits = int(profile.credits) - 60
	profile.meds = int(profile.meds) + 1
	return _commit(before)

func claim_quest() -> bool:
	if active or profile.quest_claimed or not profile.stash.has("core"):
		return false
	var before: Dictionary = profile.duplicate(true)
	profile.stash.erase("core")
	profile.credits = int(profile.credits) + 900
	profile.quest_claimed = true
	return _commit(before)

func open_caches() -> int:
	if active:
		return 0
	var before: Dictionary = profile.duplicate(true)
	var count: int = profile.stash.count("cache")
	var pool: Array = ["scrap","circuit","cell","circuit","relic","medkit"]
	for unused: int in count:
		profile.stash.erase("cache")
		_store_extracted("circuit")
		_store_extracted(str(pool.pick_random()))
	return count if _commit(before) else 0

func bag_rows() -> int:
	# Legacy display metadata only. Loot has no capacity or weight limit.
	return maxi(4, bag.size() * 2)

func used_cells() -> int:
	var total: int = 0
	for entry: Dictionary in bag:
		total += int(entry.w) * int(entry.h)
	return total

func bag_value() -> int:
	var total: int = 0
	for entry: Dictionary in bag:
		total += int(ITEMS[entry.id].value)
	if ITEMS.has(secure):
		total += int(ITEMS[secure].value)
	return total

func start_run() -> bool:
	if active:
		return false
	var before: Dictionary = profile.duplicate(true)
	bag.clear()
	secure = ""
	last_result = {}
	active = true
	profile["active_run"] = {"weapon":profile.weapon, "secure":"", "equipped":profile.equipped.duplicate(true)}
	if not _commit(before):
		active = false
		return false
	return true

func add_loot(id: String) -> bool:
	if not active or not ITEMS.has(id):
		return false
	var definition: Dictionary = ITEMS[id]
	bag.append({"id":id,"x":0,"y":bag.size() * 2,"w":int(definition.w),"h":int(definition.h)})
	return true

func drop_loot(index: int) -> String:
	if not active or index < 0 or index >= bag.size():
		return ""
	var id: String = str(bag[index].id)
	bag.remove_at(index)
	return id

func secure_loot(_index: int) -> bool:
	# Retired in v2. load_profile still honors v1 active_run.secure.
	return false

func unsecure_loot() -> bool:
	return false

func _store_extracted(id: String) -> void:
	if id == "medkit":
		profile.meds = int(profile.meds) + 1
	elif ITEMS.has(id):
		profile.stash.append(id)

func _lose_weapon(id: String) -> void:
	if id not in ["needle","spear"]:
		profile.owned.erase(id)
	profile.weapon = "spear" if id == "spear" else "needle"

func finish_run(success: bool, kills: int) -> Dictionary:
	if not active:
		return last_result.duplicate(true)
	var before: Dictionary = profile.duplicate(true)
	var extracted: Array = []
	var lost: Array = []
	var value: int = 0
	for entry: Dictionary in bag:
		var id: String = str(entry.id)
		if success:
			extracted.append(id)
			value += int(ITEMS[id].value)
			_store_extracted(id)
		else:
			lost.append(id)
	if ITEMS.has(secure):
		extracted.append(secure)
		value += int(ITEMS[secure].value)
		_store_extracted(secure)
	var reward: int = 80 + maxi(0, kills) * 12 if success else 0
	profile.credits = int(profile.credits) + reward
	profile.runs = int(profile.runs) + 1
	profile.kills = int(profile.kills) + maxi(0, kills)
	if success:
		profile.extracts = int(profile.extracts) + 1
	else:
		_lose_weapon(str(profile.active_run.get("weapon", profile.weapon)))
		_lose_equipment()
	profile.active_run = {}
	if not _commit(before):
		return {"success":false,"save_failed":true,"error":last_error,"items":[],"value":0,"lost":[],"credits":0,"kills":kills}
	last_result = {"success":success,"items":extracted,"value":value,"lost":lost,"credits":reward,"kills":maxi(0,kills)}
	bag.clear()
	secure = ""
	active = false
	return last_result.duplicate(true)
