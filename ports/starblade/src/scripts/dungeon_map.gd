extends Control
## A world-coordinate room map. Hidden rooms never produce render primitives.
const CYAN := Color("73eceb")
const GOLD := Color("f5ac61")
const MUTED := Color("547783")
var data: Dictionary = {}

func visible_rooms() -> Array:
	var result: Array = []
	for room in data.get("rooms",[]):
		if room is Dictionary and bool(room.get("discovered",room.get("visited",false))): result.append(room)
	return result

func visible_links() -> Array:
	var ids: Array = []
	for room in visible_rooms(): ids.append(room.get("id",-1))
	var result: Array = []
	for link in data.get("links",[]):
		if link is Dictionary and ids.has(link.get("a",-2)) and ids.has(link.get("b",-2)): result.append(link)
	return result

func known_position(point: Vector2,current_only: bool = false) -> bool:
	if data.get("rooms",[]).is_empty(): return true
	for room in visible_rooms():
		if not bool(room.get("current",false) if current_only else room.get("visited",false)): continue
		var rect: Rect2 = room.get("rect",Rect2())
		if rect.has_point(point): return true
	return false

func visible_enemies() -> Array:
	var result: Array = []
	for point in data.get("enemies",[]):
		if point is Vector2 and known_position(point,true): result.append(point)
	return result

func bounds() -> Rect2:
	var rect: Rect2 = data.get("bounds",Rect2())
	if rect.size.x > 0 and rect.size.y > 0: return rect
	var rooms := visible_rooms()
	if rooms.is_empty(): return Rect2(-24,-28,48,52)
	rect = rooms[0].get("rect",Rect2(-1,-1,2,2))
	for room in rooms: rect = rect.merge(room.get("rect",rect))
	return rect.grow(4)

func project(point: Vector2) -> Vector2:
	var world := bounds()
	var scale_factor := minf((size.x-24)/maxf(1,world.size.x),(size.y-24)/maxf(1,world.size.y))
	return size*.5+(point-world.get_center())*scale_factor

func project_rect(rect: Rect2) -> Rect2:
	return Rect2(project(rect.position),project(rect.end)-project(rect.position))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.018,.038,.058,.86))
	draw_line(Vector2(0,0),Vector2(size.x,0),Color(CYAN,.32),1)
	draw_line(Vector2(0,size.y-1),Vector2(size.x,size.y-1),Color(CYAN,.15),1)
	for x in range(16,int(size.x),20):
		for y in range(14,int(size.y),20): draw_circle(Vector2(x,y),.7,Color(CYAN,.08))
	var rooms := visible_rooms()
	if not data.get("rooms",[]).is_empty():
		for link in visible_links():
			var rect: Rect2 = link.get("corridor",Rect2())
			if rect.has_area(): draw_rect(project_rect(rect),Color("263f4b"))
		for room in rooms:
			var rect := project_rect(room.get("rect",Rect2()))
			var current := bool(room.get("current",false))
			var visited := bool(room.get("visited",false))
			var cleared := bool(room.get("cleared",false))
			var color := CYAN if current else (Color("a5bdc4") if visited else MUTED)
			if current: draw_rect(rect.grow(2),Color(CYAN,.09))
			draw_rect(rect,Color("193c46") if current else Color("14272f") if visited else Color("08141e"))
			draw_rect(rect,color if current else Color(color,.65),false,1.6 if current else 1.0)
			_room_icon(str(room.get("kind","combat")),rect.get_center(),color if visited else color.darkened(.1))
			if cleared:
				var p := rect.end-Vector2(6,5)
				draw_polyline(PackedVector2Array([p+Vector2(-4,-2),p+Vector2(-1,1),p+Vector2(4,-5)]),CYAN,1.4,true)
	else:
		draw_rect(Rect2(Vector2(12,12),size-Vector2(24,24)),Color(MUTED,.6),false,1)
	for point in data.get("containers",[]):
		if point is Vector2 and known_position(point): draw_rect(Rect2(project(point)-Vector2(1.5,1.5),Vector2(3,3)),GOLD)
	for point in visible_enemies(): draw_circle(project(point),2,Color("ff766c"))
	for exit in data.get("extracts",[]):
		var point: Vector2 = exit.get("pos",Vector2.ZERO)
		if known_position(point):
			var color := GOLD if exit.get("locked",false) else CYAN
			draw_rect(Rect2(project(point)-Vector2(3.5,3.5),Vector2(7,7)),color,false,1.5)
	if data.has("terminal") and data.terminal is Vector2 and known_position(data.terminal):
		var p := project(data.terminal)
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-3),p+Vector2(3,0),p+Vector2(0,3),p+Vector2(-3,0)]),Color("cbb3ff"))
	if data.has("player") and data.player is Vector2:
		var p := project(data.player)
		draw_circle(p,6,Color(CYAN,.16))
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(3,3),p+Vector2(0,1.5),p+Vector2(-3,3)]),Color("edffff"))

func _room_icon(kind: String,at: Vector2,color: Color) -> void:
	match kind:
		"boss":
			var p := PackedVector2Array([at+Vector2(-5,-3),at+Vector2(-3,3),at+Vector2(3,3),at+Vector2(5,-3),at+Vector2(1,0),at+Vector2(0,-4),at+Vector2(-1,0)])
			draw_polyline(p+PackedVector2Array([p[0]]),GOLD,1.2,true)
		"treasure","reward","cache":
			draw_rect(Rect2(at-Vector2(4,3),Vector2(8,6)),GOLD,false,1.2)
			draw_line(at+Vector2(-4,-.5),at+Vector2(4,-.5),GOLD,1)
		"rest","heal","supply":
			draw_line(at+Vector2(-3,0),at+Vector2(3,0),color,2)
			draw_line(at+Vector2(0,-3),at+Vector2(0,3),color,2)
		"elite":
			draw_polyline(PackedVector2Array([at+Vector2(0,-4),at+Vector2(4,0),at+Vector2(0,4),at+Vector2(-4,0),at+Vector2(0,-4)]),GOLD,1.2,true)
		"entry","start":
			draw_arc(at,3,.1,TAU,12,color,1.2,true)
		_:
			draw_circle(at,1.5,Color(color,.65))
