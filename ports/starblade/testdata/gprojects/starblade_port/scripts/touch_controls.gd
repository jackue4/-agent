extends CanvasLayer
## Mobile touch layer: floating joystick (left half) + action buttons (right).
## Drives the same InputMap actions as the keyboard, so gameplay code is shared.
## Activates on mobile/web-mobile builds, or on the first real touch event.
const Quality = preload("res://scripts/quality.gd")
const DEAD := 0.18

var g
var active := false
var _pad: Control
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _vec := Vector2.ZERO
var _held := {}            ## touch index -> action
var _buttons: Array = []   ## [{action, pos, r, label, color, hold}]
var _last_layout := Vector2.ZERO
var _dirty := true

func bind(game) -> void:
	g = game

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pad = Control.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		activate()
	else:
		visible = false

func activate() -> void:
	if active: return
	active = true
	visible = true
	Quality.touch_active = true
	# Emulated mouse clicks must not fire attacks; touch buttons own combat input.
	for act in ["melee","special"]:
		for ev in InputMap.action_get_events(act):
			if ev is InputEventMouseButton: InputMap.action_erase_event(act, ev)
	if g != null and g.has_method("push_ui"): g.push_ui()

func _gameplay() -> bool:
	if g == null: return false
	return (g.mode == "raid") or (g.mode == "hub" and str(g.hub_station).is_empty())

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	if s == _last_layout and not _dirty: return
	_last_layout = s; _dirty = false
	var u := minf(s.x/1280.0, s.y/720.0)
	var base := Vector2(s.x - 150*u, s.y - 130*u)
	_buttons = [
		{"action":"melee","pos":base,"r":66*u,"label":"攻击","color":Color("fff0c9"),"hold":true},
		{"action":"dash","pos":base+Vector2(-155,25)*u,"r":44*u,"label":"冲刺","color":Color("62e5eb"),"hold":false,"tile":"dash"},
		{"action":"special","pos":base+Vector2(-120,-110)*u,"r":40*u,"label":"投掷","color":Color("b8afff"),"hold":true,"tile":"special"},
		{"action":"hero_primary","pos":base+Vector2(-10,-172)*u,"r":40*u,"label":"技能","color":Color("ffd36b"),"hold":false,"tile":"primary"},
		{"action":"hero_secondary","pos":base+Vector2(96,-126)*u,"r":36*u,"label":"绝技","color":Color("ff7a9c"),"hold":false,"tile":"secondary"},
		{"action":"interact","pos":base+Vector2(-262,-40)*u,"r":36*u,"label":"交互","color":Color("ff9e50"),"hold":false},
		{"action":"bag","pos":Vector2(s.x-150*u,44*u),"r":28*u,"label":"背包","color":Color("c9d6de"),"hold":false},
		{"action":"pause","pos":Vector2(s.x-76*u,44*u),"r":28*u,"label":"暂停","color":Color("c9d6de"),"hold":false},
	]

func _shown(b: Dictionary) -> bool:
	if g == null: return false
	var a: String = b.action
	if a == "pause": return g.mode in ["raid","hub"] and str(g.hub_station).is_empty() or g.mode == "pause"
	if not _gameplay(): return false
	if g.mode == "hub": return a in ["dash","interact"]
	match a:
		"special": return g.weapon_family() != "flying"
		"interact": return not str(g.prompt).is_empty()
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not active: activate()
	else:
		return
	_layout()
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			for b in _buttons:
				if _shown(b) and pos.distance_to(b.pos) <= b.r*1.25:
					_held[event.index] = b.action
					_send(b.action, true)
					if not b.hold: _send(b.action, false)
					get_viewport().set_input_as_handled()
					_pad.queue_redraw()
					return
			if _gameplay() and _stick_id < 0 and pos.x < get_viewport().get_visible_rect().size.x*0.5:
				_stick_id = event.index
				_stick_origin = pos; _stick_pos = pos
				_set_vec(Vector2.ZERO)
				get_viewport().set_input_as_handled()
		else:
			if _held.has(event.index):
				var a: String = _held[event.index]
				_held.erase(event.index)
				for b in _buttons:
					if b.action == a and b.hold: _send(a, false)
				get_viewport().set_input_as_handled()
			if event.index == _stick_id:
				_stick_id = -1
				_set_vec(Vector2.ZERO)
				get_viewport().set_input_as_handled()
		_pad.queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_id:
		_stick_pos = event.position
		var u := minf(_last_layout.x/1280.0, _last_layout.y/720.0)
		var radius := 70.0*u
		var d: Vector2 = _stick_pos - _stick_origin
		if d.length() > radius*1.6: _stick_origin = _stick_pos - d.normalized()*radius*1.6
		_set_vec((_stick_pos - _stick_origin)/radius)
		get_viewport().set_input_as_handled()
		_pad.queue_redraw()

