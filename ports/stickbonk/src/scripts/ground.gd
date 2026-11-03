class_name Ground
extends Node2D
## Martial-arts arena floor: one solid parchment colour with sparse, faint ink-stamp motifs
## (cloud, bamboo, fist, flying kick, yin-yang, nunchaku, enso, dragon, lotus).

const FLOOR := Color(0.95, 0.86, 0.66)
const STAMP := Color(0.5, 0.32, 0.18, 0.42)
const STAMP_RED := Color(0.78, 0.2, 0.14, 0.36)

var stamps: Array = []
var motifs: Array[Texture2D] = []
var tile: Texture2D = null
var floor_col := FLOOR
var stamp_col := STAMP


## Per-map hand-painted floor tile (竹林 / 火山 / 冰原); empty = classic dojo parchment.
func set_map(tex_id: String) -> void:
	tile = Art.tex(tex_id) if tex_id != "" else null
	match tex_id:
		"ground_bamboo":
			floor_col = Color(0.78, 0.84, 0.58)
			stamp_col = Color(0.2, 0.35, 0.15, 0.3)
		"ground_volcano":
			floor_col = Color(0.42, 0.3, 0.27)
			stamp_col = Color(0.1, 0.05, 0.05, 0.35)
		"ground_ice":
			floor_col = Color(0.82, 0.9, 0.97)
			stamp_col = Color(0.25, 0.4, 0.6, 0.3)
	queue_redraw()


func _ready() -> void:
	z_index = -10
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for i in 9:
		var path := "res://art/motifs/m%d.png" % i
		if ResourceLoader.exists(path):
			motifs.append(load(path))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	# jittered grid so stamps stay sparse and evenly spread (never clumped)
	var step := 420.0
	var a := G.ARENA
	var y := a.position.y + step * 0.5
	var row := 0
	while y < a.end.y:
		var x := a.position.x + step * (0.5 if row % 2 == 0 else 1.0)
		while x < a.end.x:
			if rng.randf() < 0.7 and Vector2(x, y).length() > 380.0:
				stamps.append({
					"p": Vector2(x, y) + Vector2(rng.randf_range(-110, 110), rng.randf_range(-90, 90)),
					"i": rng.randi() % maxi(motifs.size(), 1),
					"s": rng.randf_range(0.55, 0.95),
					"r": rng.randf_range(-0.5, 0.5),
					"red": rng.randf() < 0.18,
				})
			x += step
		y += step * 0.8
		row += 1


func _draw() -> void:
	var a := G.ARENA
	var ink := G.INK
	# outer void (dark comic gutter)
	draw_rect(a.grow(2000), Color(0.16, 0.12, 0.2))
	draw_rect(a, floor_col)
	if tile != null:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 2.0))
		draw_texture_rect(tile, Rect2(a.position / 2.0, a.size / 2.0), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# centre: big faint enso brush circle, like a dojo emblem
	if motifs.size() > 6:
		var en: Texture2D = motifs[6]
		var es := 4.2
		draw_set_transform(Vector2.ZERO, 0.3, Vector2(es, es))
		draw_texture(en, -en.get_size() * 0.5, Color(stamp_col, 0.2))
	for st in stamps:
		if motifs.is_empty():
			break
		var tx: Texture2D = motifs[st["i"]]
		var s: float = st["s"]
		draw_set_transform(st["p"], st["r"], Vector2(s, s))
		draw_texture(tx, -tx.get_size() * 0.5, STAMP_RED if st["red"] and tile == null else stamp_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_border(a, ink)


func _draw_border(a: Rect2, ink: Color) -> void:
	# arena wall: thick comic panel border with hazard stripes
	var w := 34.0
	var outer := a.grow(w)
	for side in 4:
		var r: Rect2
		match side:
			0: r = Rect2(outer.position.x, outer.position.y, outer.size.x, w)
			1: r = Rect2(outer.position.x, a.end.y, outer.size.x, w)
			2: r = Rect2(outer.position.x, a.position.y, w, a.size.y)
			3: r = Rect2(a.end.x, a.position.y, w, a.size.y)
		draw_rect(r, G.YELLOW)
	var x := outer.position.x
	while x < outer.end.x:
		draw_colored_polygon(PackedVector2Array([Vector2(x, outer.position.y), Vector2(x + 30, outer.position.y), Vector2(x + 30 + w, a.position.y), Vector2(x + w, a.position.y)]), ink)
		draw_colored_polygon(PackedVector2Array([Vector2(x, a.end.y), Vector2(x + 30, a.end.y), Vector2(x + 30 + w, outer.end.y), Vector2(x + w, outer.end.y)]), ink)
		x += 80
	var yy := a.position.y
	while yy < a.end.y:
		draw_colored_polygon(PackedVector2Array([Vector2(outer.position.x, yy), Vector2(a.position.x, yy + w), Vector2(a.position.x, yy + w + 30), Vector2(outer.position.x, yy + 30)]), ink)
		draw_colored_polygon(PackedVector2Array([Vector2(a.end.x, yy), Vector2(outer.end.x, yy + w), Vector2(outer.end.x, yy + w + 30), Vector2(a.end.x, yy + 30)]), ink)
		yy += 80
	draw_rect(outer, ink, false, 8.0)
	draw_rect(a, ink, false, 8.0)