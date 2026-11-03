extends RefCounted
## Hades-gun style flying blades. The fan behind the hero is the magazine:
## J fires one blade along the facing, each blade lands at max range and
## sticks in the floor; once the fan is empty, J recalls every blade. All
## motion uses cubic Bezier paths with per-slot bends so a volley fans out
## like wings and the recall sweeps back through the crowd.

var g
var swords: Array:
	get: return g.swords

var held := false
var buffer := 0.0
var heat := 0.0
var kick := 0.0
var kick_dir := Vector3.ZERO
var fan_dir := Vector3.FORWARD
var crit_hint := 0.0
var volley_index := 0
var ghosts: Array = []
var _full_fan := true
var fx_rng := RandomNumberGenerator.new()

const FAN_RADIUS := 1.08
const FLIGHT_SPEED := 31.0
const RECALL_SPEED := 27.0
const BLOOM_PERIOD := .5

func _init(game) -> void:
	g = game

# ---------------------------------------------------------------- stats
func weapon() -> Dictionary:
	return g.data.weapon()

func perk(id: String) -> int:
	return int(g.taken.get(id,0))

func total() -> int:
	return swords.size()

func ready_count() -> int:
	var n := 0
	for s in swords:
		if s.state == "ready": n += 1
	return n

func recalling() -> bool:
	for s in swords:
		if s.state == "recall": return true
	return false

func state_name() -> String:
	if swords.is_empty(): return "none"
	if recalling(): return "recall"
	return "empty" if ready_count() == 0 else "ready"

func fire_interval() -> float:
	return float(weapon().interval)*pow(.82,perk("haste"))/(1.0+float(g.gear_bonus.get("haste",0)))

func speed_scale() -> float:
	return 1.0+perk("haste")*.2

func max_range() -> float:
	return float(weapon().range)+perk("magnet")*.8+float(g.gear_bonus.get("range",0))

func damage() -> float:
	return float(weapon().damage)*(1.0+perk("power")*.25+int(g.data.profile.upgrades.reactor)*.12+float(g.gear_bonus.get("damage",0)))

func recall_ratio() -> float:
	return .35+.65*perk("recall_cut")

func color() -> Color:
	return Color(str(weapon().get("color","64e8ff")))

# ---------------------------------------------------------------- lifecycle
func refresh() -> void:
	for s in swords:
		if is_instance_valid(s.node): s.node.queue_free()
	swords.clear()
	for gh in ghosts:
		if is_instance_valid(gh.node): gh.node.queue_free()
	ghosts.clear()
	held = false; buffer = 0; heat = 0; kick = 0; volley_index = 0; _full_fan = true
	if g.weapon_family() != "flying": return
	fan_dir = _flat(g.direction)
	var count := int(weapon().count)+perk("extra")
	for i in count:
		var node: Node3D = g.world.make_sword(color())
		g.actors.add_child(node)
		var rec := {"node":node,"state":"ready","slot":i,"life":0.0,"duration":.3,"p0":Vector3.ZERO,"p1":Vector3.ZERO,"p2":Vector3.ZERO,"p3":Vector3.ZERO,
			"hit":{},"props":{},"dir":Vector3.FORWARD,"pierce":0,"bounces":0,"homing":{},"vel":Vector3.ZERO,"pop":0.0,"wobble":0.0,"delay":0.0,"bloom":0.0,"crit":false}
		swords.append(rec)
		node.position = slot_position(i,count)
		_point(node,slot_facing(i,count))

func press() -> void:
	if g.mode != "raid" or swords.is_empty(): return
	held = true
	if ready_count() == 0:
		if not recalling(): recall_all()
		return
	if g.attack_timer <= 0: fire()
	else: buffer = .14

func release() -> void:
	held = false

# ---------------------------------------------------------------- fan
func _flat(v: Vector3) -> Vector3:
	v.y = 0
	return v.normalized() if v.length_squared() > .0001 else Vector3.FORWARD

func _slot_t(i: int, n: int) -> float:
	return 0.0 if n <= 1 else float(i)/float(n-1)-.5

func _spread(n: int) -> float:
	return minf(2.7,.46*float(n-1))

