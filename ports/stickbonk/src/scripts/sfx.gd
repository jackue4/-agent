extends Node
## Procedurally synthesised comic sound effects (no external audio files needed).

const RATE := 22050
var streams := {}
var players: Array[AudioStreamPlayer] = []
var _idx := 0
var _last_play := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 24:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for k in ["hit", "heavy", "shatter", "whoosh", "pickup", "levelup", "hurt", "zap", "boom", "dash", "click", "fire"]:
		streams[k] = _make(k)


func play(sound: String, vol_db: float = 0.0, pitch_var: float = 0.12) -> void:
	if not streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if _last_play.has(sound) and now - int(_last_play[sound]) < 40:
		return
	_last_play[sound] = now
	var p := players[_idx]
	_idx = (_idx + 1) % players.size()
	p.stream = streams[sound]
	p.volume_db = vol_db - 4.0
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()


func _dur(kind: String) -> float:
	match kind:
		"hit": return 0.16
		"heavy": return 0.42
		"shatter": return 0.55
		"whoosh": return 0.17
		"pickup": return 0.07
		"levelup": return 0.55
		"hurt": return 0.22
		"zap": return 0.25
		"boom": return 0.9
		"dash": return 0.2
		"click": return 0.04
		"fire": return 0.35
	return 0.2


func _make(kind: String) -> AudioStreamWAV:
	var dur := _dur(kind)
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var prev := 0.0
	var hold := 0.0
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		var noise := randf() * 2.0 - 1.0
		match kind:
			"hit":
				var f := 55.0 + 210.0 * exp(-t * 35.0)
				phase += TAU * f / RATE
				s = sin(phase) * exp(-t * 18.0) * 0.95 + noise * exp(-t * 75.0) * 0.75
			"heavy":
				var f := 32.0 + 170.0 * exp(-t * 16.0)
				phase += TAU * f / RATE
				lp += (noise - lp) * 0.12
				s = clampf(sin(phase) * 1.8, -1.0, 1.0) * exp(-t * 6.5) * 0.9 + lp * exp(-t * 10.0) * 1.6
			"shatter":
				if randf() < 0.006:
					hold = randf_range(0.5, 1.0)
				hold *= 0.996
				var hp := noise - prev
				prev = noise
				s = hp * hold * exp(-t * 5.0) * 0.7 + noise * exp(-t * 35.0) * 0.6
			"whoosh":
				var env := sin(PI * t / dur)
				lp += (noise - lp) * (0.04 + 0.3 * env)
				s = lp * env * 1.8
			"dash":
				var env := sin(PI * t / dur)
				lp += (noise - lp) * (0.1 + 0.4 * env)
				s = (lp - lp2) * env * 2.0
				lp2 = lp
			"pickup":
				var f := 900.0 + 1100.0 * t / dur
				phase += f / RATE
				s = (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * 0.22 * exp(-t * 18.0)
			"levelup":
				var idx := mini(int(t / 0.1), 3)
				phase += float(notes[idx]) / RATE
				s = (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * 0.2 * (1.0 - t / dur)
			"hurt":
				var f := 260.0 - 160.0 * t / dur
				phase += f / RATE
				s = (fmod(phase, 1.0) * 2.0 - 1.0) * 0.45 * exp(-t * 8.0) + noise * 0.2 * exp(-t * 30.0)
			"zap":
				var f := 70.0 + 40.0 * sin(t * 90.0)
				phase += f / RATE
				var sq := 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
				s = (sq * 0.35 + noise * 0.45) * exp(-t * 9.0)
			"boom":
				var f := 28.0 + 70.0 * exp(-t * 6.0)
				phase += TAU * f / RATE
				lp += (noise - lp) * 0.06
				s = clampf(sin(phase) * 1.5, -1.0, 1.0) * exp(-t * 3.5) * 0.8 + lp * exp(-t * 3.0) * 2.2
			"click":
				phase += 1500.0 / RATE
				s = sin(phase * TAU) * 0.3 * (1.0 - t / dur)
			"fire":
				lp += (noise - lp) * 0.2
				if randf() < 0.01:
					hold = 1.0
				hold *= 0.99
				s = lp * 0.5 * sin(PI * t / dur) + noise * hold * 0.3
		var v := int(clampf(s, -1.0, 1.0) * 30000.0)
		data.encode_s16(i * 2, v)
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st
