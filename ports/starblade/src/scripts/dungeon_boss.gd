extends RefCounted
## Room-scoped boss state machines. Only enemy time advances these warnings.
## Main owns HP, armor, status decay and ordinary projectile collision.
const NAMES := ["炉心看守","棱镜双核","虚空执政"]
const COLORS := [Color("ff9461"),Color("70e6ff"),Color("ce93ff")]
const PATTERNS := [["fan","ring","shock"],["cross_fan","orbit","charge"],["void_mark","fan","void_triad"]]
const LABELS := {"fan":"锁向扇射","ring":"缺口环弹","shock":"炉心震荡","cross_fan":"交错扇射","orbit":"旋转环弹","charge":"棱镜冲锋","void_mark":"虚空追踪","void_triad":"三重虚空"}
var g
var _enemies: Array = []

func _init(controller) -> void: g = controller

static func name_for(floor_number: int) -> String:
	return NAMES[posmod(maxi(1,floor_number)-1,3)]

func configure(enemy: Dictionary,floor_number: int,arena: Rect2) -> void:
	_remove(enemy)
	if not _alive(enemy): return
	var floor_id := maxi(1,floor_number)
	var type := posmod(floor_id-1,3)
	enemy.boss_phase = 1; enemy.boss_name = name_for(floor_id)
	enemy.boss_attack = "接近目标"; enemy.boss_state = "cooldown"
	enemy.boss_telegraph_left = 0.0; enemy.boss_attack_radius = 0.0
	enemy["_boss"] = {"floor":floor_id,"type":type,"arena":arena,"owner_id":enemy.node.get_instance_id(),"sequence":0,"clock":0.0,
		"cooldown":1.0,"action":"","windup":0.0,"warning_duration":0.0,"elapsed":0.0,
		"aim":Vector3.FORWARD,"origin":enemy.node.position,"targets":[],"marks":[],"fills":[],
		"active_left":0.0,"volley":0,"hit_player":false,"phase_notice":0.0,"decor":null}
	_enemies.append(enemy)
	_decorate(enemy)

func tick(enemy: Dictionary,delta: float) -> void:
	if not enemy.has("_boss"): return
	if not _alive(enemy): _remove(enemy); return
	if g == null or not is_instance_valid(g.player): return
	if g.mode != "raid" or g.hp <= 0 or delta <= 0 or not is_finite(delta): return
	var s: Dictionary = enemy._boss
	# A telegraph cannot follow a player into a connected room.
	if not _inside(s.arena,g.player.position):
		_clear_warning(s); s.active_left = 0.0; s.cooldown = maxf(1.0,s.cooldown)
		enemy.boss_state = "cooldown"; enemy.boss_telegraph_left = 0; enemy.boss_attack = "等待入场"
		return
	if float(enemy.get("stagger",0)) > 0: return
	var speed := _move_scale(enemy)*(.38 if float(enemy.get("slow",0)) > 0 else 1.0)
	var left := delta*speed
	while left > .000001 and _alive(enemy) and g.mode == "raid" and g.hp > 0:
		var dt := minf(left,1.0/60.0)
		_step(enemy,s,dt)
		left -= dt

