extends Node
## Simulación del mundo vivo (fase 1). Es la autoridad: decide la economía, lo que los NPC
## saben, su reputación del jugador, sus ambiciones y las misiones que ofrecen.
## La parte visual (npc.gd, ui.gd) solo lee de aquí. Pensada para poder moverse a un servidor:
## el jugador es un "actor" más ("jugador"), igual que los NPC.
##
## Piezas:
##   • Fichas de vida (Data.LIFE): rasgos, dinero e inventario reales, miedo, necesidades, opinión de los demás.
##   • Economía: Lía siembra trigo si se atreve a salir, Bruno lo hornea, todos comen pan y lo pagan.
##   • Hechos y rumores: cada acto queda como hecho con testigos; en las charlas se contagia y se distorsiona.
##   • Reputación por ejes (miedo, respeto, cariño) además de la confianza (n.aff).
##   • Director: lee el mundo, propone misiones con plantillas y paga con lo que el NPC tiene.
##   • Cadenas: cada final de misión cambia el mundo y puede abrir otra misión.

const Data = preload("res://scripts/data.gd")
const PLAYER := "jugador"

# plantillas de misión: tipo de progreso, plazo (horas de juego) y confianza mínima
const TEMPLATES := {
	"traer": {"type": "item", "hours": 30, "trust": -25, "base": 1.6},
	"cazar": {"type": "kill", "hours": 18, "trust": -25, "base": 5.0},
	"escoltar": {"type": "escort", "hours": 6, "trust": 5, "base": 14.0},
	"entregar": {"type": "item", "hours": 24, "trust": 0, "base": 9.0},
	"explorar": {"type": "visit", "hours": 48, "trust": 0, "base": 18.0},
}
const OFFER_HOURS := 14.0     # una oferta no aceptada caduca
# confianza mínima según el sitio: a las Ruinas solo se manda a alguien de mucha confianza
const SPOT_TRUST := {"ruinas": 15.0, "portal": 5.0}
const FEAR_HIDE := 0.65       # por encima, un NPC poco valiente no sale a trabajar al campo

var main: Node
var actors := {}              # id -> ficha viva
var facts: Array = []         # {id, t, actor, verb, target, text}
var known := {}               # npc_id -> {fact_id: certeza 0..1}
var next_fact := 1
var defs := {}                # misiones dinámicas: id -> definición
var offers := {}              # npc_id -> id de misión ofrecida (pendiente)
var escrow := {}              # id de misión -> oro reservado por el NPC
var followups: Array = []     # [{giver, template, params, parent, at}]
var next_q := 1
var pan_stock := 12.0
var called_at := {}           # npc_id -> t_total del último aviso al jugador
var stats := {"generated": 0, "chained": 0, "invalid": 0, "success": 0, "failed": 0, "expired_offers": 0,
	"steps_up": 0, "steps_down": 0, "hides": 0, "by_template": {}, "price_min": 99, "price_max": 0, "negotiations": 0}


func setup(m: Node) -> void:
	main = m
	for id in Data.LIFE:
		var L: Dictionary = Data.LIFE[id]
		actors[id] = {
			"gold": float(L.gold), "items": (L.items as Dictionary).duplicate(), "hunger": randf_range(0.0, 0.4),
			"fear": 0.0, "hiding": false, "rep": {"miedo": 0.0, "respeto": 0.0, "carino": 0.0},
			"step": 0, "ruined": false, "op": (L.op as Dictionary).duplicate(),
		}
		known[id] = {}


func traits(id: String) -> Dictionary:
	return Data.LIFE[id].traits


func a(id: String) -> Dictionary:
	return actors[id]


func npc(id: String) -> Node:
	return Game.npcs.get(id)


func trust(id: String) -> float:
	var n := npc(id)
	return float(n.aff) if n else 0.0


func goal_text(id: String) -> String:
	var lad: Array = Data.LIFE[id].ladder
	var st: Dictionary = lad[clampi(int(a(id).step), 0, lad.size() - 1)]
	return ("arruinado: " if a(id).ruined else "") + str(st.goal)


# ======================================================================
# Cerebro: dónde quiere estar cada NPC (sobrescribe el horario si hace falta)
# ======================================================================

## "" = sigue su horario normal. Lo llama npc.sched_place().
func override_place(id: String, sched: String) -> String:
	var act: Dictionary = a(id)
	# acompañar: espera en su puerta y solo camina al campo con el jugador cerca
	var esc := escort_quest(id)
	if not esc.is_empty():
		var d: Dictionary = qdef(esc.id)
		if int(esc.progress) >= 1:
			return str(d.dest_place)
		var n := npc(id)
		if n and n.pos.distance_to(main.player_pos()) < 7.0:
			return str(d.dest_place)
		return "lia_door" if id == "lia" else str(Data.LIFE[id].home)
	# miedo: el poco valiente no sale a trabajar al campo
	if act.hiding and sched in Data.LIFE[id].work:
		return str(Data.LIFE[id].home)
	return ""


func escort_quest(id: String) -> Dictionary:
	for q in Game.quests:
		var d: Dictionary = qdef(q.id)
		if d.get("template", "") == "escoltar" and d.giver == id:
			return q
	return {}


## El NPC acompañado no camina si el jugador se aleja.
func escort_wait(n: Node) -> bool:
	var esc := escort_quest(n.id)
	if esc.is_empty() or int(esc.progress) >= 1:
		return false
	return n.pos.distance_to(main.player_pos()) > 7.0


