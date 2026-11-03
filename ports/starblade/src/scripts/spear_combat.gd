extends RefCounted
## Varatha-style base spear. All timings/ranges are explicit local tuning, not
## extracted commercial animation frames. No mana cost; no innate bullet deflect.
const Boons = preload("res://scripts/boons.gd")

const DEFAULTS := {
	"thrust_damage":[25.0,30.0,30.0], "thrust_reach":[3.7,3.95,4.25],
	"thrust_windup":[.065,.075,.105], "thrust_active":[.095,.10,.12],
	"thrust_recovery":[.14,.15,.18], "thrust_radius":.62,
	"combo_window":.72, "input_buffer":.24, "attack_move":.16,
	"charge_thresholds":[.20,.64,1.15], "charge_move":.0,
	"spin_damage":[30.0,50.0,100.0], "spin_radius":[2.8,3.75,4.95],
	"spin_windup":.02, "spin_active":.19, "spin_recovery":.16,
	"dash_spin_delay":.045, "dash_damage":20.0, "dash_reach":4.4,
	"dash_windup":.025, "dash_active":.115, "dash_recovery":.11,
	"throw_windup":.10, "throw_recovery":.12, "throw_damage":25.0,
	"return_damage":25.0, "throw_range":12.0, "throw_speed":27.0,
	"return_speed":34.0, "special_radius":.32, "special_buffer":.24,
	"normal_hit_stop":.025, "heavy_hit_stop":.055,
	"normal_stagger":.15, "heavy_stagger":.28,
	"normal_knockback":3.4, "heavy_knockback":6.5,
	"cancel_after_active":true, "navigation_step":.75
}

var g
var tuning: Dictionary = DEFAULTS.duplicate(true)
var state := "idle"
var special_state := "idle" # idle / outbound / lodged / returning
var combo := 0
var charge_ratio := 0.0
var move_multiplier := 1.0
var attack_held := false
var special_held := false
var build: Dictionary = {}
var _hammer_effects: Dictionary = {}
var sturdy: bool:
	get: return state == "charge" and has_hammer("flaring_spin")
var thrown: bool:
	get: return special_state != "idle"
var attack_progress: float:
	get:
		if state in ["charge","special_charge"]: return charge_ratio
		if state in ["thrust","dash_strike","spin"]: return clampf(elapsed/maxf(.001,_duration),0,1)
		if state == "throw": return clampf(elapsed/(float(tuning.throw_windup)+float(tuning.throw_recovery)),0,1)
		return 0.0
var recovery_remaining: float:
	get:
		if state in ["thrust","dash_strike","spin"]: return maxf(0,_duration-elapsed)
		if state == "throw": return maxf(0,float(tuning.throw_windup)+float(tuning.throw_recovery)-elapsed)
		return 0.0
var elapsed := 0.0
var charge_time := 0.0
var charge_tier := 0
var pending_dash_spin := false
var visual: Node3D
var charge_ring: Node3D
var attack_hits: Dictionary = {}
var outbound_hits: Dictionary = {}
var return_hits: Dictionary = {}

var _attack_buffer := 0.0
var _special_buffer := 0.0
var _combo_left := 0.0
var _facing := Vector3.FORWARD
var _windup := 0.0
var _active := 0.0
var _duration := 0.0
var _attack_speed := 1.0
var _damage := 0.0
var _reach := 0.0
var _radius := 0.0
var _fx_started := false
var _throw_launched := false
var _attack_after_recall := false
var _recall_requested := false
var _dash_attack_pending := false
var _dash_struck := false
var _spin_tier := 0
var _projectile_pos := Vector3.ZERO
var _throw_direction := Vector3.FORWARD
var _travelled := 0.0
var _route: Array[Vector3] = []
var _route_cooldown := 0.0
var _last_tip := Vector3.ZERO
var _lane_hits: Array = [{},{},{}]
var _pulse_elapsed := 0.0
var _special_charge_time := 0.0
var _special_power := 1.0
var _special_range_multiplier := 1.0
var _chain_count := 0
var _chain_target = null
var _launched_explosive := false
var _flurry_index := 0
var _serrated_fx_index := -1

func set_build(owned: Dictionary) -> void:
	build = owned.duplicate(true)
	_hammer_effects.clear()
	for id in build:
		var entry := Boons.lookup(id)
		if entry.get("type","") == "hammer": _hammer_effects[id] = entry.effects

func has_hammer(id: String) -> bool:
	return build.has(id)

func _hammer(id: String,key: String,fallback: float = 0.0) -> float:
	if not _hammer_effects.has(id): return fallback
	return float(_hammer_effects[id].get(key,fallback))

func special_crit_bonus(kind: String) -> float:
	return .5 if kind == "special_return" and has_hammer("vicious_skewer") else 0.0

