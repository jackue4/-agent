extends Control
## On-screen controls for touch devices. Left half: floating virtual stick that drives the
## move_* actions; right side: round buttons for jump / action. Everything goes through the
## InputMap, so gameplay code never needs to know input came from touch.
## Shown only when a touchscreen is present (or forced with --touch for testing).

const STICK_RADIUS := 84.0
const DEADZONE := 0.25
const BTN_RADIUS := 62.0

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_touch := {}  # touch index -> action
var buttons: Array = []  # [{action, label, center}]
var horizontal_only := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# keep stick touches from also acting as mouse drags (3D orbit / editor drag)
	Input.emulate_mouse_from_touch = false

## mode: "platformer" (left/right + jump), "topdown" (8-way), "3d" (8-way + jump).
func configure(mode: String, can_shoot: bool) -> void:
	horizontal_only = mode == "platformer"
	buttons.clear()
	if mode != "topdown":
		buttons.append({"action": "jump", "label": "跳"})
	if can_shoot:
		buttons.append({"action": "action", "label": "射"})
	_layout()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

func _layout() -> void:
	var s := size
	for i in buttons.size():
		buttons[i]["center"] = Vector2(s.x - 110 - i * 150, s.y - 120 - i * 40)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			for b in buttons:
				if t.position.distance_to(b["center"]) < BTN_RADIUS * 1.25:
					_btn_touch[t.index] = b["action"]
					Input.action_press(b["action"])
					queue_redraw()
					return
			if t.position.x < size.x * 0.5 and _stick_touch == -1:
				_stick_touch = t.index
				_stick_origin = t.position
				_stick_pos = t.position
				queue_redraw()
		else:
			if _btn_touch.has(t.index):
				Input.action_release(_btn_touch[t.index])
				_btn_touch.erase(t.index)
				queue_redraw()
			elif t.index == _stick_touch:
				_stick_touch = -1
				_apply_stick(Vector2.ZERO)
				queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			var off := (d.position - _stick_origin).limit_length(STICK_RADIUS)
			_stick_pos = _stick_origin + off
			_apply_stick(off / STICK_RADIUS)
			queue_redraw()

func _apply_stick(v: Vector2) -> void:
	_axis("move_left", "move_right", v.x)
	if horizontal_only:
		_axis("move_up", "move_down", 0.0)
	else:
		_axis("move_up", "move_down", v.y)

func _axis(neg: String, pos: String, x: float) -> void:
	if x < -DEADZONE:
		Input.action_press(neg, clampf(-x, 0.0, 1.0))
		Input.action_release(pos)
	elif x > DEADZONE:
		Input.action_press(pos, clampf(x, 0.0, 1.0))
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)

func release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "action"]:
		Input.action_release(a)
	_btn_touch.clear()
	_stick_touch = -1
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	# stick: show a hint ring bottom-left when idle, the live stick when touched
	var base := _stick_origin if _stick_touch != -1 else Vector2(150, size.y - 140)
	var knob := _stick_pos if _stick_touch != -1 else base
	var a := 0.55 if _stick_touch != -1 else 0.3
	draw_circle(base, STICK_RADIUS, Color(1, 1, 1, a * 0.35))
	draw_arc(base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, a), 3.0, true)
	draw_circle(knob, 36, Color(1, 1, 1, a + 0.2))
	for b in buttons:
		var pressed: bool = b["action"] in _btn_touch.values()
		var c: Vector2 = b["center"]
		draw_circle(c, BTN_RADIUS, Color(0.6, 0.45, 1.0, 0.75 if pressed else 0.45))
		draw_arc(c, BTN_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.8), 3.0, true)
		var fs := 34
		var ts := font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-ts.x * 0.5, ts.y * 0.3), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
