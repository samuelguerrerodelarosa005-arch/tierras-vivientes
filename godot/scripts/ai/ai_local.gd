extends Node
## IA local, en el PC del jugador y sin APIs de pago. Arranca y vigila tres programas que viven en
## la carpeta `ia/` junto al juego:
##   - llama-server  (cerebro de los habitantes, modelo .gguf)     → http://127.0.0.1:8180
##   - whisper-server (voz a texto, modelo ggml-*.bin)               → http://127.0.0.1:8181
##   - piper          (voces de los habitantes; lo maneja voice_out.gd)
## Con `ia/config.json` → {"servidor": "http://IP"} usa un servidor propio en vez del PC local.
## Si falta algo, el juego sigue con guion y botones.

signal status_changed

const LLM_PORT := 8180
const STT_PORT := 8181
const LLM_TIMEOUT := 25.0
const STT_TIMEOUT := 20.0

var dir := ""            # carpeta ia/ encontrada ("" = no hay)
var cfg := {}
var llm_url := ""
var stt_url := ""
var llm_ok := false
var stt_ok := false
var llm_model := ""
var stt_model := ""
var stt_cpu := false     # se pasó a la versión sin tarjeta gráfica
var pids := {}           # nombre → pid de los procesos que arrancamos nosotros
var started_at := {}
var _poll_t := 0.0
var _stt_tries := 0
var calls := 0
var last_ms := {}        # "stt"/"llm" → milisegundos de la última llamada
var log_lines: Array = []


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 30:
		log_lines.pop_front()
	print("IA: ", s)


static func exe(name: String) -> String:
	return name + (".exe" if OS.get_name() == "Windows" else "")


static func find_dir() -> String:
	var cands: Array = []
	var env := OS.get_environment("TIERRAS_IA_DIR")
	if env != "":
		cands.append(env)
	cands.append(OS.get_executable_path().get_base_dir().path_join("ia"))
	var res := ProjectSettings.globalize_path("res://")
	cands.append(res.path_join("ia"))
	cands.append(res.path_join("../ia").simplify_path())
	for c in cands:
		if DirAccess.dir_exists_absolute(c):
			return c
	return ""


func setup() -> void:
	dir = find_dir()
	if dir == "":
		_log("no hay carpeta ia/: los habitantes hablan con guion")
		status_changed.emit()
		return
	if FileAccess.file_exists(dir.path_join("config.json")):
		var j = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("config.json")))
		if j is Dictionary:
			cfg = j
	if str(cfg.get("modo", "local")) == "apagada":
		_log("IA apagada en config.json")
		status_changed.emit()
		return
	var server := str(cfg.get("servidor", "")).strip_edges().trim_suffix("/")
	llm_url = str(cfg.get("llm_url", server + ":%d" % LLM_PORT if server != "" else "http://127.0.0.1:%d" % LLM_PORT))
	stt_url = str(cfg.get("stt_url", server + ":%d" % STT_PORT if server != "" else "http://127.0.0.1:%d" % STT_PORT))
	if server == "" and not cfg.has("llm_url"):
		llm_model = _first_file(dir.path_join("modelos"), ".gguf", str(cfg.get("llm_modelo", "")))
	if server == "" and not cfg.has("stt_url"):
		stt_model = _first_file(dir.path_join("modelos"), ".bin", str(cfg.get("stt_modelo", "")))
	# si ya hay servidores escuchando (otra partida que se cerró mal), se reutilizan
	var llm_alive := await _health(llm_url + "/health")
	var stt_alive := await _health(stt_url + "/health")
	if not llm_alive and llm_model != "":
		_start_llm()
	if not stt_alive and stt_model != "":
		_start_stt(bool(cfg.get("stt_cpu", false)))
	llm_ok = llm_alive
	stt_ok = stt_alive
	status_changed.emit()


func _first_file(d: String, ext: String, prefer: String) -> String:
	if prefer != "":
		var p := prefer if prefer.is_absolute_path() else dir.path_join(prefer)
		if FileAccess.file_exists(p):
			return p
	if not DirAccess.dir_exists_absolute(d):
		return ""
	var files := Array(DirAccess.get_files_at(d))
	files.sort()
	for f in files:
		if f.ends_with(ext) and not f.begins_with("ggml-vad"):
			return d.path_join(f)
	return ""