func _step(enemy: Dictionary,s: Dictionary,dt: float) -> void:
	s.clock += dt
	if enemy.boss_phase == 1 and float(enemy.hp)+float(enemy.get("armor",0)) < float(enemy.max_hp)*.5:
		enemy.boss_phase = 2; s.phase_notice = 1.5
		enemy.boss_attack = "二阶段 · 节奏加快"
		if g.has_method("_float_text"): g._float_text(enemy.node.position+Vector3.UP*4,"二阶段 · 加速",COLORS[s.type])
	s.phase_notice = maxf(0,s.phase_notice-dt)
	if enemy.boss_state == "telegraph":
		s.elapsed += dt
		if s.action in ["void_mark","void_triad"] and s.elapsed <= .25:
			_track_targets(enemy,s)
		s.windup = maxf(0,s.windup-dt); enemy.boss_telegraph_left = s.windup
		_update_warning(s)
		if s.windup <= .000001: _launch(enemy,s)
		return
	if enemy.boss_state == "active":
		_active(enemy,s,dt)
		return
	var offset: Vector3 = g.player.position-enemy.node.position; offset.y = 0
	if offset.length_squared() > .001:
		enemy.node.rotation.y = lerp_angle(enemy.node.rotation.y,atan2(-offset.x,-offset.z),minf(1,dt*5))
		if offset.length() > 6.5 or g.world.line_blocked(enemy.node.position,g.player.position):
			_move_safe(enemy,offset.normalized()*dt*1.3,s.arena)
	s.cooldown = maxf(0,s.cooldown-dt)
	if s.cooldown <= .000001 and not g.world.line_blocked(enemy.node.position,g.player.position):
		_begin(enemy,s,str(PATTERNS[s.type][int(s.sequence)%3])); s.sequence += 1
	elif s.phase_notice <= 0:
		enemy.boss_attack = "寻找破绽" if enemy.boss_phase == 1 else "二阶段 · 寻找破绽"

func _begin(enemy: Dictionary,s: Dictionary,action: String) -> void:
	_clear_warning(s)
	s.action = action; s.elapsed = 0.0; s.volley = 0; s.hit_player = false
	s.origin = enemy.node.position; s.aim = _direction(s.origin,g.player.position)
	s.targets = []; enemy.boss_attack_radius = 0.0
	s.warning_duration = {"fan":.78,"cross_fan":.85,"ring":1.0,"orbit":1.05,"shock":1.0,"charge":1.1,"void_mark":1.1,"void_triad":1.25}.get(action,1.0)
	s.windup = s.warning_duration
	enemy.boss_state = "telegraph"; enemy.boss_attack = LABELS[action]
	enemy.boss_telegraph_left = s.windup
	match action:
		"shock":
			enemy.boss_attack_radius = 5.2
			s.targets = [s.origin]; _circle_warning(s,s.origin,5.2)
		"void_mark","void_triad":
			enemy.boss_attack_radius = 2.9+minf(.3,float(s.floor-1)*.05)
			_set_void_targets(enemy,s)
			for point in s.targets: _circle_warning(s,point,enemy.boss_attack_radius)
		"charge":
			var end: Vector3 = _safe_end(s.origin,s.origin+s.aim*minf(9,s.origin.distance_to(g.player.position)+1.4),.85,s.arena)
			s.targets = [end]; _lane_warning(s,s.origin,end,1.15)
		"ring","orbit":
			_circle_warning(s,s.origin,2.4)
			# Green boundaries show the safe angular gap; its direction locks now.
			for sign_value in [-1,1]: _line_warning(s,s.origin,s.origin+s.aim.rotated(Vector3.UP,sign_value*.52)*7,Color("88efb0"),.065)
		_:
			for angle in [-.55,0.0,.55]: _line_warning(s,s.origin,s.origin+s.aim.rotated(Vector3.UP,angle)*11,COLORS[s.type],.045)

func _launch(enemy: Dictionary,s: Dictionary) -> void:
	_clear_warning(s); enemy.boss_telegraph_left = 0
	if g.boon_runtime != null: g.boon_runtime.before_fire(enemy)
	if not _alive(enemy): _remove(enemy); return
	if not _inside(s.arena,g.player.position): _finish(enemy,s); return
	enemy.boss_state = "active"; s.elapsed = 0.0
	match s.action:
		"fan": _fan(enemy,s,0); _finish(enemy,s)
		"cross_fan": _fan(enemy,s,-.16); s.active_left = .24; s.volley = 1
		"ring": _ring(enemy,s,0); _finish(enemy,s)
		"orbit": _ring(enemy,s,0); s.active_left = .38; s.volley = 1
		"charge":
			s.active_left = .65
			if g.has_method("play_combat_fx"): g.play_combat_fx("rush_slash",enemy.node.position,COLORS[s.type],s.aim,1.5)
		"shock","void_mark","void_triad":
			for point in s.targets:
				_ground_hit(enemy,s,point,float(enemy.boss_attack_radius),26.0 if s.action == "shock" else 22.0)
			_finish(enemy,s)

