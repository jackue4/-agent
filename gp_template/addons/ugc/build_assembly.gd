extends Node2D
## Authoring-only assembly pass over a freshly loaded build. Pieces of the real screen that are
## new since the previous build start under blueprint veils; a fairy flies to each one and the
## veil is wiped away. Game nodes are only read, never moved, hidden or modified.

signal finished(count: int)

const FAIRY = preload("res://addons/ugc/build_fairy.gd")
const MAX_PIECES := 28
const TOTAL_SECONDS := 8.0
const INK := Color(0.05, 0.1, 0.19, 0.93)
const LINE := Color(0.45, 0.85, 1.0)

var pieces: Array = []       ## {key, rect, label, kind: "new"|"changed"}
var current := -1
var revealed := 0
var per_piece := 0.6
var _t := 0.0
var _flashes: Array = []     ## {rect, life}
var _fairy: Node2D
var _font: Font
var _rng := RandomNumberGenerator.new()
var _done := false

## Visible pieces of the running scene keyed by node path. Shared by the baseline and the pass.
static func scan(root: Node, view: Rect2) -> Array:
	var out: Array = []
	if root == null or not is_instance_valid(root):
		return out
	if root is CanvasItem and root.has_method("_draw") and (root as CanvasItem).is_visible_in_tree():
		out.append({"key": ".:" + root.get_class(), "rect": view, "label": "场景"})
	_scan(root, view, out, 0, "")
	var seen := {}
	var unique: Array = []
	for row in out:
		var r: Rect2 = row.rect
		var sig := "%d,%d,%d,%d" % [roundi(r.position.x / 4), roundi(r.position.y / 4), roundi(r.size.x / 4), roundi(r.size.y / 4)]
		if seen.has(sig):
			continue
		seen[sig] = true
		unique.append(row)
	unique.sort_custom(func(a, b): return a.rect.get_area() > b.rect.get_area())
	return unique

static func _scan(n: Node, view: Rect2, out: Array, depth: int, prefix: String) -> void:
	if depth > 10 or out.size() >= 160:
		return
	var auto_index := {}
	for c in n.get_children():
		# Code-built UI gets generated names (@Label@23) that differ per run; key those by
		# structure (class and order among unnamed siblings) so a rebuild maps to the same piece.
		var segment := str(c.name)
		if segment.contains("@"):
			var cls := c.get_class()
			auto_index[cls] = int(auto_index.get(cls, -1)) + 1
			segment = cls + "#" + str(auto_index[cls])
		if not (c is CanvasItem) and not (c is CanvasLayer):
			continue
		if c is CanvasItem and not (c as CanvasItem).is_visible_in_tree():
			continue
		if c is CanvasLayer and not (c as CanvasLayer).visible:
			continue
		var path := segment if prefix == "" else prefix + "/" + segment
		if c is CanvasItem:
			var rect = _rect_of(c as CanvasItem)
			if rect is Rect2:
				var clipped: Rect2 = (rect as Rect2).intersection(view)
				if clipped.get_area() >= 140.0 and (c as CanvasItem).modulate.a > 0.05:
					out.append({"key": path + ":" + c.get_class(), "rect": clipped, "label": _label_of(c), "control": c is Control})
		_scan(c, view, out, depth + 1, path)

