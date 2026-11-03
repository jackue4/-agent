class_name Player
extends Node2D
## The stick-figure brawler: combo strikes, ground slam, dash, roguelike skills.

signal leveled_up
signal died

const RADIUS := 18.0
const P_IDLE := {"hip": Vector2(0, -42), "neck": Vector2(3, -84), "head": Vector2(6, -102), "eR": Vector2(17, -66), "hR": Vector2(25, -80), "eL": Vector2(-5, -64), "hL": Vector2(9, -77), "kR": Vector2(13, -22), "fR": Vector2(17, 0), "kL": Vector2(-10, -22), "fL": Vector2(-15, 0)}
const P_JAB_W := {"hip": Vector2(-2, -42), "neck": Vector2(-3, -84), "head": Vector2(-1, -102), "eR": Vector2(4, -66), "hR": Vector2(10, -78), "eL": Vector2(-8, -64), "hL": Vector2(6, -78), "kR": Vector2(14, -22), "fR": Vector2(19, 0), "kL": Vector2(-12, -22), "fL": Vector2(-18, 0)}
const P_JAB := {"hip": Vector2(4, -42), "neck": Vector2(12, -82), "head": Vector2(17, -99), "eR": Vector2(36, -79), "hR": Vector2(60, -81), "eL": Vector2(0, -64), "hL": Vector2(10, -76), "kR": Vector2(22, -22), "fR": Vector2(30, 0), "kL": Vector2(-10, -22), "fL": Vector2(-22, 0)}
const P_HOOK := {"hip": Vector2(4, -42), "neck": Vector2(14, -80), "head": Vector2(20, -97), "eR": Vector2(4, -64), "hR": Vector2(12, -74), "eL": Vector2(34, -84), "hL": Vector2(60, -86), "kR": Vector2(20, -22), "fR": Vector2(26, 0), "kL": Vector2(-8, -20), "fL": Vector2(-24, 0)}
const P_KICK_W := {"hip": Vector2(-4, -44), "neck": Vector2(-10, -84), "head": Vector2(-10, -102), "eR": Vector2(-14, -70), "hR": Vector2(-24, -84), "eL": Vector2(10, -66), "hL": Vector2(16, -78), "kR": Vector2(14, -38), "fR": Vector2(4, -24), "kL": Vector2(-6, -22), "fL": Vector2(-8, 0)}
const P_KICK := {"hip": Vector2(-6, -46), "neck": Vector2(-20, -82), "head": Vector2(-24, -98), "eR": Vector2(-24, -72), "hR": Vector2(-42, -64), "eL": Vector2(2, -70), "hL": Vector2(-10, -60), "kR": Vector2(26, -56), "fR": Vector2(66, -66), "kL": Vector2(-6, -22), "fL": Vector2(-10, 0)}
const P_UPPER_W := {"hip": Vector2(0, -32), "neck": Vector2(8, -70), "head": Vector2(13, -86), "eR": Vector2(14, -42), "hR": Vector2(26, -36), "eL": Vector2(-4, -56), "hL": Vector2(10, -66), "kR": Vector2(20, -16), "fR": Vector2(24, 0), "kL": Vector2(-14, -16), "fL": Vector2(-20, 0)}
const P_UPPER := {"hip": Vector2(0, -50), "neck": Vector2(6, -92), "head": Vector2(9, -110), "eR": Vector2(22, -106), "hR": Vector2(26, -134), "eL": Vector2(-10, -76), "hL": Vector2(-18, -62), "kR": Vector2(16, -38), "fR": Vector2(20, -14), "kL": Vector2(-6, -24), "fL": Vector2(-8, 0)}
const P_SLAM_W := {"hip": Vector2(0, -46), "neck": Vector2(0, -88), "head": Vector2(2, -106), "eR": Vector2(14, -112), "hR": Vector2(8, -136), "eL": Vector2(-12, -110), "hL": Vector2(-6, -134), "kR": Vector2(16, -34), "fR": Vector2(14, -10), "kL": Vector2(-12, -32), "fL": Vector2(-14, -10)}
const P_SLAM := {"hip": Vector2(0, -26), "neck": Vector2(12, -58), "head": Vector2(19, -74), "eR": Vector2(30, -34), "hR": Vector2(38, -2), "eL": Vector2(16, -34), "hL": Vector2(26, -4), "kR": Vector2(22, -16), "fR": Vector2(26, 0), "kL": Vector2(-18, -14), "fL": Vector2(-24, 0)}
const P_DASH := {"hip": Vector2(0, -38), "neck": Vector2(24, -72), "head": Vector2(33, -86), "eR": Vector2(-6, -66), "hR": Vector2(-30, -62), "eL": Vector2(-10, -60), "hL": Vector2(-36, -54), "kR": Vector2(18, -20), "fR": Vector2(32, -6), "kL": Vector2(-18, -24), "fL": Vector2(-38, -14)}
const P_FLYKICK := {"hip": Vector2(0, -50), "neck": Vector2(-12, -86), "head": Vector2(-14, -104), "eR": Vector2(-14, -74), "hR": Vector2(-34, -82), "eL": Vector2(6, -76), "hL": Vector2(-6, -92), "kR": Vector2(34, -48), "fR": Vector2(70, -46), "kL": Vector2(-6, -34), "fL": Vector2(-2, -14)}
const P_HURT := {"hip": Vector2(-4, -40), "neck": Vector2(-16, -80), "head": Vector2(-24, -96), "eR": Vector2(-2, -92), "hR": Vector2(10, -108), "eL": Vector2(-30, -82), "hL": Vector2(-40, -96), "kR": Vector2(12, -20), "fR": Vector2(18, 0), "kL": Vector2(-12, -20), "fL": Vector2(-18, 0)}
const P_DEAD := {"hip": Vector2(0, -8), "neck": Vector2(-40, -10), "head": Vector2(-58, -10), "eR": Vector2(-24, -30), "hR": Vector2(-14, -44), "eL": Vector2(-30, -2), "hL": Vector2(-14, -2), "kR": Vector2(20, -16), "fR": Vector2(40, -4), "kL": Vector2(18, -4), "fL": Vector2(40, 0)}

