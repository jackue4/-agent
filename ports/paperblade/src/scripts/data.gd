extends RefCounted
## Static game data: weapons, passives, enemies, waves.

const WEAPONS := {
	"sword": {"name": "御剑术", "icon": 0, "max": 8, "evo": "sword_evo", "req": "book",
		"desc": ["飞剑环绕周身，自动索敌斩击，穿透后回旋再斩", "飞剑 +1", "伤害 +6", "飞剑 +1，穿透 +1", "伤害 +6，冷却 -10%", "飞剑 +1", "穿透 +2，飞行速度 +20%", "飞剑 +2，伤害 +8"]},
	"sword_evo": {"name": "万剑归宗", "icon": 6, "max": 1,
		"desc": ["【进化】万剑齐出，无限穿透，命中后连锁追击下一名敌人"]},
	"wheel": {"name": "剑轮", "icon": 1, "max": 8, "evo": "wheel_evo", "req": "hourglass",
		"desc": ["金色剑轮绕身旋转，绞碎靠近的敌人", "剑刃 +1", "范围 +25%，转速 +30%", "伤害 +6，持续 +0.5秒", "剑刃 +1", "范围 +25%", "伤害 +6，持续 +1秒", "剑刃 +1"]},
	"wheel_evo": {"name": "烈阳剑阵", "icon": 7, "max": 1,
		"desc": ["【进化】烈阳剑阵永不停歇，焚尽周身一切"]},
	"rain": {"name": "天剑雨", "icon": 2, "max": 8,
		"desc": ["天降巨剑轰击敌群，造成范围伤害", "剑数 +1", "伤害 +10", "范围 +25%", "剑数 +1，冷却 -10%", "伤害 +10", "剑数 +2", "范围 +25%，伤害 +10"]},
	"crescent": {"name": "霜月斩", "icon": 3, "max": 8,
		"desc": ["向前挥出霜月剑气，减速并击退敌人", "额外向后方挥斩", "伤害 +8", "范围 +20%", "冷却 -15%", "伤害 +8", "范围 +20%", "四向剑气，伤害 +10"]},
	"thunder": {"name": "掌心雷", "icon": 4, "max": 8, "evo": "thunder_evo", "req": "cloud",
		"desc": ["雷符引动天雷，劈击随机敌人", "落雷 +1", "范围 +30%", "伤害 +12", "落雷 +1", "冷却 -15%", "落雷 +1", "伤害 +15，范围 +20%"]},
	"thunder_evo": {"name": "紫霄神雷", "icon": 8, "max": 1,
		"desc": ["【进化】紫霄神雷连环轰落，每道雷霆会连锁弹跳"]},
	"aura": {"name": "青灵护体", "icon": 5, "max": 8,
		"desc": ["青色灵气护身，持续伤害并震退周围敌人", "范围 +20%", "伤害 +3", "范围 +20%，频率提升", "伤害 +3", "范围 +20%", "伤害 +4", "范围 +20%，伤害 +4"]},
}

const BASE_WEAPONS := ["sword", "wheel", "rain", "crescent", "thunder", "aura"]

const PASSIVES := {
	"might": {"name": "蛮力", "icon": 0, "max": 5, "desc": "所有伤害 +10%"},
	"swift": {"name": "轻羽", "icon": 1, "max": 5, "desc": "飞行速度 +12%"},
	"amount": {"name": "双刃诀", "icon": 2, "max": 2, "desc": "所有武器数量 +1"},
	"area": {"name": "灵域", "icon": 3, "max": 5, "desc": "攻击范围 +10%"},
	"boots": {"name": "踏云靴", "icon": 4, "max": 5, "desc": "移动速度 +10%"},
	"magnet": {"name": "吸星石", "icon": 5, "max": 5, "desc": "拾取范围 +30%"},
	"heart": {"name": "龙心", "icon": 6, "max": 5, "desc": "最大生命 +20%"},
	"leaf": {"name": "回春叶", "icon": 7, "max": 5, "desc": "每秒回复 0.3 生命"},
	"book": {"name": "剑典", "icon": 8, "max": 5, "desc": "武器冷却 -8%"},
	"hourglass": {"name": "流沙漏", "icon": 9, "max": 5, "desc": "持续时间 +12%"},
	"cloud": {"name": "祥云", "icon": 10, "max": 5, "desc": "暴击率 +6%，幸运 +10%"},
	"armor": {"name": "玄甲", "icon": 11, "max": 5, "desc": "护甲 +1（受到伤害 -1）"},
}

