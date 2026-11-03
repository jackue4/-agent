extends RefCounted
## Floor exploration and encounters. A room is paid out once per expedition.
var g
var rooms: Array = []
var links: Array = []
var current := -1
var locked_room := -1
var wave := 0
var wave_wait := 0.0
var wave_pending := false
var enabled := false
var boss_defeated := false
var visited: Dictionary = {}
var discovered: Dictionary = {}
var cleared: Dictionary = {}

func _init(controller) -> void: g = controller

func reset() -> void:
	rooms.clear(); links.clear(); visited.clear(); discovered.clear(); cleared.clear()
	current = -1; locked_room = -1; wave = 0; wave_wait = 0; wave_pending = false
	enabled = false; boss_defeated = false

func begin(map: Dictionary) -> void:
	reset()
	enabled = bool(map.get("dungeon",false))
	if not enabled: return
	rooms = map.rooms.duplicate(true); links = map.links.duplicate(true)
	_enter(0)

func room(id: int = -1) -> Dictionary:
	var wanted := current if id < 0 else id
	for item in rooms:
		if int(item.id) == wanted: return item
	return {}

func visited_position(pos: Vector3) -> bool:
	return visited.has(g.world.room_at(pos)) if enabled else true

func tick(delta: float) -> void:
	if not enabled or g.mode != "raid" or not is_instance_valid(g.player): return
	var id: int = g.world.room_at(g.player.position)
	if id >= 0 and id != current and locked_room < 0:
		var next := room(id)
		# Cross the threshold, then move fully past the shutter before closing it.
		# This also prevents slipping around the perimeter to skip encounters.
		if not visited.has(id) and str(next.kind) in ["combat","elite","boss"]:
			var safe: Rect2 = next.rect.grow(-1.55)
			var point := Vector2(g.player.position.x,g.player.position.z)
			var clamped := Vector2(clampf(point.x,safe.position.x,safe.end.x),clampf(point.y,safe.position.y,safe.end.y))
			g._move_actor(g.player,Vector3(clamped.x-point.x,0,clamped.y-point.y),.42)
		_enter(id)
	if locked_room < 0: return
	if wave_pending:
		wave_wait = maxf(0,wave_wait-delta)
		if wave_wait <= 0:
			wave_pending = false
			_spawn_wave()
		return
	if alive_in_room(locked_room) > 0: return
	var encounter := room(locked_room)
	if wave < encounter.waves.size():
		wave_wait = 1.15; wave_pending = true
		g.notify("增援接近 · 第 %d / %d 波" % [wave+1,encounter.waves.size()],1.1)
	else:
		_finish_room(encounter)

func _enter(id: int) -> void:
	var target := room(id)
	if target.is_empty(): return
	current = id
	discovered[id] = true
	for neighbor in target.neighbors: discovered[int(neighbor)] = true
	if visited.has(id):
		g.sound.combat = false
		return
	visited[id] = true
	for prop in target.get("breakables",[]):
		var record: Dictionary = g._spawn_breakable(prop.pos,prop.kind)
		record["room_id"] = id
	match str(target.kind):
		"combat","elite","boss":
			locked_room = id; wave = 0; wave_wait = .55; wave_pending = true
			g.world.set_room_locked(id,true)
			g.sound.combat = true
			g.notify(("首领警戒 · " if target.kind == "boss" else "封锁启动 · ")+str(target.name),2.0)
		"treasure":
			cleared[id] = true
			g.world.set_room_cleared(id,true)
			g.spawn_room_rewards(target.center,2,true)
			g.notify("补给秘藏 · 战利品自动回收",2.0)
		"rest":
			cleared[id] = true
			g.world.set_room_cleared(id,true)
			var restored: float = minf(g.max_hp-g.hp,g.max_hp*.28)
			g.hp += restored; g.mana = minf(g.max_mana,g.mana+45)
			g.play_combat_fx("prism_guard",target.center,Color("78f6b1"),Vector3.FORWARD,.55)
			g._float_text(g.player.position+Vector3.UP*2,"修复 +%d" % restored,Color("80efab"))
			g.sound.play("heal_pickup",-14,.9)
			g.notify("修复舱已使用 · 生命与能量恢复",2.2)
		_:
			cleared[id] = true
			g.world.set_room_cleared(id,true)
			g.sound.combat = false
	g.push_ui()

