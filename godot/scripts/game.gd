extends Node
## Estado global de Tierras Vivas (autoload «Game»): datos del juego, jugador, mundo,
## misiones, títulos, ajustes y guardado. No crea nodos 3D: eso lo hace main.gd.

signal toast(msg: String, kind: String)
signal changed

const SAVE_PATH := "user://tierras_vivas_save.json"
const SETTINGS_PATH := "user://tierras_vivas_settings.cfg"

# ---------- trabajos (una sola lista: cualquier trabajo puede ser principal o secundario) ----------
const JOBS := {
	"elementalista": {"name": "Elementalista", "kind": "Combate · Magia", "hp": 90, "mp": 130, "p": "Bola de fuego +40 % de daño.", "s": "Bola de fuego +20 % de daño."},
	"guardian": {"name": "Guardián", "kind": "Combate · Defensa", "hp": 150, "mp": 80, "p": "Mucha vida; el escudo dura el doble.", "s": "+20 de vida; el escudo dura +50 %."},
	"sanador": {"name": "Sanador", "kind": "Combate · Soporte", "hp": 105, "mp": 115, "p": "Curar restaura el doble.", "s": "Curar restaura +50 %."},
	"herrero": {"name": "Herrero", "kind": "Oficio · Forja", "hp": 120, "mp": 85, "p": "Zona de golpe +80 %; con más de 70 % de precisión la espada sube un grado.", "s": "Zona de golpe +40 % en la forja."},
	"cocinero": {"name": "Cocinero", "kind": "Oficio · Cocina", "hp": 110, "mp": 95, "p": "La comida restaura ×2,5 y su efecto dura el doble.", "s": "La comida restaura ×1,75."},
	"comerciante": {"name": "Comerciante", "kind": "Oficio · Comercio", "hp": 105, "mp": 95, "p": "Compras 25 % más barato; te pagan hasta +35 %.", "s": "Compras 12 % más barato; te pagan hasta +17 %."},
	"rastreador": {"name": "Rastreador", "kind": "Oficio · Caza", "hp": 115, "mp": 90, "p": "Ves a los limos a 45 m a través de todo y les haces +15 % de daño.", "s": "Ves a los limos a 25 m a través de todo."},
}
const JOB_ORDER := ["elementalista", "guardian", "sanador", "herrero", "cocinero", "comerciante", "rastreador"]

# Claves en orden alfabético: «a+b» con a < b.
const SYNERGY := {
	"guardian+herrero": "Escudo templado: con una espada forjada por ti, el escudo absorbe 80 % en lugar de 70 %.",
	"cocinero+elementalista": "Cocina elemental: comer te da +25 % de daño de fuego durante 60 s.",
	"elementalista+rastreador": "Fuego guiado: la bola de fuego se curva hacia limos cercanos.",
	"cocinero+sanador": "Caldo curativo: Curar también restaura 40 de energía.",
	"comerciante+sanador": "Boticario: cada venta en tu puesto te devuelve 10 de maná.",
	"guardian+rastreador": "Centinela: los limos te hacen 20 % menos daño.",
	"elementalista+herrero": "Fragua viva: forjar con el efecto de fuego activo sube la calidad un grado.",
	"cocinero+herrero": "Fogón de forja: bien alimentado, tu zona de golpe es 15 % más ancha.",
	"comerciante+herrero": "Marca de taller: los habitantes pagan hasta 30 % más por tus espadas.",
	"cocinero+comerciante": "Pan de la casa: el pan de Bruno te cuesta la mitad.",
	"guardian+sanador": "Muralla viva: Curar también te da 3 s de escudo.",
	"herrero+rastreador": "Ojo de minero: cada roca te da 2 trozos de mineral.",
}

const SPELLS := [
	{"id": "fuego", "name": "Bola de fuego", "mp": 12, "color": Color(1.0, 0.48, 0.16)},
	{"id": "escudo", "name": "Escudo", "mp": 18, "color": Color(0.44, 0.83, 1.0)},
	{"id": "curar", "name": "Curar", "mp": 22, "color": Color(0.62, 1.0, 0.54)},
]