# moves: [pose_windup, pose_strike, damage, range, arc, knockback, launch, total_time, hit_at, lunge]
const COMBO := [
	{"w": "jab_w", "s": "jab", "dmg": 11.0, "r": 92.0, "arc": 1.7, "kb": 420.0, "up": 0.0, "time": 0.25, "hit": 0.32, "lunge": 260.0, "word": false},
	{"w": "jab_w", "s": "hook", "dmg": 13.0, "r": 96.0, "arc": 1.9, "kb": 460.0, "up": 0.0, "time": 0.26, "hit": 0.32, "lunge": 280.0, "word": false},
	{"w": "kick_w", "s": "kick", "dmg": 17.0, "r": 112.0, "arc": 2.6, "kb": 620.0, "up": 120.0, "time": 0.32, "hit": 0.36, "lunge": 300.0, "word": true},
	{"w": "upper_w", "s": "upper", "dmg": 28.0, "r": 120.0, "arc": 2.3, "kb": 780.0, "up": 640.0, "time": 0.46, "hit": 0.4, "lunge": 360.0, "word": true},
]

var poses := {}
var pose := {}
var target_pose := {}
var pose_speed := 26.0
var facing := 1.0
var aim := Vector2.RIGHT
var vel := Vector2.ZERO
var z := 0.0
var squash := Vector2.ONE
var dead := false

var max_hp := 100.0
var hp := 100.0
var speed := 310.0
var dmg_mult := 1.0
var atk_speed := 1.0
var crit := 0.06
var crit_mult := 2.0
var vamp := 0.0
var pickup_r := 120.0
var reach := 1.0
var kb_mult := 1.0
var dash_cd_max := 0.85

var level := 1
var xp := 0
var xp_need := 8
var pending_levels := 0
var skills := {}

var state := "move"
var st_t := 0.0
var move_def := {}
var combo_step := 0
var combo_window := 0.0
var hit_done := false
var buffer_attack := 0.0
var buffer_heavy := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var dash_path: Array = []
var heavy_cd := 0.0
var invuln := 0.0
var hurt_flash := 0.0
var run_phase := 0.0
var scarf: Array = []
var mouse_aim := false
var regen_t := 0.0
var ghost_t := 0.0
var skill_runner: SkillRunner
# loadout (道馆 meta): hero / weapon / sect / move evolutions / curses
var hero := "red"
var weapon := "fist"
var sect := "none"
var evo := {}
var curses: Array = []
var atk_mult := 1.0
var slam_mult := 1.0
var slam_dmg := 1.0
var heavy_cd_max := 1.1
var arc_mult := 1.0
var launch_all := false
var dodge := 0.0
var dmg_taken := 1.0
var revive_left := 0
var drunk_t := 20.0
var body_w := 8.0
var body_scale := 1.0
var band_col := Color(0.93, 0.17, 0.2)
var head_col := Color(1, 1, 1)


func _ready() -> void:
	poses = {"idle": P_IDLE, "jab_w": P_JAB_W, "jab": P_JAB, "hook": P_HOOK, "kick_w": P_KICK_W, "kick": P_KICK, "upper_w": P_UPPER_W, "upper": P_UPPER, "slam_w": P_SLAM_W, "slam": P_SLAM, "dash": P_DASH, "flykick": P_FLYKICK, "hurt": P_HURT, "dead": P_DEAD}
	pose = P_IDLE.duplicate()
	target_pose = P_IDLE.duplicate()
	for i in 8:
		scarf.append(position + Vector2(-i * 8, -80))
	skill_runner = SkillRunner.new()
	skill_runner.player = self
	add_child(skill_runner)
	xp_need = _need(level)


