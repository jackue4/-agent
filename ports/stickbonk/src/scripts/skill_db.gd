class_name SkillDB
extends RefCounted
## Roguelike skill definitions, gold combo cards, curses, move evolutions, rarity rolls + icon drawing.

const MAX := 5
const ACTIVE := ["shockwave", "lightning", "fireball", "orbit", "meteor", "clone", "nova", "frost"]
const LIST := {
	"shockwave": {"name": "震地波", "kind": "主动", "col": Color(0.3, 0.75, 1.0), "desc": "每隔几秒猛踏地面，冲击波把周围怪物全部震飞。", "awaken": "【觉醒】双重震爆：连续释放两道巨型冲击波！"},
	"lightning": {"name": "雷霆连锁", "kind": "主动·雷", "col": Color(1.0, 0.85, 0.15), "desc": "天雷劈向敌人并连锁弹跳，命中附加【感电】。", "awaken": "【觉醒】万雷天牢：同时释放两道连锁闪电！"},
	"fireball": {"name": "爆裂火球", "kind": "主动·火", "col": Color(1.0, 0.45, 0.1), "desc": "向最近的敌人投掷火球，爆炸附加【灼烧】。", "awaken": "【觉醒】炼狱三连：一次投出三枚巨型火球！"},
	"orbit": {"name": "旋风拳套", "kind": "主动·火", "col": Color(0.95, 0.3, 0.5), "desc": "燃烧的拳套环绕身体旋转，撞飞并点燃靠近的敌人。", "awaken": "【觉醒】拳皇风暴：六只拳套高速环绕！"},
	"meteor": {"name": "天降陨石", "kind": "主动·火", "col": Color(0.85, 0.4, 0.2), "desc": "陨石砸向怪物最密集处，范围毁灭并【挑飞】。", "awaken": "【觉醒】流星雨：一次砸下三颗陨石！"},
	"clone": {"name": "影分身", "kind": "主动", "col": Color(0.6, 0.35, 0.95), "desc": "召唤暗影分身，在敌群中连续瞬移斩击。", "awaken": "【觉醒】百影乱舞：分身斩击次数翻倍！"},
	"nova": {"name": "冲刺爆破", "kind": "主动", "col": Color(0.3, 0.95, 0.6), "desc": "冲刺结束时在落点引发爆炸。", "awaken": "【觉醒】流星冲刺：冲刺路径上连环爆炸！"},
	"frost": {"name": "冰霜新星", "kind": "主动·冰", "col": Color(0.45, 0.82, 1.0), "desc": "寒气爆发，【冰冻】周身敌人。重击冰冻目标触发冰爆！", "awaken": "【觉醒】绝对零度：冰冻范围翻倍，冰冻时间延长！", "secret": "frost"},
	"power": {"name": "怪力", "kind": "被动", "col": Color(0.95, 0.25, 0.2), "desc": "所有伤害 +22%。"},
	"fury": {"name": "狂暴连打", "kind": "被动", "col": Color(1.0, 0.6, 0.2), "desc": "攻击速度 +14%，连招更快。"},
	"crit": {"name": "致命一击", "kind": "被动", "col": Color(1.0, 0.9, 0.3), "desc": "暴击率 +9%，暴击伤害提升。"},
	"vamp": {"name": "吸血拳", "kind": "被动", "col": Color(0.75, 0.1, 0.25), "desc": "普攻每命中一个敌人回复生命。"},
	"vitality": {"name": "钢铁之躯", "kind": "被动", "col": Color(0.55, 0.6, 0.7), "desc": "最大生命 +25，并立即回复 40 生命。"},
	"swift": {"name": "疾风步", "kind": "被动", "col": Color(0.4, 0.9, 0.95), "desc": "移动速度 +10%，冲刺冷却缩短。"},
	"magnet": {"name": "经验磁铁", "kind": "被动", "col": Color(0.35, 0.55, 1.0), "desc": "拾取范围 +45%。"},
	"reach": {"name": "巨人之拳", "kind": "被动", "col": Color(0.9, 0.75, 0.5), "desc": "普攻范围 +14%，击退力度 +20%。"},
	"heavyfist": {"name": "重锤精通", "kind": "被动", "col": Color(0.95, 0.55, 0.15), "desc": "重锤砸地范围 +12%、伤害 +25%，冷却缩短。", "secret": "heavyfist"},
}
## Gold combo cards: offered once BOTH ingredients reach Lv3.
const COMBOS := {
	"combo_thunderflash": {"name": "雷光闪", "a": "lightning", "b": "nova", "col": Color(1.0, 0.88, 0.25), "desc": "冲刺化作雷光：路径上的敌人全部遭雷击并【感电】，落点引发雷爆。"},
	"combo_thousand": {"name": "千手观音", "a": "orbit", "b": "clone", "col": Color(1.0, 0.75, 0.2), "desc": "每 6 秒千掌齐发：金色掌影连续轰击周围所有敌人，分身 +1。"},
	"combo_quake": {"name": "天崩地裂", "a": "shockwave", "b": "heavyfist", "col": Color(0.95, 0.6, 0.25), "desc": "重锤砸地引发三重余震，大地开裂，把一切【挑飞】上天。"},
	"combo_firemeteor": {"name": "火流星", "a": "fireball", "b": "meteor", "col": Color(1.0, 0.45, 0.15), "desc": "火球爆炸时有几率召唤陨石坠落，陨石点燃落点所有敌人。"},
	"combo_bloodshadow": {"name": "血影", "a": "vamp", "b": "clone", "col": Color(0.85, 0.15, 0.25), "desc": "分身斩击为你吸血；受伤时自动召唤血色分身反击。"},
	"combo_gravity": {"name": "引力拳", "a": "magnet", "b": "shockwave", "col": Color(0.55, 0.4, 1.0), "desc": "每 5 秒在敌群中心制造引力奇点，吸住敌人后爆炸挑飞。"},
}
## Curse cards (from 混沌祭坛 / 每日挑战): a drawback + a perk; each curse raises crystal rewards 15%.
const CURSES := {
	"glass": {"name": "玻璃大炮", "desc": "伤害 +40%，但最大生命 -40%。"},
	"swarm": {"name": "怪潮", "desc": "怪物数量 +40%，经验 +30%。"},
	"frenzy": {"name": "狂躁", "desc": "怪物移速 +25%，击碎获得的铜钱翻倍。"},
	"nodrug": {"name": "断药", "desc": "不再掉落爱心，伤害 +20%。"},
	"blood": {"name": "以血还血", "desc": "暴击率 +15%，但每次暴击流失 0.5 生命。"},
}
## Move evolutions (秘籍「招式进化」): offered at Lv5 / 10 / 15 as a two-branch choice.
const EVO := {
	"fin_dragon": {"slot": "fin", "name": "升龙拳", "icon": "fireball", "col": Color(1.0, 0.45, 0.1), "desc": "第四击化作火焰升龙：挑飞更高并【灼烧】周围敌人。"},
	"fin_burst": {"slot": "fin", "name": "崩拳", "icon": "lightning", "col": Color(1.0, 0.85, 0.2), "desc": "第四击向前轰出雷霆冲击波，巨大击退并【感电】。"},
	"slam_meteor": {"slot": "slam", "name": "陨星坠", "icon": "meteor", "col": Color(0.95, 0.4, 0.2), "desc": "重锤范围 +35%，砸地点燃一圈烈焰。"},
	"slam_frost": {"slot": "slam", "name": "寒冰踏", "icon": "frost", "col": Color(0.45, 0.82, 1.0), "desc": "重锤砸地【冰冻】范围内所有敌人。"},
	"dash_wind": {"slot": "dash", "name": "疾风连踢", "icon": "swift", "col": Color(0.4, 0.9, 0.95), "desc": "冲刺飞踢连击两次，击杀敌人刷新冲刺冷却。"},
	"dash_thunder": {"slot": "dash", "name": "雷遁", "icon": "lightning", "col": Color(1.0, 0.9, 0.3), "desc": "冲刺无需按攻击，自动对路径敌人造成雷击并【感电】。"},
}
const RARITY := {
	"common": {"name": "普通", "col": Color(0.96, 0.94, 0.88), "lv": 1},
	"rare": {"name": "稀有", "col": Color(0.35, 0.6, 1.0), "lv": 2},
	"epic": {"name": "史诗", "col": Color(0.7, 0.35, 0.95), "lv": 3},
	"combo": {"name": "合体", "col": Color(1.0, 0.8, 0.15), "lv": 1},
	"curse": {"name": "诅咒", "col": Color(0.55, 0.1, 0.2), "lv": 1},
	"evo": {"name": "进化", "col": Color(0.3, 0.9, 0.55), "lv": 1},
}

