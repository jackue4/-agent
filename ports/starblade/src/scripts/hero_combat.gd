extends RefCounted
## Hero-owned skills compose with CombatArts without advancing its clock twice.
## All impacts use the normal attack-boon path; no global time scale is changed.
const Heroes = preload("res://scripts/heroes.gd")
var g
var hero_id := "chrono"
var shield_amount := 0.0
var error := ""
var phase_invulnerable: bool:
	get: return _raid_valid() and _left("sky_slam") > 0 and _slam_elapsed >= .06 and _slam_elapsed < .48 and not _slam_impacted
var controls_movement: bool:
	get: return _left("sky_slam") > 0
var visual_height: float:
	get:
		if not controls_movement or _slam_impacted: return 0.0
		if _slam_elapsed < .18: return 6.5*sin(clampf(_slam_elapsed/.18,0,1)*PI*.5)
		if _slam_elapsed < .28: return 6.5
		return 6.5*(1.0-smoothstep(.28,.48,_slam_elapsed))
var slam_position := Vector3.ZERO
var _slam_origin := Vector3.ZERO
var _slam_elapsed := 0.0
var _slam_impacted := false
var _slam_hits: Dictionary = {}
var _slam_mark: Node3D
var gravity_position := Vector3.ZERO
var _cooldowns: Dictionary = {}
var _remaining: Dictionary = {}
var _flame_elapsed := 0.0
var _flame_pulses := 0
var _gravity_elapsed := 0.0
var _gravity_pulses := 0
var _skill_defs: Dictionary = {}
var _talents: Dictionary = {}
var _field_fx: Node3D
var _guard_fx: Node3D

func _init(controller) -> void:
	g = controller
	_cache_metadata()

func set_hero(id: String) -> bool:
	if not Heroes.valid(id): error = "未知英雄"; return false
	reset()
	hero_id = id
	_talents.clear()
	if g != null and g.arts != null: g.arts.configure_talents({})
	_cache_metadata()
	return true

func set_talents(bonuses: Dictionary) -> void:
	_talents = bonuses.duplicate(true)
	_cache_metadata()
	if g != null and g.arts != null: g.arts.configure_talents(_talents)

func _cache_metadata() -> void:
	_skill_defs.clear()
	var metadata: Dictionary = Heroes.get_hero(hero_id)
	for slot in ["primary","secondary"]:
		var definition: Dictionary = metadata[slot].duplicate(true)
		definition.cost *= 1.0-clampf(float(_talents.get("skill_cost_reduction",0)),0,.8)
		definition.cooldown *= 1.0-clampf(float(_talents.get("skill_cooldown_reduction",0)),0,.8)
		if definition.id == "time_stop": definition.duration += maxf(0,float(_talents.get("time_duration",0)))
		_skill_defs[definition.id] = definition

func state(slot: String) -> Dictionary:
	var index := _slot_index(slot)
	if index < 0: return {}
	var result: Dictionary = _skill_defs[Heroes.get_hero(hero_id)[slot].id].duplicate(true)
	var id: String = result.id
	result.id = id; result.cd = float(_cooldowns.get(id,0)); result.left = _left(id)
	if g != null and g.arts != null:
		if id == "time_stop":
			result.cd = g.arts.time_cd; result.left = g.arts.time_left
		elif id == "rush":
			result.cd = g.arts.rush_cd; result.left = float(g.arts.get("_rush_left")) if g.arts.rushing else 0.0
			result.hits = g.arts.rush_hits.size()
	result.active = float(result.left) > 0
	result.slot = slot; result.hero = hero_id
	if id == "sky_slam":
		result.height = visual_height; result.landing = slam_position
		result.radius = _slam_radius(); result.damage = _slam_damage()
		result.impact_at = .48; result.elapsed = _slam_elapsed
	if id == "flame_spin": result.radius = _flame_radius()
	if id == "gravity_well": result.radius = _gravity_radius(); result.damage_multiplier = _gravity_damage_scale()
	if id == "prism_guard": result.shield = shield_amount; result.shield_max = 40.0+float(_talents.get("guard_shield",0))
	if id == "rush" and g != null and g.arts != null:
		result.range = g.arts.tuning.rush_range; result.damage = g.arts.tuning.rush_damage
	if not _talents.is_empty():
		match id:
			"time_stop": result.desc = result.desc.replace("3 秒",String.num(float(result.duration),1)+" 秒")
			"sky_slam": result.desc = result.desc.replace("4.8 米",String.num(_slam_radius(),1)+" 米").replace("90 基础",String.num(_slam_damage(),1)+" 基础")
			"rush":
				result.desc = result.desc.replace("普通段 32、第五段 48", "普通段 %s、第五段 %s" % [String.num(float(g.arts.tuning.rush_damage),1),String.num(float(g.arts.tuning.rush_final_damage),1)])
			"flame_spin": result.desc = result.desc.replace("4.1 米",String.num(_flame_radius(),1)+" 米")
			"gravity_well":
				result.desc = result.desc.replace("4.8 米",String.num(_gravity_radius(),1)+" 米").replace("造成 8 基础", "造成 %s 基础" % String.num(8.0*_gravity_damage_scale(),1)).replace("爆破 55", "爆破 %s" % String.num(55.0*_gravity_damage_scale(),1))
			"prism_guard": result.desc = result.desc.replace("40 临时", "%d 临时" % int(result.shield_max))
		result.desc += "\n当前：消耗 %s 能量 · 冷却 %s 秒" % [String.num(float(result.cost),1),String.num(float(result.cooldown),1)]
		if id == "time_stop": result.desc += " · 时停 %s 秒" % String.num(float(result.duration),1)
		if result.has("distance"): result.desc += " · 距离 %s 米" % String.num(float(result.distance),1)
		if result.has("radius"): result.desc += " · 半径 %s 米" % String.num(float(result.radius),1)
		if result.has("shield_max"): result.desc += " · 临时护盾 %d" % int(result.shield_max)
	return result