## Applies hero, weapon, sect and 修炼 upgrades from the save (called once before the run starts).
func setup_loadout(h: String, w: String, s: String) -> void:
	hero = h if Meta.HEROES.has(h) else "red"
	weapon = w if Meta.WEAPONS.has(w) else "fist"
	sect = s if Meta.SECTS.has(s) else "none"
	var hd: Dictionary = Meta.HEROES[hero]
	max_hp = float(hd["hp"]) + 8.0 * Meta.up("hp")
	speed = 310.0 * float(hd["speed"]) * (1.0 + 0.04 * Meta.up("spd"))
	crit += float(hd["crit"])
	dash_cd_max *= float(hd["dash"])
	body_w = float(hd["w"])
	band_col = hd["band"]
	head_col = hd["head"]
	dmg_mult *= 1.0 + 0.05 * Meta.up("atk")
	revive_left = Meta.up("revive")
	match hero:
		"sumo":
			slam_mult = 1.4
			body_scale = 1.12
		"drunk":
			dodge = 0.2
	match weapon:
		"gloves":
			crit += 0.08
			crit_mult += 0.4
		"nunchaku":
			atk_speed += 0.25
			atk_mult = 0.85
		"hammer":
			atk_speed -= 0.2
			atk_mult = 1.45
			launch_all = true
			heavy_cd_max *= 0.6
		"staff":
			reach += 0.4
			arc_mult = 1.3
			kb_mult += 0.3
	if sect == "vajra":
		max_hp += 20.0
		dmg_taken = 0.85
	hp = max_hp


func add_curse(id: String) -> void:
	if curses.has(id):
		return
	curses.append(id)
	match id:
		"glass":
			dmg_mult *= 1.4
			max_hp = maxf(max_hp * 0.6, 20.0)
			hp = minf(hp, max_hp)
		"nodrug":
			dmg_mult *= 1.2
			G.no_hearts = true
		"blood":
			crit += 0.15
		"swarm":
			G.xp_mult *= 1.3
	G.spawn_text(position + Vector2(0, -150), "诅咒：" + String(SkillDB.CURSES[id]["name"]), Color(0.8, 0.2, 0.3), 36)


func has_evo(id: String) -> bool:
	return evo.values().has(id)


## XP to next level, tuned for the 5-minute round (~1 XP per small monster):
## measured (auto-play probe): ~Lv4 at 1:00, ~Lv9 at 3:00, ~Lv14 when 死神 arrives at 5:00.
func _need(l: int) -> int:
	return int(10.0 + 8.0 * l + 2.2 * l * l)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_aim = not G.touch
	elif event is InputEventKey and event.pressed:
		var k: InputEventKey = event
		if k.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_J, KEY_K]:
			mouse_aim = false


func _process(dt: float) -> void:
	if dead:
		_blend_pose(dt)
		queue_redraw()
		return
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("attack"):
		buffer_attack = 0.25
	if Input.is_action_just_pressed("heavy"):
		buffer_heavy = 0.25
	buffer_attack -= dt
	buffer_heavy -= dt
	dash_cd -= dt
	heavy_cd -= dt
	invuln -= dt
	hurt_flash -= dt
	if hero == "drunk":
		drunk_t -= dt
		if drunk_t <= 0.0:
			drunk_t = 20.0
			heal(15.0)
			G.spawn_text(position + Vector2(0, -140), "咕噜~", G.ORANGE, 30)
	combo_window -= dt
	st_t += dt
	_update_aim(mv)

	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0 and state != "slam":
		_start_dash(mv)

	match state:
		"move":
			_state_move(mv, dt)
		"attack":
			_state_attack(mv, dt)
		"slam":
			_state_slam(dt)
		"dash":
			_state_dash(dt)
		"hurt":
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * dt))
			if st_t > 0.18:
				state = "move"

	position += (vel + G.wind * 0.55) * dt
	position.x = clampf(position.x, G.ARENA.position.x + 40, G.ARENA.end.x - 40)
	position.y = clampf(position.y, G.ARENA.position.y + 60, G.ARENA.end.y - 30)
	for pr in G.props:
		if pr.dead:
			continue
		var d: Vector2 = position - pr.position
		var mind: float = RADIUS + float(pr.radius)
		if d.length() < mind and d.length() > 0.01:
			position = (pr.position as Vector2) + d.normalized() * mind
	if max_hp > hp and skills.has("vitality"):
		regen_t += dt
		if regen_t > 1.0:
			regen_t = 0.0
			heal(0.4 * float(skills["vitality"]), false)
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * dt))
	_blend_pose(dt)
	_update_scarf(dt)
	queue_redraw()


