extends Node3D
## Pooled juice: damage numbers, shards, glows, rings.

class Part:
	var n: Sprite3D
	var v := Vector3.ZERO
	var t := 0.0
	var life := 1.0
	var g := 9.0
	var c := Color.WHITE

class Num:
	var l: Label3D
	var t := 0.0
	var base := Vector3.ZERO
	var crit := false
	var col := Color.WHITE

const MAX_PARTS := 420
const MAX_NUMS := 70

var parts: Array = []
var ppool: Array = []
var nums: Array = []
var npool: Array = []
var shard_tex: Texture2D
var show_numbers := true


func _ready() -> void:
	shard_tex = G.tex("res://assets/fx/shard.png")


func number(pos: Vector3, val: float, crit: bool = false, col: Color = Color(1, 1, 1)) -> void:
	if not show_numbers:
		return
	var n: Num
	if npool.size() > 0:
		n = npool.pop_back()
	elif nums.size() >= (MAX_NUMS / 2 if G.low else MAX_NUMS):
		n = nums.pop_front()
	else:
		n = Num.new()
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font = G.font
		l.outline_size = 14
		l.pixel_size = 0.0085
		l.render_priority = 10
		l.outline_render_priority = 9
		l.double_sided = true
		add_child(l)
		n.l = l
	n.l.text = str(maxi(1, int(round(val))))
	n.l.visible = true
	n.t = 0.0
	n.crit = crit
	n.base = pos + Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.2, 0.2))
	n.col = Color(1.0, 0.82, 0.15) if crit else col
	n.l.font_size = 68 if crit else 46
	n.l.modulate = n.col
	n.l.outline_modulate = Color(0.12, 0.04, 0.04, 1.0)
	nums.append(n)


func text(pos: Vector3, s: String, col: Color, size: int = 56) -> void:
	number(pos, 1.0, false, col)
	var n: Num = nums.back()
	n.l.text = s
	n.l.font_size = size


func burst(pos: Vector3, col: Color, count: int, spd: float, size: float = 0.13, life: float = 0.6, grav: float = 16.0, tex: Texture2D = null) -> void:
	if G.low:
		count = maxi(1, count / 2)
	for i in count:
		var p: Part
		if ppool.size() > 0:
			p = ppool.pop_back()
		elif parts.size() >= (MAX_PARTS / 2 if G.low else MAX_PARTS):
			p = parts.pop_front()
		else:
			p = Part.new()
			var s := Sprite3D.new()
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(s)
			p.n = s
		p.n.texture = tex if tex != null else shard_tex
		p.n.pixel_size = size / float(p.n.texture.get_width())
		p.n.modulate = col
		p.n.position = pos
		p.n.visible = true
		var a := randf() * TAU
		p.v = Vector3(cos(a), randf_range(0.5, 1.4), sin(a)) * spd * randf_range(0.35, 1.0)
		p.t = 0.0
		p.life = life * randf_range(0.7, 1.3)
		p.g = grav
		p.c = col
		parts.append(p)


## Additive sprite that scales from s0 to s1 and fades out.
func glow(pos: Vector3, col: Color, size: float, life: float = 0.3, tex_path: String = "res://assets/fx/glow.png", s0: float = 1.0, s1: float = 1.6, flat: bool = false) -> Sprite3D:
	var s := Sprite3D.new()
	var tx := G.tex(tex_path)
	s.texture = tx
	s.material_override = G.mat(tx, 2)
	G.init_inst(s)
	s.pixel_size = size / float(tx.get_width())
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	s.transform = Transform3D(G.flat_basis if flat else G.cam_basis, pos)
	s.scale = Vector3.ONE * s0
	G.sp(s, "tint", col)
	var tw := s.create_tween()
	tw.tween_method(func(k: float) -> void:
		s.scale = Vector3.ONE * lerpf(s0, s1, k)
		G.sp(s, "tint", Color(col.r, col.g, col.b, col.a * (1.0 - k * k)))
	, 0.0, 1.0, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(s.queue_free)
	return s


func ring(pos: Vector3, col: Color, radius: float, life: float = 0.35) -> void:
	glow(pos + Vector3(0, 0.06, 0), col, radius * 2.0 / 0.85, life, "res://assets/fx/ring.png", 0.25, 1.0, true)


func _process(delta: float) -> void:
	for i in range(parts.size() - 1, -1, -1):
		var p: Part = parts[i]
		p.t += delta
		if p.t >= p.life:
			p.n.visible = false
			ppool.append(p)
			parts.remove_at(i)
			continue
		p.v.y -= p.g * delta
		var np := p.n.position + p.v * delta
		if np.y < 0.04:
			np.y = 0.04
			p.v = Vector3(p.v.x * 0.5, absf(p.v.y) * 0.25, p.v.z * 0.5)
		p.n.position = np
		var k := p.t / p.life
		if k > 0.6:
			p.n.modulate = Color(p.c.r, p.c.g, p.c.b, p.c.a * (1.0 - (k - 0.6) / 0.4))
	for i in range(nums.size() - 1, -1, -1):
		var n: Num = nums[i]
		n.t += delta
		var dur := 0.75 if n.crit else 0.6
		if n.t >= dur:
			n.l.visible = false
			npool.append(n)
			nums.remove_at(i)
			continue
		var k := n.t / dur
		n.l.position = n.base + Vector3(0, 0.2 + (1.0 - pow(1.0 - k, 2.0)) * 0.8, 0)
		var pop := maxf(0.0, 1.0 - n.t * 8.0)
		n.l.scale = Vector3.ONE * (1.0 + pop * (0.9 if n.crit else 0.5))
		var a := 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
		n.l.modulate = Color(n.col.r, n.col.g, n.col.b, a)
		n.l.outline_modulate = Color(0.12, 0.04, 0.04, a)
