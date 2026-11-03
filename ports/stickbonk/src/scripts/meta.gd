extends Node
## 道馆 meta progression: 碎片结晶 currency, 修炼 upgrades, 秘籍 unlocks, 门派, codex, achievements,
## run selection. Persisted as versioned JSON in user:// with an atomic tmp+rename write and a .bak fallback.

const VERSION := 1

const HEROES := {
	"red": {"name": "赤带拳师", "desc": "均衡型拳师，四段连击稳扎稳打。", "cost": 0, "hp": 100.0, "speed": 1.0, "crit": 0.0, "dash": 1.0, "w": 8.0, "band": Color(0.93, 0.17, 0.2), "scarf": Color(0.93, 0.17, 0.2), "head": Color(1, 1, 1)},
	"sumo": {"name": "相扑横纲", "desc": "生命 160、移速 -15%，重锤范围 +40%，冲刺化作肚皮冲撞。", "cost": 300, "hp": 160.0, "speed": 0.85, "crit": 0.0, "dash": 1.2, "w": 11.0, "band": Color(0.12, 0.1, 0.16), "scarf": Color(0.96, 0.94, 0.86), "head": Color(1, 0.93, 0.85)},
	"ninja": {"name": "影忍", "desc": "生命 75、移速 +20%、暴击 +15%，冲刺冷却 -35% 并甩出手里剑。", "cost": 400, "hp": 75.0, "speed": 1.2, "crit": 0.15, "dash": 0.65, "w": 7.0, "band": Color(0.55, 0.3, 0.9), "scarf": Color(0.55, 0.3, 0.9), "head": Color(0.2, 0.17, 0.26)},
	"drunk": {"name": "醉拳仙", "desc": "20% 醉步闪避，普攻有几率醉拳暴涨，每 20 秒喝酒回血。", "cost": 500, "hp": 100.0, "speed": 1.0, "crit": 0.04, "dash": 1.0, "w": 8.0, "band": Color(0.3, 0.75, 0.35), "scarf": Color(0.3, 0.75, 0.35), "head": Color(1, 0.85, 0.8)},
}
const WEAPONS := {
	"fist": {"name": "空手", "desc": "赤手空拳，没有加成也没有负担。", "cost": 0},
	"gloves": {"name": "拳套", "desc": "暴击率 +8%，暴击伤害 +40%。", "cost": 150},
	"nunchaku": {"name": "双节棍", "desc": "攻速 +25%，普攻伤害 -15%，每击追加一记回旋二段。", "cost": 250},
	"hammer": {"name": "大锤", "desc": "攻速 -20%，普攻伤害 +45% 且必定挑飞，重锤冷却 -40%。", "cost": 300},
	"staff": {"name": "长棍", "desc": "普攻范围 +40%、扫击弧度更大，击退 +30%。", "cost": 250},
}
const MAPS := {
	"dojo": {"name": "街头道场", "desc": "经典擂台。BOSS：巨拳魔王", "cost": 0, "boss": "boss", "ground": ""},
	"bamboo": {"name": "竹林", "desc": "周期刮起竹林狂风，把所有人吹向一侧。BOSS：史莱姆王", "cost": 200, "boss": "slimeking", "ground": "ground_bamboo"},
	"volcano": {"name": "火山", "desc": "岩浆池灼烧站在上面的一切，火山会周期喷发落石。BOSS：巨拳魔王", "cost": 350, "boss": "boss", "ground": "ground_volcano"},
	"ice": {"name": "冰原", "desc": "冰面打滑；暴风雪中敌人减速、攻击附带冰冻。BOSS：蝙蝠女王", "cost": 500, "boss": "batqueen", "ground": "ground_ice"},
}
const MODES := {
	"normal": {"name": "标准", "desc": "一局 5 分钟，2:00 / 4:00 各一只 BOSS，时间到死神降临收割。可选破坏协议难度。"},
	"daily": {"name": "每日挑战", "desc": "每天固定种子：固定角色/武器/地图/诅咒，5 分钟比拼击碎数。"},
	"speed": {"name": "狂潮", "desc": "怪物 1.5 倍密度，BOSS 每 90 秒一只，撑到死神降临结算奖励 +50%。"},
}
const UPGRADES := {
	"hp": {"name": "体魄", "desc": "最大生命 +8", "max": 5, "cost": 40, "step": 30},
	"atk": {"name": "力量", "desc": "全部伤害 +5%", "max": 5, "cost": 50, "step": 35},
	"spd": {"name": "身法", "desc": "移动速度 +4%", "max": 5, "cost": 40, "step": 30},
	"wis": {"name": "悟性", "desc": "经验获取 +6%", "max": 5, "cost": 45, "step": 30},
	"luck": {"name": "气运", "desc": "稀有/史诗卡概率提升", "max": 5, "cost": 50, "step": 40},
	"gold": {"name": "财运", "desc": "结算结晶 +10%", "max": 5, "cost": 60, "step": 40},
	"reroll": {"name": "刷新", "desc": "每局刷新卡牌次数 +1", "max": 3, "cost": 60, "step": 60},
	"banish": {"name": "封印", "desc": "每局封印卡牌次数 +1", "max": 3, "cost": 60, "step": 60},
	"lock": {"name": "锁定", "desc": "解锁卡牌锁定（保留到下次升级）", "max": 1, "cost": 120, "step": 0},
	"revive": {"name": "不屈", "desc": "每局一次倒地复活（50% 生命）", "max": 1, "cost": 250, "step": 0},
}
const SECTS := {
	"none": {"name": "无门无派", "desc": "自由之身。", "cost": 0, "col": Color(0.7, 0.7, 0.7)},
	"flame": {"name": "烈焰门", "desc": "命中 15% 附加灼烧，灼烧伤害 +50%。", "cost": 150, "col": Color(1.0, 0.45, 0.1)},
	"thunder": {"name": "雷霆宗", "desc": "命中 15% 附加感电，雷暴反应伤害 +50%。", "cost": 150, "col": Color(1.0, 0.85, 0.15)},
	"frost": {"name": "寒霜派", "desc": "命中 10% 附加冰冻，冰爆伤害 +50%。", "cost": 150, "col": Color(0.45, 0.8, 1.0)},
	"vajra": {"name": "金刚寺", "desc": "最大生命 +20，受到伤害 -15%。", "cost": 150, "col": Color(0.95, 0.75, 0.3)},
}
const SECRETS := {
	"frost": {"name": "寒冰掌", "desc": "解锁主动技能：冰霜新星，冻结周身敌人。", "cost": 150},
	"heavyfist": {"name": "重锤精通", "desc": "解锁被动：重锤范围与伤害提升（合体技「天崩地裂」原料）。", "cost": 100},
	"evo": {"name": "招式进化", "desc": "Lv5/10/15 时可进化第四击、重锤或冲刺（二选一分支）。", "cost": 200},
}
const ACHIEVEMENTS := {
	"first": {"name": "初出茅庐", "desc": "完成第一局", "reward": 20},
	"kills1k": {"name": "千人斩", "desc": "累计击碎 1000 只怪物", "reward": 60},
	"combo100": {"name": "连击大师", "desc": "单局达到 100 连击", "reward": 40},
	"boss": {"name": "魔王克星", "desc": "击败巨拳魔王", "reward": 60},
	"slimeking": {"name": "果冻粉碎机", "desc": "击败史莱姆王", "reward": 60},
	"batqueen": {"name": "黎明之拳", "desc": "击败蝙蝠女王", "reward": 60},
	"reactions": {"name": "元素宗师", "desc": "触发全部四种元素反应", "reward": 50},
	"combo_card": {"name": "合体技！", "desc": "获得任意一张合体金卡", "reward": 40},
	"combo_all": {"name": "六合一统", "desc": "图鉴集齐全部 6 张合体金卡", "reward": 120},
	"heat5": {"name": "破坏狂", "desc": "达成破坏协议 5", "reward": 100},
	"speed": {"name": "狂潮之王", "desc": "狂潮模式撑到死神降临", "reward": 60},
	"survive10": {"name": "时辰已到", "desc": "坚持 5 分钟直到死神降临", "reward": 50},
	"curse3": {"name": "与魔共舞", "desc": "单局背负 3 个诅咒", "reward": 50},
	"all_heroes": {"name": "一代宗师", "desc": "解锁全部角色", "reward": 80},
}
const REACTIONS := ["爆燃", "雷暴", "冰爆", "空中追击"]
## 破坏协议 ladder: heat N stacks the first N modifiers. Clearing heat N (boss kill or 5:00) unlocks N+1.
const PROTOCOL := ["怪物生命 +25%", "怪物移速 +10%", "精英怪更频繁", "受到伤害 +25%", "BOSS 提前登场", "怪物数量 +30%", "回复效果减半", "怪物生命再 +50%"]

