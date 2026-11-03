extends RefCounted
## Permanent, one-rank hero progression. This catalog owns no save or scene state.

const HERO_IDS := ["chrono","ember","flux"]
const NODE_IDS := ["vitality","mobility","survival","force","precision","mastery","efficiency","recovery","signature"]
const BRANCHES := ["survival","offense","ability"]
const COSTS := [180,360,650]
const BONUS_DEFAULTS := {"hp":0.0,"speed":0.0,"damage":0.0,"crit":0.0,"skill_cost_reduction":0.0,"skill_cooldown_reduction":0.0,"time_duration":0.0,"rush_range":0.0,"slam_damage":0.0,"slam_radius":0.0,"flame_radius":0.0,"gravity_radius":0.0,"gravity_damage":0.0,"guard_shield":0.0}
const CATALOG := {
	"chrono":[
		["恒时核心","最大生命 +15。",{"hp":15.0},"heart"],
		["流秒轻步","移动速度 +4%。",{"speed":.04},"move"],
		["时隙穿梭","疾影连击索敌及突进范围 +1.5 米。",{"rush_range":1.5},"rush"],
		["时刃调律","通用伤害 +8%。",{"damage":.08},"sword"],
		["定格弱点","暴击率 +4 个百分点。",{"crit":.04},"target"],
		["因果锋芒","通用伤害额外 +12%。",{"damage":.12},"blade"],
		["低耗时隙","F/L 英雄技能能量消耗降低 10%。",{"skill_cost_reduction":.10},"energy"],
		["循环复位","F/L 英雄技能冷却缩短 10%。",{"skill_cooldown_reduction":.10},"cycle"],
		["永恒一瞬","时裂领域持续时间 +0.8 秒。",{"time_duration":.8},"clock"]
	],
	"ember":[
		["炽心炉膛","最大生命 +20。",{"hp":20.0},"heart"],
		["逐焰轻步","移动速度 +5%。",{"speed":.05},"move"],
		["燎原回旋","赤焰回旋半径 +0.8 米。",{"flame_radius":.8},"flame"],
		["熔刃淬火","通用伤害 +10%。",{"damage":.10},"sword"],
		["灼点洞察","暴击率 +5 个百分点。",{"crit":.05},"target"],
		["焰陨重击","天坠焰击伤害额外 +25%。",{"slam_damage":.25},"blade"],
		["余火回收","F/L 英雄技能能量消耗降低 10%。",{"skill_cost_reduction":.10},"energy"],
		["连燃节律","F/L 英雄技能冷却缩短 10%。",{"skill_cooldown_reduction":.10},"cycle"],
		["燎原天坠","天坠焰击冲击半径 +1 米。",{"slam_radius":1.0},"flame"]
	],
	"flux":[
		["磁核护层","最大生命 +25。",{"hp":25.0},"heart"],
		["悬浮步伐","移动速度 +3%。",{"speed":.03},"move"],
		["六棱增幅","棱镜护卫护盾值 +20。",{"guard_shield":20.0},"shield"],
		["极性增幅","通用伤害 +8%。",{"damage":.08},"sword"],
		["磁轨校准","暴击率 +4 个百分点。",{"crit":.04},"target"],
		["引力湮灭","引力奇点伤害额外 +30%。",{"gravity_damage":.30},"gravity"],
		["闭环供能","F/L 英雄技能能量消耗降低 10%。",{"skill_cost_reduction":.10},"energy"],
		["频率重整","F/L 英雄技能冷却缩短 10%。",{"skill_cooldown_reduction":.10},"cycle"],
		["深空引力","引力奇点半径 +1 米。",{"gravity_radius":1.0},"orbit"]
	]
}

static func tree(hero: String) -> Array:
	if not CATALOG.has(hero): return []
	var result: Array = []
	for i in NODE_IDS.size():
		var depth: int = i%3+1
		var source: Array = CATALOG[hero][i]
		result.append({"id":NODE_IDS[i],"name":source[0],"desc":source[1],"branch":BRANCHES[i/3],"depth":depth,"parent":"" if depth==1 else NODE_IDS[i-1],"cost":COSTS[depth-1],"bonuses":source[2].duplicate(true),"icon":source[3],"max_rank":1})
	return result

static func defaults() -> Dictionary:
	var result: Dictionary = {}
	for hero in HERO_IDS:
		var nodes: Dictionary = {}
		for id in NODE_IDS: nodes[id] = false
		result[hero] = nodes
	return result

static func sanitize(raw: Variant) -> Dictionary:
	var result := defaults()
	if not raw is Dictionary: return result
	for hero in HERO_IDS:
		var source: Variant = raw.get(hero,{})
		if not source is Dictionary: continue
		# Catalog order is topological: a child is only kept if its parent survived.
		for entry in tree(hero):
			var value: Variant = source.get(entry.id,false)
			var enabled: bool = value if value is bool else ((value is int or value is float) and value == 1)
			var has_parent: bool = str(entry.parent).is_empty() or result[hero][entry.parent] == true
			result[hero][entry.id] = enabled and has_parent
	return result

static func bonuses(hero: String, progress: Dictionary) -> Dictionary:
	var result := BONUS_DEFAULTS.duplicate(true)
	if not CATALOG.has(hero): return result
	var full: Dictionary = progress if progress.has(hero) else {hero:progress}
	var clean := sanitize(full)
	for entry in tree(hero):
		if not clean[hero][entry.id]: continue
		for key in entry.bonuses:
			if result.has(key): result[key] = float(result[key])+float(entry.bonuses[key])
	return result
