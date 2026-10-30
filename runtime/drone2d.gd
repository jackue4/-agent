extends Node2D
## "AI builder" avatar: a little robot drone that flies around and builds the level in front of the user.
## Code-engine games use colour and motion to distinguish the crew. Short speech bubbles convey
## progress without covering the game with role labels, source code or implementation details.
const ROBOT_TEXTURE: Texture2D = preload("res://art/ai-robot.png")
const ROBOT_SIZE := Vector2(112, 112)

var t := 0.0
var beam_t := 0.0
var beam_rect := Rect2()
var talk := ""
var label: Label
var body_col := Color("#8b5cf6")
var state := ""            ## "" | thinking | coding | testing | done
var _talk_left := 0.0
var _spawn_t := 0.0

func _ready() -> void:
	z_index = 100
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	label.position = Vector2(-label.size.x * 0.5, 62)
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
	var c := Vector2(0, roundf(bob))
	if _spawn_t > 0.0:
		var k := _spawn_t / 0.6
		draw_circle(c, 30.0 + (1.0 - k) * 60.0, Color(body_col, 0.45 * k))
		draw_arc(c, 34.0 + (1.0 - k) * 90.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8 * k), 3.0)
	if beam_t > 0.0:
		var a := beam_t / 0.5
		var pts := PackedVector2Array([c + Vector2(-10, 18), c + Vector2(10, 18), beam_rect.end, Vector2(beam_rect.position.x, beam_rect.end.y)])
		draw_colored_polygon(pts, Color(0.55, 0.9, 1.0, 0.28 * a))
		draw_rect(beam_rect, Color(0.6, 0.95, 1.0, 0.8 * a), false, 3.0)
	# Keep the generated pixel character upright and untinted. Crew colour lives in the halo.
	draw_circle(c, 49, Color(body_col, 0.08 + sin(t * 2.0) * 0.025))
	draw_arc(c, 52.0, t * 0.7, t * 0.7 + 2.5, 36, Color(body_col, 0.36), 1.5, true)
	draw_set_transform(c)
	draw_texture_rect(ROBOT_TEXTURE, Rect2(-ROBOT_SIZE * 0.5, ROBOT_SIZE), false)
	draw_set_transform(Vector2.ZERO)
	if state == "thinking":
		for i in 3:
			var ang := t * 3.0 + float(i) * TAU / 3.0
			draw_circle(c + Vector2(cos(ang) * 44.0, sin(ang) * 10.0 - 58.0), 3.5, Color(0.7, 0.92, 1.0, 0.55 + 0.45 * sin(t * 5.0 + float(i))))
	elif state == "testing":
		draw_arc(c, 55, t * 4.0, t * 4.0 + 2.2, 24, Color("#7dd3fc"), 3.0, true)
	elif state == "done":
		draw_circle(c + Vector2(38, -38), 10, Color("#10b981"))
		draw_polyline(PackedVector2Array([c + Vector2(33, -38), c + Vector2(37, -34), c + Vector2(43, -42)]), Color.WHITE, 2.5)