func _update_aim(mv: Vector2) -> void:
	var a := aim
	if mouse_aim and not G.touch:
		var m := get_global_mouse_position() - (position + Vector2(0, -60))
		if m.length() > 10.0:
			a = m.normalized()
	elif mv.length() > 0.2:
		a = mv.normalized()
	aim = a
	if state == "move" or state == "hurt":
		if absf(aim.x) > 0.15:
			facing = signf(aim.x)


func _auto_aim(dir: Vector2, rng: float) -> Vector2:
	var best = null
	var bs := -1.0
	for e in G.query(position, rng):
		var d: Vector2 = (e.position as Vector2) - position
		var l := d.length()
		if l < 1.0:
			continue
		var dotv := d.normalized().dot(dir)
		if dotv < 0.55:
			continue
		var score := dotv - l / rng * 0.5
		if score > bs:
			bs = score
			best = e
	if best == null and G.touch:
		# Touch has no mouse aim: fall back to the nearest monster in a wider ring.
		best = G.nearest_enemy(position, rng * 1.5)
	if best != null:
		return ((best.position as Vector2) - position).normalized()
	return dir


func _state_move(mv: Vector2, dt: float) -> void:
	var tv := mv * speed
	vel = vel.lerp(tv, 1.0 - exp(-(2.6 if G.ice_floor else 14.0) * dt))
	if buffer_heavy > 0.0 and heavy_cd <= 0.0:
		buffer_heavy = 0.0
		_start_slam()
		return
	if buffer_attack > 0.0:
		buffer_attack = 0.0
		if combo_window <= 0.0:
			combo_step = 0
		_start_attack(combo_step)
		return
	if vel.length() > 40.0:
		run_phase += dt * vel.length() * 0.045
		var s := sin(run_phase)
		var c := cos(run_phase)
		var lean := 10.0
		target_pose = {
			"hip": Vector2(0, -44 + absf(c) * 4.0), "neck": Vector2(lean, -84 + absf(c) * 4.0), "head": Vector2(lean + 5, -101 + absf(c) * 4.0),
			"eR": Vector2(8 - s * 14, -64), "hR": Vector2(20 - s * 22, -72 + s * 6),
			"eL": Vector2(4 + s * 14, -64), "hL": Vector2(16 + s * 22, -72 - s * 6),
			"kR": Vector2(10 + s * 18, -24 + maxf(-c, 0) * 8), "fR": Vector2(s * 30, maxf(c, 0) * -16),
			"kL": Vector2(10 - s * 18, -24 + maxf(c, 0) * 8), "fL": Vector2(-s * 30, maxf(-c, 0) * -16),
		}
		pose_speed = 22.0
		if absf(vel.x) > 30.0 and not mouse_aim:
			facing = signf(vel.x)
		if mouse_aim:
			facing = signf(aim.x) if absf(aim.x) > 0.1 else facing
	else:
		var b := sin(G.game_time * 3.0) * 2.0
		target_pose = P_IDLE.duplicate()
		target_pose["neck"] = P_IDLE["neck"] + Vector2(0, b)
		target_pose["head"] = P_IDLE["head"] + Vector2(0, b)
		target_pose["hR"] = P_IDLE["hR"] + Vector2(0, b * 1.5)
		target_pose["hL"] = P_IDLE["hL"] + Vector2(0, b * 1.5)
		pose_speed = 16.0


func _start_attack(step: int) -> void:
	state = "attack"
	st_t = 0.0
	hit_done = false
	move_def = COMBO[step]
	aim = _auto_aim(aim, 220.0)
	if absf(aim.x) > 0.05:
		facing = signf(aim.x)
	target_pose = poses[move_def["w"]]
	pose_speed = 40.0
	Sfx.play("whoosh", -6.0, 0.2)


func _state_attack(mv: Vector2, dt: float) -> void:
	var dur: float = float(move_def["time"]) / atk_speed
	var k := st_t / dur
	var hit_at: float = move_def["hit"]
	if k < hit_at:
		vel = vel.lerp(mv * speed * 0.25, 1.0 - exp(-10.0 * dt))
	elif not hit_done:
		hit_done = true
		target_pose = poses[move_def["s"]]
		pose_speed = 70.0
		vel = aim * float(move_def["lunge"])
		_do_strike()
	else:
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * dt))
		if k > hit_at + 0.35:
			if buffer_attack > 0.0:
				buffer_attack = 0.0
				combo_step = (combo_step + 1) % COMBO.size()
				_start_attack(combo_step)
				return
			if buffer_heavy > 0.0 and heavy_cd <= 0.0:
				buffer_heavy = 0.0
				_start_slam()
				return
	if k >= 1.0:
		state = "move"
		combo_window = 0.45
		combo_step = (combo_step + 1) % COMBO.size()
		pose_speed = 14.0


