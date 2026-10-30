extends RefCounted
## Shared helpers for reading loosely-typed JSON specs produced by the AI.

static func col(v, def: Color) -> Color:
	if typeof(v) == TYPE_STRING and v != "":
		return Color.from_string(v, def)
	return def

static func v2(v, def: Vector2) -> Vector2:
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if typeof(v) == TYPE_DICTIONARY:
		return Vector2(float(v.get("x", def.x)), float(v.get("y", def.y)))
	return def

static func v3(v, def: Vector3) -> Vector3:
	if typeof(v) == TYPE_ARRAY and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if typeof(v) == TYPE_ARRAY and v.size() == 2:
		return Vector3(float(v[0]), def.y, float(v[1]))
	if typeof(v) == TYPE_DICTIONARY:
		return Vector3(float(v.get("x", def.x)), float(v.get("y", def.y)), float(v.get("z", def.z)))
	return def

static func num(d, k: String, def: float) -> float:
	if typeof(d) != TYPE_DICTIONARY:
		return def
	var x = d.get(k, def)
	if typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT:
		return float(x)
	if typeof(x) == TYPE_STRING and x.is_valid_float():
		return x.to_float()
	return def

static func str_of(d, k: String, def: String) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return def
	var x = d.get(k, def)
	if x == null:
		return def
	return str(x)

## Strips emoji / symbols outside the Basic Multilingual Plane and variation selectors: the
## bundled font has no colour-emoji glyphs and Web builds have no system fallback (tofu boxes).
static func clean_text(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c > 0xFFFF or (c >= 0xFE00 and c <= 0xFE0F) or c == 0x200D or (c >= 0x2600 and c <= 0x27BF):
			continue
		out += char(c)
	return out.strip_edges()

## Shared surface theme for platforms in both dimensions. `world.theme` is canonical;
## `world.platform_style` is accepted as an alias. Empty means "infer from colour".
static func world_theme(spec: Dictionary) -> String:
	var w = spec.get("world", {})
	var t := str_of(w, "theme", "")
	return t if t != "" else str_of(w, "platform_style", "")

static func dict_of(d, k: String) -> Dictionary:
	if typeof(d) == TYPE_DICTIONARY and typeof(d.get(k)) == TYPE_DICTIONARY:
		return d[k]
	return {}

static func default_size_2d(kind: String) -> Vector2:
	match kind:
		"platform": return Vector2(220, 36)
		"collectible": return Vector2(44, 44)
		"enemy": return Vector2(60, 60)
		"hazard": return Vector2(96, 36)
		"goal": return Vector2(72, 120)
		"powerup": return Vector2(52, 52)
		"bouncer": return Vector2(72, 32)
		"sign": return Vector2(160, 80)
		"checkpoint": return Vector2(56, 110)
		"text": return Vector2(300, 60)
		"player": return Vector2(64, 64)
		"projectile": return Vector2(18, 18)
	return Vector2(110, 110)

static func default_size_3d(kind: String) -> Vector3:
	match kind:
		"platform": return Vector3(4, 0.6, 4)
		"collectible": return Vector3(0.8, 0.8, 0.8)
		"enemy": return Vector3(1.1, 1.1, 1.1)
		"hazard": return Vector3(2.5, 0.4, 2.5)
		"goal": return Vector3(1.4, 3.2, 1.4)
		"powerup": return Vector3(0.9, 0.9, 0.9)
		"bouncer": return Vector3(1.8, 0.4, 1.8)
		"sign": return Vector3(2.4, 1.4, 0.2)
		"checkpoint": return Vector3(1, 2.2, 1)
		"player": return Vector3(0.9, 1.7, 0.9)
		"projectile": return Vector3(0.3, 0.3, 0.3)
	return Vector3(2, 2.5, 2)

static func default_color(kind: String) -> Color:
	match kind:
		"platform": return Color("#7cc44f")
		"collectible": return Color("#ffd23f")
		"enemy": return Color("#ef476f")
		"hazard": return Color("#b8c0cc")
		"goal": return Color("#ff6b6b")
		"powerup": return Color("#9b5de5")
		"bouncer": return Color("#ff4d6d")
		"sign": return Color("#c08552")
		"text": return Color("#ffffff")
		"player": return Color("#4cc9f0")
		"checkpoint": return Color("#4cc9f0")
	return Color("#57cc99")

static func kind_label(kind: String) -> String:
	match kind:
		"platform": return "平台"
		"collectible": return "收集物"
		"enemy": return "敌人"
		"hazard": return "陷阱"
		"goal": return "终点"
		"powerup": return "道具"
		"bouncer": return "弹簧"
		"sign": return "告示牌"
		"text": return "文字"
		"decor": return "装饰"
		"checkpoint": return "检查点"
	return kind
