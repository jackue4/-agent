extends RefCounted
## Runtime effects are scoped to the current expedition; they never alter saved equipment.
const Boons = preload("res://scripts/boons.gd")
var g
var clock := 0.0
var deflect_until := 0.0
var _display_tick := 0.0
var _signature: int = -1
var _entries: Array = []
var _slots: Dictionary = {}
var _effects: Dictionary = {}

func _init(game) -> void:
	g = game

func slots() -> Dictionary:
	_ensure_cache()
	return _slots

func entries() -> Array:
	_ensure_cache()
	return _entries

func _ensure_cache() -> void:
	var signature: int = hash(g.boon_owned)
	if signature == _signature: return
	_signature = signature
	_entries.clear(); _slots.clear(); _effects.clear()
	for id in g.boon_owned:
		var entry: Dictionary = Boons.owned_entry(g.boon_owned,id)
		if entry.is_empty(): continue
		entry["active"] = Boons.active(id,g.boon_owned)
		_entries.append(entry)
		if entry.active: _effects[id] = entry.get("effects",{})
		if str(entry.get("slot","")) in ["attack","special","dash"]: _slots[entry.slot] = entry

func hammer_count() -> int:
	var count := 0
	for entry in entries():
		if entry.get("type","") == "hammer": count += 1
	return count

func effect(id: String) -> Dictionary:
	_ensure_cache()
	return _effects.get(id,{})

func hit(enemy: Dictionary,base_damage: float,kind: String,origin: Vector3,aim: Vector3) -> void:
	if enemy.hp <= 0: return
	var slot: String = "special" if kind in ["special","special_return"] else ("dash" if kind == "dash" else "attack")
	var entry: Dictionary = slots().get(slot,{})
	var fx: Dictionary = entry.get("effects",{})
	var damage: float = base_damage*(1.0+float(fx.get("damage_pct",0)))
	if enemy.get("weak_time",0.0) > 0: damage *= 1.0+float(effect("sweet_surrender").get("weak_damage_bonus",0))
	if enemy.get("exposed_time",0.0) > 0:
		var behind: Vector3 = enemy.node.position-origin
		if (-enemy.node.global_basis.z).dot(behind.normalized()) > .4: damage *= 1.0+float(effect("blinding_flash").get("exposed_bonus",0))
	var chance: float = float(fx.get("crit_chance",0))+float(g.gear_bonus.get("crit",0))
	if g.has_method("talent_crit_chance"): chance += g.talent_crit_chance()
	if "base_crit" in g: chance += float(g.base_crit)
	chance += float(effect("pressure_points").get("global_crit",0))
	if g.spear != null: chance += g.spear.special_crit_bonus(kind)
	if g.weapon_family() == "flying": chance += .08+int(g.taken.get("crit",0))*.2
	if g.weapon_family() == "flying" and g.get("blades") != null: chance += float(g.blades.crit_hint)
	var critical: bool = g.rng.randf() < chance
	if critical:
		var multiplier := 2.0 if g.weapon_family() == "flying" and not fx.has("crit_chance") else 3.0
		if enemy.get("weak_time",0.0) > 0:
			multiplier += float(effect("heart_rend").get("weak_crit_bonus",0))
		damage *= multiplier
	g.hit_enemy(enemy,damage,critical,false,"frost" if fx.has("chill_stacks") else "normal")
	var pos: Vector3 = enemy.node.position
	var color := Color(str(entry.get("color","81e6ff")))
	if not fx.is_empty(): g.play_combat_fx(_fx_kind(fx),pos,color,aim,.65 if slot == "attack" else .9)
	if fx.has("lightning_damage") or fx.has("bolt_damage"):
		_lightning(enemy,float(fx.get("lightning_damage",fx.get("bolt_damage",10))),int(fx.get("chain_count",0)))
	if fx.has("knockback"):
		_knockback(enemy,origin,aim,float(fx.knockback))
	if fx.has("weak_duration"):
		enemy["weak_time"] = float(fx.weak_duration)
		enemy["weak_reduction"] = float(fx.get("weak_reduction",.3))
	if fx.has("doom_damage"):
		if enemy.get("doom_time",0.0) <= 0:
			enemy["doom_time"] = float(fx.get("doom_delay",1.1))+float(effect("impending_doom").get("doom_delay_bonus",0))
			enemy["doom_damage"] = float(fx.doom_damage)*(1.0+float(effect("impending_doom").get("doom_bonus",0)))
	if fx.has("hangover_damage"):
		var cap: int = int(fx.get("hangover_max_stacks",5))
		var stacks: Array = enemy.get("hangover",[])
		var stack := {"remaining":float(fx.get("hangover_duration",4)),"damage":float(fx.hangover_damage)}
		if stacks.size() >= cap: stacks.pop_front()
		stacks.append(stack)
		enemy["hangover"] = stacks
		enemy["hangover_tick"] = float(enemy.get("hangover_tick",float(fx.get("hangover_interval",.5))))
	if fx.has("chill_stacks"):
		enemy["chill"] = mini(int(fx.get("chill_max_stacks",10)),int(enemy.get("chill",0))+int(fx.chill_stacks))
		enemy["chill_time"] = float(fx.get("chill_duration",8))
		enemy["chill_slow"] = float(fx.get("chill_slow",.04))
		if int(enemy.chill) >= 10 and g.boon_owned.has("arctic_blast"):
			enemy.chill = 0
			_area_damage(pos,float(effect("arctic_blast").get("chill_blast_radius",2.6)),float(effect("arctic_blast").get("chill_blast_damage",80)),Color("9bf3ff"),"frost")
	if fx.get("deflect",false):
		# Active weapon geometry handles deflection, including attacks that miss enemies.
		if not effect("blinding_flash").is_empty(): enemy["exposed_time"] = float(effect("blinding_flash").get("exposed_duration",5))
		if enemy.get("doom_time",0.0) > 0 and not effect("merciful_end").is_empty():
			_trigger_doom(enemy,float(effect("merciful_end").get("doom_detonation_bonus",40)))

