extends Node
## Conversación con los habitantes. Con clave de API, Claude improvisa el diálogo con la
## personalidad, memoria y rumores de cada habitante; sin clave, usa frases de respaldo.
## La IA solo escribe el texto: las misiones y recompensas las decide el juego.

const Data = preload("res://scripts/data.gd")
# Se prueba el primero; si la API dice que no existe, se pasa al siguiente.
const MODELS := ["claude-haiku-5-5", "claude-haiku-4-5"]
var model_idx := 0
var last_error := ""   # último error de la IA, explicado (se ve en Ajustes)

var main: Node
var npc: Node = null
var offer := ""
var busy := false
var busy_since := 0.0
var you := ""
var reply := ""
var thinking := false
var ai_warned := false


func open(n: Node) -> void:
	if npc:
		close()
	npc = n
	offer = ""
	you = ""
	reply = ""
	busy = false
	n.busy = "player"
	n.face = main.player
	main.on_dialog_open()
	talk(n, "(El Viajero se acerca y te saluda.)", "greet")


func close() -> void:
	if npc == null:
		return
	npc.busy = ""
	npc.face = null
	npc = null
	offer = ""
	busy = false
	thinking = false
	main.on_dialog_close()


func ai_enabled() -> bool:
	return str(Game.settings.api_key).strip_edges() != ""


func options() -> Array:
	var n = npc
	if n == null:
		return []
	var others: Array = main.npcs.filter(func(o): return o != n)
	var other = others[n.other_idx % others.size()]
	var o := [
		{"t": "¿Qué se cuenta por aquí?", "i": "rumor"},
		{"t": "¿Tienes trabajo para mí?", "i": "work"},
		{"t": _special_text(n.id), "i": "special"},
		{"t": "¿Quién eres?", "i": "about"},
		{"t": "Háblame de " + other.npc_name, "i": "other", "other": other},
	]
	for q in Game.deliverable(n.id):
		o.push_front({"t": "Entregar: " + Game.QT[q.id].title, "i": "deliver", "q": q})
	o.append({"t": "Adiós", "i": "bye"})
	return o


func choose(o: Dictionary) -> void:
	var n = npc
	if n == null:
		return
	if busy and o.i != "bye":
		# seguro contra bloqueos: si una respuesta se quedó colgada, se libera sola
		if main.t_total - busy_since < 9.0:
			return
		busy = false
	match o.i:
		"bye":
			var lines: Array = n.def.lines.bye
			n.say(lines.pick_random(), "saludar")
			close()
		"deliver":
			Game.deliver_quest(o.q, n)
			talk(n, "(El Viajero te entrega lo que pediste para «%s». Reacciona.)" % Game.QT[o.q.id].title, "thanks")
		"special":
			var r := _special_run(n.id)
			talk(n, r.prompt, "special", r.reply, o.t)
		"other":
			n.other_idx += 1
			talk(n, "Háblame de %s." % o.other.npc_name, "other", Data.OPINION[n.id][o.other.id])
		_:
			talk(n, o.t, o.i)


func say_free(text: String) -> void:
	text = text.strip_edges()
	if text == "" or npc == null or busy:
		return
	var t := _norm(text)
	var intent := "generic"
	if "trabajo" in t or "mision" in t or "ayuda" in t or "encargo" in t:
		intent = "work"
	elif "rumor" in t or "cuenta" in t or "noticia" in t or "chisme" in t:
		intent = "rumor"
	elif "quien eres" in t or "como te llamas" in t:
		intent = "about"
	elif "adios" in t or "chao" in t or "hasta luego" in t:
		choose({"i": "bye", "t": text})
		return
	talk(npc, text, intent)


func _norm(s: String) -> String:
	s = s.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"], ["¿", ""], ["?", ""], ["¡", ""], ["!", ""]]:
		s = s.replace(pair[0], pair[1])
	return s


func _special_text(id: String) -> String:
	match id:
		"bruno":
			return "Quiero pan (%d monedas)" % Game.bread_cost()
		"lia":
			return "¿Cómo va el sembrado?"
		"dorran":
			return "¿Algún consejo para forjar?"
		"sira":
			return "¿Cuándo abre el portal?"
	return "…"