func slot_offset(i: int, n: int) -> Vector3:
	var aim := fan_dir
	var side := Vector3(-aim.z,0,aim.x)
	var a := _slot_t(i,n)*_spread(n)
	return -aim*cos(a)*FAN_RADIUS + side*sin(a)*FAN_RADIUS*1.15

func slot_position(i: int, n: int) -> Vector3:
	var a := _slot_t(i,n)*_spread(n)
	var bob := sin(g.visual_time*3.1+i*.9)*.07
	return g.player.position + slot_offset(i,n) + Vector3.UP*(1.18+cos(a)*.42+bob)

func slot_facing(i: int, n: int) -> Vector3:
	var out := slot_offset(i,n).normalized()
	return (out*.62 + Vector3.UP + fan_dir*.18).normalized()

func _point(node: Node3D, dir: Vector3) -> void:
	if dir.length_squared() < .000001: return
	dir = dir.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < .97 else Vector3.RIGHT
	node.look_at(node.position+dir,up)

func _fire_order(n: int) -> Array:
	var order: Array = []
	var lo := 0; var hi := n-1
	while lo <= hi:
		order.append(lo)
		if hi != lo: order.append(hi)
		lo += 1; hi -= 1
	return order

# ---------------------------------------------------------------- firing
func _assist(aim: Vector3, reach: float) -> Dictionary:
	var cone := deg_to_rad(11.0 + (24.0 if perk("magnet") > 0 else 0.0))
	var best: Dictionary = {}
	var best_angle := cone
	for e in g.enemies:
		if e.hp <= 0: continue
		var to: Vector3 = e.node.position-g.player.position
		to.y = 0
		var d := to.length()
		if d < .3 or d > reach: continue
		var ang := aim.angle_to(to/d)
		if ang < best_angle and not g.world.line_blocked(g.player.position,e.node.position):
			best_angle = ang; best = e
	return best

func _landing(origin: Vector3, aim: Vector3, reach: float) -> Vector3:
	var ground: float = g.player.position.y
	var last := Vector3(origin.x,ground,origin.z)
	var steps := ceili(reach/.35)
	for k in range(1,steps+1):
		var p := Vector3(origin.x,ground,origin.z)+aim*minf(reach,k*.35)
		if g.world.blocked(p,.18) or g.world.line_blocked(last,p): break
		last = p
	return last

func fire() -> void:
	var n := swords.size()
	var s: Dictionary = {}
	for i in _fire_order(n):
		if swords[i].state == "ready": s = swords[i]; break
	if s.is_empty(): return
	var aim := _flat(g.direction)
	var reach := max_range()
	var target := _assist(aim,reach)
	if g.has_method("assist_target"):
		var assisted: Dictionary = g.assist_target(reach)
		if not assisted.is_empty(): target = assisted
	if not target.is_empty(): aim = _flat(target.node.position-g.player.position)
	var node: Node3D = s.node
	var home := slot_position(int(s.slot),n)
	if node.position.distance_to(home) > 2.5: node.position = home
	var p0: Vector3 = node.position
	var landing := _landing(g.player.position,aim,reach)
	var side := Vector3(-aim.z,0,aim.x)
	var sign := -1.0 if _slot_t(int(s.slot),n) < 0 else 1.0
	if n == 1: sign = 1.0 if volley_index % 2 == 0 else -1.0
	var dist := maxf(1.0,Vector3(p0.x,landing.y,p0.z).distance_to(landing))
	s.state = "flight"; s.life = 0.0; s.hit = {}; s.props = {}; s.dir = aim
	s.p0 = p0
	# Wing out of the fan, snap onto the aim line, then dive into the floor.
	var base: Vector3 = g.player.position
	s.p1 = base + aim*1.3 + side*sign*.8 + Vector3.UP*1.55
	s.p2 = base + aim*dist*.58 - side*sign*.22 + Vector3.UP*1.05
	s.p3 = landing + Vector3.UP*.05
	s.duration = clampf(dist/(FLIGHT_SPEED*speed_scale()),.16,.48)
	s.pierce = perk("pierce") + (1 if g.data.profile.weapon == "heavy" else 0)
	s.bounces = perk("ricochet")
	s.homing = target if perk("magnet") > 0 else {}
	s.crit = _full_fan and perk("quickdraw") > 0
	_full_fan = false
	g.attack_timer = fire_interval()
	buffer = 0
	volley_index += 1
	# Feel: recoil squash, camera kick against the shot, muzzle sparkle, rising pitch.
	g.direction = aim
	g._sync_player_heading()
	g.squash_velocity -= 2.4
	heat = minf(1.0,heat+.34)
	kick = .16 if not g.motion_reduced else .05
	kick_dir = -aim
	var c := color()
	g._burst(p0,c.lightened(.3),5)
	g._ring_effect(g.player.position,c,.15,1.05,.16)
	g.sound.play("sword",-17,1.12+.05*float(volley_index%6)+fx_rng.randf_range(-.03,.03))
	if perk("salvo") > 0: _spawn_ghost(p0,aim,-sign,reach)