func _active(enemy: Dictionary,s: Dictionary,dt: float) -> void:
	s.elapsed += dt; s.active_left = maxf(0,s.active_left-dt)
	if s.action == "charge":
		var from: Vector3 = enemy.node.position
		var end: Vector3 = s.targets[0]
		var motion: Vector3 = end-from; motion.y = 0
		_move_safe(enemy,motion.normalized()*minf(15.0*dt,motion.length()),s.arena)
		var to: Vector3 = enemy.node.position
		var closest := Geometry3D.get_closest_point_to_segment(g.player.position,from,to)
		if not s.hit_player and closest.distance_to(g.player.position) < 1.25 and not g.world.line_blocked(closest,g.player.position) and _inside(s.arena,g.player.position):
			s.hit_player = true; g.damage_player(_damage(enemy,s,26))
		if motion.length() < .1 or from.distance_to(to) < .001: s.active_left = 0.0
	if s.active_left <= .000001:
		if s.action == "cross_fan" or s.action == "orbit":
			if g.boon_runtime != null: g.boon_runtime.before_fire(enemy)
			if not _alive(enemy): _remove(enemy); return
			if s.action == "cross_fan": _fan(enemy,s,.16)
			else: _ring(enemy,s,.22)
		_finish(enemy,s)

func _finish(enemy: Dictionary,s: Dictionary) -> void:
	s.active_left = 0.0; enemy.boss_state = "cooldown"
	var base := 1.15 if s.action in ["charge","shock","void_triad"] else .95
	s.cooldown = base*(.8 if enemy.boss_phase == 2 else 1.0)
	enemy.boss_attack = "二阶段 · 回气" if enemy.boss_phase == 2 else "回气"

func _fan(enemy: Dictionary,s: Dictionary,offset: float) -> void:
	var count := 5+mini(4,2*int((s.floor-1)/3))
	for index in count:
		var angle := (float(index)-(count-1)*.5)*.17+offset
		_bullet(enemy,s,s.aim.rotated(Vector3.UP,angle),7.0+minf(2,float(s.floor-1)*.25),14)

func _ring(enemy: Dictionary,s: Dictionary,rotation: float) -> void:
	var count := 16+mini(4,2*int((s.floor-1)/3))
	var gap: Vector3 = s.aim.rotated(Vector3.UP,rotation)
	for index in count:
		var direction := Vector3.FORWARD.rotated(Vector3.UP,TAU*float(index)/count+float(s.sequence)*.19+rotation)
		if direction.dot(gap) > cos(.52): continue
		_bullet(enemy,s,direction,4.6+minf(1.6,float(s.floor-1)*.18),11)

func _bullet(enemy: Dictionary,s: Dictionary,direction: Vector3,speed: float,damage: float) -> void:
	if g.bullets.size() >= 96: return
	var origin: Vector3 = enemy.node.position+Vector3.UP*.7
	# Lifetime ends before crossing this room, independently of surrounding doors.
	var distance := 30.0
	var rect: Rect2 = s.arena.grow(-.2)
	if direction.x > .0001: distance = minf(distance,(rect.end.x-origin.x)/direction.x)
	elif direction.x < -.0001: distance = minf(distance,(rect.position.x-origin.x)/direction.x)
	if direction.z > .0001: distance = minf(distance,(rect.end.y-origin.z)/direction.z)
	elif direction.z < -.0001: distance = minf(distance,(rect.position.y-origin.z)/direction.z)
	if distance <= .2: return
	var index: int = g.bullets.size()
	g.spawn_bullet(origin,direction*speed,_damage(enemy,s,damage))
	if g.bullets.size() > index:
		var bullet: Dictionary = g.bullets[index]
		bullet.life = minf(float(bullet.life),distance/speed)
		bullet.boss_owner = enemy.node.get_instance_id(); bullet.boss_arena = s.arena