func _do_strike() -> void:
	var r: float = float(move_def["r"]) * reach
	var arc: float = float(move_def["arc"]) * arc_mult
	var center := position + Vector2(0, -10)
	var hits := 0
	var kills_now := 0
	var final_hit: bool = move_def["s"] == "upper"
	var kind := "big" if final_hit or move_def["s"] == "kick" else ""
	G.spawn_slash(position + Vector2(0, -60), aim, r * 0.95, arc, kind, Color(1, 1, 1) if not final_hit else Color(1, 0.9, 0.3))
	for e in G.hittables_in(center, r):
		var d: Vector2 = (e.position as Vector2) - center
		if d.length() > 12.0 and absf(aim.angle_to(d)) > arc * 0.5 + 0.2:
			continue
		var dir := d.normalized() if d.length() > 1.0 else aim
		dir = (dir + aim).normalized()
		var up := float(move_def["up"])
		if launch_all:
			up = maxf(up, 260.0)
		var base := float(move_def["dmg"]) * atk_mult
		var elem := ""
		if final_hit and has_evo("fin_dragon"):
			base *= 1.3
			up *= 1.35
			elem = "fire"
		elif final_hit and has_evo("fin_burst"):
			elem = "shock"
		if hero == "drunk" and randf() < 0.15:
			base *= 2.0
			G.spawn_text(e.position + Vector2(0, -120), "醉拳!", G.ORANGE, 32)
		var res := _deal(e, base, dir, float(move_def["kb"]), up, elem)
		if weapon == "nunchaku" and not res and is_instance_valid(e) and not e.dead:
			_deal(e, base * 0.35, dir, 120.0, 0.0)
		hits += 1
		if res:
			kills_now += 1
		if vamp > 0.0 and e is Enemy:
			heal(vamp, false)
	if final_hit and has_evo("fin_burst"):
		_fin_burst()
	if final_hit and has_evo("fin_dragon"):
		G.spawn_ring(position + Vector2(0, -20), 10, r * 1.2, G.ORANGE, 0.35, 14.0)
		G.particles.sparks(position + Vector2(0, -80), Vector2.UP, 10, G.ORANGE)
	if hits > 0:
		var hs := 0.045 if not final_hit else 0.09
		if kills_now > 0:
			hs += 0.03
		G.hitstop(hs)
		G.shake(0.22 if not final_hit else 0.45)
		if final_hit or kills_now >= 3:
			G.kick_zoom(0.05)
		if final_hit and hits >= 2:
			G.impact_frame(0.05)
		if bool(move_def["word"]) or kills_now > 0:
			G.spawn_text(position + aim * 70 + Vector2(0, -110), G.SFX_WORDS.pick_random(), G.YELLOW if not final_hit else G.RED, 34 if not final_hit else 44)
		Sfx.play("heavy" if final_hit else "hit", 0.0 if final_hit else -2.0)
		squash = Vector2(1.15, 0.9)


func _deal(e, base: float, dir: Vector2, kb: float, up: float, elem: String = "", heavy: bool = false) -> bool:
	var dmg := base * dmg_mult
	var is_crit := randf() < crit
	if is_crit:
		dmg *= crit_mult
		if curses.has("blood"):
			hp = maxf(hp - 0.5, 1.0)
	if e is Enemy:
		var en: Enemy = e
		if elem == "":
			var roll := randf()
			if sect == "flame" and roll < 0.15:
				elem = "fire"
			elif sect == "thunder" and roll < 0.15:
				elem = "shock"
			elif sect == "frost" and roll < 0.10:
				elem = "frost"
			elif G.blizzard and roll > 0.88:
				elem = "frost"
		if elem != "" or heavy:
			en.apply_elem(elem, dmg, heavy)
			if en.dead:
				return true
	return e.take_hit(dmg, dir, kb * kb_mult * (1.25 if is_crit else 1.0), up, is_crit)


func deal_skill(e, base: float, dir: Vector2, kb: float, up: float, elem: String = "") -> bool:
	return _deal(e, base, dir, kb, up, elem)


func _fin_burst() -> void:
	var c := position + aim * 150.0
	for e in G.hittables_in(c, 130.0 * reach):
		_deal(e, 26.0, aim, 1100.0, 200.0, "shock")
	G.spawn_ring(c, 10, 150.0 * reach, G.YELLOW, 0.3, 14.0, "shock")
	G.spawn_bolt(position + Vector2(0, -60), c + Vector2(0, -40), G.YELLOW)
	Sfx.play("zap", -4.0)


