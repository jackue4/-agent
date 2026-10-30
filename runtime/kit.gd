extends Node
## Game SDK for AI-written games (the "code" engine), registered as the autoload `G`.
## AI code calls only this API for flow (win/lose/score), feedback (sound, tweens, particles,
## floating text), styled UI pieces and assets, so every generated game shares the platform's
## polish. Rules and layout are always the game's own code: nothing here is genre-specific.

signal asset_ready(id: String)

const OVERLAY_LAYER := 40
const DEFAULT_PALETTE := ["#8b5cf6", "#22d3ee", "#facc15", "#f472b6", "#34d399"]

var main = null          ## runtime main.gd (set by code_world.gd)
var game: Node = null    ## root node of the running AI game
var rng := RandomNumberGenerator.new()
var palette: Array[Color] = []
var score := 0
var test_log: Array = []   ## [{ok, what}] from G.check() in auto_test()
var show_clicks := false   ## AI test drives (live session, preview mirror) leave a ripple where they click
var _overlay: CanvasLayer
var _shake_tw: Tween
var _capture: ErrorCapture

## Collects script errors raised by AI code (files under user://ugc/) so the platform can show
## them to the AI for repair. Logger callbacks may arrive on any thread, hence the mutex.
class ErrorCapture extends Logger:
	var mutex := Mutex.new()
	var entries: Array = []
	var seen := {}
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		var where := file
		var ln := line
		if not where.begins_with("user://ugc/"):
			for bt in script_backtrace:
				if bt.get_frame_count() > 0 and bt.get_frame_file(0).begins_with("user://ugc/"):
					where = bt.get_frame_file(0)
					ln = bt.get_frame_line(0)
					break
		if not where.begins_with("user://ugc/"):
			return
		var msg := code if rationale == "" else code + " (" + rationale + ")"
		var e := {"file": where.get_file(), "line": ln, "message": msg.strip_edges(), "kind": "warning" if error_type == ERROR_TYPE_WARNING else "error"}
		var key := "%s:%d:%s" % [e.file, ln, e.message]
		mutex.lock()
		if not seen.has(key) and entries.size() < 200:
			seen[key] = true
			entries.append(e)
		mutex.unlock()
	func take() -> Array:
		mutex.lock()
		var out := entries.duplicate()
		entries.clear()
		mutex.unlock()
		return out
	func forget() -> void:
		mutex.lock()
		seen.clear()
		entries.clear()
		mutex.unlock()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture = ErrorCapture.new()
	OS.add_logger(_capture)
	_overlay = CanvasLayer.new()
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)
	set_palette([])

# ------------------------------------------------------------------ setup (runtime only)

func set_palette(hexes: Array) -> void:
	palette.clear()
	for h in (hexes if hexes.size() >= 3 else DEFAULT_PALETTE):
		palette.append(Color.from_string(str(h), Color.WHITE))

func reset() -> void:
	score = 0
	test_log.clear()
	rng.randomize()
	for c in _overlay.get_children():
		c.queue_free()

# ------------------------------------------------------------------ game flow

## Screen size in pixels (the game always fills the screen).
func screen() -> Vector2:
	return get_viewport().get_visible_rect().size

## Ends the run as a win; shows the platform result card (stars from stars 1-3).
func win(final_score := -1, stars := 3) -> void:
	if final_score >= 0:
		score = final_score
	if main:
		main.code_over(true, score, clampi(stars, 1, 3))

func lose(final_score := -1) -> void:
	if final_score >= 0:
		score = final_score
	if main:
		main.code_over(false, score, 0)

func add_score(n: int) -> void:
	score += n

## Seconds since the run started (pauses with the game).
func elapsed() -> float:
	return main.elapsed if main else 0.0

## Awaitable delay that respects pause: `await G.wait(0.3)`
func wait(secs: float) -> Signal:
	return get_tree().create_timer(secs, false).timeout

# ------------------------------------------------------------------ sound

