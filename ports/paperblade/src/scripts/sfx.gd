extends Node
## Pooled, rate-limited sound effects + music.

const GAP := {"tick": 0.03, "coin": 0.05, "hit": 0.035, "kill": 0.045, "gem": 0.028, "swing": 0.06, "thunder": 0.07, "boom": 0.06, "hurt": 0.1}

var streams: Dictionary = {}
var players: Array = []
var last: Dictionary = {}
var idx := 0
var music: AudioStreamPlayer
var music_b: AudioStreamPlayer
var tracks: Dictionary = {}
var battle_list: Array = []
var battle_i := 0
var cur := ""
const MUSIC_DB := -8.0
var gem_pitch := 1.0
var gem_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in ["hit", "kill", "gem", "swing", "hurt", "levelup", "thunder", "boom", "chest", "heal", "click", "tick", "ding", "reveal", "charge", "coin", "jackpot"]:
		streams[n] = load("res://assets/sfx/%s.wav" % n)
	_setup_buses()
	for i in 28:
		var a := AudioStreamPlayer.new()
		a.bus = "SFX"
		add_child(a)
		players.append(a)
	for p in ["title", "battle"]:
		var w: AudioStreamWAV = load("res://assets/music/%s.wav" % p)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		tracks[p] = w
	var mp3 = load("res://assets/music/bgm.mp3")
	if mp3 is AudioStreamMP3:
		mp3.loop = false
		tracks["bgm"] = mp3
	battle_list = ["battle", "bgm"] if tracks.has("bgm") else ["battle"]
	music = AudioStreamPlayer.new()
	music_b = AudioStreamPlayer.new()
	for m in [music, music_b]:
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		m.finished.connect(_on_track_end.bind(m))


func _setup_buses() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	for nm in ["Music", "SFX"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, "Master")
	var mi := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(mi, MUSIC_DB)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(mi, lp)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -1.0)


## Crossfade to a named track ("title", "battle", "bgm").
func play_music(name: String, fade: float = 1.2) -> void:
	if name == cur or not tracks.has(name):
		return
	cur = name
	var old := music
	music = music_b
	music_b = old
	music.stream = tracks[name]
	music.volume_db = -40.0
	music.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(music, "volume_db", 0.0, fade)
	if music_b.playing:
		tw.tween_property(music_b, "volume_db", -60.0, fade)
		tw.chain().tween_callback(music_b.stop)


func _on_track_end(p: AudioStreamPlayer) -> void:
	# non-looping (mp3) track in the battle playlist ended -> next one
	if p == music and battle_list.has(cur):
		battle_i = (battle_i + 1) % battle_list.size()
		cur = ""
		play_music(battle_list[battle_i], 0.3)


## Muffle the music while menus are open (level-up / pause / chest).
func muffle(on: bool) -> void:
	var mi := AudioServer.get_bus_index("Music")
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(mi, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lp, "cutoff_hz", 900.0 if on else 20000.0, 0.25)
	tw.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(mi, v), AudioServer.get_bus_volume_db(mi), MUSIC_DB - (4.0 if on else 0.0), 0.25)


func play(n: String, vol: float = 0.0, pv: float = 0.08, pitch: float = 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last.get(n, -9.0)) < float(GAP.get(n, 0.0)):
		return
	last[n] = now
	var a: AudioStreamPlayer = players[idx]
	idx = (idx + 1) % players.size()
	a.stream = streams[n]
	a.volume_db = vol
	a.pitch_scale = pitch * randf_range(1.0 - pv, 1.0 + pv)
	a.play()


func gem() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - gem_t < 0.5:
		gem_pitch = minf(gem_pitch + 0.03, 2.2)
	else:
		gem_pitch = 1.0
	gem_t = now
	play("gem", -9.0, 0.0, gem_pitch)


func start_music() -> void:
	battle_i = 0
	play_music(battle_list[0])
