extends RefCounted
## Skill clocks are local: enemies use enemy_time_scale/clock, while the player,
## weapons and hit presentation continue on the normal raid delta.
const DEFAULTS := {
	"time_cost":40.0,"time_cooldown":12.0,"time_duration":3.0,"time_recovery":.25,
	"rush_cost":35.0,"rush_cooldown":8.0,"rush_duration":.8,"rush_steps":5,
	"rush_step_time":.145,"rush_gap":.015,"rush_speed":43.0,"rush_range":6.2,
	"rush_damage":32.0,"rush_final_damage":48.0,"rush_radius":.8,
	"player_radius":.42,"target_overshoot":.7,"empty_dash_range":4.8
}
var g
var tuning: Dictionary = DEFAULTS.duplicate(true)
var time_left := 0.0
var time_cd := 0.0
var rush_cd := 0.0
var rushing := false
var rush_step := 0
var rush_hits: Dictionary = {}
var enemy_clock := 0.0
var frozen_enemies: bool:
	get: return time_left > 0
var enemy_time_scale: float:
	get:
		if time_left > 0: return 0.0
		if _recovery_left <= 0: return 1.0
		var ratio := 1.0-_recovery_left/maxf(.001,float(tuning.time_recovery))
		return ratio*ratio*(3.0-2.0*ratio)
var rush_invulnerable: bool:
	get: return rushing and _step_left > 0 and _moving_step and _valid_raid()
var _recovery_left := 0.0
var _rush_left := 0.0
var _step_left := 0.0
var _gap_left := 0.0
var _trail_left := 0.0
var _moving_step := false
var _empty_step := false
var _intent := Vector3.FORWARD
var _rush_direction := Vector3.FORWARD
var _destination := Vector3.ZERO
var _origin := Vector3.ZERO
var _target = null
var _auto_target := false

func _init(controller) -> void:
	g = controller

func configure_talents(bonuses: Dictionary) -> void:
	# Rebuild from defaults once per loadout; reset() only clears active clocks.
	tuning = DEFAULTS.duplicate(true)
	var cost_scale := 1.0-clampf(float(bonuses.get("skill_cost_reduction",0)),0,.8)
	var cooldown_scale := 1.0-clampf(float(bonuses.get("skill_cooldown_reduction",0)),0,.8)
	for key in ["time_cost","rush_cost"]: tuning[key] *= cost_scale
	for key in ["time_cooldown","rush_cooldown"]: tuning[key] *= cooldown_scale
	tuning.time_duration += maxf(0,float(bonuses.get("time_duration",0)))
	var reach := maxf(0,float(bonuses.get("rush_range",0)))
	tuning.rush_range += reach
	tuning.empty_dash_range += reach
	# A larger search radius must also be reachable within the same dash budget.
	tuning.rush_speed *= float(tuning.rush_range)/float(DEFAULTS.rush_range)
	var damage_scale := 1.0+maxf(0,float(bonuses.get("rush_damage",0)))
	tuning.rush_damage *= damage_scale
	tuning.rush_final_damage *= damage_scale

func trigger_time_stop() -> bool:
	if not _valid_raid() or time_cd > .00001 or time_left > 0 or g.mana < float(tuning.time_cost): return false
	g.mana -= float(tuning.time_cost)
	time_cd = float(tuning.time_cooldown)
	time_left = float(tuning.time_duration)
	_recovery_left = 0
	_fx("time_stop",g.player.position,Color("85dcff"),_aim(),1.0)
	_sound("impact",-15,.65)
	_sound("tick",-23,.7)
	return true

func trigger_rush(auto_target: bool = false) -> bool:
	if not _valid_raid() or rushing or rush_cd > .00001 or g.mana < float(tuning.rush_cost): return false
	g.mana -= float(tuning.rush_cost)
	rush_cd = float(tuning.rush_cooldown)
	rushing = true; rush_step = 0; rush_hits.clear()
	_auto_target = auto_target
	_rush_left = float(tuning.rush_duration); _step_left = 0; _gap_left = 0
	_trail_left = 0; _intent = _aim()
	_begin_step(true)
	return true