func _fx_kind(fx: Dictionary) -> String:
	if fx.has("doom_damage"): return "doom_mark"
	if fx.has("lightning_damage") or fx.has("bolt_damage"): return "lightning"
	if fx.has("knockback"): return "wave"
	if fx.has("hangover_damage"): return "poison"
	if fx.has("chill_stacks"): return "frost"
	if fx.get("deflect",false): return "deflect"
	return "impact"

func _lightning(enemy: Dictionary,damage: float,chains: int) -> void:
	# Each target has its own short lockout; rapid jabs cannot proc infinitely in one frame.
	if clock < float(enemy.get("lightning_ready",-1)): return
	enemy["lightning_ready"] = clock+.18
	var visited: Array = [enemy]
	var from: Vector3 = enemy.node.position
	if enemy.hp > 0: g.hit_enemy(enemy,damage,false)
	_apply_jolt(enemy)
	if chains == 0:
		for other in g.enemies.duplicate():
			if other == enemy or other.hp <= 0: continue
			if other.node.position.distance_to(from) < 2 and not g.world.line_blocked(from,other.node.position):
				g.hit_enemy(other,damage,false); _apply_jolt(other)
	for bounce in mini(chains,5):
		var nearest := {}; var distance := 5.0
		for other in g.enemies:
			if other.hp <= 0 or other in visited: continue
			var d: float = from.distance_to(other.node.position)
			if d < distance and not g.world.line_blocked(from,other.node.position): nearest = other; distance = d
		if nearest.is_empty(): break
		visited.append(nearest)
		g._sword_trail(from+Vector3.UP,nearest.node.position+Vector3.UP,Color("fff1a2"))
		g.play_combat_fx("lightning",nearest.node.position,Color("ffe68d"),Vector3.FORWARD,.7)
		g.hit_enemy(nearest,damage,false)
		_apply_jolt(nearest)
		from = nearest.node.position

func _apply_jolt(enemy: Dictionary) -> void:
	if not effect("static_discharge").is_empty():
		enemy["jolted"] = float(effect("static_discharge").get("jolted_damage",60))
		enemy["jolt_time"] = float(effect("static_discharge").get("jolted_duration",8))