func _init(controller = null) -> void:
	g = controller
	if g != null: reset()

func reset() -> void:
	state = "idle"; special_state = "idle"; combo = 0
	charge_ratio = 0; charge_time = 0; charge_tier = 0
	move_multiplier = 1; attack_held = false; special_held = false; elapsed = 0
	_attack_buffer = 0; _special_buffer = 0; _combo_left = 0
	_attack_after_recall = false; _recall_requested = false
	pending_dash_spin = false; _dash_attack_pending = false; _dash_struck = false
	attack_hits.clear(); outbound_hits.clear(); return_hits.clear(); _route.clear()
	_lane_hits = [{},{},{}]; _pulse_elapsed = 0; _special_power = 1
	_special_charge_time = 0; _special_range_multiplier = 1; _chain_count = 0; _chain_target = null; _launched_explosive = false
	if g != null and is_instance_valid(g.player):
		_ensure_visual()
		charge_ring.visible = false
		_pose_idle(1.0)

func dispose() -> void:
	if is_instance_valid(visual): visual.queue_free()
	if is_instance_valid(charge_ring): charge_ring.queue_free()
	visual = null; charge_ring = null
	attack_held = false

func press_attack() -> void:
	if not _can_input(): return
	attack_held = true
	if state == "throw" and not _throw_launched:
		_recall_requested = true; _attack_after_recall = true
		return
	if special_state != "idle":
		_attack_after_recall = true
		if not _launched_explosive: _begin_return()
		return
	_attack_buffer = float(tuning.input_buffer)
	if g.dash_time > 0 and not _dash_struck:
		_begin_dash_strike()
	elif state == "idle":
		_begin_thrust()

func release_attack() -> void:
	attack_held = false
	if not _can_input(): return # Record release during pause; resolve on resume.
	if state == "charge":
		if charge_tier > 0: _begin_spin(charge_tier)
		else: _idle()

func press_special() -> void:
	if not _can_input(): return
	special_held = true
	attack_held = false; _attack_buffer = 0
	if state == "special_charge": return
	if state == "throw" and not _throw_launched:
		_recall_requested = true; _attack_after_recall = false
		return
	if special_state != "idle":
		_attack_after_recall = false
		if not _launched_explosive: _begin_return()
		return
	_special_buffer = float(tuning.special_buffer)
	if state in ["idle","charge"] or _may_cancel(): _begin_throw()

func release_special() -> void:
	# Resolution stays in tick, including a release while a modal is open.
	special_held = false

func dash_request() -> bool:
	if not _can_input(): return false
	_dash_struck = false
	if state == "charge" and charge_tier > 0:
		_spin_tier = charge_tier
		pending_dash_spin = true
		state = "dash_spin"; elapsed = 0; move_multiplier = 1.0
		_attack_buffer = 0; _special_buffer = 0
	elif state != "dash_spin":
		_dash_attack_pending = attack_held and special_state == "idle"
		_idle()
		_attack_buffer = 0; _special_buffer = 0
		combo = 0; _combo_left = 0
	return true

func tick(delta: float) -> void:
	if g == null or not is_instance_valid(g.player): return
	_ensure_visual()
	if g.mode != "raid":
		_pose_idle(delta)
		return
	# Bounded substeps keep active windows and wall sweeps reliable at low FPS.
	var remaining := minf(delta,.5)
	while remaining > .00001:
		var dt := minf(remaining,1.0/120.0)
		_step(dt)
		remaining -= dt

func _step(dt: float) -> void:
	_attack_buffer = maxf(0,_attack_buffer-dt)
	_special_buffer = maxf(0,_special_buffer-dt)
	_combo_left = maxf(0,_combo_left-dt)
	_route_cooldown = maxf(0,_route_cooldown-dt)
	elapsed += dt
	_tick_special(dt)
	if _dash_attack_pending and g.dash_time > 0 and special_state == "idle":
		_dash_attack_pending = false
		_begin_dash_strike()
	match state:
		"idle":
			move_multiplier = 1.0
			if special_state == "idle":
				if _special_buffer > 0: _begin_throw()
				elif _attack_buffer > 0: _begin_thrust()
				else: _pose_idle(dt)
			if _combo_left <= 0: combo = 0
		"charge": _tick_charge(dt)
		"special_charge": _tick_special_charge(dt)
		"dash_spin":
			if elapsed >= float(tuning.dash_spin_delay):
				pending_dash_spin = false
				_begin_spin(_spin_tier)
		"thrust", "dash_strike", "spin": _tick_attack(dt)
		"throw":
			_pose_throw()
			if not _throw_launched and elapsed >= float(tuning.throw_windup): _launch_throw()
			if elapsed >= float(tuning.throw_windup)+float(tuning.throw_recovery): _idle()
		"recall":
			move_multiplier = 1.0
			if special_state == "idle": _idle()
	if is_instance_valid(charge_ring):
		charge_ring.visible = state in ["charge","dash_spin","special_charge"]
		charge_ring.position = g.player.position + Vector3(0,.055,0)
		charge_ring.scale = Vector3.ONE * lerpf(1.5,4.4,charge_ratio)
		charge_ring.rotation.y += dt*(1.5+charge_ratio*4)