func _ground_hit(enemy: Dictionary,s: Dictionary,center: Vector3,radius: float,amount: float) -> void:
	# A locked warning behind newly-created cover does not blast through it.
	if g.world.line_blocked(enemy.node.position,center): return
	if g.has_method("play_combat_fx"): g.play_combat_fx("gravity_burst" if s.type == 2 else "impact",center,COLORS[s.type],Vector3.FORWARD,radius/4.8)
	if _inside(s.arena,g.player.position) and _flat_distance(center,g.player.position) <= radius+.35 and not g.world.line_blocked(center,g.player.position):
		g.damage_player(_damage(enemy,s,amount))

func _set_void_targets(enemy: Dictionary,s: Dictionary) -> void:
	var center := _clamp_point(g.player.position,s.arena,float(enemy.boss_attack_radius)+.2)
	s.targets = [center]
	if s.action == "void_triad":
		var side: Vector3 = s.aim.rotated(Vector3.UP,PI*.5)
		for sign_value in [-1,1]:
			var point := _clamp_point(center+side*5.4*sign_value,s.arena,float(enemy.boss_attack_radius)+.2)
			if point.distance_to(center) > 4 and not g.world.line_blocked(enemy.node.position,point): s.targets.append(point)

func _track_targets(enemy: Dictionary,s: Dictionary) -> void:
	if g.world.line_blocked(enemy.node.position,g.player.position): return
	var old_count: int = s.targets.size()
	_set_void_targets(enemy,s)
	# Tracking moves the existing fixed-count marks; no per-frame mesh allocation.
	while s.targets.size() < old_count: s.targets.append(s.targets[0])
	if s.targets.size() > old_count: s.targets.resize(old_count)
	for index in mini(s.targets.size(),s.marks.size()): s.marks[index].position = s.targets[index]+Vector3.UP*.07

func _move_safe(enemy: Dictionary,motion: Vector3,arena: Rect2) -> void:
	var from: Vector3 = enemy.node.position
	var safe := _safe_end(from,from+motion,.85,arena)
	g._move_actor(enemy.node,safe-from,.85)

func _safe_end(from: Vector3,to: Vector3,radius: float,arena: Rect2) -> Vector3:
	var steps := maxi(1,ceili(from.distance_to(to)/.12))
	var previous := from
	for index in range(1,steps+1):
		var point := from.lerp(to,float(index)/steps)
		var blocked: bool = g._position_blocked(point,radius) if g.has_method("_position_blocked") else g.world.blocked(point,radius)
		if not _inside(arena.grow(-radius),point) or blocked or g.world.line_blocked(previous,point): return previous
		previous = point
	return to

func _circle_warning(s: Dictionary,center: Vector3,radius: float) -> void:
	var node := Node3D.new(); g.actors.add_child(node); node.position = center+Vector3.UP*.07
	s.marks.append(node)
	for index in 32:
		var a := TAU*index/32.0
		var piece := _box(node,Vector3(cos(a)*radius,0,sin(a)*radius),Vector3(.10,.035,radius*TAU/32.0+.02),COLORS[s.type],.75)
		piece.rotation.y = -a
	var fill := Node3D.new(); node.add_child(fill); s.fills.append(fill)
	for index in 12:
		var a := TAU*index/12.0
		var piece := _box(fill,Vector3(cos(a)*radius,0,sin(a)*radius),Vector3(.07,.045,radius*.36),COLORS[s.type],.4)
		piece.rotation.y = -a
	fill.scale = Vector3(.15,1,.15)

func _line_warning(s: Dictionary,from: Vector3,to: Vector3,color: Color,width: float) -> void:
	var node := Node3D.new(); g.actors.add_child(node); s.marks.append(node)
	var delta := to-from; delta.y = 0
	var piece := _box(node,(from+to)*.5+Vector3.UP*.06,Vector3(width,.035,delta.length()),color,.55)
	piece.rotation.y = atan2(delta.x,delta.z)

func _lane_warning(s: Dictionary,from: Vector3,to: Vector3,radius: float) -> void:
	var side := _direction(from,to).rotated(Vector3.UP,PI*.5)*radius
	for sign_value in [-1,1]: _line_warning(s,from+side*sign_value,to+side*sign_value,COLORS[s.type],.10)
	_line_warning(s,from,to,COLORS[s.type],.04)