func trigger(slot: String) -> bool:
	error = ""
	if not _raid_valid(): error = "当前无法使用技能"; return false
	if controls_movement: error = "天坠焰击施放中"; return false
	var entry := state(slot)
	if entry.is_empty(): error = "无效技能槽"; return false
	if float(entry.cd) > .00001 or bool(entry.active): error = "技能正在冷却"; return false
	if g.mana < float(entry.cost): error = "能量不足"; return false
	var id: String = entry.id
	if id == "time_stop": return g.arts.trigger_time_stop()
	if id == "rush": return g.arts.trigger_rush(true)
	if id == "sky_slam":
		if g.arts != null and g.arts.rushing: error = "突进尚未结束"; return false
		slam_position = _select_slam_position()
	if id == "gravity_well":
		var from: Vector3 = g.player.position
		gravity_position = _safe_end(from,from+_aim()*5.0,.2)
		if g.world.line_blocked(from,gravity_position): error = "无法在遮挡后放置引力场"; return false
	_spend(id)
	match id:
		"sky_slam":
			_slam_origin = g.player.position; _slam_elapsed = 0; _slam_impacted = false; _slam_hits.clear()
			_slam_mark = _fx("slam_mark",slam_position,Color("ff9c5b"),_aim(),_slam_radius()/4.8)
			_sound("spear_throw",-16,.7)
		"flame_spin":
			_flame_elapsed = 0; _flame_pulses = 0
			_flame_pulse()
		"gravity_well":
			_gravity_elapsed = 0; _gravity_pulses = 0
			_field_fx = _fx("gravity_well",gravity_position,Color("b58cff"),_aim(),_gravity_radius()/4.8)
			_sound("spin_charge",-16,.55)
		"prism_guard":
			shield_amount = 40.0+float(_talents.get("guard_shield",0))
			_guard_fx = _fx("prism_guard",g.player.position,Color("a6c9ff"),_aim(),1.0)
			_sound("heal_pickup",-15,1.35)
			_reflect_guard()
	return true

func tick(delta: float) -> void:
	if g == null: return
	if not is_instance_valid(g.player) or g.hp <= 0: cancel_active(); return
	if g.mode != "raid": return # Modal time is preserved; root resets on exit.
	var remaining := maxf(0,delta)
	while remaining > .000001:
		var dt := minf(remaining,1.0/120.0)
		_tick_step(dt)
		remaining -= dt
		if not _raid_valid():
			if g.hp <= 0: cancel_active()
			return