func _can_input() -> bool:
	return g != null and is_instance_valid(g.player) and g.mode == "raid"

func _aim() -> Vector3:
	var value: Vector3 = g.direction
	value.y = 0
	return value.normalized() if value.length_squared() > .001 else Vector3.FORWARD

func facing_direction() -> Vector3:
	return _facing if is_direction_locked() else _aim()

func is_direction_locked() -> bool:
	return state in ["thrust","dash_strike","spin","throw"]

func _idle() -> void:
	state = "idle"; elapsed = 0; move_multiplier = 1.0
	charge_time = 0; charge_ratio = 0; charge_tier = 0
	pending_dash_spin = false

func _begin_thrust() -> void:
	if special_state != "idle": return
	combo = combo % 3 + 1 if _combo_left > 0 else 1
	var speed := .48 if has_hammer("flurry_jab") else 1.0
	_begin_attack("thrust",float(tuning.thrust_damage[combo-1]),float(tuning.thrust_reach[combo-1])*_hammer("extending_jab","reach_multiplier",1),float(tuning.thrust_radius),float(tuning.thrust_windup[combo-1])*speed,float(tuning.thrust_active[combo-1])*speed,float(tuning.thrust_recovery[combo-1])*speed)
	_combo_left = float(tuning.combo_window) + _duration
	g.sound.play("thrust",-17,1.0+(combo-1)*.07)

func _begin_dash_strike() -> void:
	if special_state != "idle" or _dash_struck: return
	_dash_struck = true
	_begin_attack("dash_strike",float(tuning.dash_damage),float(tuning.dash_reach),float(tuning.thrust_radius),float(tuning.dash_windup),float(tuning.dash_active),float(tuning.dash_recovery))
	combo = 0; _combo_left = 0
	# Hades dash-strikes trade dash safety for offense. Do not erase a longer
	# unrelated hurt invulnerability interval owned by the controller.
	if g.dash_time > 0 and g.invuln <= .181: g.invuln = 0
	g.sound.play("thrust",-15,1.2)

func _begin_attack(kind: String,damage: float,reach: float,radius: float,windup: float,active: float,recovery: float) -> void:
	# Aim assist: a player-triggered strike turns toward a nearby enemy first.
	if g != null and g.has_method("assist_aim"): g.assist_aim(reach+1.6)
	state = kind; elapsed = 0; _attack_buffer = 0
	_damage = damage; _reach = reach; _radius = radius
	# Equipment haste changes melee execution, not charge thresholds, projectiles
	# or hero skills. Snapshot it per move so its active windows stay consistent.
	_attack_speed = maxf(.1,1.0+float(g.gear_bonus.get("haste",0)))
	_windup = windup/_attack_speed; _active = active/_attack_speed
	_duration = (windup+active+recovery)/_attack_speed
	_facing = _aim(); _fx_started = false; attack_hits.clear()
	_lane_hits = [{},{},{}]
	_serrated_fx_index = -1
	move_multiplier = float(tuning.attack_move)
	g.squash_velocity = -2.0
	_last_tip = g.player.position + _facing*.5 + Vector3.UP*.9

func _may_cancel() -> bool:
	return state in ["thrust","dash_strike","spin"] and elapsed >= _windup+_active and bool(tuning.cancel_after_active)

