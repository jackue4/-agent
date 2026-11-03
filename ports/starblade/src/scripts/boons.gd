extends RefCounted
## Hades-inspired build catalog. Mechanic identities follow the reference;
## numbers, rarity curves and two-slot prerequisite coverage are project tuning.
const GODS := {
	"zeus":{"name":"宙斯","color":"f4d969"}, "poseidon":{"name":"波塞冬","color":"57d6ec"},
	"athena":{"name":"雅典娜","color":"e9d6a2"}, "aphrodite":{"name":"阿芙洛狄忒","color":"f29fc6"},
	"artemis":{"name":"阿尔忒弥斯","color":"9be983"}, "ares":{"name":"阿瑞斯","color":"ec6c67"},
	"dionysus":{"name":"狄俄尼索斯","color":"bc8bea"}, "demeter":{"name":"德墨忒尔","color":"afdeeb"}
}
const RARITIES := ["普通","稀有","史诗","英雄"]
static var _templates: Dictionary = {}

static func catalog() -> Dictionary:
	if _templates.is_empty(): _templates = _build_catalog()
	return _templates.duplicate(true)

static func _build_catalog() -> Dictionary:
	var entries: Dictionary = {}
	var hammers := [
		["triple_jab","三叉突刺","每次普攻同时朝三个方向突刺，覆盖更广；同一目标只受伤一次。",{"attack_lanes":3,"spread_angle":.28},[]],
		["flurry_jab","疾风突刺","按住普攻连续快速突刺；失去蓄力旋扫。",{"flurry":true},["massive_spin","quick_spin","flaring_spin"]],
		["serrated_point","锯齿枪尖","冲刺突刺连续命中三次；冲刺距离减少 25%。",{"dash_hits":3,"dash_distance":.75},[]],
		["extending_jab","延伸突刺","突刺射程提高 40%；远处敌人额外承受 40% 伤害。",{"reach_multiplier":1.4,"distant_damage":.4,"distant_threshold":3.48},[]],
		["massive_spin","巨大旋扫","旋扫伤害提高 125%，半径提高 30%。",{"spin_damage":2.25,"spin_radius":1.3},["flurry_jab"]],
		["quick_spin","迅捷旋扫","旋扫仅需 0.15 秒达到二档、0.30 秒满蓄力，旋扫后摇缩短。",{"charge_medium":.15,"charge_full":.30,"spin_recovery":.5},["flurry_jab"]],
		["flaring_spin","炽焰旋扫","蓄力期间持续脉冲伤害，并获得坚韧：减伤 30%、不被打断。",{"charge_pulse_damage":40.0,"charge_pulse_interval":.55,"charge_pulse_radius":2.4,"sturdy_reduction":.3},["flurry_jab"]],
		["chain_skewer","连锁穿刺","投出的长矛在最多七名敌人间折返追击，伤害提高 30%。",{"chain_targets":7,"chain_damage":1.3,"chain_radius":6.0},["exploding_launcher"]],
		["exploding_launcher","爆裂发射器","特殊攻击改为爆炸弹，基础伤害 50；命中或撞墙爆炸，无需召回。",{"explosion_damage":50.0,"explosion_radius":2.5},["chain_skewer","vicious_skewer"]],
		["charged_skewer","蓄力穿刺","按住特殊攻击蓄力，松开投出；最高增加 200% 基础伤害，轻点投程缩短。",{"special_charge_time":.85,"special_charge_bonus":2.0,"minimum_range":.25},[]],
		["breaching_skewer","破甲穿刺","特殊攻击对尚有护甲的敌人造成额外 400% 伤害。",{"armor_bonus":4.0},[]],
		["vicious_skewer","残酷穿刺","特殊攻击伤害提高 50%；召回命中额外获得 50% 暴击率。",{"special_damage":1.5,"return_crit":.5},["exploding_launcher"]]
	]
	for h in hammers:
		entries[h[0]] = {"id":h[0],"name":h[1],"desc":h[2],"color":"ffc56b","type":"hammer","slot":"hammer","god":"daedalus","god_name":"代达罗斯","tags":["spear","hammer"],"effects":h[3],"excludes":h[4],"requires":[],"scales":[]}
	_core(entries,"zeus_attack","雷霆突刺","zeus","attack","攻击引发连锁闪电。",{"damage_pct":0.0,"lightning_damage":10.0,"chain_count":3,"chain_radius":4.0},["lightning_damage"])
	_core(entries,"zeus_special","雷霆投枪","zeus","special","特殊攻击召唤落雷。",{"damage_pct":0.0,"bolt_damage":30.0,"bolt_radius":1.5},["bolt_damage"])
	_core(entries,"poseidon_attack","风浪突刺","poseidon","attack","攻击伤害提高，并强力击退。",{"damage_pct":.3,"knockback":7.0},["damage_pct"])
	_core(entries,"poseidon_special","风浪投枪","poseidon","special","特殊攻击伤害提高，并强力击退。",{"damage_pct":.7,"knockback":9.0},["damage_pct"])
	_core(entries,"athena_attack","神圣突刺","athena","attack","攻击伤害提高，攻击轨迹反弹敌方子弹。",{"damage_pct":.4,"deflect":true},["damage_pct"])
	_core(entries,"athena_special","神圣投枪","athena","special","特殊攻击伤害提高，投掷和召回沿途反弹子弹。",{"damage_pct":.6,"deflect":true},["damage_pct"])
	_core(entries,"aphrodite_attack","心碎突刺","aphrodite","attack","攻击伤害提高，并施加虚弱，降低敌人伤害。",{"damage_pct":.5,"weak_duration":4.0,"weak_reduction":.3},["damage_pct"])
	_core(entries,"aphrodite_special","心碎投枪","aphrodite","special","特殊攻击伤害提高，并施加虚弱。",{"damage_pct":.8,"weak_duration":4.0,"weak_reduction":.3},["damage_pct"])
	_core(entries,"artemis_attack","致命突刺","artemis","attack","攻击伤害提高，有 15% 几率造成三倍暴击。",{"damage_pct":.2,"crit_chance":.15},["damage_pct"])
	_core(entries,"artemis_special","致命投枪","artemis","special","特殊攻击伤害提高，有 20% 几率造成三倍暴击。",{"damage_pct":.4,"crit_chance":.2},["damage_pct"])
	_core(entries,"ares_attack","痛苦诅咒","ares","attack","攻击施加厄运，延迟爆发一次伤害。",{"damage_pct":0.0,"doom_damage":50.0,"doom_delay":1.1},["doom_damage"])
	_core(entries,"ares_special","苦难诅咒","ares","special","特殊攻击施加厄运，延迟爆发一次伤害。",{"damage_pct":0.0,"doom_damage":60.0,"doom_delay":1.1},["doom_damage"])
	_core(entries,"dionysus_attack","醉酒突刺","dionysus","attack","攻击叠加宿醉，每半秒持续伤害，最多五层。",{"damage_pct":0.0,"hangover_damage":4.0,"hangover_duration":4.0,"hangover_interval":.5,"hangover_max_stacks":5},["hangover_damage"])
	_core(entries,"dionysus_special","醉酒投枪","dionysus","special","特殊攻击叠加宿醉，每半秒持续伤害，最多五层。",{"damage_pct":0.0,"hangover_damage":5.0,"hangover_duration":4.0,"hangover_interval":.5,"hangover_max_stacks":5},["hangover_damage"])
	_core(entries,"demeter_attack","冰霜突刺","demeter","attack","攻击伤害提高并叠加寒冷，减缓敌人移动和攻击。",{"damage_pct":.4,"chill_stacks":1,"chill_slow":.04,"chill_duration":5.0,"chill_max_stacks":10},["damage_pct"])
	_core(entries,"demeter_special","冰霜投枪","demeter","special","特殊攻击伤害提高并叠加寒冷。",{"damage_pct":.6,"chill_stacks":1,"chill_slow":.04,"chill_duration":5.0,"chill_max_stacks":10},["damage_pct"])
	_support(entries,"static_discharge","静电释放","zeus","雷击附加触电，敌人下次攻击时爆发伤害。",{"jolted_damage":40.0,"jolted_duration":8.0},[["zeus_attack","zeus_special"]],["jolted_damage"])
	_support(entries,"razor_shoals","剃刀浅滩","poseidon","击退附加割裂，敌人移动时持续受伤。",{"rupture_damage":10.0,"rupture_interval":.25,"rupture_duration":3.0},[["poseidon_attack","poseidon_special"]],["rupture_damage"])
	_support(entries,"blinding_flash","耀目闪光","athena","能反弹的攻击命中后使敌人暴露，来自背后的伤害提高。",{"exposed_bonus":.5,"exposed_duration":5.0},[["athena_attack","athena_special"]],["exposed_bonus"])
	_support(entries,"sweet_surrender","甜蜜投降","aphrodite","虚弱敌人承受更多伤害。",{"weak_damage_bonus":.1},[["aphrodite_attack","aphrodite_special"]],["weak_damage_bonus"])
	_support(entries,"pressure_points","致命要害","artemis","所有伤害获得少量暴击率。",{"global_crit":.02},[],["global_crit"])
	_support(entries,"impending_doom","厄运将至","ares","厄运伤害提高，但引爆延迟增加。",{"doom_bonus":.6,"doom_delay_bonus":.5},[["ares_attack","ares_special"]],["doom_bonus"])
	_support(entries,"numbing_sensation","麻痹感受","dionysus","宿醉敌人额外减速。",{"hangover_slow":.15},[["dionysus_attack","dionysus_special"]],["hangover_slow"])
	_support(entries,"arctic_blast","极地爆破","demeter","寒冷达到十层时引爆冰霜并清除层数。",{"chill_blast_damage":80.0,"chill_blast_radius":2.6},[["demeter_attack","demeter_special"]],["chill_blast_damage"])
	_duo(entries,"sea_storm","海上风暴","poseidon","zeus","击退同时引发额外雷击。",{"knockback_lightning":40.0},[["poseidon_attack","poseidon_special"],["zeus_attack","zeus_special"]])
	_duo(entries,"heart_rend","心碎重击","artemis","aphrodite","对虚弱敌人的暴击伤害额外提高。",{"weak_crit_bonus":1.5},[["artemis_attack","artemis_special"],["aphrodite_attack","aphrodite_special"]])
	_duo(entries,"merciful_end","仁慈终结","athena","ares","能反弹的攻击立即引爆已存在的厄运。",{"deflect_detonates_doom":true,"doom_detonation_bonus":40.0},[["athena_attack","athena_special"],["ares_attack","ares_special"]])
	_duo(entries,"curse_of_nausea","恶心诅咒","ares","dionysus","宿醉伤害间隔从 0.5 秒缩短至 0.35 秒。",{"hangover_interval_override":.35},[["ares_attack","ares_special"],["dionysus_attack","dionysus_special"]])
	return entries