## Built-in sounds: pop sparkle jump coin hurt win lose whoosh step land stomp checkpoint tick star
func sfx(sound_name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if main:
		main.audio.play(sound_name, vol_db, pitch)

## Pickup-style sound whose pitch climbs on quick repeats (combos, chains, card flips).
func sfx_combo(sound_name := "coin") -> void:
	if main:
		main.audio.play_combo(sound_name)

# ------------------------------------------------------------------ juice

func toast(text: String, color := Color.WHITE, secs := 1.4) -> void:
	if main:
		main.ui.toast(text, color, secs)

## Rising, fading text at a screen position (damage numbers, "+50", "Combo!").
func float_text(pos: Vector2, text: String, color := Color.WHITE, font_size := 36) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 6))
	_overlay.add_child(l)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.position = pos - l.size * 0.5
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)

## Particle burst at a screen position.
func burst(pos: Vector2, color := Color.WHITE, amount := 24, spread := 260.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = spread * 0.4
	p.initial_velocity_max = spread
	p.gravity = Vector2(0, 520)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 9.0
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	_overlay.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

## Quick scale "pop" (feedback on click, score change, card played).
func pop(node: CanvasItem, amount := 1.18, secs := 0.25) -> void:
	if not is_instance_valid(node):
		return
	if node is Control:
		(node as Control).pivot_offset = (node as Control).size * 0.5
	var base: Vector2 = node.scale
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base * amount, secs * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", base, secs * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Horizontal shake of one node (wrong move, damage). Use shake_screen() for the whole game.
func shake(node: CanvasItem, amount := 10.0, secs := 0.3) -> void:
	if not is_instance_valid(node):
		return
	var base: Vector2 = node.position
	var tw := node.create_tween()
	var n := 6
	for i in n:
		var k := 1.0 - float(i) / n
		tw.tween_property(node, "position", base + Vector2((amount if i % 2 == 0 else -amount) * k, 0), secs / n)
	tw.tween_property(node, "position", base, secs / n)

func shake_screen(amount := 10.0) -> void:
	if game is CanvasItem:
		if _shake_tw and _shake_tw.is_valid():
			_shake_tw.kill()
			(game as CanvasItem).set("position", Vector2.ZERO)
		_shake_tw = game.create_tween()
		for i in 6:
			var k := 1.0 - i / 6.0
			_shake_tw.tween_property(game, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * k, 0.035)
		_shake_tw.tween_property(game, "position", Vector2.ZERO, 0.035)

## Brief colour flash (hit, select, match).
func flash(node: CanvasItem, color := Color(1.6, 1.6, 1.6), secs := 0.18) -> void:
	if not is_instance_valid(node):
		return
	var base: Color = node.modulate
	node.modulate = color
	node.create_tween().tween_property(node, "modulate", base, secs)

## Tween position (Control or Node2D). Returns the Tween so callers can `await tw.finished`.
func move_to(node: CanvasItem, pos: Vector2, secs := 0.3, trans := Tween.TRANS_CUBIC) -> Tween:
	var tw := node.create_tween()
	tw.tween_property(node, "position", pos, secs).set_trans(trans).set_ease(Tween.EASE_OUT)
	return tw

func fade_in(node: CanvasItem, secs := 0.25) -> Tween:
	node.modulate.a = 0.0
	node.visible = true
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, secs)
	return tw

func fade_out(node: CanvasItem, secs := 0.25, free_after := false) -> Tween:
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 0.0, secs)
	if free_after:
		tw.tween_callback(node.queue_free)
	return tw

## Animated number on a Label (scores, chips, gold).
func count_up(label: Label, from_value: int, to_value: int, secs := 0.5, prefix := "", suffix := "") -> void:
	var tw := label.create_tween()
	tw.tween_method(func(v: float): label.text = prefix + str(int(round(v))) + suffix, float(from_value), float(to_value), secs)

