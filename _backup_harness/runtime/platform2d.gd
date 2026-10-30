extends Node2D
## Renders a 2D platform as a chunky, readable piece of terrain: drop shadow, body with
## gradient + texture detail, a cap layer (grass / snow / candy / stone…) with an outline and
## drips, and optional tiling AI texture (world.platform_asset).
##
## style is one of: grass, snow, stone, wood, candy, sand, ice, lava, cloud, metal (shared with
## terrain3d via world.theme).
## When unset it is inferred from the platform colour so AI-picked colours still look themed.

const OUTLINE := Color(0.13, 0.08, 0.16, 0.9)
const CAP_MIN := 10.0
const CORNER := 10.0

var size := Vector2(200, 40)
var color := Color("#7cc44f")
var style := ""
var texture: Texture2D = null
var seed_value := 0

func setup(sz: Vector2, col: Color, st: String, tex: Texture2D, sd: int) -> void:
	size = sz
	color = col
	style = st if st != "" else infer_style(col)
	texture = tex
	seed_value = sd
	queue_redraw()

static func infer_style(c: Color) -> String:
	if c.s < 0.12:
		return "snow" if c.v > 0.8 else ("stone" if c.v > 0.35 else "metal")
	var h := c.h * 360.0
	if h < 15.0 or h >= 320.0:
		return "candy"
	if h < 50.0:
		return "wood" if c.v < 0.75 else "sand"
	if h < 170.0:
		return "grass"
	if h < 250.0:
		return "ice"
	return "candy"

func _cap_color() -> Color:
	match style:
		"snow": return Color("#f4f9ff")
		"ice": return color.lightened(0.45)
		"sand": return color.lightened(0.15)
		"lava": return Color("#ff7b2e")
	return color

func _body_color() -> Color:
	match style:
		"grass": return Color("#8a5a3b")
		"snow": return Color("#7f8fa6")
		"stone": return color.darkened(0.25)
		"metal": return color.darkened(0.1)
		"wood": return color.darkened(0.2)
		"candy": return Color("#fff1e6")
		"sand": return color.darkened(0.25)
		"ice": return color.darkened(0.1)
		"cloud": return Color("#e9f1ff")
		"lava": return Color("#3a2a33")
	return color.darkened(0.4)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var r := Rect2(-size * 0.5, size)
	if style == "cloud":
		_draw_cloud(r)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var thin := h <= 48.0
	# drop shadow
	_round_rect(Rect2(r.position + Vector2(6, 9), r.size), Color(0, 0, 0, 0.22), CORNER)
	# body
	var body := _body_color()
	_round_rect(r.grow(3), OUTLINE, CORNER + 3)
	_round_rect(r, body, CORNER)
	if texture:
		_draw_texture_body(r)
	else:
		_draw_body_detail(r, body, rng, thin)
	# bottom shade
	draw_rect(Rect2(r.position.x + 4, r.end.y - minf(8.0, h * 0.2), w - 8, minf(8.0, h * 0.2) - 2), Color(0, 0, 0, 0.15))
	_draw_cap(r, rng, thin)

func _draw_texture_body(r: Rect2) -> void:
	var ts := texture.get_size()
	var k := clampf(r.size.y / ts.y, 0.15, 1.0)
	if r.size.y > 120.0:
		k = 128.0 / ts.y
	draw_set_transform(r.position, 0.0, Vector2(k, k))
	draw_texture_rect(texture, Rect2(Vector2.ZERO, r.size / k), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_body_detail(r: Rect2, body: Color, rng: RandomNumberGenerator, thin: bool) -> void:
	var w := r.size.x
	var h := r.size.y
	# vertical gradient bands
	var bands := 4
	for i in bands:
		var y0 := r.position.y + h * (0.35 + 0.65 * i / float(bands))
		var hh := h * 0.65 / bands
		draw_rect(Rect2(r.position.x + 3, y0, w - 6, hh), Color(0, 0, 0, 0.05 * i))
	match style:
		"stone", "metal":
			var row_h := clampf(h * 0.5, 18.0, 34.0)
			var y := r.position.y + CAP_MIN
			var row := 0
			while y < r.end.y - 6.0:
				var x := r.position.x + (0.0 if row % 2 == 0 else 22.0)
				while x < r.end.x - 4.0:
					draw_line(Vector2(x, y), Vector2(x, minf(y + row_h, r.end.y - 3)), body.darkened(0.3), 2.0)
					x += 44.0
				draw_line(Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), body.darkened(0.3), 2.0)
				y += row_h
				row += 1
		"wood":
			var y2 := r.position.y + CAP_MIN + 4.0
			while y2 < r.end.y - 4.0:
				draw_line(Vector2(r.position.x + 6, y2), Vector2(r.end.x - 6, y2), body.darkened(0.25), 2.0)
				y2 += 12.0
			var x2 := r.position.x + 18.0
			while x2 < r.end.x - 10.0:
				draw_circle(Vector2(x2, r.position.y + h * 0.6), 2.5, body.darkened(0.45))
				x2 += 60.0
		"candy":
			var x3 := r.position.x - h
			while x3 < r.end.x:
				var pts := PackedVector2Array([Vector2(x3, r.end.y - 3), Vector2(x3 + 14, r.end.y - 3), Vector2(minf(x3 + 14 + h, r.end.x - 3), r.position.y + 6), Vector2(minf(x3 + h, r.end.x - 3), r.position.y + 6)])
				if x3 + 14 > r.position.x + 3:
					var clipped := PackedVector2Array()
					for p in pts:
						clipped.append(Vector2(clampf(p.x, r.position.x + 3, r.end.x - 3), p.y))
					draw_colored_polygon(clipped, Color(color, 0.35))
				x3 += 36.0
		_:
			# pebbles / soil specks
			var count := int(w * h / 900.0) + 2
			for i in count:
				var p := Vector2(rng.randf_range(r.position.x + 8, r.end.x - 8), rng.randf_range(r.position.y + CAP_MIN + 6, r.end.y - 6))
				var rad := rng.randf_range(2.0, 5.0) if not thin else rng.randf_range(1.5, 3.0)
				draw_circle(p, rad, body.darkened(0.22))
				draw_circle(p - Vector2(rad * 0.3, rad * 0.3), rad * 0.4, body.lightened(0.12))

