extends Node2D
## "AI builder" avatar: a little robot drone that flies around and builds the level in front of the user.
## Code-engine games use colour and motion to distinguish the crew. Short speech bubbles convey
## progress without covering the game with role labels, source code or implementation details.

var t := 0.0
var beam_t := 0.0
var beam_rect := Rect2()
var talk := ""
var label: Label
var eye_col := Color("#7df9ff")
var body_col := Color("#8b5cf6")
var state := ""            ## "" | thinking | coding | testing | done
var _talk_left := 0.0
var _spawn_t := 0.0

func _ready() -> void:
	z_index = 100
	label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("#1b1b3a"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.border_color = body_col
	sb.set_border_width_all(2)
	label.add_theme_stylebox_override("normal", sb)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 180.0
	label.visible = false
	add_child(label)

## Keep crew identity visual; the conversation sidebar owns detailed roles and messages.
func make_crew(_display_name: String, col: Color) -> void:
	body_col = col
	(label.get_theme_stylebox("normal") as StyleBoxFlat).border_color = col
	_spawn_t = 0.6

func say(text: String) -> void:
	if text == "":
		label.visible = false
		_talk_left = 0.0
		return
	var brief := text.replace("\n", " ").strip_edges()
	if brief.length() > 24:
		brief = brief.left(23) + "…"
	if label.visible and label.text == brief:
		return
	label.text = brief
	label.visible = true
	_talk_left = 4.0
	label.reset_size()
	label.position = Vector2(-label.size.x * 0.5, 52)
	label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.15)

## Kept for existing callers; source code does not belong in the game scene.
func show_code(_text: String) -> void:
	pass

func set_state(s: String) -> void:
	state = s
	if s == "done":
		show_code("")

func fly_to(target: Vector2, dur := 0.35) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "position", target + Vector2(0, -140), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tw

## Moves to an exact screen point (crew home spots).
func hover_to(target: Vector2, dur := 0.6) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "position", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw

func beam(r: Rect2) -> void:
	beam_rect = Rect2(to_local(r.position), r.size)
	beam_t = 0.5

func _process(delta: float) -> void:
	t += delta
	beam_t = maxf(0.0, beam_t - delta)
	_spawn_t = maxf(0.0, _spawn_t - delta)
	if _talk_left > 0.0:
		_talk_left = maxf(0.0, _talk_left - delta)
		if _talk_left == 0.0:
			label.visible = false
	queue_redraw()

func _draw() -> void:
	var speed := 9.0 if state == "coding" else 4.0
	var bob := sin(t * speed) * (3.0 if state == "coding" else 5.0)
	var c := Vector2(0, bob)
	if _spawn_t > 0.0:
		var k := _spawn_t / 0.6
		draw_circle(c, 30.0 + (1.0 - k) * 60.0, Color(body_col, 0.45 * k))
		draw_arc(c, 34.0 + (1.0 - k) * 90.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8 * k), 3.0)
	if beam_t > 0.0:
		var a := beam_t / 0.5
		var pts := PackedVector2Array([c + Vector2(-10, 18), c + Vector2(10, 18), beam_rect.end, Vector2(beam_rect.position.x, beam_rect.end.y)])
		draw_colored_polygon(pts, Color(0.55, 0.9, 1.0, 0.28 * a))
		draw_rect(beam_rect, Color(0.6, 0.95, 1.0, 0.8 * a), false, 3.0)
	# glow
	draw_circle(c, 40, Color(body_col, 0.18))
	if state == "thinking":
		for i in 3:
			var ang := t * 3.0 + float(i) * TAU / 3.0
			draw_circle(c + Vector2(cos(ang) * 44.0, sin(ang) * 14.0 - 44.0), 4.5, Color(1, 1, 1, 0.55 + 0.45 * sin(t * 5.0 + float(i))))
	elif state == "testing":
		draw_arc(c, 46, t * 4.0, t * 4.0 + 2.2, 24, Color("#facc15"), 4.0)
	elif state == "done":
		draw_circle(c + Vector2(26, -26), 10, Color("#10b981"))
		draw_polyline(PackedVector2Array([c + Vector2(21, -26), c + Vector2(25, -22), c + Vector2(31, -30)]), Color.WHITE, 2.5)
	# propeller
	var pw := 34.0 * absf(cos(t * 30.0))
	draw_line(c + Vector2(0, -26), c + Vector2(0, -36), Color("#444"), 3.0)
	draw_line(c + Vector2(-pw, -37), c + Vector2(pw, -37), Color("#333"), 4.0)
	# body
	draw_circle(c, 26, body_col)
	draw_circle(c + Vector2(-6, -8), 10, body_col.lightened(0.3))
	# face screen
	var face := Rect2(c + Vector2(-18, -10), Vector2(36, 22))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1b1b3a")
	sb.set_corner_radius_all(8)
	draw_style_box(sb, face)
	var blink := 1.0 if fmod(t, 3.0) > 0.12 else 0.15
	draw_rect(Rect2(c + Vector2(-11, -4), Vector2(7, 10 * blink)), eye_col)
	draw_rect(Rect2(c + Vector2(4, -4), Vector2(7, 10 * blink)), eye_col)
	# arms (typing fast while coding)
	var arm := sin(t * 22.0) * 6.0 if state == "coding" else bob * 0.5
	draw_line(c + Vector2(-24, 6), c + Vector2(-36, 18 + arm), body_col.darkened(0.3), 4.0)
	draw_line(c + Vector2(24, 6), c + Vector2(36, 18 - arm), body_col.darkened(0.3), 4.0)