const ENEMIES := {
	# 青云山门
	"slime": {"tex": "res://assets/enemy_slime.png", "ps": 0.0036, "hp": 9.0, "spd": 1.7, "dmg": 5.0, "xp": 1, "r": 0.45, "h": 0.9, "mass": 1.0, "col": Color(0.65, 0.4, 0.95), "anim": "bounce"},
	"bat": {"tex": "res://assets/enemy_bat.png", "ps": 0.0032, "hp": 6.0, "spd": 3.3, "dmg": 4.0, "xp": 1, "r": 0.4, "h": 1.5, "mass": 0.7, "col": Color(0.9, 0.2, 0.25), "anim": "fly"},
	"goblin": {"tex": "res://assets/enemy_goblin.png", "ps": 0.0039, "hp": 24.0, "spd": 2.4, "dmg": 8.0, "xp": 2, "r": 0.45, "h": 1.4, "mass": 1.3, "col": Color(0.45, 0.65, 0.25), "anim": "walk"},
	"knight": {"tex": "res://assets/enemy_knight.png", "ps": 0.0058, "hp": 90.0, "spd": 1.5, "dmg": 14.0, "xp": 6, "r": 0.6, "h": 2.0, "mass": 3.0, "col": Color(0.55, 0.55, 0.6), "anim": "walk"},
	"lantern": {"tex": "res://assets/prop_lantern.png", "ps": 0.0115, "hp": 1.0, "spd": 0.0, "dmg": 0.0, "xp": 0, "r": 0.4, "h": 1.6, "mass": 999.0, "col": Color(0.7, 0.7, 0.6), "anim": "none", "prop": true},
	# 幽冥鬼域
	"wisp": {"tex": "res://assets/enemy_wisp.png", "ps": 0.0029, "hp": 9.0, "spd": 1.9, "dmg": 5.0, "xp": 1, "r": 0.42, "h": 0.95, "mass": 0.9, "col": Color(0.45, 0.7, 1.0), "anim": "float"},
	"imp": {"tex": "res://assets/enemy_imp.png", "ps": 0.0037, "hp": 6.0, "spd": 3.4, "dmg": 4.0, "xp": 1, "r": 0.4, "h": 0.9, "mass": 0.7, "col": Color(0.7, 0.3, 0.85), "anim": "fly"},
	"jiangshi": {"tex": "res://assets/enemy_jiangshi.png", "ps": 0.0040, "hp": 26.0, "spd": 2.3, "dmg": 8.0, "xp": 2, "r": 0.45, "h": 1.45, "mass": 1.3, "col": Color(0.4, 0.4, 0.6), "anim": "hop"},
	"general": {"tex": "res://assets/enemy_general.png", "ps": 0.0059, "hp": 95.0, "spd": 1.5, "dmg": 15.0, "xp": 6, "r": 0.6, "h": 2.1, "mass": 3.0, "col": Color(0.3, 0.9, 0.6), "anim": "walk"},
	"ghostlantern": {"tex": "res://assets/prop_ghostlantern.png", "ps": 0.0115, "hp": 1.0, "spd": 0.0, "dmg": 0.0, "xp": 0, "r": 0.4, "h": 1.7, "mass": 999.0, "col": Color(0.5, 0.9, 1.0), "anim": "none", "prop": true},
	# 昆仑雪原
	"iceslime": {"tex": "res://assets/enemy_iceslime.png", "ps": 0.0031, "hp": 10.0, "spd": 1.8, "dmg": 5.0, "xp": 1, "r": 0.45, "h": 0.85, "mass": 1.0, "col": Color(0.6, 0.85, 1.0), "anim": "bounce"},
	"owl": {"tex": "res://assets/enemy_owl.png", "ps": 0.0030, "hp": 7.0, "spd": 3.5, "dmg": 4.0, "xp": 1, "r": 0.42, "h": 0.95, "mass": 0.7, "col": Color(0.85, 0.92, 1.0), "anim": "fly"},
	"wolf": {"tex": "res://assets/enemy_wolf.png", "ps": 0.0041, "hp": 26.0, "spd": 2.7, "dmg": 9.0, "xp": 2, "r": 0.45, "h": 1.5, "mass": 1.3, "col": Color(0.75, 0.8, 0.95), "anim": "walk"},
	"yeti": {"tex": "res://assets/enemy_yeti.png", "ps": 0.0061, "hp": 110.0, "spd": 1.45, "dmg": 16.0, "xp": 6, "r": 0.65, "h": 2.2, "mass": 3.5, "col": Color(0.6, 0.8, 1.0), "anim": "walk"},
	"snowlantern": {"tex": "res://assets/prop_snowlantern.png", "ps": 0.0116, "hp": 1.0, "spd": 0.0, "dmg": 0.0, "xp": 0, "r": 0.4, "h": 1.6, "mass": 999.0, "col": Color(0.9, 0.9, 0.85), "anim": "none", "prop": true},
}