# ======================================================================
# Reloj: economía, necesidades, miedo, ambiciones y director (cada hora de juego)
# ======================================================================

func hour_tick() -> void:
	var h := Game.hour_now()
	var day_work := h >= 6 and h < 19
	var pests: int = main.slimes_near_field()
	var lia_n := npc("lia")
	var bruno_n := npc("bruno")
	# --- trigo: Lía lo siembra si está en el campo; los limos se lo comen ---
	var lia_working: bool = lia_n != null and day_work and str(lia_n.place) in ["field", "field2"] and not a("lia").hiding
	if lia_working:
		Game.wheat += 3.2 if pests < 3 else 1.2
	if pests >= 3:
		Game.wheat -= 1.4
	# Lía vende el trigo que sobra a los comerciantes de paso
	if day_work and Game.wheat > 40.0:
		Game.wheat -= 1.0
		a("lia").gold += 1.5
	# --- pan: Bruno hornea lo que se va a comer y le compra el trigo a Lía ---
	if bruno_n != null and day_work and str(bruno_n.place) == "bakery" and Game.wheat >= 2.0 and pan_stock < 16.0:
		Game.wheat -= 2.0
		pan_stock += 3.0
		_pay("bruno", "lia", 3.0)
	# el pan que sobra se vende a los viajeros
	if day_work and pan_stock > 18.0:
		pan_stock -= 1.0
		a("bruno").gold += 3.0
	Game.wheat = clampf(Game.wheat, 0.0, 60.0)
	# --- hierro y forja ---
	if day_work and h >= 7 and h < 18:
		if Game.iron >= 0.35:
			Game.iron -= 0.35
			a("dorran").gold += 2.0   # vende herramientas y herraduras
	Game.iron = maxf(0.0, Game.iron)
	# --- Sira recibe del pueblo por guardar el portal ---
	if h == 8:
		a("sira").gold += 12.0   # diezmo del Santuario
	# --- Dorran compra mineral a los comerciantes si puede ---
	if h == 9 and float(a("dorran").gold) > 15.0 and Game.iron < 4.0:
		a("dorran").gold = float(a("dorran").gold) - 4.0
		Game.iron += 1.0
	# --- perdón: la desconfianza se va pasando con el tiempo, según el carácter ---
	if h == 12:
		for id in actors:
			var n0 := npc(id)
			if n0 and n0.aff < 0.0:
				var tr0 := traits(id)
				n0.aff = minf(0.0, n0.aff + 1.0 + 2.0 * float(tr0.generosidad) + 1.0 * float(tr0.lealtad))
	# --- herramientas: Lía y Bruno compran a Dorran ---
	if h == 10:
		if float(a("lia").gold) > 25.0 and Game.day % 3 == 0:
			_pay("lia", "dorran", 4.0)
		if float(a("bruno").gold) > 20.0:
			_pay("bruno", "dorran", 4.0)
	# --- impuesto de la capital: saca dinero del pueblo (el monopolio que Bruno quiere romper) ---
	if h == 6:
		for id in actors:
			var g := float(a(id).gold)
			if g > 40.0:
				a(id).gold = g - (g - 40.0) * 0.06
	# --- quien tiene de sobra gasta (taberna, regalos): el dinero circula ---
	if h == 20:
		for id in actors:
			var rich := float(a(id).gold)
			if rich > 120.0:
				var spend := rich * 0.1
				a(id).gold = rich - spend
				for other in actors:
					if other != id:
						a(other).gold = float(a(other).gold) + spend / float(actors.size() - 1)
	# --- Lía recoge manzanas una vez al día ---
	if h == 7:
		a("lia").items["manzana"] = mini(int(a("lia").items.get("manzana", 0)) + 2, 10)
	# --- comer: cada NPC compra pan a Bruno cuando tiene hambre ---
	for id in actors:
		var act: Dictionary = actors[id]
		act.hunger = minf(1.0, float(act.hunger) + 1.0 / 14.0)
		if float(act.hunger) >= 0.7 and pan_stock >= 1.0:
			pan_stock -= 1.0
			act.hunger = 0.0
			if id != "bruno":
				_pay(id, "bruno", float(Game.bread_price))
	_update_prices()
	# --- miedo ---
	for id in actors:
		var act2: Dictionary = actors[id]
		var tr := traits(id)
		var n := npc(id)
		if pests >= 3 and n != null and str(n.place) in ["field", "field2"] and day_work:
			act2.fear = minf(1.0, float(act2.fear) + 0.12 * (1.0 + float(tr.miedo)))
		act2.fear = maxf(0.0, float(act2.fear) - 0.035 * (1.0 + float(tr.valentia)))
		var was: bool = act2.hiding
		act2.hiding = float(act2.fear) >= FEAR_HIDE and float(tr.valentia) < 0.6
		if act2.hiding and not was:
			stats.hides += 1
			record(id, "se_escondio", "", "%s tiene miedo de salir al campo" % Game.npcs[id].npc_name if Game.npcs.has(id) else "", [id])
	# --- ambiciones ---
	for id in actors:
		_check_ladder(id)
	# --- misiones: caducidad, seguimiento y director ---
	_expire()
	_run_followups()
	_director()


func _pay(from: String, to: String, amount: float) -> void:
	var have := float(a(from).gold)
	var paid := minf(have, amount)
	a(from).gold = have - paid
	a(to).gold = float(a(to).gold) + paid


