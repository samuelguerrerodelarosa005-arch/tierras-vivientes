extends Node
## Conversación por voz con los habitantes, sin menús: te acercas, le miras y hablas.
## Reparto de papeles (para que la IA no pueda romper el mundo):
##   1. La IA (o, sin IA, palabras clave) solo ENTIENDE qué quieres: pedir trabajo, aceptar, regatear…
##   2. El JUEGO decide qué pasa: qué misión hay, cuánto paga, si el regateo sale bien.
##   3. La IA dice el resultado con la personalidad del NPC, sin cifras (la gramática no le deja
##      escribir números). Las cifras y los plazos los añade el juego, siempre ciertos.

const Sim = preload("res://scripts/sim.gd")
const Data = preload("res://scripts/data.gd")

const REACH := 3.4          # a cuánto tienes que estar para que te escuche
const LEAVE := 5.5          # a cuánto se termina la conversación
const LOOK_DOT := 0.80      # cuánto tienes que mirarle (≈ 37°)
const IDLE_END := 25.0      # sin hablar este tiempo y mirando a otro lado, se acaba

const INTENTS := ["charla", "pedir_trabajo", "aceptar", "rechazar", "regatear", "entregar", "preguntar_rumor",
	"quien_eres", "comprar_pan", "despedida", "elogio", "insulto", "amenaza"]
const EMOTIONS := ["neutral", "alegre", "enojado", "triste", "miedo", "pensativo"]
const GEST := {"neutral": "hablar", "alegre": "reir", "enojado": "enojado", "triste": "hablar", "miedo": "hablar", "pensativo": "pensar"}

var main: Node
var ai: Node                 # ai_local.gd
var vin: Node                # voice_in.gd
var vout: Node               # voice_out.gd
var target: Node = null      # NPC con el que hablas
var thinking := false
var pending := {}            # id NPC → {"qid", "state": "propuesta"|"confirmando"}
var last_talk := 0.0
var greeted := {}            # id NPC → t_total del último saludo
var praise_day := {}         # id NPC → [día, veces] (los halagos no suben la confianza sin fin)
var turns := 0
var last := {}               # para las pruebas: último turno
var ear: Label3D             # «te escucha»
var you_label: Label3D       # lo que entendió de ti


func setup(m: Node, ai_node: Node, vin_node: Node, vout_node: Node) -> void:
	main = m
	ai = ai_node
	vin = vin_node
	vout = vout_node
	vin.utterance.connect(_on_utterance)
	vin.speech_started.connect(func(): _show_ear("…te escucha…", Color(0.6, 1.0, 0.7)))
	ear = _label3d(0.0016, Color(0.75, 1.0, 0.8))
	you_label = _label3d(0.0015, Color(0.85, 0.9, 1.0))