func _special_run(id: String) -> Dictionary:
	match id:
		"bruno":
			var had := Game.gold
			main.buy_bread()
			var ok := Game.gold < had
			if ok:
				return {"prompt": "(El Viajero te compra un pan.)", "reply": ["Ahí tienes. Cómetelo caliente.", "Crujiente, como debe ser. Llévatelo a la boca, no lo mires tanto."].pick_random()}
			return {"prompt": "(El Viajero quiere pan pero no le alcanzan las monedas.)", "reply": "Sin monedas no hay pan, Viajero. Vende algo en tu puesto."}
		"lia":
			var pests: int = main.slimes_near_field()
			var w := roundi(Game.wheat)
			var rp := "¡Fatal! Hay %d limos comiéndose el trigo. Solo quedan %d sacos." % [pests, w] if pests >= 3 else "¡Bien, bien! Quedan %d sacos y los limos andan lejos." % w
			return {"prompt": "(El Viajero pregunta por el sembrado. Quedan %d sacos de trigo y hay %d limos cerca.)" % [w, pests], "reply": rp}
		"dorran":
			return {"prompt": "(El Viajero pide un consejo para forjar.)", "reply": "Golpea cuando la marca esté dentro de la luz, no antes. Y come bien: un herrero con hambre falla."}
		"sira":
			var extra := "; con luna llena el portal se queda abierto hasta el alba" if Game.moon_phase() == 4 else ""
			return {"prompt": "(El Viajero pregunta por el portal. %s La luna está %s.)" % [Game.portal_text(), Game.moon_name()], "reply": "%s Esta noche la luna está %s%s." % [Game.portal_text(), Game.moon_name(), extra]}
	return {"prompt": "", "reply": "…"}


func talk(n: Node, player_text: String, intent: String, fallback: String = "", shown: String = "") -> void:
	busy = true
	busy_since = main.t_total
	you = shown if shown != "" else ("" if player_text.begins_with("(") else player_text)
	reply = "…"
	thinking = true
	n.body.gest = "pensar"
	n.body.gest_t = 2.0
	main.ui.mark("dialog")
	var offers := Game.offerable(n.id)
	var res := {}
	if ai_enabled():
		res = await _ask_ai(n, player_text, intent, offers)
	if res.is_empty():
		res = _scripted(n, intent, offers, fallback)
	if npc != n:
		busy = false
		thinking = false
		return
	n.aff = clampf(n.aff + clampf(roundf(float(res.get("afinidad", 0))), -3.0, 3.0), -100.0, 100.0)
	n.convo.append({"p": you if you != "" else player_text, "n": res.decir})
	if n.convo.size() > 4:
		n.convo.pop_front()
	if intent == "greet" and n.memory.is_empty():
		n.remember("Conocí a %s, %s de trabajo principal y %s de secundario" % [Game.player_name, Game.JOBS[Game.cls].name.to_lower(), Game.JOBS[Game.sub].name.to_lower()])
	reply = res.decir
	thinking = false
	var em := str(res.get("emote", "hablar"))
	if em == "ninguno":
		em = "hablar"
	n.say(reply, em, 1.0, false)
	var want := str(res.get("ofrecer_mision", ""))
	if want in offers:
		offer = want
	elif intent == "work" and not offers.is_empty():
		offer = offers[0]
	else:
		offer = ""
	busy = false
	Game.check_titles()
	main.ui.mark("dialog")


func _scripted(n: Node, intent: String, offers: Array, fallback: String) -> Dictionary:
	var lines: Dictionary = n.def.lines
	var t := ""
	if fallback != "":
		t = fallback
	elif intent == "about":
		t = Data.ABOUT[n.id].pick_random()
	elif intent == "greet":
		t = lines.greet.pick_random() + (" Me alegra verte." if n.aff >= 20 else "")
		if not n.memory.is_empty() and randf() < 0.5:
			var m: String = n.memory[-1]
			t += " Todavía recuerdo que " + m.substr(0, 1).to_lower() + m.substr(1) + "."
	elif intent == "work":
		if offers.is_empty():
			t = lines.none.pick_random()
		elif Game.QT[offers[0]].get("hidden", false):
			t = "…Has demostrado buen oído. Mi maestro forjaba con cristales lunares. Tráeme uno de las Ruinas."
		else:
			t = lines.work.pick_random()
	elif intent == "rumor":
		t = "Dicen por ahí: " + n.rumors[-1] if not n.rumors.is_empty() else lines.generic.pick_random()
	elif intent == "thanks":
		t = lines.thanks.pick_random()
	else:
		t = lines.generic.pick_random()
	var emote := "saludar" if intent == "greet" else ("reir" if intent == "thanks" else "hablar")
	return {"decir": t, "emote": emote, "afinidad": 1 if intent == "greet" else 0, "ofrecer_mision": offers[0] if intent == "work" and not offers.is_empty() else ""}