func _update_prices() -> void:
	var p := 4.0
	if pan_stock < 3.0:
		p = 8.0
	elif pan_stock < 7.0:
		p = 6.0
	elif pan_stock < 11.0:
		p = 5.0
	elif pan_stock > 17.0:
		p = 3.0
	if Game.wheat < 10.0:
		p += 1.0
	Game.bread_price = int(p)
	stats.price_min = mini(int(stats.price_min), Game.bread_price)
	stats.price_max = maxi(int(stats.price_max), Game.bread_price)


func _check_ladder(id: String) -> void:
	var act: Dictionary = a(id)
	var lad: Array = Data.LIFE[id].ladder
	# caída: si se queda sin dinero, se arruina (y baja un peldaño)
	if float(act.gold) < 12.0 and not act.ruined:
		act.ruined = true
		if int(act.step) > 0:
			act.step = int(act.step) - 1
		stats.steps_down += 1
		record(id, "arruinado", "", "%s se ha quedado sin dinero" % _name(id), [id])
		return
	if act.ruined and float(act.gold) >= 30.0:
		act.ruined = false
		record(id, "se_recupero", "", "%s ha salido de la ruina" % _name(id), [id])
	var stp := int(act.step)
	if stp >= lad.size() - 1 or act.ruined:
		return
	var up: Dictionary = lad[stp].up
	if up.is_empty():
		return
	if up.has("gold") and float(act.gold) < float(up.gold):
		return
	if up.has("trust") and trust(id) < float(up.trust):
		return
	if up.has("wheat") and Game.wheat < float(up.wheat):
		return
	if up.has("ruins") and not (Game.ruins_seen or Game.flags.get("explored_portal", false)):
		return
	if up.has("op"):
		for other in up.op:
			if float(a(other).op.get(id, 0.0)) < float(up.op[other]):
				return
	act.step = stp + 1
	stats.steps_up += 1
	var st: Dictionary = lad[stp + 1]
	record(id, "nueva_meta", "", "%s ahora quiere %s" % [_name(id), st.goal], [id])
	var n := npc(id)
	if n:
		n.remember("Ahora persigo esto: %s" % st.goal)


func _name(id: String) -> String:
	if id == PLAYER:
		return Game.player_name
	return Game.npcs[id].npc_name if Game.npcs.has(id) else id


# ======================================================================
# Hechos, rumores y reputación
# ======================================================================

## Registra un hecho. Los testigos lo saben con certeza 1.
func record(actor: String, verb: String, target: String, text: String, witnesses: Array) -> Dictionary:
	var f := {"id": next_fact, "t": Game.now_abs(), "actor": actor, "verb": verb, "target": target, "text": text}
	next_fact += 1
	facts.append(f)
	if facts.size() > 300:
		var old: Dictionary = facts.pop_front()
		for id in known:
			known[id].erase(old.id)
	for w in witnesses:
		if known.has(w):
			_learn(w, f, 1.0)
	return f


func knows(id: String, fid: int) -> bool:
	return known.has(id) and known[id].has(fid)


func _fact(fid: int) -> Dictionary:
	for f in facts:
		if int(f.id) == fid:
			return f
	return {}


func _learn(id: String, f: Dictionary, cert: float) -> void:
	if known[id].has(f.id):
		return
	known[id][f.id] = cert
	if f.actor != PLAYER:
		return
	# cómo cambia lo que este NPC piensa del jugador
	var rep: Dictionary = a(id).rep
	var tgt: String = f.target
	var likes_target := tgt != "" and actors.has(tgt) and (tgt == id or float(a(id).op.get(tgt, 0.0)) >= 15.0)
	match f.verb:
		"ayudo":
			rep.carino = minf(100.0, float(rep.carino) + (3.0 if likes_target else 1.0) * cert * (1.0 - maxf(float(rep.carino), 0.0) / 120.0))
			rep.respeto = minf(100.0, float(rep.respeto) + 1.5 * cert * (1.0 - maxf(float(rep.respeto), 0.0) / 120.0))
		"fallo":
			rep.respeto = maxf(-100.0, float(rep.respeto) - 3.0 * cert)
			rep.carino = maxf(-100.0, float(rep.carino) - (3.0 if likes_target else 1.0) * cert)
		"limpio_campo":
			rep.respeto = minf(100.0, float(rep.respeto) + 2.0 * cert)
			if id == "lia":
				rep.carino = minf(100.0, float(rep.carino) + 2.0)
		"forjo":
			rep.respeto = minf(100.0, float(rep.respeto) + 3.0 * cert)
		"murio":
			rep.respeto = maxf(-100.0, float(rep.respeto) - 1.0 * cert)
		"insulto":
			rep.carino = maxf(-100.0, float(rep.carino) - (4.0 if tgt == id else (2.0 if likes_target else 0.5)) * cert)
			rep.respeto = maxf(-100.0, float(rep.respeto) - 1.0 * cert)
		"amenaza":
			rep.miedo = minf(100.0, float(rep.miedo) + (8.0 if tgt == id else 4.0) * cert)
			rep.carino = maxf(-100.0, float(rep.carino) - (6.0 if tgt == id else (3.0 if likes_target else 1.0)) * cert)
	_check_world_titles()