func recall_all() -> void:
	var k := 0
	var n := swords.size()
	for s in swords:
		if s.state == "ready" or s.state == "recall": continue
		s.state = "recall"; s.life = 0.0; s.hit = {}; s.props = {}
		s.delay = k*.035
		k += 1
		var p0: Vector3 = s.node.position
		var slot := slot_position(int(s.slot),n)
		var to := slot-p0
		to.y = 0
		var side := Vector3(-to.z,0,to.x).normalized()
		# Outer blades arc wide and converge, the centre blade returns straight.
		var bend := _slot_t(int(s.slot),n)*2.4*minf(1.0,to.length()/6.0)
		s.p0 = p0
		s.p1 = p0 + Vector3.UP*1.5 + to*.12
		s.p2 = p0 + to*.7 + side*bend + Vector3.UP*.75
		s.p3 = slot
		s.duration = clampf(p0.distance_to(slot)/(RECALL_SPEED*speed_scale()),.2,.5)
		s.dir = to.normalized() if to.length() > .01 else -fan_dir
		g._burst(p0,color(),4)
	if k > 0:
		g.sound.play("spear_recall",-18,1.15)
		g.attack_timer = minf(g.attack_timer,.05)

# ---------------------------------------------------------------- simulation
func tick(delta: float, combat: bool) -> void:
	if g.weapon_family() != "flying": return
	if swords.is_empty(): return
	var n := swords.size()
	var aim := _flat(g.direction)
	fan_dir = _flat(fan_dir.lerp(aim,minf(1.0,delta*9.0)))
	if combat:
		g.attack_timer -= delta
		buffer = maxf(0,buffer-delta)
		if (held or buffer > 0) and g.attack_timer <= 0 and ready_count() > 0 and g.mode == "raid": fire()
	heat = maxf(0,heat-delta*1.4)
	kick = kick*exp(-delta*16.0)
	for s in swords:
		match str(s.state):
			"flight": _tick_flight(s,delta)
			"drop": _tick_drop(s,delta)
			"grounded": _tick_grounded(s,delta,combat)
			"recall": _tick_recall(s,delta,n)
			_: _tick_ready(s,delta,n)
	for i in range(ghosts.size()-1,-1,-1):
		if not _tick_ghost(ghosts[i],delta): ghosts.remove_at(i)

func _bezier(s: Dictionary, t: float) -> Vector3:
	return g._bezier(s.p0,s.p1,s.p2,s.p3,t)

func _tick_ready(s: Dictionary, delta: float, n: int) -> void:
	var node: Node3D = s.node
	var slot := slot_position(int(s.slot),n)
	node.position = node.position.lerp(slot,1.0-exp(-delta*15.0))
	s.pop = maxf(0,float(s.pop)-delta*4.5)
	var p: float = s.pop
	node.scale = Vector3.ONE*(1.0+sin(p*PI)*.35)
	_point(node,slot_facing(int(s.slot),n).lerp(fan_dir,heat*.25))