func _start_slam() -> void:
	state = "slam"
	st_t = 0.0
	hit_done = false
	heavy_cd = heavy_cd_max / atk_speed
	target_pose = P_SLAM_W
	pose_speed = 30.0
	aim = _auto_aim(aim, 260.0)
	if absf(aim.x) > 0.05:
		facing = signf(aim.x)
	vel = aim * 340.0
	Sfx.play("whoosh", -2.0)


func _state_slam(dt: float) -> void:
	var up_t := 0.24 / atk_speed
	if st_t < up_t:
		var k := st_t / up_t
		z = sin(k * PI * 0.5) * 95.0
		squash = Vector2(0.9, 1.12)
	elif not hit_done:
		z = maxf(z - 2600.0 * dt, 0.0)
		if z <= 0.0:
			hit_done = true
			vel = Vector2.ZERO
			target_pose = P_SLAM
			pose_speed = 80.0
			squash = Vector2(1.35, 0.7)
			_slam_impact()
	else:
		vel = Vector2.ZERO
		if st_t > up_t + 0.42 / atk_speed:
			state = "move"
			combo_step = 0


func _slam_impact() -> void:
	var hf := int(skills.get("heavyfist", 0))
	var r := 175.0 * reach * slam_mult * (1.0 + 0.12 * hf) * (1.35 if has_evo("slam_meteor") else 1.0)
	var hits := 0
	var kills_now := 0
	var elem := "fire" if has_evo("slam_meteor") else ("frost" if has_evo("slam_frost") else "")
	for e in G.hittables_in(position, r):
		var d: Vector2 = (e.position as Vector2) - position
		var dir := d.normalized() if d.length() > 1.0 else aim
		if _deal(e, 30.0 * (1.0 + 0.25 * hf), dir, 700.0, 720.0, elem, true):
			kills_now += 1
		hits += 1
	if elem == "fire":
		G.spawn_ring(position, 20, r, G.ORANGE, 0.45, 22.0)
	elif elem == "frost":
		G.spawn_ring(position, 20, r, Color(0.55, 0.9, 1.0), 0.45, 22.0)
	if skills.has("combo_quake"):
		skill_runner.quake(position, r)
	G.spawn_ring(position, 20, r * 1.15, G.WHITE, 0.35, 18.0, "shock")
	G.spawn_ring(position, 10, r * 0.7, G.YELLOW, 0.25, 10.0)
	G.particles.dust(position, 16, 60)
	G.particles.sparks(position + Vector2(0, -6), Vector2.UP, 10, G.YELLOW)
	G.decals.crack(position, r * 0.6)
	G.push_shards(position, r * 1.5, 650)
	G.spawn_text(position + Vector2(0, -140), "KA-BLAM!", G.ORANGE, 46)
	G.shake(0.55)
	G.kick_zoom(0.06)
	G.hitstop(0.1 if hits > 0 else 0.05)
	if hits >= 3:
		G.impact_frame(0.06)
	Sfx.play("heavy", 2.0)


func _start_dash(mv: Vector2) -> void:
	dash_dir = mv.normalized() if mv.length() > 0.2 else aim
	state = "dash"
	st_t = 0.0
	dash_cd = dash_cd_max
	invuln = 0.3
	dash_path = [position]
	hit_done = false
	z = 0.0
	if absf(dash_dir.x) > 0.1:
		facing = signf(dash_dir.x)
	target_pose = P_DASH
	pose_speed = 50.0
	G.particles.dust(position, 6, 20)
	Sfx.play("dash", -2.0)


func _state_dash(dt: float) -> void:
	var dur := 0.17
	if st_t < dur:
		vel = dash_dir * 1150.0
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.025
			G.spawn_ghost(position, pose, facing)
		if (buffer_attack > 0.0 or hero == "sumo" or has_evo("dash_thunder")) and not hit_done:
			hit_done = true
			buffer_attack = 0.0
			_dash_strike()
		dash_path.append(position)
	else:
		vel = dash_dir * 220.0
		if skill_runner != null:
			skill_runner.on_dash_end(dash_path)
		if hero == "ninja":
			skill_runner.shuriken(position, dash_dir)
		if has_evo("dash_wind") and hit_done:
			_dash_strike()
		state = "move"
		combo_window = 0.4
		if buffer_attack > 0.0:
			buffer_attack = 0.0
			_dash_strike()


