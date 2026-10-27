extends Node
## Micrófono: captura, pasa a 16 kHz mono y detecta cuándo empiezas y terminas de hablar
## (detección de voz por energía, con un suelo de ruido que se adapta a tu cuarto).
## Emite `utterance` con la frase completa. Se puede forzar con un botón (mantener para hablar).

signal utterance(samples: PackedFloat32Array)
signal speech_started

const RATE := 16000
const FRAME := 320                 # 20 ms
const PREROLL := 15                # 300 ms antes de que se detecte la voz
const START_FRAMES := 3            # 60 ms seguidos por encima del umbral para empezar
const END_FRAMES := 40             # 800 ms de silencio para terminar
const MIN_FRAMES := 18             # menos de 360 ms no es una frase (tos, golpe)
const MAX_FRAMES := 600            # 12 s como máximo

var enabled := false               # hay alguien a quien hablar
var muted := false                 # un NPC está hablando: no escuchar (evita que se oiga a sí mismo)
var ptt := false                   # botón de hablar pulsado
var mic_ok := false
var level := 0.0                   # para el indicador
var floor_rms := 0.004
var speaking := false

var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _src_rate := 48000.0
var _acc := 0.0
var _acc_n := 0
var _phase := 0.0
var _frame := PackedFloat32Array()
var _pre: Array = []                # últimos fotogramas antes de hablar
var _cur := PackedFloat32Array()
var _loud := 0
var _quiet := 0
var _nframes := 0
var _was_ptt := false


func setup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		push_warning("audio/driver/enable_input está desactivado: sin micrófono")
		return
	var idx := AudioServer.get_bus_index("Micro")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Micro")
		AudioServer.set_bus_mute(idx, true)
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, _capture)
	else:
		_capture = AudioServer.get_bus_effect(idx, 0)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = "Micro"
	add_child(_player)
	_player.play()
	_src_rate = AudioServer.get_input_mix_rate() if AudioServer.has_method("get_input_mix_rate") else AudioServer.get_mix_rate()
	var dev := str(Game.settings.get("mic_device", ""))
	if dev != "" and dev in AudioServer.get_input_device_list():
		AudioServer.input_device = dev
	mic_ok = true


static func devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func set_device(dev: String) -> void:
	AudioServer.input_device = dev
	_reset()


func _process(_dt: float) -> void:
	if not mic_ok or _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var buf := _capture.get_buffer(n)
	# a 16 kHz mono: media de las muestras que caen en cada hueco
	var step := _src_rate / float(RATE)
	var out := PackedFloat32Array()
	for v in buf:
		_acc += (v.x + v.y) * 0.5
		_acc_n += 1
		_phase += 1.0
		if _phase >= step:
			_phase -= step
			out.append(_acc / float(_acc_n))
			_acc = 0.0
			_acc_n = 0
	feed(out)


## Entrada de muestras a 16 kHz (también la usan las pruebas automáticas).
func feed(samples: PackedFloat32Array) -> void:
	for s in samples:
		_frame.append(s)
		if _frame.size() >= FRAME:
			_on_frame(_frame)
			_frame = PackedFloat32Array()


func _reset() -> void:
	speaking = false
	_cur = PackedFloat32Array()
	_pre.clear()
	_loud = 0
	_quiet = 0
	_nframes = 0


func _on_frame(f: PackedFloat32Array) -> void:
	var e := 0.0
	for s in f:
		e += s * s
	var rms := sqrt(e / float(f.size()))
	level = lerpf(level, rms, 0.4)
	if _was_ptt and speaking and not ptt:
		# soltaste el botón: la frase termina aquí
		_finish()
		return
	var listening := (enabled or ptt) and not muted
	if not listening:
		if speaking:
			_reset()
		_was_ptt = false
		floor_rms = lerpf(floor_rms, clampf(rms, 0.0005, 0.05), 0.02)
		return
	if ptt:
		# mantener para hablar: graba todo mientras el botón esté pulsado
		if not speaking:
			speaking = true
			_cur = PackedFloat32Array()
			for p in _pre:
				_cur.append_array(p)
			speech_started.emit()
		_cur.append_array(f)
		_nframes += 1
		_was_ptt = true
		if _nframes >= MAX_FRAMES:
			_finish()
		return
	var on_thr := maxf(floor_rms * 3.2, 0.012)
	var off_thr := maxf(floor_rms * 2.0, 0.007)
	if not speaking:
		_pre.append(f)
		if _pre.size() > PREROLL:
			_pre.pop_front()
		if rms > on_thr:
			_loud += 1
			if _loud >= START_FRAMES:
				speaking = true
				_cur = PackedFloat32Array()
				for p in _pre:
					_cur.append_array(p)
				_nframes = _pre.size()
				_quiet = 0
				speech_started.emit()
		else:
			_loud = 0
			floor_rms = lerpf(floor_rms, clampf(rms, 0.0005, 0.05), 0.03)
		return
	_cur.append_array(f)
	_nframes += 1
	if rms < off_thr:
		_quiet += 1
	else:
		_quiet = 0
	if _quiet >= END_FRAMES or _nframes >= MAX_FRAMES:
		_finish()


func _finish() -> void:
	var s := _cur
	var voiced := _nframes - _quiet
	var by_button := _was_ptt
	_was_ptt = false
	_reset()
	if s.size() < MIN_FRAMES * FRAME or (voiced < MIN_FRAMES and not by_button):
		return
	utterance.emit(s)
