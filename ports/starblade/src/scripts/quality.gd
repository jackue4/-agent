extends RefCounted
## Device quality tier. Mobile and web builds default to "low": no post pass,
## shadows, glow, point lights or screen readback; fewer particles.
static var _low := -1
static var touch_active := false
static var _font: Font

static func low() -> bool:
	if _low < 0:
		_low = 1 if (OS.has_feature("mobile") or OS.has_feature("web")) else 0
	return _low == 1

static func set_low(value: bool) -> void:
	_low = 1 if value else 0

static func font() -> Font:
	if _font == null:
		var f = load("res://addons/ugc/font.ttf") if ResourceLoader.exists("res://addons/ugc/font.ttf") else null
		_font = f if f is Font else ThemeDB.fallback_font
	return _font