const ITEMS := {
	"pan": {"name": "Pan de Bruno", "food": {"hp": 15, "st": 35, "buff": 60}, "base": 5},
	"manzana": {"name": "Manzana", "food": {"hp": 10, "st": 15, "buff": 0}, "base": 2},
	"trigo": {"name": "Gavilla de trigo", "base": 3},
	"hierro": {"name": "Mineral de hierro", "base": 6},
	"gel": {"name": "Gel de limo", "base": 4},
	"cristal": {"name": "Cristal lunar", "base": 30},
	"encargo_pan": {"name": "Encargo de pan de Bruno", "base": 0},
	"encargo_herramientas": {"name": "Encargo de Lía para Dorran", "base": 0},
}
const GRADES := ["Común", "Rara", "Épica", "Única", "Legendaria"]
const GRADE_COL := [Color(0.79, 0.82, 0.84), Color(0.42, 0.79, 0.9), Color(0.69, 0.49, 1.0), Color(0.91, 0.71, 0.3), Color(1.0, 0.54, 0.24)]
const SWORD_BASE := [12, 25, 45, 80, 140]
const MOONS := ["nueva", "creciente", "cuarto creciente", "gibosa creciente", "llena", "gibosa menguante", "cuarto menguante", "menguante"]

const TITLES := {
	"Amigo de los Panaderos": "El pan te cuesta 1 moneda menos.",
	"Azote de Limos": "+10 % de daño de fuego.",
	"Martillo Firme": "Zona de golpe más ancha en la forja.",
	"Viajero Lunar": "+50 % de regeneración de maná.",
	"Heredero del Yunque": "Toda espada que forjes sube un grado.",
	"Héroe de Valdeluz": "Lo gana el pueblo, no tú: los habitantes te pagan un 10 % más.",
	"Promesa Rota": "El pueblo sabe que fallas: te ofrecen un 20 % menos.",
}

# Misiones escritas a mano (ganchos fijos). Las demás las crea el director de sim.gd.
# Las recompensas las decide el juego, nunca la IA.
const QT := {
	"investigar": {"giver": "sira", "title": "¿Acapara Bruno?", "desc": "Revisa el almacén detrás de la panadería y vuelve con Sira.", "type": "flag", "need": 1, "reward": {"gold": 12, "aff": 8, "xp": 40}},
	"maestro": {"giver": "dorran", "hidden": true, "once": true, "title": "La forja del maestro", "desc": "Dorran te confió su secreto: trae un Cristal lunar de las Ruinas.", "type": "item", "item": "cristal", "need": 1, "reward": {"gold": 40, "aff": 15, "xp": 80, "title": "Heredero del Yunque"}},
}

# ---------- jugador ----------
var player_name := "Viajero"
var look := {"skin": "#d9a07a", "hair": "#3a2618", "hair_style": "corto", "outfit": "#3f6e8c", "cape": true, "height": 1.75, "build": 1.0, "model": "caballero"}
var cls := "elementalista"
var sub := "herrero"
var hp := 90.0
var max_hp := 90.0
var mp := 130.0
var max_mp := 130.0
var st := 100.0
var max_st := 100.0
var xp := 0
var lvl := 1
var gold := 25
var inv := {"hierro": 2, "manzana": 1}
var titles: Array = []
var title := ""
var kills := 0
var best_grade := -1
var spell := 0
var shield_t := 0.0
var buff_t := 0.0
var fire_buff_t := 0.0
var alive := true
var seated := false
var ruins_seen := false
var forged_own := false

# ---------- mundo ----------
var minute := 17.0 * 60.0 + 30.0
var day := 1
var wheat := 32.0
var iron := 3.0
var bread_price := 4
var hoarding = null  # null hasta que se crea el rumor; luego true/false
var flags := {}
var rumor_log: Array = []
var crystal_day := 0
var quests: Array = []   # [{"id": String, "progress": int}]
var done_at := {}
var stall: Array = []    # [{"key": String, "price": int, "node": Node3D}]

var npcs := {}           # id -> nodo NPC (lo rellena main.gd)
var world: Node = null   # main.gd
var started := false
var settings := {"tts": true, "snap": 30, "vignette": true, "volume": 0.8, "quality": 2}   # quality: 0 baja … 3 ultra


# ---------- trabajos ----------

func jw(id: String) -> float:
	if cls == id:
		return 1.0
	if sub == id:
		return 0.5
	return 0.0


func has_job(id: String) -> bool:
	return jw(id) > 0.0


func syn_key() -> String:
	var a := [cls, sub]
	a.sort()
	return "%s+%s" % [a[0], a[1]]


func has_syn(k: String) -> bool:
	var parts := k.split("+")
	parts.sort()
	return syn_key() == "+".join(parts)


func base_hp() -> float:
	return float(JOBS[cls].hp) + (20.0 if sub == "guardian" else 0.0)


# ---------- objetos ----------

