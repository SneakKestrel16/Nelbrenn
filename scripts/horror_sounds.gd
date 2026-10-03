extends RefCounted
## Every horror sound, made in code so there are no sound files. Each
## function returns a ready-to-play AudioStreamWAV; the looping ones say so.

const RATE := 22050


## Low, uneasy drone of two slightly mistuned notes (loops).
static func drone() -> AudioStreamWAV:
	var f := func(t: float, _rng: RandomNumberGenerator) -> float:
		var swell := 0.6 + 0.4 * sin(TAU * t / 6.0)
		return (sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 58.5 * t) * 0.4 + sin(TAU * 82.5 * t) * 0.15) * swell * 0.35
	return _make(6.0, true, f)


## Breathy whispering (loops). Played by the Watcher and the Shade.
static func whisper() -> AudioStreamWAV:
	var state := [0.0, 0.0]
	var f := func(t: float, rng: RandomNumberGenerator) -> float:
		var n := rng.randf_range(-1.0, 1.0)
		state[0] = lerpf(state[0], n, 0.35)         # Take the harshness off...
		state[1] = lerpf(state[1], state[0], 0.02)  # ...and remove the rumble: a hissy band.
		var syllables := maxf(sin(TAU * 3.3333 * t) * sin(TAU * 1.0 * t + 1.0), 0.0)
		return (state[0] - state[1]) * syllables * 1.6
	return _make(3.0, true, f)


## A skittering of claws (loops). The Crawler makes it while moving.
static func skitter() -> AudioStreamWAV:
	var clicks: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var c := 0.0
	while c < 0.98:
		clicks.append(c)
		c += rng.randf_range(0.03, 0.08)
	var f := func(t: float, r: RandomNumberGenerator) -> float:
		var s := 0.0
		for click in clicks:
			var dt := t - click
			if dt >= 0.0 and dt < 0.02:
				s += r.randf_range(-1.0, 1.0) * exp(-dt * 300.0) + sin(TAU * 2400.0 * dt) * exp(-dt * 400.0) * 0.5
		return s * 0.6
	return _make(1.0, true, f)


## A deep, wavering hum (loops). The Shade's sound.
static func hum() -> AudioStreamWAV:
	var f := func(t: float, rng: RandomNumberGenerator) -> float:
		var tremolo := 0.6 + 0.4 * sin(TAU * 4.5 * t)
		var s := sin(TAU * 70.0 * t) * 0.5 + sin(TAU * 140.0 * t + sin(TAU * 0.5 * t)) * 0.25 + rng.randf_range(-1.0, 1.0) * 0.05
		return s * tremolo * 0.6
	return _make(4.0, true, f)


## A rough, falling roar. The Mimic when it reveals itself.
static func roar() -> AudioStreamWAV:
	var phase := [0.0]
	var f := func(t: float, rng: RandomNumberGenerator) -> float:
		phase[0] += lerpf(120.0, 55.0, t / 1.3) / RATE
		var saw := fmod(phase[0], 1.0) * 2.0 - 1.0
		var env := minf(t / 0.05, 1.0) * exp(-t * 1.6)
		return tanh((saw * 0.7 + rng.randf_range(-1.0, 1.0) * 0.6) * 2.5) * env * 0.7
	return _make(1.3, false, f)


## A shrieking, clashing screech. The Watcher's attack.
static func screech() -> AudioStreamWAV:
	var f := func(t: float, rng: RandomNumberGenerator) -> float:
		var env := minf(t / 0.01, 1.0) * exp(-t * 2.5)
		var s := sin(TAU * 1900.0 * t) + sin(TAU * 2017.0 * t) + sin(TAU * 1450.0 * t * (1.0 + t * 0.3))
		return tanh((s * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5) * 3.0) * env * 0.8
	return _make(0.9, false, f)


## A deep boom with a hiss. Plays when you first spot the Watcher.
static func boom() -> AudioStreamWAV:
	var f := func(t: float, rng: RandomNumberGenerator) -> float:
		var low := sin(TAU * lerpf(48.0, 30.0, t / 2.0) * t) * exp(-t * 1.8)
		return (low * 0.9 + rng.randf_range(-1.0, 1.0) * exp(-t * 3.0) * 0.15) * 0.9
	return _make(2.0, false, f)


## One "lub-dub".
static func heartbeat() -> AudioStreamWAV:
	var f := func(t: float, _rng: RandomNumberGenerator) -> float:
		var s := 0.0
		for start in [0.0, 0.17]:
			if t >= start:
				s += sin(TAU * 52.0 * (t - start)) * exp(-(t - start) * 22.0)
		return s * 0.9
	return _make(0.5, false, f)


## A distant, wavering howl.
static func howl() -> AudioStreamWAV:
	var phase := [0.0]
	var f := func(t: float, _rng: RandomNumberGenerator) -> float:
		var p := t / 2.6
		var pitch := lerpf(300.0, 520.0, sin(p * PI)) * (1.0 + sin(TAU * 5.5 * t) * 0.02)
		phase[0] += pitch / RATE
		return (sin(TAU * phase[0]) + sin(TAU * phase[0] * 2.0) * 0.2) * sin(p * PI) * 0.4
	return _make(2.6, false, f)


## A slow creak, like an old tree or a door.
static func creak() -> AudioStreamWAV:
	var phase := [0.0]
	var f := func(t: float, rng: RandomNumberGenerator) -> float:
		phase[0] += lerpf(150.0, 95.0, t / 1.4) / RATE
		var pulses := maxf(sin(TAU * 18.0 * t), 0.0)
		var saw := fmod(phase[0], 1.0) * 2.0 - 1.0
		return (saw * 0.6 + rng.randf_range(-1.0, 1.0) * 0.2) * pulses * sin(PI * t / 1.4) * 0.5
	return _make(1.4, false, f)


## Builds a sound of `length` seconds from `sample(t, rng) -> float` (-1..1).
static func _make(length: float, loop: bool, sample: Callable) -> AudioStreamWAV:
	var samples := int(RATE * length)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var s: float = sample.call(float(i) / RATE, rng)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples
	return wav
