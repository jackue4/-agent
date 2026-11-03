class_name EventObj
extends Node2D
## Field events: 武馆挑战 (fight inside the ring), 流浪商人 (shop), 混沌祭坛 (curse altar).

var kind := "dojo"
var t := 0.0
var life := 45.0
var active := false
var done := false
var kills_need := 12
var kills_got := 0
var timer := 0.0
const RING := 280.0


func _ready() -> void:
	G.enemy_died.connect(_on_enemy_died)


func title() -> String:
	return {"dojo": "武馆挑战", "merchant": "流浪商人", "altar": "混沌祭坛"}.get(kind, "")


func _on_enemy_died(e) -> void:
	if active and (e.position as Vector2).distance_to(position) < RING + 60.0:
		kills_got += 1


func _process(dt: float) -> void:
	t += dt
	var pl := G.player
	if pl == null or pl.dead:
		return
	var d := pl.position.distance_to(position)
	match kind:
		"dojo":
			if not active and not done and d < RING:
				active = true
				timer = 22.0
				G.banner("武馆挑战！20 秒内在擂台中击碎 %d 只怪！" % kills_need, 2.2)
				for i in 10:
					G.main.spawn_minion(["imp", "blob", "bat"][i % 3], position + Vector2.from_angle(TAU * i / 10.0) * (RING + 80.0))
			if active:
				timer -= dt
				if int(t * 2.0) % 4 == 0 and G.enemies.size() < 120 and Engine.get_process_frames() % 30 == 0:
					G.main.spawn_minion("imp", position + Vector2.from_angle(randf() * TAU) * (RING + 60.0))
				if kills_got >= kills_need:
					active = false
					done = true
					G.main.event_reward("dojo", position)
					_leave()
				elif timer <= 0.0:
					active = false
					done = true
					G.banner("挑战失败……", 1.6)
					_leave()
		"merchant", "altar":
			if d < 95.0 and not done:
				done = true
				if kind == "merchant":
					G.main.open_shop()
				else:
					G.main.open_altar()
				_leave()
	if not active:
		life -= dt
		if life <= 0.0:
			_leave()
	queue_redraw()


func _leave() -> void:
	if G.main != null and G.main.event_obj == self:
		G.main.event_obj = null
	G.particles.dust(position, 12, 60)
	queue_free()


func _draw() -> void:
	var ink := G.INK
	match kind:
		"dojo":
			var ring := Ink.ellipse(Vector2.ZERO, RING, RING * 0.62, 40)
			draw_colored_polygon(ring, Color(0.9, 0.2, 0.15, 0.12 if not active else 0.2))
			Ink.outline(self, ring, 6.0, Color(0.85, 0.15, 0.15, 0.9))
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				var p := Vector2(cos(a) * RING, sin(a) * RING * 0.62)
				draw_line(p, p + Vector2(0, -110), ink, 6.0)
				Ink.shape(self, PackedVector2Array([p + Vector2(0, -110), p + Vector2(46, -96), p + Vector2(0, -80)]), G.RED, 3.0)
			if active:
				draw_string_outline(G.font, Vector2(-80, -RING * 0.62 - 30), "%d / %d" % [kills_got, kills_need], HORIZONTAL_ALIGNMENT_CENTER, 160, 40, 8, ink)
				draw_string(G.font, Vector2(-80, -RING * 0.62 - 30), "%d / %d" % [kills_got, kills_need], HORIZONTAL_ALIGNMENT_CENTER, 160, 40, G.YELLOW)
		"merchant":
			Ink.shadow(self, Vector2.ZERO, 40, 12)
			var sack := Ink.ellipse(Vector2(-26, -40), 26, 30, 14)
			Ink.shape(self, sack, Color(0.75, 0.55, 0.3), 4.0)
			Stick.draw(self, Player.P_IDLE, 1.0, Vector2(0, sin(t * 3.0) * 2.0), ink, Color(0.3, 0.25, 0.3), Color(1, 0.9, 0.8), 7.0, Color(0, 0, 0, 0))
			var hat := PackedVector2Array([Vector2(-26, -108), Vector2(32, -108), Vector2(6, -130)])
			Ink.shape(self, hat, Color(0.85, 0.7, 0.35), 4.0)
		"altar":
			Ink.shadow(self, Vector2.ZERO, 60, 16)
			var base := PackedVector2Array([Vector2(-55, 0), Vector2(55, 0), Vector2(42, -46), Vector2(-42, -46)])
			Ink.shape(self, base, Color(0.4, 0.38, 0.45), 5.0)
			var fl := Ink.burst(Vector2(0, -80), 26, 38 + sin(t * 8.0) * 6.0, 8, 0.35, int(t * 12.0))
			Ink.shape(self, fl, Color(0.65, 0.2, 0.95), 4.0)
			draw_circle(Vector2(0, -74), 10.0, Color(1, 0.8, 1.0), true, -1.0, false)
	var lab := title()
	draw_string_outline(G.font_cn, Vector2(-100, -150 if kind != "dojo" else -RING * 0.62 - 80), lab, HORIZONTAL_ALIGNMENT_CENTER, 200, 30, 8, ink)
	draw_string(G.font_cn, Vector2(-100, -150 if kind != "dojo" else -RING * 0.62 - 80), lab, HORIZONTAL_ALIGNMENT_CENTER, 200, 30, G.YELLOW)
