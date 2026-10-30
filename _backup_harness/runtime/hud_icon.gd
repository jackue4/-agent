extends Control
## Small vector icon for the HUD (heart, coin, star, skull, clock, flag, gem). Crisp at any scale.

@export var kind := "coin"
@export var filled := true
@export var tint := Color.WHITE

func _init(k := "coin", sz := 30.0) -> void:
	kind = k
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_filled(v: bool) -> void:
	if v != filled:
		filled = v
		queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var outline := Color(0.12, 0.06, 0.2, 0.95)
	match kind:
		"heart":
			var col := Color("#ff4d6d") if filled else Color(1, 1, 1, 0.18)
			_heart(c + Vector2(0, s * 0.04), s * 0.5, outline)
			_heart(c + Vector2(0, s * 0.04), s * 0.4, col)
			if filled:
				draw_circle(c + Vector2(-s * 0.14, -s * 0.1), s * 0.07, Color(1, 1, 1, 0.75))
		"coin":
			var col2 := tint if tint != Color.WHITE else Color("#ffd23f")
			draw_circle(c, s * 0.47, outline)
			draw_circle(c, s * 0.4, col2.darkened(0.2))
			draw_circle(c, s * 0.31, col2)
			draw_rect(Rect2(c + Vector2(-s * 0.05, -s * 0.18), Vector2(s * 0.1, s * 0.36)), col2.lightened(0.55))
		"star":
			var col3 := Color("#ffd23f") if filled else Color(1, 1, 1, 0.16)
			_star(c, s * 0.5, outline)
			_star(c, s * 0.38, col3)
		"skull":
			draw_circle(c + Vector2(0, -s * 0.05), s * 0.42, outline)
			draw_circle(c + Vector2(0, -s * 0.05), s * 0.34, Color("#f1f1f1"))
			draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.1), Vector2(s * 0.4, s * 0.26)), Color("#f1f1f1"))
			draw_circle(c + Vector2(-s * 0.13, -s * 0.06), s * 0.09, outline)
			draw_circle(c + Vector2(s * 0.13, -s * 0.06), s * 0.09, outline)
		"clock":
			draw_circle(c, s * 0.47, outline)
			draw_circle(c, s * 0.38, Color("#e8f1ff"))
			draw_line(c, c + Vector2(0, -s * 0.26), outline, maxf(2.0, s * 0.08))
			draw_line(c, c + Vector2(s * 0.18, 0), outline, maxf(2.0, s * 0.08))
		"gem":
			var g := tint if tint != Color.WHITE else Color("#4cc9f0")
			var pts := PackedVector2Array([c + Vector2(0, -s * 0.42), c + Vector2(s * 0.36, -s * 0.08), c + Vector2(0, s * 0.42), c + Vector2(-s * 0.36, -s * 0.08)])
			draw_colored_polygon(_grow(pts, c, 1.25), outline)
			draw_colored_polygon(pts, g)
			draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c]), g.lightened(0.35))
		"flag":
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.42), Vector2(s * 0.1, s * 0.84)), outline)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.42), c + Vector2(s * 0.38, -s * 0.24), c + Vector2(-s * 0.2, -s * 0.04)]), Color("#4cc9f0"))

static func _grow(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out

func _heart(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(-r * 0.48, -r * 0.3), r * 0.52, col)
	draw_circle(c + Vector2(r * 0.48, -r * 0.3), r * 0.52, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.98, -r * 0.18), c + Vector2(r * 0.98, -r * 0.18), c + Vector2(0, r * 0.85)]), col)

func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.48
		pts.append(c + Vector2.from_angle(TAU * i / 10.0 - PI / 2.0) * rr)
	draw_colored_polygon(pts, col)