func item_name(k: String) -> String:
	if k.begins_with("espada:"):
		var g := int(k.split(":")[1])
		return ("Espada de " + player_name if g >= 3 else "Espada") + " (" + GRADES[g] + ")"
	return ITEMS[k].name if ITEMS.has(k) else k


func item_base(k: String) -> int:
	if k.begins_with("espada:"):
		return SWORD_BASE[int(k.split(":")[1])]
	return int(ITEMS[k].base) if ITEMS.has(k) else 1


func add_item(k: String, n: int = 1) -> void:
	inv[k] = int(inv.get(k, 0)) + n
	changed.emit()


func remove_item(k: String, n: int = 1) -> void:
	inv[k] = int(inv.get(k, 0)) - n
	if inv[k] <= 0:
		inv.erase(k)
	changed.emit()


func count(k: String) -> int:
	return int(inv.get(k, 0))


func food_key() -> String:
	for k in ["pan", "manzana"]:
		if count(k) > 0:
			return k
	return ""


# ---------- progreso ----------

func say(msg: String, kind: String = "") -> void:
	toast.emit(msg, kind)


func add_xp(x: int) -> void:
	xp += x
	while xp >= lvl * 100:
		xp -= lvl * 100
		lvl += 1
		max_hp += 10
		max_mp += 5
		hp = max_hp
		mp = max_mp
		Sfx.play("level")
		say("Subiste a nivel %d." % lvl, "gold")
	changed.emit()


func award_title(t: String) -> void:
	if t in titles:
		return
	titles.append(t)
	if title == "":
		title = t
	say("Título obtenido: «%s». %s" % [t, TITLES[t]], "gold")
	Sfx.play("level")
	for id in npcs:
		npcs[id].remember("%s ganó el título «%s»" % [player_name, t])
	changed.emit()


func check_titles() -> void:
	if npcs.has("bruno") and npcs["bruno"].aff >= 30:
		award_title("Amigo de los Panaderos")
	if kills >= 10:
		award_title("Azote de Limos")


func title_active(t: String) -> bool:
	return title == t


# ---------- tiempo y luna ----------

func hour_now() -> int:
	return int(minute / 60.0) % 24


func moon_phase() -> int:
	return (day + 3) % 8


func moon_name() -> String:
	return MOONS[moon_phase()]


func portal_open() -> bool:
	var h := hour_now()
	if moon_phase() == 4:
		return h >= 19 or h < 5
	return h >= 19


func portal_text() -> String:
	return "El portal está abierto." if portal_open() else "El portal abre a las 19:00."


func is_night() -> bool:
	var h := fmod(minute / 60.0, 24.0)
	return h < 6.0 or h >= 19.0


func time_str() -> String:
	var m := int(minute) % 1440
	return "%02d:%02d" % [m / 60, m % 60]


func now_abs() -> float:
	return day * 1440.0 + minute


func upd_prices() -> void:
	bread_price = 7 if wheat < 15 else (5 if wheat < 30 else 4)


func advance(mins: float) -> void:
	var before := int(minute / 60.0)
	minute += mins
	while minute >= 1440.0:
		minute -= 1440.0
		day += 1
	var after := int(minute / 60.0)
	var steps := (after - before + 24) % 24
	if steps == 0 and mins >= 60.0:
		steps = 1
	for i in steps:
		_hour_tick()


func _hour_tick() -> void:
	var h := hour_now()
	if world == null or world.sim == null:
		# sin simulación (pruebas sueltas): economía mínima
		var pests: int = world.slimes_near_field() if world else 0
		wheat += -1.0 if pests >= 3 else 2.5
		if h >= 6 and h < 19:
			wheat -= 2.2
		wheat = clampf(wheat, 0.0, 60.0)
		if h >= 7 and h < 18:
			iron = maxf(0.0, iron - 0.35)
		upd_prices()
	if world:
		world.on_hour_tick()
	if h == 6:
		for id in npcs:
			var n = npcs[id]
			n.memory = n.memory.slice(-8)


func bread_cost() -> int:
	var c := float(bread_price)
	c = roundf(c * (1.0 - 0.25 * jw("comerciante")))
	if has_syn("cocinero+comerciante"):
		c = ceilf(c / 2.0)
	if title_active("Amigo de los Panaderos"):
		c -= 1.0
	if now_abs() < float(flags.get("bread_discount_until", 0.0)):
		c -= 1.0
	return maxi(1, int(c))


# ---------- misiones (fijas de QT + dinámicas del director) ----------

func qdef(id: String) -> Dictionary:
	if QT.has(id):
		return QT[id]
	if world and world.sim:
		return world.sim.defs.get(id, {})
	return {}


