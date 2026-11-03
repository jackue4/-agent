class_name TouchControls
extends CanvasLayer
## Mobile touch layer: floating joystick (left half) + comic action buttons (right).
## Drives the same InputMap actions as the keyboard, so gameplay code is shared.
## Activates on mobile browsers, or on the first real touch event anywhere.

const DEAD := 0.16

var main
var active := false
var _pad: Control
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _held := {}            ## touch index -> action
var _buttons: Array = []   ## [{action, pos, r, label, color, hold}]
var _last_layout := Vector2.ZERO


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pad = Control.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	if G.low or G.touch:
		activate()
	else:
		visible = false


func activate() -> void:
	if active:
		return
	active = true
	visible = true
	G.touch = true
	# Emulated mouse clicks from taps must not fire attacks; the buttons own combat input.
	for act in ["attack", "heavy"]:
		for ev in InputMap.action_get_events(act):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(act, ev)
	if G.player != null:
		G.player.mouse_aim = false
	_layout(true)


func _gameplay() -> bool:
	return main != null and main.state == "play"


func _layout(force := false) -> void:
	var s := get_viewport().get_visible_rect().size
	if s == _last_layout and not force:
		return
	_last_layout = s
	var u := s.y / 720.0
	var base := Vector2(s.x - 140 * u, s.y - 130 * u)
	_buttons = [
		{"action": "attack", "pos": base, "r": 74 * u, "label": "攻击", "color": G.YELLOW, "hold": true},
		{"action": "heavy", "pos": base + Vector2(-60, -165) * u, "r": 52 * u, "label": "重锤", "color": G.ORANGE, "hold": false},
		{"action": "dash", "pos": base + Vector2(-178, 30) * u, "r": 52 * u, "label": "冲刺", "color": Color(0.35, 0.8, 1.0), "hold": false},
		{"action": "pause", "pos": Vector2(440 * u, 69 * u), "r": 34 * u, "label": "暂停", "color": G.WHITE, "hold": false},
	]


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if not active:
		activate()
	_layout()
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if not _gameplay():
				return
			for b in _buttons:
				if pos.distance_to(b.pos) <= b.r * 1.3:
					get_viewport().set_input_as_handled()
					if b.action == "pause":
						_release_all()
						main.toggle_pause()
						return
					_held[event.index] = b.action
					_send(b.action, true)
					if not b.hold:
						_send.call_deferred(b.action, false)
					_pad.queue_redraw()
					return
			if _stick_id < 0 and pos.x < _last_layout.x * 0.5:
				_stick_id = event.index
				_stick_origin = pos
				_stick_pos = pos
				_set_vec(Vector2.ZERO)
				get_viewport().set_input_as_handled()
		else:
			if _held.has(event.index):
				var a: String = _held[event.index]
				_held.erase(event.index)
				if a == "attack":
					_send(a, false)
				get_viewport().set_input_as_handled()
			if event.index == _stick_id:
				_stick_id = -1
				_set_vec(Vector2.ZERO)
				get_viewport().set_input_as_handled()
		_pad.queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_id:
		_stick_pos = event.position
		var radius := 80.0 * _last_layout.y / 720.0
		var d: Vector2 = _stick_pos - _stick_origin
		if d.length() > radius * 1.5:
			_stick_origin = _stick_pos - d.normalized() * radius * 1.5
		_set_vec((_stick_pos - _stick_origin) / radius)
		get_viewport().set_input_as_handled()
		_pad.queue_redraw()


func _process(_dt: float) -> void:
	if not active:
		return
	if not _gameplay() and (_stick_id >= 0 or not _held.is_empty()):
		_release_all()
	_pad.queue_redraw()


func _release_all() -> void:
	_stick_id = -1
	_set_vec(Vector2.ZERO)
	for i in _held:
		_send(_held[i], false)
	_held.clear()


func _set_vec(v: Vector2) -> void:
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < DEAD:
		v = Vector2.ZERO
	_axis("move_left", "move_right", v.x)
	_axis("move_up", "move_down", v.y)


func _axis(neg: String, pos: String, x: float) -> void:
	if x < 0:
		Input.action_press(neg, -x)
		Input.action_release(pos)
	elif x > 0:
		Input.action_press(pos, x)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _send(action: String, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	ev.strength = 1.0 if down else 0.0
	Input.parse_input_event(ev)


func _draw_pad() -> void:
	if not active or not _gameplay():
		return
	_layout()
	var u := _last_layout.y / 720.0
	var ink := Color(G.INK, 0.55)
	if _stick_id >= 0:
		var r := 80.0 * u
		_pad.draw_circle(_stick_origin, r * 1.15, Color(G.INK, 0.35))
		_pad.draw_arc(_stick_origin, r * 1.15, 0, TAU, 40, Color(1, 1, 1, 0.55), 4.0 * u)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(r)
		_pad.draw_circle(knob + Vector2(4, 4) * u, 40 * u, ink)
		_pad.draw_circle(knob, 40 * u, Color(G.PAPER, 0.85))
		_pad.draw_arc(knob, 40 * u, 0, TAU, 32, G.INK, 5.0 * u)
	elif G.game_time < 20.0:
		var hint := Vector2(200 * u, _last_layout.y - 190 * u)
		_pad.draw_arc(hint, 80 * u, 0, TAU, 40, Color(1, 1, 1, 0.3), 3.0 * u)
		_pad.draw_circle(hint, 34 * u, Color(1, 1, 1, 0.2))
		_draw_label(hint + Vector2(0, 125 * u), "左侧拖动 移动", int(26 * u), G.WHITE)
	var p = G.player
	for b in _buttons:
		var pressed: bool = _held.values().has(b.action)
		var c: Color = b.color
		var r: float = b.r * (0.92 if pressed else 1.0)
		_pad.draw_circle(b.pos + Vector2(6, 6) * u, r, ink)
		_pad.draw_circle(b.pos, r, Color(c, 0.95 if pressed else 0.78))
		_pad.draw_arc(b.pos, r, 0, TAU, 40, G.INK, 6.0 * u)
		var cd := 0.0
		if p != null:
			if b.action == "dash":
				cd = clampf(p.dash_cd / maxf(p.dash_cd_max, 0.01), 0.0, 1.0)
			elif b.action == "heavy":
				cd = clampf(p.heavy_cd / 1.1, 0.0, 1.0)
		if cd > 0.0:
			_pad.draw_circle(b.pos, r - 6 * u, Color(G.INK, 0.45))
			_pad.draw_arc(b.pos, r - 8 * u, -PI / 2, -PI / 2 + TAU * cd, 32, G.WHITE, 6.0 * u)
		_draw_label(b.pos + Vector2(0, r * 0.18), b.label, int(maxf(14.0, r * 0.45)), G.INK if cd <= 0.0 else G.WHITE)


func _draw_label(pos: Vector2, s: String, fs: int, col: Color) -> void:
	var tw := G.font_cn.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_pad.draw_string(G.font_cn, pos - Vector2(tw * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