static var banished := {}   ## per-run banished card ids


static func info(id: String) -> Dictionary:
	if LIST.has(id):
		return LIST[id]
	if COMBOS.has(id):
		var c: Dictionary = COMBOS[id].duplicate()
		c["kind"] = "合体技"
		return c
	if CURSES.has(id):
		var k: Dictionary = CURSES[id].duplicate()
		k["kind"] = "诅咒"
		k["col"] = Color(0.55, 0.1, 0.2)
		return k
	if EVO.has(id):
		var e: Dictionary = EVO[id].duplicate()
		e["kind"] = "招式进化"
		return e
	if id == "heal":
		return {"name": "回复", "kind": "补给", "col": Color(0.4, 0.9, 0.4), "desc": "回复 50 点生命。"}
	return {"name": id, "kind": "", "col": Color.WHITE, "desc": ""}


static func max_of(id: String) -> int:
	return MAX if LIST.has(id) else 1


static func available(id: String) -> bool:
	var d: Dictionary = LIST[id]
	if d.has("secret") and not Meta.owns("secrets", String(d["secret"])):
		return false
	return not banished.has(id)


## Combos whose ingredients are both Lv3+ and not owned yet.
static func combos_ready(owned: Dictionary) -> Array:
	var out := []
	for id in COMBOS.keys():
		var c: Dictionary = COMBOS[id]
		if owned.has(id) or banished.has(id):
			continue
		if int(owned.get(c["a"], 0)) >= 3 and int(owned.get(c["b"], 0)) >= 3:
			out.append(id)
	return out


