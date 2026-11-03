extends CanvasLayer
const FlatPoly = preload("res://scripts/flat_poly.gd")

signal action(name: String, value: Variant)
signal card_landed(quality: int)

const INK := Color("08141f")
const PANEL := Color(0.031, 0.069, 0.098, 0.94)
const LINE := Color("274453")
const WHITE := Color("e6f0ed")
const MUTED := Color("8aadb8")
const CYAN := Color("73eceb")
const ORANGE := Color("f5ac61")
const RED := Color("ff6b62")
const Heroes := preload("res://scripts/heroes.gd")
const TalentTreeUI := preload("res://scripts/talent_tree_ui.gd")
const BoonCardArt := preload("res://scripts/boon_card_art.gd")
const DungeonMap := preload("res://scripts/dungeon_map.gd")

var state: Dictionary = {}
var canvas: Control
var scene_ui: Control
var refs: Dictionary = {}
var current_mode := ""
var signature := ""
var selected_item := -1
var map_expanded := false
var warehouse_open := false
var ui_font: Font
var motion_clock := 0.0
var result_started := 0.0
var hero_tab := "roster"
var talent_selection: Dictionary = {}
var receipt_seen := 0
var rendered_surface := ""
var _panel_parts: Array[Control] = []
var _retiring: Array[Control] = []
var _boss_key := ""
var _boss_armor_capacity := 0.0
const ROOM_CAPTION_X := 470.0
const ROOM_CAPTION_HOLD := 1.6
var _combo_shown := 0
var _combo_pop := 0.0
var _combo_tilt := 0.0
var _combo_shake := 0.0
var _combo_burst := 0.0
var _combo_tier := 0
var _combo_sparks: Array = []
var _choice_busy := false
var _choice_generation := 0

class CardDissolve extends Control:
	var snapshot: Texture2D
	var accent := Color("73eceb")
	var age := 0.0
	const LIFETIME := .58
	const COLS := 11
	const ROWS := 18
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)
	func _process(delta: float) -> void:
		age += delta
		queue_redraw()
		if age >= LIFETIME: queue_free()
	func _draw() -> void:
		var tile := Vector2(size.x/COLS,size.y/ROWS)
		var source_size := snapshot.get_size() if snapshot != null else size
		var source_tile := Vector2(source_size.x/COLS,source_size.y/ROWS)
		for row in ROWS:
			for col in COLS:
				var seed := float((row*31+col*17)%13)/13.0
				var delay := .035+float(row)/ROWS*.15+seed*.055
				var t := clampf((age-delay)/maxf(.001,LIFETIME-delay),0,1)
				var drift := Vector2((col-(COLS-1)*.5)*t*3.2+(seed-.5)*t*34.0,-t*t*(35.0+seed*80.0)+t*row*1.5)
				var destination := Rect2(Vector2(col,row)*tile+drift,tile+Vector2.ONE)
				var alpha := 1.0-pow(t,1.6)
				if snapshot != null:
					draw_texture_rect_region(snapshot,destination,Rect2(Vector2(col,row)*source_tile,source_tile),Color(1,1,1,alpha))
				else:
					draw_rect(destination,Color(accent,alpha))


class CutPanel extends Control:
	var fill := Color(0.025, 0.055, 0.075, 0.96)
	var edge := Color("274453")
	var accent := Color.TRANSPARENT
	var cut := 18.0
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var p := PackedVector2Array([Vector2(cut, 0), Vector2(w, 0), Vector2(w - cut, h), Vector2(0, h)])
		if fill.a > .6:
			var shadow := PackedVector2Array()
			for point in p: shadow.append(point+Vector2(0,6))
			draw_colored_polygon(shadow,Color(0,0,0,.22))
		draw_polygon(p,PackedColorArray([fill.lightened(.045),fill.lightened(.02),fill.darkened(.12),fill.darkened(.04)]))
		draw_polyline(p + PackedVector2Array([p[0]]), edge, 1.0, true)
		draw_line(Vector2(cut+3,5),Vector2(w-8,5),Color(WHITE,.055),1,true)
		if accent.a > 0:
			draw_colored_polygon(PackedVector2Array([Vector2(cut, 0), Vector2(w, 0), Vector2(w - 0.6, 3), Vector2(cut - 0.6, 3)]), accent)


class SlashMeter extends Control:
	var ratio := 1.0
	var trail := 1.0
	var tint := Color("f4f4e9")
	var segments := 10
	var gap := 5.0
	var skew := 7.0
	func shape(x: float, width: float, f: float = 1.0) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x + skew, 0), Vector2(x + skew + (width - skew) * f, 0), Vector2(x + (width - skew) * f, size.y), Vector2(x, size.y)])
	func _draw() -> void:
		var width := (size.x - (segments - 1) * gap) / segments
		for i in range(segments):
			var x := i * (width + gap)
			draw_colored_polygon(shape(x, width), Color(0.16, 0.23, 0.27, 0.78))
			var lag := clampf(trail * segments - i, 0, 1)
			var filled := clampf(ratio * segments - i, 0, 1)
			if lag > filled and lag > 0:
				draw_colored_polygon(shape(x, width, lag), Color("e36f65"))
			if filled > 0:
				draw_colored_polygon(shape(x, width, filled), tint)


class BossMeter extends Control:
	var hp_fraction := 1.0
	var armor_fraction := 0.0
	var total := 1.0
	var maximum := 1.0
	func set_values(hp: float,max_hp: float,armor: float,max_armor: float) -> void:
		maximum = maxf(1,maxf(0,max_hp)+maxf(0,max_armor))
		var body := clampf(hp,0,maxf(0,max_hp))
		var plating := clampf(armor,0,maxf(0,max_armor))
		total = body+plating
		hp_fraction = body/maximum
		armor_fraction = plating/maximum
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("283038"))
		if hp_fraction > 0: draw_rect(Rect2(0,0,size.x*hp_fraction,size.y),Color("f59c68"))
		if armor_fraction > 0: draw_rect(Rect2(size.x*hp_fraction,0,size.x*armor_fraction,size.y),Color("9edbe8"))
		for i in range(1,3): draw_line(Vector2(size.x*i/3.0,0),Vector2(size.x*i/3.0,size.y),Color(0,0,0,.55),1)
		draw_line(Vector2.ZERO,Vector2(size.x*(hp_fraction+armor_fraction),0),Color(1,.94,.84,.5),1)


class DamageVeil extends Control:
	var flash := 0.0
	var reduced := false
	func _draw() -> void:
		if flash <= 0.001:
			return
		var alpha := clampf(flash, 0, 1) * (0.08 if reduced else 0.26)
		var hot := Color(0.86, 0.13, 0.12, alpha)
		var clear := Color(0.86, 0.13, 0.12, 0)
		var w := size.x
		var h := size.y
		var edge := 115.0
		draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(w,0),Vector2(w,edge),Vector2(0,edge)]),PackedColorArray([hot,hot,clear,clear]))
		draw_polygon(PackedVector2Array([Vector2(0,h),Vector2(w,h),Vector2(w,h-edge),Vector2(0,h-edge)]),PackedColorArray([hot,hot,clear,clear]))
		draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(0,h),Vector2(edge,h),Vector2(edge,0)]),PackedColorArray([hot,hot,clear,clear]))
		draw_polygon(PackedVector2Array([Vector2(w,0),Vector2(w,h),Vector2(w-edge,h),Vector2(w-edge,0)]),PackedColorArray([hot,hot,clear,clear]))


class AbilityTile extends Control:
	signal activated
	var tint := Color("73eceb")
	var cooldown := 0.0
	var duration := 1.0
	var hover := 0.0
	var hovered := false
	var clock := 0.0
	var reduced := false
	var progress := 0.0
	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): hovered = true)
		mouse_exited.connect(func(): hovered = false)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			activated.emit()
			accept_event()
	func _process(delta: float) -> void:
		clock += delta
		hover = lerpf(hover, 1.0 if hovered else 0.0, minf(delta * 14, 1))
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var p := PackedVector2Array([Vector2(15,0),Vector2(w,0),Vector2(w-15,h),Vector2(0,h)])
		draw_colored_polygon(p, Color(0.012 + hover * 0.035,0.026 + hover * 0.04,0.038 + hover * 0.05,0.96))
		draw_polyline(p + PackedVector2Array([p[0]]), tint.darkened(0.72 - hover * 0.45), 1.2, true)
		draw_colored_polygon(PackedVector2Array([Vector2(15,0),Vector2(w,0),Vector2(w-.5,3),Vector2(14.5,3)]),tint)
		if cooldown > 0.0:
			var f := clampf(cooldown / maxf(duration,0.01),0,1)
			var y := h * (1-f)
			draw_colored_polygon(PackedVector2Array([Vector2(15*(1-y/h),y),Vector2(w-15*y/h,y),Vector2(w-15,h),Vector2(0,h)]),Color(0.12,0.19,0.22,0.65))
		elif not reduced:
			var x := fposmod(clock*35, w)
			draw_line(Vector2(maxf(15,x-16),1),Vector2(maxf(15,x),1),Color(0.9,1,1,0.7),2)
		for i in range(3):
			draw_line(Vector2(w-28-i*5,h-11),Vector2(w-24-i*5,h-20),Color(tint,0.22 + hover*.18),1)
		if progress > 0.0:
			draw_line(Vector2(9,h-3),Vector2(9+(w-33)*clampf(progress,0,1),h-3),tint,3)


class CardArt extends Control:
	var tint := Color("73eceb")
	var clock := 0.0
	var reduced := false
	func _process(delta: float) -> void:
		if not reduced:
			clock += delta
			queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in range(4):
			var x := 12.0 + i * 64
			draw_colored_polygon(PackedVector2Array([Vector2(x+45,0),Vector2(x+76,0),Vector2(x+22,h),Vector2(x-9,h)]),Color(tint,0.05 + i * .022))
		draw_arc(Vector2(w*.55,h*.5),h*.4,-.8,2.2,24,Color(tint,.35),1.5,true)
		draw_line(Vector2(15,h-10),Vector2(w-20,8),Color(tint,.55),1.0,true)
		var x := fposmod(clock * 53,w + 70)-35
		if not reduced:
			draw_line(Vector2(x,h),Vector2(x+42,0),Color(tint,.3),2,true)


class HeroPortrait extends Control:
	var hero_id := "chrono"
	var tint := Color("73eceb")
	func cube(at: Vector2, width: float, height: float, color: Color) -> void:
		var dx := width*.32
		var dy := width*.18
		var front := PackedVector2Array([at+Vector2(-width*.5,-height*.5),at+Vector2(width*.5,-height*.5),at+Vector2(width*.5,height*.5),at+Vector2(-width*.5,height*.5)])
		var top := PackedVector2Array([front[0],front[1],front[1]+Vector2(dx,-dy),front[0]+Vector2(dx,-dy)])
		var side := PackedVector2Array([front[1],front[2],front[2]+Vector2(dx,-dy),front[1]+Vector2(dx,-dy)])
		draw_colored_polygon(top,color.lightened(.32))
		draw_colored_polygon(side,color.darkened(.35))
		var face := StyleBoxFlat.new()
		face.bg_color = color
		face.set_corner_radius_all(7)
		face.set_border_width_all(1)
		face.border_color = Color(tint,.8)
		draw_style_box(face,Rect2(at-Vector2(width,height)*.5,Vector2(width,height)))
	func _draw() -> void:
		var c := size*.5
		draw_set_transform(c+Vector2(0,43),0,Vector2(1,.24))
		draw_arc(Vector2.ZERO,67,0,TAU,48,Color(tint,.25),1.2,true)
		draw_set_transform(Vector2.ZERO)
		draw_line(c+Vector2(-93,42),c+Vector2(98,42),Color(tint,.14),1)
		if hero_id == "chrono":
			draw_arc(c+Vector2(2,-6),48,-2.7,2.7,40,Color(tint,.6),1.6,true)
			for i in range(8):
				var d := Vector2.from_angle(i*TAU/8)
				draw_line(c+Vector2(2,-6)+d*44,c+Vector2(2,-6)+d*49,tint,1.5,true)
		elif hero_id == "ember":
			for direction in [-1,1]:
				draw_colored_polygon(PackedVector2Array([c+Vector2(direction*28,17),c+Vector2(direction*47,-32),c+Vector2(direction*56,-41),c+Vector2(direction*42,23)]),tint)
		else:
			for direction in [-1,1]:
				cube(c+Vector2(direction*59,-7),12,16,tint.darkened(.42))
				draw_arc(c+Vector2(direction*56,-7),23,-1.3,1.4,18,Color(tint,.6),1.3,true)
		cube(c+Vector2(-5,0),61,61,tint.darkened(.22))
		for x in [-18,4]:
			var eye := StyleBoxFlat.new()
			eye.bg_color = Color("f0fdff")
			eye.set_corner_radius_all(3)
			draw_style_box(eye,Rect2(c+Vector2(x,-10),Vector2(12,18)))
			draw_rect(Rect2(c+Vector2(x+4,-4),Vector2(5,9)),Color("132337"))