func _prompt(n: Node, player_text: String, offers: Array) -> String:
	var q := ""
	for id in offers:
		var d: Dictionary = Game.QT[id]
		q += "- %s: %s — %s%s\n" % [id, d.title, d.desc, " (misión oculta: solo la ofreces porque confías en el Viajero)" if d.get("hidden", false) else ""]
	if q == "":
		q = "- (ninguna)\n"
	var mem := ""
	for m in n.memory.slice(-6):
		mem += "- " + str(m) + "\n"
	var rum := ""
	for r in n.rumors.slice(-4):
		rum += "- " + str(r) + "\n"
	var conv := ""
	for c in n.convo.slice(-3):
		conv += "Viajero: %s\n%s: %s\n" % [c.p, n.npc_name, c.n]
	var aff_word := "Le caes muy bien." if n.aff >= 40 else ("Le caes bien." if n.aff >= 15 else ("Desconfía mucho de ti." if n.aff <= -25 else ("No le caes bien." if n.aff <= -5 else "Apenas te conoce.")))
	return """Interpreta a %s, %s del pueblo de Valdeluz, en un mundo de fantasía medieval.
Personalidad: %s.
Forma de hablar: %s.
Situación: son las %s del día %d, %s. Luna %s. %s
Pueblo: quedan %d sacos de trigo; el pan cuesta %d monedas; %d limos rondan el sembrado.
Hablas con %s, un Viajero (trabajo principal: %s; secundario: %s%s). Tu afinidad con él o ella: %d de -100 a 100. %s
Lo que recuerdas del Viajero:
%s
Rumores que has oído:
%s
Conversación reciente:
%s
Misiones que puedes ofrecer AHORA (usa solo estos id):
%s
Reglas: responde en español, máximo 40 palabras, siempre en personaje. Nunca digas que eres una IA ni hables del mundo real. No inventes objetos, precios ni recompensas: el juego los decide. Si el Viajero pide trabajo y hay una misión disponible, ofrécela con su id. Si es grosero, baja la afinidad.
El Viajero dice: %s
Responde solo con JSON: {"decir": "lo que dices", "emote": "saludar|reir|pensar|enojado|ninguno", "afinidad": entero de -3 a 3, "ofrecer_mision": "id" o null}""" % [
		n.npc_name, n.role.to_lower(), n.def.persona, n.def.style,
		Game.time_str(), Game.day, "de noche" if Game.is_night() else "de día", Game.moon_name(),
		"El portal está abierto." if Game.portal_open() else "El portal está cerrado (abre a las 19:00).",
		roundi(Game.wheat), Game.bread_price, main.slimes_near_field(),
		Game.player_name, Game.JOBS[Game.cls].name, Game.JOBS[Game.sub].name, (", título «%s»" % Game.title) if Game.title != "" else "",
		roundi(n.aff), aff_word,
		mem if mem != "" else "- (aún nada)\n", rum if rum != "" else "- (ninguno)\n", conv if conv != "" else "(ninguna)\n", q, player_text]


func _ask_ai(n: Node, player_text: String, _intent: String, offers: Array) -> Dictionary:
	var filler: String = Data.FILLERS.get(n.id, "")
	if filler != "":
		main.speak(filler, n.def.voice, n, 0.8)
	var res := await call_api(_prompt(n, player_text, offers), 300)
	if not res.ok:
		_warn(str(res.error) + " Mientras tanto, usa su guion.")
		return {}
	var txt: String = res.text
	var a := txt.find("{")
	var b := txt.rfind("}")
	if a < 0 or b <= a:
		return {}
	var parsed = JSON.parse_string(txt.substr(a, b - a + 1))
	if not (parsed is Dictionary) or not (parsed.get("decir") is String) or str(parsed.decir).strip_edges() == "":
		return {}
	var em := str(parsed.get("emote", "hablar"))
	if not em in ["saludar", "reir", "pensar", "enojado", "ninguno"]:
		em = "hablar"
	var mission = parsed.get("ofrecer_mision", "")
	return {"decir": str(parsed.decir).substr(0, 280), "emote": em, "afinidad": float(parsed.get("afinidad", 0)), "ofrecer_mision": str(mission) if mission is String else ""}