func _tick_attack(dt: float) -> void:
	var active_now := elapsed >= _windup and elapsed < _windup+_active
	var progress := clampf((elapsed-_windup)/maxf(.01,_active),0,1)
	var origin: Vector3 = g.player.position
	if state == "spin":
		var facing := _facing.rotated(Vector3.UP,-TAU*progress)
		visual.position = origin + facing*.15 + Vector3.UP*.9
		visual.rotation = Vector3(0,atan2(-facing.x,-facing.z),0)
		visual.scale = Vector3.ONE * lerpf(1.0,1.18,float(_spin_tier)/3.0)
		if active_now: _damage_radius(origin,_reach,_damage,attack_hits,true,"spin")
	else:
		var extension := 0.0
		var visual_progress := fmod(progress*3,1.0) if state == "dash_strike" and has_hammer("serrated_point") else progress
		if elapsed < _windup: extension = lerpf(.05,-.28,elapsed/maxf(.01,_windup))
		elif active_now: extension = lerpf(-.28,_reach-2.15,1.0-pow(1.0-visual_progress,3))
		else: extension = lerpf(_reach-2.15,.05,clampf((elapsed-_windup-_active)/maxf(.01,_duration-_windup-_active),0,1))
		visual.position = origin + _facing*extension + Vector3.UP*.92
		visual.rotation = Vector3(0,atan2(-_facing.x,-_facing.z),0)
		visual.scale = Vector3.ONE
		if active_now:
			if state == "thrust" and has_hammer("triple_jab"):
				for lane in 3:
					var direction := _facing.rotated(Vector3.UP,(lane-1)*.28)
					_damage_segment(origin+direction*.12,origin+direction*_reach,_radius,_damage,attack_hits,false,"attack")
			elif state == "dash_strike" and has_hammer("serrated_point"):
				# Three distinct stabs, not one hit carrying triple damage.
				var index := clampi(int(progress*3),0,2)
				_damage_segment(origin+_facing*.12,origin+_facing*_reach,_radius,_damage,_lane_hits[index],false,"dash_attack")
				if index != _serrated_fx_index:
					_serrated_fx_index = index
					_fx("spear_thrust",origin,Color("d4efff"),_facing,_reach/3.15)
					g.sound.play("thrust",-22,1.1+index*.12)
			else:
				_damage_segment(origin+_facing*.12,origin+_facing*_reach,_radius,_damage,attack_hits,false,"dash_attack" if state == "dash_strike" else "attack")
			var active_arts = g.get("arts")
			var active_hero = g.get("hero_combat")
			if state == "thrust" and (active_arts == null or not active_arts.rushing) and (active_hero == null or not active_hero.controls_movement):
				g._move_actor(g.player,_facing*dt*1.25*_attack_speed,.42)
	if active_now:
		var tip: Vector3 = visual.position - visual.basis.z*2.25
		_trail(_last_tip,tip,Color("a9faff"))
		_last_tip = tip
		if not _fx_started:
			_fx_started = true
			g.squash_velocity = 3.2
			if state == "spin":
				_fx("spin",origin,Color("8eecff"),_facing,_reach/3.35)
				if g.has_method("_spear_sweep_fx"):
					g._spear_sweep_fx(origin,_reach,_spin_tier)
				g._ring_effect(origin,Color("ffc67a") if _spin_tier == 3 else Color("77eaff"),.1,_reach,.22)
			else:
				var lanes := 3 if state == "thrust" and has_hammer("triple_jab") else 1
				for lane in lanes:
					var direction := _facing.rotated(Vector3.UP,(lane-1)*.28 if lanes == 3 else 0.0)
					_trail(origin+Vector3.UP*.9,origin+direction*_reach+Vector3.UP*.9,Color("f1ffff"),.10)
					_fx("spear_thrust",origin,Color("a9faff"),direction,_reach/3.15)
	if _may_cancel():
		if _special_buffer > 0: _begin_throw(); return
		if _attack_buffer > 0: _begin_thrust(); return
	if elapsed >= _duration:
		var can_charge: bool = attack_held and state in ["thrust","dash_strike"]
		_idle()
		if can_charge:
			if has_hammer("flurry_jab"): _begin_thrust()
			else: _begin_charge()

func _begin_charge() -> void:
	state = "charge"; elapsed = 0; charge_time = 0; charge_ratio = 0; charge_tier = 0
	_pulse_elapsed = 0
	move_multiplier = float(tuning.charge_move)
	g.sound.play("spin_charge",-23,.8)

func _tick_charge(dt: float) -> void:
	charge_time += dt
	if has_hammer("flaring_spin"):
		_pulse_elapsed += dt
		if _pulse_elapsed >= _hammer("flaring_spin","charge_pulse_interval"):
			_pulse_elapsed = 0
			_damage_radius(g.player.position,2.4,40.0,{},false,"spin")
			g._ring_effect(g.player.position,Color("ffbd70"),.1,2.4,.22)
			_fx("spin",g.player.position,Color("ffbd70"),_aim(),.65)
	charge_ratio = clampf(charge_time/(_hammer("quick_spin","charge_full") if has_hammer("quick_spin") else float(tuning.charge_thresholds[2])),0,1)
	var previous := charge_tier
	charge_tier = 0
	if has_hammer("quick_spin"):
		charge_tier = 3 if charge_time >= .30 else (2 if charge_time >= .15 else 0)
	else:
		for threshold in tuning.charge_thresholds:
			if charge_time >= float(threshold): charge_tier += 1
	if charge_tier > previous:
		g._ring_effect(g.player.position,Color("ffd17a") if charge_tier == 3 else Color("73e8ff"),.3,float(tuning.spin_radius[charge_tier-1]),.18)
		g.sound.play("spin_charge",-22,1.0+charge_tier*.18)
		g.squash_velocity = -1.0-charge_tier*.5
	_facing = _aim()
	visual.position = g.player.position-_facing*.26+Vector3.UP*.92
	visual.rotation = Vector3(-.12,atan2(-_facing.x,-_facing.z)+.7,0)
	visual.scale = Vector3.ONE
	if not attack_held:
		if charge_tier > 0: _begin_spin(charge_tier)
		else: _idle()