static func roll_rarity(luck: int) -> String:
	var r := randf()
	if r < 0.05 + 0.015 * luck:
		return "epic"
	if r < 0.23 + 0.045 * luck:
		return "rare"
	return "common"


## Returns [{id, rar}] cards. `locked` (may be {}) keeps its slot.
static func roll(owned: Dictionary, n: int, luck: int = 0, locked: Dictionary = {}) -> Array:
	var out := []
	var taken := {}
	if not locked.is_empty():
		out.append(locked)
		taken[locked["id"]] = true
	var ready := combos_ready(owned)
	if not ready.is_empty() and out.size() < n:
		var cid: String = ready.pick_random()
		if not taken.has(cid):
			out.append({"id": cid, "rar": "combo"})
			taken[cid] = true
	var pool := []
	var weights := []
	var actives := 0
	for id in owned.keys():
		if ACTIVE.has(id):
			actives += 1
	for id in LIST.keys():
		var l := int(owned.get(id, 0))
		if l >= MAX or taken.has(id) or not available(id):
			continue
		if l == 0 and ACTIVE.has(id) and actives >= 5:
			continue
		pool.append(id)
		var w := 1.6 if l > 0 else 1.0
		if l == 0 and ACTIVE.has(id) and actives < 2:
			w = 2.2
		weights.append(w)
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += float(w)
		var r := randf() * total
		var idx := 0
		for i in weights.size():
			r -= float(weights[i])
			if r <= 0.0:
				idx = i
				break
		out.append({"id": pool[idx], "rar": roll_rarity(luck)})
		pool.remove_at(idx)
		weights.remove_at(idx)
	if out.is_empty():
		out.append({"id": "heal", "rar": "common"})
	return out


static func evo_cards(slot: String) -> Array:
	var out := []
	for id in EVO.keys():
		if EVO[id]["slot"] == slot:
			out.append({"id": id, "rar": "evo"})
	return out

