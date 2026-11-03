extends Node

const ACTION_IDS := ["thrust", "spear_throw", "spear_recall", "spin_charge", "spin", "break", "heal_pickup", "energy_pickup"]

var samples: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var beat := 0.0
var step := 0
var combat := false
var enabled := true

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for id in ["sword", "hit", "hurt", "loot", "dash", "level", "extract", "shot", "ui", "bass", "tick", "melee_light", "melee_heavy", "impact", "pickup_rare"]:
		samples[id] = synth(id)
	for id in ACTION_IDS:
		samples[id] = synth(id)

func synth(id: String) -> AudioStreamWAV:
	if id in ACTION_IDS:
		return _synth_actions(id)
	if id in ["melee_light", "melee_heavy", "impact", "pickup_rare"]:
		return _synth_combat(id)
	var duration := 0.13
	var freq := 400.0
	match id:
		"sword": freq = 780.0
		"hit": freq = 190.0
		"hurt": freq = 80.0; duration = 0.23
		"loot": freq = 920.0; duration = 0.2
		"dash": freq = 170.0; duration = 0.22
		"level": freq = 660.0; duration = 0.55
		"extract": freq = 440.0; duration = 1.1
		"shot": freq = 160.0; duration = 0.09
		"ui": freq = 800.0; duration = 0.055
		"bass": freq = 55.0; duration = 0.45
		"tick": freq = 1200.0; duration = 0.04
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / rate
		var u := t / duration
		var pitch := freq
		if id in ["sword", "shot", "dash", "hit"]: pitch *= 1.0 - u * 0.65
		if id in ["level", "extract"]: pitch *= pow(2.0, floor(u * 4.0) / 4.0)
		phase += TAU * pitch / rate
		var value := sin(phase) * exp(-u * 5.0) * minf(t * 160, 1.0)
		if id in ["hurt", "dash", "shot", "hit"]:
			value = (value * 0.4 + randf_range(-1, 1) * 0.35 * exp(-u * 9.0))
		bytes.encode_s16(i * 2, int(clampf(value, -1, 1) * 22000))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav


func _synth_combat(id: String) -> AudioStreamWAV:
	# Short layered one-shots with spectral headroom; noise is band-limited so
	# repeated close-range swings do not turn into a harsh wall of white noise.
	var duration := .18
	match id:
		"melee_heavy": duration = .27
		"impact": duration = .14
		"pickup_rare": duration = .46
	var rate := 22050
	var count := int(duration*rate)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var noise := RandomNumberGenerator.new()
	noise.seed = absi(id.hash())
	var fast_noise := 0.0
	var slow_noise := 0.0
	var phase := 0.0
	var body_phase := 0.0
	for i in count:
		var t := float(i)/rate
		var u := t/duration
		var white := noise.randf_range(-1.0,1.0)
		fast_noise += (white-fast_noise)*.36
		slow_noise += (white-slow_noise)*.045
		var air := fast_noise-slow_noise
		var value := 0.0
		match id:
			"melee_light":
				var pitch := lerpf(1050.0,180.0,pow(u,.64))
				phase += TAU*pitch/rate
				var swell := pow(sin(PI*u),.72)*exp(-u*2.2)
				value = air*.88*swell + sin(phase)*.24*swell
				value += sin(phase*1.98)*.055*exp(-u*8.0)
			"melee_heavy":
				phase += TAU*lerpf(640.0,90.0,pow(u,.58))/rate
				body_phase += TAU*(58.0+70.0*exp(-t*22.0))/rate
				var swell := pow(sin(PI*u),.60)*exp(-u*2.3)
				value = air*.72*swell + sin(phase)*.20*swell
				value += sin(body_phase)*.43*exp(-u*5.0)
				value += sin(body_phase*2.03)*.11*exp(-u*9.0)
			"impact":
				phase += TAU*(75.0+245.0*exp(-t*40.0))/rate
				value = sin(phase)*.48*exp(-u*5.7)
				value += air*.80*exp(-u*16.0)
				value += sin(TAU*1480.0*t)*.12*exp(-u*21.0)
			"pickup_rare":
				# A short rising major arpeggio, with soft octave partials.
				for note in 4:
					var note_time := t-note*.058
					if note_time < 0.0: continue
					var freq: float = [622.25,783.99,932.33,1244.51][note]
					var attack := minf(note_time/.004,1.0)
					var envelope := attack*exp(-note_time*17.0)
					value += (sin(TAU*freq*note_time)*.29+sin(TAU*freq*2.0*note_time)*.045)*envelope
		# A two-ms onset and final 18-ms release remove discontinuities without
		# rounding away the blade/impact transients. PCM has > 3 dB of headroom.
		var edge := minf(t/.002,1.0)*minf((duration-t)/.018,1.0)
		bytes.encode_s16(i*2,int(clampf(value*edge,-.9,.9)*22000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav


func _synth_actions(id: String) -> AudioStreamWAV:
	# Low-pass / high-pass noise layers create airy weapon motion rather than
	# sharp white-noise hiss. All cues are finite one-shots and share headroom.
	var duration: float = {"thrust":.135,"spear_throw":.30,"spear_recall":.28,"spin_charge":.25,"spin":.42,"break":.25,"heal_pickup":.34,"energy_pickup":.38}[id]
	var rate := 22050
	var count := int(duration*rate)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var random := RandomNumberGenerator.new()
	random.seed = absi(id.hash())
	var low_noise := 0.0
	var high_noise := 0.0
	var phase := 0.0
	var body_phase := 0.0
	for i in count:
		var t := float(i)/rate
		var u := t/duration
		var white := random.randf_range(-1.0,1.0)
		low_noise += (white-low_noise)*.028
		high_noise += (white-high_noise)*.24
		var air := high_noise-low_noise
		var value := 0.0
		match id:
			"thrust":
				phase += TAU*lerpf(940.0,270.0,pow(u,.42))/rate
				body_phase += TAU*(130.0+90.0*exp(-t*42.0))/rate
				var snap := exp(-u*6.5)
				value = air*.92*pow(sin(PI*u),.48)*exp(-u*3.9)
				value += sin(phase)*.14*snap + sin(body_phase)*.22*snap
			"spear_throw":
				phase += TAU*lerpf(740.0,145.0,pow(u,.75))/rate
				var swell := pow(sin(PI*u),.72)*exp(-u*1.9)
				value = air*.90*swell + sin(phase)*.19*swell
				value += sin(phase*.497)*.09*exp(-u*7.0)
			"spear_recall":
				# Rising return whistle contrasts with the outward falling sweep.
				phase += TAU*lerpf(190.0,1020.0,pow(u,.8))/rate
				var swell := pow(sin(PI*u),.80)
				value = air*.47*swell + sin(phase)*.18*swell
				value += sin(phase*.5)*.08*swell
			"spin_charge":
				phase += TAU*lerpf(180.0,440.0,pow(u,.65))/rate
				var swell := pow(sin(PI*u),.65)
				value = sin(phase)*.20*swell + sin(phase*1.995)*.045*swell
				value += air*.20*swell
			"spin":
				phase += TAU*(160.0+120.0*sin(PI*u))/rate
				body_phase += TAU*lerpf(108.0,63.0,u)/rate
				var sweep := pow(sin(PI*u),.60)*(.64+.36*sin(TAU*u*2.0-.5))
				value = air*.78*sweep + sin(phase)*.11*sweep
				value += sin(body_phase)*.19*pow(sin(PI*u),.75)
			"break":
				# Staggered damped clicks and low woody knocks read as falling blocks.
				for chip in 5:
					var dt := t-float(chip)*.026
					if dt < 0.0: continue
					var f := 145.0+float(chip)*93.0
					var envelope := minf(dt/.0015,1.0)*exp(-dt*(42.0+chip*8.0))
					value += (sin(TAU*f*dt)*.14+air*.31)*envelope
				value += sin(TAU*79.0*t)*.19*exp(-u*8.0)
			"heal_pickup":
				# Warm, close-spaced healing triad with a soft lower fundamental.
				for note in 3:
					var dt := t-note*.052
					if dt < 0.0: continue
					var f: float = [392.0,493.88,587.33][note]
					var envelope := minf(dt/.006,1.0)*exp(-dt*17.0)
					value += (sin(TAU*f*dt)*.22+sin(TAU*f*.5*dt)*.055)*envelope
			"energy_pickup":
				# A clean glassy upper register makes energy identifiable by ear.
				for note in 3:
					var dt := t-note*.065
					if dt < 0.0: continue
					var f: float = [659.25,987.77,1318.51][note]
					var envelope := minf(dt/.004,1.0)*exp(-dt*19.0)
					value += (sin(TAU*f*dt)*.205+sin(TAU*f*1.997*dt)*.028)*envelope
		var edge := minf(t/.0025,1.0)*minf((duration-t)/.021,1.0)
		# -7.8 dBFS ceiling before the normal -18 dB playback gain. Twelve
		# identical coincident cues remain below full scale at default volume.
		bytes.encode_s16(i*2,int(clampf(value*edge,-.54,.54)*24500.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = bytes
	return wav


func play(id: String, db: float = -18, pitch: float = 1.0) -> void:
	if not enabled or not samples.has(id): return
	for p in players:
		if not p.playing:
			p.stream = samples[id]
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return

func _process(delta: float) -> void:
	beat -= delta
	if beat <= 0:
		beat = 0.33 if combat else 0.55
		step += 1
		if step % 4 == 0: play("bass", -29, [1.0, 1.0, 1.5, 1.25][(step / 8) % 4])
		if combat and step % 2 == 0: play("tick", -36, 0.9)