func _begin_spin(tier: int) -> void:
	_spin_tier = clampi(tier,1,3)
	_begin_attack("spin",float(tuning.spin_damage[_spin_tier-1])*_hammer("massive_spin","spin_damage",1),float(tuning.spin_radius[_spin_tier-1])*_hammer("massive_spin","spin_radius",1),0,float(tuning.spin_windup),float(tuning.spin_active),float(tuning.spin_recovery)*_hammer("quick_spin","spin_recovery",1))
	attack_held = false; charge_ratio = 0; charge_tier = 0; pending_dash_spin = false
	combo = 0; _combo_left = 0
	g.sound.play("spin",-16,1.1-_spin_tier*.1)

func _begin_throw(charged: bool = false) -> void:
	if special_state != "idle": return
	if has_hammer("charged_skewer") and not charged:
		state = "special_charge"; elapsed = 0; _special_charge_time = 0
		charge_ratio = 0; move_multiplier = .15; _special_buffer = 0
		_special_power = 1; _facing = _aim(); _throw_direction = _facing
		g.sound.play("spin_charge",-22,.8)
		return
	if not charged: _special_power = 1; _special_range_multiplier = 1
	state = "throw"; elapsed = 0; _throw_launched = false
	_special_buffer = 0; _attack_buffer = 0; attack_held = false
	charge_ratio = 0; charge_time = 0; charge_tier = 0
	combo = 0; _combo_left = 0; move_multiplier = .35
	_facing = _aim(); _throw_direction = _facing

func _tick_special_charge(dt: float) -> void:
	_special_charge_time += dt
	charge_ratio = clampf(_special_charge_time/_hammer("charged_skewer","special_charge_time",.85),0,1)
	_facing = _aim(); _throw_direction = _facing
	visual.position = g.player.position-_facing*(.35+charge_ratio*.5)+Vector3.UP*1.08
	visual.rotation = Vector3(0,atan2(-_facing.x,-_facing.z),0)
	if not special_held:
		_special_power = 1.0+charge_ratio*_hammer("charged_skewer","special_charge_bonus",2)
		_special_range_multiplier = lerpf(.25,1.0,charge_ratio)
		_begin_throw(true)

func _pose_throw() -> void:
	if _throw_launched: return
	visual.position = g.player.position-_facing*.35+Vector3.UP*1.08
	visual.rotation = Vector3(0,atan2(-_facing.x,-_facing.z),0)
	visual.scale = Vector3.ONE

func _launch_throw() -> void:
	_throw_launched = true; special_state = "outbound"
	_projectile_pos = g.player.position+Vector3.UP*.95
	_travelled = 0; outbound_hits.clear(); return_hits.clear(); _route.clear()
	_chain_count = 0; _chain_target = null; _launched_explosive = has_hammer("exploding_launcher")
	g.sound.play("spear_throw",-16,1.0)
	if _recall_requested and not _launched_explosive:
		_recall_requested = false
		_begin_return()

func _begin_return() -> void:
	if special_state == "idle": return
	if special_state == "returning": return
	special_state = "returning"; state = "recall"; elapsed = 0
	_return_route_reset()
	return_hits.clear()
	g.sound.play("spear_recall",-16,1.0)

func _return_route_reset() -> void:
	_route.clear(); _route_cooldown = 0