static func draw_icon(ci: CanvasItem, id: String, c: Vector2, r: float) -> void:
	var col: Color = Color(0.4, 0.9, 0.4)
	if LIST.has(id):
		col = LIST[id]["col"]
	var ink := Ink.INK
	if EVO.has(id):
		id = String(EVO[id]["icon"])
	if CURSES.has(id):
		Ink.circle(ci, c, r, Color(0.3, 0.05, 0.12), maxf(3.0, r * 0.14))
		var sk := r / 30.0
		Ink.circle(ci, c + Vector2(0, -3) * sk, 13 * sk, Color(0.95, 0.92, 0.85), 2.5)
		ci.draw_circle(c + Vector2(-5, -4) * sk, 3.5 * sk, ink, true, -1.0, false)
		ci.draw_circle(c + Vector2(5, -4) * sk, 3.5 * sk, ink, true, -1.0, false)
		for k in 3:
			ci.draw_line(c + Vector2(-6 + k * 6, 8) * sk, c + Vector2(-6 + k * 6, 14) * sk, ink, 2.0)
		return
	var itex := Art.icon(id)
	if itex != null:
		ci.draw_circle(c + Vector2(r * 0.08, r * 0.1), r * 1.02, ink, true, -1.0, false)
		ci.draw_texture_rect(itex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
		return
	Ink.circle(ci, c, r, col, maxf(3.0, r * 0.14))
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.22, Color(1, 1, 1, 0.45), true, -1.0, false)
	var w := maxf(2.5, r * 0.13)
	var s := r / 30.0
	match id:
		"shockwave":
			for i in 3:
				ci.draw_arc(c + Vector2(0, 8 * s), (8.0 + i * 7.0) * s, PI * 1.1, PI * 1.9, 12, ink, w)
			ci.draw_line(c + Vector2(-16, 12) * s, c + Vector2(16, 12) * s, ink, w)
		"lightning":
			var b := PackedVector2Array([Vector2(4, -20), Vector2(-10, 2), Vector2(-1, 2), Vector2(-6, 20), Vector2(10, -4), Vector2(1, -4), Vector2(6, -20)])
			for i in b.size():
				b[i] = c + b[i] * s
			Ink.shape(ci, b, Color(1, 1, 0.85), w * 0.8)
		"fireball":
			var f := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				var rr := 11.0 * s
				var p := Vector2(cos(a), sin(a)) * rr
				if p.y < 0:
					p.y *= 1.0 + 0.9 * absf(sin(a)) * (1.0 - absf(cos(a)))
				f.append(c + p + Vector2(0, 4 * s))
			Ink.shape(ci, f, Color(1, 0.9, 0.3), w * 0.8)
		"orbit":
			ci.draw_arc(c, 15 * s, 0, TAU, 24, ink, w * 0.6)
			for i in 3:
				Ink.circle(ci, c + Vector2.from_angle(TAU * i / 3.0 - 0.5) * 15 * s, 5 * s, Color(1, 0.85, 0.85), w * 0.6)
		"meteor":
			for i in 3:
				ci.draw_line(c + Vector2(2 + i * 5, -6 - i * 4) * s, c + Vector2(18 + i * 5, -20 - i * 4) * s, ink, w * 0.7)
			Ink.circle(ci, c + Vector2(-4, 5) * s, 10 * s, Color(0.55, 0.45, 0.4), w * 0.8)
		"clone":
			Ink.circle(ci, c + Vector2(-7, -4) * s, 7 * s, Color(0.3, 0.15, 0.5), w * 0.6)
			Ink.circle(ci, c + Vector2(7, -4) * s, 7 * s, Color(1, 1, 1), w * 0.6)
			ci.draw_line(c + Vector2(-7, 3) * s, c + Vector2(-7, 18) * s, ink, w)
			ci.draw_line(c + Vector2(7, 3) * s, c + Vector2(7, 18) * s, ink, w)
		"nova":
			Ink.shape(ci, Ink.star(c, 17 * s, 7 * s, 6, 0.3), Color(1, 1, 0.8), w * 0.7)
		"power":
			var fr := Rect2(c + Vector2(-12, -10) * s, Vector2(24, 18) * s)
			ci.draw_rect(fr, Color(1, 0.85, 0.7))
			ci.draw_rect(fr, ink, false, w * 0.7)
			for i in 3:
				ci.draw_line(c + Vector2(-4 + i * 8, -10) * s, c + Vector2(-4 + i * 8, -2) * s, ink, w * 0.5)
			ci.draw_line(c + Vector2(-8, 8) * s, c + Vector2(-8, 18) * s, ink, w)
			ci.draw_line(c + Vector2(8, 8) * s, c + Vector2(8, 18) * s, ink, w)
		"fury":
			for i in 2:
				var o := Vector2(-8 + i * 12, 0) * s
				ci.draw_polyline(PackedVector2Array([c + o + Vector2(-6, -12) * s, c + o + Vector2(6, 0) * s, c + o + Vector2(-6, 12) * s]), ink, w * 1.2)
		"crit":
			ci.draw_arc(c, 13 * s, 0, TAU, 24, ink, w * 0.8)
			ci.draw_line(c + Vector2(-20, 0) * s, c + Vector2(20, 0) * s, ink, w * 0.7)
			ci.draw_line(c + Vector2(0, -20) * s, c + Vector2(0, 20) * s, ink, w * 0.7)
			ci.draw_circle(c, 4 * s, Color(0.9, 0.1, 0.1), true, -1.0, false)
		"vamp":
			var d := PackedVector2Array()
			for i in 14:
				var a := TAU * i / 14.0
				var p := Vector2(cos(a), sin(a)) * 10.0
				if p.y < 0:
					p.y *= 1.9 * (1.0 - absf(cos(a)) * 0.4)
				d.append(c + (p + Vector2(0, 5)) * s)
			Ink.shape(ci, d, Color(0.95, 0.15, 0.2), w * 0.7)
		"vitality":
			var sp := PackedVector2Array([Vector2(-14, -14), Vector2(14, -14), Vector2(12, 4), Vector2(0, 18), Vector2(-12, 4)])
			for i in sp.size():
				sp[i] = c + sp[i] * s
			Ink.shape(ci, sp, Color(0.85, 0.9, 1.0), w * 0.8)
			ci.draw_line(c + Vector2(0, -8) * s, c + Vector2(0, 8) * s, Color(0.9, 0.2, 0.2), w)
			ci.draw_line(c + Vector2(-7, 0) * s, c + Vector2(7, 0) * s, Color(0.9, 0.2, 0.2), w)
		"swift":
			for i in 3:
				ci.draw_line(c + Vector2(-18, -10 + i * 10) * s, c + Vector2(6 - i * 4, -10 + i * 10) * s, ink, w * 0.8)
			ci.draw_polyline(PackedVector2Array([c + Vector2(4, -14) * s, c + Vector2(16, 0) * s, c + Vector2(4, 14) * s]), ink, w)
		"magnet":
			ci.draw_arc(c + Vector2(0, -2) * s, 12 * s, 0, PI, 16, Color(0.9, 0.15, 0.2), w * 1.6)
			ci.draw_line(c + Vector2(-12, -2) * s, c + Vector2(-12, -14) * s, Color(0.9, 0.9, 0.9), w * 1.6)
			ci.draw_line(c + Vector2(12, -2) * s, c + Vector2(12, -14) * s, Color(0.9, 0.9, 0.9), w * 1.6)
		"heavyfist":
			Ink.circle(ci, c + Vector2(0, -2) * s, 13 * s, Color(1, 0.85, 0.7), w * 0.8)
			for i in 3:
				ci.draw_arc(c + Vector2(0, 14) * s, (6.0 + i * 6.0) * s, PI * 1.15, PI * 1.85, 10, ink, w * 0.6)
		"reach":
			Ink.circle(ci, c + Vector2(4, 0) * s, 12 * s, Color(1, 0.85, 0.7), w * 0.8)
			for i in 3:
				ci.draw_line(c + Vector2(-22, -8 + i * 8) * s, c + Vector2(-12, -8 + i * 8) * s, ink, w * 0.6)
		_:
			ci.draw_line(c + Vector2(0, -12) * s, c + Vector2(0, 12) * s, Color(0.9, 0.2, 0.2), w * 1.5)
			ci.draw_line(c + Vector2(-12, 0) * s, c + Vector2(12, 0) * s, Color(0.9, 0.2, 0.2), w * 1.5)