func _dash_strike() -> void:
	target_pose = P_FLYKICK
	pose_speed = 60.0
	var hits := 0
	var r := 120.0 * reach
	var c := position + dash_dir * 50.0
	var elem := "shock" if has_evo("dash_thunder") else ""
	var bonus := 1.6 if hero == "sumo" else 1.0
	for e in G.hittables_in(c, r * (1.25 if hero == "sumo" else 1.0)):
		if _deal(e, 22.0 * bonus, (dash_dir + ((e.position as Vector2) - position).normalized() * 0.4).normalized(), 760.0 * bonus, 200.0, elem) and has_evo("dash_wind"):
			dash_cd = 0.0
		hits += 1
	G.spawn_slash(position + Vector2(0, -50), dash_dir, r, 1.4, "big", G.BLUE)
	if hits > 0:
		G.hitstop(0.07)
		G.shake(0.35)
		G.spawn_text(position + dash_dir * 80 + Vector2(0, -110), "THWACK!", G.BLUE, 38)
		Sfx.play("heavy", -1.0)
	else:
		Sfx.play("whoosh")


func _blend_pose(dt: float) -> void:
	var k := 1.0 - exp(-pose_speed * dt)
	for key in target_pose.keys():
		var a: Vector2 = pose.get(key, target_pose[key])
		pose[key] = a.lerp(target_pose[key], k)


func _update_scarf(dt: float) -> void:
	var neck: Vector2 = Stick.pt(pose, "neck", facing, position + Vector2(0, -z)) + Vector2(-4 * facing, 2)
	scarf[0] = neck
	for i in range(1, scarf.size()):
		var prev: Vector2 = scarf[i - 1]
		var cur: Vector2 = scarf[i]
		cur += Vector2(-facing * 30.0, 8.0 + sin(G.game_time * 12.0 + i) * 10.0) * dt
		var d := cur - prev
		if d.length() > 9.0:
			cur = prev + d.normalized() * 9.0
		scarf[i] = cur


func take_damage(amount: float, from: Vector2) -> void:
	if dead or invuln > 0.0 or state == "dash":
		return
	if dodge > 0.0 and randf() < dodge:
		invuln = 0.3
		G.spawn_text(position + Vector2(0, -130), "醉步闪!", G.GREEN, 28)
		vel = (position - from).normalized().orthogonal() * 420.0
		return
	amount *= dmg_taken * G.dmg_in_mult
	if skills.has("combo_bloodshadow"):
		skill_runner.blood_clone()
	hp -= amount
	invuln = 0.55
	hurt_flash = 0.15
	var d := (position - from).normalized()
	vel = d * 520.0
	state = "hurt"
	st_t = 0.0
	target_pose = P_HURT
	pose_speed = 50.0
	z = 0.0
	G.shake(0.4)
	G.hitstop(0.06)
	G.combo = 0
	G.particles.ink_spray(position + Vector2(0, -60), d, 8, G.INK, 60)
	G.spawn_text(position + Vector2(0, -130), "OUCH!", G.RED, 30)
	Sfx.play("hurt")
	if hp <= 0.0:
		if revive_left > 0:
			revive_left -= 1
			hp = max_hp * 0.5
			invuln = 2.0
			G.banner("不屈！原地复活！", 2.0)
			skill_runner.explode(position, 300.0, 80.0, G.YELLOW)
			return
		hp = 0.0
		_die()


## Killed by 死神 at the end of the round: bypasses i-frames, dodge and revive.
func reaped() -> void:
	if dead:
		return
	revive_left = 0
	hp = 0.0
	G.particles.ink_spray(position + Vector2(0, -60), Vector2.UP, 24, Color(0.35, 0.1, 0.5), 80)
	G.spawn_text(position + Vector2(0, -190), "被死神收割！", Color(0.8, 0.4, 1.0), 56, true, 1.6)
	_die()


func _die() -> void:
	dead = true
	target_pose = P_DEAD
	pose_speed = 10.0
	G.slowmo(0.25, 1.4)
	G.impact_frame(0.12)
	G.shake(0.8)
	G.spawn_text(position + Vector2(0, -150), "K.O.!", G.RED, 70, true, 2.0)
	Sfx.play("boom")
	died.emit()


func heal(amount: float, show: bool = true) -> void:
	amount *= G.heal_mult
	var before := hp
	hp = minf(hp + amount, max_hp)
	if show and hp > before:
		G.spawn_text(position + Vector2(0, -120), "+" + str(int(hp - before)), G.GREEN, 26, false)


func add_xp(v: int) -> void:
	xp += maxi(int(round(v * (1.0 + 0.06 * Meta.up("wis")))), 1) if v > 0 else 0
	while xp >= xp_need:
		xp -= xp_need
		level += 1
		xp_need = _need(level)
		pending_levels += 1
	if pending_levels > 0:
		leveled_up.emit()