func _spawn_wave() -> void:
	var encounter := room(locked_room)
	if encounter.is_empty() or wave >= encounter.waves.size(): return
	var definitions: Array = encounter.waves[wave]
	wave += 1
	for definition in definitions:
		var enemy: Dictionary = g.spawn_enemy(definition.pos,definition.kind)
		enemy["room_id"] = locked_room
		var multiplier: float = 1.0 + (g.stage-1)*.22
		if definition.kind == "boss": multiplier = 1.0+(g.stage-1)*.30
		enemy.hp *= multiplier; enemy.max_hp *= multiplier
		if definition.kind in ["elite","boss"]:
			enemy["armor"] = enemy.hp*(.25 if definition.kind == "elite" else .18)
			enemy["max_armor"] = enemy.armor
			enemy.hp -= enemy.armor
		if definition.kind == "boss": g.dungeon_boss.configure(enemy,g.stage,encounter.rect.grow(-.7))
		g.play_combat_fx("loot_land",definition.pos,Color("ff7961"),Vector3.FORWARD,.55)
	g.push_ui()

func alive_in_room(id: int) -> int:
	var count := 0
	for enemy in g.enemies:
		if enemy.hp > 0 and int(enemy.get("room_id",-1)) == id: count += 1
	return count

func _finish_room(encounter: Dictionary) -> void:
	var id: int = encounter.id
	if cleared.has(id): return
	cleared[id] = true
	locked_room = -1; wave_pending = false
	g.world.set_room_locked(id,false); g.world.set_room_cleared(id,true)
	for bullet in g.bullets: bullet.life = 0
	g.sound.combat = false
	g.mana = minf(g.max_mana,g.mana+15)
	if str(encounter.kind) == "boss":
		boss_defeated = true
		g.clear_stage()
	else:
		g.sound.play("level",-15,1.2)
		g.world.pulse_floor(encounter.center,.65)
		g.play_combat_fx("clear_burst",encounter.center,Color("65e5e9"),Vector3.FORWARD,.65)
		g.spawn_room_rewards(g.player.position,2 if str(encounter.kind) == "elite" else 1,str(encounter.kind) == "elite")
		g.room_reward.on_room_cleared(encounter.center,str(encounter.kind))
		g.notify("房间肃清 · 封锁解除",1.8)
	g.push_ui()

func can_finish_floor() -> bool:
	return enabled and boss_defeated

func minimap() -> Dictionary:
	var result: Array = []
	for item in rooms:
		result.append({"id":item.id,"rect":item.rect,"kind":item.kind,"visited":visited.has(int(item.id)),"discovered":discovered.has(int(item.id)),"cleared":cleared.has(int(item.id)),"current":int(item.id)==current})
	return {"rooms":result,"links":links}

func state() -> Dictionary:
	if not enabled: return {}
	var active := room()
	var boss := {}
	for enemy in g.enemies:
		if enemy.kind == "boss" and enemy.hp > 0 and int(enemy.get("room_id",-1)) == current:
			var max_armor: float = enemy.get("max_armor",0)
			boss = {"name":enemy.get("boss_name","楼层守卫"),"hp":enemy.hp,"max_hp":enemy.max_hp-max_armor,"armor":enemy.get("armor",0),"max_armor":max_armor,"phase":enemy.get("boss_phase",1),"attack":enemy.get("boss_attack","")}
			break
	return {"floor":g.stage,"room_id":current,"room_name":active.get("name","连接通道"),"room_kind":active.get("kind","entry"),"visited":visited.size(),"total":rooms.size(),"cleared":cleared.size(),"combat_locked":locked_room>=0,"wave":wave,"waves":active.get("waves",[]).size(),"boss_defeated":boss_defeated,"boss":boss}