## Dos NPC charlan: cada uno cuenta hasta 2 hechos que el otro no sabe. Se distorsionan un poco.
func gossip(na: Node, nb: Node) -> Array:
	var told := []
	for pair in [[na.id, nb.id], [nb.id, na.id]]:
		var from: String = pair[0]
		var to: String = pair[1]
		var cand := []
		for fid in known[from]:
			if not known[to].has(fid):
				cand.append(fid)
		cand.sort()
		cand.reverse()
		for fid in cand.slice(0, 2):
			var f := _fact(int(fid))
			if f.is_empty() or str(f.text) == "":
				continue
			var cert: float = float(known[from][fid]) * 0.85
			_learn(to, f, cert)
			told.append({"from": from, "to": to, "text": _rumor_text(f, cert)})
	return told


func _rumor_text(f: Dictionary, cert: float) -> String:
	var t := str(f.text)
	if cert < 0.6:
		return "Dicen por ahí que " + t.substr(0, 1).to_lower() + t.substr(1) + "… o eso cuentan."
	if cert < 0.95:
		return "Me contaron que " + t.substr(0, 1).to_lower() + t.substr(1) + "."
	return t + "."


## Cuántos NPC saben al menos `min_n` hechos del jugador con ese verbo.
func renown(verb: String, min_n: int) -> int:
	var c := 0
	for id in known:
		var k := 0
		for fid in known[id]:
			var f := _fact(int(fid))
			if not f.is_empty() and f.actor == PLAYER and f.verb == verb:
				k += 1
		if k >= min_n:
			c += 1
	return c


## Títulos que pone el mundo: los gana el jugador cuando suficientes NPC saben lo que hizo.
func _check_world_titles() -> void:
	var heroes := 0
	var broken := 0
	for id in known:
		var helps := 0
		var fails := 0
		for fid in known[id]:
			var f := _fact(int(fid))
			if f.is_empty() or f.actor != PLAYER:
				continue
			if f.verb == "ayudo":
				helps += 1
			elif f.verb == "fallo":
				fails += 1
		if helps >= 3 and helps >= fails * 2:
			heroes += 1
		if fails >= 3 and fails * 2 >= helps:
			broken += 1
	if heroes >= 3:
		Game.award_title("Héroe de Valdeluz")
	if broken >= 3:
		Game.award_title("Promesa Rota")


func rep_line(id: String) -> String:
	var r: Dictionary = a(id).rep
	return "confianza %d · respeto %d · cariño %d · miedo %d" % [roundi(trust(id)), roundi(float(r.respeto)), roundi(float(r.carino)), roundi(float(r.miedo))]


# ======================================================================
# Director de misiones
# ======================================================================

func qdef(id: String) -> Dictionary:
	if Game.QT.has(id):
		return Game.QT[id]
	return defs.get(id, {})


func _gives_active(id: String) -> bool:
	for q in Game.quests:
		var d: Dictionary = qdef(q.id)
		if d.get("dyn", false) and d.giver == id:
			return true
	return false


func _director() -> void:
	var h := Game.hour_now()
	for id in actors:
		if _gives_active(id):
			continue
		var c := _candidate(id, h)
		if c.is_empty():
			continue
		if offers.has(id):
			var cur: Dictionary = defs.get(offers[id], {})
			if not cur.is_empty() and (float(c.urgency) < float(cur.urgency) + 0.2 or cur.template == c.template):
				continue
			offers.erase(id)
		var d := make_quest(id, c.template, c.params, float(c.urgency), str(c.reason), "")
		if not d.is_empty():
			offers[id] = d.id


## El problema más urgente de este NPC, según el estado del mundo. {} si no tiene ninguno.
func _candidate(id: String, h: int) -> Dictionary:
	var act: Dictionary = a(id)
	var pests: int = main.slimes_near_field()
	var stp := int(act.step)
	var c := []
	match id:
		"bruno":
			if Game.wheat < 22.0:
				c.append({"template": "traer", "params": {"item": "trigo", "need": 4 if Game.wheat > 10.0 else 6}, "urgency": (22.0 - Game.wheat) / 22.0 + 0.3,
					"reason": "No le queda trigo para el horno" + (" y está arruinado" if act.ruined else "")})
			if stp >= 1 and not act.ruined:
				var to := "sira" if float(act.op.get("sira", 0.0)) < float(act.op.get("dorran", 0.0)) else "dorran"
				if stp >= 2:
					to = "lia" if float(a("lia").op.get("bruno", 0.0)) < 30.0 else to
				c.append({"template": "entregar", "params": {"item": "encargo_pan", "to": to}, "urgency": 0.45,
					"reason": "Quiere que %s pruebe su pan para ganar su apoyo" % _name(to) if stp < 2 else "Busca apoyos para fundar el gremio"})
			if stp >= 3:
				c.append({"template": "explorar", "params": {"spot": "portal"}, "urgency": 0.4, "reason": "Quiere saber si el portal sirve de ruta para traer harina sin pasar por la capital"})
		"lia":
			if pests >= 3:
				c.append({"template": "cazar", "params": {"need": clampi(pests, 3, 5)}, "urgency": minf(0.45 + pests * 0.08, 0.8), "reason": "Los limos se están comiendo su trigo"})
			if act.hiding and h >= 7 and h <= 15:
				c.append({"template": "escoltar", "params": {"dest_place": "field", "spot_pos": Vector3(-27.5, 0, 13.5)}, "urgency": 1.0, "reason": "Tiene miedo de ir sola al sembrado"})
			if stp >= 1:
				c.append({"template": "entregar", "params": {"item": "encargo_herramientas", "to": "dorran"}, "urgency": 0.4, "reason": "Necesita herramientas nuevas de Dorran para ampliar el sembrado"})
		"dorran":
			if Game.iron < 3.0:
				c.append({"template": "traer", "params": {"item": "hierro", "need": 3}, "urgency": (3.0 - Game.iron) / 3.0 + 0.3, "reason": "La forja se queda sin hierro"})
			if stp >= 1 and Game.best_grade >= 1:
				c.append({"template": "explorar", "params": {"spot": "rocas_este"}, "urgency": 0.35, "reason": "Busca una veta de hierro puro para su obra maestra"})
		"sira":
			if stp >= 1:
				c.append({"template": "explorar", "params": {"spot": "ruinas"}, "urgency": 0.5, "reason": "Algo despierta en las Ruinas Lunares y quiere saber qué"})
			elif not Game.flags.get("explored_portal", false):
				c.append({"template": "explorar", "params": {"spot": "portal" if trust("sira") >= 5.0 else "manzano"}, "urgency": 0.35, "reason": "Quiere ponerte a prueba antes de confiarte el portal" if trust("sira") < 5.0 else "Quiere que alguien de fuera mire el círculo del portal"})
	if c.is_empty():
		return {}
	c.sort_custom(func(x, y): return float(x.urgency) > float(y.urgency))
	return c[0] if float(c[0].urgency) >= 0.3 else {}