static func _core(entries: Dictionary,id: String,title: String,god: String,slot: String,desc: String,effects: Dictionary,scales: Array) -> void:
	entries[id] = {"id":id,"name":title,"desc":desc,"color":GODS[god].color,"type":"core","slot":slot,"god":god,"god_name":GODS[god].name,"tags":[god,slot],"effects":effects,"scales":scales,"requires":[],"excludes":[]}

static func _support(entries: Dictionary,id: String,title: String,god: String,desc: String,effects: Dictionary,requirements: Array,scales: Array) -> void:
	_core(entries,id,title,god,"support",desc,effects,scales)
	entries[id].type = "support"; entries[id].requires = requirements

static func _duo(entries: Dictionary,id: String,title: String,god: String,other: String,desc: String,effects: Dictionary,requirements: Array) -> void:
	_support(entries,id,title,god,desc,effects,requirements,[])
	entries[id].type = "duo"; entries[id].tags = [god,other,"duo"]
	entries[id].color = "f5dc85"; entries[id].god_name = str(GODS[god].name)+" × "+str(GODS[other].name)

static func lookup(id: String) -> Dictionary:
	if _templates.is_empty(): _templates = _build_catalog()
	return _templates.get(id,{}).duplicate(true)

static func resolve(id: String,level: int = 1,rarity: int = 0) -> Dictionary:
	var entry: Dictionary = lookup(id)
	if entry.is_empty(): return entry
	entry.level = clampi(level,1,20); entry.rarity = clampi(rarity,0,3)
	if entry.type in ["hammer","duo"]: entry.level = 1; entry.rarity = 0
	entry.rarity_name = "锻造" if entry.type == "hammer" else ("双重" if entry.type == "duo" else RARITIES[entry.rarity])
	var factor: float = [1.0,1.3,1.6,2.0][entry.rarity] * (1.0+.35*sqrt(float(entry.level-1)))
	for key in entry.scales: entry.effects[key] = float(entry.effects[key])*factor
	var labels := {"damage_pct":"伤害加成","lightning_damage":"闪电伤害","bolt_damage":"落雷伤害","doom_damage":"厄运伤害","hangover_damage":"宿醉每层伤害","jolted_damage":"触电伤害","rupture_damage":"割裂伤害","exposed_bonus":"背刺加成","weak_damage_bonus":"易伤加成","global_crit":"暴击率","doom_bonus":"厄运加成","hangover_slow":"宿醉减速","chill_blast_damage":"冰爆伤害"}
	var percent_keys := ["damage_pct","exposed_bonus","weak_damage_bonus","global_crit","doom_bonus","hangover_slow"]
	var values: Array[String] = []
	for key in entry.scales:
		var value: float = entry.effects[key]
		values.append(str(labels.get(key,key))+" "+String.num(value*100 if key in percent_keys else value,1)+("%" if key in percent_keys else ""))
	if not values.is_empty(): entry.desc += "\n"+" · ".join(values)
	return entry