func _warn(msg: String) -> void:
	if ai_warned and msg == last_error:
		return
	ai_warned = true
	last_error = msg
	Game.say(msg, "bad")


## Llama a la API de Claude. Devuelve {"ok": bool, "text": String, "error": String (explicado), "model": String}.
func call_api(prompt: String, max_tokens: int) -> Dictionary:
	var key := str(Game.settings.api_key).strip_edges()
	if key == "":
		return {"ok": false, "error": "No hay clave de API."}
	if not key.begins_with("sk-ant-"):
		return {"ok": false, "error": "Eso no parece una clave de API de Anthropic (empiezan por «sk-ant-»). Cópiala de console.anthropic.com → API Keys."}
	while model_idx < MODELS.size():
		var http := HTTPRequest.new()
		http.timeout = 20.0
		add_child(http)
		var body := JSON.stringify({"model": MODELS[model_idx], "max_tokens": max_tokens, "messages": [{"role": "user", "content": prompt}]})
		var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + key, "anthropic-version: 2023-06-01"])
		var err := http.request("https://api.anthropic.com/v1/messages", headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			http.queue_free()
			return {"ok": false, "error": "No se pudo abrir la conexión con la IA (¿sin internet?)."}
		var r: Array = await http.request_completed
		http.queue_free()
		if int(r[0]) != HTTPRequest.RESULT_SUCCESS:
			return {"ok": false, "error": "No hubo respuesta de la IA (sin internet o tardó demasiado)."}
		var code: int = r[1]
		var j = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
		if code == 200 and j is Dictionary:
			var txt := ""
			for c in j.get("content", []):
				txt += str(c.get("text", ""))
			last_error = ""
			return {"ok": true, "text": txt, "model": MODELS[model_idx]}
		var etype := ""
		var emsg := ""
		if j is Dictionary and j.get("error") is Dictionary:
			etype = str(j.error.get("type", ""))
			emsg = str(j.error.get("message", ""))
		print("IA: error %d %s: %s (modelo %s)" % [code, etype, emsg, MODELS[model_idx]])
		if code == 404 or (etype == "not_found_error") or (code == 400 and "model" in emsg.to_lower() and not "credit" in emsg.to_lower()):
			model_idx += 1   # ese modelo no existe para esta cuenta: probar el siguiente
			continue
		return {"ok": false, "error": explain_error(code, etype, emsg)}
	model_idx = 0
	return {"ok": false, "error": "Ningún modelo de la lista está disponible para tu cuenta (%s)." % ", ".join(MODELS)}


static func explain_error(code: int, etype: String, msg: String) -> String:
	var m := msg.to_lower()
	if "credit balance" in m or "billing" in m:
		return "Tu cuenta de la API no tiene saldo (error %d). Ojo: la suscripción de Claude (Pro/Max) no incluye la API; se paga aparte. Añade crédito en console.anthropic.com → Billing." % code
	match code:
		401:
			return "Clave no válida (401). Copia otra vez la clave de console.anthropic.com → API Keys."
		403:
			return "La clave no tiene permiso para este modelo (403)."
		413:
			return "La petición era demasiado grande (413)."
		429:
			return "Demasiadas peticiones o límite de gasto alcanzado (429). Espera un poco."
		500, 529:
			return "Los servidores de la IA están saturados (%d). Prueba en un rato." % code
	return "La IA respondió con error %d%s." % [code, (": " + msg) if msg != "" else ""]


## Prueba la clave con una petición mínima. Devuelve el texto a mostrar.
func test_key() -> String:
	var res := await call_api("Responde solo con la palabra: listo", 10)
	if res.ok:
		ai_warned = false
		return "Funciona: la IA responde (modelo %s)." % res.model
	return str(res.error)