func _tick_step(dt: float) -> void:
	for id in _cooldowns: _cooldowns[id] = maxf(0,float(_cooldowns[id])-dt)
	if _left("sky_slam") > 0: _tick_slam(dt)
	if _left("flame_spin") > 0:
		var active_dt := minf(dt,_left("flame_spin"))
		_flame_elapsed += active_dt
		_remaining.flame_spin = maxf(0,_left("flame_spin")-dt)
		while _flame_pulses < 3 and _flame_elapsed+.000001 >= float(_flame_pulses)*.16:
			_flame_pulse()
			if not _raid_valid(): return
	if _left("gravity_well") > 0:
		var active_dt := minf(dt,_left("gravity_well"))
		_gravity_elapsed += active_dt
		_remaining.gravity_well = maxf(0,_left("gravity_well")-dt)
		_pull_gravity(active_dt)
		while _gravity_pulses < 5 and _gravity_elapsed+.000001 >= float(_gravity_pulses+1)*.6:
			_gravity_pulses += 1
			_area_hit(gravity_position,_gravity_radius(),8.0*_gravity_damage_scale(),{})
			if not _raid_valid(): return
		if _left("gravity_well") <= .000001:
			_remaining.gravity_well = 0
			_clear_fx(_field_fx); _field_fx = null
			_area_hit(gravity_position,_gravity_radius(),55.0*_gravity_damage_scale(),{})
			_fx("gravity_burst",gravity_position,Color("d5b8ff"),_aim(),_gravity_radius()/4.8)
			_sound("impact",-15,.6)
	if _left("prism_guard") > 0:
		_remaining.prism_guard = maxf(0,_left("prism_guard")-dt)
		if _left("prism_guard") <= .000001:
			_remaining.prism_guard = 0; shield_amount = 0
			_clear_fx(_guard_fx); _guard_fx = null
		else:
			_reflect_guard()
			if is_instance_valid(_guard_fx): _guard_fx.global_position = g.player.global_position

func _spend(id: String) -> void:
	g.mana -= float(_skill_defs[id].cost)
	_cooldowns[id] = float(_skill_defs[id].cooldown)
	_remaining[id] = float(_skill_defs[id].duration)

func _select_slam_position() -> Vector3:
	var start: Vector3 = g.player.position
	var selected: Vector3 = _safe_end(start,start+_aim()*4.0,.42)
	var nearest := 7.0001
	for enemy in g.enemies:
		if not _valid_enemy(enemy): continue
		var point: Vector3 = enemy.node.position; point.y = start.y
		var distance := start.distance_to(point)
		if distance > 7.0 or distance >= nearest or g.world.line_blocked(start,point): continue
		if _safe_end(start,point,.42).distance_to(point) > .08: continue
		selected = point; nearest = distance
	return selected

func _tick_slam(dt: float) -> void:
	_slam_elapsed += minf(dt,_left("sky_slam"))
	_remaining.sky_slam = maxf(0,_left("sky_slam")-dt)
	if not _slam_impacted:
		var desired := _slam_origin.lerp(slam_position,smoothstep(.06,.48,_slam_elapsed))
		var safe := _safe_end(g.player.position,desired,.42)
		g._move_actor(g.player,safe-g.player.position,.42)
		if _slam_elapsed+.000001 >= .48:
			_slam_impacted = true
			# Recheck the actual landing if dynamic cover appeared during the jump.
			slam_position = g.player.position
			_clear_fx(_slam_mark); _slam_mark = null
			_fx("sky_slam",slam_position,Color("ffad66"),_aim(),_slam_radius()/4.8)
			if g.has_method("on_slam_impact"): g.on_slam_impact(slam_position,_slam_radius())
			else: _sound("impact",-14,.55)
			_area_hit(slam_position,_slam_radius(),_slam_damage(),_slam_hits)
	if _left("sky_slam") <= .000001:
		_remaining.sky_slam = 0
		_clear_fx(_slam_mark); _slam_mark = null

func _slam_radius() -> float:
	return 4.8+maxf(0,float(_talents.get("slam_radius",0)))

func _slam_damage() -> float:
	return 90.0*(1.0+maxf(0,float(_talents.get("slam_damage",0))))

func _flame_pulse() -> void:
	_flame_pulses += 1
	_area_hit(g.player.position,_flame_radius(),22.0,{})
	_fx("flame_spin",g.player.position,Color("ff9c5b"),_aim(),_flame_radius()/4.1)
	_sound("spin",-18,1.05+float(_flame_pulses)*.12)

func _flame_radius() -> float:
	return 4.1+maxf(0,float(_talents.get("flame_radius",0)))

func _gravity_radius() -> float:
	return 4.8+maxf(0,float(_talents.get("gravity_radius",0)))

func _gravity_damage_scale() -> float:
	return 1.0+maxf(0,float(_talents.get("gravity_damage",0)))

func _pull_gravity(dt: float) -> void:
	if g.arts != null and g.arts.frozen_enemies: return
	for enemy in g.enemies:
		if not _valid_enemy(enemy): continue
		var toward: Vector3 = gravity_position-enemy.node.position; toward.y = 0
		var distance := toward.length()
		if distance > _gravity_radius() or distance < .16 or g.world.line_blocked(enemy.node.position,gravity_position): continue
		var speed := 4.0*(.2 if enemy.get("kind","") == "boss" else 1.0)
		var desired: Vector3 = enemy.node.position+toward.normalized()*minf(speed*dt,distance-.16)
		var safe := _safe_end(enemy.node.position,desired,.42)
		g._move_actor(enemy.node,safe-enemy.node.position,.42)

