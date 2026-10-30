extends Node
## Audio service: Music / SFX buses, a voice pool for sound effects with pitch variation,
## pickup "combo" pitch climbing, and music ducking for jingles.
const Synth = preload("res://sfx_synth.gd")

const BUILTIN := ["pop", "sparkle", "jump", "coin", "hurt", "win", "lose", "whoosh"]
const SYNTH := ["step", "land", "stomp", "checkpoint", "tick", "star"]
const VOICES := 12
const MUSIC_DB := -11.0
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
## Per-sound base gain so the mix stays balanced without per-call tweaking.
const GAIN := {"step": -14.0, "land": -8.0, "jump": -7.0, "coin": -5.0, "pop": -5.0, "whoosh": -9.0, "sparkle": -7.0, "hurt": -3.0, "stomp": -3.0, "checkpoint": -4.0, "tick": -12.0, "star": -4.0, "win": -2.0, "lose": -2.0}

var library := {}
var overrides := {}  # sfx name -> AudioStream from AI assets
var voices: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var combo := 0
var combo_t := 0.0
var _duck_tw: Tween

func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	for n in BUILTIN:
		var p := "res://sfx/%s.mp3" % n
		if ResourceLoader.exists(p):
			library[n] = load(p)
	for n in SYNTH:
		library[n] = Synth.make(n)
	for i in VOICES:
		var ap := AudioStreamPlayer.new()
		ap.bus = SFX_BUS
		add_child(ap)
		voices.append(ap)
	music = AudioStreamPlayer.new()
	music.bus = MUSIC_BUS
	music.volume_db = MUSIC_DB
	add_child(music)

func _process(delta: float) -> void:
	if combo_t > 0.0:
		combo_t -= delta
		if combo_t <= 0.0:
			combo = 0

static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")

func play(sfx_name: String, vol_db := 0.0, pitch := 1.0) -> void:
	var st: AudioStream = overrides.get(sfx_name, library.get(sfx_name))
	if st == null:
		return
	var ap := _free_voice()
	ap.stream = st
	ap.volume_db = vol_db + float(GAIN.get(sfx_name, -5.0))
	ap.pitch_scale = pitch * randf_range(0.94, 1.06)
	ap.play()

## Pickup sound whose pitch rises while the player chains pickups quickly.
func play_combo(sfx_name: String) -> void:
	combo = mini(combo + 1, 8)
	combo_t = 1.1
	play(sfx_name, 0.0, pow(1.0595, (combo - 1) * 2))

func _free_voice() -> AudioStreamPlayer:
	for ap in voices:
		if not ap.playing:
			return ap
	# steal the voice that has played longest
	var best := voices[0]
	for ap in voices:
		if ap.get_playback_position() > best.get_playback_position():
			best = ap
	return best

func set_music(st: AudioStream) -> void:
	if st == null:
		music.stop()
		music.stream = null
		return
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	elif st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	if music.stream != st:
		music.stream = st
		music.volume_db = -40.0
		music.play()
		create_tween().tween_property(music, "volume_db", MUSIC_DB, 1.2)
	elif not music.playing:
		music.play()

## Temporarily lower music under a jingle (win/lose), then restore.
func duck(depth_db := 14.0, hold := 2.5) -> void:
	if _duck_tw and _duck_tw.is_valid():
		_duck_tw.kill()
	_duck_tw = create_tween()
	_duck_tw.tween_property(music, "volume_db", MUSIC_DB - depth_db, 0.15)
	_duck_tw.tween_interval(hold)
	_duck_tw.tween_property(music, "volume_db", MUSIC_DB, 1.5)

func set_muted(v: bool) -> void:
	AudioServer.set_bus_mute(0, v)