static func _rect_of(c: CanvasItem):
	var local = null
	if c is Control:
		var ctl := c as Control
		if ctl is Container and not ctl is PanelContainer:
			return null
		if ctl.get_class() == "Control" and ctl.get_script() == null:
			return null
		if ctl is Label and (ctl as Label).text.strip_edges() == "":
			return null
		local = Rect2(Vector2.ZERO, ctl.size)
	elif c is Sprite2D and (c as Sprite2D).texture != null:
		local = (c as Sprite2D).get_rect()
	elif c is AnimatedSprite2D and (c as AnimatedSprite2D).sprite_frames != null:
		var a := c as AnimatedSprite2D
		var tex := a.sprite_frames.get_frame_texture(a.animation, a.frame) if a.sprite_frames.has_animation(a.animation) else null
		if tex != null:
			var s := tex.get_size()
			local = Rect2((-s * 0.5 if a.centered else Vector2.ZERO) + a.offset, s)
	elif c is TileMapLayer and (c as TileMapLayer).tile_set != null:
		var t := c as TileMapLayer
		var used := t.get_used_rect()
		if used.size.x > 0:
			var ts := Vector2(t.tile_set.tile_size)
			local = Rect2(Vector2(used.position) * ts, Vector2(used.size) * ts)
	elif c is Polygon2D and (c as Polygon2D).polygon.size() >= 3:
		var poly := (c as Polygon2D).polygon
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		local = box
	elif c is Node2D and c.get_script() != null and c.has_method("_draw"):
		local = Rect2(Vector2(-28, -28), Vector2(56, 56))
	if local == null or (local as Rect2).get_area() <= 0.0:
		return null
	return c.get_global_transform_with_canvas() * (local as Rect2)

static func _label_of(c: Node) -> String:
	var kind := "部件"
	if c is BaseButton:
		kind = "按钮"
	elif c is Label or c is RichTextLabel:
		kind = "文字"
	elif c is Range:
		kind = "进度条"
	elif c is TextureRect or c is Sprite2D or c is AnimatedSprite2D:
		kind = "图像"
	elif c is Panel or c is PanelContainer or c is NinePatchRect:
		kind = "面板"
	elif c is ColorRect:
		kind = "底板"
	elif c is TileMapLayer:
		kind = "地图"
	elif c is Node2D:
		kind = "角色" if c.get_script() != null else "图形"
	var text = c.get("text")
	if typeof(text) == TYPE_STRING and (text as String).strip_edges() != "":
		kind += "「" + (text as String).strip_edges().replace("\n", " ").left(6) + "」"
	return kind

static func baseline_of(rows: Array) -> Dictionary:
	var out := {}
	for row in rows:
		var r: Rect2 = row.rect
		out[row.key] = [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
	return out

## Pieces that are new or (for UI) moved since `previous`. An empty baseline means a first build.
static func diff(rows: Array, previous: Dictionary) -> Array:
	var out: Array = []
	for row in rows:
		if not previous.has(row.key):
			# A scene drawn by its root script has no child nodes to assemble; paint it in bands.
			if str(row.key).begins_with(".:"):
				var r: Rect2 = row.rect
				var bands := 4 if r.size.y > r.size.x else 3
				for i in bands:
					var band := Rect2(r.position.x, r.position.y + r.size.y * i / bands, r.size.x, r.size.y / bands)
					out.append(row.merged({"rect": band, "label": "场景 %d/%d" % [i + 1, bands], "kind": "new"}, true))
				continue
			out.append(row.merged({"kind": "new"}))
		elif row.get("control", false):
			var old = previous[row.key]
			var r: Rect2 = row.rect
			if old is Array and old.size() == 4 and (absf(r.position.x - float(old[0])) > 6 or absf(r.position.y - float(old[1])) > 6 or absf(r.size.x - float(old[2])) > 6 or absf(r.size.y - float(old[3])) > 6):
				out.append(row.merged({"kind": "changed"}))
	return out.slice(0, MAX_PIECES)

func start(rows: Array) -> void:
	name = "UGCAssembly"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://addons/ugc/font.ttf"):
		_font = load("res://addons/ugc/font.ttf") as Font
	pieces = rows
	per_piece = clampf(TOTAL_SECONDS / maxf(1.0, rows.size()), 0.3, 0.75)
	_fairy = FAIRY.new()
	add_child(_fairy)
	_fairy.setup("assembly", {"name": "搭建小精灵", "state": "building"}, get_viewport().get_visible_rect().size)
	_fairy.position = Vector2(-40, get_viewport().get_visible_rect().size.y * 0.25)
	_next()

func _next() -> void:
	current += 1
	_t = 0.0
	if current >= pieces.size():
		_finish()
		return
	var row: Dictionary = pieces[current]
	var r: Rect2 = row.rect
	var verb := "拼装" if row.kind == "new" else "调整"
	_fairy.assist(Vector2(r.position.x + minf(r.size.x * 0.5, 120.0), r.position.y + minf(r.size.y * 0.5, 80.0)), verb + str(row.label))

func _finish() -> void:
	if _done:
		return
	_done = true
	_fairy.set_work({"state": "done"})
	_fairy.cast(_fairy.position, 24)
	finished.emit(revealed)
	await get_tree().create_timer(1.6, true, false, true).timeout
	queue_free()

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i].life -= delta
		if _flashes[i].life <= 0.0:
			_flashes.remove_at(i)
	if not _done and current < pieces.size():
		_t += delta
		var row: Dictionary = pieces[current]
		var travel := per_piece * 0.35
		var wipe := _wipe()
		if _t > travel and wipe < 1.0 and _rng.randf() < 0.7:
			var r: Rect2 = row.rect
			_fairy.cast(Vector2(r.position.x + r.size.x * wipe, r.position.y + _rng.randf() * r.size.y), 2)
		if _t >= per_piece:
			_flashes.append({"rect": row.rect, "life": 0.5})
			revealed += 1
			_next()
	queue_redraw()