func _tick_special(dt: float) -> void:
	if special_state == "idle": return
	var before := _projectile_pos
	if special_state == "outbound":
		if _chain_target != null and is_instance_valid(_chain_target.node) and _chain_target.hp > 0:
			var toward: Vector3 = _chain_target.node.position-before; toward.y = 0
			if toward.length_squared() > .0001: _throw_direction = toward.normalized()
		var max_range := float(tuning.throw_range)*_special_range_multiplier
		var distance := minf(float(tuning.throw_speed)*dt,max_range-_travelled)
		var desired := before+_throw_direction*distance
		_projectile_pos = _safe_end(before,desired)
		if _launched_explosive:
			var impacted = _first_target(before,_projectile_pos,{})
			if impacted != null:
				_projectile_pos = impacted.node.position+Vector3.UP*.95
				_explode_launcher()
				return
		else:
			var previous_count := _enemy_hit_count(outbound_hits)
			_damage_segment(before,_projectile_pos,float(tuning.special_radius),float(tuning.throw_damage)*_special_power*_hammer("chain_skewer","chain_damage",1),outbound_hits,false,"special")
			var next_count := _enemy_hit_count(outbound_hits)
			if has_hammer("chain_skewer") and next_count > previous_count:
				_chain_count = next_count
				_chain_target = _nearest_chain_target(_projectile_pos)
				if _chain_target != null and _chain_count < 7:
					_travelled = 0
					var turn: Vector3 = _chain_target.node.position-_projectile_pos; turn.y = 0
					_throw_direction = turn.normalized()
				else: special_state = "lodged"
		_travelled += before.distance_to(_projectile_pos)
		if _projectile_pos.distance_to(desired) > .005 or _travelled >= max_range-.01:
			if _launched_explosive:
				_explode_launcher()
				return
			special_state = "lodged"
			g._burst(_projectile_pos,Color("7fefff"),5)
	elif special_state == "returning":
		var home: Vector3 = g.player.position+Vector3.UP*.95
		if not g.world.line_blocked(_projectile_pos,home):
			_route.clear()
		elif _route.is_empty() and _route_cooldown <= 0:
			_route = _find_return_route(_projectile_pos,home)
			_route_cooldown = .18
		var target := home if _route.is_empty() else _route[0]
		var wanted := before.move_toward(target,float(tuning.return_speed)*dt)
		_projectile_pos = _safe_end(before,wanted)
		_damage_segment(before,_projectile_pos,float(tuning.special_radius),float(tuning.return_damage),return_hits,false,"special_return")
		if not _route.is_empty() and _projectile_pos.distance_to(target) < .06: _route.pop_front()
		if _projectile_pos.distance_to(wanted) > .005: _return_route_reset()
		if _projectile_pos.distance_to(home) < .35 and not g.world.line_blocked(_projectile_pos,home):
			special_state = "idle"
			_idle()
			if _attack_after_recall:
				_attack_after_recall = false
				_begin_thrust()
			return
	visual.position = _projectile_pos
	visual.scale = Vector3.ONE
	var movement := _projectile_pos-before
	var facing: Vector3 = movement.normalized() if movement.length_squared() > .000001 else _throw_direction
	facing.y = 0
	if facing.length_squared() > .001: visual.rotation = Vector3(0,atan2(-facing.x,-facing.z),0)
	if movement.length() > .01: _trail(before,_projectile_pos,Color("ffc77b") if special_state == "returning" else Color("94faff"))

func _first_target(from: Vector3,to: Vector3,hits: Dictionary):
	var selected = null
	var nearest := INF
	for enemy in g.enemies:
		if enemy.hp <= 0 or not is_instance_valid(enemy.node) or hits.has(enemy.node.get_instance_id()): continue
		var p: Vector3 = enemy.node.position; p.y = from.y
		if Geometry3D.get_closest_point_to_segment(p,from,to).distance_to(p) > float(tuning.special_radius)+.35: continue
		if g.world.line_blocked(from,p): continue
		var distance := from.distance_squared_to(p)
		if distance < nearest: selected = enemy; nearest = distance
	return selected

func _enemy_hit_count(hits: Dictionary) -> int:
	var count := 0
	for key in hits:
		if key is int: count += 1
	return count

func _nearest_chain_target(origin: Vector3):
	var selected = null
	var nearest := 6.0*6.0
	for enemy in g.enemies:
		if enemy.hp <= 0 or not is_instance_valid(enemy.node) or outbound_hits.has(enemy.node.get_instance_id()): continue
		var p: Vector3 = enemy.node.position; p.y = origin.y
		var distance := origin.distance_squared_to(p)
		if distance < nearest and not g.world.line_blocked(origin,p):
			selected = enemy; nearest = distance
	return selected

func _explode_launcher() -> void:
	_damage_radius(_projectile_pos,2.5,50.0*_special_power,{},true,"special")
	g._ring_effect(_projectile_pos,Color("ffc17c"),.1,2.5,.3)
	g._burst(_projectile_pos,Color("ffc17c"),22)
	_fx("impact",_projectile_pos,Color("ffc17c"),_throw_direction,2.0)
	g.sound.play("impact",-16,.7)
	special_state = "idle"; _launched_explosive = false; _recall_requested = false
	if state == "recall": _idle()
	if _attack_after_recall:
		_attack_after_recall = false
		_begin_thrust()

func _safe_end(from: Vector3,to: Vector3) -> Vector3:
	if not g.world.line_blocked(from,to): return to
	var low := 0.0
	var high := 1.0
	for unused in 10:
		var middle := (low+high)*.5
		if g.world.line_blocked(from,from.lerp(to,middle)): high = middle
		else: low = middle
	return from.lerp(to,maxf(0,low-.002))