## Maps. Waves are written with role names (slime / bat / goblin / knight / lantern)
## that each map translates into its own monsters.
const MAPS := [
	{"name": "青云山门", "sub": "Qingyun Gate", "preview": "res://assets/map_0.png",
		"desc": "山门石阶之上，妖物初现。适合初入仙途的修士。",
		"roles": {},
		"floor": Color(1.0, 1.0, 1.0), "bg": Color(0.17, 0.21, 0.2),
		"deco": [Color(0.55, 0.95, 0.8), Color(1.0, 0.85, 0.5)], "deco_a": 1.0,
		"props": [["res://assets/prop_tree.png", 2.9, 2.2, 0.3], ["res://assets/prop_bush.png", 0.9, 1.0, 0.15], ["res://assets/prop_rock.png", 1.1, 1.4, 0.55]],
		"prop_tint": Color(0.82, 0.9, 0.88),
		"boss": "骸骨剑王", "hp": 1.0, "dmg": 1.0, "spd": 1.0, "gold": 1.0, "stars": 1, "weather": "",
		"unlock": -1},
	{"name": "幽冥鬼域", "sub": "Netherworld", "preview": "res://assets/map_1.png",
		"desc": "彼岸花开，阴魂不散。僵尸跳跃逼近，鬼火成群。",
		"roles": {"slime": "wisp", "bat": "imp", "goblin": "jiangshi", "knight": "general", "lantern": "ghostlantern"},
		"floor": Color(0.95, 0.5, 1.05), "bg": Color(0.12, 0.07, 0.14),
		"deco": [Color(0.85, 0.35, 0.9), Color(1.0, 0.3, 0.35)], "deco_a": 1.15,
		"props": [["res://assets/prop_deadtree.png", 3.0, 2.2, 0.3], ["res://assets/prop_lily.png", 0.9, 0.9, 0.3], ["res://assets/prop_tomb.png", 1.8, 1.4, 0.4]],
		"prop_tint": Color(0.9, 0.85, 0.95),
		"boss": "幽冥鬼将", "hp": 1.35, "dmg": 1.15, "spd": 1.05, "gold": 1.3, "stars": 2, "weather": "embers",
		"unlock": 0},
	{"name": "昆仑雪原", "sub": "Kunlun Snowfield", "preview": "res://assets/map_2.png",
		"desc": "万里冰封，风雪迷眼。雪狼与冰魄巨猿镇守昆仑。",
		"roles": {"slime": "iceslime", "bat": "owl", "goblin": "wolf", "knight": "yeti", "lantern": "snowlantern"},
		"floor": Color(2.25, 2.2, 2.55), "bg": Color(0.55, 0.62, 0.7),
		"deco": [Color(0.75, 0.9, 1.0), Color(0.95, 0.95, 1.0)], "deco_a": 0.9,
		"props": [["res://assets/prop_pine.png", 3.0, 2.2, 0.35], ["res://assets/prop_plum.png", 1.5, 1.2, 0.25], ["res://assets/prop_icerock.png", 1.7, 1.6, 0.4]],
		"prop_tint": Color(1.0, 1.0, 1.0),
		"boss": "霜魄雪猿", "hp": 1.7, "dmg": 1.3, "spd": 1.1, "gold": 1.6, "stars": 3, "weather": "snow",
		"unlock": 1},
]
const UNLOCK_TIME := 300.0