static func owned_entry(owned: Dictionary,id: String) -> Dictionary:
	if not owned.has(id): return {}
	var value = owned[id]
	return resolve(id,int(value.get("level",1)),int(value.get("rarity",0))) if value is Dictionary else resolve(id,int(value),0)

static func effects(owned: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in owned:
		var entry := owned_entry(owned,id)
		if not entry.is_empty(): result[id] = entry.effects
	return result

static func hammer_count(owned: Dictionary) -> int:
	var count := 0
	for id in owned:
		if lookup(id).get("type","") == "hammer": count += 1
	return count

static func eligible(id: String,owned: Dictionary,family: String = "spear") -> bool:
	var entry: Dictionary = lookup(id)
	if entry.is_empty(): return false
	var spear_family := family in ["spear","varatha","all",""] or GODS.has(family)
	if entry.type == "hammer":
		if not spear_family or owned.has(id) or hammer_count(owned) >= 2: return false
	elif entry.type == "duo" and owned.has(id): return false
	elif entry.slot == "special" and not spear_family: return false
	elif owned.has(id) and int(owned_entry(owned,id).level) >= 20: return false
	for conflict in entry.excludes:
		if owned.has(conflict): return false
	# Each group is OR; every group is required. A slot swap cannot silently
	# invalidate an already-owned support: existing supports remain but inactive.
	for group in entry.requires:
		var satisfied := false
		for prerequisite in group:
			if owned.has(prerequisite): satisfied = true; break
		if not satisfied: return false
	return true

static func active(id: String,owned: Dictionary) -> bool:
	var entry: Dictionary = lookup(id)
	if entry.is_empty() or not owned.has(id): return false
	for group in entry.requires:
		var satisfied := false
		for prerequisite in group:
			if owned.has(prerequisite): satisfied = true; break
		if not satisfied: return false
	return true

static func offers(owned: Dictionary,family: String,rng: RandomNumberGenerator,count: int = 3,hammer: bool = false) -> Array:
	var pool: Array = []
	var has_core := false
	for id in owned:
		if lookup(id).get("type","") == "core": has_core = true; break
	for id in catalog():
		var entry: Dictionary = lookup(id)
		if (entry.type == "hammer") != hammer or not eligible(id,owned,family): continue
		if not hammer and not has_core and entry.type != "core": continue
		if GODS.has(family) and not entry.tags.has(family): continue
		pool.append(id)
	var result: Array = []
	while not pool.is_empty() and result.size() < maxi(0,count):
		var candidates: Array = pool
		if not hammer and result.is_empty():
			var synergies: Array = []
			for candidate in pool:
				var entry := lookup(candidate)
				if entry.type == "duo" or (entry.type == "support" and not entry.requires.is_empty()): synergies.append(candidate)
			if not synergies.is_empty(): candidates = synergies
		var id := _weighted_choice(candidates,owned,rng,hammer)
		pool.erase(id)
		var old := owned_entry(owned,id)
		var roll := rng.randf()
		var rarity := 0 if hammer else (3 if roll < .02 else (2 if roll < .15 else (1 if roll < .5 else 0)))
		var offer := resolve(id,1 if old.is_empty() else int(old.level)+1,rarity if old.is_empty() else int(old.rarity))
		offer.upgrade = not old.is_empty()
		result.append(offer)
	return result

static func _weighted_choice(pool: Array,owned: Dictionary,rng: RandomNumberGenerator,hammer: bool) -> String:
	var weights: Array[float] = []
	var total := 0.0
	for id in pool:
		var entry := lookup(id)
		var weight := 1.0
		if not hammer:
			if entry.type == "duo": weight = 9.0
			elif entry.type == "support" and not entry.requires.is_empty(): weight = 5.0
			elif owned.has(id): weight = 5.0
			else:
				for previous in owned:
					if lookup(previous).get("god","") == entry.god: weight = 2.0; break
		weights.append(weight); total += weight
	var draw := rng.randf()*total
	for index in pool.size():
		draw -= weights[index]
		if draw <= 0: return str(pool[index])
	return str(pool.back())

static func acquire(owned: Dictionary,offer: Dictionary) -> Dictionary:
	var result := owned.duplicate(true)
	var id := str(offer.get("id",""))
	if not eligible(id,owned): return result
	var entry := resolve(id,int(offer.get("level",1)),int(offer.get("rarity",0)))
	if entry.slot in ["attack","special"]:
		for old in result.keys():
			if old != id and lookup(old).get("slot","") == entry.slot: result.erase(old)
	if owned.has(id):
		var previous := owned_entry(owned,id)
		entry.level = maxi(int(entry.level),mini(20,int(previous.level)+1))
		entry.rarity = maxi(int(entry.rarity),int(previous.rarity))
	result[id] = {"level":int(entry.level),"rarity":int(entry.rarity)}
	return result