func _tick_flight(s: Dictionary, delta: float) -> void:
	var node: Node3D = s.node
	s.life += delta
	if perk("magnet") > 0: _steer(s,delta)
	var u := clampf(float(s.life)/float(s.duration),0,1)
	var e := 1.0-pow(1.0-u,1.7)
	var old: Vector3 = node.position
	var pos := _bezier(s,e)
	if g.world.line_blocked(old,pos):
		if g.has_method("_static_impact"):
			g._static_impact(g.world.static_hit_segment(old,pos,.3),s.props)
		_drop(s,old,-Vector3(s.dir)*.6)
		return
	node.position = pos
	node.scale = Vector3.ONE*1.08
	_point(node,pos-old)
	_trail(old,pos,false)
	var motion := pos-old
	if motion.length() > .01: s.dir = _flat(motion)
	g.damage_breakables_segment(old,pos,.5,damage()*.5,s.props)
	if _sweep(s,old,pos,damage(),false): return
	if u >= 1.0: _land(s,pos)

func _steer(s: Dictionary, delta: float) -> void:
	var node: Node3D = s.node
	var h: Dictionary = s.homing
	if h.is_empty() or h.hp <= 0 or s.hit.has(h.node.get_instance_id()):
		h = {}
		var reach := 2.2+perk("magnet")*1.1
		for e in g.enemies:
			if e.hp <= 0 or s.hit.has(e.node.get_instance_id()): continue
			var to: Vector3 = e.node.position-node.position
			to.y = 0
			if to.length() < reach and _flat(to).dot(Vector3(s.dir)) > .15:
				reach = to.length(); h = e
		s.homing = h
	if h.is_empty(): return
	var feet: Vector3 = h.node.position+Vector3(0,.05,0)
	var rate := minf(1.0,delta*(7.0+perk("magnet")*2.0))
	s.p3 = Vector3(s.p3).lerp(feet,rate)
	s.p2 = Vector3(s.p2).lerp(h.node.position+Vector3.UP*1.0,rate)

func _enemy_radius(e: Dictionary) -> float:
	return .8+(.55 if e.kind == "boss" else (.25 if e.kind == "elite" else 0.0))

## Swept, frame-rate independent hit test. Returns true when the blade stopped.
func _sweep(s: Dictionary, a: Vector3, b: Vector3, dmg: float, returning: bool) -> bool:
	for e in g.enemies.duplicate():
		if e.hp <= 0: continue
		var id: int = e.node.get_instance_id()
		if s.hit.has(id): continue
		var center: Vector3 = e.node.position+Vector3.UP*.85
		var close := Geometry3D.get_closest_point_to_segment(center,a,b)
		var flat := Vector2(close.x-center.x,close.z-center.z).length()
		if flat > _enemy_radius(e) or close.y > center.y+1.4 or close.y < center.y-1.2: continue
		s.hit[id] = true
		_strike(s,e,dmg,_flat(b-a) if (b-a).length() > .01 else Vector3(s.dir),returning)
		if returning: continue
		if int(s.pierce) > 0:
			s.pierce -= 1
			continue
		if int(s.bounces) > 0 and _ricochet(s,e): return true
		_drop(s,close,Vector3(s.dir))
		return true
	return false

func _strike(s: Dictionary, e: Dictionary, dmg: float, dir: Vector3, returning: bool) -> void:
	var target_pos: Vector3 = e.node.position+Vector3.UP*.85
	crit_hint = 1.0 if bool(s.get("crit",false)) else 0.0
	g.combat_hit(e,dmg,"attack",g.player.position,dir)
	crit_hint = 0.0
	s.crit = false
	if e.hp > 0 and e.kind != "boss":
		e["knockback"] = e.get("knockback",Vector3.ZERO)+dir*(1.6 if returning else 2.6)
		e["stagger"] = maxf(float(e.get("stagger",0.0)),.06)
	var c := color()
	g._burst(target_pos,c.lightened(.25),6)
	g.play_combat_fx("impact",target_pos,c,dir,.5)
	g.hit_pause = maxf(g.hit_pause,.014)
	if g.taken.has("frost"):
		e.slow = 2.0+int(g.taken.frost)*.5
		g._ring_effect(e.node.position,Color("80e9ff"),.2,1.6,.5)
	if g.taken.has("chain") or g.data.profile.weapon == "arc":
		g._chain_hit(e,dmg*(.5+.15*perk("chain")))
	if g.taken.has("penetrate") or g.data.profile.weapon == "heavy":
		g._ring_effect(e.node.position,c,.2,2.6,.26)
		for other in g.enemies.duplicate():
			if other != e and other.hp > 0 and other.node.position.distance_to(target_pos) < 2.8:
				g.hit_enemy(other,dmg*.45,false)