func tick(delta: float) -> void:
	if not _valid_raid():
		cancel_active()
		return
	# Clocks use the full supplied raid delta, including low-FPS frames. Rush
	# movement is substepped and independently bounded by its .8 second budget.
	var remaining := maxf(0,delta)
	while remaining > .000001:
		var dt := minf(remaining,1.0/120.0)
		_tick_time(dt)
		if rushing: _tick_rush(dt)
		remaining -= dt
		if not _valid_raid(): cancel_active(); return

func _tick_time(dt: float) -> void:
	time_cd = maxf(0,time_cd-dt)
	rush_cd = maxf(0,rush_cd-dt)
	if time_left > 0:
		var old := time_left
		time_left = maxf(0,time_left-dt)
		if time_left <= 0:
			_recovery_left = float(tuning.time_recovery)
			_fx("time_shatter",g.player.position,Color("a8efff"),_aim(),1.0)
			_sound("spear_recall",-19,.8)
			var overflow := maxf(0,dt-old)
			_recovery_left = maxf(0,_recovery_left-overflow)
			enemy_clock += overflow*enemy_time_scale
	else:
		_recovery_left = maxf(0,_recovery_left-dt)
		enemy_clock += dt*enemy_time_scale

func _tick_rush(dt: float) -> void:
	_rush_left = maxf(0,_rush_left-dt)
	if _rush_left <= 0: _finish_rush(); return
	if _gap_left > 0:
		_gap_left = maxf(0,_gap_left-dt)
		if _gap_left <= 0: _begin_step(false)
		return
	if _step_left <= 0: _finish_rush(); return
	_step_left = maxf(0,_step_left-dt)
	var from: Vector3 = g.player.position
	var desired := from.move_toward(_destination,float(tuning.rush_speed)*dt)
	var safe := _safe_destination(from,desired)
	if safe.distance_to(from) > .0001:
		g._move_actor(g.player,safe-from,float(tuning.player_radius))
	var to: Vector3 = g.player.position
	_moving_step = from.distance_squared_to(to) > .000001
	if _moving_step:
		g.direction = _rush_direction
		_hit_segment(from,to)
		_trail_left -= dt
		if _trail_left <= 0:
			_trail_left = .035
			_fx("afterimage",from,Color("99eaff"),_rush_direction,.85)
	if not _valid_raid(): cancel_active(); return
	var arrived := to.distance_to(_destination) < .09
	var blocked := desired.distance_to(from) > .01 and to.distance_to(from) < .002
	if arrived or blocked or _step_left <= 0:
		_step_left = 0; _moving_step = false
		if _empty_step or rush_step >= int(tuning.rush_steps) or _next_target() == null:
			_finish_rush()
		else: _gap_left = float(tuning.rush_gap)

func _begin_step(allow_empty: bool) -> void:
	if not _valid_raid() or rush_step >= int(tuning.rush_steps): _finish_rush(); return
	_target = _next_target()
	_empty_step = _target == null
	if _empty_step and not allow_empty: _finish_rush(); return
	_origin = g.player.position
	if _empty_step:
		_rush_direction = _intent
		_destination = _origin+_intent*float(tuning.empty_dash_range)
	else:
		var toward: Vector3 = _target.node.position-_origin; toward.y = 0
		_rush_direction = toward.normalized() if toward.length_squared() > .001 else _intent
		_destination = _target.node.position+_rush_direction*float(tuning.target_overshoot)
		_destination.y = _origin.y
		_destination = _origin.move_toward(_destination,float(tuning.rush_range))
	_destination = _safe_destination(_origin,_destination)
	if _destination.distance_to(_origin) < .08: _finish_rush(); return
	rush_step += 1; _step_left = float(tuning.rush_step_time); _moving_step = true
	_trail_left = 0; _gap_left = 0
	_fx("rush_slash",_origin,Color("c4f5ff"),_rush_direction,1.3 if rush_step == int(tuning.rush_steps) else 1.0)
	_fx("speed_lines",_origin,Color("bdf4ff"),_rush_direction,1.0)
	# Presentation only: floor slabs ripple along the dash route, camera reacts.
	if g.get("world") != null and g.world.has_method("pulse_path"): g.world.pulse_path(_origin,_destination,1.0 if rush_step < int(tuning.rush_steps) else 1.35)
	if g.has_method("on_rush_step"): g.on_rush_step(rush_step,_origin,_destination)
	_sound("dash",-18,1.0+float(rush_step)*.08)