func _find_return_route(from: Vector3,to: Vector3) -> Array[Vector3]:
	# A small collision-aware grid is only built when the direct recall line is
	# blocked. This prevents an unreturnable spear after moving behind cover.
	var result: Array[Vector3] = []
	var cell: float = tuning.navigation_step
	var origin := Vector2(floorf(minf(from.x,to.x)/cell)*cell-3, floorf(minf(from.z,to.z)/cell)*cell-3)
	var width := mini(64,ceili((absf(from.x-to.x)+6)/cell)+1)
	var height := mini(64,ceili((absf(from.z-to.z)+6)/cell)+1)
	var start := Vector2i(roundi((from.x-origin.x)/cell),roundi((from.z-origin.y)/cell))
	var goal := Vector2i(roundi((to.x-origin.x)/cell),roundi((to.z-origin.y)/cell))
	var queue: Array[Vector2i] = [start]
	var parents: Dictionary = {start:start}
	var cursor := 0
	var found := false
	while cursor < queue.size() and cursor < 4096:
		var current: Vector2i = queue[cursor]; cursor += 1
		var p := Vector3(origin.x+current.x*cell,.95,origin.y+current.y*cell)
		if current == start: p = from
		if p.distance_to(to) < cell*1.6 and not g.world.line_blocked(p,to): goal = current; found = true; break
		for offset in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
			var next: Vector2i = current+offset
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height or parents.has(next): continue
			var n := Vector3(origin.x+next.x*cell,.95,origin.y+next.y*cell)
			if g.world.blocked(n,.13) or g.world.line_blocked(p,n): continue
			parents[next] = current; queue.append(next)
	if not found: return result
	var at := goal
	while at != start:
		result.push_front(g.world.ground_position(Vector3(origin.x+at.x*cell,0,origin.y+at.y*cell))+Vector3.UP*.95)
		at = parents[at]
	result.append(to)
	return result

func _damage_segment(from: Vector3,to: Vector3,radius: float,damage: float,hits: Dictionary,heavy: bool,kind: String = "attack") -> void:
	var a := Vector3(from.x,0,from.z)
	var is_melee := kind in ["attack","dash_attack"]
	if is_melee: a = Vector3(g.player.position.x,0,g.player.position.z)
	var b := _safe_end(a,Vector3(to.x,0,to.z))
	for enemy in g.enemies.duplicate():
		if kind == "special" and has_hammer("chain_skewer") and _enemy_hit_count(hits) >= 7: break
		if enemy.hp <= 0 or not is_instance_valid(enemy.node): continue
		var key: int = enemy.node.get_instance_id()
		if hits.has(key): continue
		var p: Vector3 = enemy.node.position; p.y = 0
		# Include overlapping bodies at the feet, while rejecting genuine rear
		# targets. A forward capsule must not turn into a circular melee attack.
		var offset := p-a
		if is_melee and offset.length() > .3 and offset.dot(_facing) < -.05: continue
		var closest := Geometry3D.get_closest_point_to_segment(p,a,b)
		if closest.distance_to(p) > radius+.35 or g.world.line_blocked(a,p): continue
		hits[key] = true
		var value := damage
		if kind == "attack" and has_hammer("extending_jab") and Vector2(g.player.position.x,g.player.position.z).distance_to(Vector2(p.x,p.z)) >= 3.48: value *= 1.4
		_impact(enemy,value,(b-a).normalized(),heavy,kind,a)
	if g.has_method("damage_breakables_segment"):
		g.damage_breakables_segment(a,b,radius,_scaled(damage),hits)
	if g.has_method("combat_sweep"):
		g.combat_sweep(a,b,radius,kind,hits)

func _damage_radius(center: Vector3,radius: float,damage: float,hits: Dictionary,heavy: bool,kind: String = "spin") -> void:
	for enemy in g.enemies.duplicate():
		if enemy.hp <= 0 or not is_instance_valid(enemy.node): continue
		var key: int = enemy.node.get_instance_id()
		if hits.has(key): continue
		var to: Vector3 = enemy.node.position-center; to.y = 0
		if to.length() > radius+.35 or g.world.line_blocked(center,enemy.node.position): continue
		hits[key] = true
		_impact(enemy,damage,to.normalized(),heavy,kind,center)
	if g.has_method("damage_breakables_radius"):
		g.damage_breakables_radius(center,radius,_scaled(damage),hits)
	if g.has_method("combat_burst"):
		g.combat_burst(center,radius,kind,hits)

func _scaled(damage: float) -> float:
	return damage*(1.0+float(g.gear_bonus.get("damage",0))+int(g.taken.get("power",0))*.25+int(g.data.profile.upgrades.reactor)*.12)