func _launch(name: String, path: String, args: PackedStringArray) -> void:
	if not FileAccess.file_exists(path):
		_log("falta %s" % path)
		return
	if OS.get_name() != "Windows":
		OS.set_environment("LD_LIBRARY_PATH", path.get_base_dir())
	var pid := OS.create_process(path, args)
	if pid <= 0:
		_log("no pude arrancar %s" % name)
		return
	pids[name] = pid
	started_at[name] = Time.get_ticks_msec()
	_log("arrancado %s (pid %d)" % [name, pid])


func _start_llm() -> void:
	var args := PackedStringArray(["-m", llm_model, "--host", "127.0.0.1", "--port", str(LLM_PORT),
		"-c", str(int(cfg.get("contexto", 4096))), "-ngl", str(int(cfg.get("capas_gpu", 99))), "-np", "1",
		"--no-webui", "--reasoning-budget", "0"])
	_launch("llm", dir.path_join("llama").path_join(exe("llama-server")), args)


func _start_stt(cpu: bool) -> void:
	stt_cpu = cpu
	var sub := "whisper-cpu" if cpu else "whisper"
	var bin := dir.path_join(sub).path_join(exe("whisper-server"))
	if not FileAccess.file_exists(bin) and not cpu:
		_start_stt(true)
		return
	var model := stt_model
	if cpu:
		var small := _first_file(dir.path_join("modelos"), ".bin", str(cfg.get("stt_modelo_cpu", "modelos/ggml-small-q5_1.bin")))
		if small != "":
			model = small
	# la primera vez la tarjeta gráfica compila sus programas: que la caché quepa
	OS.set_environment("CUDA_CACHE_MAXSIZE", "4294967296")
	var args := PackedStringArray(["-m", model, "-l", "es", "--host", "127.0.0.1", "--port", str(STT_PORT),
		"-t", str(int(cfg.get("hilos_voz", 4))), "-nt"])
	if cpu:
		args.append("-ng")
	_launch("stt", bin, args)


func shutdown() -> void:
	for k in pids:
		OS.kill(int(pids[k]))
	pids.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


func _process(dt: float) -> void:
	if dir == "" or (llm_url == "" and stt_url == ""):
		return
	_poll_t -= dt
	if _poll_t > 0.0:
		return
	_poll_t = 2.0 if (not llm_ok or not stt_ok) else 15.0
	_poll()


func _poll() -> void:
	var was := [llm_ok, stt_ok]
	if llm_url != "":
		llm_ok = await _health(llm_url + "/health")
	if stt_url != "":
		stt_ok = await _health(stt_url + "/health")
		# la versión con tarjeta gráfica no arrancó: pasar a la de procesador
		if not stt_ok and pids.has("stt") and not stt_cpu:
			var dead := not OS.is_process_running(int(pids.stt))
			var slow := Time.get_ticks_msec() - int(started_at.stt) > 240000
			if dead or slow:
				_log("la voz a texto con GPU no arrancó; pruebo con el procesador")
				OS.kill(int(pids.stt))
				pids.erase("stt")
				_start_stt(true)
	if was != [llm_ok, stt_ok]:
		_log("cerebro %s · voz a texto %s" % ["listo" if llm_ok else "no", "listo" if stt_ok else "no"])
		status_changed.emit()


func status_text() -> String:
	if dir == "":
		return "Sin IA: falta la carpeta «ia» (ejecuta instalar_ia.bat). Hablan con guion."
	var parts := []
	parts.append("cerebro " + ("listo" if llm_ok else ("cargando…" if pids.has("llm") else "no instalado")))
	parts.append("oído " + ("listo" if stt_ok else ("cargando…" if pids.has("stt") else "no instalado")) + (" (procesador)" if stt_cpu and stt_ok else ""))
	return "IA local: " + " · ".join(parts)


# ---------------------------------------------------------------- HTTP

func _http(url: String, method: int, headers: PackedStringArray, body: PackedByteArray, timeout: float) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = timeout
	add_child(h)
	var err := h.request_raw(url, headers, method, body)
	if err != OK:
		h.queue_free()
		return {"ok": false, "code": 0, "body": PackedByteArray()}
	var r: Array = await h.request_completed
	h.queue_free()
	return {"ok": int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) == 200, "code": int(r[1]), "body": r[3]}


func _health(url: String) -> bool:
	var r := await _http(url, HTTPClient.METHOD_GET, PackedStringArray(), PackedByteArray(), 3.0)
	return r.ok