func _next_target():
	if not _valid_raid(): return null
	var selected = null
	var best := INF
	var from: Vector3 = g.player.position
	for enemy in g.enemies:
		if not _valid_enemy(enemy) or rush_hits.has(enemy.node.get_instance_id()): continue
		var toward: Vector3 = enemy.node.position-from; toward.y = 0
		var distance := toward.length()
		if distance > float(tuning.rush_range)-.25 or g.world.line_blocked(from,enemy.node.position): continue
		# A clear center ray is insufficient for the player's body: reject paths
		# too narrow for its radius before consuming a step chasing that target.
		var destination: Vector3 = enemy.node.position; destination.y = from.y
		if _safe_destination(from,destination).distance_to(destination) > .12: continue
		var alignment := _intent.dot(toward.normalized()) if distance > .01 else 1.0
		var score := distance if _auto_target else distance+(1.0-alignment)*(3.5 if rush_step == 0 else .8)
		if score < best: selected = enemy; best = score
	return selected

func _safe_destination(from: Vector3,to: Vector3) -> Vector3:
	var steps := maxi(1,ceili(from.distance_to(to)/.12))
	var last := from
	for i in range(1,steps+1):
		var point := from.lerp(to,float(i)/steps)
		if _blocked(point) or g.world.line_blocked(last,point): return last
		last = point
	return to

func _blocked(pos: Vector3) -> bool:
	if g.has_method("_position_blocked"): return g._position_blocked(pos,float(tuning.player_radius))
	return g.world.blocked(pos,float(tuning.player_radius))

func _hit_segment(from: Vector3,to: Vector3) -> void:
	var damage := float(tuning.rush_final_damage) if rush_step == int(tuning.rush_steps) else float(tuning.rush_damage)
	var a := Vector3(from.x,0,from.z)
	var b := Vector3(to.x,0,to.z)
	for enemy in g.enemies.duplicate():
		if not _valid_raid(): return
		if not _valid_enemy(enemy): continue
		var key: int = enemy.node.get_instance_id()
		if rush_hits.has(key): continue
		var p: Vector3 = enemy.node.position; p.y = 0
		var closest := Geometry3D.get_closest_point_to_segment(p,a,b)
		if p.distance_to(closest) > float(tuning.rush_radius)+.35 or g.world.line_blocked(closest,p): continue
		rush_hits[key] = true
		g.combat_hit(enemy,damage,"attack",a,_rush_direction)
		_fx("rush_slash",enemy.node.position+Vector3.UP*.7,Color("effcff"),_rush_direction,.7)
	if g.has_method("damage_breakables_segment"):
		g.damage_breakables_segment(a,b,float(tuning.rush_radius),damage,rush_hits)
	if g.has_method("combat_sweep"):
		g.combat_sweep(a,b,float(tuning.rush_radius),"attack",rush_hits)

func _finish_rush() -> void:
	rushing = false; _rush_left = 0; _step_left = 0; _gap_left = 0; _moving_step = false
	_target = null

func cancel_active() -> void:
	# No shared invulnerability, time_scale or velocity was acquired, so cancel
	# cannot erase hurt protection or leave a latent global modifier behind.
	time_left = 0; _recovery_left = 0
	_finish_rush()

func reset() -> void:
	cancel_active()
	_auto_target = false
	time_cd = 0; rush_cd = 0; rush_step = 0; rush_hits.clear(); enemy_clock = 0

func dispose() -> void:
	reset()
	g = null

func _valid_raid() -> bool:
	return g != null and is_instance_valid(g.player) and g.mode == "raid" and g.hp > 0

func _valid_enemy(enemy: Dictionary) -> bool:
	return float(enemy.get("hp",0)) > 0 and is_instance_valid(enemy.get("node")) and not enemy.node.is_queued_for_deletion()

func _aim() -> Vector3:
	var direction: Vector3 = g.direction; direction.y = 0
	return direction.normalized() if direction.length_squared() > .001 else Vector3.FORWARD

func _fx(kind: String,pos: Vector3,color: Color,direction: Vector3,size: float) -> void:
	if g != null and g.has_method("play_combat_fx"): g.play_combat_fx(kind,pos,color,direction,size)

func _sound(id: String,db: float,pitch: float) -> void:
	if g != null and g.sound != null: g.sound.play(id,db,pitch)