func _wipe() -> float:
	var travel := per_piece * 0.35
	return clampf((_t - travel) / maxf(0.01, per_piece - travel), 0.0, 1.0)

func _draw() -> void:
	if _done:
		_draw_flashes()
		return
	# Pending new pieces stay veiled; drawn largest first so smaller pieces sit on top.
	for i in range(maxi(current, 0), pieces.size()):
		var row: Dictionary = pieces[i]
		if row.kind != "new":
			continue
		var r: Rect2 = row.rect
		if i == current:
			var w := _wipe()
			var cut := r.size.x * w
			_veil(Rect2(r.position + Vector2(cut, 0), Vector2(r.size.x - cut, r.size.y)), r)
			if w > 0.0 and w < 1.0:
				var x := r.position.x + cut
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.9), 3.0)
				draw_line(Vector2(x - 6, r.position.y), Vector2(x - 6, r.end.y), Color(LINE.r, LINE.g, LINE.b, 0.35), 8.0)
		else:
			_veil(r, r)
	if current >= 0 and current < pieces.size() and pieces[current].kind == "changed":
		var r: Rect2 = pieces[current].rect
		var a := 0.4 + 0.5 * sin(_t * 18.0)
		draw_rect(r.grow(2), Color(1.0, 0.9, 0.5, a), false, 2.0)
	_draw_flashes()

func _veil(part: Rect2, whole: Rect2) -> void:
	if part.size.x <= 0.5 or part.size.y <= 0.5:
		return
	draw_rect(part, INK)
	var step := 24.0
	var grid := Color(LINE.r, LINE.g, LINE.b, 0.14)
	var x := whole.position.x + step
	while x < part.end.x:
		if x > part.position.x:
			draw_line(Vector2(x, part.position.y), Vector2(x, part.end.y), grid, 1.0)
		x += step
	var y := whole.position.y + step
	while y < part.end.y:
		draw_line(Vector2(part.position.x, y), Vector2(part.end.x, y), grid, 1.0)
		y += step
	draw_rect(whole, Color(LINE.r, LINE.g, LINE.b, 0.55), false, 1.5)

func _draw_flashes() -> void:
	for f in _flashes:
		var r: Rect2 = f.rect
		var a: float = f.life / 0.5
		draw_rect(r.grow(4.0 * (1.0 - a)), Color(1.0, 0.95, 0.7, a * 0.9), false, 3.0)
		draw_rect(r, Color(1.0, 1.0, 1.0, a * 0.18))