var data := {}
var no_save := false   ## self-test sandbox: never touch the real save
var last_reward := 0
var last_new_ach: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = defaults()
	load_save()


func defaults() -> Dictionary:
	return {
		"version": VERSION, "crystals": 0, "total_crystals": 0,
		"upgrades": {}, "secrets": {}, "heroes": {"red": true}, "weapons": {"fist": true}, "maps": {"dojo": true}, "sects": {"none": true},
		"sel": {"hero": "red", "weapon": "fist", "map": "dojo", "mode": "normal", "heat": 0, "sect": "none"},
		"max_heat": 0, "codex": {"enemies": {}, "skills": {}, "combos": {}, "reactions": {}},
		"ach": {}, "stats": {"runs": 0, "kills": 0, "bosses": 0, "best_time": 0, "best_combo": 0},
		"daily": {}, "speed_best": 0,
		"settings": {"sfx": 80, "shake": 100, "dmg_num": true, "hitstop": true, "quality": "auto", "fps": false},
	}


# ---------------------------------------------------------------- persistence
func save() -> void:
	if no_save:
		return
	var txt := JSON.stringify(data)
	var f := FileAccess.open("user://stickbonk_save.tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()
	if FileAccess.file_exists("user://stickbonk_save.json"):
		DirAccess.copy_absolute("user://stickbonk_save.json", "user://stickbonk_save.bak")
	if DirAccess.rename_absolute("user://stickbonk_save.tmp", "user://stickbonk_save.json") != OK:
		var g := FileAccess.open("user://stickbonk_save.json", FileAccess.WRITE)
		if g != null:
			g.store_string(txt)
			g.close()


func load_save() -> void:
	var d = _read("main")
	if not (d is Dictionary):
		d = _read("bak")
	if d is Dictionary:
		data = migrate(d)
	apply_settings()


## Pushes the persisted settings into the live game (called on load and on every change).
func apply_settings() -> void:
	var s: Dictionary = data["settings"]
	var v := clampf(float(s.get("sfx", 80)) / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(0, v <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))
	G.shake_k = clampf(float(s.get("shake", 100)) / 100.0, 0.0, 1.0)
	G.dmg_numbers = bool(s.get("dmg_num", true))
	G.hitstop_on = bool(s.get("hitstop", true))
	G.show_fps = bool(s.get("fps", false))
	var q := String(s.get("quality", "auto"))
	G.low = G.auto_low if q == "auto" else q == "low"
	G.MAX_SHARDS = 150 if G.low else 280


func _read(which: String):
	var txt := ""
	if which == "main" and FileAccess.file_exists("user://stickbonk_save.json"):
		txt = FileAccess.get_file_as_string("user://stickbonk_save.json")
	elif which == "bak" and FileAccess.file_exists("user://stickbonk_save.bak"):
		txt = FileAccess.get_file_as_string("user://stickbonk_save.bak")
	if txt == "":
		return null
	return JSON.parse_string(txt)


## Fills every missing key from the defaults (so older saves keep working) and stamps the version.
func migrate(d: Dictionary) -> Dictionary:
	var out := _merge(defaults(), d)
	out["version"] = VERSION
	return out


func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = _merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


# ---------------------------------------------------------------- queries
func crystals() -> int:
	return int(data["crystals"])


func up(id: String) -> int:
	return int(data["upgrades"].get(id, 0))


func up_cost(id: String) -> int:
	var u: Dictionary = UPGRADES[id]
	return int(u["cost"]) + int(u["step"]) * up(id)


func owns(group: String, id: String) -> bool:
	return bool(data[group].get(id, false))


func sel(k: String):
	return data["sel"][k]


func set_sel(k: String, v) -> void:
	data["sel"][k] = v
	save()


func spend(n: int) -> bool:
	if crystals() < n:
		return false
	data["crystals"] = crystals() - n
	return true


func buy_upgrade(id: String) -> bool:
	if up(id) >= int(UPGRADES[id]["max"]) or not spend(up_cost(id)):
		return false
	data["upgrades"][id] = up(id) + 1
	save()
	return true


## group: heroes / weapons / maps / sects / secrets
func buy(group: String, id: String) -> bool:
	if owns(group, id):
		return true
	var table: Dictionary = {"heroes": HEROES, "weapons": WEAPONS, "maps": MAPS, "sects": SECTS, "secrets": SECRETS}[group]
	if not spend(int(table[id]["cost"])):
		return false
	data[group][id] = true
	if group == "heroes" and data["heroes"].size() >= HEROES.size():
		unlock_ach("all_heroes")
	save()
	return true


func add_crystals(n: int) -> void:
	data["crystals"] = crystals() + n
	data["total_crystals"] = int(data["total_crystals"]) + n


# ---------------------------------------------------------------- codex & achievements
func codex_add(group: String, id: String, n: int = 1) -> void:
	var c: Dictionary = data["codex"][group]
	c[id] = int(c.get(id, 0)) + n


func codex_has(group: String, id: String) -> bool:
	return int(data["codex"][group].get(id, 0)) > 0


func unlock_ach(id: String) -> bool:
	if bool(data["ach"].get(id, false)) or not ACHIEVEMENTS.has(id):
		return false
	data["ach"][id] = true
	add_crystals(int(ACHIEVEMENTS[id]["reward"]))
	last_new_ach.append(id)
	if G.main != null:
		G.banner("成就达成：" + String(ACHIEVEMENTS[id]["name"]) + "  +" + str(ACHIEVEMENTS[id]["reward"]) + " 结晶", 2.6)
	return true


func check_reactions_ach() -> void:
	for r in REACTIONS:
		if not codex_has("reactions", r):
			return
	unlock_ach("reactions")


# ---------------------------------------------------------------- modes
func today() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


## Deterministic loadout for one calendar day (every player gets the same run).
func daily_config(day: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 7919 + 17
	var hk := HEROES.keys()
	var wk := WEAPONS.keys()
	var mk := MAPS.keys()
	var ck := SkillDB.CURSES.keys()
	return {"seed": day, "hero": hk[rng.randi() % hk.size()], "weapon": wk[rng.randi() % wk.size()], "map": mk[rng.randi() % mk.size()], "curse": ck[rng.randi() % ck.size()]}


## Crystals earned by a finished run (all multipliers in one place so the end screen can explain them).
func run_reward(r: Dictionary) -> int:
	var base := float(r.get("kills", 0)) * 0.2 + float(r.get("time", 0.0)) / 6.0 + float(r.get("bosses", 0)) * 40.0 + float(r.get("protocol", 0)) * 30.0
	if bool(r.get("survived", false)):
		base += 40.0
	if bool(r.get("speed_win", false)):
		base *= 1.5
	var mult := (1.0 + 0.25 * float(r.get("heat", 0))) * (1.0 + 0.1 * up("gold")) * (1.0 + 0.15 * float(r.get("curses", 0)))
	if String(r.get("mode", "normal")) == "daily":
		mult *= 1.5
	return int(round(base * mult))


## Applies a finished run to the save; returns crystals earned.
func finish_run(r: Dictionary) -> int:
	last_new_ach.clear()
	var earned := run_reward(r)
	add_crystals(earned)
	var st: Dictionary = data["stats"]
	st["runs"] = int(st["runs"]) + 1
	st["kills"] = int(st["kills"]) + int(r.get("kills", 0))
	st["bosses"] = int(st["bosses"]) + int(r.get("bosses", 0))
	st["best_time"] = maxi(int(st["best_time"]), int(r.get("time", 0.0)))
	st["best_combo"] = maxi(int(st["best_combo"]), int(r.get("combo", 0)))
	var heat := int(r.get("protocol", 0))
	if heat > 0:
		data["max_heat"] = maxi(int(data["max_heat"]), heat)
	if String(r.get("mode", "")) == "daily":
		var key := str(r.get("seed", today()))
		data["daily"][key] = maxi(int(data["daily"].get(key, 0)), int(r.get("kills", 0)))
	if String(r.get("mode", "")) == "speed" and bool(r.get("speed_win", false)):
		data["speed_best"] = maxi(int(data["speed_best"]), int(r.get("kills", 0)))
	unlock_ach("first")
	if int(st["kills"]) >= 1000:
		unlock_ach("kills1k")
	if int(r.get("combo", 0)) >= 100:
		unlock_ach("combo100")
	if bool(r.get("survived", false)):
		unlock_ach("survive10")
	if int(data["max_heat"]) >= 5:
		unlock_ach("heat5")
	if bool(r.get("speed_win", false)):
		unlock_ach("speed")
	if int(r.get("curses", 0)) >= 3:
		unlock_ach("curse3")
	last_reward = earned
	save()
	return earned
