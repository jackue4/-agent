extends RefCounted
## Pure deterministic encounter data. Geometry and locks are owned by world.gd.
const CELLS := [Vector2i(0,2),Vector2i(0,1),Vector2i(0,0),Vector2i(-1,1),Vector2i(1,1),Vector2i(2,1),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,-2)]
const KINDS := ["entry","combat","combat","treasure","elite","treasure","rest","combat","boss"]
const NAMES := ["登陆气闸","断电车间","中继枢纽","封存货仓","警戒熔炉","高能储藏室","修复静室","核心前厅","主控熔心"]
const EDGES := [Vector2i(0,1),Vector2i(1,2),Vector2i(1,3),Vector2i(1,4),Vector2i(4,5),Vector2i(2,6),Vector2i(6,4),Vector2i(2,7),Vector2i(7,8)]
const CORRIDOR_WIDTH := 8.0

static func build(floor_number: int) -> Dictionary:
	var depth := maxi(1,floor_number)
	if (depth-1)%5 == 1: return _desert(depth)
	var mirror := -1.0 if depth%2 == 0 else 1.0
	var rooms: Array = []
	var links: Array = []
	var walkable: Array[Rect2] = []
	var bounds := Rect2()
	for id in CELLS.size():
		var center := Vector3(CELLS[id].x*36.0*mirror,0,CELLS[id].y*32.0)
		var size := Vector2(32,26) if KINDS[id] == "boss" else Vector2(28,24)
		var rect := Rect2(Vector2(center.x,center.z)-size*.5,size)
		var room := {"id":id,"kind":KINDS[id],"name":NAMES[id],"rect":rect,"center":center,"neighbors":[],"waves":[],"breakables":[],"covers":[],"cleared":false}
		if KINDS[id] in ["combat","elite"]:
			room.covers = [{"pos":center+Vector3(-8*mirror,0,-3),"size":Vector3(2.4,1.2,1.8)},{"pos":center+Vector3(8*mirror,0,3),"size":Vector3(1.8,1.45,2.4)}]
			# Floors rotate through cover patterns so rooms read differently per depth.
			match (depth+id)%3:
				1:
					for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
						room.covers.append({"pos":center+Vector3(corner.x*4.6,0,corner.y*3.6),"size":Vector3(.9,2.4,.9),"style":"pillar"})
				2:
					room.covers.append({"pos":center+Vector3(-2.8*mirror,0,-3.2),"size":Vector3(3.2,.9,.7),"style":"barrier"})
					room.covers.append({"pos":center+Vector3(2.8*mirror,0,3.2),"size":Vector3(3.2,.9,.7),"style":"barrier"})
		elif KINDS[id] == "boss":
			room.covers = [{"pos":center+Vector3(-11,0,0),"size":Vector3(2,1.1,2)},{"pos":center+Vector3(11,0,0),"size":Vector3(2,1.1,2)}]
		room.waves = _waves(id,depth,center,mirror)
		var prop_offsets := [Vector3(-10,0,-6.5),Vector3(10,0,6.5),Vector3(-10,0,6.5),Vector3(10,0,-6.5)]
		var prop_count := 2 if KINDS[id] in ["entry","rest"] else 4
		for i in prop_count:
			var offset: Vector3 = prop_offsets[i]; offset.x *= mirror
			room.breakables.append({"pos":center+offset,"kind":"crate" if i%2 == 0 else "canister"})
		rooms.append(room); walkable.append(rect)
		bounds = rect if id == 0 else bounds.merge(rect)
	for edge in EDGES:
		var a: Dictionary = rooms[edge.x]; var b: Dictionary = rooms[edge.y]
		a.neighbors.append(edge.y); b.neighbors.append(edge.x)
		var corridor: Rect2
		if is_equal_approx(a.center.x,b.center.x):
			var north: Rect2 = a.rect if a.center.z < b.center.z else b.rect
			var south: Rect2 = b.rect if a.center.z < b.center.z else a.rect
			corridor = Rect2(a.center.x-CORRIDOR_WIDTH*.5,north.end.y,CORRIDOR_WIDTH,south.position.y-north.end.y)
		else:
			var west: Rect2 = a.rect if a.center.x < b.center.x else b.rect
			var east: Rect2 = b.rect if a.center.x < b.center.x else a.rect
			corridor = Rect2(west.end.x,a.center.z-CORRIDOR_WIDTH*.5,east.position.x-west.end.x,CORRIDOR_WIDTH)
		links.append({"a":edge.x,"b":edge.y,"corridor":corridor})
		walkable.append(corridor)
	return {"dungeon":true,"floor":depth,"spawn":rooms[0].center+Vector3(0,0,5),"bounds":bounds,"rooms":rooms,"links":links,"walkable":walkable,"enemies":[],"breakables":[],"containers":[],"terminal":Vector3.ZERO,"extracts":[{"pos":rooms[8].center+Vector3(0,0,-9),"name":"熔心升降梯","locked":true,"room_id":8}]}