func _update_warning(s: Dictionary) -> void:
	var progress := clampf(1.0-float(s.windup)/float(s.warning_duration),0,1)
	for fill in s.fills:
		if is_instance_valid(fill): fill.scale = Vector3(.15+.8*progress,1,.15+.8*progress)

func _clear_warning(s: Dictionary) -> void:
	for node in s.get("marks",[]):
		if is_instance_valid(node): node.visible = false; node.queue_free()
	s.marks = []; s.fills = []; s.windup = 0.0

func _decorate(enemy: Dictionary) -> void:
	var s: Dictionary = enemy._boss
	var root := Node3D.new(); enemy.node.add_child(root); root.name = "BossVariant"
	s.decor = root; root.set_meta("boss_type",s.type)
	var color: Color = COLORS[s.type]
	match int(s.type):
		0:
			for side in [-1,1]:
				for index in 3: _box(root,Vector3(side*.62,1.45+index*.14,0),Vector3(.34,.08,.65),color,.7)
		1:
			for side in [-1,1]:
				var crystal := _box(root,Vector3(side*.77,1.8,0),Vector3(.35,.55,.35),color,1.1)
				crystal.rotation.z = side*.45; crystal.rotation.y = PI*.25
		2:
			for index in 7:
				var a := TAU*index/7.0
				var piece := _box(root,Vector3(cos(a)*.8,2.05,sin(a)*.8),Vector3(.15,.15,.38),color,.8)
				piece.rotation.y = -a

func _box(parent: Node3D,pos: Vector3,size: Vector3,color: Color,emission: float) -> MeshInstance3D:
	# Unit meshes keep varied room/telegraph lengths out of the world mesh cache.
	var node: MeshInstance3D = g.world.box(parent,pos,Vector3.ONE,color,emission)
	node.scale = size
	return node

func _remove(enemy: Dictionary) -> void:
	if not enemy.has("_boss"): return
	var s: Dictionary = enemy._boss
	_clear_warning(s)
	if is_instance_valid(s.get("decor")): s.decor.queue_free()
	var owner_id: int = int(s.owner_id)
	if g != null:
		for index in range(g.bullets.size()-1,-1,-1):
			var bullet: Dictionary = g.bullets[index]
			if int(bullet.get("boss_owner",-2)) != owner_id: continue
			if is_instance_valid(bullet.get("node")): bullet.node.queue_free()
			g.bullets.remove_at(index)
	enemy.erase("_boss"); enemy.boss_state = "inactive"; enemy.boss_telegraph_left = 0.0
	_enemies.erase(enemy)

func reset() -> void:
	for enemy in _enemies.duplicate(): _remove(enemy)
	_enemies.clear()

func dispose() -> void: reset(); g = null

func _move_scale(enemy: Dictionary) -> float:
	return clampf(float(g.boon_runtime.move_multiplier(enemy)),.1,1.0) if g.boon_runtime != null else 1.0

func _damage(enemy: Dictionary,s: Dictionary,amount: float) -> float:
	var weak: float = g.boon_runtime.outgoing_multiplier(enemy) if g.boon_runtime != null else 1.0
	return amount*(1.0+minf(.6,float(s.floor-1)*.06))*weak

func _alive(enemy: Dictionary) -> bool:
	return float(enemy.get("hp",0)) > 0 and is_instance_valid(enemy.get("node")) and not enemy.node.is_queued_for_deletion()

func _inside(arena: Rect2,point: Vector3) -> bool: return arena.has_point(Vector2(point.x,point.z))
func _flat_distance(a: Vector3,b: Vector3) -> float: return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))
func _direction(a: Vector3,b: Vector3) -> Vector3:
	var value := b-a; value.y = 0
	return value.normalized() if value.length_squared() > .001 else Vector3.FORWARD
func _clamp_point(point: Vector3,arena: Rect2,margin: float) -> Vector3:
	var inner := arena.grow(-margin)
	return g.world.ground_position(Vector3(clampf(point.x,inner.position.x,inner.end.x),0,clampf(point.z,inner.position.y,inner.end.y)))