func _impact(enemy: Dictionary,damage: float,away: Vector3,heavy: bool,kind: String,origin: Vector3) -> void:
	enemy["stagger"] = float(tuning.heavy_stagger if heavy else tuning.normal_stagger)
	enemy["knockback"] = away*float(tuning.heavy_knockback if heavy else tuning.normal_knockback)*(.2 if enemy.get("kind","") == "boss" else 1.0)
	enemy.windup = 0
	enemy.cooldown = maxf(float(enemy.get("cooldown",0)),.25)
	if is_instance_valid(enemy.get("telegraph")): enemy.telegraph.queue_free()
	enemy.telegraph = null
	if kind in ["special","special_return"]:
		damage *= _hammer("vicious_skewer","special_damage",1)
		if has_hammer("breaching_skewer") and float(enemy.get("armor",0)) > 0:
			# Armor-only amplification never overflows into health damage.
			var permanent_scale: float = g.talent_damage_multiplier() if g.has_method("talent_damage_multiplier") else 1.0
			enemy.armor = maxf(0,float(enemy.armor)-_scaled(damage)*4.0*permanent_scale)
	if g.has_method("combat_hit"):
		g.combat_hit(enemy,_scaled(damage),kind,origin,away)
	else:
		g.hit_enemy(enemy,_scaled(damage),false)
	g.hit_pause = maxf(g.hit_pause,float(tuning.heavy_hit_stop if heavy else tuning.normal_hit_stop))
	g.shake = maxf(g.shake,.11 if heavy else .045)
	g._burst(enemy.node.position+Vector3.UP*.85,Color("ffe0a0") if heavy else Color("c3faff"),12 if heavy else 6)
	g.sound.play("impact",-19,.85 if heavy else 1.15)
	_fx("impact",enemy.node.position+Vector3.UP*.85,Color("b4edff"),away,1.2 if heavy else .6)

func _fx(kind: String,pos: Vector3,color: Color,direction: Vector3,scale_factor: float) -> void:
	if g.has_method("play_combat_fx"): g.play_combat_fx(kind,pos,color,direction,scale_factor)

func _trail(from: Vector3,to: Vector3,color: Color,width: float = .065) -> void:
	if from.distance_to(to) < .02 or g.effects.size() >= 250: return
	var node = g._beam(from,to,color,width)
	g.effects.append({"node":node,"life":.12,"max":.12,"vel":Vector3.ZERO,"grow":-1.0})

func _ensure_visual() -> void:
	if is_instance_valid(g.hand_sword): g.hand_sword.visible = false
	if is_instance_valid(visual): return
	visual = Node3D.new(); visual.name = "ActiveSpear"
	g.actors.add_child(visual)
	g.world.box(visual,Vector3(0,0,-.55),Vector3(.105,.105,2.6),Color("344650"))
	g.world.box(visual,Vector3(0,.01,-.62),Vector3(.045,.045,2.25),Color("7aefff"),1.2)
	for z in [-.12,-.3,-.48]:
		g.world.box(visual,Vector3(0,0,z),Vector3(.16,.16,.06),Color("d8ad67"),.15)
	g.world.box(visual,Vector3(0,0,-1.82),Vector3(.35,.18,.14),Color("e8bd74"),.4)
	var left = g.world.box(visual,Vector3(-.095,0,-2.06),Vector3(.12,.12,.56),Color("ddfbff"),.7)
	left.rotation.y = -.32
	var right = g.world.box(visual,Vector3(.095,0,-2.06),Vector3(.12,.12,.56),Color("ddfbff"),.7)
	right.rotation.y = .32
	g.world.box(visual,Vector3(0,0,-2.29),Vector3(.07,.07,.22),Color("a2f7ff"),1.3)
	g.world.box(visual,Vector3(0,0,.81),Vector3(.13,.13,.24),Color("cba36b"),.2)
	charge_ring = Node3D.new(); charge_ring.name = "SpearChargeRing"
	g.actors.add_child(charge_ring)
	for i in 20:
		var a := TAU*i/20.0
		var mark = g.world.box(charge_ring,Vector3(cos(a),0,sin(a)),Vector3(.15,.018,.035),Color("80edff"),1.1)
		mark.rotation.y = -a+PI*.5
	charge_ring.visible = false

func _pose_idle(delta: float) -> void:
	if not is_instance_valid(visual) or special_state != "idle": return
	var facing := _aim()
	var side := facing.rotated(Vector3.UP,-PI*.5)
	visual.position = visual.position.lerp(g.player.position+side*.43+Vector3.UP*.9,minf(1,delta*25))
	visual.rotation = Vector3(-.08,atan2(-facing.x,-facing.z),-.04)
	visual.scale = Vector3.ONE