## Crea (y valida) una misión. La recompensa sale de lo que el NPC posee de verdad.
func make_quest(giver: String, template: String, params: Dictionary, urgency: float, reason: String, parent: String) -> Dictionary:
	var T: Dictionary = TEMPLATES[template]
	var id := "dq%d" % next_q
	var d := {"id": id, "dyn": true, "giver": giver, "template": template, "type": T.type, "need": 1,
		"reason": reason, "trust_needed": float(T.trust), "hours": int(T.hours), "parent": parent,
		"created": Game.now_abs(), "expires": Game.now_abs() + OFFER_HOURS * 60.0, "urgency": urgency, "haggled": false}
	var gname := _name(giver)
	var value := 0.0
	match template:
		"traer":
			d.item = params.item
			d.need = int(params.need)
			value = Game.item_base(d.item) * d.need * float(T.base)
			d.title = "%s para %s" % [Game.item_name(d.item), gname]
			d.desc = "Lleva %d × %s a %s." % [d.need, Game.item_name(d.item).to_lower(), gname]
		"cazar":
			d.need = int(params.need)
			value = float(T.base) * d.need
			d.title = "Limos en el sembrado"
			d.desc = "Elimina %d limos y vuelve con %s." % [d.need, gname]
		"escoltar":
			d.dest_place = params.dest_place
			d.dest_pos = params.spot_pos
			value = float(T.base)
			d.title = "Acompañar a %s" % gname
			d.desc = "%s espera en su puerta. Camina a su lado hasta el sembrado (si te alejas, se detiene)." % gname
		"entregar":
			d.item = params.item
			d.deliver_to = params.to
			value = float(T.base)
			d.title = "Un encargo para %s" % _name(params.to)
			d.desc = "%s te da un paquete: llévaselo a %s." % [gname, _name(params.to)]
			d.trust_needed = float(T.trust)
		"explorar":
			d.spot = params.spot
			var sp: Dictionary = Data.SPOTS[params.spot]
			value = float(T.base)
			d.title = "Explorar %s" % sp.name
			d.trust_needed = float(SPOT_TRUST.get(params.spot, 0.0))
			d.desc = "Ve a %s, mira bien y vuelve a contárselo a %s." % [sp.name, gname]
	d.reward = _reward(giver, value * (1.0 + urgency * 0.5), template)
	if not _validate(d):
		stats.invalid += 1
		return {}
	defs[id] = d
	next_q += 1
	stats.generated += 1
	stats.by_template[template] = int(stats.by_template.get(template, 0)) + 1
	if parent != "":
		stats.chained += 1
	return d


## Recompensa: oro hasta lo que el NPC puede permitirse; si no llega, paga con lo que tiene o con un favor.
func _reward(giver: String, value: float, template: String) -> Dictionary:
	var tr := traits(giver)
	var act: Dictionary = a(giver)
	var mood := 1.0 + float(act.rep.respeto) / 200.0
	if trust(giver) < 0.0:
		mood -= 0.25   # pide ayuda aunque desconfíe, pero paga menos
	if "Héroe de Valdeluz" in Game.titles:
		mood += 0.1
	if "Promesa Rota" in Game.titles:
		mood -= 0.2
	var want := value * (0.8 + 0.4 * float(tr.generosidad)) * (1.0 - 0.3 * float(tr.codicia)) * mood
	var budget := float(act.gold) * (0.15 + 0.35 * float(tr.generosidad))
	if float(act.gold) < 25.0:
		budget *= 0.5   # cerca de la ruina, paga sobre todo con lo que tiene
	var gold := int(floor(minf(want, budget)))
	var rw := {"gold": maxi(gold, 0), "xp": int(15 + value), "aff": int(clampf(4.0 + value / 5.0, 4.0, 10.0)), "items": {}, "favor": ""}
	if float(gold) < want * 0.6:
		# no le alcanza el dinero: completa con lo que tiene
		match giver:
			"bruno":
				if pan_stock >= 3.0:
					rw.items = {"pan": 2}
				else:
					rw.favor = "descuento_pan"
			"lia":
				if int(act.items.get("manzana", 0)) >= 2:
					rw.items = {"manzana": mini(3, int(act.items.manzana))}
			"dorran":
				rw.favor = "leccion_forja"
			"sira":
				rw.favor = "bendicion"
	return rw