func _ricochet(s: Dictionary, from: Dictionary) -> bool:
	var best: Dictionary = {}
	var reach := 6.5
	for e in g.enemies:
		if e.hp <= 0 or e == from or s.hit.has(e.node.get_instance_id()): continue
		var d: float = e.node.position.distance_to(from.node.position)
		if d < reach and not g.world.line_blocked(from.node.position,e.node.position):
			reach = d; best = e
	if best.is_empty(): return false
	s.bounces -= 1
	var p0: Vector3 = s.node.position
	var feet: Vector3 = best.node.position+Vector3(0,.05,0)
	var to := feet-p0
	to.y = 0
	var side := Vector3(-to.z,0,to.x).normalized()
	s.p0 = p0
	s.p1 = p0 + Vector3.UP*1.3 + side*.8
	s.p2 = feet + Vector3.UP*1.4 - to*.15
	s.p3 = feet + _flat(to)*1.2
	s.life = 0.0
	s.duration = clampf(to.length()/(FLIGHT_SPEED*speed_scale()),.12,.3)
	s.homing = best
	s.dir = _flat(to)
	g._ring_effect(p0-Vector3.UP*p0.y,Color("c2a5ff"),.1,.9,.16)
	g.sound.play("tick",-20,1.6)
	return true

func _drop(s: Dictionary, at: Vector3, dir: Vector3) -> void:
	s.state = "drop"
	s.node.position = at
	s.vel = _flat(dir)*3.2+Vector3.UP*4.6
	s.life = 0.0

func _tick_drop(s: Dictionary, delta: float) -> void:
	var node: Node3D = s.node
	s.life += delta
	s.vel = Vector3(s.vel)+Vector3.DOWN*24.0*delta
	var old := node.position
	var pos := old+Vector3(s.vel)*delta
	var flat := Vector3(pos.x,g.player.position.y,pos.z)
	if g.world.blocked(flat,.12):
		pos.x = old.x; pos.z = old.z
		s.vel = Vector3(0,s.vel.y,0)
	node.position = pos
	node.rotate_object_local(Vector3.RIGHT,delta*19.0)
	if pos.y <= g.player.position.y+.45 and s.vel.y < 0:
		_land(s,Vector3(pos.x,g.player.position.y,pos.z))

func _land(s: Dictionary, pos: Vector3) -> void:
	var node: Node3D = s.node
	var ground := Vector3(pos.x,g.player.position.y,pos.z)
	s.state = "grounded"
	s.life = 0.0
	s.wobble = 1.0
	s.bloom = BLOOM_PERIOD
	node.position = ground+Vector3.UP*.42
	node.scale = Vector3.ONE
	_point(node,Vector3(s.dir)*.38+Vector3.DOWN)
	var c := color()
	g._ring_effect(ground,c,.1,1.15,.22)
	g._burst(ground+Vector3.UP*.15,c.darkened(.1),5)
	g.sound.play("impact",-27,fx_rng.randf_range(1.15,1.35))
	g.shake = maxf(g.shake,.02*(.35 if g.motion_reduced else 1.0))
	if perk("bloom") > 0: g._ring_effect(ground,Color("ffd18b"),.2,1.7,.3)

func _tick_grounded(s: Dictionary, delta: float, combat: bool) -> void:
	var node: Node3D = s.node
	if float(s.wobble) > 0:
		s.wobble = maxf(0,float(s.wobble)-delta*3.2)
		s.life += delta
		var base: Vector3 = node.position
		_point(node,Vector3(s.dir)*.38+Vector3.DOWN+Vector3(s.dir)*sin(float(s.life)*46.0)*.32*float(s.wobble))
		node.position = base
	if not combat or perk("bloom") <= 0: return
	s.bloom -= delta
	if s.bloom > 0: return
	s.bloom = BLOOM_PERIOD
	var ground := Vector3(node.position.x,g.player.position.y,node.position.z)
	var hit := false
	for e in g.enemies.duplicate():
		if e.hp > 0 and Vector2(e.node.position.x-ground.x,e.node.position.z-ground.z).length() < 1.7:
			g.hit_enemy(e,damage()*.22*perk("bloom"),false,false,"dot")
			hit = true
	if hit: g._ring_effect(ground,Color("ffd18b"),.3,1.7,.25)