class Radar extends Control:

	var data: Dictionary = {}

	func project(p: Vector2) -> Vector2:
		var b: Rect2 = data.get("bounds", Rect2(-24, -28, 48, 52))
		return Vector2(12, 12) + (p - b.position) / b.size * (size - Vector2(24, 24))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.06, 0.085, 0.91))
		for i in range(1, 7):
			draw_line(Vector2(i * size.x / 7.0, 0), Vector2(i * size.x / 7.0, size.y), Color(0.18, 0.3, 0.34, 0.3))
			draw_line(Vector2(0, i * size.y / 7.0), Vector2(size.x, i * size.y / 7.0), Color(0.18, 0.3, 0.34, 0.3))
		draw_rect(Rect2(Vector2(12, 12), size - Vector2(24, 24)), Color("3d626e"), false, 1.0)
		for p in data.get("containers", []):
			if p is Vector2:
				draw_rect(Rect2(project(p) - Vector2(2, 2), Vector2(4, 4)), Color("d7a55a"))
		for p in data.get("enemies", []):
			if p is Vector2:
				draw_circle(project(p), 2.0, Color("ed766c"))
		for ex in data.get("extracts", []):
			var p: Vector2 = project(ex.get("pos", Vector2.ZERO))
			var c := Color("ffb262") if ex.get("locked", false) else Color("74eee2")
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), c, false, 1.5)
		if data.has("terminal"):
			var t := project(data.terminal)
			draw_colored_polygon(PackedVector2Array([t + Vector2(0, -4), t + Vector2(4, 0), t + Vector2(0, 4), t + Vector2(-4, 0)]), Color("d5abff"))
		var player: Vector2 = project(data.get("player", Vector2.ZERO))
		draw_circle(player, 7.0, Color(0.4, 0.95, 0.94, 0.12))
		draw_colored_polygon(PackedVector2Array([player + Vector2(0, -5), player + Vector2(4, 4), player + Vector2(0, 2), player + Vector2(-4, 4)]), Color("d4fffc"))


class BladePips extends Control:
	var total := 3
	var loaded := 3
	var tint := Color("62e5eb")
	func _draw() -> void:
		var n := maxi(1,total)
		var w := minf(26.0,(size.x-10)/n)
		var x0 := size.x*.5-w*n*.5
		for i in n:
			var cx := x0+w*(i+.5)
			var lit := i < loaded
			var c := tint if lit else Color(tint,.22)
			var pts := PackedVector2Array([Vector2(cx,4),Vector2(cx+4.5,12),Vector2(cx+2.4,size.y-7),Vector2(cx-2.4,size.y-7),Vector2(cx-4.5,12)])
			draw_colored_polygon(pts,c)
			draw_line(Vector2(cx-7,size.y-9),Vector2(cx+7,size.y-9),c,2.0,true)
			if lit: draw_polyline(PackedVector2Array([pts[0],pts[1],pts[2],pts[3],pts[4],pts[0]]),Color(1,1,1,.55),1.0,true)

class Glyph extends Control:

	var kind := "sword"
	var tint := Color("73eceb")

	func _draw() -> void:
		var c := size * 0.5
		var u := minf(size.x, size.y) / 46.0
		if kind == "slash":
			for i in range(3):
				var x := -16.0 + i*11
				draw_colored_polygon(PackedVector2Array([c+Vector2(x+14,-17)*u,c+Vector2(x+19,-18)*u,c+Vector2(x+3,14)*u,c+Vector2(x-1,17)*u]),tint)
		elif kind in ["spear", "throw"]:
			draw_line(c+Vector2(-16,17)*u,c+Vector2(11,-11)*u,tint,2.5*u,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(19,-20)*u,c+Vector2(15,-6)*u,c+Vector2(5,-15)*u]),tint)
			if kind == "throw":
				draw_arc(c+Vector2(-1,1)*u,18*u,.05,2.9,24,Color(tint,.7),1.5*u,true)
				draw_polyline(PackedVector2Array([c+Vector2(-18,3)*u,c+Vector2(-19,9)*u,c+Vector2(-12,8)*u]),tint,1.7*u,true)
		elif kind == "dash":
			for i in range(2):
				var x := -12.0+i*15
				draw_polyline(PackedVector2Array([c+Vector2(x-6,-13)*u,c+Vector2(x+7,0)*u,c+Vector2(x-6,13)*u]),tint,3*u,true)
		elif kind in ["time_stop","time_field","chrono_field"]:
			draw_arc(c,18*u,-PI*.65,PI*1.15,34,tint,1.8*u,true)
			draw_arc(c,13*u,-PI*.4,PI*.4,18,Color(tint,.4),1.5*u,true)
			draw_line(c+Vector2(-5,-8)*u,c+Vector2(-5,8)*u,tint,4*u,true)
			draw_line(c+Vector2(5,-8)*u,c+Vector2(5,8)*u,tint,4*u,true)
			for i in range(4):
				var a := i*PI*.5
				draw_line(c+Vector2.from_angle(a)*20*u,c+Vector2.from_angle(a)*23*u,tint,1.7*u,true)
		elif kind in ["rush","blade_rush"]:
			for i in range(3):
				var x := -18+i*12
				draw_colored_polygon(PackedVector2Array([c+Vector2(x+12,-18)*u,c+Vector2(x+17,-18)*u,c+Vector2(x-2,18)*u,c+Vector2(x-7,18)*u]),Color(tint,.4+i*.3))
			draw_line(c+Vector2(-22,3)*u,c+Vector2(20,3)*u,Color.WHITE,1.4*u,true)
		elif kind == "sky_slam":
			draw_line(c+Vector2(0,-20)*u,c+Vector2(0,7)*u,tint,3*u,true)
			draw_polyline(PackedVector2Array([c+Vector2(-9,-1)*u,c+Vector2(0,10)*u,c+Vector2(9,-1)*u]),tint,3*u,true)
			draw_arc(c+Vector2(0,12)*u,16*u,.1,PI-.1,20,tint,2*u,true)
			for direction in [-1,1]: draw_line(c+Vector2(direction*10,7)*u,c+Vector2(direction*20,-1)*u,Color(tint,.6),2*u,true)
		elif kind in ["rewind","backstep","phase_step","rewind_step"]:
			draw_arc(c,18*u,PI*.2,PI*1.9,32,tint,2*u,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(-20,-6)*u,c+Vector2(-9,-11)*u,c+Vector2(-13,1)*u]),tint)
			draw_line(c+Vector2(-7,2)*u,c+Vector2(8,2)*u,tint,2*u,true)
		elif kind in ["flame","flame_spin","fire_spin"]:
			draw_arc(c,19*u,.5,5.4,34,tint,2*u,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(0,-20)*u,c+Vector2(-11,-1)*u,c+Vector2(-9,12)*u,c+Vector2(0,19)*u,c+Vector2(12,9)*u,c+Vector2(8,-8)*u,c+Vector2(3,3)*u]),tint)
		elif kind in ["gravity","singularity","gravity_well"]:
			draw_circle(c,6*u,tint)
			for i in range(3):
				draw_arc(c,(11+i*5)*u,i*2.0,i*2.0+3.9,30,Color(tint,1.0-i*.2),1.8*u,true)
		elif kind in ["prism","prism_guard","reflect"]:
			var shield := PackedVector2Array([c+Vector2(0,-20)*u,c+Vector2(17,-12)*u,c+Vector2(13,10)*u,c+Vector2(0,20)*u,c+Vector2(-13,10)*u,c+Vector2(-17,-12)*u])
			draw_polyline(shield+PackedVector2Array([shield[0]]),tint,2*u,true)
			draw_polyline(PackedVector2Array([c+Vector2(-7,-8)*u,c+Vector2(6,0)*u,c+Vector2(-7,9)*u]),tint,2*u,true)
		elif kind == "pulse":
			draw_arc(c,16*u,0,TAU,32,tint,1.6*u,true)
			draw_arc(c,10*u,.2,4.2,24,Color(tint,.45),u,true)
			for i in range(3):
				var a := i*TAU/3-PI/2
				var p := c+Vector2(cos(a),sin(a))*16*u
				draw_colored_polygon(PackedVector2Array([p+Vector2(0,-5)*u,p+Vector2(3,0)*u,p+Vector2(0,6)*u,p+Vector2(-3,0)*u]),tint)
		elif kind in ["needle", "arc", "heavy", "sword"]:
			var thick := 3.0 if kind != "heavy" else 5.0
			var p := PackedVector2Array([c + Vector2(12, -18) * u, c + Vector2(8, -2) * u, c + Vector2(-5, 11) * u, c + Vector2(-10, 6) * u, c + Vector2(3, -7) * u])
			draw_colored_polygon(p, tint)
			draw_line(c + Vector2(-11, 3) * u, c + Vector2(-1, 13) * u, Color("dbe6e8"), thick * u)
			draw_line(c + Vector2(-7, 9) * u, c + Vector2(-15, 17) * u, tint, thick * u)
			if kind == "arc":
				draw_line(c + Vector2(-17, -12) * u, c + Vector2(-9, -17) * u, tint, 2.0 * u)
				draw_line(c + Vector2(-9, -17) * u, c + Vector2(-10, -7) * u, tint, 2.0 * u)
				draw_line(c + Vector2(-10, -7) * u, c + Vector2(-2, -11) * u, tint, 2.0 * u)
		elif kind == "medkit":
			draw_rect(Rect2(c - Vector2(14, 10) * u, Vector2(28, 23) * u), Color(0.1, 0.24, 0.24))
			draw_rect(Rect2(c - Vector2(4, 8) * u, Vector2(8, 20) * u), tint)
			draw_rect(Rect2(c - Vector2(10, 2) * u, Vector2(20, 8) * u), tint)
		elif kind in ["core", "relic", "cell"]:
			var p := PackedVector2Array([c + Vector2(0, -17) * u, c + Vector2(11, -7) * u, c + Vector2(11, 9) * u, c + Vector2(0, 17) * u, c + Vector2(-11, 9) * u, c + Vector2(-11, -7) * u])
			draw_colored_polygon(p, tint.darkened(0.4))
			draw_polyline(p + PackedVector2Array([p[0]]), tint, 1.5 * u)
			draw_line(c + Vector2(0, -10) * u, c + Vector2(0, 10) * u, tint, 4 * u)
		elif kind == "circuit":
			draw_rect(Rect2(c - Vector2(11, 11) * u, Vector2(22, 22) * u), tint.darkened(0.6))
			draw_rect(Rect2(c - Vector2(8, 8) * u, Vector2(16, 16) * u), tint, false, 2 * u)
			for n in [-1, 0, 1]:
				draw_line(c + Vector2(-16, n * 6) * u, c + Vector2(16, n * 6) * u, tint, u)
		elif kind == "key":
			draw_rect(Rect2(c - Vector2(14, 10) * u, Vector2(28, 20) * u), tint.darkened(0.45))
			draw_rect(Rect2(c - Vector2(9, 5) * u, Vector2(7, 7) * u), tint)
			draw_line(c + Vector2(2, 5) * u, c + Vector2(10, 5) * u, tint, 2 * u)
		elif kind == "armor":
			var p := PackedVector2Array([c + Vector2(-14, -13) * u, c + Vector2(0, -17) * u, c + Vector2(14, -13) * u, c + Vector2(12, 6) * u, c + Vector2(0, 18) * u, c + Vector2(-12, 6) * u])
			draw_colored_polygon(p, tint.darkened(0.55))
			draw_polyline(p + PackedVector2Array([p[0]]), tint, 1.5 * u)
			draw_line(c + Vector2(0, -11) * u, c + Vector2(0, 9) * u, tint, 3 * u)
			draw_line(c + Vector2(-7, -2) * u, c + Vector2(7, -2) * u, tint, 2 * u)
		else:
			var p := PackedVector2Array([c + Vector2(0, -14) * u, c + Vector2(15, -7) * u, c + Vector2(15, 10) * u, c + Vector2(0, 17) * u, c + Vector2(-15, 10) * u, c + Vector2(-15, -7) * u])
			draw_colored_polygon(p, tint.darkened(0.6))
			draw_polyline(p + PackedVector2Array([p[0]]), tint, 1.4 * u)
			draw_line(c + Vector2(-15, -7) * u, c, tint, u)
			draw_line(c + Vector2(15, -7) * u, c, tint, u)
			draw_line(c, c + Vector2(0, 17) * u, tint, u)


func _ready() -> void:
	layer = 10
	setup()


func setup() -> void:
	if is_instance_valid(canvas):
		return
	ui_font = preload("res://scripts/quality.gd").font()
	canvas = Control.new()
	canvas.name = "GameInterface"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	var theme := Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 17
	canvas.theme = theme


func update_view(s: Dictionary) -> void:
	setup()
	state = s
	warehouse_open = str(state.get("hub_station", "")) == "warehouse"
	var mode: String = str(state.get("mode", "hub"))
	var sig := _signature(mode)
	if mode != current_mode or sig != signature:
		if mode != current_mode:
			selected_item = -1
		current_mode = mode
		signature = sig
		_rebuild()
	_update_dynamic()
	var visible_size := get_viewport().get_visible_rect().size
	var factor := minf(visible_size.x / 1440.0, visible_size.y / 900.0)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (visible_size - Vector2(1440, 900) * factor) * 0.5


func _process(delta: float) -> void:
	motion_clock += delta
	var reduced := bool(state.get("motion_reduced",false))
	if refs.has("health_meter"):
		var hp_ratio := clampf(float(state.get("hp",100))/maxf(1,float(state.get("max_hp",100))),0,1)
		var meter: SlashMeter = refs["health_meter"]
		meter.ratio = hp_ratio if reduced else lerpf(meter.ratio,hp_ratio,minf(delta*18,1))
		meter.trail = hp_ratio if reduced else lerpf(meter.trail,hp_ratio,minf(delta*3,1))
		meter.tint = WHITE if hp_ratio > .25 else RED
		meter.queue_redraw()
		var veil: DamageVeil = refs["damage_veil"]
		veil.flash = float(state.get("hit_flash",0)) if current_mode == "raid" else 0
		veil.reduced = reduced
		veil.queue_redraw()
		for id in ["melee","special","dash","primary","secondary"]:
			if refs.has("tile_"+id): refs["tile_"+id].reduced = reduced
		var feed: Array = state.get("pickup_feed",[])
		for i in range(4):
			if i < feed.size():
				var age := float(feed[i].get("age",0))
				refs["feed_"+str(i)].position.x = 1087 + (0 if reduced else 18*(1-clampf(age/.2,0,1)))
				refs["feed_"+str(i)].modulate.a = clampf((4.0-age)/.5,0,1)
	if refs.has("combo_root"):
		var combo_root: Control = refs["combo_root"]
		var live := int(state.get("combo",0)) >= 2 and current_mode == "raid"
		combo_root.modulate.a = move_toward(combo_root.modulate.a,1.0 if live else 0.0,delta*(10.0 if live else 3.5))
		_combo_pop = maxf(0.0,_combo_pop-delta*6.0)
		var pop := 0.0 if reduced else _combo_pop*_combo_pop
		combo_root.scale = Vector2.ONE*(1.0+pop*.45)
		combo_root.rotation = deg_to_rad(-6.0+(0.0 if reduced else _combo_tilt*pop*7.0))
		if refs.has("combo_bar"): refs["combo_bar"].size.x = lerpf(refs["combo_bar"].size.x,140.0*clampf(float(state.get("combo_left",0)),0,1),minf(1,delta*14))
		_animate_combo(combo_root,delta,reduced)
	if refs.has("zone"):
		var caption: Label = refs["zone"]
		var age := float(caption.get_meta("caption_age",99.0))+delta
		caption.set_meta("caption_age",age)
		if age > ROOM_CAPTION_HOLD and current_mode == "raid":
			caption.modulate.a = move_toward(caption.modulate.a,0.0,delta*1.6)
	if refs.has("clear_banner"):
		var fx := float(state.get("clear_fx",0))
		var banner: Control = refs["clear_banner"]
		banner.visible = fx > 0 and current_mode == "raid"
		if banner.visible:
			banner.modulate.a = minf(fx*5,1)
			banner.position.y = 244.0
			refs["clear_sweep"].position.x = 18.0 if reduced else 18.0+fposmod(motion_clock*250,548)