## El validador: nada se ofrece si el NPC no puede pagarlo o la misión no tiene sentido.
func _validate(d: Dictionary) -> bool:
	var act: Dictionary = a(d.giver)
	if int(d.reward.gold) > int(floor(float(act.gold))) or int(d.reward.gold) < 0:
		return false
	for k in d.reward.items:
		if k == "pan":
			if pan_stock < float(d.reward.items[k]):
				return false
		elif int(act.items.get(k, 0)) < int(d.reward.items[k]):
			return false
	if d.type == "item" and d.template == "traer" and not Game.ITEMS.has(d.item):
		return false
	if d.template == "entregar" and (d.deliver_to == d.giver or not actors.has(d.deliver_to)):
		return false
	if d.template == "explorar" and not Data.SPOTS.has(d.spot):
		return false
	return true


## La oferta que este NPC le haría al jugador ahora (respeta la confianza mínima). "" si no hay.
func offer_for(id: String) -> String:
	if not offers.has(id):
		return ""
	var qid: String = offers[id]
	var d: Dictionary = defs.get(qid, {})
	if d.is_empty():
		offers.erase(id)
		return ""
	_reprice(d)
	# el orgulloso tarda más en pedir ayuda a un desconocido
	var need := float(d.trust_needed) + (5.0 if float(traits(id).orgullo) > 0.7 and d.urgency < 0.6 else 0.0)
	if trust(id) < need:
		return ""
	return qid


## Si el NPC gastó dinero desde que pensó la oferta, la ajusta a lo que tiene ahora.
func _reprice(d: Dictionary) -> void:
	var have := int(floor(float(a(d.giver).gold)))
	if int(d.reward.gold) <= have:
		return
	d.reward.gold = maxi(have, 0)
	if (d.reward.items as Dictionary).is_empty() and str(d.reward.favor) == "":
		var alt := _reward(d.giver, 0.0, d.template)
		d.reward.favor = {"bruno": "descuento_pan", "lia": "", "dorran": "leccion_forja", "sira": "bendicion"}[d.giver]
		if d.giver == "lia" and int(a("lia").items.get("manzana", 0)) >= 2:
			d.reward.items = {"manzana": 2}


## Frase con la que el NPC pide la misión (su guion; en la fase 2 la IA la reescribe).
func ask_line(qid: String) -> String:
	var d: Dictionary = defs[qid]
	var rw: Dictionary = d.reward
	var pay := reward_text(rw)
	match d.template:
		"traer":
			return "%s. ¿Me traes %d × %s? Te daré %s." % [d.reason, d.need, Game.item_name(d.item).to_lower(), pay]
		"cazar":
			return "%s. Si eliminas %d, te doy %s." % [d.reason, d.need, pay]
		"escoltar":
			return "%s… ¿Me acompañas? Te pagaré %s." % [d.reason, pay]
		"entregar":
			return "%s. Llévale esto a %s y te daré %s." % [d.reason, _name(d.deliver_to), pay]
		"explorar":
			return "%s. Ve a %s y cuéntame qué ves. Te daré %s." % [d.reason, Data.SPOTS[d.spot].name, pay]
	return d.reason


static func reward_text(rw: Dictionary) -> String:
	var parts := []
	if int(rw.gold) > 0:
		parts.append("%d monedas" % int(rw.gold))
	for k in rw.get("items", {}):
		parts.append("%d × %s" % [int(rw.items[k]), Game.item_name(k).to_lower()])
	match str(rw.get("favor", "")):
		"descuento_pan":
			parts.append("pan más barato 2 días")
		"leccion_forja":
			parts.append("una lección de forja")
		"bendicion":
			parts.append("la bendición de la luna")
	if parts.is_empty():
		parts.append("su gratitud")
	return ", ".join(parts)


## Regatear: lo decide el carácter del NPC y la confianza, nunca la IA. Una vez por oferta.
func negotiate(qid: String) -> Dictionary:
	var d: Dictionary = defs[qid]
	if d.haggled:
		return {"ok": false, "line": "Ya te dije mi precio."}
	d.haggled = true
	stats.negotiations += 1
	var tr := traits(d.giver)
	var chance := clampf(0.25 + trust(d.giver) / 100.0 * 0.5 - float(tr.codicia) * 0.3 + float(a(d.giver).rep.respeto) / 200.0, 0.05, 0.85)
	var n := npc(d.giver)
	if randf() < chance:
		var extra := int(ceil(float(d.reward.gold) * 0.15)) + 1
		var can := int(floor(float(a(d.giver).gold))) - int(d.reward.gold)
		extra = mini(extra, maxi(can, 0))
		if extra <= 0:
			return {"ok": false, "line": "No tengo más, de verdad. Es todo lo que hay."}
		d.reward.gold = int(d.reward.gold) + extra
		return {"ok": true, "line": "Está bien… %d monedas más. Pero no me falles." % extra}
	if n:
		n.aff = clampf(n.aff - 2.0, -100.0, 100.0)
	return {"ok": false, "line": "¿Más? " + ("Bah, no abuses." if float(tr.orgullo) > 0.6 else "Lo siento, no puedo.")}


## Al aceptar: el NPC aparta el oro (no puede gastarlo en otra cosa) y entrega lo necesario.
func on_accept(qid: String) -> void:
	var d: Dictionary = defs[qid]
	offers.erase(d.giver)
	_reprice(d)
	var gold := mini(int(d.reward.gold), int(floor(float(a(d.giver).gold))))
	d.reward.gold = gold
	a(d.giver).gold = float(a(d.giver).gold) - gold
	escrow[qid] = gold
	if d.template == "entregar":
		Game.add_item(d.item, 1)
	if d.template == "escoltar":
		var n := npc(d.giver)
		if n:
			n.away = false