static func _waves(id: int, depth: int, center: Vector3, mirror: float) -> Array:
	var kind: String = KINDS[id]
	if kind == "boss":
		return [[{"pos":center+Vector3(0,0,-4),"kind":"boss"},{"pos":center+Vector3(-7,0,4),"kind":"gunner"},{"pos":center+Vector3(7,0,4),"kind":"scout"}]]
	if not kind in ["combat","elite"]: return []
	var result: Array = []
	var waves := 2 if kind == "elite" or depth >= 2 else 1
	var count := mini(8,(5 if kind == "elite" else 4+id%2)+depth-1)
	var offsets := [Vector3(-8,0,-5),Vector3(8,0,-5),Vector3(-7,0,5),Vector3(7,0,5),Vector3(0,0,-7),Vector3(0,0,6),Vector3(-4,0,0),Vector3(4,0,0)]
	for wave_index in waves:
		var enemies: Array = []
		for i in count:
			var offset: Vector3 = offsets[(i+wave_index*2)%offsets.size()]; offset.x *= mirror
			var enemy_kind := "scout"
			if kind == "elite" and i == 0: enemy_kind = "elite"
			elif i%3 == 1: enemy_kind = "gunner"
			elif i%4 == 3 and depth >= 2: enemy_kind = "sniper"
			enemies.append({"pos":center+offset,"kind":enemy_kind})
		result.append(enemies)
	return result

static func _desert(depth: int) -> Dictionary:
	# Broad shrine courts, a raised north approach and an optional western loop.
	var points := [Vector2(0,64),Vector2(0,30),Vector2(0,-8),Vector2(36,30),Vector2(-36,30),Vector2(-72,30),Vector2(-36,-8),Vector2(0,-46),Vector2(0,-84)]
	var sizes := [Vector2(26,24),Vector2(32,28),Vector2(34,30),Vector2(26,24),Vector2(28,26),Vector2(26,24),Vector2(28,26),Vector2(28,26),Vector2(34,30)]
	var heights := [0.0,.6,1.2,.6,.6,1.2,1.2,1.8,2.4]
	var names := ["风沙山门","日晷前庭","流沙祭庭","东翼藏室","残柱武场","落日宝库","棕榈泉庭","登神阶廊","埋日圣殿"]
	var rooms: Array = []; var links: Array = []; var walkable: Array[Rect2] = []
	var bounds := Rect2()
	for id in 9:
		var center := Vector3(points[id].x,heights[id],points[id].y)
		var rect := Rect2(points[id]-sizes[id]*.5,sizes[id])
		var room := {"id":id,"kind":KINDS[id],"name":names[id],"rect":rect,"center":center,"elevation":heights[id],"neighbors":[],"waves":_waves(id,depth,center,-1.0),"breakables":[],"covers":[],"cleared":false}
		if KINDS[id] in ["combat","elite","boss"]:
			# Fallen masonry holds the flanks; both central cross axes stay open.
			for sign_value in [-1.0,1.0]:
				room.covers.append({"pos":center+Vector3(sign_value*10.5,0,-sign_value*2.5),"size":Vector3(2.2,1.1,1.5),"style":"ruin"})
		for i in (2 if KINDS[id] in ["entry","rest"] else 4):
			var offsets := [Vector3(-10,0,-8.5),Vector3(10,0,8.5),Vector3(-10,0,8.5),Vector3(10,0,-8.5)]
			room.breakables.append({"pos":center+offsets[i],"kind":"urn"})
		rooms.append(room); walkable.append(rect)
		bounds = rect if id == 0 else bounds.merge(rect)
	for edge in EDGES:
		var a: Dictionary = rooms[edge.x]; var b: Dictionary = rooms[edge.y]
		a.neighbors.append(edge.y); b.neighbors.append(edge.x)
		var vertical := is_equal_approx(a.center.x,b.center.x)
		var start: Dictionary = (a if a.center.z < b.center.z else b) if vertical else (a if a.center.x < b.center.x else b)
		var end: Dictionary = b if start.id == a.id else a
		var corridor := Rect2(a.center.x-4,start.rect.end.y,8,end.rect.position.y-start.rect.end.y) if vertical else Rect2(start.rect.end.x,a.center.z-4,end.rect.position.x-start.rect.end.x,8)
		links.append({"a":edge.x,"b":edge.y,"corridor":corridor,"vertical":vertical,"height_start":start.elevation,"height_end":end.elevation,"steps":6})
		walkable.append(corridor)
	return {"dungeon":true,"desert":true,"floor":depth,"spawn":rooms[0].center+Vector3(0,0,6),"bounds":bounds,"rooms":rooms,"links":links,"walkable":walkable,"enemies":[],"breakables":[],"containers":[],"terminal":Vector3.ZERO,"extracts":[{"pos":rooms[8].center+Vector3(0,0,-10),"name":"圣殿星门","locked":true,"room_id":8}]}