func _signature(mode: String) -> String:
	match mode:
		"hub":
			if str(state.get("hub_station","")) == "heroes": return JSON.stringify(["heroes",state.get("hero_id","chrono"),hero_tab])
			if str(state.get("hub_station","")) == "shop": return JSON.stringify(["shop",state.get("meds"),state.get("quest_claimed")])
			return JSON.stringify([state.get("hub_station", ""),state.get("hero_id","chrono"), state.get("credits"), state.get("weapon"), state.get("upgrades"), state.get("stash"), state.get("meds"), state.get("quest_claimed"), state.get("equipped"), state.get("best_stage")])
		"inventory", "loot":
			return JSON.stringify([state.get("bag", []),state.get("boons",[]),state.get("boon_slots",{}),_family()])
		"skills":
			return JSON.stringify([state.get("choices", []),state.get("boon_slots",{}),_family()])
		"result":
			return JSON.stringify(state.get("result", {}))
		"gate":
			return JSON.stringify([state.get("stage", 1), state.get("bag_value", 0),state.get("dungeon",{}).get("floor",0)])
	return JSON.stringify([mode,_family(),state.get("hero_id","chrono"),state.get("boon_slots",{}),state.get("hammer_count",0)])


func _rebuild() -> void:
	_choice_generation += 1
	_choice_busy = false
	var surface := current_mode+":"+str(state.get("hub_station",""))+":"+(hero_tab if str(state.get("hub_station","")) == "heroes" else "")
	var transition := surface != rendered_surface
	rendered_surface = surface
	if is_instance_valid(scene_ui):
		_retire(scene_ui,transition)
	refs.clear()
	_panel_parts.clear()
	scene_ui = Control.new()
	scene_ui.size = Vector2(1440, 900)
	scene_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(scene_ui)
	if current_mode == "hub":
		_build_hub()
	else:
		_build_hud()
		var base := scene_ui
		if current_mode != "raid":
			var modal := Control.new()
			modal.size = Vector2(1440,900)
			modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
			base.add_child(modal)
			_panel_parts.append(modal)
			scene_ui = modal
		match current_mode:
			"inventory", "loot": _build_inventory()
			"skills": _build_skills()
			"result": _build_result()
			"pause": _build_pause()
			"gate": _build_gate()
		scene_ui = base
	_build_toast()
	scene_ui.set_meta("panel_parts",_panel_parts.duplicate())
	if transition:
		for part in _panel_parts: _enter_panel(part)


