extends Node3D
## The paper swordsman.

const Data := preload("res://scripts/data.gd")

var paper: Node3D
var spr: Sprite3D
var vel := Vector3.ZERO
var facing := Vector3(1, 0, 0)
var face_x := 1.0
var walk_ph := 0.0
var anim_t := 0.0
var revivals := 0
var dead := false

var max_hp := 100.0
var hp := 100.0
var level := 1
var xp := 0.0
var xp_next := 5.0
var pending_levels := 0
var iframe := 0.0
var flash := 0.0

# stats
var speed := 5.0
var might := 1.0
var cd := 1.0
var area := 1.0
var dur := 1.0
var amount := 0
var proj := 1.0
var magnet := 2.8
var luck := 1.0
var crit := 0.05
var armor := 0.0
var regen := 0.0
var growth := 1.0

var passives: Dictionary = {}


func _ready() -> void:
	paper = Node3D.new()
	paper.rotation.x = -deg_to_rad(20)
	add_child(paper)
	var t := G.tex("res://assets/hero_sheet.png")
	spr = Sprite3D.new()
	spr.texture = t
	spr.hframes = 4
	spr.vframes = 2
	spr.pixel_size = 0.0064
	spr.material_override = G.mat(t, 0)
	G.init_inst(spr)
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spr.offset = Vector2(0, t.get_height() / 4.0)
	paper.add_child(spr)
	revivals = G.meta("revival")
	add_child(G.shadow(1.3))
	var gl := Sprite3D.new()
	var gt := G.tex("res://assets/fx/aura.png")
	gl.texture = gt
	gl.material_override = G.mat(gt, 2)
	G.init_inst(gl)
	gl.pixel_size = 1.5 / 128.0
	gl.transform = Transform3D(G.flat_basis, Vector3(0, 0.04, 0))
	G.sp(gl, "tint", Color(0.5, 0.9, 1.3, 0.35))
	add_child(gl)
	recalc()
	hp = max_hp


func recalc() -> void:
	var l := func(k: String) -> int: return int(passives.get(k, 0))
	var old_max := max_hp
	might = 1.0 + 0.1 * l.call("might") + 0.05 * G.meta("might")
	proj = 1.0 + 0.12 * l.call("swift")
	amount = l.call("amount") + G.meta("amount")
	area = 1.0 + 0.1 * l.call("area") + 0.05 * G.meta("area")
	speed = 5.0 * (1.0 + 0.1 * l.call("boots") + 0.05 * G.meta("speed"))
	magnet = 2.8 * (1.0 + 0.3 * l.call("magnet") + 0.25 * G.meta("magnet"))
	max_hp = 100.0 * (1.0 + 0.2 * l.call("heart") + 0.1 * G.meta("maxhp"))
	regen = 0.3 * l.call("leaf") + 0.1 * G.meta("regen")
	cd = 1.0 - 0.08 * l.call("book") - 0.03 * G.meta("cd")
	dur = 1.0 + 0.12 * l.call("hourglass")
	crit = 0.05 + 0.06 * l.call("cloud")
	luck = 1.0 + 0.1 * l.call("cloud") + 0.1 * G.meta("luck")
	armor = 1.0 * l.call("armor") + G.meta("armor")
	growth = 1.0 + 0.03 * G.meta("growth")
	if max_hp > old_max:
		hp += max_hp - old_max


func update(delta: float) -> void:
	if dead:
		return
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if G.bot:
		var tt := Time.get_ticks_msec() / 1000.0 * Engine.time_scale
		iv = Vector2(cos(tt * 0.35), sin(tt * 0.5)).normalized()
	var mv := Vector3(iv.x, 0, iv.y)
	if mv.length() > 1.0:
		mv = mv.normalized()
	vel = vel.lerp(mv * speed, 1.0 - exp(-14.0 * delta))
	position += vel * delta
	if mv.length() > 0.1:
		facing = mv.normalized()
		walk_ph += delta * 13.0
		if absf(mv.x) > 0.1:
			face_x = signf(mv.x)
	else:
		walk_ph = lerpf(walk_ph, round(walk_ph / PI) * PI, 1.0 - exp(-10.0 * delta))
	# sprite-sheet animation: row 0 idle, row 1 run
	var moving := vel.length() > 0.8
	anim_t += delta * (12.0 * clampf(vel.length() / speed, 0.7, 1.4) if moving else 5.0)
	spr.frame = (4 if moving else 0) + int(anim_t) % 4
	# paper juice: flip, bob, sway
	paper.scale.x = move_toward(paper.scale.x, face_x, delta * 10.0)
	var bob := absf(sin(walk_ph))
	spr.position.y = bob * 0.06
	paper.rotation.z = sin(walk_ph) * 0.04 * minf(vel.length() / speed, 1.0)
	paper.scale.y = 1.0 + (bob - 0.5) * 0.03
	if regen > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen * delta)
	if iframe > 0.0:
		iframe -= delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 5.0)
		G.sp(spr, "tint", Color(1.0, 1.0 - flash * 0.7, 1.0 - flash * 0.7))
		G.sp(spr, "flash", flash * 0.5)


func hurt(d: float) -> void:
	if iframe > 0.0 or dead:
		return
	var amt := maxf(1.0, d - armor)
	hp -= amt
	iframe = 0.4
	flash = 1.0
	G.sfx.play("hurt", -4.0)
	G.fx.number(position + Vector3(0, 2.2, 0), amt, false, Color(1.0, 0.3, 0.3))
	G.game.shake(0.25)
	G.hud.hurt_flash()
	if hp <= 0.0 and revivals > 0:
		revivals -= 1
		hp = max_hp * 0.5
		iframe = 2.5
		G.game.bomb()
		G.hud.banner("涅槃重生！", Color(1.0, 0.6, 0.3))
		return
	if hp <= 0.0:
		hp = 0.0
		dead = true
		G.game.game_over(false)


func heal(v: float) -> void:
	hp = minf(max_hp, hp + v)
	G.fx.text(position + Vector3(0, 2.3, 0), "+%d" % int(v), Color(0.4, 1.0, 0.5), 58)
	G.fx.burst(position + Vector3(0, 1, 0), Color(0.5, 1.0, 0.6), 12, 4.0, 0.14, 0.7, 2.0)


func add_xp(v: float) -> void:
	xp += v * growth
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		pending_levels += 1
		xp_next = Data.xp_for(level)