func _area_hit(center: Vector3,radius: float,damage: float,hits: Dictionary) -> void:
	for enemy in g.enemies.duplicate():
		if not _raid_valid(): return
		if not _valid_enemy(enemy): continue
		var key: int = enemy.node.get_instance_id()
		if hits.has(key): continue
		var direction: Vector3 = enemy.node.position-center; direction.y = 0
		if direction.length() > radius+.35 or g.world.line_blocked(center,enemy.node.position): continue
		hits[key] = true
		g.combat_hit(enemy,damage,"attack",center,direction.normalized() if direction.length_squared() > .001 else _aim())
	if g.has_method("damage_breakables_radius"): g.damage_breakables_radius(center,radius,damage,hits)
	if g.has_method("combat_burst"): g.combat_burst(center,radius,"attack",hits)

func _reflect_guard() -> void:
	if g.boon_runtime != null and g.boon_runtime.has_method("_reflect"):
		g.boon_runtime._reflect(g.player.position,g.player.position,2.3)
		return
	# Isolated integrations without a boon runtime retain correct reflection.
	var center: Vector3 = g.player.position+Vector3.UP*.7
	for bullet in g.bullets:
		if bullet.life <= 0 or bullet.get("reflected",false) or not is_instance_valid(bullet.node): continue
		if bullet.node.position.distance_to(center) > 2.3 or g.world.line_blocked(center,bullet.node.position): continue
		bullet.reflected = true
		var away: Vector3 = bullet.node.position-center
		if away.length_squared() < .001: away = -bullet.vel
		if away.length_squared() < .001: away = _aim()
		bullet.vel = away.normalized()*maxf(15,bullet.vel.length()*1.6)
		bullet.damage *= 2

func absorb_damage(amount: float) -> float:
	if not is_finite(amount) or amount <= 0: return 0.0
	if not _raid_valid() or _left("prism_guard") <= 0: return amount
	var absorbed := minf(shield_amount,amount)
	shield_amount -= absorbed
	return amount-absorbed

func cancel_active() -> void:
	_remaining.clear(); shield_amount = 0
	_slam_elapsed = 0; _slam_impacted = false; _slam_hits.clear()
	_slam_origin = Vector3.ZERO; slam_position = Vector3.ZERO
	_clear_fx(_slam_mark); _slam_mark = null
	_flame_elapsed = 0; _flame_pulses = 0; _gravity_elapsed = 0; _gravity_pulses = 0
	_clear_fx(_field_fx); _field_fx = null
	_clear_fx(_guard_fx); _guard_fx = null
	if g != null and g.arts != null: g.arts.cancel_active()

func reset() -> void:
	cancel_active(); _cooldowns.clear(); error = ""; gravity_position = Vector3.ZERO
	if g != null and g.arts != null: g.arts.reset()

func dispose() -> void:
	reset(); g = null

func _left(id: String) -> float:
	return float(_remaining.get(id,0))

func _slot_index(slot: String) -> int:
	return 0 if slot == "primary" else (1 if slot == "secondary" else -1)

func _raid_valid() -> bool:
	return g != null and is_instance_valid(g.player) and g.mode == "raid" and g.hp > 0

func _valid_enemy(enemy: Dictionary) -> bool:
	return float(enemy.get("hp",0)) > 0 and is_instance_valid(enemy.get("node")) and not enemy.node.is_queued_for_deletion()

func _aim() -> Vector3:
	var value: Vector3 = g.direction; value.y = 0
	return value.normalized() if value.length_squared() > .001 else Vector3.FORWARD

func _safe_end(from: Vector3,to: Vector3,radius: float) -> Vector3:
	var steps := maxi(1,ceili(from.distance_to(to)/.1))
	var last := from
	for index in range(1,steps+1):
		var point := from.lerp(to,float(index)/steps)
		var blocked: bool = g._position_blocked(point,radius) if g.has_method("_position_blocked") else g.world.blocked(point,radius)
		if blocked or g.world.line_blocked(last,point): return last
		last = point
	return to

func _fx(kind: String,pos: Vector3,color: Color,direction: Vector3,size: float) -> Node3D:
	if g != null and g.has_method("play_combat_fx"):
		var result = g.play_combat_fx(kind,pos,color,direction,size)
		if result is Node3D: return result
	return null

func _clear_fx(node: Node3D) -> void:
	if is_instance_valid(node): node.visible = false; node.queue_free()

func _sound(id: String,db: float,pitch: float) -> void:
	if g != null and g.sound != null: g.sound.play(id,db,pitch)