func _disable_tree(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
		if node is BaseButton: node.disabled = true
	node.set_process(false)
	for child in node.get_children(): _disable_tree(child)


func _retire(old: Control, animate: bool) -> void:
	var parts: Array = old.get_meta("panel_parts",[])
	_disable_tree(old)
	if not animate or parts.is_empty():
		old.get_parent().remove_child(old)
		old.queue_free()
		return
	for previous in _retiring:
		if is_instance_valid(previous): previous.queue_free()
	_retiring.clear()
	_retiring.append(old)
	for child in old.get_children():
		if child is CanvasItem and not parts.has(child): child.visible = false
	var tween := old.create_tween().set_parallel(true)
	tween.tween_property(old,"modulate:a",0.0,.18)
	if not bool(state.get("motion_reduced",false)):
		tween.tween_property(old,"position:y",-8.0,.18).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(func():
		_retiring.erase(old)
		if is_instance_valid(old): old.queue_free()
	)


func _enter_panel(panel: Control) -> void:
	panel.modulate.a = 0
	var tween := panel.create_tween().set_parallel(true)
	tween.tween_property(panel,"modulate:a",1.0,.2)
	if not bool(state.get("motion_reduced",false)):
		var end := panel.position
		panel.position.y += 10
		tween.tween_property(panel,"position",end,.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _live_control(node: Control) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and is_instance_valid(scene_ui) and scene_ui.is_ancestor_of(node)


func _color(value: Variant, fallback: Color = CYAN) -> Color:
	if value is Color:
		return value
	if value is String and not value.is_empty():
		return Color.from_string(value, fallback)
	return fallback


func _box(parent: Control, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, width: int = 1) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	return node


func _cut(parent: Control, rect: Rect2, color: Color, border: Color = LINE, accent: Color = Color.TRANSPARENT) -> CutPanel:
	var panel := CutPanel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.fill = color
	panel.edge = border
	panel.accent = accent
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _label(parent: Control, text: String, rect: Rect2, font_size: int = 18, color: Color = WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.clip_text = true
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.size = rect.size
	return node


func _paragraph(parent: Control, text: String, rect: Rect2, font_size: int = 16, color: Color = MUTED) -> Label:
	var node := _label(parent, text, rect, font_size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	node.size = rect.size
	return node


func _button(parent: Control, text: String, rect: Rect2, action_name: String, value: Variant = null, accent: Color = CYAN, solid: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pivot_offset = rect.size * 0.5
	node.add_theme_font_size_override("font_size", 17)
	node.add_theme_color_override("font_color", INK if solid else accent)
	node.add_theme_color_override("font_hover_color", INK if solid else WHITE)
	node.add_theme_color_override("font_pressed_color", INK if solid else WHITE)
	node.add_theme_color_override("font_disabled_color", Color("4f6b73"))
	for type in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = accent if solid else Color(0.06, 0.13, 0.17, 0.9)
		if type == "hover":
			style.bg_color = accent.lightened(0.12) if solid else Color(0.12, 0.24, 0.29, 0.98)
		if type == "pressed":
			style.bg_color = accent.darkened(0.15) if solid else Color(0.13, 0.3, 0.34, 1.0)
		if type == "disabled":
			style.bg_color = Color(0.04, 0.08, 0.1, 0.8)
		style.border_color = accent.darkened(0.55) if type == "normal" else accent
		if type == "disabled":
			style.border_color = LINE.darkened(0.4)
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		style.shadow_color = Color(0,0,0,.18)
		style.shadow_size = 3 if type != "pressed" else 0
		if type == "focus": style.set_border_width_all(2)
		node.add_theme_stylebox_override(type, style)
	node.pressed.connect(func():
		if _live_control(node) and not node.disabled: _dispatch(action_name,value)
	)
	node.mouse_entered.connect(func():
		if not node.disabled and not bool(state.get("motion_reduced",false)):
			var tween := node.create_tween()
			tween.tween_property(node, "scale", Vector2(1.025, 1.025), 0.1).set_trans(Tween.TRANS_QUAD)
	)
	node.mouse_exited.connect(func():
		if bool(state.get("motion_reduced",false)):
			node.scale = Vector2.ONE
		else:
			var tween := node.create_tween()
			tween.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD)
	)
	parent.add_child(node)
	return node


func _dispatch(action_name: String, value: Variant) -> void:
	if action_name == "skill":
		request_skill_choice(str(value))
		return
	if action_name == "hero_tab":
		hero_tab = str(value)
		signature = ""
		update_view(state)
		return
	action.emit(action_name, value)


func _decimal(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value,roundf(value)) else String.num(value,1)


func _rarity(item: Dictionary) -> String:
	if item.has("rarity_name"):
		return str(item.rarity_name)
	var raw: String = str(item.get("rarity", "common")).to_lower()
	return {"0":"普通", "1":"优秀", "2":"稀有", "3":"史诗", "4":"传说", "common":"普通", "uncommon":"优秀", "rare":"稀有", "epic":"史诗", "heroic":"英雄", "legendary":"传说", "mythic":"神话"}.get(raw, raw)


func _family() -> String:
	return str(state.get("weapon_family","spear" if str(state.get("weapon","spear")) == "spear" else "flying"))


func _hero() -> Dictionary:
	var hero: Dictionary = state.get("hero",{})
	return hero if not hero.is_empty() else Heroes.get_hero(str(state.get("hero_id","chrono")))


func _hero_skill(slot: String) -> Dictionary:
	var skill: Dictionary = _hero().get(slot,{}).duplicate(true)
	skill.merge(state.get("hero_skills",{}).get(slot,{}),true)
	return skill


func _hero_skill_brief(skill: Dictionary) -> String:
	match str(skill.get("id","")):
		"time_stop": return "冻结敌人与敌弹 %s 秒，玩家仍能移动和攻击。" % _decimal(float(skill.get("duration",3)))
		"rush": return "自动锁定 %s 米内最近敌人，至多五段穿梭；移动中短暂无敌，附带攻击祝福。" % _decimal(float(skill.get("range",6.2)))
		"sky_slam": return "腾空砸落，冲击半径 %s 米，造成 %s 基础伤害；附带攻击祝福。" % [_decimal(float(skill.get("radius",4.8))),_decimal(float(skill.get("damage",90)))]
		"flame_spin": return "半径 %s 米内三次旋斩，附带攻击祝福。" % _decimal(float(skill.get("radius",4.1)))
		"gravity_well": return "持续 %s 秒聚怪后爆破，半径 %s 米；首领较难牵引。" % [_decimal(float(skill.get("duration",3))),_decimal(float(skill.get("radius",4.8)))]
		"prism_guard": return "临时护盾 %s，持续 %s 秒并反弹 2.3 米内敌弹；结束清除余盾。" % [_decimal(float(skill.get("shield_max",40))),_decimal(float(skill.get("duration",4)))]
	return str(skill.get("desc",""))


func _boon_slot(slot: String) -> String:
	if slot == "attack" and _family() == "flying": return "飞剑攻击"
	return {"attack":"普通攻击","special":"特殊攻击","dash":"冲刺","passive":"被动","support":"辅助","hammer":"武器改造"}.get(slot,slot if not slot.is_empty() else "被动")


func _god_name(god: String) -> String:
	return {"zeus":"宙斯","poseidon":"波塞冬","athena":"雅典娜","ares":"阿瑞斯","artemis":"阿尔忒弥斯","aphrodite":"阿芙洛狄忒","dionysus":"狄俄尼索斯","demeter":"德墨忒尔","hermes":"赫尔墨斯","daedalus":"代达罗斯"}.get(god.to_lower(),god)


func _god_names(entry: Dictionary) -> String:
	if not str(entry.get("god_name","")).is_empty(): return str(entry.god_name)
	var names := PackedStringArray()
	var primary := str(entry.get("god",""))
	if not primary.is_empty(): names.append(_god_name(primary))
	if str(entry.get("type","")) == "duo":
		for tag in entry.get("tags",[]):
			if str(tag) in ["zeus","poseidon","athena","ares","artemis","aphrodite","dionysus","demeter"] and not names.has(_god_name(str(tag))): names.append(_god_name(str(tag)))
	return "＋".join(names)


func _has_boon(id: String) -> bool:
	for boon in state.get("boons",[]):
		if str(boon.get("id","")) == id: return bool(boon.get("active",true))
	return false


func _boon_meta(entry: Dictionary) -> String:
	var parts := PackedStringArray()
	var god := _god_names(entry)
	if not god.is_empty(): parts.append(god)
	parts.append("锤子改造" if str(entry.get("type","")) == "hammer" else _boon_slot(str(entry.get("slot","passive"))))
	parts.append(_rarity(entry))
	parts.append("Lv.%d" % int(entry.get("level",1)))
	return " / ".join(parts)


func _choice_note(choice: Dictionary) -> String:
	if str(choice.get("type","")) == "hammer": return "锤子改造 · 本次行动持续生效"
	var slot: String = str(choice.get("slot",""))
	var previous: Dictionary = state.get("boon_slots",{}).get(slot,{})
	if not previous.is_empty():
		if str(previous.get("id","")) == str(choice.get("id","")):
			return "强化 " + str(previous.get("name","")) + "  Lv.%d → %d" % [int(previous.get("level",1)),int(choice.get("level",int(previous.get("level",1))+1))]
		return "替换" + _boon_slot(slot) + " · " + str(previous.get("name",""))
	return "赋予" + _boon_slot(slot) if slot in ["attack","special","dash"] else "新增本次行动强化"


func _item_color(item: Dictionary) -> Color:
	if not str(item.get("slot", "")).is_empty():
		return {"普通":Color("b7c9d3"), "优秀":Color("8aefae"), "精良":Color("8aefae"), "稀有":Color("79bcff"), "史诗":Color("c79cff"), "传说":Color("ffc169"), "神话":Color("ff7c98")}.get(_rarity(item), _color(item.get("color", CYAN)))
	return _color(item.get("color", CYAN))


func _bonus_text(item: Dictionary) -> String:
	var bonuses: Dictionary = item.get("bonuses", {})
	var names := {"damage":"伤害", "damage_pct":"伤害", "hp":"生命", "health":"生命", "max_hp":"生命", "shield":"护盾", "crit":"暴击", "crit_chance":"暴击", "speed":"移速", "speed_pct":"移速", "attack_speed":"攻速", "haste":"攻速", "range":"射程", "sword_count":"飞剑", "count":"飞剑", "armor":"减伤", "leech":"吸血"}
	var parts := PackedStringArray()
	for key in bonuses:
		var value: Variant = bonuses[key]
		var amount: String = String.num(float(value), 2) if value is float or value is int else str(value)
		if str(key).ends_with("_pct") or key in ["damage", "crit", "crit_chance", "attack_speed", "haste", "speed"]:
			amount = String.num(float(value) * 100.0, 2) + "%"
		parts.append(str(names.get(key, key)) + (" +" if float(value) >= 0 else " ") + amount)
	return "  ·  ".join(parts)


func _item_icon(item: Dictionary) -> String:
	return {"blade":"sword", "armor":"armor", "charm":"core"}.get(str(item.get("slot", "")), str(item.get("id", "cache")))


func _slot_name(slot: String) -> String:
	return {"blade":"剑刃", "armor":"装甲", "charm":"挂件"}.get(slot, "物资")


func _glyph(parent: Control, id: String, pos: Vector2, dim: float, color: Color = CYAN) -> Glyph:
	var icon := Glyph.new()
	icon.kind = id
	icon.tint = color
	icon.position = pos
	icon.size = Vector2.ONE * dim
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon


func _line(parent: Control, x: float, y: float, width: float, color: Color = LINE) -> void:
	_box(parent, Rect2(x, y, width, 1), color)


func _bar(parent: Control, rect: Rect2, tint: Color) -> ProgressBar:
	var node := ProgressBar.new()
	node.position = rect.position
	node.size = rect.size
	node.show_percentage = false
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.12, 0.15, 0.85)
	var fg := StyleBoxFlat.new()
	fg.bg_color = tint
	node.add_theme_stylebox_override("background", bg)
	node.add_theme_stylebox_override("fill", fg)
	parent.add_child(node)
	return node


func _build_hub() -> void:
	var title := Control.new()
	title.position = Vector2(37,34)
	title.rotation = deg_to_rad(-2.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_ui.add_child(title)
	_box(title,Rect2(0,8,3,43),CYAN)
	_label(title,"STARBLADE",Rect2(17,0,330,42),31,WHITE)
	_label(title,"轨道补给站  /  HANGAR 07",Rect2(18,48,350,23),12,CYAN)
	_label(title,"最佳推进  第 %02d 区" % int(state.get("best_stage",0)),Rect2(18,77,340,20),11,MUTED)
	_label(title,"当前英雄  /  "+str(_hero().get("name","时隙")),Rect2(18,108,340,25),14,_color(_hero().get("color",CYAN)))
	refs["credits"] = _label(scene_ui,"%s CR" % _number(int(state.get("credits",0))),Rect2(1098,35,299,35),25,ORANGE,HORIZONTAL_ALIGNMENT_RIGHT)
	_label(scene_ui,"修复剂  × %d   /   储备" % int(state.get("meds",0)),Rect2(1098,76,299,23),12,WHITE,HORIZONTAL_ALIGNMENT_RIGHT)
	var station: String = str(state.get("hub_station",""))
	if station.is_empty():
		refs["hub_prompt_bg"] = _cut(scene_ui,Rect2(450,753,540,56),Color(.014,.035,.05,.78),Color(CYAN,.35),CYAN)
		refs["hub_prompt"] = _label(refs["hub_prompt_bg"],"靠近设施  ·  点「交互」" if preload("res://scripts/quality.gd").touch_active else "靠近设施  ·  按 E 交互",Rect2(20,9,500,36),18,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
		_label(scene_ui,"左侧拖动 移动     冲刺     交互" if preload("res://scripts/quality.gd").touch_active else "WASD  移动     SPACE  冲刺     E  交互",Rect2(435,843,570,25),12,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
		_label(scene_ui,"英雄终端  /  工作台  /  仓库  /  补给商店  /  出击通道",Rect2(435,817,570,21),11,Color(WHITE,.65),HORIZONTAL_ALIGNMENT_CENTER)
	else:
		match station:
			"heroes": _build_heroes()
			"workbench": _build_workbench()
			"warehouse": _build_warehouse()
			"shop": _build_shop()
			"deploy": _build_deploy()


func _build_heroes() -> void:
	var panel := _station_panel("英雄终端","",Rect2(548,100,856,752),_color(_hero().get("color",CYAN)))
	refs["hero_tab_roster"] = _button(panel,"英雄",Rect2(30,75,105,29),"hero_tab","roster",CYAN,hero_tab == "roster")
	refs["hero_tab_talents"] = _button(panel,"天赋",Rect2(147,75,105,29),"hero_tab","talents",CYAN,hero_tab == "talents")
	_label(panel,str(_hero().get("name",""))+"  /  "+("永久成长" if hero_tab == "talents" else "武器独立配置"),Rect2(290,77,470,23),12,_color(_hero().get("color",CYAN)),HORIZONTAL_ALIGNMENT_RIGHT)
	if hero_tab == "talents":
		var tree := TalentTreeUI.new()
		tree.position = Vector2(30,145)
		tree.size = Vector2(796,540)
		tree.hero_id = str(state.get("hero_id","chrono"))
		tree.tint = _color(_hero().get("color",CYAN))
		tree.selected_id = str(talent_selection.get(tree.hero_id,"vitality"))
		tree.entries = state.get("talent_tree",[])
		panel.add_child(tree)
		tree.selected.connect(func(id: String):
			if _live_control(tree): talent_selection[tree.hero_id] = id
		)
		tree.unlock_requested.connect(func(id: String):
			if _live_control(tree): _dispatch("unlock_talent",{"hero":tree.hero_id,"node":id})
		)
		refs["talent_tree"] = tree
		refs["talent_unlock"] = tree.unlock_button
		for id in tree.buttons: refs["talent_node_"+id] = tree.buttons[id]
		call_deferred("_focus_button",tree.buttons.get(tree.selected_id))
		_label(panel,"信用点共用 · 天赋按英雄独立保存",Rect2(30,716,796,24),12,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
		return
	var roster: Array = state.get("heroes",Heroes.all())
	for i in range(mini(3,roster.size())):
		var hero: Dictionary = roster[i]
		var id: String = str(hero.get("id","chrono"))
		var color := _color(hero.get("color",CYAN))
		var selected := str(state.get("hero_id","chrono")) == id
		var card := _cut(panel,Rect2(30+i*270,132,254,574),Color(color.darkened(.89),.98),color if selected else LINE,color if selected else Color.TRANSPARENT)
		_label(card,str(hero.get("codename",id)),Rect2(17,12,220,20),11,color)
		var portrait := HeroPortrait.new()
		portrait.hero_id = str(hero.get("visual",id))
		portrait.tint = color
		portrait.position = Vector2(20,35)
		portrait.size = Vector2(214,115)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)
		_label(card,str(hero.get("name",id)),Rect2(17,148,220,37),28,WHITE)
		_label(card,str(hero.get("role","")),Rect2(18,188,218,23),12,color)
		_paragraph(card,str(hero.get("desc","")),Rect2(18,220,218,41),12,MUTED)
		_line(card,18,273,218,Color(color,.25))
		for n in range(2):
			var slot: String = ["primary","secondary"][n]
			var skill: Dictionary = _hero_skill(slot) if selected else hero.get(slot,{})
			var y := 287.0+n*116
			_glyph(card,str(skill.get("icon","core")),Vector2(17,y),26,_color(skill.get("color",color)))
			_label(card,str(skill.get("key","F"))+"  "+str(skill.get("name","技能")),Rect2(52,y,184,26),14,WHITE)
			_label(card,"%s 能量 / %s 秒%s" % [_decimal(float(skill.get("cost",0))),_decimal(float(skill.get("cooldown",0))),"" if selected else " · 基础"],Rect2(18,y+31,218,19),10,color)
			_paragraph(card,_hero_skill_brief(skill),Rect2(18,y+55,218,54),11,MUTED)
		var button := _button(card,"已部署  ✓" if selected else "部署 "+str(hero.get("name",id)),Rect2(18,534,218,27),"select_hero",id,color,selected)
		button.add_theme_font_size_override("font_size",13)
		button.disabled = selected
		refs["hero_select_"+id] = button
	_label(panel,"全部英雄免费 · 选择即时保存 · 在出击前自由更换",Rect2(30,718,796,20),11,MUTED,HORIZONTAL_ALIGNMENT_CENTER)


func _station_panel(title: String, subtitle: String, rect: Rect2, accent: Color = CYAN) -> Control:
	var overlay := Control.new()
	overlay.size = Vector2(1440,900)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_ui.add_child(overlay)
	_panel_parts.append(overlay)
	_box(overlay,Rect2(0,0,1440,900),Color(.004,.014,.023,.24)).mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := _cut(overlay,rect,Color(.022,.051,.072,.98),LINE,accent)
	_label(panel,title,Rect2(30,23,rect.size.x-120,43),29,WHITE)
	_label(panel,subtitle,Rect2(31,73,rect.size.x-69,24),12,accent)
	_button(panel,"×",Rect2(rect.size.x-75,26,42,35),"station_close",null,MUTED)
	_line(panel,30,112,rect.size.x-60)
	_label(overlay,"ESC  返回大厅",Rect2(rect.position.x,rect.end.y+15,rect.size.x,22),11,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	return panel


func _build_equipment(parent: Control, rect: Rect2, can_remove: bool = false) -> void:
	var equipped: Dictionary = state.get("equipped",{})
	var slots := ["blade","armor","charm"]
	var width := (rect.size.x-20)/3
	for i in range(3):
		var slot: String = slots[i]
		var item: Dictionary = equipped.get(slot,{})
		var c := _item_color(item) if not item.is_empty() else MUTED
		var card := _cut(parent,Rect2(rect.position+Vector2(i*(width+10),0),Vector2(width,rect.size.y)),Color(.035,.08,.105,.94),c.darkened(.5))
		_glyph(card,_item_icon(item) if not item.is_empty() else {"blade":"sword","armor":"armor","charm":"core"}[slot],Vector2(12,10),29,c)
		_label(card,_slot_name(slot)+(" · "+_rarity(item) if not item.is_empty() else ""),Rect2(49,12,width-62,22),11,c)
		_label(card,str(item.get("name","未装备")),Rect2(14,44,width-28,27),16,WHITE if not item.is_empty() else MUTED)
		_paragraph(card,_bonus_text(item) if not item.is_empty() else "战区回收 / 仓库装备",Rect2(14,77,width-28,38),11,c)
		if can_remove and not item.is_empty():
			_button(card,"卸下",Rect2(width-64,rect.size.y-32,49,24),"unequip",slot,MUTED).add_theme_font_size_override("font_size",11)


func _build_workbench() -> void:
	var panel := _station_panel("武器工作台","选择一件主武器",Rect2(580,128,824,650))
	var weapons: Array = state.get("weapons",[]).duplicate()
	for i in range(weapons.size()):
		if str(weapons[i].get("id","")) == "spear":
			var primary: Dictionary = weapons.pop_at(i)
			weapons.push_front(primary)
			break
	for i in range(mini(weapons.size(),4)):
		var weapon: Dictionary = weapons[i]
		var id: String = str(weapon.get("id","spear"))
		var chosen: bool = str(state.get("weapon","spear")) == id
		var c := _color(weapon.get("color",CYAN))
		var card := _cut(panel,Rect2(30+(i%2)*388,132+(i/2)*156,376,146),Color(.035,.085,.115,.97),c if chosen else LINE,c if chosen else Color.TRANSPARENT)
		var art := CardArt.new()
		art.position = Vector2(248,3)
		art.size = Vector2(109,76)
		art.tint = c
		art.reduced = bool(state.get("motion_reduced",false))
		art.clip_contents = true
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
		_glyph(card,id,Vector2(13,13),44,c)
		_label(card,str(weapon.get("name",id)),Rect2(70,10,280,31),22,WHITE)
		_label(card,str(weapon.get("subtitle","主动长矛" if id == "spear" else "射击御剑")),Rect2(70,45,288,21),11,c)
		_paragraph(card,str(weapon.get("desc","")),Rect2(17,79,233,55),12,MUTED)
		var owned: bool = bool(weapon.get("owned",id == "spear"))
		var text: String = "已选择" if chosen else ("装 备" if owned else "%d CR 购入" % int(weapon.get("price",0)))
		var button := _button(card,text,Rect2(258,96,100,34),"select_weapon",id,c,chosen)
		button.add_theme_font_size_override("font_size",12)
		button.disabled = not owned and int(state.get("credits",0)) < int(weapon.get("price",0))
	_label(panel,"当前配装",Rect2(30,450,360,24),16,WHITE)
	_label(panel,"前往仓库更换",Rect2(408,450,386,23),11,MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	_build_equipment(panel,Rect2(30,486,764,112))
	var legacy: Dictionary = state.get("upgrades",{})
	_label(panel,"旧设施收益继续生效" if int(legacy.get("reactor",0))+int(legacy.get("armor",0)) > 0 else "永久成长：前往英雄终端点亮天赋",Rect2(30,612,764,23),11,MUTED)


func _build_warehouse() -> void:
	var panel := _station_panel("物资仓库","STORAGE  /  撤离物资永久保留 · 选择战利装备",Rect2(604,129,800,710))
	var stash: Array = state.get("stash",[])
	var value := 0
	var caches := 0
	for item in stash:
		value += int(item.get("value",0))
		if str(item.get("id","")) == "cache": caches += 1
	_label(panel,"当前配装",Rect2(30,128,300,24),15,WHITE)
	_build_equipment(panel,Rect2(30,165,740,142),true)
	_label(panel,"库存 %d 件  /  估值 %s CR" % [stash.size(),_number(value)],Rect2(30,324,530,25),14,ORANGE)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30,365)
	scroll.size = Vector2(740,253)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	var grouped: Dictionary = {}
	for i in range(stash.size()):
		var item: Dictionary = stash[i]
		var id: String = str(item.get("id",""))
		var key: String = str(i) if not str(item.get("slot","")).is_empty() else id
		if not grouped.has(key): grouped[key] = {"item":item,"count":0,"index":i}
		grouped[key].count += 1
	for key in grouped:
		var item: Dictionary = grouped[key].item
		var count: int = grouped[key].count
		var is_gear := not str(item.get("slot","")).is_empty()
		var row := Control.new()
		row.custom_minimum_size = Vector2(725,96)
		list.add_child(row)
		var c := _item_color(item)
		_box(row,Rect2(0,0,725,96),Color(.035,.08,.11,1),c.darkened(.55) if is_gear else LINE)
		_glyph(row,_item_icon(item),Vector2(13,20),48,c)
		_label(row,str(item.get("name","物资"))+("" if is_gear else "  × "+str(count)),Rect2(76,9,478,28),18,c)
		if is_gear:
			_label(row,_rarity(item)+"  /  "+_slot_name(str(item.slot)),Rect2(76,40,478,20),11,c)
			_label(row,_bonus_text(item),Rect2(76,66,478,20),12,MUTED)
			_button(row,"装备",Rect2(590,10,118,32),"equip",int(grouped[key].index),c).add_theme_font_size_override("font_size",14)
		else:
			_paragraph(row,str(item.get("desc","")),Rect2(76,45,478,39),12,MUTED)
			_label(row,"单件 %d CR" % int(item.get("value",0)),Rect2(572,12,136,25),12,ORANGE,HORIZONTAL_ALIGNMENT_RIGHT)
		_button(row,"出售 %d" % int(item.get("value",0)),Rect2(590,54,118,29),"sell_item",int(grouped[key].index),MUTED).add_theme_font_size_override("font_size",12)
	if grouped.is_empty():
		var empty := Label.new()
		empty.text = "仓库还是空的。\n前往战区，带回第一批物资。"
		empty.custom_minimum_size = Vector2(725,245)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color",MUTED)
		list.add_child(empty)
	_label(panel,"材料可用于升级，装备可单独出售。",Rect2(30,650,400,26),11,MUTED)
	var open := _button(panel,"开启封存宝箱  × %d" % caches,Rect2(494,640,276,43),"open_caches",null,CYAN)
	open.add_theme_font_size_override("font_size",15)
	open.disabled = caches == 0


func _build_shop() -> void:
	var panel := _station_panel("补给商店","购入后存入仓库，在仓库装配生效",Rect2(548,100,856,752),ORANGE)
	var offers: Array = state.get("shop_offers",[])
	for i in range(mini(9,offers.size())):
		var item: Dictionary = offers[i]
		var id := str(item.get("id",""))
		var color := _item_color(item)
		var card := _cut(panel,Rect2(30+(i%3)*270,132+(i/3)*142,254,130),Color(.025,.06,.08,.97),Color(color,.3))
		_glyph(card,_item_icon(item),Vector2(13,13),31,color)
		_label(card,str(item.get("name","装备")),Rect2(56,10,180,26),15,color)
		_label(card,_rarity(item)+" / "+_slot_name(str(item.get("slot",""))),Rect2(56,38,180,18),10,MUTED)
		_paragraph(card,_bonus_text(item),Rect2(14,62,226,30),11,WHITE)
		var price := int(item.get("price",0))
		var button := _button(card,"购入 %d CR" % price,Rect2(14,92,226,31),"buy_equipment",id,color)
		button.add_theme_font_size_override("font_size",13)
		button.set_meta("price",price)
		refs["shop_buy_"+id] = button
	_line(panel,30,563,796)
	_glyph(panel,"medkit",Vector2(31,580),34,Color("90e9bb"))
	_label(panel,"修复剂 × %d" % int(state.get("meds",0)),Rect2(78,575,180,27),17,WHITE)
	_label(panel,"每次最多携带 2 份",Rect2(78,606,180,20),11,MUTED)
	refs["shop_med"] = _button(panel,"购入 60 CR",Rect2(262,583,158,36),"buy_med",null,CYAN)
	_button(panel,"出售普通物资",Rect2(445,583,350,36),"sell",null,ORANGE)
	_line(panel,30,645,796)
	var claimed := bool(state.get("quest_claimed",false))
	_label(panel,"委托已完成" if claimed else "中继核心委托",Rect2(31,661,505,29),19,WHITE)
	_label(panel,"感谢你的回收" if claimed else "交付第五区核心 · 奖励 900 CR",Rect2(31,700,505,23),12,MUTED)
	var q := _button(panel,"已完成" if claimed else "提交核心",Rect2(602,671,194,39),"claim_quest",null,ORANGE)
	var has_core := false
	for item in state.get("stash",[]):
		if str(item.get("id","")) == "core": has_core = true
	q.disabled = claimed or not has_core


func _build_deploy() -> void:
	var panel := _station_panel("出击通道","DEPLOYMENT  /  将整备成果带入战区",Rect2(704,163,700,646),ORANGE)
	var weapon_name := "基础长矛"
	var weapon_id: String = str(state.get("weapon","spear"))
	for weapon in state.get("weapons",[]):
		if str(weapon.get("id","")) == weapon_id: weapon_name = str(weapon.get("name",weapon_id))
	_glyph(panel,weapon_id,Vector2(30,133),62,WHITE)
	_label(panel,weapon_name+"  /  已就绪",Rect2(111,135,514,32),23,WHITE)
	_label(panel,"J 连刺（自动瞄准）/ 长按横扫    K 投掷与召回    Space 冲刺" if _family() == "spear" else "J 射剑（自动瞄准）· 打空后 J 召回    Space 闪避",Rect2(111,180,549,23),12,MUTED)
	_label(panel,str(_hero().get("name","时隙"))+"  /  "+("主动长矛" if _family() == "spear" else "射击御剑"),Rect2(31,229,400,28),17,_color(_hero().get("color",CYAN)))
	_build_equipment(panel,Rect2(30,284,640,122))
	_paragraph(panel,"选择初始强化，探索每层的 9 个相连房间。\n击败本层首领后，可深入更危险的下一层，或撤离保存收获。",Rect2(31,432,638,55),15,WHITE)
	_label(panel,"阵亡会遗失本次战利品、战利装备与付费武器。",Rect2(31,500,638,24),12,ORANGE)
	_button(panel,"开 始 行 动     →",Rect2(31,553,638,57),"start",null,ORANGE,true).add_theme_font_size_override("font_size",22)


func _build_hud() -> void:
	var damage := DamageVeil.new()
	damage.size = Vector2(1440,900)
	damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_ui.add_child(damage)
	refs["damage_veil"] = damage
	# Immersive HUD: no persistent ops panel. The room name only surfaces as a
	# short caption when a new room is entered.
	refs["zone"] = _label(scene_ui,"",Rect2(ROOM_CAPTION_X,34,500,34),22,Color(WHITE,.92),HORIZONTAL_ALIGNMENT_CENTER)
	refs["zone"].add_theme_constant_override("outline_size",6)
	refs["zone"].add_theme_color_override("font_outline_color",Color(0,0,0,.55))
	refs["zone"].modulate.a = 0
	var radar := DungeonMap.new()
	radar.position = Vector2(1260,49)
	radar.size = Vector2(138,132)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_ui.add_child(radar)
	refs["radar"] = radar
	refs["dungeon_map"] = radar
	var boss_panel := _cut(scene_ui,Rect2(480,105,480,79),Color(.025,.04,.055,.91),Color(ORANGE,.3),ORANGE)
	refs["boss_panel"] = boss_panel
	refs["boss_name"] = _label(boss_panel,"",Rect2(18,9,300,23),16,WHITE)
	refs["boss_phase"] = _label(boss_panel,"",Rect2(314,11,148,19),11,ORANGE,HORIZONTAL_ALIGNMENT_RIGHT)
	var boss_meter := BossMeter.new()
	boss_meter.position = Vector2(18,39)
	boss_meter.size = Vector2(444,8)
	boss_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_panel.add_child(boss_meter)
	refs["boss_meter"] = boss_meter
	refs["boss_attack"] = _label(boss_panel,"",Rect2(18,53,228,17),10,MUTED)
	refs["boss_values"] = _label(boss_panel,"",Rect2(248,53,214,17),10,MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	boss_panel.visible = false
	var vitals := Control.new()
	vitals.position = Vector2(34,782)
	vitals.rotation = deg_to_rad(-4.0)
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_ui.add_child(vitals)
	# Soft backing keeps vitals readable over silver floors and cloud silhouettes.
	var backing := TextureRect.new()
	backing.position = Vector2(-30,-54); backing.size = Vector2(455,158)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := GradientTexture2D.new()
	fade.width = 256; fade.height = 96
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(.25,.52); fade.fill_to = Vector2(1,.52)
	fade.gradient = Gradient.new()
	fade.gradient.set_color(0,Color(.018,.038,.065,.78))
	fade.gradient.set_color(1,Color(.018,.038,.065,0))
	backing.texture = fade
	vitals.add_child(backing)
	refs["health_text"] = _label(vitals,"100 / 100",Rect2(4,-31,200,26),18,WHITE)
	var health := SlashMeter.new()
	health.size = Vector2(356,22)
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(health)
	refs["health_meter"] = health
	var shield := SlashMeter.new()
	shield.position = Vector2(0,27)
	shield.size = Vector2(354,3)
	shield.segments = 1
	shield.skew = 2
	shield.tint = Color("91b8ff")
	shield.ratio = 0
	shield.trail = 0
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(shield)
	refs["shield_meter"] = shield
	var chrono := SlashMeter.new()
	chrono.position = Vector2(0,58)
	chrono.size = Vector2(354,7)
	chrono.segments = 1
	chrono.skew = 5
	chrono.tint = CYAN
	chrono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(chrono)
	refs["mana_meter"] = chrono
	var abilities := [
		{"id":"melee","key":"J / 左键","name":"连刺 · 长按横扫","icon":"spear","color":WHITE,"duration":.6},
		{"id":"special","key":"K / 右键","name":"投掷 / 召回","icon":"throw","color":Color("b8afff"),"duration":.6},
		{"id":"dash","key":"SPACE","name":"冲刺  × 2","icon":"dash","color":CYAN,"duration":2.2}
	]
	if _family() == "flying": abilities = abilities.slice(2)
	for i in range(abilities.size()):
		var a: Dictionary = abilities[i]
		var tile := AbilityTile.new()
		tile.position = Vector2(1398-abilities.size()*120+i*120,758+i*2)
		tile.size = Vector2(112,112)
		tile.tint = a.color
		tile.duration = a.duration
		tile.activated.connect(func(): action.emit(str(a.id),null))
		scene_ui.add_child(tile)
		refs["tile_"+str(a.id)] = tile
		_label(tile,str(a.key),Rect2(18,8,84,19),10,a.color)
		var icon := _glyph(tile,str(a.icon),Vector2(33,32),47,a.color)
		refs["icon_"+str(a.id)] = icon
		refs["cool_"+str(a.id)] = _label(tile,"",Rect2(8,31,96,48),27,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
		refs["name_"+str(a.id)] = _label(tile,str(a.name),Rect2(5,83,102,22),10,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
		var slot: String = {"melee":"attack","special":"special","dash":"dash"}.get(str(a.id),"")
		var boon: Dictionary = state.get("boon_slots",{}).get(slot,{})
		if not boon.is_empty():
			_label(tile,str(boon.get("name",""))+" Lv.%d" % int(boon.get("level",1)),Rect2(-2,-25,118,19),10,_color(boon.get("color",CYAN)),HORIZONTAL_ALIGNMENT_CENTER)
			tile.tooltip_text = _boon_meta(boon)+"\n"+str(boon.get("desc",""))
	if _family() == "flying":
		var pips := BladePips.new()
		pips.position = Vector2(814,770)
		pips.size = Vector2(205,40)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scene_ui.add_child(pips)
		refs["blade_pips"] = pips
		refs["blade_hint"] = _label(scene_ui,"「攻击」射剑 · 打空后召回" if preload("res://scripts/quality.gd").touch_active else "J 射剑 · 打空后 J 召回",Rect2(794,815,245,22),11,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
		var attack_boon: Dictionary = state.get("boon_slots",{}).get("attack",{})
		if not attack_boon.is_empty(): _label(scene_ui,str(attack_boon.get("name",""))+" Lv.%d" % int(attack_boon.get("level",1)),Rect2(814,749,205,22),12,_color(attack_boon.get("color",CYAN)),HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(2):
		var slot: String = ["primary","secondary"][i]
		var a := _hero_skill(slot)
		var color := _color(a.get("color",_hero().get("color",CYAN)))
		var tile := AbilityTile.new()
		tile.position = Vector2(1106+i*146,608+i*3)
		tile.size = Vector2(140,96)
		tile.tint = color
		tile.duration = float(a.get("cooldown",1))
		tile.activated.connect(func(): action.emit("hero_"+slot,null))
		scene_ui.add_child(tile)
		refs["tile_"+slot] = tile
		_label(tile,str(a.get("key","F" if i == 0 else "L")),Rect2(18,8,20,21),15,color)
		_label(tile,str(a.get("name","技能")),Rect2(42,9,90,20),11,WHITE)
		refs["icon_"+slot] = _glyph(tile,str(a.get("icon","core")),Vector2(17,34),38,color)
		refs["cool_"+slot] = _label(tile,"就绪",Rect2(58,32,65,36),21,WHITE,HORIZONTAL_ALIGNMENT_RIGHT)
		refs["name_"+slot] = _label(tile,"",Rect2(8,73,119,18),10,color,HORIZONTAL_ALIGNMENT_CENTER)
		tile.tooltip_text = str(a.get("name",""))+"\n"+str(a.get("desc",""))
	refs["prompt"] = _label(scene_ui,"",Rect2(426,711,528,36),17,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
	_build_combo()
	for i in range(4):
		var feed := _cut(scene_ui,Rect2(1087,232+i*41,311,35),Color(.015,.045,.065,.7),Color.TRANSPARENT)
		feed.visible = false
		refs["feed_"+str(i)] = feed
		refs["feed_icon_"+str(i)] = _glyph(feed,"core",Vector2(15,4),27,CYAN)
		refs["feed_text_"+str(i)] = _label(feed,"",Rect2(52,2,240,31),12,WHITE)
	var clear_banner := _cut(scene_ui,Rect2(414,244,612,76),Color(.015,.045,.06,.88),CYAN,CYAN)
	_label(clear_banner,"S E C T O R  C L E A R",Rect2(30,8,552,17),10,CYAN,HORIZONTAL_ALIGNMENT_CENTER)
	refs["clear_title"] = _label(clear_banner,"第 01 区  肃 清",Rect2(30,27,552,29),25,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
	_label(clear_banner,"战利品掉落 · 正在自动回收",Rect2(30,57,552,17),10,ORANGE,HORIZONTAL_ALIGNMENT_CENTER)
	refs["clear_sweep"] = _box(clear_banner,Rect2(18,0,36,3),WHITE)
	refs["clear_banner"] = clear_banner
	clear_banner.visible = false


func _build_combo() -> void:
	_combo_sparks.clear()
	var root := Control.new()
	root.position = Vector2(1150,430)
	root.size = Vector2(250,150)
	root.pivot_offset = Vector2(200,62)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.rotation = deg_to_rad(-6.0)
	root.modulate.a = 0
	scene_ui.add_child(root)
	refs["combo_root"] = root
	# Slanted energy plate behind the digits gives the counter depth.
	var plate := FlatPoly.new()
	plate.polygon = PackedVector2Array([Vector2(70,18),Vector2(250,6),Vector2(236,120),Vector2(40,128)])
	plate.color = Color(1,.6,.25,.0)
	root.add_child(plate)
	refs["combo_plate"] = plate
	var streak := FlatPoly.new()
	streak.polygon = PackedVector2Array([Vector2(-30,70),Vector2(260,52),Vector2(260,58),Vector2(-30,78)])
	streak.color = Color(1,1,1,0)
	root.add_child(streak)
	refs["combo_streak"] = streak
	var ghost := _label(root,"0",Rect2(0,0,236,96),78,Color(1,.5,.2,0),HORIZONTAL_ALIGNMENT_RIGHT)
	ghost.pivot_offset = Vector2(200,48)
	refs["combo_ghost"] = ghost
	var count := _label(root,"0",Rect2(0,0,236,96),78,WHITE,HORIZONTAL_ALIGNMENT_RIGHT)
	count.pivot_offset = Vector2(200,48)
	count.add_theme_constant_override("outline_size",12)
	count.add_theme_color_override("font_outline_color",Color(.02,.02,.05,.85))
	refs["combo_count"] = count
	var title := _label(root,"连 击",Rect2(0,90,236,26),18,ORANGE,HORIZONTAL_ALIGNMENT_RIGHT)
	title.add_theme_constant_override("outline_size",6)
	title.add_theme_color_override("font_outline_color",Color(0,0,0,.7))
	refs["combo_title"] = title
	for i in 2:
		var bar := ColorRect.new()
		bar.position = Vector2(96,122); bar.size = Vector2(140,4)
		bar.color = Color(1,1,1,.14) if i == 0 else ORANGE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		refs["combo_bar_back" if i == 0 else "combo_bar"] = bar
	var ring := Line2D.new()
	ring.width = 4; ring.default_color = Color(1,1,1,0)
	for k in 33: ring.add_point(Vector2(cos(TAU*k/32.0)*1.0,sin(TAU*k/32.0)*.55))
	ring.position = Vector2(178,52)
	root.add_child(ring)
	refs["combo_ring"] = ring
	for k in 10:
		var spark := ColorRect.new()
		spark.size = Vector2(10,3); spark.pivot_offset = Vector2(5,1.5)
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spark.color = Color(1,1,1,0)
		root.add_child(spark)
		_combo_sparks.append({"node":spark,"vel":Vector2.ZERO,"life":0.0})


func _combo_color(n: int) -> Color:
	if n >= 50: return Color("ff6bd6")
	if n >= 25: return Color("ffd16a")
	if n >= 10: return Color("7ff4ff")
	return WHITE


func _update_combo() -> void:
	if not refs.has("combo_root"): return
	var n := int(state.get("combo",0))
	if n > _combo_shown:
		_combo_pop = 1.0
		_combo_tilt = (randf()*2.0-1.0)
		_combo_shake = minf(1.0,.45+float(n)*.012)
		if refs.has("combo_ghost"):
			refs["combo_ghost"].text = str(n)
			refs["combo_ghost"].scale = Vector2.ONE
			refs["combo_ghost"].modulate.a = 1.0
		_spawn_combo_sparks(3 if n < 10 else 5)
	var tier := 3 if n >= 50 else (2 if n >= 25 else (1 if n >= 10 else 0))
	if tier > _combo_tier and n > _combo_shown:
		_combo_burst = 1.0
		_spawn_combo_sparks(10)
	_combo_tier = tier
	_combo_shown = n
	var color := _combo_color(n)
	refs["combo_count"].text = str(n)
	refs["combo_count"].add_theme_color_override("font_color",color)
	refs["combo_title"].text = {50:"疯 狂 连 击",25:"狂 热 连 击",10:"凌 厉 连 击"}.get(50 if n >= 50 else (25 if n >= 25 else (10 if n >= 10 else 0)),"连 击")
	refs["combo_title"].add_theme_color_override("font_color",color if n >= 10 else ORANGE)
	refs["combo_bar"].color = color if n >= 10 else ORANGE
	refs["combo_bar"].size.x = 140.0*clampf(float(state.get("combo_left",0)),0,1)
	if refs.has("combo_ghost"): refs["combo_ghost"].add_theme_color_override("font_color",(color if n >= 10 else ORANGE))


func _spawn_combo_sparks(count: int) -> void:
	var used := 0
	for s in _combo_sparks:
		if used >= count: break
		if float(s.life) > 0: continue
		var a := randf_range(-PI*.95,PI*.15)
		s.vel = Vector2(cos(a),sin(a))*randf_range(240,520)
		s.life = randf_range(.25,.45)
		s.node.position = Vector2(178,52)
		s.node.rotation = a
		used += 1


func _animate_combo(root: Control, delta: float, reduced: bool) -> void:
	var n := int(state.get("combo",0))
	var color := _combo_color(n) if n >= 10 else ORANGE
	_combo_shake = maxf(0.0,_combo_shake-delta*5.0)
	_combo_burst = maxf(0.0,_combo_burst-delta*2.4)
	var shake := 0.0 if reduced else _combo_shake*_combo_shake*9.0
	var t := Time.get_ticks_msec()*.001
	root.position = Vector2(1150,430)+Vector2(sin(t*71.0),cos(t*53.0))*shake
	# Perspective lean: the plate skews toward the camera on every pop.
	var pop := 0.0 if reduced else _combo_pop*_combo_pop
	var count: Label = refs["combo_count"]
	count.scale = Vector2(1.0+pop*.25,1.0+pop*.42)
	if refs.has("combo_plate"):
		var lean := pop*18.0
		refs["combo_plate"].polygon = PackedVector2Array([Vector2(70-lean,18-lean*.4),Vector2(250+lean*.4,6-lean*.6),Vector2(236+lean,120+lean*.3),Vector2(40-lean*.4,128+lean*.4)])
		var heat := clampf(float(n)/50.0,0,1)
		refs["combo_plate"].color = Color(color.r*.45,color.g*.3,color.b*.35,.08+heat*.16+pop*.28)
	if refs.has("combo_streak"):
		refs["combo_streak"].color = Color(color.lightened(.4),pop*.8)
		refs["combo_streak"].position.x = -60.0+(1.0-_combo_pop)*90.0
	if refs.has("combo_ghost"):
		var ghost: Label = refs["combo_ghost"]
		ghost.modulate.a = maxf(0.0,ghost.modulate.a-delta*4.0)
		ghost.scale = ghost.scale+Vector2.ONE*delta*(0.0 if reduced else 2.4)
	if refs.has("combo_ring"):
		var ring: Line2D = refs["combo_ring"]
		var b := 1.0-_combo_burst
		ring.scale = Vector2.ONE*(30.0+b*190.0)
		ring.width = 6.0*_combo_burst+1.0
		ring.default_color = Color(color.lightened(.3),_combo_burst*(.4 if reduced else .9))
	if refs.has("combo_bar"):
		var bar: ColorRect = refs["combo_bar"]
		var left := clampf(float(state.get("combo_left",0)),0,1)
		# The meter flares white on each hit and pulses red when about to drop.
		bar.color = color.lerp(Color.WHITE,pop*.8)
		if left < .3 and n >= 2: bar.color = bar.color.lerp(Color("ff4a3a"),.5+.5*sin(t*24.0))
		bar.size.y = 4.0+pop*4.0
	for s in _combo_sparks:
		if float(s.life) <= 0:
			s.node.color.a = 0.0
			continue
		s.life = float(s.life)-delta
		s.vel = s.vel*exp(-delta*5.0)+Vector2(0,420)*delta
		s.node.position += s.vel*delta
		s.node.rotation = s.vel.angle()
		s.node.color = Color(color.lightened(.5),clampf(float(s.life)*3.0,0,1)*(0.0 if reduced else 1.0))


func _build_inventory() -> void:
	var veil := _box(scene_ui,Rect2(0,0,1440,900),Color(.005,.015,.025,.25))
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_build_overview()
	var panel := _cut(scene_ui,Rect2(938,154,466,543),Color(.018,.045,.063,.97),LINE,CYAN)
	_label(panel,"本次收获",Rect2(30,24,360,39),28,WHITE)
	_button(panel,"×",Rect2(389,25,42,32),"close",null,MUTED)
	var items: Array = state.get("bag",[])
	_label(panel,"已自动收纳 %d 件  /  %s CR" % [int(state.get("loot_count",items.size())),_number(int(state.get("bag_value",0)))],Rect2(30,73,400,25),15,ORANGE)
	_label(panel,"无限携行 · 成功撤离后存入仓库",Rect2(30,106,400,22),12,MUTED)
	_line(panel,30,145,400)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30,165)
	scroll.size = Vector2(400,298)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	var grouped: Dictionary = {}
	for item in items:
		var id: String = str(item.get("id",""))
		if not grouped.has(id): grouped[id] = {"item":item,"count":0}
		grouped[id].count += 1
	for id in grouped:
		var item: Dictionary = grouped[id].item
		var count: int = grouped[id].count
		var color := _item_color(item)
		var row := Control.new()
		row.custom_minimum_size = Vector2(385,76)
		list.add_child(row)
		_cut(row,Rect2(0,0,385,76),Color(color.darkened(.86),.9),Color(color,.25))
		_glyph(row,_item_icon(item),Vector2(12,12),43,color)
		_label(row,str(item.get("name","物资"))+"  ×"+str(count),Rect2(68,10,227,27),17,color)
		_label(row,"%d CR" % (int(item.get("value",0))*count),Rect2(280,13,88,23),12,ORANGE,HORIZONTAL_ALIGNMENT_RIGHT)
		_label(row,_bonus_text(item) if item.has("slot") else "已回收 / 等待撤离",Rect2(68,44,300,22),11,MUTED)
	if items.is_empty():
		var empty := Label.new()
		empty.text = "清空战区后，战利品会自动收纳。"
		empty.custom_minimum_size = Vector2(380,190)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color",MUTED)
		list.add_child(empty)
	_line(panel,30,483,400)
	_label(panel,"无需整理，不占操作时间。   TAB / ESC 关闭",Rect2(30,497,400,25),12,CYAN)

func request_skill_choice(id: String) -> void:
	if current_mode != "skills" or _choice_busy: return
	var index := -1
	var offers: Array = state.get("choices",[])
	for i in mini(offers.size(),3):
		if str(offers[i].get("id","")) == id: index = i; break
	if index < 0: return
	var card: Control = refs.get("boon_card_"+str(index))
	if not is_instance_valid(card): return
	_choice_busy = true
	var generation := _choice_generation
	if not card.revealed: await card.reveal_finished
	if generation != _choice_generation or not _live_control(card): return
	if bool(state.get("motion_reduced",false)):
		action.emit("skill",id)
		return
	for i in mini(offers.size(),3):
		var other: Control = refs.get("boon_card_"+str(i))
		if is_instance_valid(other):
			other.selectable = false
			refs["boon_choose_"+str(i)].disabled = true
	card.press_feedback()
	await get_tree().process_frame
	if generation != _choice_generation or not _live_control(card): return
	RenderingServer.force_draw()
	var snapshot: Texture2D = null
	if DisplayServer.get_name() != "headless" and not preload("res://scripts/quality.gd").low():
		var screen: Image = get_viewport().get_texture().get_image()
		if screen != null and not screen.is_empty():
			# Control coordinates use the logical viewport; the captured image uses
			# render pixels. Apply both the canvas transform and viewport stretch.
			var viewport_rect: Rect2 = card.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,card.size)
			var pixel_scale := Vector2(screen.get_size())/get_viewport().get_visible_rect().size
			var pixel_start := (viewport_rect.position*pixel_scale).ceil()
			var pixel_end := (viewport_rect.end*pixel_scale).floor()
			var rect := Rect2i(Vector2i(pixel_start),Vector2i(pixel_end-pixel_start))
			rect = rect.intersection(Rect2i(Vector2i.ZERO,screen.get_size()))
			if rect.size.x > 8 and rect.size.y > 8: snapshot = ImageTexture.create_from_image(screen.get_region(rect))
	var dissolve := CardDissolve.new()
	# Preserve the clicked card's hover/press transform and parent coordinates.
	var local_rect: Rect2 = card.get_transform()*Rect2(Vector2.ZERO,card.size)
	dissolve.position = local_rect.position
	dissolve.size = local_rect.size
	dissolve.snapshot = snapshot
	dissolve.accent = card.tint
	card.get_parent().add_child(dissolve)
	card.visible = false
	for i in mini(offers.size(),3):
		if i == index: continue
		var other: Control = refs.get("boon_card_"+str(i))
		if is_instance_valid(other):
			other.create_tween().tween_property(other,"modulate:a",.16,.24)
	await get_tree().create_timer(CardDissolve.LIFETIME).timeout
	if generation == _choice_generation and current_mode == "skills": action.emit("skill",id)


func _build_skills() -> void:
	_box(scene_ui,Rect2(0,0,1440,900),Color(.005,.015,.026,.84)).mouse_filter = Control.MOUSE_FILTER_STOP
	var choices: Array = state.get("choices",[])
	var is_hammer: bool = not choices.is_empty() and str(choices[0].get("type","")) == "hammer"
	_label(scene_ui,"武 器 重 构" if is_hammer else "选 择 祝 福",Rect2(420,57,600,55),38,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
	_label(scene_ui,"选择一项改造，重塑武器招式" if is_hammer else "来自诸神的力量 · 本次行动生效",Rect2(290,118,860,27),15,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	var total: int = mini(choices.size(),3)
	var start := (1440.0-total*352-(total-1)*28)/2.0
	for i in range(total):
		var choice: Dictionary = choices[i]
		var c := _color(choice.get("color",CYAN))
		var panel := BoonCardArt.new()
		panel.position = Vector2(start+i*380,166)
		panel.size = Vector2(352,620)
		panel.configure(choice,bool(state.get("motion_reduced",false)))
		scene_ui.add_child(panel)
		panel.activated.connect(func():
			if _live_control(panel): _dispatch("skill",str(choice.get("id","power")))
		)
		refs["boon_card_"+str(i)] = panel
		_box(panel,Rect2(23,23,35,35),Color(.025,.04,.055,.9),Color(c,.7))
		_label(panel,str(i+1),Rect2(23,22,35,36),22,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
		var god := _god_names(choice)
		var type_name: String = {"hammer":"锤子改造","core":"核心祝福","support":"衍生祝福","duo":"双重祝福"}.get(str(choice.get("type","")),"共鸣强化")
		_box(panel,Rect2(192,25,136,29),Color(.025,.04,.055,.87),Color(c,.35))
		_label(panel,_rarity(choice)+" / Lv.%d" % int(choice.get("level",1)),Rect2(197,25,126,29),12,c,HORIZONTAL_ALIGNMENT_CENTER)
		_label(panel,god if not god.is_empty() else type_name,Rect2(24,208,304,28),16,WHITE)
		var slot: String = str(choice.get("slot","passive"))
		var icon: String = {"attack":"spear","special":"throw","dash":"dash"}.get(slot,"core")
		_glyph(panel,icon,Vector2(22,261),25,c)
		_label(panel,type_name+" / "+("武器招式" if is_hammer else _boon_slot(slot)),Rect2(56,262,272,24),12,c)
		_label(panel,str(choice.get("name","强化")),Rect2(22,297,308,40),26,WHITE)
		var desc := str(choice.get("desc",""))
		refs["boon_desc_"+str(i)] = _paragraph(panel,desc,Rect2(22,351,308,129),14 if desc.length() > 110 else 15,WHITE)
		_line(panel,22,492,308,Color(c,.25))
		_paragraph(panel,_choice_note(choice),Rect2(22,507,308,35),12,ORANGE if _choice_note(choice).begins_with("替换") else MUTED)
		var button := _button(panel,"选择强化   [ %d ]" % (i+1),Rect2(22,562,308,39),"skill",str(choice.get("id","power")),c,true)
		button.add_theme_font_size_override("font_size",15)
		button.button_down.connect(func():
			if _live_control(panel): panel.press_feedback()
		)
		button.mouse_entered.connect(func(): panel.hovered = true)
		button.focus_entered.connect(func(): panel.hovered = true)
		button.focus_exited.connect(func(): panel.hovered = false)
		refs["boon_choose_"+str(i)] = button
		panel.landed.connect(func():
			if _live_control(panel): card_landed.emit(panel.rarity)
		)
		panel.start_reveal(float(i)*.14)
	_label(scene_ui,"点击卡牌或按 1 / 2 / 3 选择",Rect2(300,816,840,25),12,MUTED,HORIZONTAL_ALIGNMENT_CENTER)


func _build_build_overview() -> void:
	var panel := _cut(scene_ui,Rect2(390,154,526,543),Color(.018,.045,.063,.97),LINE,ORANGE)
	_label(panel,"构筑总览",Rect2(30,24,460,39),28,WHITE)
	var boons: Array = state.get("boons",[])
	var summary := "主动长矛  /  %d 项强化  /  锤子 × %d" % [boons.size(),int(state.get("hammer_count",0))] if _family() == "spear" else "射击飞剑  /  %d 项强化" % boons.size()
	_label(panel,summary,Rect2(30,75,466,25),14,ORANGE)
	_line(panel,30,116,466)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30,137)
	scroll.size = Vector2(466,360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	refs["build_scroll"] = scroll
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",8)
	scroll.add_child(list)
	var entries: Array = []
	for slot in ["attack","special","dash"]:
		if _family() == "flying" and slot == "special": continue
		var boon: Dictionary = state.get("boon_slots",{}).get(slot,{}).duplicate(true)
		if boon.is_empty(): boon = {"name":_boon_slot(slot)+" / 未赋予祝福","desc":"选择对应槽位的神祇祝福后显示效果。","slot":slot,"empty":true}
		entries.append(boon)
	for boon in boons:
		if str(boon.get("slot","")) not in ["attack","special","dash"] or str(boon.get("type","")) == "hammer": entries.append(boon)
	for boon in entries:
		var c := _color(boon.get("color",MUTED))
		var active: bool = bool(boon.get("active",true))
		if not active: c = MUTED.darkened(.2)
		var row := Control.new()
		var height := 119.0 if boon.get("empty",false) else 146.0
		row.custom_minimum_size = Vector2(451,height)
		list.add_child(row)
		_cut(row,Rect2(0,0,451,height),Color(c.darkened(.88),.9),Color(c,.3))
		_label(row,str(boon.get("name","强化")),Rect2(17,10,417,28),18,c)
		_label(row,"前置已替换 / 当前不生效" if not active else (_boon_slot(str(boon.get("slot",""))) if boon.get("empty",false) else _boon_meta(boon)),Rect2(17,43,417,21),10,ORANGE if not active else MUTED)
		_paragraph(row,str(boon.get("desc","")),Rect2(17,73,417,height-82),12,MUTED if not active else WHITE)
	_label(panel,"祝福槽位互相替换，锤子改造持续叠加。" if _family() == "spear" else "飞剑共鸣与神祇祝福共同生效。",Rect2(30,508,466,21),11,MUTED)


func _build_gate() -> void:
	_box(scene_ui, Rect2(0, 0, 1440, 900), Color(0.005, 0.015, 0.026, 0.77)).mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := _cut(scene_ui, Rect2(375, 174, 690, 552), PANEL, CYAN.darkened(0.25),CYAN)
	var dungeon: Dictionary = state.get("dungeon",{})
	var stage := int(dungeon.get("floor",state.get("stage", 1)))
	_label(panel, "首领已击败  /  撤离通道已开启" if not dungeon.is_empty() else "SECTOR CLEARED  /  回收窗口已开启", Rect2(34, 24, 622, 26), 13, CYAN)
	refs["gate_title"] = _label(panel, ("第 %02d 层  探索完成" if not dungeon.is_empty() else "第 %02d 区  已肃清") % stage, Rect2(34, 73, 622, 60), 38, WHITE)
	refs["gate_note"] = _paragraph(panel, "本层首领已击败，战利品已自动回收。\n下一层将出现更强的敌人与首领；撤离可保住本次全部收获。" if not dungeon.is_empty() else "战利品已自动回收。接下来由你决定。\n继续深入会遇到更强的守卫，也有机会获得更高品质的装备。", Rect2(34, 154, 622, 62), 17, MUTED)
	_line(panel, 34, 235, 622)
	_label(panel, "当前携行价值", Rect2(34, 259, 290, 26), 14, MUTED)
	_label(panel, "%s CR" % _number(int(state.get("bag_value", 0))), Rect2(34, 298, 290, 43), 31, ORANGE)
	_label(panel, "已回收战利品", Rect2(376, 259, 280, 26), 14, MUTED)
	_label(panel, "%d 件" % int(state.get("loot_count",state.get("bag",[]).size())), Rect2(376, 298, 280, 43), 29, WHITE)
	_line(panel, 34, 366, 622)
	_label(panel, "战利品只有撤离后才会存入仓库", Rect2(34, 387, 622, 25), 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_button(panel, ("继续深入  →  第 %02d 层" if not dungeon.is_empty() else "继续深入  →  第 %02d 区") % (stage + 1), Rect2(34, 434, 302, 56), "next_stage", null, CYAN).add_theme_font_size_override("font_size", 18)
	_button(panel, "立 即 撤 离", Rect2(350, 434, 306, 56), "extract", null, ORANGE, true).add_theme_font_size_override("font_size", 20)
	_button(panel, "暂留战区   /   ESC", Rect2(180, 507, 330, 28), "close", null, MUTED).add_theme_font_size_override("font_size", 12)


func _build_result() -> void:
	_box(scene_ui, Rect2(0, 0, 1440, 900), Color(0.005, 0.015, 0.026, 0.85)).mouse_filter = Control.MOUSE_FILTER_STOP
	var r: Dictionary = state.get("result", {})
	var success: bool = bool(r.get("success", false))
	var c := CYAN if success else RED
	var panel := _cut(scene_ui, Rect2(390, 140, 660, 619), PANEL, c.darkened(0.35),c)
	_label(panel, "MISSION REPORT  /  行动结算", Rect2(42, 31, 576, 27), 13, c)
	_label(panel, "撤离成功" if success else "信号中断", Rect2(42, 81, 576, 68), 46, WHITE)
	_paragraph(panel, "战利品已存入补给站仓库。欢迎回来，回收员。" if success else "本次收获遗失在现场。重新整备，再次出发。", Rect2(42, 165, 576, 50), 17, MUTED)
	_line(panel, 42, 231, 576)
	_label(panel, "击破目标", Rect2(42, 253, 180, 26), 14, MUTED)
	_label(panel, str(int(r.get("kills", state.get("kills", 0)))), Rect2(42, 292, 180, 45), 34, WHITE)
	_label(panel, "回收价值" if success else "遗失物资", Rect2(239, 253, 180, 26), 14, MUTED)
	var amount: int = int(r.get("value",0)) if success else _lost_count(r.get("lost",[]))
	refs["result_count"] = _label(panel,_number(amount)+(" CR" if success else " 件"),Rect2(239,292,180,45),27,c)
	_label(panel, "本次时长", Rect2(437, 253, 180, 26), 14, MUTED)
	_label(panel, _clock(float(state.get("time", 0))), Rect2(437, 292, 180, 45), 30, WHITE)
	_line(panel, 42, 358, 576)
	var floor_number := int(state.get("dungeon",{}).get("floor",state.get("stage",1)))
	refs["result_floor"] = _label(panel, (("第 %02d 层撤离  /  回收清单" if not state.get("dungeon",{}).is_empty() else "第 %02d 区撤离  /  回收清单") % floor_number) if success else "第 %02d 层  /  下一次行动" % floor_number, Rect2(42, 382, 576, 26), 16, WHITE)
	var item_count := _lost_count(r.get("items", []))
	_paragraph(panel,("%d 件物资已转入仓库；返回补给站培养英雄、购入装备。" % item_count) if success else "重新整备后可再次出发，基础武器免费可用。\n本次祝福与锤子改造已重置。",Rect2(42,425,576,67),16,MUTED)
	var back := _button(panel,"返 回 补 给 站    [ ENTER ]",Rect2(42,530,576,56),"hub",null,ORANGE,true)
	back.add_theme_font_size_override("font_size",21)
	call_deferred("_focus_button",back)


func _focus_button(button: Variant) -> void:
	if is_instance_valid(button) and button is Control and _live_control(button) and button.is_visible_in_tree() and button.focus_mode != Control.FOCUS_NONE:
		if not (button is BaseButton and button.disabled): button.grab_focus()


func _lost_count(value: Variant) -> int:
	return value.size() if value is Array else int(value)


func _build_pause() -> void:
	_box(scene_ui, Rect2(0, 0, 1440, 900), Color(0.005, 0.015, 0.026, 0.8)).mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := _cut(scene_ui, Rect2(480, 125, 480, 650), PANEL, LINE,CYAN)
	_label(panel, "行动暂停", Rect2(34, 28, 412, 47), 32, WHITE)
	_label(panel, "STANDBY  /  现场已冻结", Rect2(34, 86, 412, 26), 12, CYAN)
	_line(panel, 34, 132, 412)
	var controls := "左侧拖动  移动\n攻击  连刺/射剑（自动瞄准）；按住蓄力\n投掷  长矛投掷与召回\n冲刺  闪避\n技能 / 绝技  英雄技能\n交互  设施与宝箱   /   背包  构筑与收获" if preload("res://scripts/quality.gd").touch_active else ("WASD / 方向键  移动\nJ / 左键  连刺（自动瞄准附近敌人）；按住蓄力横扫\nK / 右键  投掷长矛，再按召回\nSPACE  冲刺；冲刺时按 J 追击\nQ  修复剂   /   R  消耗能量过载\nE  交互 / 通道   /   TAB  构筑与收获" if _family() == "spear" else "WASD / 方向键  移动\nJ / 左键  射出一柄飞剑（自动瞄准）；剑阵打空后召回\nSPACE  闪避\nQ  修复剂   /   R  消耗能量过载\nE  交互 / 通道\nTAB  构筑与收获")
	if _has_boon("flurry_jab"): controls = controls.replace("连刺；按住蓄力横扫","按住连续快速突刺")
	if _has_boon("charged_skewer"): controls = controls.replace("投掷长矛，再按召回","按住蓄力，松开投出")
	if _has_boon("exploding_launcher"): controls = controls.replace("投掷长矛，再按召回","发射爆炸弹，无需召回").replace("按住蓄力，松开投出","蓄力发射爆炸弹")
	controls = controls.replace("Q  修复剂", "F  "+str(_hero_skill("primary").get("name","主技能"))+"   /   L  "+str(_hero_skill("secondary").get("name","副技能"))+"\nQ  修复剂")
	_paragraph(panel,controls,Rect2(34,149,412,188),14,MUTED)
	_label(panel, "音量", Rect2(34, 343, 100, 29), 14, WHITE)
	var slider := HSlider.new()
	slider.position = Vector2(124, 348)
	slider.size = Vector2(322, 24)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(state.get("volume", 0.6))
	slider.value_changed.connect(func(v: float): action.emit("volume", v))
	panel.add_child(slider)
	var reduced := CheckButton.new()
	reduced.text = "减少动态效果"
	reduced.position = Vector2(34,385)
	reduced.size = Vector2(412,29)
	reduced.button_pressed = bool(state.get("motion_reduced",false))
	reduced.add_theme_font_size_override("font_size",14)
	reduced.toggled.connect(func(value: bool): action.emit("motion_reduced",value))
	panel.add_child(reduced)
	_button(panel, "继续行动", Rect2(34, 436, 412, 51), "resume", null, CYAN, true)
	_button(panel, "放弃行动并返回  /  遗失本次收获", Rect2(34, 501, 412, 46), "abandon", null, RED).add_theme_font_size_override("font_size", 15)
	_button(panel, "退出游戏", Rect2(34, 561, 412, 46), "quit", null, MUTED).add_theme_font_size_override("font_size", 15)


func _build_toast() -> void:
	var rect := Rect2(30,802,490,46) if current_mode == "hub" and not str(state.get("hub_station","")).is_empty() else Rect2(445,111,550,46)
	var bg := _cut(scene_ui,rect,Color(0.025,0.08,0.1,.96),CYAN.darkened(.4))
	refs["toast_bg"] = bg
	refs["toast"] = _label(bg,"",Rect2(16,4,rect.size.x-32,38),15,WHITE,HORIZONTAL_ALIGNMENT_CENTER)
	bg.visible = false


func _update_dungeon() -> void:
	var dungeon: Dictionary = state.get("dungeon",{})
	var map: Control = refs["radar"]
	var enabled := not dungeon.is_empty()
	map.position = Vector2(1192,49) if enabled else Vector2(1260,49)
	map.size = Vector2(206,170) if enabled else Vector2(138,132)
	if enabled:
		refs["zone"].text = "第 %d 层  ·  %s" % [int(dungeon.get("floor",1)),str(dungeon.get("room_name","未知房间"))]
		refs["clear_title"].text = "第 %02d 层  首领击败" % int(dungeon.get("floor",1)) if dungeon.get("boss_defeated",false) else str(dungeon.get("room_name","房间"))+"  已肃清"
		var room_key := "%s:%s" % [dungeon.get("floor",1),dungeon.get("room_id",0)]
		var name_label: Label = refs["zone"]
		if str(name_label.get_meta("room_key","")) != room_key:
			name_label.set_meta("room_key",room_key)
			name_label.set_meta("transition_count",int(name_label.get_meta("transition_count",0))+1)
			var old_tween: Tween = name_label.get_meta("room_tween") if name_label.has_meta("room_tween") else null
			if old_tween != null and old_tween.is_valid(): old_tween.kill()
			name_label.modulate.a = 0
			name_label.set_meta("caption_age",0.0)
			name_label.position.x = ROOM_CAPTION_X
			var tween := name_label.create_tween().set_parallel(true)
			tween.tween_property(name_label,"modulate:a",1.0,.18)
			if not bool(state.get("motion_reduced",false)):
				name_label.position.x += 6
				tween.tween_property(name_label,"position:x",ROOM_CAPTION_X,.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			name_label.set_meta("room_tween",tween)
	var boss: Dictionary = dungeon.get("boss",{})
	var show_boss: bool = enabled and not boss.is_empty() and float(boss.get("hp",0)) > 0 and not dungeon.get("boss_defeated",false) and current_mode not in ["gate","result"]
	var panel: Control = refs["boss_panel"]
	if show_boss and not panel.visible:
		panel.visible = true
		var old_tween: Tween = panel.get_meta("entry_tween") if panel.has_meta("entry_tween") else null
		if old_tween != null and old_tween.is_valid(): old_tween.kill()
		panel.position.y = 105
		panel.modulate.a = 0
		var tween := panel.create_tween().set_parallel(true)
		tween.tween_property(panel,"modulate:a",1.0,.2)
		if not bool(state.get("motion_reduced",false)):
			panel.position.y += 6
			tween.tween_property(panel,"position:y",105.0,.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		panel.set_meta("entry_tween",tween)
		panel.set_meta("entry_count",int(panel.get_meta("entry_count",0))+1)
	elif not show_boss: panel.visible = false
	if show_boss:
		var key := "%s:%s:%s" % [dungeon.get("floor",1),dungeon.get("room_id",0),boss.get("name","")]
		if _boss_key != key:
			_boss_key = key
			_boss_armor_capacity = 0
		var armor := maxf(0,float(boss.get("armor",0)))
		_boss_armor_capacity = maxf(_boss_armor_capacity,armor)
		var maximum_armor := maxf(0,float(boss.get("max_armor",_boss_armor_capacity)))
		refs["boss_meter"].set_values(float(boss.get("hp",0)),float(boss.get("max_hp",1)),armor,maximum_armor)
		refs["boss_name"].text = str(boss.get("name","区域首领"))
		refs["boss_phase"].text = "阶段 %s" % str(boss.get("phase",1))
		refs["boss_attack"].text = str(boss.get("attack",""))
		refs["boss_values"].text = "%d / %d  ·  护甲 %d" % [ceili(refs["boss_meter"].total),ceili(refs["boss_meter"].maximum),ceili(armor)]
	if refs.has("toast_bg"):
		refs["toast_bg"].position.y = 195 if show_boss else 111


func _update_dynamic() -> void:
	if refs.has("credits"): refs.credits.text = "%s CR" % _number(int(state.get("credits",0)))
	if refs.has("talent_tree"):
		var tree = refs.talent_tree
		tree.reduced_motion = bool(state.get("motion_reduced",false))
		tree.refresh(state.get("talent_tree",[]))
	var receipt: Dictionary = state.get("talent_receipt",{})
	var serial := int(receipt.get("serial",0))
	if serial > receipt_seen:
		if refs.has("talent_tree") and str(receipt.get("hero","")) == str(state.get("hero_id","chrono")):
			refs.talent_tree.celebrate(str(receipt.get("node","")))
		receipt_seen = serial
	for key in refs:
		if str(key).begins_with("shop_buy_"): refs[key].disabled = int(state.get("credits",0)) < int(refs[key].get_meta("price",0))
	if refs.has("shop_med"): refs.shop_med.disabled = int(state.get("credits",0)) < 60
	if refs.has("toast"):
		var text: String = str(state.get("toast",""))
		refs["toast"].text = text
		refs["toast_bg"].visible = not text.is_empty() and current_mode not in ["skills","result","pause"]
	if refs.has("hub_prompt"):
		var prompt: String = str(state.get("prompt", ""))
		refs["hub_prompt"].text = prompt if not prompt.is_empty() else ("靠近设施  ·  点「交互」" if preload("res://scripts/quality.gd").touch_active else "靠近设施  ·  按 E 交互")
	if not refs.has("health_meter"):
		return
	var hp := float(state.get("hp",100))
	var maximum := maxf(1,float(state.get("max_hp",100)))
	refs["health_text"].text = "%d / %d" % [ceili(hp),int(maximum)]
	refs["health_text"].add_theme_color_override("font_color",RED if hp < maximum*.25 else WHITE)
	refs["shield_meter"].ratio = minf(float(state.get("shield",0))/50.0,1)
	refs["shield_meter"].trail = refs["shield_meter"].ratio
	refs["shield_meter"].queue_redraw()
	var dash := float(state.get("dash_cd",0))
	var mana := float(state.get("mana",100))
	var max_mana := maxf(1,float(state.get("max_mana",100)))
	refs["mana_meter"].ratio = clampf(mana/max_mana,0,1)
	refs["mana_meter"].trail = refs["mana_meter"].ratio
	refs["mana_meter"].queue_redraw()
	refs["zone"].text = str(state.get("zone","中继战区"))
	refs["clear_title"].text = "第 %02d 区  肃 清" % int(state.get("stage",1))
	_update_dungeon()
	_update_combo()
	var charges := int(state.get("dash_charges",1 if dash <= 0 else 0))
	var cd := {"melee":float(state.get("melee_cd",0)),"special":float(state.get("special_cd",0)),"dash":dash if charges == 0 else 0.0}
	for id in cd:
		if not refs.has("tile_"+id): continue
		refs["tile_"+id].cooldown = cd[id]
		refs["cool_"+id].text = "%.1f" % cd[id] if cd[id] >= .7 and id != "melee" else ""
		refs["icon_"+id].modulate.a = .28 if cd[id] >= .7 and id != "melee" else 1.0
	if refs.has("blade_pips"):
		var pips: BladePips = refs["blade_pips"]
		pips.total = int(state.get("blades_total",0))
		pips.loaded = int(state.get("blades_ready",0))
		pips.tint = CYAN
		pips.queue_redraw()
		var bs := str(state.get("blades_state","ready"))
		refs["blade_hint"].text = {"empty":"剑阵已空 · 点攻击召回" if preload("res://scripts/quality.gd").touch_active else "剑阵已空 · 按 J 召回","recall":"召回中……"}.get(bs,("射剑  %d / %d" if preload("res://scripts/quality.gd").touch_active else "J 射剑  %d / %d") % [pips.loaded,pips.total])
		refs["blade_hint"].add_theme_color_override("font_color",ORANGE if bs == "empty" else MUTED)
	var spear: String = str(state.get("spear_state","idle"))
	var charge := clampf(float(state.get("charge_ratio",0)),0,1)
	var special: String = str(state.get("special_state","idle"))
	if refs.has("tile_melee"):
		var attack_hint := "按住疾风突刺" if _has_boon("flurry_jab") else "连刺 · 长按横扫"
		refs["name_melee"].text = {"charge":"蓄力横扫 %d%%" % roundi(charge*100),"charging":"蓄力横扫 %d%%" % roundi(charge*100),"spin":"环身横扫","dash_strike":"冲刺追击","thrust":"疾风连刺" if _has_boon("flurry_jab") else "长矛连刺"}.get(spear,attack_hint)
		refs["tile_melee"].progress = charge if spear in ["charge","charging"] else float(state.get("melee_progress",0))
		var special_hint := "长按 K 蓄力投掷" if _has_boon("charged_skewer") else "投掷 / 召回"
		if _has_boon("exploding_launcher"): special_hint = "蓄力爆破投掷" if _has_boon("charged_skewer") else "爆破投掷"
		refs["name_special"].text = {"outbound":"爆破弹飞行中" if _has_boon("exploding_launcher") else "飞行中 · 可召回","lodged":"再次按 K 召回","returning":"召回中"}.get(special,special_hint)
		if spear == "special_charge": refs["name_special"].text = "蓄力投掷 %d%%" % roundi(charge*100)
		refs["tile_special"].progress = charge if spear == "special_charge" else (1.0 if special == "lodged" else 0.0)
	refs["name_dash"].text = "冲刺  × %d" % charges
	for slot in ["primary","secondary"]:
		var skill := _hero_skill(slot)
		var cost := float(skill.get("cost",0))
		var remaining := float(skill.get("cd",0))
		var tile: AbilityTile = refs["tile_"+slot]
		tile.cooldown = remaining
		tile.duration = float(skill.get("cooldown",1))
		var active := bool(skill.get("active",false))
		var color := tile.tint if mana >= cost or active else MUTED
		refs["name_"+slot].add_theme_color_override("font_color",color)
		refs["icon_"+slot].modulate.a = 1.0 if active or (remaining <= 0 and mana >= cost) else .32
		refs["cool_"+slot].text = "%.1f" % remaining if remaining > 0 else ("就绪" if mana >= cost else "不足")
		refs["cool_"+slot].add_theme_color_override("font_color",tile.tint if active else WHITE)
		refs["name_"+slot].text = "%s 能量%s" % [_decimal(cost)," · 不足" if mana < cost else ""]
		tile.progress = 0
		if active:
			var left := float(skill.get("left",0))
			refs["cool_"+slot].text = "%.1fs" % left
			refs["name_"+slot].text = "技 能 生 效 中"
			tile.progress = left/maxf(.01,float(skill.get("duration",1)))
			if str(skill.get("id","")) == "rush":
				refs["cool_"+slot].text = "× %d" % int(skill.get("hits",0))
				refs["name_"+slot].text = "疾冲中 · 已命中"
			elif str(skill.get("id","")) == "prism_guard":
				refs["name_"+slot].text = "护盾 %s" % _decimal(float(skill.get("shield",0)))
	refs["prompt"].text = str(state.get("prompt",""))
	refs["radar"].data = state.get("minimap",{})
	refs["radar"].queue_redraw()
	var feeds: Array = state.get("pickup_feed",[])
	for i in range(4):
		var row: Control = refs["feed_"+str(i)]
		row.visible = i < feeds.size() and current_mode == "raid"
		if i < feeds.size():
			var item: Dictionary = feeds[i]
			var color := _item_color(item)
			refs["feed_icon_"+str(i)].kind = _item_icon(item)
			refs["feed_icon_"+str(i)].tint = color
			refs["feed_icon_"+str(i)].queue_redraw()
			refs["feed_text_"+str(i)].text = "+  " + str(item.get("name","战利品"))
			refs["feed_text_"+str(i)].add_theme_color_override("font_color",color)

func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _number(n: int) -> String:
	var text := str(n)
	var result := ""
	for i in range(text.length()):
		if i > 0 and (text.length() - i) % 3 == 0:
			result += ","
		result += text[i]
	return result