## Recompensa al terminar. Devuelve el texto de lo recibido.
func pay(qid: String) -> String:
	var d: Dictionary = defs[qid]
	var rw: Dictionary = d.reward
	Game.gold += int(escrow.get(qid, 0))
	escrow.erase(qid)
	for k in rw.items:
		var c := int(rw.items[k])
		if k == "pan":
			pan_stock = maxf(0.0, pan_stock - c)
		else:
			a(d.giver).items[k] = maxi(0, int(a(d.giver).items.get(k, 0)) - c)
		Game.add_item(k, c)
	match str(rw.favor):
		"descuento_pan":
			Game.flags["bread_discount_until"] = Game.now_abs() + 48.0 * 60.0
		"leccion_forja":
			Game.flags["forge_lesson_until"] = Game.now_abs() + 24.0 * 60.0
		"bendicion":
			Game.buff_t = maxf(Game.buff_t, 300.0)
	return reward_text(rw)


## Final con éxito: cambia el mundo y puede abrir otra misión (cadena).
func on_success(qid: String, n: Node) -> String:
	var d: Dictionary = defs[qid]
	var g: String = d.giver
	var wit := _witnesses(g)
	stats.success += 1
	record(PLAYER, "ayudo", g, "%s ayudó a %s: %s" % [Game.player_name, _name(g), d.title.to_lower()], wit)
	var extra := ""
	match d.template:
		"traer":
			if d.item == "trigo":
				Game.wheat += float(d.need) * 3.0
				extra = " El horno vuelve a rugir."
				if randf() < 0.3:
					var to := "sira" if randf() < 0.5 else "dorran"
					_follow("bruno", "entregar", {"item": "encargo_pan", "to": to}, qid, 6, "Con el horno lleno, quiere regalarle pan a %s" % _name(to))
			elif d.item == "hierro":
				Game.iron += float(d.need)
				extra = " La forja vuelve a sonar."
				if randf() < 0.3:
					_follow("dorran", "explorar", {"spot": "rocas_este"}, qid, 10, "El mineral que trajiste es bueno; quiere saber si hay una veta más grande")
			a(g).fear = maxf(0.0, float(a(g).fear) - 0.1)
		"cazar":
			a(g).fear = maxf(0.0, float(a(g).fear) - 0.4)
			record(PLAYER, "limpio_campo", g, "%s limpió el sembrado de limos" % Game.player_name, wit)
			if randf() < 0.45:
				_follow("sira", "explorar", {"spot": "ruinas" if Game.ruins_seen else "portal"}, qid, 6, "Los limos que huyeron vienen de algún sitio. Quiere saber de dónde")
		"escoltar":
			a(g).fear = maxf(0.0, float(a(g).fear) - 0.5)
			a(g).hiding = false
			if randf() < 0.5:
				_follow("bruno", "traer", {"item": "trigo", "need": 4}, qid, 4, "Con Lía de vuelta en el campo, quiere hacer una hornada grande")
		"entregar":
			var to: String = d.deliver_to
			a(to).op[g] = minf(100.0, float(a(to).op.get(g, 0.0)) + 12.0)
			a(g).op[to] = minf(100.0, float(a(g).op.get(to, 0.0)) + 6.0)
			extra = " %s ahora ve con mejores ojos a %s." % [_name(to), _name(g)]
			if randf() < 0.4:
				_follow(to, "traer", {"item": "trigo" if to == "bruno" else "hierro", "need": 3}, qid, 8, "Agradecido por el encargo, se anima a pedirte ayuda")
		"explorar":
			Game.flags["explored_" + str(d.spot)] = true
			record(PLAYER, "descubrio", d.spot, "%s exploró %s" % [Game.player_name, Data.SPOTS[d.spot].name], wit)
			if g == "sira" and d.spot == "ruinas":
				Game.flags["ruins_explored"] = true
				extra = " Sira anota lo que viste en las Ruinas."
				if randf() < 0.5:
					_follow("dorran", "traer", {"item": "cristal", "need": 1}, qid, 12, "Sira le contó lo de los cristales lunares de las Ruinas")
	var got := pay(qid)
	return "Recibes: %s.%s" % [got, extra]


## Final con fracaso (plazo vencido): baja la confianza y el mundo empeora.
func on_fail(q: Dictionary) -> void:
	var d: Dictionary = defs[q.id]
	var g: String = d.giver
	stats.failed += 1
	a(g).gold = float(a(g).gold) + float(escrow.get(q.id, 0))
	escrow.erase(q.id)
	var n := npc(g)
	if n:
		n.aff = clampf(n.aff - 8.0, -100.0, 100.0)
		n.remember("%s no cumplió lo que me prometió: %s" % [Game.player_name, d.title.to_lower()])
	record(PLAYER, "fallo", g, "%s le falló a %s" % [Game.player_name, _name(g)], _witnesses(g))
	match d.template:
		"cazar":
			a(g).fear = minf(1.0, float(a(g).fear) + 0.3)
			Game.wheat = maxf(0.0, Game.wheat - 8.0)
		"traer":
			if d.item == "trigo":
				a(g).gold = maxf(0.0, float(a(g).gold) - 10.0)   # pierde ventas
		"escoltar":
			a(g).fear = minf(1.0, float(a(g).fear) + 0.15)
	if d.template == "entregar":
		Game.remove_item(d.item, 1)
	Game.quests.erase(q)
	Game.say("Misión fallida: %s. %s se lo contará a otros." % [d.title, _name(g)], "bad")


