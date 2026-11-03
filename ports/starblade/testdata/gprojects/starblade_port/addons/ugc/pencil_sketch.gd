extends Node2D
## A pencil drawing: shapes are stored once and re-stroked with deterministic jitter, so the same
## seed always looks the same and a few "boil" frames make the lines feel alive.

const INK := Color("2a2a30")

@export var seed := 0
@export var boil := true
@export var boil_fps := 6.0
@export var boil_frames := 3

var shapes: Array = []
var _frame := 0
var _t := 0.0

func _process(delta: float) -> void:
	if not boil or boil_frames <= 1:
		return
	_t += delta
	if _t >= 1.0 / boil_fps:
		_t = 0.0
		_frame = (_frame + 1) % boil_frames
		queue_redraw()

func clear() -> void:
	shapes.clear()
	queue_redraw()

func _add(d: Dictionary) -> Node2D:
	shapes.append(d)
	queue_redraw()
	return self

## Outline (and optional colored-pencil fill / hatching) of a rectangle.
func rect(r: Rect2, ink := INK, fill := Color(0, 0, 0, 0), hatch := false, width := 2.0) -> Node2D:
	return _add({"k": "poly", "pts": PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), "ink": ink, "fill": fill, "hatch": hatch, "w": width})

func circle(center: Vector2, radius: float, ink := INK, fill := Color(0, 0, 0, 0), hatch := false, width := 2.0) -> Node2D:
	return ellipse(center, Vector2(radius, radius), ink, fill, hatch, width)

func ellipse(center: Vector2, radii: Vector2, ink := INK, fill := Color(0, 0, 0, 0), hatch := false, width := 2.0) -> Node2D:
	var pts := PackedVector2Array()
	var n := clampi(int(max(radii.x, radii.y) / 3.0), 14, 40)
	for i in n:
		var a := TAU * i / n
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return _add({"k": "poly", "pts": pts, "ink": ink, "fill": fill, "hatch": hatch, "w": width})

func poly(points: PackedVector2Array, ink := INK, fill := Color(0, 0, 0, 0), hatch := false, width := 2.0) -> Node2D:
	return _add({"k": "poly", "pts": points, "ink": ink, "fill": fill, "hatch": hatch, "w": width})

func line(a: Vector2, b: Vector2, ink := INK, width := 2.0) -> Node2D:
	return _add({"k": "line", "pts": PackedVector2Array([a, b]), "ink": ink, "w": width})

func polyline(points: PackedVector2Array, ink := INK, width := 2.0) -> Node2D:
	return _add({"k": "line", "pts": points, "ink": ink, "w": width})

func arrow(a: Vector2, b: Vector2, ink := INK, width := 2.0) -> Node2D:
	line(a, b, ink, width)
	var d := (b - a).normalized()
	var s := d.orthogonal() * 7.0
	line(b, b - d * 12.0 + s, ink, width)
	return line(b, b - d * 12.0 - s, ink, width)

func text(pos: Vector2, s: String, size := 22, ink := INK) -> Node2D:
	return _add({"k": "text", "pos": pos, "s": s, "size": size, "ink": ink})

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	for i in shapes.size():
		var d: Dictionary = shapes[i]
		rng.seed = hash([seed, i, _frame])
		var w: float = d.get("w", 2.0)
		var ink: Color = d.get("ink", INK)
		match d.k:
			"poly":
				var pts: PackedVector2Array = d.pts
				var fill: Color = d.fill
				if fill.a > 0.0:
					draw_colored_polygon(_jitter(pts, rng, 1.2), Color(fill, fill.a * 0.85))
				if d.hatch:
					for seg in _hatch(pts, rng, 7.0):
						draw_line(seg[0], seg[1], Color(ink, 0.38), 1.0, true)
				draw_polyline(_wobble(pts, true, rng), Color(ink, 0.88), w, true)
				draw_polyline(_wobble(pts, true, rng, 0.7), Color(ink, 0.35), w * 0.6, true)
			"line":
				var pts: PackedVector2Array = d.pts
				draw_polyline(_wobble(pts, false, rng), Color(ink, 0.88), w, true)
				draw_polyline(_wobble(pts, false, rng, 0.7), Color(ink, 0.3), w * 0.6, true)
			"text":
				var font := _font()
				var off := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
				draw_string(font, d.pos + off, d.s, HORIZONTAL_ALIGNMENT_LEFT, -1, d.size, Color(ink, 0.9))

static var _cjk: Font

## The platform font covers Chinese; the engine fallback font does not.
static func _font() -> Font:
	if _cjk == null and ResourceLoader.exists("res://addons/ugc/font.ttf"):
		_cjk = load("res://addons/ugc/font.ttf") as Font
	return _cjk if _cjk else ThemeDB.fallback_font

static func _jitter(pts: PackedVector2Array, rng: RandomNumberGenerator, amp: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp)))
	return out

## Subdivided, slightly bowed polyline with drifting wobble and loose overshooting ends.
static func _wobble(pts: PackedVector2Array, closed: bool, rng: RandomNumberGenerator, amp := 0.9) -> PackedVector2Array:
	var src := PackedVector2Array(pts)
	if closed and pts.size() > 1:
		src.append(pts[0])
		src.append(pts[0].lerp(pts[1], 0.12))
	var out := PackedVector2Array()
	var drift := 0.0
	for s in src.size() - 1:
		var a := src[s]
		var b := src[s + 1]
		var L := maxf(a.distance_to(b), 0.001)
		var nrm := (b - a).orthogonal() / L
		var n := maxi(2, ceili(L / 9.0))
		var bow := rng.randf_range(-1.0, 1.0) * minf(L * 0.02, 5.0)
		for k in range(0 if s == 0 else 1, n + 1):
			var t := float(k) / n
			drift = drift * 0.7 + rng.randf_range(-0.5, 0.5) * amp
			out.append(a.lerp(b, t) + nrm * (sin(PI * t) * bow + drift))
	if not closed and out.size() >= 2:
		var head := out[0] + (out[0] - out[1]).normalized() * rng.randf_range(1.0, 4.0)
		var tail := out[out.size() - 1] + (out[out.size() - 1] - out[out.size() - 2]).normalized() * rng.randf_range(1.0, 4.0)
		out.insert(0, head)
		out.append(tail)
	return out

## Diagonal shading lines clipped to a polygon.
static func _hatch(poly: PackedVector2Array, rng: RandomNumberGenerator, spacing: float) -> Array:
	var lo := INF
	var hi := -INF
	for p in poly:
		lo = minf(lo, p.x + p.y)
		hi = maxf(hi, p.x + p.y)
	var out: Array = []
	var c := lo + spacing * rng.randf_range(0.5, 1.0)
	while c < hi:
		var hits: Array = []
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var fa := a.x + a.y - c
			var fb := b.x + b.y - c
			if (fa < 0.0) != (fb < 0.0):
				hits.append(a.lerp(b, fa / (fa - fb)))
		hits.sort_custom(func(p, q): return p.x < q.x)
		var k := 0
		while k + 1 < hits.size():
			var p1: Vector2 = hits[k]
			var p2: Vector2 = hits[k + 1]
			if p1.distance_to(p2) > 3.0:
				out.append([p1.lerp(p2, rng.randf() * 0.06) + Vector2(0, rng.randf_range(-0.5, 0.5)), p2.lerp(p1, rng.randf() * 0.06)])
			k += 2
		c += spacing * rng.randf_range(0.8, 1.2)
	return out