func active_q(id: String) -> Dictionary:
	for q in quests:
		if q.id == id:
			return q
	return {}


func q_progress(q: Dictionary) -> int:
	var d := qdef(q.id)
	if d.is_empty():
		return 0
	if d.type == "item":
		return mini(int(d.need), count(d.item))
	return mini(int(d.need), int(q.progress))


func q_done(q: Dictionary) -> bool:
	var d := qdef(q.id)
	return not d.is_empty() and q_progress(q) >= int(d.need)


## Horas que quedan para el plazo (solo misiones dinámicas). -1 si no tiene plazo.
func q_hours_left(q: Dictionary) -> int:
	if not q.has("deadline"):
		return -1
	return maxi(0, int((float(q.deadline) - now_abs()) / 60.0))


func quest_available(id: String) -> bool:
	match id:
		"investigar":
			return flags.get("rumor_hoard", false) and not flags.get("investigated", false)
		"maestro":
			return npcs.has("dorran") and npcs["dorran"].aff >= 25 and best_grade >= 2
	return false


func offerable(npc_id: String) -> Array:
	var out := []
	for id in QT:
		var d: Dictionary = QT[id]
		if d.giver != npc_id or not active_q(id).is_empty():
			continue
		if d.get("once", false) and done_at.has(id):
			continue
		if done_at.has(id) and now_abs() - float(done_at[id]) < 360.0:
			continue
		if quest_available(id):
			out.append(id)
	if world and world.sim:
		var dyn: String = world.sim.offer_for(npc_id)
		if dyn != "":
			out.append(dyn)
	return out


func deliverable(npc_id: String) -> Array:
	var out := []
	for q in quests:
		var d := qdef(q.id)
		if not d.is_empty() and str(d.get("deliver_to", d.giver)) == npc_id and q_done(q):
			out.append(q)
	return out


func accept_quest(id: String) -> void:
	if not active_q(id).is_empty():
		return
	var d := qdef(id)
	if d.is_empty():
		return
	var q := {"id": id, "progress": 0}
	if d.get("dyn", false):
		q["deadline"] = now_abs() + float(d.hours) * 60.0
		world.sim.on_accept(id)
	quests.append(q)
	say("Misión aceptada: " + str(d.title), "gold")
	Sfx.play("pick")
	changed.emit()


func deliver_quest(q: Dictionary, n) -> void:
	var d := qdef(q.id)
	if d.type == "item":
		remove_item(d.item, int(d.need))
	quests.erase(q)
	done_at[q.id] = now_abs()
	if d.get("dyn", false):
		var giver = npcs[d.giver]
		# la confianza crece cada vez más despacio (cuesta llegar a lo más alto)
		giver.aff = clampf(giver.aff + float(d.reward.aff) * (1.0 - maxf(giver.aff, 0.0) / 120.0), -100.0, 100.0)
		if n != giver:
			n.aff = clampf(n.aff + 3.0, -100.0, 100.0)
		add_xp(int(d.reward.xp))
		Sfx.play("coin")
		giver.remember("%s cumplió: %s" % [player_name, str(d.title).to_lower()])
		var got: String = world.sim.on_success(q.id, n)
		say("Misión completada: %s. %s" % [d.title, got], "gold")
		check_titles()
		changed.emit()
		return
	gold += int(d.reward.gold)
	n.aff = clampf(n.aff + float(d.reward.aff), -100.0, 100.0)
	add_xp(int(d.reward.xp))
	Sfx.play("coin")
	var extra := ""
	match q.id:
		"maestro":
			n.remember("%s trajo un cristal lunar para honrar a mi maestro" % player_name)
		"investigar":
			flags["investigated"] = true
			var b = npcs["bruno"]
			if hoarding == true:
				b.aff = clampf(b.aff - 10.0, -100.0, 100.0)
				wheat += 18.0
				upd_prices()
				b.remember("%s descubrió la harina que escondía" % player_name)
				n.remember("%s confirmó que Bruno acaparaba harina" % player_name)
				extra = " Bruno tuvo que liberar la harina. El pan bajó, pero Bruno te mira mal."
			else:
				b.aff = clampf(b.aff + 6.0, -100.0, 100.0)
				b.remember("%s demostró que yo no escondía harina" % player_name)
				n.remember("%s desmintió el rumor sobre Bruno" % player_name)
				extra = " El rumor era falso. Bruno te lo agradece."
	if world and world.sim:
		world.sim.record(world.sim.PLAYER, "ayudo", d.giver, "%s ayudó a %s: %s" % [player_name, n.npc_name, str(d.title).to_lower()], world.sim._witnesses(d.giver))
	if d.reward.has("title"):
		award_title(d.reward.title)
	say("Misión completada: %s (+%d monedas, +%d XP).%s" % [d.title, int(d.reward.gold), int(d.reward.xp), extra], "gold")
	check_titles()
	changed.emit()