func _draw_cap(r: Rect2, rng: RandomNumberGenerator, thin: bool) -> void:
	var w := r.size.x
	var cap_h := clampf(r.size.y * 0.38, CAP_MIN, 22.0)
	var cap := _cap_color()
	if style in ["stone", "metal", "wood"]:
		cap_h = clampf(r.size.y * 0.25, 6.0, 12.0)
		cap = _body_color().lightened(0.25)
	var top := r.position.y
	# cap with outline and drips
	_round_rect(Rect2(r.position.x - 3, top - 3, w + 6, cap_h + 6), OUTLINE, CORNER + 3)
	_round_rect(Rect2(r.position.x, top, w, cap_h), cap, CORNER)
	if style in ["grass", "snow", "candy", "ice", "sand", "lava"]:
		var x := r.position.x + 10.0
		while x < r.end.x - 12.0:
			var dw := rng.randf_range(10.0, 18.0)
			var dh := rng.randf_range(4.0, 9.0) * (0.6 if thin else 1.0)
			draw_circle(Vector2(x + dw * 0.5, top + cap_h), dw * 0.5 + 2.0, OUTLINE)
			draw_rect(Rect2(x - 2, top + cap_h - 4, dw + 4, 4), cap)
			draw_circle(Vector2(x + dw * 0.5, top + cap_h - 1), dw * 0.5, cap)
			draw_rect(Rect2(x, top + cap_h - 6, dw, dh * 0.4 + 5), cap)
			x += dw + rng.randf_range(10.0, 30.0)
	# highlight
	draw_line(Vector2(r.position.x + CORNER, top + 3), Vector2(r.end.x - CORNER, top + 3), cap.lightened(0.35), 3.0)
	if style == "grass":
		var gx := r.position.x + 14.0
		while gx < r.end.x - 14.0:
			var gh := rng.randf_range(5.0, 10.0)
			draw_line(Vector2(gx, top + 1), Vector2(gx - 2, top - gh), cap.darkened(0.12), 3.0)
			draw_line(Vector2(gx + 4, top + 1), Vector2(gx + 6, top - gh * 0.7), cap.lightened(0.1), 3.0)
			gx += rng.randf_range(28.0, 70.0)

func _draw_cloud(r: Rect2) -> void:
	var w := r.size.x
	var h := maxf(r.size.y, 30.0)
	var c := Color("#ffffff")
	var n := maxi(2, int(w / 60.0))
	for pass_i in 2:
		var col := OUTLINE if pass_i == 0 else c
		var grow := 3.0 if pass_i == 0 else 0.0
		for i in n:
			var cx := r.position.x + w * (i + 0.5) / n
			draw_circle(Vector2(cx, r.position.y + h * 0.45), h * 0.55 + grow, col)
		_round_rect(Rect2(r.position.x - grow, r.position.y + h * 0.3 - grow, w + grow * 2, h * 0.6 + grow * 2), col, h * 0.3)
	draw_rect(Rect2(r.position.x + 8, r.position.y + h * 0.72, w - 16, h * 0.14), Color("#d6e4ff"))

func _round_rect(rr: Rect2, c: Color, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(minf(rad, minf(rr.size.x, rr.size.y) * 0.5)))
	sb.anti_aliasing = true
	draw_style_box(sb, rr)