func _set_vec(v: Vector2) -> void:
	if v.length() > 1.0: v = v.normalized()
	if v.length() < DEAD: v = Vector2.ZERO
	_vec = v
	_axis("left","right",v.x)
	_axis("up","down",v.y)

func _axis(neg: String, pos: String, x: float) -> void:
	if x < 0: Input.action_press(neg, -x); Input.action_release(pos)
	elif x > 0: Input.action_press(pos, x); Input.action_release(neg)
	else: Input.action_release(neg); Input.action_release(pos)

func _send(action: String, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	ev.strength = 1.0 if down else 0.0
	Input.parse_input_event(ev)

func release_all() -> void:
	for idx in _held.keys():
		_send(str(_held[idx]), false)
	_held.clear()
	_stick_id = -1
	_set_vec(Vector2.ZERO)

var _was_gameplay := false
var _redraw_t := 0.0
func _process(delta: float) -> void:
	if not active: return
	var gp := _gameplay()
	if gp != _was_gameplay:
		_was_gameplay = gp
		if not gp: release_all()
		_pad.queue_redraw()
	# Original desktop tiles for melee/special/dash are replaced by touch buttons.
	if g != null and g.ui != null:
		for id in ["melee","special","dash","primary","secondary"]:
			var t = g.ui.refs.get("tile_"+id)
			if t is Control and is_instance_valid(t) and t.visible: t.visible = false
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.1   # cooldown/prompt visuals at 10 Hz, input redraws immediately
		_pad.queue_redraw()

func _draw_pad() -> void:
	if not active or g == null: return
	_layout()
	var font: Font = Quality.font()
	var u := minf(_last_layout.x/1280.0, _last_layout.y/720.0)
	if _gameplay():
		if _stick_id >= 0:
			_pad.draw_circle(_stick_origin, 70*u, Color(1,1,1,.08))
			_pad.draw_arc(_stick_origin, 70*u, 0, TAU, 40, Color(1,1,1,.35), 2.0*u)
			_pad.draw_circle(_stick_origin+_vec*70*u, 30*u, Color(1,1,1,.45))
		else:
			var hint := Vector2(160*u, _last_layout.y-200*u)
			_pad.draw_arc(hint, 70*u, 0, TAU, 40, Color(1,1,1,.14), 2.0*u)
			_pad.draw_circle(hint, 26*u, Color(1,1,1,.12))
	for b in _buttons:
		if not _shown(b): continue
		var pressed: bool = _held.values().has(b.action)
		var c: Color = b.color
		var cd := 0.0
		var cd_max := 1.0
		if b.has("tile") and g.ui != null:
			var t = g.ui.refs.get("tile_"+str(b.tile))
			if t != null and is_instance_valid(t): cd = float(t.cooldown); cd_max = maxf(.01,float(t.duration))
		_pad.draw_circle(b.pos, b.r, Color(.02,.05,.08,.62 if not pressed else .85))
		_pad.draw_arc(b.pos, b.r, 0, TAU, 40, Color(c, .9 if pressed else .6), 3.0*u)
		if cd > 0.0:
			_pad.draw_arc(b.pos, b.r-5*u, -PI/2, -PI/2+TAU*clampf(cd/cd_max,0,1), 32, Color(c,.35), 6.0*u)
		var fs := int(maxf(12, b.r*0.42))
		var tw := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_pad.draw_string(font, b.pos+Vector2(-tw*.5, fs*.35), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(c, .95))