func _knockback(enemy: Dictionary,origin: Vector3,aim: Vector3,strength: float) -> void:
	var away: Vector3 = enemy.node.position-origin
	away.y = 0
	if away.length() < .01: away = aim
	away = away.normalized()
	var velocity: float = strength * (.2 if enemy.kind == "boss" else 1.0)
	enemy["knockback"] = away*velocity
	enemy["stagger"] = maxf(float(enemy.get("stagger",0)),.26)
	if not effect("razor_shoals").is_empty():
		enemy["rupture_time"] = float(effect("razor_shoals").get("rupture_duration",3))
		enemy["rupture_damage"] = float(effect("razor_shoals").get("rupture_damage",10))
		enemy["rupture_pos"] = enemy.node.position
		enemy["rupture_distance"] = 0.0
		enemy["rupture_tick"] = 0.0
	if not effect("sea_storm").is_empty(): _lightning(enemy,float(effect("sea_storm").get("knockback_lightning",40)),0)

func _area_damage(pos: Vector3,radius: float,damage: float,color: Color,kind: String) -> void:
	g.play_combat_fx(kind,pos,color,Vector3.FORWARD,1.25)
	for other in g.enemies.duplicate():
		if other.hp > 0 and other.node.position.distance_to(pos) < radius and not g.world.line_blocked(pos,other.node.position): g.hit_enemy(other,damage,false,true,"frost" if kind == "frost" else "normal")

func _trigger_doom(enemy: Dictionary,bonus: float = 0.0) -> void:
	enemy["doom_time"] = 0.0
	g.play_combat_fx("doom",enemy.node.position,Color("ff4668"),Vector3.FORWARD,1.2)
	g.hit_enemy(enemy,float(enemy.get("doom_damage",0))+bonus,false,true,"dot")
	g.sound.play("impact",-17,.7)

func outgoing_multiplier(enemy: Dictionary) -> float:
	return 1.0-float(enemy.get("weak_reduction",.3)) if enemy.get("weak_time",0.0) > 0 else 1.0

func move_multiplier(enemy: Dictionary) -> float:
	var slow: float = int(enemy.get("chill",0))*float(enemy.get("chill_slow",.04))
	if not enemy.get("hangover",[]).is_empty(): slow += float(effect("numbing_sensation").get("hangover_slow",0))
	return maxf(.1,1.0-slow)

func before_fire(enemy: Dictionary) -> void:
	if enemy.get("jolted",0.0) > 0:
		var amount: float = enemy.jolted
		enemy.jolted = 0.0
		_area_damage(enemy.node.position,2.5,amount,Color("ffe8a2"),"lightning")

func dash() -> void:
	var entry: Dictionary = slots().get("dash",{})
	if entry.is_empty(): return
	var fx: Dictionary = entry.get("effects",{})
	if fx.get("deflect",false): deflect_until = clock+.22
	g.play_combat_fx(_fx_kind(fx),g.player.position,Color(str(entry.get("color","a6edff"))),g.direction,1.0)
	for enemy in g.enemies.duplicate():
		if enemy.hp > 0 and enemy.node.position.distance_to(g.player.position) < 3 and not g.world.line_blocked(g.player.position,enemy.node.position):
			hit(enemy,float(fx.get("dash_damage",10)),"dash",g.player.position,g.direction)