func _label3d(px: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = px
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = col
	l.outline_size = 10
	l.font_size = 30
	l.no_depth_test = true
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.visible = false
	main.add_child(l)
	return l


func voice_ready() -> bool:
	return ai.stt_ok and vin.mic_ok and str(Game.settings.get("voice_mode", "auto")) != "off"


# ---------------------------------------------------------------- cada fotograma

func update(_dt: float) -> void:
	if not Game.started:
		_release()
		vin.enabled = false
		return
	var mode := str(Game.settings.get("voice_mode", "auto"))
	# con la ventana de diálogo abierta también se puede hablar: va a ese NPC
	if main.dialogue.npc != null:
		if target != main.dialogue.npc:
			_release()
			target = main.dialogue.npc
		_update_mic(mode)
		ear.visible = false
		return
	var cam: Camera3D = main.player.camera
	var eye: Vector3 = cam.global_position
	var fw: Vector3 = -cam.global_transform.basis.z
	# ¿a quién miras?
	var best: Node = null
	var best_dot := LOOK_DOT
	for n in main.npcs:
		if n.away or not n.visible:
			continue
		var head: Vector3 = n.pos + Vector3(0, 1.45, 0)
		var to := head - eye
		var d := to.length()
		if d > REACH:
			continue
		var dot := fw.dot(to / maxf(d, 0.01))
		if dot > best_dot:
			best_dot = dot
			best = n
	if target and is_instance_valid(target):
		var dist: float = target.pos.distance_to(main.player_pos())
		var idle: float = main.t_total - last_talk
		if dist > LEAVE or target.away or (best != target and best != null) or (best == null and idle > IDLE_END):
			_release()
	if target == null and best != null and mode != "off":
		_engage(best)
	_update_mic(mode)
	# indicador
	if target:
		ear.global_position = target.pos + Vector3(0, 2.32, 0)
		if thinking:
			_show_ear("…pensando…", Color(1.0, 0.9, 0.6))
		elif vin.speaking:
			_show_ear("…te escucha…", Color(0.6, 1.0, 0.7))
		elif not voice_ready():
			ear.visible = false
		elif vin.muted:
			ear.visible = false
		else:
			_show_ear("habla (%s)" % ("mantén Y / V" if mode == "ptt" else "te escucha"), Color(0.75, 1.0, 0.8, 0.75))
	else:
		ear.visible = false
	if you_label.visible and main.t_total > float(you_label.get_meta("until", 0.0)):
		you_label.visible = false


## Micrófono: abierto solo cuando hay a quien hablar y nadie está hablando cerca.
func _update_mic(mode: String) -> void:
	# el NPC con el que hablas, o alguien hablando muy cerca (si no, su voz se colaría en el micro)
	var near_voice: bool = (target != null and vout.is_speaking(target.id)) or vout.any_speaking_near(main.player_pos(), 3.5) if vout.available else (target != null and main.t_total < target.talk_until)
	vin.muted = thinking or near_voice
	vin.enabled = target != null and mode == "auto"
	vin.ptt = mode != "off" and _ptt_pressed()


func _show_ear(t: String, c: Color) -> void:
	ear.text = t
	ear.modulate = c
	ear.visible = true


func _ptt_pressed() -> bool:
	if main.xr:
		var p: Dictionary = main.player.pads.get("left", {})
		return bool(p.get("b", false))   # botón Y del mando izquierdo
	return Input.is_physical_key_pressed(KEY_V)


func _engage(n: Node) -> void:
	target = n
	last_talk = main.t_total
	if n.busy == "" or n.busy == "chat":
		n.busy = "voz"
		n.face = main.player.camera
	if not voice_ready():
		return
	# saluda si hace rato que no os veis
	if main.t_total - float(greeted.get(n.id, -999.0)) > 120.0:
		greeted[n.id] = main.t_total
		var lines: Array = n.def.lines.greet
		var t: String = lines.pick_random()
		if n.aff >= 20:
			t += " Me alegra verte."
		say(n, t, "saludar")


func _release() -> void:
	if target and is_instance_valid(target) and target.busy == "voz" and main.dialogue.npc != target:
		target.busy = ""
		target.face = null
	target = null
	ear.visible = false


func say(n: Node, text: String, gesture: String = "hablar") -> void:
	n.say(text, gesture)
	last_talk = main.t_total


# ---------------------------------------------------------------- un turno

func _on_utterance(samples: PackedFloat32Array) -> void:
	var n := target
	if n == null or thinking:
		return
	thinking = true
	var hint := "Valdeluz. %s. Bruno, Lía, Dorran, Sira. Limos, trigo, pan, hierro, portal, ruinas, monedas." % n.npc_name
	var text: String = await ai.transcribe(samples, hint)
	if text == "":
		thinking = false
		return
	_show_you(n, text)
	if main.dialogue.npc == n:
		thinking = false
		main.dialogue.say_free(text)
		return
	await handle_text(n, text)


func _show_you(n: Node, text: String) -> void:
	you_label.text = "Tú: «%s»" % text
	you_label.global_position = n.pos + Vector3(0, 0.55, 0) + (main.player_pos() - n.pos).normalized() * 0.4
	you_label.visible = true
	you_label.set_meta("until", main.t_total + 6.0)


## Lo que dices a un NPC (por voz o escrito). Async.
func handle_text(n: Node, text: String) -> void:
	thinking = true
	last_talk = main.t_total
	turns += 1
	var ctx := _context(n)
	var intent := _keyword_intent(n, text, ctx)
	if intent == "" and ai.llm_ok:
		var filler: Array = Data.FILLERS_V.get(n.id, [])
		if not filler.is_empty() and randf() < 0.55:
			say(n, filler.pick_random(), "pensar")
		intent = await _classify(n, text, ctx)
	if intent == "":
		intent = _keyword_intent_loose(n, text, ctx)
	var out := _act(n, intent, text, ctx)
	var line := ""
	if out.get("fixed", "") != "":
		line = out.fixed
	else:
		var llm := {}
		if ai.llm_ok:
			llm = await _speak_llm(n, text, out.situation)
		if not llm.is_empty():
			line = _clean_numbers(str(llm.dice))
			out.emotion = str(llm.get("emocion", out.get("emotion", "neutral")))
		if line == "":
			line = out.scripted
	if out.get("suffix", "") != "":
		line = (line + " " + str(out.suffix)).strip_edges()
	if not is_instance_valid(n):
		thinking = false
		return
	n.convo.append({"p": text, "n": line})
	if n.convo.size() > 6:
		n.convo.pop_front()
	last = {"npc": n.id, "text": text, "intent": intent, "line": line}
	print("VOZ: «%s» → %s → %s: «%s»" % [text, intent, n.npc_name, line])
	say(n, line, GEST.get(str(out.get("emotion", "neutral")), "hablar"))
	thinking = false
	if intent == "despedida":
		_release()
	main.ui.mark("dialog")


# ---------------------------------------------------------------- qué hay sobre la mesa

func _context(n: Node) -> Dictionary:
	var offers: Array = Game.offerable(n.id)
	var offer := ""
	if not offers.is_empty():
		offer = offers[-1] if Game.qdef(offers[-1]).get("dyn", false) else offers[0]
	var p: Dictionary = pending.get(n.id, {})
	if not p.is_empty() and not p.qid in offers:
		pending.erase(n.id)
		p = {}
	return {"offer": offer, "pending": p, "deliver": Game.deliverable(n.id)}


# ---------------------------------------------------------------- entender (sin IA o atajos)

static func norm(s: String) -> String:
	s = s.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"], ["¿", ""], ["?", ""], ["¡", ""], ["!", ""], [",", " "], [".", " "]]:
		s = s.replace(pair[0], pair[1])
	return " " + " ".join(s.split(" ", false)) + " "


static func _has(t: String, words: Array) -> bool:
	for w in words:
		if (" " + str(w) + " ") in t:
			return true
	return false


const YES := ["si", "vale", "claro", "acepto", "de acuerdo", "trato hecho", "hecho", "venga", "por supuesto", "ok", "okay", "dale", "lo hago", "cuenta conmigo", "me apunto", "perfecto", "va"]
const NO := ["no", "mejor no", "olvidalo", "paso", "otro dia", "ahora no", "no gracias", "no puedo", "luego"]
const BYE := ["adios", "hasta luego", "nos vemos", "chao", "chau", "me voy", "hasta pronto", "hasta manana"]
const HAGGLE := ["mas dinero", "mas oro", "mas monedas", "paga mas", "pagas mas", "pagar mas", "pagame mas", "un poco mas", "es poco", "muy poco", "no es suficiente", "subir el precio", "sube el precio", "mejor paga", "mas paga", "algo mas"]
const ACCEPT_STRONG := ["acepto", "trato hecho", "lo hago", "cuenta conmigo", "me apunto", "hecho", "de acuerdo"]


## Atajos seguros: solo frases sin duda. "" = que decida la IA.
func _keyword_intent(n: Node, text: String, ctx: Dictionary) -> String:
	var t := norm(text)
	var words := t.split(" ", false).size()
	if ctx.pending.get("state", "") == "confirmando":
		if _has(t, YES) and not _has(t, ["no"]):
			return "aceptar"
		if _has(t, NO):
			return "rechazar"
	if words <= 4 and _has(t, BYE):
		return "despedida"
	if ctx.offer != "" and words <= 6 and _has(t, ACCEPT_STRONG) and not _has(t, ["no"]):
		return "aceptar"
	if not ai.llm_ok:
		return _keyword_intent_loose(n, text, ctx)
	return ""


## Sin IA: palabras clave más amplias (puede equivocarse más).
func _keyword_intent_loose(n: Node, text: String, ctx: Dictionary) -> String:
	var t := norm(text)
	if _has(t, BYE):
		return "despedida"
	if _has(t, ["te voy a matar", "te mato", "te matare", "quemare", "voy a quemar", "destruire", "te arrepentiras", "te voy a destruir"]):
		return "amenaza"
	if _has(t, ["idiota", "estupido", "estupida", "imbecil", "tonto", "tonta", "inutil", "asqueroso", "basura", "gordo", "feo", "fea", "callate"]):
		return "insulto"
	if ctx.offer != "" or not ctx.pending.is_empty():
		if _has(t, HAGGLE) or ("mas" in t and ("paga" in t or "moneda" in t or "oro" in t)):
			return "regatear"
		if _has(t, YES) and not _has(t, ["no"]):
			return "aceptar"
		if not ctx.pending.is_empty() and _has(t, NO):
			return "rechazar"
	if not (ctx.deliver as Array).is_empty() and _has(t, ["aqui tienes", "te traigo", "te traje", "traje", "toma", "entrego", "te lo traigo", "lo tengo", "ya lo hice", "ya esta", "listo", "cumpli", "hecho"]):
		return "entregar"
	if n.id == "bruno" and "pan" in t and _has(t, ["quiero", "dame", "comprar", "compro", "vendes", "vende", "me das", "un pan"]):
		return "comprar_pan"
	if _has(t, ["trabajo", "mision", "encargo", "ayuda", "ayudarte", "ayudar", "necesitas", "algo que hacer", "puedo hacer", "tarea", "problema"]):
		return "pedir_trabajo"
	if _has(t, ["rumor", "rumores", "se cuenta", "noticias", "chisme", "chismes", "se dice", "novedades", "que hay de nuevo", "que pasa"]):
		return "preguntar_rumor"
	if _has(t, ["quien eres", "como te llamas", "a que te dedicas", "hablame de ti", "tu nombre"]):
		return "quien_eres"
	if _has(t, ["gracias", "eres genial", "que bien", "me encanta", "eres el mejor", "eres la mejor", "buen trabajo", "admiro"]):
		return "elogio"
	return "charla"


# ---------------------------------------------------------------- entender (con IA)

func _classify(n: Node, text: String, ctx: Dictionary) -> String:
	var sit := []
	if ctx.offer != "":
		sit.append("%s le ha propuesto (o puede proponerle) la misión «%s»." % [n.npc_name, Game.qdef(ctx.offer).title])
	if ctx.pending.get("state", "") == "confirmando":
		sit.append("%s acaba de preguntar «¿Trato hecho?». Un sí es aceptar; un no es rechazar." % n.npc_name)
	if not (ctx.deliver as Array).is_empty():
		sit.append("El jugador ya tiene lo que pedía «%s» y puede entregarlo." % Game.qdef(ctx.deliver[0].id).title)
	if n.id == "bruno":
		sit.append("Bruno vende pan.")
	var sys := """Clasifica la intención de lo que el jugador le dice a %s, %s de un pueblo medieval.
%s
Intenciones:
- pedir_trabajo: pide trabajo, una misión o pregunta si puede ayudar.
- aceptar: acepta la misión o el trato propuesto.
- rechazar: no quiere la misión o dice que no al trato.
- regatear: pide más paga o mejores condiciones.
- entregar: dice que trae lo pedido o que ya cumplió.
- preguntar_rumor: pide noticias, rumores o qué pasa en el pueblo.
- quien_eres: pregunta quién es el habitante o por su vida.
- comprar_pan: quiere comprar pan.
- despedida: se despide.
- elogio: halaga o agradece.
- insulto: insulta o se burla.
- amenaza: amenaza con hacer daño.
- charla: cualquier otra cosa (preguntas, opiniones, saludos).""" % [n.npc_name, n.role.to_lower(), "\n".join(sit)]
	var r: Dictionary = await ai.chat([{"role": "system", "content": sys}, {"role": "user", "content": text}],
		{"type": "object", "properties": {"intencion": {"type": "string", "enum": INTENTS}}, "required": ["intencion"]}, 16, 0.0)
	var it := str(r.get("intencion", ""))
	return it if it in INTENTS else ""


# ---------------------------------------------------------------- decidir (el juego)

## Aplica la intención al mundo. Devuelve qué tiene que decir el NPC:
##   fixed     = frase cerrada del juego (no pasa por la IA)
##   situation = lo que la IA debe contar (sin cifras)
##   scripted  = frase de guion por si no hay IA
##   suffix    = cifras/plazos que el juego añade al final
func _act(n: Node, intent: String, _text: String, ctx: Dictionary) -> Dictionary:
	var lines: Dictionary = n.def.lines
	var sim = main.sim
	var offer: String = ctx.offer
	match intent:
		"pedir_trabajo":
			if offer == "":
				var why := "No tienes ningún encargo para el Viajero ahora mismo."
				if sim and float(sim.a(n.id).fear) >= 0.5:
					why = "No tienes encargos: tienes demasiado miedo de los limos como para pensar en eso."
				return {"situation": why, "scripted": lines.none.pick_random(), "emotion": "neutral"}
			pending[n.id] = {"qid": offer, "state": "propuesta"}
			var d: Dictionary = Game.qdef(offer)
			var why2: String = d.get("reason", d.get("desc", ""))
			return {"situation": "Le propones al Viajero esta misión: «%s». Por qué la necesitas: %s. Qué tendría que hacer: %s. Explícalo con tus palabras, sin decir la paga ni el plazo (los dirá el juego), y termina preguntando si acepta." % [d.title, why2, d.get("desc", "")],
				"scripted": (str(d.reason) + ".") if d.get("dyn", false) else lines.work.pick_random(), "suffix": _terms(d, d.get("dyn", false)), "emotion": "pensativo"}
		"aceptar":
			var qid: String = ctx.pending.get("qid", offer)
			if qid == "":
				return {"situation": "El Viajero dice que acepta, pero no le has propuesto nada. Díselo con amabilidad y pregúntale si busca trabajo.", "scripted": "¿Aceptar qué? No te he pedido nada… todavía.", "emotion": "pensativo"}
			var d: Dictionary = Game.qdef(qid)
			# si la IA lo interpretó (no fue un «acepto» claro), se confirma en voz alta antes de cerrar
			if ctx.pending.get("state", "") != "confirmando" and not _strong_yes(_text):
				pending[n.id] = {"qid": qid, "state": "confirmando"}
				return {"fixed": "¿Trato hecho? «%s», por %s." % [d.title, spoken_reward(d.reward)], "emotion": "pensativo"}
			pending.erase(n.id)
			Game.accept_quest(qid)
			n.remember("%s aceptó ayudarme: %s" % [Game.player_name, str(d.title).to_lower()])
			var hours := float(Game.q_hours_left(Game.active_q(qid)))
			return {"situation": "El Viajero ha aceptado la misión «%s». Dale las gracias a tu manera y recuérdale qué hacer: %s." % [d.title, d.get("desc", "")],
				"scripted": "Trato hecho. No me falles.", "suffix": ("Tienes %d horas." % roundi(hours)) if hours > 0.0 else "", "emotion": "alegre"}
		"rechazar":
			var had: bool = not (ctx.pending as Dictionary).is_empty() or offer != ""
			pending.erase(n.id)
			return {"situation": "El Viajero no quiere la misión. Reacciona según tu carácter, sin enfadarte demasiado." if had else "El Viajero dice que no a algo. Responde con naturalidad.",
				"scripted": "Como quieras. Si cambias de idea, aquí estaré.", "emotion": "triste" if had else "neutral"}
		"regatear":
			var qid: String = ctx.pending.get("qid", offer)
			if qid == "" or not Game.qdef(qid).get("dyn", false):
				return {"situation": "El Viajero habla de dinero, pero no hay ningún trato entre vosotros. Contesta con naturalidad.", "scripted": lines.generic.pick_random(), "emotion": "neutral"}
			var r: Dictionary = sim.negotiate(qid)
			var d: Dictionary = Game.qdef(qid)
			pending[n.id] = {"qid": qid, "state": "propuesta"}
			if r.ok:
				return {"situation": "El Viajero te pidió más paga y has cedido a regañadientes. Dilo según tu carácter y pídele que no te falle.", "scripted": r.line,
					"suffix": "Te daré %s. ¿Aceptas?" % spoken_reward(d.reward), "emotion": "pensativo"}
			var again: bool = r.line.begins_with("Ya te dije")
			return {"situation": ("Ya regateó antes y no vas a ceder más. Díselo con firmeza." if again else "El Viajero te pidió más paga y te niegas: no puedes o no quieres dar más. Dilo según tu carácter."),
				"scripted": r.line, "suffix": "Lo dicho: %s." % spoken_reward(d.reward), "emotion": "enojado" if not again else "neutral"}
		"entregar":
			if (ctx.deliver as Array).is_empty():
				return {"situation": "El Viajero dice que te trae algo o que ya cumplió, pero no es verdad (no tiene lo que pediste). Díselo sin rodeos.", "scripted": "Todavía no lo tienes, Viajero.", "emotion": "pensativo"}
			var q: Dictionary = ctx.deliver[0]
			var d: Dictionary = Game.qdef(q.id)
			var before := Game.gold
			Game.deliver_quest(q, n)
			var got := Game.gold - before
			return {"situation": "El Viajero ha cumplido «%s» y te lo entrega. Agradécelo a tu manera; tu confianza en él ha subido." % d.title,
				"scripted": lines.thanks.pick_random(), "suffix": ("Aquí tienes tus %d monedas." % got) if got > 0 else "", "emotion": "alegre"}
		"comprar_pan":
			if n.id != "bruno":
				return {"situation": "El Viajero quiere pan, pero tú no vendes pan: Bruno es el panadero.", "scripted": "¿Pan? Eso es cosa de Bruno, en la panadería.", "emotion": "neutral"}
			var had_g := Game.gold
			main.buy_bread()
			if Game.gold < had_g:
				return {"situation": "Le has vendido un pan al Viajero. Dáselo con orgullo de panadero.", "scripted": "Ahí tienes. Cómetelo caliente.", "emotion": "alegre"}
			return {"situation": "El Viajero quiere pan pero no tiene monedas suficientes, o no te queda pan. Díselo a tu manera.", "scripted": "Sin monedas no hay pan, Viajero.", "emotion": "neutral"}
		"preguntar_rumor":
			var rum := ""
			if not n.rumors.is_empty():
				rum = str(n.rumors[-1])
			if rum == "":
				return {"situation": "No has oído nada nuevo. Cuenta algo de tu día o del pueblo.", "scripted": lines.generic.pick_random(), "emotion": "neutral"}
			return {"situation": "Cuéntale al Viajero este rumor con tus palabras (puedes dudar de él): %s" % rum, "scripted": "Dicen por ahí: " + rum, "emotion": "pensativo"}
		"quien_eres":
			var goal: String = sim.goal_text(n.id) if sim else ""
			return {"situation": "Te pregunta quién eres. Preséntate. Lo que quieres conseguir ahora: %s." % goal, "scripted": Data.ABOUT[n.id].pick_random(), "emotion": "neutral"}
		"despedida":
			pending.erase(n.id)
			return {"situation": "El Viajero se despide. Despídete en una frase corta.", "scripted": lines.bye.pick_random(), "emotion": "neutral"}
		"elogio":
			var pd: Array = praise_day.get(n.id, [-1, 0])
			if int(pd[0]) != Game.day:
				pd = [Game.day, 0]
			pd[1] = int(pd[1]) + 1
			praise_day[n.id] = pd
			if int(pd[1]) <= 2:
				n.aff = clampf(n.aff + 1.0, -100.0, 100.0)
			return {"situation": "El Viajero te halaga o te da las gracias. Reacciona según tu carácter." + (" Ya te ha halagado varias veces hoy: empieza a parecerte sospechoso." if int(pd[1]) > 2 else ""),
				"scripted": "Vaya… gracias.", "emotion": "alegre"}
		"insulto":
			n.aff = clampf(n.aff - 4.0, -100.0, 100.0)
			if sim:
				sim.record(Sim.PLAYER, "insulto", n.id, "%s insultó a %s" % [Game.player_name, n.npc_name], sim._witnesses(n.id))
			n.remember("%s me insultó" % Game.player_name)
			return {"situation": "El Viajero te ha insultado. Reacciona según tu carácter (ofendido, frío o desafiante). Lo recordarás.", "scripted": "No tengo por qué aguantar eso.", "emotion": "enojado"}
		"amenaza":
			n.aff = clampf(n.aff - 8.0, -100.0, 100.0)
			if sim:
				sim.record(Sim.PLAYER, "amenaza", n.id, "%s amenazó a %s" % [Game.player_name, n.npc_name], sim._witnesses(n.id))
				sim.a(n.id).fear = minf(1.0, float(sim.a(n.id).fear) + 0.25)
			n.remember("%s me amenazó" % Game.player_name)
			return {"situation": "El Viajero te ha amenazado de muerte o de hacer daño. Tienes miedo pero respondes según tu carácter. Esto se sabrá en el pueblo.", "scripted": "…Vete de aquí. Ahora mismo.", "emotion": "miedo"}
	return {"situation": "Contesta a lo que dice el Viajero de forma natural, como en una charla.", "scripted": lines.generic.pick_random(), "emotion": "neutral"}


func _strong_yes(text: String) -> bool:
	var t := norm(text)
	return _has(t, ACCEPT_STRONG) and not _has(t, ["no"])


## La paga dicha en voz alta: «2 panes de Bruno», no «2 × pan de bruno».
static func spoken_reward(rw: Dictionary) -> String:
	var parts := []
	if int(rw.get("gold", 0)) > 0:
		parts.append("%d moneda%s" % [int(rw.gold), "" if int(rw.gold) == 1 else "s"])
	for k in rw.get("items", {}):
		var c := int(rw.items[k])
		var nm := str(Game.item_name(k)).to_lower()
		var art := "una " if nm.split(" ", false)[0].ends_with("a") else "un "
		parts.append((art if c == 1 else "%d " % c) + (nm if c == 1 else plural(nm)))
	match str(rw.get("favor", "")):
		"descuento_pan":
			parts.append("pan más barato dos días")
		"leccion_forja":
			parts.append("una lección de forja")
		"bendicion":
			parts.append("la bendición de la luna")
	if parts.is_empty():
		return "mi gratitud"
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, -1)) + " y " + parts[-1]