func apply_skill(id: String) -> void:
	if id == "heal":
		heal(50.0)
		return
	var l: int = int(skills.get(id, 0)) + 1
	skills[id] = l
	if SkillDB.EVO.has(id):
		evo[String(SkillDB.EVO[id]["slot"])] = id
		skills.erase(id)
		G.banner("招式进化：" + String(SkillDB.EVO[id]["name"]), 2.4)
		return
	if SkillDB.CURSES.has(id):
		skills.erase(id)
		add_curse(id)
		return
	if SkillDB.COMBOS.has(id):
		Meta.codex_add("combos", id)
		G.banner("合体技！" + String(SkillDB.COMBOS[id]["name"]), 3.0)
		G.impact_frame(0.08)
		Meta.unlock_ach("combo_card")
		if Meta.data["codex"]["combos"].size() >= SkillDB.COMBOS.size():
			Meta.unlock_ach("combo_all")
	else:
		Meta.codex_add("skills", id)
	match id:
		"heavyfist":
			heavy_cd_max *= 0.9
		"power":
			dmg_mult += 0.22
		"fury":
			atk_speed += 0.14
		"crit":
			crit += 0.09
			crit_mult += 0.15
		"vamp":
			vamp += 0.8
		"vitality":
			max_hp += 25.0
			heal(40.0)
		"swift":
			speed *= 1.1
			dash_cd_max *= 0.88
		"magnet":
			pickup_r *= 1.45
		"reach":
			reach += 0.14
			kb_mult += 0.2
	skill_runner.refresh()


func _draw() -> void:
	var off := Vector2(0, -z)
	Ink.shadow(self, Vector2.ZERO, 26.0 - z * 0.08, 8.0 - z * 0.02)
	if pickup_r > 0.0 and not dead:
		pass
	draw_set_transform(Vector2.ZERO, 0.0, squash)
	var ink := G.INK
	if hurt_flash > 0.0:
		ink = G.RED
	elif invuln > 0.0 and int(invuln * 30.0) % 2 == 0:
		ink = Color(0.3, 0.3, 0.4)
	# scarf
	var sp := PackedVector2Array()
	for p in scarf:
		sp.append((p as Vector2) - position)
	draw_polyline(sp, G.INK, 11.0)
	draw_polyline(sp, band_col, 6.0)
	var back := Color(0.27, 0.22, 0.3)
	if body_scale != 1.0:
		draw_set_transform(Vector2.ZERO, 0.0, squash * body_scale)
	if hero == "sumo":
		var belly := Stick.pt(pose, "hip", facing, off).lerp(Stick.pt(pose, "neck", facing, off), 0.4)
		Ink.circle(self, belly + Vector2(4 * facing, 0), 22.0, Color(1, 0.88, 0.78), 4.0, ink)
	Stick.draw(self, pose, facing, off, ink, back, head_col, body_w, band_col)
	_draw_weapon(off, ink)
	if hero == "ninja":
		var hd := Stick.pt(pose, "head", facing, off)
		draw_line(hd + Vector2(-12 * facing, 2), hd + Vector2(12 * facing, 0), band_col, 6.0)
	# speed lines while dashing
	if state == "dash":
		for i in 5:
			var o := Vector2(-dash_dir.x, -dash_dir.y) * (40.0 + i * 16.0) + dash_dir.orthogonal() * (i * 14.0 - 28.0) + Vector2(0, -50)
			draw_line(o, o - dash_dir * 60.0, Color(0.07, 0.05, 0.09, 0.6), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_weapon(off: Vector2, ink: Color) -> void:
	var h := Stick.pt(pose, "hR", facing, off)
	var e := Stick.pt(pose, "eR", facing, off)
	var d := (h - e).normalized()
	match weapon:
		"gloves":
			Ink.circle(self, h, 11.0, G.RED, 3.5, ink)
		"nunchaku":
			var a := h + d * 26.0
			draw_line(h, a, ink, 7.0)
			draw_line(h, a, G.YELLOW, 4.0)
			var sw := a + d.rotated(sin(G.game_time * 14.0) * 1.2) * 26.0
			draw_line(a, sw, ink, 7.0)
			draw_line(a, sw, G.YELLOW, 4.0)
		"hammer":
			var top := h + d * 46.0
			draw_line(h - d * 8.0, top, ink, 7.0)
			draw_line(h - d * 8.0, top, Color(0.6, 0.4, 0.25), 4.0)
			var n := d.orthogonal()
			Ink.shape(self, PackedVector2Array([top + n * 22 - d * 4, top + n * 22 + d * 18, top - n * 22 + d * 18, top - n * 22 - d * 4]), Color(0.55, 0.55, 0.62), 4.0, ink)
		"staff":
			var n2 := d.rotated(-0.5 * facing)
			draw_line(h - n2 * 50.0, h + n2 * 70.0, ink, 8.0)
			draw_line(h - n2 * 50.0, h + n2 * 70.0, Color(0.75, 0.45, 0.2), 4.5)