## Hover lift for a Control: grows slightly and rises while hovered (cards, tiles, buttons).
func hover_lift(c: Control, lift := 14.0, grow := 1.06) -> void:
	c.mouse_entered.connect(func():
		c.pivot_offset = c.size * 0.5
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "scale", Vector2(grow, grow), 0.12)
		tw.tween_property(c, "position:y", c.position.y - lift, 0.12)
		c.set_meta("_lift", lift))
	c.mouse_exited.connect(func():
		var l: float = c.get_meta("_lift", 0.0)
		c.set_meta("_lift", 0.0)
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "scale", Vector2.ONE, 0.12)
		tw.tween_property(c, "position:y", c.position.y + l, 0.12))

## Makes a Control draggable with mouse or touch. on_drop(control, global_pos) -> bool:
## return true to accept the drop, false to snap back to where the drag started.
func make_draggable(c: Control, on_drop: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				c.set_meta("_drag_from", c.position)
				c.set_meta("_drag_off", c.get_global_mouse_position() - c.global_position)
				c.z_index = 50
			elif c.has_meta("_drag_from"):
				var from: Vector2 = c.get_meta("_drag_from")
				c.remove_meta("_drag_from")
				c.z_index = 0
				if not bool(on_drop.call(c, c.get_global_mouse_position())):
					move_to(c, from, 0.2, Tween.TRANS_BACK)
		elif ev is InputEventMouseMotion and c.has_meta("_drag_from"):
			var off: Vector2 = c.get_meta("_drag_off")
			c.global_position = c.get_global_mouse_position() - off)

# ------------------------------------------------------------------ styled UI pieces

## Palette colour i (wraps). The palette comes from the game design (meta.palette).
func color(i: int) -> Color:
	return palette[posmod(i, palette.size())]

func style(bg: Color, radius := 16, border := Color.TRANSPARENT, border_w := 0, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.4)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func label(text: String, font_size := 24, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func panel(bg: Color, radius := 16, border := Color.TRANSPARENT, border_w := 0, shadow := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(bg, radius, border, border_w, shadow))
	return p

## Rounded button with hover / press states and a click sound.
func button(text: String, bg := Color(-1, 0, 0), font_size := 24) -> Button:
	var col := color(0) if bg.r < 0.0 else bg
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.add_theme_stylebox_override("normal", style(col, 14, col.lightened(0.25), 2, 6))
	b.add_theme_stylebox_override("hover", style(col.lightened(0.12), 14, col.lightened(0.4), 2, 8))
	b.add_theme_stylebox_override("pressed", style(col.darkened(0.15), 14, col.lightened(0.2), 2, 2))
	b.add_theme_stylebox_override("disabled", style(Color(col.darkened(0.5), 0.7), 14, Color.TRANSPARENT, 0, 0))
	b.custom_minimum_size = Vector2(0, font_size * 2.2)
	b.pressed.connect(func():
		sfx("pop", -2.0)
		pop(b, 1.08, 0.18))
	return b

## Texture of an AI-generated image asset, or null while it is still being painted.
## Connect to asset_ready(id) to swap placeholders in when it arrives.
func tex(asset_id: String) -> Texture2D:
	if main == null:
		return null
	var r = main.assets.get_res(asset_id)
	return r as Texture2D if r is Texture2D else null

## Draws a vector icon on any CanvasItem inside its _draw():
## shape = heart diamond club spade star circle square triangle.
func draw_shape(ci: CanvasItem, shape: String, c: Vector2, r: float, col: Color) -> void:
	match shape:
		"heart":
			ci.draw_circle(c + Vector2(-r * 0.48, -r * 0.25), r * 0.52, col)
			ci.draw_circle(c + Vector2(r * 0.48, -r * 0.25), r * 0.52, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.98, -r * 0.1), c + Vector2(r * 0.98, -r * 0.1), c + Vector2(0, r * 0.95)]), col)
		"diamond":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.72, 0), c + Vector2(0, r), c + Vector2(-r * 0.72, 0)]), col)
		"club":
			ci.draw_circle(c + Vector2(0, -r * 0.45), r * 0.42, col)
			ci.draw_circle(c + Vector2(-r * 0.47, r * 0.12), r * 0.42, col)
			ci.draw_circle(c + Vector2(r * 0.47, r * 0.12), r * 0.42, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.12, 0), c + Vector2(r * 0.12, 0), c + Vector2(r * 0.35, r), c + Vector2(-r * 0.35, r)]), col)
		"spade":
			ci.draw_circle(c + Vector2(-r * 0.45, r * 0.1), r * 0.45, col)
			ci.draw_circle(c + Vector2(r * 0.45, r * 0.1), r * 0.45, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, r * 0.05), c + Vector2(-r * 0.9, r * 0.05)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.12, r * 0.2), c + Vector2(r * 0.12, r * 0.2), c + Vector2(r * 0.35, r), c + Vector2(-r * 0.35, r)]), col)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
			ci.draw_colored_polygon(pts, col)
		"square":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), col)
		"triangle":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, r * 0.7), c + Vector2(-r * 0.9, r * 0.7)]), col)
		_:
			ci.draw_circle(c, r, col)