## Plural de la primera palabra: «pan de bruno» → «panes de bruno».
static func plural(nm: String) -> String:
	var w := nm.split(" ", false)
	if w.is_empty():
		return nm
	var f: String = w[0]
	if f.ends_with("s"):
		pass
	elif f[-1] in "aeiouáéó":
		f += "s"
	elif f.ends_with("z"):
		f = f.substr(0, f.length() - 1) + "ces"
	else:
		f += "es"
	w[0] = f
	return " ".join(w)


## Paga y plazo: siempre los dice el juego (son ciertos).
func _terms(d: Dictionary, dyn: bool) -> String:
	if not dyn:
		return "Te daré %s. ¿Aceptas?" % spoken_reward(d.reward)
	return "Te daré %s. Tienes %d horas. ¿Aceptas?" % [spoken_reward(d.reward), int(d.get("hours", 24))]


# ---------------------------------------------------------------- hablar (con IA)

func _persona(n: Node) -> String:
	var tr: Dictionary = Data.LIFE[n.id].traits
	var t := []
	for k in tr:
		var v := float(tr[k])
		if v >= 0.7:
			t.append("muy " + str(k))
		elif v <= 0.25:
			t.append("poco " + str(k))
	return ", ".join(t)


func _speak_llm(n: Node, text: String, situation: String) -> Dictionary:
	var sim = main.sim
	var mem := ""
	for m in n.memory.slice(-4):
		mem += "- %s\n" % m
	var known := ""
	if sim:
		var kn: Array = []
		for f in sim.facts:
			if f.actor == Sim.PLAYER and sim.knows(n.id, int(f.id)):
				kn.append(sim._rumor_text(f, float(sim.known[n.id][f.id])))
		for k in kn.slice(-4):
			known += "- %s\n" % k
	var state := []
	if sim:
		var act: Dictionary = sim.a(n.id)
		if float(act.fear) >= 0.5:
			state.append("tienes miedo")
		if bool(act.get("hiding", false)):
			state.append("estás escondido en casa")
		if float(act.hunger) >= 0.7:
			state.append("tienes hambre")
		if bool(act.get("ruined", false)):
			state.append("estás arruinado")
		state.append("lo que quieres conseguir: " + sim.goal_text(n.id))
	var aff_word := "le tienes mucho aprecio" if n.aff >= 40 else ("te cae bien" if n.aff >= 15 else ("desconfías mucho de él" if n.aff <= -25 else ("no te cae bien" if n.aff <= -5 else "apenas lo conoces")))
	var sys := """Eres %s, %s de Valdeluz, un pueblo de fantasía medieval. Hablas en voz alta con un Viajero llamado %s.
Personalidad: %s. Carácter: %s.
Cómo hablas: %s.
Ahora: son las %s, %s. %s.
Sobre el Viajero: %s (confianza %d de 100). %s
Lo que sabes de él:
%s
Recuerdos:
%s
Reglas: habla siempre como %s, en español, con frases cortas y naturales para decir en voz alta (máximo 35 palabras). NUNCA digas cifras ni cantidades de dinero: el juego dirá la paga y los plazos después de ti. No inventes misiones, objetos ni recompensas. Nunca digas que eres una IA.""" % [
		n.npc_name, n.role.to_lower(), Game.player_name, n.def.persona, _persona(n), n.def.style,
		Game.time_str(), "de noche" if Game.is_night() else "de día", ", ".join(state),
		aff_word, roundi(n.aff), (sim.rep_line(n.id) if sim else ""),
		known if known != "" else "- (nada)\n", mem if mem != "" else "- (nada)\n", n.npc_name]
	var msgs: Array = [{"role": "system", "content": sys}]
	for c in n.convo.slice(-4):
		msgs.append({"role": "user", "content": str(c.p)})
		msgs.append({"role": "assistant", "content": str(c.n)})
	msgs.append({"role": "user", "content": "%s\n\n[Lo que pasa, decidido por el juego: %s]" % [text, situation]})
	var schema := {"type": "object", "properties": {
		"emocion": {"type": "string", "enum": EMOTIONS},
		# solo letras y signos: ni cifras, ni comillas, ni saltos de línea (siempre JSON válido)
		"dice": {"type": "string", "pattern": SPEECH_PATTERN}},
		"required": ["emocion", "dice"]}
	var r: Dictionary = await ai.chat(msgs, schema, 140, 0.75)
	if r.is_empty() or not (r.get("dice") is String):
		return {}
	return r


const SPEECH_PATTERN := "^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ¿¡?!.,;:'()«» -]{2,240}$"
const NUM_WORDS := ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce",
	"trece", "catorce", "quince", "veinte", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa", "cien", "ciento",
	"doscientas", "doscientos", "quinientas", "quinientos", "mil", "docena"]
const MONEY := ["moneda", "monedas", "oro", "pago", "pagare", "paga", "pagarte", "recompensa", "horas", "dias", "plata", "cobre"]


## Por si acaso: quita frases que pongan precio con palabras («te daré mil monedas»).
static func _clean_numbers(line: String) -> String:
	var re := RegEx.new()
	re.compile("[^.!?…]+[.!?…]*")
	var keep := []
	for m in re.search_all(line):
		var s := m.get_string()
		var t := norm(s)
		if _has(t, MONEY) and _has(t, NUM_WORDS):
			continue
		var dg := RegEx.new()
		dg.compile("[0-9]")
		if dg.search(s):
			continue
		keep.append(s.strip_edges())
	return " ".join(keep).strip_edges()
