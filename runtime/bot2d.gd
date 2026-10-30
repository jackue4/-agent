extends Node
## Autoplay bot for 2D platformer levels (test tool, native only: --bot=<platform ids>).
## Follows the critical path computed by the server's reachability model through the *real*
## runtime physics by pressing input actions, so it verifies that a level the static checker
## calls reachable is actually beatable. Prints one machine-readable result line and quits:
##   [bot] result=win|lose|timeout time=<s> lives=<n> step=<i>/<n> pos=<x,y>
const TIMEOUT := 120.0
## Horizontal look-ahead (px) at which the bot takes off before the edge of its platform.
const EDGE_MARGIN := 26.0

var main = null
var path: Array[String] = []
var step := 0
var t := 0.0
var holding_jump := false
var stuck_t := 0.0
var last_x := 0.0
var done := false

func setup(m, ids: Array[String]) -> void:
	main = m
	path = ids

func _physics_process(delta: float) -> void:
	if done or main == null or main.world == null:
		return
	if main.state == main.State.OVER:
		_finish("win" if main.lives > 0 else "lose")
		return
	if main.state != main.State.PLAYING:
		return
	t += delta
	if t > TIMEOUT:
		_finish("timeout")
		return
	var p = main.world.player
	if p == null or not is_instance_valid(p):
		return
	_steer(p, delta)

## Rect of a path node in Godot coords (y down); the goal is the final target.
func _rect(id: String) -> Rect2:
	var e = main.world.ents.get(id)
	if e == null or not is_instance_valid(e):
		return Rect2()
	return Rect2(e.global_position - e.size * 0.5, e.size)

func _steer(p, delta: float) -> void:
	var feet: Vector2 = p.global_position + Vector2(0, p.size.y * 0.5)
	var on_floor: bool = p.is_on_floor()
	# advance along the path once we stand on (or are inside) the next node
	while step + 1 < path.size():
		var nr := _rect(path[step + 1])
		var over := feet.x > nr.position.x - 4.0 and feet.x < nr.end.x + 4.0 and feet.y < nr.position.y + 14.0
		# platforms count once we stand at/above their top; bouncers and the goal once touched
		var e = main.world.ents.get(path[step + 1])
		var solid_kind: bool = e != null and e.kind == "platform"
		if over and (on_floor or not solid_kind):
			step += 1
		else:
			break
	var target_x: float
	var want_jump := false
	if step + 1 < path.size():
		var cur := _rect(path[step])
		var nxt := _rect(path[step + 1])
		var rise := cur.position.y - nxt.position.y  # >0: next top is higher
		var dir := 1.0 if nxt.get_center().x > feet.x else -1.0
		# aim a little inside the near edge of the next platform
		var near_edge := nxt.position.x if dir > 0.0 else nxt.end.x
		target_x = near_edge + dir * minf(60.0, nxt.size.x * 0.4)
		var overlap := feet.x > nxt.position.x and feet.x < nxt.end.x
		var cur_edge := cur.end.x if dir > 0.0 else cur.position.x
		var to_edge := (cur_edge - feet.x) * dir
		var gap := (near_edge - feet.x) * dir
		if on_floor:
			if overlap and rise > 8.0:
				want_jump = true  # platform directly overhead (one-way): jump through
			elif rise > 8.0 and gap < 40.0 + rise * 0.9:
				want_jump = true  # step up: take off early enough to clear the lip
			elif to_edge < EDGE_MARGIN and gap > 0.0:
				want_jump = true  # gap: jump at the edge
	else:
		var g := _rect(path[path.size() - 1])
		target_x = g.get_center().x
		if on_floor and g.position.y + g.size.y < feet.y - 10.0 and absf(target_x - feet.x) < 80.0:
			want_jump = true
	var dx := target_x - feet.x
	if on_floor and _danger_ahead(p, signf(dx)):
		want_jump = true
	_press("move_right", dx > 6.0)
	_press("move_left", dx < -6.0)
	if want_jump and not holding_jump:
		holding_jump = true
		Input.action_press("jump")
	elif holding_jump and (on_floor and not want_jump or p.velocity.y > 0.0):
		holding_jump = false
		Input.action_release("jump")
	# stuck detection: nudge with a jump if we have not moved for a while
	if absf(p.global_position.x - last_x) < 1.0 and absf(dx) > 20.0:
		stuck_t += delta
		if stuck_t > 0.6 and on_floor:
			stuck_t = 0.0
			holding_jump = true
			Input.action_press("jump")
	else:
		stuck_t = 0.0
	last_x = p.global_position.x

## An alive enemy or hazard within reach in the walking direction at body height: jump over
## it (landing on an enemy stomps it).
func _danger_ahead(p, dir: float) -> bool:
	if dir == 0.0:
		return false
	var ppos: Vector2 = p.global_position
	var psize: Vector2 = p.size
	var pr := Rect2(ppos - psize * 0.5, psize)
	for e in main.world.ents.values():
		if not is_instance_valid(e) or not (e.kind in ["enemy", "hazard"]) or not e.alive:
			continue
		var epos: Vector2 = e.global_position
		var esize: Vector2 = e.size
		var er := Rect2(epos - esize * 0.5, esize)
		var ahead := (er.get_center().x - pr.get_center().x) * dir
		var reach: float = 70.0 + (p.size.x + er.size.x) * 0.5 + absf(p.velocity.x) * 0.12
		if ahead > 0.0 and ahead < reach and er.end.y > pr.position.y and er.position.y < pr.end.y + 8.0:
			return true
	return false

func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)

func _finish(result: String) -> void:
	done = true
	var pos := Vector2.ZERO
	if main.world.player and is_instance_valid(main.world.player):
		pos = main.world.player.global_position
	print("[bot] result=%s time=%.1f lives=%d step=%d/%d pos=%d,%d" % [result, t, main.lives, step, path.size() - 1, roundi(pos.x), roundi(-pos.y)])
	for a in ["move_left", "move_right", "jump"]:
		Input.action_release(a)
	main.get_tree().quit(0 if result == "win" else 2)
