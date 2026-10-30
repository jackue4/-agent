extends RefCounted
## Procedurally synthesised fallback sound effects (no asset files needed).
## Each generator returns a short mono 16-bit AudioStreamWAV.

const RATE := 22050

static func make(sfx_name: String) -> AudioStreamWAV:
	match sfx_name:
		"step": return _render(0.045, _step)
		"land": return _render(0.16, _land)
		"stomp": return _render(0.2, _stomp)
		"checkpoint": return _render(0.5, _checkpoint)
		"tick": return _render(0.05, _tick)
		"star": return _render(0.35, _star)
	return null

static func _render(dur: float, gen: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var state := {"lp": 0.0, "rng": rng}
	for i in n:
		var t := float(i) / RATE
		var v: float = gen.call(t, dur, state)
		# short fade-out to avoid clicks
		v *= clampf((dur - t) / 0.008, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

static func _noise_lp(state: Dictionary, k: float) -> float:
	var r: RandomNumberGenerator = state["rng"]
	state["lp"] = lerpf(state["lp"], r.randf_range(-1.0, 1.0), k)
	return state["lp"]

static func _step(t: float, _d: float, st: Dictionary) -> float:
	return _noise_lp(st, 0.35) * exp(-t * 90.0) * 0.55

static func _land(t: float, _d: float, st: Dictionary) -> float:
	var f := lerpf(150.0, 55.0, minf(t / 0.12, 1.0))
	var body := sin(TAU * f * t) * exp(-t * 26.0)
	return body * 0.8 + _noise_lp(st, 0.2) * exp(-t * 45.0) * 0.5

static func _stomp(t: float, _d: float, st: Dictionary) -> float:
	var f := lerpf(520.0, 120.0, minf(t / 0.16, 1.0))
	var sq := 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0
	return sq * exp(-t * 16.0) * 0.32 + _noise_lp(st, 0.5) * exp(-t * 60.0) * 0.45

static func _checkpoint(t: float, _d: float, _st: Dictionary) -> float:
	var notes := [1046.5, 1318.5, 1568.0, 2093.0]
	var idx := mini(int(t / 0.075), notes.size() - 1)
	var lt := t - idx * 0.075
	var ph := fmod(t * notes[idx], 1.0)
	var tri := 4.0 * absf(ph - 0.5) - 1.0
	return tri * exp(-lt * (8.0 if idx == notes.size() - 1 else 18.0)) * 0.4

static func _tick(t: float, _d: float, _st: Dictionary) -> float:
	return sin(TAU * 1800.0 * t) * exp(-t * 120.0) * 0.4

static func _star(t: float, _d: float, _st: Dictionary) -> float:
	var f := 880.0 + 880.0 * minf(t / 0.08, 1.0)
	var v := sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.0 * t)
	return v * exp(-t * 9.0) * 0.28