func _witnesses(g: String) -> Array:
	var w := [g]
	var gn := npc(g)
	for n in main.npcs:
		if n.id != g and not n.away and gn and n.pos.distance_to(gn.pos) < 15.0:
			w.append(n.id)
	return w


func _follow(giver: String, template: String, params: Dictionary, parent: String, delay_h: int, reason: String) -> void:
	followups.append({"giver": giver, "template": template, "params": params, "parent": parent, "at": Game.now_abs() + delay_h * 60.0, "reason": reason})


func _run_followups() -> void:
	for i in range(followups.size() - 1, -1, -1):
		var f: Dictionary = followups[i]
		if Game.now_abs() < float(f.at) or _gives_active(f.giver):
			continue
		if Game.now_abs() > float(f.at) + 72.0 * 60.0:
			followups.remove_at(i)   # la oportunidad pasó
			continue
		followups.remove_at(i)
		offers.erase(f.giver)   # lo que nace de tus actos va primero
		var d := make_quest(f.giver, f.template, f.params, 0.6, f.reason, f.parent)
		if not d.is_empty():
			offers[f.giver] = d.id


func _expire() -> void:
	var now := Game.now_abs()
	for id in offers.keys():
		var d: Dictionary = defs.get(offers[id], {})
		if d.is_empty() or now > float(d.expires):
			offers.erase(id)
			stats.expired_offers += 1
	for q in Game.quests.duplicate():
		var d2: Dictionary = qdef(q.id)
		if d2.get("dyn", false) and now > float(q.get("deadline", INF)):
			on_fail(q)


# ======================================================================
# Cada segundo: progreso de explorar/acompañar y NPC que llaman al jugador
# ======================================================================

func frame_tick() -> void:
	var pp: Vector3 = main.player_pos()
	for q in Game.quests:
		var d: Dictionary = qdef(q.id)
		if not d.get("dyn", false) or int(q.progress) >= 1:
			continue
		if d.template == "explorar":
			var sp: Dictionary = Data.SPOTS[d.spot]
			if Vector2(pp.x - sp.pos.x, pp.z - sp.pos.z).length() < float(sp.r):
				q.progress = 1
				Game.say("Exploraste %s. Vuelve con %s para contárselo." % [sp.name, _name(d.giver)], "gold")
		elif d.template == "escoltar":
			var n := npc(d.giver)
			if n and n.place == d.dest_place and n.path.is_empty() and n.pos.distance_to(pp) < 10.0:
				q.progress = 1
				n.say("¡Llegamos! Gracias por no dejarme sola.", "reir")
				Game.say("%s llegó a salvo. Habla con ella para cobrar." % n.npc_name, "gold")
	# el NPC con un problema urgente llama al jugador si pasa cerca
	for id in offers:
		var qid := offer_for(id)
		if qid == "":
			continue
		var n2 := npc(id)
		if n2 == null or n2.away or n2.busy != "" or main.dialogue.npc != null:
			continue
		if float(defs[qid].urgency) < 0.7 or n2.pos.distance_to(pp) > 7.0:
			continue
		if main.t_total - float(called_at.get(id, -999.0)) < 120.0:
			continue
		called_at[id] = main.t_total
		n2.say("¡Viajero! ¿Tienes un momento? Necesito ayuda.", "saludar")


# ======================================================================
# Guardado
# ======================================================================

func serialize() -> Dictionary:
	var acts := {}
	for id in actors:
		acts[id] = actors[id].duplicate(true)
	var kn := {}
	for id in known:
		var m := {}
		for fid in known[id]:
			m[str(fid)] = known[id][fid]
		kn[id] = m
	var defs_out := {}
	for id in defs:
		var d: Dictionary = defs[id].duplicate(true)
		if d.has("dest_pos"):
			d.dest_pos = [d.dest_pos.x, d.dest_pos.y, d.dest_pos.z]
		defs_out[id] = d
	return {"actors": acts, "facts": facts.slice(-150), "known": kn, "next_fact": next_fact, "defs": defs_out,
		"offers": offers, "escrow": escrow, "next_q": next_q, "pan": pan_stock, "followups": followups}


func restore(s: Dictionary) -> void:
	if s.is_empty():
		return
	for id in s.get("actors", {}):
		if actors.has(id):
			for k in s.actors[id]:
				actors[id][k] = s.actors[id][k]
	facts = s.get("facts", [])
	for f in facts:
		f.id = int(f.id)
	for id in s.get("known", {}):
		if known.has(id):
			known[id] = {}
			for fid in s.known[id]:
				known[id][int(fid)] = float(s.known[id][fid])
	next_fact = int(s.get("next_fact", next_fact))
	defs = {}
	for id in s.get("defs", {}):
		var d: Dictionary = s.defs[id]
		if d.get("dest_pos") is Array:
			d.dest_pos = Vector3(float(d.dest_pos[0]), float(d.dest_pos[1]), float(d.dest_pos[2]))
		defs[id] = d
	offers = s.get("offers", {})
	escrow = s.get("escrow", {})
	next_q = int(s.get("next_q", next_q))
	pan_stock = float(s.get("pan", pan_stock))
	followups = s.get("followups", [])
	_update_prices()