# ---------- ajustes ----------

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("settings", k, settings[k])
	Sfx.set_volume(float(settings.volume))


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


# ---------- guardado ----------

func serialize() -> Dictionary:
	var npc_data := []
	for id in npcs:
		var n = npcs[id]
		npc_data.append({"id": id, "aff": n.aff, "memory": n.memory, "rumors": n.rumors})
	var pos: Vector3 = world.player_pos() if world else Vector3(0, 0, 7)
	var stall_out := []
	for s in stall:
		stall_out.append({"key": s.key, "price": s.price})
	return {
		"v": 2,
		"p": {"name": player_name, "look": look, "cls": cls, "sub": sub, "pos": [pos.x, pos.y, pos.z],
			"hp": hp, "max_hp": max_hp, "mp": mp, "max_mp": max_mp, "st": st, "xp": xp, "lvl": lvl, "gold": gold,
			"inv": inv, "titles": titles, "title": title, "kills": kills, "best_grade": best_grade, "spell": spell,
			"ruins_seen": ruins_seen, "forged_own": forged_own, "seated": seated},
		"w": {"minute": minute, "day": day, "wheat": wheat, "iron": iron, "hoarding": hoarding, "flags": flags,
			"rumor_log": rumor_log, "crystal_day": crystal_day},
		"quests": quests, "done_at": done_at, "stall": stall_out, "npcs": npc_data,
		"sim": world.sim.serialize() if world and world.sim else {},
	}


func save_game() -> void:
	if not started:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(serialize()))


func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Aplica una partida guardada. Devuelve la posición del jugador.
func restore(s: Dictionary) -> Vector3:
	var p: Dictionary = s.get("p", {})
	player_name = str(p.get("name", player_name))
	if p.get("look") is Dictionary:
		for k in p.look:
			look[k] = p.look[k]
	cls = str(p.get("cls", cls))
	sub = str(p.get("sub", sub))
	if not JOBS.has(cls):
		cls = "elementalista"
	if not JOBS.has(sub) or sub == cls:
		sub = "cocinero" if cls == "herrero" else "herrero"
	hp = float(p.get("hp", hp))
	max_hp = float(p.get("max_hp", max_hp))
	mp = float(p.get("mp", mp))
	max_mp = float(p.get("max_mp", max_mp))
	st = float(p.get("st", st))
	xp = int(p.get("xp", xp))
	lvl = int(p.get("lvl", lvl))
	gold = int(p.get("gold", gold))
	inv = {}
	for k in p.get("inv", {}):
		inv[k] = int(p.inv[k])
	titles = p.get("titles", []).duplicate()
	title = str(p.get("title", ""))
	kills = int(p.get("kills", 0))
	best_grade = int(p.get("best_grade", -1))
	spell = int(p.get("spell", 0))
	ruins_seen = bool(p.get("ruins_seen", false))
	forged_own = bool(p.get("forged_own", false))
	seated = bool(p.get("seated", false))
	var w: Dictionary = s.get("w", {})
	minute = float(w.get("minute", minute))
	day = int(w.get("day", day))
	wheat = float(w.get("wheat", wheat))
	iron = float(w.get("iron", iron))
	hoarding = w.get("hoarding", null)
	flags = w.get("flags", {})
	rumor_log = w.get("rumor_log", [])
	crystal_day = int(w.get("crystal_day", 0))
	upd_prices()
	if world and world.sim:
		world.sim.restore(s.get("sim", {}))
	quests = []
	for q in s.get("quests", []):
		if not qdef(str(q.get("id", ""))).is_empty():
			var qq := {"id": str(q.id), "progress": int(q.get("progress", 0))}
			if q.has("deadline"):
				qq["deadline"] = float(q.deadline)
			quests.append(qq)
	done_at = s.get("done_at", {})
	for d in s.get("npcs", []):
		if npcs.has(d.get("id", "")):
			var n = npcs[d.id]
			n.aff = float(d.get("aff", 0.0))
			n.memory = d.get("memory", [])
			n.rumors = d.get("rumors", [])
	var pos: Array = p.get("pos", [0, 0, 7])
	return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
