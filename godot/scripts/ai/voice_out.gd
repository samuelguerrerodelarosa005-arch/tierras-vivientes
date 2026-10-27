extends Node
## Voces de los habitantes con Piper (texto a voz local, en el procesador). Cada habitante tiene
## su voz: modelo, hablante, velocidad y tono (`"piper"` en data.gd). El sonido sale de su cabeza
## (audio 3D). Un proceso de Piper por voz, abierto todo el rato: así cada frase tarda décimas.
## Si no hay Piper, el juego usa el texto a voz de Windows.

const FALLBACK_VOICE := "es-carlfm-x-low"

var main: Node
var dir := ""              # carpeta ia/
var piper_bin := ""
var procs := {}            # clave → {"pid", "io", "queue": [items], "buf", "slot"}
var players := {}          # id NPC → AudioStreamPlayer3D
var out_dir := ""
var available := false
var voices_found: Array = []
var spoken := 0
var last_ms := 0
var _speaking_until := {}  # id NPC → t_total en que termina de sonar


func setup(m: Node, ia_dir: String) -> void:
	main = m
	dir = ia_dir
	if dir == "":
		return
	piper_bin = dir.path_join("piper").path_join("piper.exe" if OS.get_name() == "Windows" else "piper")
	if not FileAccess.file_exists(piper_bin):
		return
	for f in DirAccess.get_files_at(dir.path_join("voces")) if DirAccess.dir_exists_absolute(dir.path_join("voces")) else PackedStringArray():
		if f.ends_with(".onnx"):
			voices_found.append(f.get_basename())
	if voices_found.is_empty():
		return
	out_dir = OS.get_user_data_dir().path_join("voz")
	DirAccess.make_dir_recursive_absolute(out_dir)
	available = true
	print("VOZ: Piper con %d voces: %s" % [voices_found.size(), ", ".join(voices_found)])


func voice_for(n: Node) -> Dictionary:
	var v: Dictionary = n.def.get("piper", {})
	var model := str(v.get("model", FALLBACK_VOICE))
	var pitch := float(v.get("pitch", 1.0))
	if not model in voices_found:
		# sin su voz instalada: la de reserva, con el tono de su voz de Windows
		model = FALLBACK_VOICE if FALLBACK_VOICE in voices_found else str(voices_found[0])
		pitch = float(v.get("fallback_pitch", n.def.voice.pitch))
		return {"model": model, "speaker": 0, "length": float(v.get("length", 1.0)), "pitch": clampf(pitch, 0.7, 1.4), "fallback": true}
	return {"model": model, "speaker": int(v.get("speaker", 0)), "length": float(v.get("length", 1.0)), "pitch": pitch}


func _proc(v: Dictionary) -> Dictionary:
	var key := "%s#%d#%.2f" % [v.model, v.speaker, v.length]
	if procs.has(key) and OS.is_process_running(int(procs[key].pid)):
		return procs[key]
	var model := dir.path_join("voces").path_join(str(v.model) + ".onnx")
	var args := PackedStringArray(["-m", model, "--json-input", "-q", "-s", str(v.speaker), "--length_scale", "%.2f" % float(v.length),
		"--sentence_silence", "0.12"])
	var esp := dir.path_join("piper").path_join("espeak-ng-data")
	if DirAccess.dir_exists_absolute(esp):
		args.append_array(["--espeak_data", esp])
	if OS.get_name() != "Windows":
		OS.set_environment("LD_LIBRARY_PATH", piper_bin.get_base_dir())
	var r := OS.execute_with_pipe(piper_bin, args, false)
	if r.is_empty():
		available = false
		return {}
	procs[key] = {"pid": int(r.pid), "io": r.stdio, "queue": [], "buf": "", "slot": 0, "key": key}
	return procs[key]


## Hace hablar a un NPC. Devuelve false si no hay Piper (el juego usará otra voz).
func speak(n: Node, text: String, vol: float = 1.0) -> bool:
	if not available or text.strip_edges() == "":
		return false
	var v := voice_for(n)
	# sin su voz propia, mejor la voz de Windows que la de reserva con el tono cambiado
	if v.get("fallback", false) and not main.tts_voices.is_empty():
		return false
	var p := _proc(v)
	if p.is_empty():
		return false
	p.slot = (int(p.slot) + 1) % 6
	var f := out_dir.path_join("%s_%d.wav" % [str(p.key).md5_text().substr(0, 8), p.slot])
	var io: FileAccess = p.io
	io.store_string(JSON.stringify({"text": _speakable(text), "output_file": f}) + "\n")
	io.flush()
	p.queue.append({"npc": n, "file": f, "pitch": v.pitch, "vol": vol, "t0": Time.get_ticks_msec()})
	# mientras se sintetiza, el NPC ya cuenta como hablando (el micro no se abre)
	_speaking_until[n.id] = main.t_total + 1.5
	return true


## Piper lee mejor sin símbolos raros.
func _speakable(t: String) -> String:
	for pair in [["«", ""], ["»", ""], ["…", "."], ["×", "por"], ["—", ","], ["*", ""]]:
		t = t.replace(pair[0], pair[1])
	return t.strip_edges()


func is_speaking(id: String) -> bool:
	return main != null and float(_speaking_until.get(id, 0.0)) > main.t_total


func any_speaking_near(pos: Vector3, r: float) -> bool:
	for id in _speaking_until:
		if float(_speaking_until[id]) > main.t_total:
			var n = Game.npcs.get(id)
			if n and n.pos.distance_to(pos) < r:
				return true
	return false


func stop(id: String) -> void:
	if players.has(id):
		players[id].stop()
	_speaking_until.erase(id)


func _process(_dt: float) -> void:
	if not available:
		return
	for key in procs:
		var p: Dictionary = procs[key]
		if (p.queue as Array).is_empty():
			continue
		var io: FileAccess = p.io
		var b := io.get_buffer(4096)
		if b.size() > 0:
			p.buf = str(p.buf) + b.get_string_from_utf8()
		while "\n" in str(p.buf):
			var cut := str(p.buf).find("\n")
			var line := str(p.buf).substr(0, cut).strip_edges()
			p.buf = str(p.buf).substr(cut + 1)
			if line == "" or (p.queue as Array).is_empty():
				continue
			var it: Dictionary = p.queue.pop_front()
			_play(it)


func _play(it: Dictionary) -> void:
	var n = it.npc
	if not is_instance_valid(n):
		return
	var st := AudioStreamWAV.load_from_file(it.file)
	if st == null:
		return
	last_ms = Time.get_ticks_msec() - int(it.t0)
	spoken += 1
	var pl: AudioStreamPlayer3D = players.get(n.id)
	if pl == null or not is_instance_valid(pl):
		pl = AudioStreamPlayer3D.new()
		pl.unit_size = 4.0
		pl.max_distance = 22.0
		pl.attenuation_filter_cutoff_hz = 9000.0
		n.add_child(pl)
		pl.position = Vector3(0, 1.6, 0)
		players[n.id] = pl
	pl.stream = st
	pl.pitch_scale = float(it.pitch)
	pl.volume_db = linear_to_db(clampf(float(it.vol) * float(Game.settings.get("voice_volume", 1.0)), 0.02, 2.0)) + 2.0
	pl.play()
	var dur := st.get_length() / maxf(float(it.pitch), 0.1)
	_speaking_until[n.id] = main.t_total + dur + 0.25
	n.talk_until = main.t_total + dur
	n.body.gest = "hablar"
	n.body.gest_t = minf(dur, 8.0)


func shutdown() -> void:
	for key in procs:
		OS.kill(int(procs[key].pid))
	procs.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		shutdown()
