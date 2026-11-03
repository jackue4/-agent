class_name Art
extends RefCounted
## Loads the hand-drawn comic sprites from res://art and caches derived data
## (white flash silhouettes, opaque hull polygons used for texture-mapped shattering).

static var _tex := {}
static var _flash := {}
static var _hull := {}

## Per-sprite config: draw height in units of the entity radius, whether the source faces left.
const SPRITES := {
	"enemy_blob": {"h": 2.7, "flip": false},
	"enemy_imp": {"h": 3.3, "flip": false},
	"enemy_bat": {"h": 2.9, "flip": false},
	"enemy_spitter": {"h": 3.1, "flip": false},
	"enemy_brute": {"h": 3.3, "flip": false},
	"enemy_boss": {"h": 3.5, "flip": false},
	"prop_crate": {"h": 2.3, "flip": false},
	"prop_barrel": {"h": 2.7, "flip": false},
	"prop_rock": {"h": 1.9, "flip": false},
	"prop_hydrant": {"h": 3.3, "flip": false},
	"enemy_slimeking": {"h": 2.6, "flip": false},
	"enemy_batqueen": {"h": 3.4, "flip": false},
	"enemy_reaper": {"h": 4.2, "flip": false},
	"prop_bamboo": {"h": 3.6, "flip": false},
	"prop_obsidian": {"h": 2.4, "flip": false},
	"prop_icecrystal": {"h": 2.6, "flip": false},
}


static func tex(id: String) -> Texture2D:
	if _tex.has(id):
		return _tex[id]
	var path := "res://art/" + id + ".png"
	if id == "title_splash_tex":
		path = "res://art/title_splash.jpg"
	elif not ResourceLoader.exists(path) and ResourceLoader.exists("res://art/" + id + ".jpg"):
		path = "res://art/" + id + ".jpg"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex[id] = t
	return t


static func icon(id: String) -> Texture2D:
	return tex("icons/" + id)


static func flash(id: String) -> Texture2D:
	if not _flash.has(id):
		_flash[id] = tex(id + "_flash")
	return _flash[id]


## Convex hull of opaque pixels in texture pixel space (used as the shatter outline).
static var _hull_db := {}


static func hull(id: String) -> PackedVector2Array:
	if _hull.has(id):
		return _hull[id]
	if _hull_db.is_empty() and FileAccess.file_exists("res://art/hulls.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://art/hulls.json"))
		if j is Dictionary:
			_hull_db = j
	var out := PackedVector2Array()
	for p in _hull_db.get(id, []):
		out.append(Vector2(p[0], p[1]))
	_hull[id] = out
	return out


## Warm caches up front so the first kill never hitches.
static func preload_all() -> void:
	for id in SPRITES:
		tex(id)
		flash(id)
		hull(id)
	for id in ["pickup_gem", "pickup_heart", "ground", "title_splash_tex", "dojo_bg", "ground_bamboo", "ground_volcano", "ground_ice"]:
		tex(id)


static func has(id: String) -> bool:
	return tex(id) != null


## Local transform that maps texture pixels -> entity-local drawing space (feet at origin).
static func local_xf(id: String, radius: float, facing: float) -> Transform2D:
	var t := tex(id)
	var cfg: Dictionary = SPRITES.get(id, {"h": 3.0, "flip": false})
	var s := radius * float(cfg["h"]) / float(t.get_height())
	var fx := facing * (-1.0 if cfg["flip"] else 1.0)
	# pixel (px,py) -> ((px - w/2) * s * fx, (py - h) * s)
	return Transform2D(Vector2(s * fx, 0), Vector2(0, s), Vector2(-t.get_width() * 0.5 * s * fx, -t.get_height() * s))


## Draws sprite with the given entity-local transform already applied by caller (draw_set_transform).
static func draw(ci: CanvasItem, id: String, radius: float, facing: float, modulate: Color = Color.WHITE, flash_a: float = 0.0) -> void:
	var t := tex(id)
	var xf := local_xf(id, radius, facing)
	var rect := Rect2(Vector2.ZERO, t.get_size())
	ci.draw_set_transform_matrix(ci.get_meta("_xf", Transform2D.IDENTITY) * xf)
	ci.draw_texture_rect(t, rect, false, modulate)
	if flash_a > 0.0:
		var f := flash(id)
		if f != null:
			ci.draw_texture_rect(f, rect, false, Color(1, 1, 1, flash_a))
	ci.draw_set_transform_matrix(ci.get_meta("_xf", Transform2D.IDENTITY))


## World-space shatter polygon + world->uv transform for a sprite drawn with entity_xf * local_xf.
static func shatter_data(id: String, entity_xf: Transform2D, radius: float, facing: float) -> Array:
	var t := tex(id)
	var full := entity_xf * local_xf(id, radius, facing)
	var world := PackedVector2Array()
	for p in hull(id):
		world.append(full * p)
	var to_uv := Transform2D(Vector2(1.0 / t.get_width(), 0), Vector2(0, 1.0 / t.get_height()), Vector2.ZERO) * full.affine_inverse()
	return [world, to_uv]