## Out-of-run power-ups: [name, icon, max, base cost, desc]
const META := {
	"might": {"name": "炼体", "icon": "res://assets/item_0.png", "max": 5, "cost": 160, "desc": "伤害 +5%"},
	"armor": {"name": "金身", "icon": "res://assets/item_11.png", "max": 3, "cost": 300, "desc": "护甲 +1"},
	"maxhp": {"name": "龙血", "icon": "res://assets/item_6.png", "max": 5, "cost": 120, "desc": "最大生命 +10%"},
	"regen": {"name": "回春", "icon": "res://assets/item_7.png", "max": 5, "cost": 160, "desc": "每秒回复 +0.1"},
	"cd": {"name": "剑心", "icon": "res://assets/item_8.png", "max": 2, "cost": 450, "desc": "冷却 -3%"},
	"area": {"name": "灵域", "icon": "res://assets/item_3.png", "max": 2, "cost": 300, "desc": "范围 +5%"},
	"speed": {"name": "身法", "icon": "res://assets/item_4.png", "max": 2, "cost": 200, "desc": "移速 +5%"},
	"magnet": {"name": "摄物", "icon": "res://assets/item_5.png", "max": 2, "cost": 150, "desc": "拾取范围 +25%"},
	"luck": {"name": "气运", "icon": "res://assets/item_10.png", "max": 3, "cost": 300, "desc": "幸运 +10%"},
	"growth": {"name": "悟性", "icon": "res://assets/item_9.png", "max": 5, "cost": 450, "desc": "经验获取 +3%"},
	"greed": {"name": "聚财", "icon": "res://assets/coins.png", "max": 5, "cost": 100, "desc": "金币获取 +10%"},
	"reroll": {"name": "推演", "icon": "res://assets/skill_2.png", "max": 3, "cost": 400, "desc": "重新推演次数 +1"},
	"revival": {"name": "涅槃", "icon": "res://assets/skill_5.png", "max": 1, "cost": 2000, "desc": "死亡后原地复活一次"},
	"amount": {"name": "分光", "icon": "res://assets/item_2.png", "max": 1, "cost": 4000, "desc": "所有武器数量 +1"},
}

static func meta_cost(id: String, lvl: int, bought: int) -> int:
	return int(META[id].cost * (lvl + 1) * (1.0 + 0.08 * bought))


## [mix weights, minimum alive, batch interval]
const WAVES := [
	[{"slime": 1.0}, 20, 0.9],
	[{"slime": 0.6, "bat": 0.4}, 40, 0.8],
	[{"bat": 0.5, "goblin": 0.5}, 60, 0.7],
	[{"slime": 0.4, "goblin": 0.6}, 80, 0.6],
	[{"goblin": 0.7, "knight": 0.3}, 95, 0.6],
	[{"bat": 0.6, "goblin": 0.4}, 125, 0.5],
	[{"goblin": 0.6, "knight": 0.4}, 145, 0.5],
	[{"slime": 0.5, "knight": 0.5}, 175, 0.45],
	[{"bat": 0.4, "goblin": 0.3, "knight": 0.3}, 205, 0.4],
	[{"goblin": 0.4, "knight": 0.6}, 235, 0.4],
	[{"bat": 0.5, "knight": 0.5}, 265, 0.35],
	[{"goblin": 0.5, "knight": 0.5}, 295, 0.35],
	[{"slime": 0.3, "goblin": 0.3, "knight": 0.4}, 320, 0.3],
	[{"bat": 0.3, "knight": 0.7}, 345, 0.3],
	[{"goblin": 0.3, "knight": 0.7}, 370, 0.3],
]

const RUN_LENGTH := 900.0


static func xp_for(level: int) -> float:
	if level < 20:
		return 5.0 + (level - 1) * 10.0
	elif level < 40:
		return 195.0 + (level - 20) * 13.0
	return 455.0 + (level - 40) * 16.0