func _tick_recall(s: Dictionary, delta: float, n: int) -> void:
	var node: Node3D = s.node
	if float(s.delay) > 0:
		s.delay -= delta
		return
	s.life += delta
	s.p3 = slot_position(int(s.slot),n)
	var u := clampf(float(s.life)/float(s.duration),0,1)
	var e := u*u*(3.0-2.0*u)
	var old := node.position
	var pos := _bezier(s,e)
	node.position = pos
	node.scale = Vector3.ONE*1.05
	_point(node,pos-old)
	_trail(old,pos,true)
	_sweep(s,old,pos,damage()*recall_ratio(),true)
	if u >= 1.0: _arrive(s)

func _arrive(s: Dictionary) -> void:
	s.state = "ready"
	s.pop = 1.0
	g.sound.play("tick",-23,1.3+.08*float(ready_count()))
	if ready_count() == swords.size():
		_full_fan = true
		var c := color()
		g._ring_effect(g.player.position,c.lightened(.2),.3,1.7,.26)
		g.squash_velocity = -5.0 if not g.motion_reduced else -2.5
		g.sound.play("loot",-21,1.25)

func _trail(a: Vector3, b: Vector3, returning: bool) -> void:
	var c := color()
	g._sword_trail(a,b,c.darkened(.15) if returning else c)
	if a.distance_to(b) > .03 and g.effects.size() < 220:
		var core: MeshInstance3D = g._beam(a,b,Color(1,1,1).lerp(c,.25),.026)
		g.effects.append({"node":core,"life":.09,"max":.09,"vel":Vector3.ZERO,"grow":-1.0})

# ---------------------------------------------------------------- spectral twin
func _spawn_ghost(origin: Vector3, aim: Vector3, sign: float, reach: float) -> void:
	var node: Node3D = g.world.make_sword(color().lightened(.45))
	g.actors.add_child(node)
	node.position = origin
	node.scale = Vector3.ONE*.8
	var side := Vector3(-aim.z,0,aim.x)
	var end := origin+aim*reach*.9+Vector3.DOWN*.4
	ghosts.append({"node":node,"p0":origin,"p1":origin+aim*reach*.25+side*sign*1.4,"p2":end-aim*reach*.25+side*sign*.6,"p3":end,
		"life":0.0,"duration":clampf(reach/(FLIGHT_SPEED*1.15*speed_scale()),.14,.4),"hit":{},"props":{},"dir":aim,"pierce":99,"bounces":0,"crit":false})

func _tick_ghost(gh: Dictionary, delta: float) -> bool:
	var node: Node3D = gh.node
	if not is_instance_valid(node): return false
	gh.life += delta
	var u := clampf(float(gh.life)/float(gh.duration),0,1)
	var old := node.position
	var pos := _bezier(gh,1.0-pow(1.0-u,1.5))
	node.position = pos
	_point(node,pos-old)
	g._sword_trail(old,pos,color().lightened(.5))
	for e in g.enemies.duplicate():
		if e.hp <= 0 or gh.hit.has(e.node.get_instance_id()): continue
		var center: Vector3 = e.node.position+Vector3.UP*.85
		var close := Geometry3D.get_closest_point_to_segment(center,old,pos)
		if Vector2(close.x-center.x,close.z-center.z).length() < _enemy_radius(e):
			gh.hit[e.node.get_instance_id()] = true
			g.combat_hit(e,damage()*.5,"attack",g.player.position,Vector3(gh.dir))
	if u >= 1.0 or g.world.line_blocked(old,pos):
		g._burst(pos,color().lightened(.4),6)
		node.queue_free()
		return false
	return true

# ---------------------------------------------------------------- camera
func camera_offset() -> Vector3:
	if g.mode != "raid" or swords.is_empty(): return Vector3.ZERO
	var scale := .35 if g.motion_reduced else 1.0
	return (fan_dir*heat*1.25 + kick_dir*kick)*scale