func tick(delta: float, enemy_delta: float = -1.0) -> void:
	clock += delta; _display_tick -= delta
	_tick_deflect()
	var status_delta := delta if enemy_delta < 0 else enemy_delta
	for enemy in g.enemies.duplicate():
		if enemy.hp <= 0: continue
		if status_delta <= 0:
			if _display_tick <= 0: _status_label(enemy)
			continue
		for key in ["weak_time","chill_time","rupture_time","jolt_time","exposed_time"]:
			enemy[key] = maxf(0,float(enemy.get(key,0))-status_delta)
		if enemy.chill_time <= 0: enemy["chill"] = 0
		if enemy.jolt_time <= 0: enemy["jolted"] = 0.0
		if enemy.get("doom_time",0.0) > 0:
			enemy.doom_time -= status_delta
			if enemy.doom_time <= 0: _trigger_doom(enemy)
		var stacks: Array = enemy.get("hangover",[])
		for i in range(stacks.size()-1,-1,-1):
			stacks[i].remaining -= status_delta
			if stacks[i].remaining <= 0: stacks.remove_at(i)
		if not stacks.is_empty():
			enemy.hangover_tick -= status_delta
			if enemy.hangover_tick <= 0:
				enemy.hangover_tick += float(effect("curse_of_nausea").get("hangover_interval_override",.5))
				var amount := 0.0
				for stack in stacks: amount += float(stack.damage)
				g.hit_enemy(enemy,amount,false,true,"dot")
				g.play_combat_fx("poison",enemy.node.position,Color("c88bff"),Vector3.UP,.42)
		if enemy.rupture_time > 0:
			enemy["rupture_tick"] = maxf(0,float(enemy.get("rupture_tick",0))-status_delta)
			var distance: float = enemy.node.position.distance_to(enemy.get("rupture_pos",enemy.node.position))
			enemy["rupture_pos"] = enemy.node.position
			enemy["rupture_distance"] = float(enemy.get("rupture_distance",0))+distance
			if enemy.rupture_distance >= .05 and enemy.rupture_tick <= 0:
				enemy.rupture_tick = float(effect("razor_shoals").get("rupture_interval",.25))
				enemy.rupture_distance = 0.0
				g.hit_enemy(enemy,float(enemy.get("rupture_damage",10)),false,true,"dot")
				g.play_combat_fx("rupture",enemy.node.position,Color("79f5dc"),Vector3.FORWARD,.45)
		if _display_tick <= 0: _status_label(enemy)
	if _display_tick <= 0: _display_tick = .12

func _tick_deflect() -> void:
	if clock < deflect_until: _reflect(g.player.position,g.player.position,1.5)

func deflect_segment(from: Vector3,to: Vector3,radius: float,kind: String) -> void:
	var slot := "special" if kind in ["special","special_return"] else "attack"
	var fx: Dictionary = slots().get(slot,{}).get("effects",{})
	if fx.get("deflect",false): _reflect(from,to,radius+.15)

func _reflect(from: Vector3,to: Vector3,radius: float) -> void:
	from.y = g.world.ground_height(from)+.7; to.y = g.world.ground_height(to)+.7
	for bullet in g.bullets:
		if bullet.life <= 0 or bullet.get("reflected",false): continue
		var point: Vector3 = Geometry3D.get_closest_point_to_segment(bullet.node.position,from,to)
		if point.distance_to(bullet.node.position) > radius or g.world.line_blocked(from,bullet.node.position): continue
		bullet["reflected"] = true
		var target: Dictionary = g._nearest_enemy(bullet.node.position,20)
		var aim: Vector3 = (target.node.position+Vector3.UP*.7-bullet.node.position).normalized() if not target.is_empty() else -bullet.vel.normalized()
		bullet.vel = aim*maxf(15,bullet.vel.length()*1.6)
		bullet.damage *= 2
		g.play_combat_fx("deflect",bullet.node.position,Color("ffeec3"),aim,.5)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("fff2bc")
		bullet.node.material_override = material

func _status_label(enemy: Dictionary) -> void:
	var words: Array[String] = []
	if enemy.get("doom_time",0.0) > 0: words.append("厄运")
	if enemy.get("weak_time",0.0) > 0: words.append("虚弱")
	if enemy.get("chill",0) > 0: words.append("寒%d" % enemy.chill)
	if not enemy.get("hangover",[]).is_empty(): words.append("醉%d" % enemy.hangover.size())
	if enemy.get("jolted",0.0) > 0: words.append("震颤")
	if enemy.get("rupture_time",0.0) > 0: words.append("撕裂")
	if not is_instance_valid(enemy.get("status_label")):
		if words.is_empty(): return
		var label := Label3D.new()
		label.font = preload("res://scripts/quality.gd").font()
		label.font_size = 28; label.pixel_size = .011
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true; label.modulate = Color("e0b3ff")
		enemy.node.add_child(label); label.position.y = 2.6 if enemy.kind != "boss" else 4.1
		enemy["status_label"] = label
	enemy.status_label.text = " · ".join(words)