## Cerebro: devuelve el JSON pedido (con gramática: el modelo no puede salirse del formato) o {}.
func chat(messages: Array, schema: Dictionary, max_tokens: int = 160, temperature: float = 0.7) -> Dictionary:
	if not llm_ok:
		return {}
	var body := {
		"messages": messages, "temperature": temperature, "top_p": 0.9, "max_tokens": max_tokens,
		"response_format": {"type": "json_schema", "json_schema": {"name": "respuesta", "schema": schema}},
		"chat_template_kwargs": {"enable_thinking": false}, "cache_prompt": true, "stream": false,
	}
	var t0 := Time.get_ticks_msec()
	calls += 1
	var r := await _http(llm_url + "/v1/chat/completions", HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(), LLM_TIMEOUT)
	last_ms["llm"] = Time.get_ticks_msec() - t0
	if not r.ok:
		_log("cerebro respondió %d" % r.code)
		return {}
	var j = JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())
	if not (j is Dictionary) or not j.has("choices") or (j.choices as Array).is_empty():
		return {}
	var content := str(j.choices[0].get("message", {}).get("content", ""))
	var a := content.find("{")
	var b := content.rfind("}")
	if a < 0 or b <= a:
		return {}
	var out = JSON.parse_string(content.substr(a, b - a + 1))
	return out if out is Dictionary else {}


## Prompt de texto libre (para el diálogo con panel): devuelve el texto o "".
func complete_text(prompt: String) -> String:
	if not llm_ok:
		return ""
	var r := await chat([{"role": "user", "content": prompt}], {"type": "object", "properties": {
		"decir": {"type": "string", "pattern": "^[a-zA-Z0-9áéíóúÁÉÍÓÚñÑüÜ¿¡?!.,;:'()«» -]{1,280}$"}, "emote": {"type": "string", "enum": ["saludar", "reir", "pensar", "enojado", "ninguno"]},
		"afinidad": {"type": "integer", "minimum": -3, "maximum": 3}, "ofrecer_mision": {"type": ["string", "null"]}},
		"required": ["decir", "emote", "afinidad", "ofrecer_mision"]}, 200)
	return JSON.stringify(r) if not r.is_empty() else ""


## Voz a texto: muestras mono a 16 kHz (−1…1) → texto en español.
func transcribe(samples: PackedFloat32Array, hint: String = "") -> String:
	if not stt_ok or samples.is_empty():
		return ""
	var wav := wav_bytes(samples, 16000)
	var bnd := "----tierras%d" % randi()
	var body := PackedByteArray()
	var fields := {"temperature": "0.0", "response_format": "json", "language": "es"}
	if hint != "":
		fields["prompt"] = hint
	for k in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [bnd, k, fields[k]]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voz.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % bnd).to_utf8_buffer())
	body.append_array(wav)
	body.append_array(("\r\n--%s--\r\n" % bnd).to_utf8_buffer())
	var t0 := Time.get_ticks_msec()
	var r := await _http(stt_url + "/inference", HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: multipart/form-data; boundary=" + bnd]), body, STT_TIMEOUT)
	last_ms["stt"] = Time.get_ticks_msec() - t0
	if not r.ok:
		_log("oído respondió %d" % r.code)
		return ""
	var j = JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())
	if not (j is Dictionary):
		return ""
	return clean_transcript(str(j.get("text", "")))


## Whisper a veces «oye» cosas en el silencio. Se descartan.
static func clean_transcript(t: String) -> String:
	t = t.strip_edges()
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]|\\([^\\)]*\\)|\\*[^*]*\\*")
	t = re.sub(t, "", true).strip_edges()
	var low := t.to_lower()
	for junk in ["subtítulos", "subtitulos", "gracias por ver", "suscríbete", "amara.org", "música", "[blank_audio]"]:
		if junk in low:
			return ""
	if t.length() < 2:
		return ""
	return t


static func wav_bytes(samples: PackedFloat32Array, rate: int) -> PackedByteArray:
	var n := samples.size()
	var b := PackedByteArray()
	b.resize(44 + n * 2)
	b.encode_u32(0, 0x46464952)        # RIFF
	b.encode_u32(4, 36 + n * 2)
	b.encode_u32(8, 0x45564157)        # WAVE
	b.encode_u32(12, 0x20746d66)       # fmt
	b.encode_u32(16, 16)
	b.encode_u16(20, 1)
	b.encode_u16(22, 1)
	b.encode_u32(24, rate)
	b.encode_u32(28, rate * 2)
	b.encode_u16(32, 2)
	b.encode_u16(34, 16)
	b.encode_u32(36, 0x61746164)       # data
	b.encode_u32(40, n * 2)
	for i in n:
		b.encode_s16(44 + i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return b
