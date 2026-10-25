extends Node
## Efectos de sonido sintetizados al arrancar (sin archivos de audio). Autoload «Sfx».

const RATE := 22050
var sounds := {}
var players: Array[AudioStreamPlayer] = []
var idx := 0
var volume := 0.8


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)


func play(sound: String, pitch: float = 1.0) -> void:
	if not sounds.has(sound) or volume <= 0.01:
		return
	var p := players[idx]
	idx = (idx + 1) % players.size()
	p.stream = sounds[sound]
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(volume)
	p.play()


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	b.fill(0.0)
	return b


func _tone(b: PackedFloat32Array, f: float, dur: float, kind: String = "sine", vol: float = 0.3, slide: float = 1.0, delay: float = 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var j := start + i
		if j >= b.size():
			break
		var t := float(i) / float(n)
		ph += f * pow(slide, t) / RATE
		var fr := fmod(ph, 1.0)
		var s := 0.0
		match kind:
			"square":
				s = 1.0 if fr < 0.5 else -1.0
			"saw":
				s = fr * 2.0 - 1.0
			"tri":
				s = absf(fr * 4.0 - 2.0) - 1.0
			_:
				s = sin(ph * TAU)
		var env := exp(-5.0 * t) * minf(1.0, float(i) / (RATE * 0.004))
		b[j] += s * vol * env


func _noise(b: PackedFloat32Array, dur: float, vol: float = 0.3, cutoff: float = 1200.0, delay: float = 0.0) -> void:
	var start := int(delay * RATE)
	var n := int(dur * RATE)
	var a := clampf(TAU * cutoff / RATE, 0.0, 1.0)
	var lp := 0.0
	for i in n:
		var j := start + i
		if j >= b.size():
			break
		lp += a * (randf_range(-1.0, 1.0) - lp)
		b[j] += lp * vol * 2.0 * (1.0 - float(i) / float(n))


func _mk(b: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		data.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _build() -> void:
	var b := _buf(0.25); _noise(b, 0.12, 0.6, 2200.0); _noise(b, 0.1, 0.45, 1500.0, 0.09); sounds["crunch"] = _mk(b)
	b = _buf(0.5); _noise(b, 0.45, 0.35, 500.0); _tone(b, 220.0, 0.4, "saw", 0.06, 0.5); sounds["fire"] = _mk(b)
	b = _buf(0.55); _noise(b, 0.5, 0.5, 320.0); _tone(b, 90.0, 0.45, "sine", 0.3, 0.4); sounds["boom"] = _mk(b)
	b = _buf(0.7); _tone(b, 440.0, 0.6, "sine", 0.15, 1.5); _tone(b, 660.0, 0.6, "sine", 0.1, 1.5, 0.05); sounds["shield"] = _mk(b)
	b = _buf(0.6)
	for i in 4:
		_tone(b, [523.0, 659.0, 784.0, 1046.0][i], 0.35, "sine", 0.12, 1.0, i * 0.07)
	sounds["heal"] = _mk(b)
	b = _buf(0.9); _tone(b, 700.0, 0.9, "tri", 0.25, 0.98); _tone(b, 1930.0, 0.6, "sine", 0.1); _noise(b, 0.06, 0.3, 4000.0); sounds["clang"] = _mk(b)
	b = _buf(0.3); _tone(b, 1320.0, 0.1, "square", 0.06); _tone(b, 1760.0, 0.16, "square", 0.06, 1.0, 0.08); sounds["coin"] = _mk(b)
	b = _buf(0.3); _tone(b, 170.0, 0.25, "saw", 0.18, 0.6); sounds["hurt"] = _mk(b)
	b = _buf(0.25); _noise(b, 0.2, 0.4, 600.0); _tone(b, 300.0, 0.2, "sine", 0.15, 0.5); sounds["squish"] = _mk(b)
	b = _buf(1.2); _tone(b, 110.0, 1.2, "sine", 0.2, 2.0); _tone(b, 165.0, 1.2, "sine", 0.15, 2.0); sounds["portal"] = _mk(b)
	b = _buf(0.2); _tone(b, 880.0, 0.08, "sine", 0.14); _tone(b, 1175.0, 0.1, "sine", 0.12, 1.0, 0.06); sounds["pick"] = _mk(b)
	b = _buf(0.06); _tone(b, 660.0, 0.05, "sine", 0.07); sounds["ui"] = _mk(b)
	b = _buf(0.7)
	for i in 4:
		_tone(b, [392.0, 523.0, 659.0, 784.0][i], 0.3, "tri", 0.14, 1.0, i * 0.1)
	sounds["level"] = _mk(b)
	b = _buf(0.16); _tone(b, 300.0, 0.15, "sine", 0.07, 1.6); sounds["jump"] = _mk(b)
