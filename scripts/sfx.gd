extends Node
## Autoload: procedurally synthesised 8-bit sound effects. No audio files needed.

const RATE := 22050
var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _loop_player: AudioStreamPlayer

func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_loop_player = AudioStreamPlayer.new()
	_loop_player.volume_db = -14.0
	add_child(_loop_player)
	_build_all()

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sounds.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sounds[name]
			p.volume_db = -8.0 + volume_db
			p.pitch_scale = pitch
			p.play()
			return

func loop(name: String, on: bool) -> void:
	if on:
		if not _loop_player.playing or _loop_player.stream != _sounds[name]:
			_loop_player.stream = _sounds[name]
			_loop_player.play()
	else:
		_loop_player.stop()

func _wav(samples: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = RATE
	var data := PackedByteArray()
	data.resize(samples.size())
	for i in samples.size():
		var v := clampf(samples[i], -1.0, 1.0)
		var q := int(round(v * 15.0)) * 8   # 4-bit crunch, very SNES-sample
		data[i] = (q + 256) % 256
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _gen(seconds: float, f: Callable) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in n:
		var t := float(i) / RATE
		out[i] = f.call(t, rng)
	return out

func _env(t: float, a: float, d: float) -> float:
	if t < a:
		return t / a
	return max(0.0, 1.0 - (t - a) / d)

func _build_all() -> void:
	_sounds["shot"] = _wav(_gen(0.07, func(t: float, rng: RandomNumberGenerator) -> float:
		var fr := 900.0 - t * 6000.0
		return (sin(t * fr * TAU) * 0.6 + rng.randf_range(-1, 1) * 0.5) * _env(t, 0.002, 0.06)))
	_sounds["shot2"] = _wav(_gen(0.06, func(t: float, rng: RandomNumberGenerator) -> float:
		return (sign(sin(t * 420.0 * TAU)) * 0.4 + rng.randf_range(-1, 1) * 0.6) * _env(t, 0.002, 0.05)))
	_sounds["explode"] = _wav(_gen(0.45, func(t: float, rng: RandomNumberGenerator) -> float:
		return (rng.randf_range(-1, 1) * 0.9 + sin(t * (120.0 - t * 150.0) * TAU) * 0.4) * _env(t, 0.01, 0.4)))
	_sounds["explode_big"] = _wav(_gen(1.1, func(t: float, rng: RandomNumberGenerator) -> float:
		return (rng.randf_range(-1, 1) * 0.8 + sin(t * (70.0 - t * 40.0) * TAU) * 0.6) * _env(t, 0.02, 1.0)))
	_sounds["hit"] = _wav(_gen(0.05, func(t: float, rng: RandomNumberGenerator) -> float:
		return sign(sin(t * 1800.0 * TAU)) * 0.5 * _env(t, 0.001, 0.045)))
	_sounds["damage"] = _wav(_gen(0.5, func(t: float, rng: RandomNumberGenerator) -> float:
		return (sign(sin(t * (200.0 - t * 200.0) * TAU)) * 0.5 + rng.randf_range(-1, 1) * 0.3) * _env(t, 0.005, 0.45)))
	_sounds["xp"] = _wav(_gen(0.09, func(t: float, rng: RandomNumberGenerator) -> float:
		var fr := 1200.0 + floorf(t * 60.0) * 400.0
		return sign(sin(t * fr * TAU)) * 0.35 * _env(t, 0.002, 0.08)))
	_sounds["levelup"] = _wav(_gen(0.7, func(t: float, rng: RandomNumberGenerator) -> float:
		var step := int(t * 10.0)
		var notes := [523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0, 1319.0]
		var fr: float = notes[min(step, notes.size() - 1)]
		return sign(sin(t * fr * TAU)) * 0.35 * _env(t, 0.01, 0.75)))
	_sounds["select"] = _wav(_gen(0.08, func(t: float, rng: RandomNumberGenerator) -> float:
		return sign(sin(t * 660.0 * TAU)) * 0.3 * _env(t, 0.002, 0.07)))
	_sounds["confirm"] = _wav(_gen(0.25, func(t: float, rng: RandomNumberGenerator) -> float:
		var fr := 660.0 if t < 0.1 else 990.0
		return sign(sin(t * fr * TAU)) * 0.35 * _env(t, 0.002, 0.24)))
	_sounds["tick"] = _wav(_gen(0.03, func(t: float, rng: RandomNumberGenerator) -> float:
		return sign(sin(t * 2400.0 * TAU)) * 0.3 * _env(t, 0.001, 0.025)))
	_sounds["reel_stop"] = _wav(_gen(0.12, func(t: float, rng: RandomNumberGenerator) -> float:
		return sign(sin(t * 330.0 * TAU)) * 0.45 * _env(t, 0.002, 0.11)))
	_sounds["jackpot"] = _wav(_gen(1.4, func(t: float, rng: RandomNumberGenerator) -> float:
		var step := int(t * 14.0)
		var notes := [784.0, 988.0, 1175.0, 1568.0, 1175.0, 1568.0, 1976.0, 1568.0, 1976.0, 2349.0, 2349.0, 2349.0]
		var fr: float = notes[step % notes.size()]
		return sign(sin(t * fr * TAU)) * 0.35 * _env(t, 0.01, 1.4) * (0.5 + 0.5 * abs(sin(t * 28.0)))))
	_sounds["missile"] = _wav(_gen(0.35, func(t: float, rng: RandomNumberGenerator) -> float:
		return (rng.randf_range(-1, 1) * 0.5 + sin(t * (300.0 + t * 900.0) * TAU) * 0.4) * _env(t, 0.01, 0.33)))
	_sounds["crate"] = _wav(_gen(0.3, func(t: float, rng: RandomNumberGenerator) -> float:
		var fr := 220.0 if t < 0.15 else 330.0
		return sign(sin(t * fr * TAU)) * 0.4 * _env(t, 0.01, 0.28)))
	_sounds["warning"] = _wav(_gen(0.4, func(t: float, rng: RandomNumberGenerator) -> float:
		var on := fmod(t, 0.2) < 0.1
		return (sign(sin(t * 880.0 * TAU)) * 0.35 if on else 0.0)))
	_sounds["lost_life"] = _wav(_gen(1.2, func(t: float, rng: RandomNumberGenerator) -> float:
		var fr := 400.0 - t * 300.0
		return (sign(sin(t * fr * TAU)) * 0.4 + rng.randf_range(-1, 1) * 0.3) * _env(t, 0.01, 1.1)))
	_sounds["coin"] = _wav(_gen(0.35, func(t: float, rng: RandomNumberGenerator) -> float:
		var fr := 1319.0 if t < 0.08 else 1760.0
		return sin(t * fr * TAU) * 0.45 * _env(t, 0.002, 0.33)))
	_sounds["laser"] = _wav(_gen(0.25, func(t: float, rng: RandomNumberGenerator) -> float:
		var saw := fmod(t * 180.0, 1.0) * 2.0 - 1.0
		var saw2 := fmod(t * 183.0, 1.0) * 2.0 - 1.0
		return (saw + saw2) * 0.25), true)
	_sounds["countdown"] = _wav(_gen(0.15, func(t: float, rng: RandomNumberGenerator) -> float:
		return sign(sin(t * 440.0 * TAU)) * 0.4 * _env(t, 0.005, 0.14)))