# ------------------------------------------------------------------ self-test (auto_test)

## Records one assertion of the game's auto_test(); the platform reports failures to the AI.
func check(ok: bool, what: String) -> bool:
	test_log.append({"ok": ok, "what": what})
	return ok

## Simulated left click at a screen position (goes through normal GUI input handling).
func click_at(pos: Vector2) -> void:
	var vp := get_viewport()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev, true)
	if show_clicks:
		var r := Ripple.new()
		r.position = pos
		_overlay.add_child(r)

class Ripple extends Node2D:
	var t := 0.0
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _process(dt: float) -> void:
		t += dt * 2.2
		queue_redraw()
		if t >= 1.0:
			queue_free()
	func _draw() -> void:
		var a := 1.0 - t
		draw_arc(Vector2.ZERO, 12.0 + 36.0 * t, 0.0, TAU, 40, Color(1.0, 0.85, 0.3, a), 5.0)
		draw_circle(Vector2.ZERO, 9.0 * a, Color(1, 1, 1, a))

## Compact view of a node subtree for debugging layout from game_eval: path, class, global rect,
## visibility and text. Capped so it fits in a tool result.
func describe(root: Node = null, depth := 2) -> Array:
	var out: Array = []
	if root == null:
		root = game
	if root != null and is_instance_valid(root):
		_describe(root, root, depth, out)
	return out

func _describe(root: Node, n: Node, depth: int, out: Array) -> void:
	if out.size() >= 80:
		return
	var d := {"path": str(root.get_path_to(n)), "type": n.get_class()}
	if n is Control:
		var r := (n as Control).get_global_rect()
		d["rect"] = [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
		d["visible"] = (n as Control).is_visible_in_tree()
	elif n is Node2D:
		var p := (n as Node2D).global_position
		d["pos"] = [roundi(p.x), roundi(p.y)]
		d["visible"] = (n as Node2D).is_visible_in_tree()
	var t = n.get("text")
	if typeof(t) == TYPE_STRING and t != "":
		d["text"] = (t as String).left(40)
	out.append(d)
	if depth > 0:
		for c in n.get_children():
			_describe(root, c, depth - 1, out)

## Simulated click on the centre of a Control.
func click(c: Control) -> void:
	if is_instance_valid(c) and c.is_visible_in_tree():
		click_at(c.get_global_rect().get_center())

## Script errors from AI code since the last call (used by the runtime).
func take_errors() -> Array:
	return _capture.take()

func forget_errors() -> void:
	_capture.forget()

# ------------------------------------------------------------------ data helpers

## In-place Fisher-Yates shuffle using the run's RNG; returns the same array.
func shuffle(arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr

func pick(arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)] if not arr.is_empty() else null
