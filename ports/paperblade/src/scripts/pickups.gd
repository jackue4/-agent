extends Node3D
## XP gems and floor items.

class Gem:
	var n: Sprite3D
	var val := 1.0
	var att := false
	var v := Vector3.ZERO
	var spd := 0.0
	var ph := 0.0

class Item:
	var n: Node3D
	var spr: Sprite3D
	var kind := ""
	var ph := 0.0
	var att := false
	var spd := 0.0
	var v := Vector3.ZERO

const GEM_TEX := ["res://assets/fx/gem_blue.png", "res://assets/fx/gem_green.png", "res://assets/fx/gem_red.png", "res://assets/fx/gem_gold.png"]
const ITEM_TEX := {"chicken": "res://assets/item_12.png", "magnet": "res://assets/item_13.png", "bomb": "res://assets/item_14.png", "chest": "res://assets/item_15.png", "coin": "res://assets/coin.png", "coins": "res://assets/coins.png"}
const MAX_GEMS := 380

var gems: Array = []
var gpool: Array = []
var items: Array = []
var time := 0.0


func _gem_tex(v: float) -> Texture2D:
	var i := 0
	if v >= 50.0:
		i = 3
	elif v >= 12.0:
		i = 2
	elif v >= 3.0:
		i = 1
	return G.tex(GEM_TEX[i])


func drop_gem(pos: Vector3, val: float) -> void:
	if gems.size() >= MAX_GEMS:
		var m: Gem = gems[randi() % gems.size()]
		m.val += val
		m.n.texture = _gem_tex(m.val)
		return
	var g: Gem
	if gpool.size() > 0:
		g = gpool.pop_back()
	else:
		g = Gem.new()
		var s := Sprite3D.new()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.pixel_size = 0.036
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		g.n = s
	g.val = val
	g.att = false
	g.spd = 0.0
	g.v = Vector3.ZERO
	g.ph = randf() * TAU
	g.n.texture = _gem_tex(val)
	g.n.visible = true
	g.n.position = Vector3(pos.x + randf_range(-0.3, 0.3), 0.35, pos.z + randf_range(-0.3, 0.3))
	gems.append(g)


func drop_item(kind: String, pos: Vector3) -> void:
	var it := Item.new()
	it.kind = kind
	it.ph = randf() * TAU
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x, 0, pos.z)
	var paper := Node3D.new()
	paper.rotation.x = -deg_to_rad(22)
	root.add_child(paper)
	var big := kind == "chest"
	if kind == "coin" or kind == "coins":
		it.spr = G.sprite(ITEM_TEX[kind], 0.0058 if kind == "coin" else 0.0052, 1)
	else:
		it.spr = G.sprite(ITEM_TEX[kind], 0.0105 if big else 0.0068)
	paper.add_child(it.spr)
	root.add_child(G.shadow(1.3 if big else 0.8))
	var gl := Sprite3D.new()
	var gt := G.tex("res://assets/fx/aura.png")
	gl.texture = gt
	gl.material_override = G.mat(gt, 2)
	G.init_inst(gl)
	gl.pixel_size = (2.2 if big else 1.4) / 128.0
	gl.transform = Transform3D(G.flat_basis, Vector3(0, 0.05, 0))
	var gc := Color(1.6, 1.2, 0.3, 0.8) if big else Color(1.0, 1.0, 0.7, 0.45)
	G.sp(gl, "tint", gc)
	root.add_child(gl)
	if big:
		var beam := G.sprite("res://assets/fx/glow.png", 0.03, 2, true)
		beam.scale = Vector3(0.35, 2.5, 1.0)
		G.sp(beam, "tint", Color(1.4, 1.0, 0.3, 0.5))
		root.add_child(beam)
	it.n = root
	root.scale = Vector3.ONE * 0.01
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	items.append(it)


func attract_all() -> void:
	for g in gems:
		g.att = true
		g.spd = 9.0


func clear_all() -> void:
	for g in gems:
		g.n.visible = false
		gpool.append(g)
	gems.clear()


func _physics_process(delta: float) -> void:
	time += delta
	var p = G.player
	if p == null:
		return
	var pp: Vector3 = p.position + Vector3(0, 0.7, 0)
	var mag: float = p.magnet
	var mag2 := mag * mag
	for i in range(gems.size() - 1, -1, -1):
		var g: Gem = gems[i]
		var gp := g.n.position
		if g.att:
			var to := pp - gp
			var d := to.length()
			if d < 0.55 or p.dead:
				if not p.dead:
					p.add_xp(g.val)
					G.sfx.gem()
				g.n.visible = false
				gpool.append(g)
				gems[i] = gems.back()
				gems.pop_back()
				continue
			g.spd += 50.0 * delta
			g.v = g.v.lerp(to / d * g.spd, 1.0 - exp(-7.0 * delta))
			g.n.position = gp + g.v * delta
		else:
			var dx := pp.x - gp.x
			var dz := pp.z - gp.z
			if dx * dx + dz * dz < mag2:
				g.att = true
				g.spd = 2.5
				g.v = Vector3(-dx, 0, -dz).normalized() * 4.0 + Vector3(0, 3.0, 0)
			else:
				g.n.position.y = 0.35 + sin(time * 3.0 + g.ph) * 0.07
	var reach := 1.1 + mag * 0.15
	for i in range(items.size() - 1, -1, -1):
		var it: Item = items[i]
		it.spr.position.y = 0.12 + sin(time * 3.0 + it.ph) * 0.1
		var to: Vector3 = Vector3(pp.x, 0, pp.z) - it.n.position
		var d := to.length()
		if not it.att and d < reach:
			it.att = true
			it.spd = 2.0
		if it.att:
			it.spd += 30.0 * delta
			it.n.position += to.normalized() * minf(it.spd * delta, d)
			if d < 0.5:
				items.remove_at(i)
				_collect(it)


func _collect(it: Item) -> void:
	var p = G.player
	var pos: Vector3 = it.n.position
	it.n.queue_free()
	G.fx.glow(pos + Vector3(0, 0.6, 0), Color(1.5, 1.4, 0.8, 0.9), 2.2, 0.35)
	match it.kind:
		"chicken":
			p.heal(30.0)
			G.sfx.play("heal")
		"magnet":
			attract_all()
			G.sfx.play("heal", 0.0, 0.0, 1.5)
			G.hud.banner("吸星大法！", Color(0.5, 0.8, 1.0))
		"bomb":
			G.game.bomb()
		"chest":
			G.game.open_chest()
		"coin":
			G.game.add_gold(5.0, pos)
		"coins":
			G.game.add_gold(30.0, pos)
