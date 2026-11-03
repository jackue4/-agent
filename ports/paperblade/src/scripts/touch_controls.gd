extends CanvasLayer
## Mobile touch layer: a floating joystick anywhere on screen + a pause button.
## Drives the same move_* InputMap actions as the keyboard, so gameplay code is shared.
## Activates on mobile browsers, or on the first real touch event anywhere.

const DEAD := 0.12
const RADIUS := 90.0

var game
var active := false
var _pad: Control
var _stick_id := -1
var _origin := Vector2.ZERO
var _pos := Vector2.ZERO
var _vec := Vector2.ZERO
var _pause_pos := Vector2.ZERO
var _pause_r := 40.0
var _idle_t := 0.0


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pad = Control.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	if G.touch:
		activate()
	else:
		visible = false


func activate() -> void:
	if active:
		return
	active = true
	visible = true
	G.touch = true
	if G.hud != null and G.hud.menu_kind == "title":
		G.hud.show_title()


func _playing() -> bool:
	return game != null and game.state == "play"


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	_pause_r = 42.0
	_pause_pos = Vector2(s.x * 0.5 + 190.0, 58.0)


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if not active:
		activate()
	_layout()
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if not _playing():
				return
			if p.distance_to(_pause_pos) <= _pause_r * 1.4:
				_release()
				game.toggle_pause()
				get_viewport().set_input_as_handled()
				return
			if _stick_id < 0:
				_stick_id = event.index
				_origin = p
				_pos = p
				_set_vec(Vector2.ZERO)
				get_viewport().set_input_as_handled()
		elif event.index == _stick_id:
			_release()
			get_viewport().set_input_as_handled()
		_pad.queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_id:
		_pos = event.position
		var d: Vector2 = _pos - _origin
		# the base follows the finger when dragged past the ring, so direction changes stay instant
		if d.length() > RADIUS * 1.4:
			_origin = _pos - d.normalized() * RADIUS * 1.4
		_set_vec((_pos - _origin) / RADIUS)
		get_viewport().set_input_as_handled()
		_pad.queue_redraw()


func _process(delta: float) -> void:
	if not active:
		return
	if not _playing() and _stick_id >= 0:
		_release()
	_idle_t = _idle_t + delta if _stick_id < 0 else 0.0
	_pad.queue_redraw()


func _release() -> void:
	_stick_id = -1
	_set_vec(Vector2.ZERO)


func _set_vec(v: Vector2) -> void:
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < DEAD:
		v = Vector2.ZERO
	_vec = v
	_axis("move_left", "move_right", v.x)
	_axis("move_up", "move_down", v.y)


func _axis(neg: String, pos: String, x: float) -> void:
	if x < 0.0:
		Input.action_press(neg, -x)
		Input.action_release(pos)
	elif x > 0.0:
		Input.action_press(pos, x)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _draw_pad() -> void:
	if not active or not _playing():
		return
	_layout()
	var s := get_viewport().get_visible_rect().size
	# pause button (two bars)
	_pad.draw_circle(_pause_pos, _pause_r, Color(0.08, 0.04, 0.14, 0.55))
	_pad.draw_arc(_pause_pos, _pause_r, 0, TAU, 40, Color(1.0, 0.85, 0.5, 0.85), 3.0)
	for dx in [-9.0, 9.0]:
		_pad.draw_rect(Rect2(_pause_pos + Vector2(dx - 5.0, -14.0), Vector2(10.0, 28.0)), Color(1, 0.95, 0.85, 0.95))
	if _stick_id >= 0:
		_pad.draw_circle(_origin, RADIUS * 1.15, Color(0.06, 0.03, 0.12, 0.35))
		_pad.draw_arc(_origin, RADIUS * 1.15, 0, TAU, 48, Color(1.0, 0.88, 0.55, 0.6), 4.0)
		var knob := _origin + (_pos - _origin).limit_length(RADIUS)
		_pad.draw_circle(knob, 44.0, Color(1.0, 0.92, 0.7, 0.55))
		_pad.draw_arc(knob, 44.0, 0, TAU, 36, Color(1.0, 0.95, 0.8, 0.9), 4.0)
	elif game.time < 12.0 or _idle_t > 6.0:
		var hint := Vector2(230.0, s.y - 200.0)
		_pad.draw_arc(hint, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.3), 3.0)
		_pad.draw_circle(hint, 38.0, Color(1, 1, 1, 0.2))
		var txt := "按住屏幕任意处拖动 移动"
		var fs := 30
		var tw := G.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_pad.draw_string_outline(G.font, hint + Vector2(-tw * 0.5, RADIUS + 50.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.08, 0.04, 0.1))
		_pad.draw_string(G.font, hint + Vector2(-tw * 0.5, RADIUS + 50.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.85))
