extends Node
## Gestos personalizados: grabas un trazo y le asignas un hechizo o una función del juego;
## cada vez que repites ese trazo, se ejecuta.
##   VR: mantén el agarre (puño con las manos, o el botón lateral del mando) y dibuja en el aire.
##   PC: mantén el clic derecho y dibuja con el ratón.
## Reconocedor tipo «$1»: el trazo se remuestrea a 32 puntos, se centra y se escala; luego se
## compara con las muestras grabadas por distancia media. En VR el trazo se mide respecto a
## hacia dónde mira tu cabeza, así funciona igual aunque te gires.

const N := 32
const SAMPLES_NEEDED := 3
const SAVE_PATH := "user://tierras_vivas_gestos.json"
const MATCH_MAX := 0.3   # distancia media máxima para aceptar un gesto (unidades normalizadas)

const ACTIONS := [
	{"id": "spell:0", "name": "Bola de fuego"},
	{"id": "spell:1", "name": "Escudo"},
	{"id": "spell:2", "name": "Curar"},
	{"id": "eat", "name": "Comer"},
	{"id": "jump", "name": "Saltar"},
	{"id": "rest", "name": "Descansar 1 h"},
	{"id": "menu", "name": "Abrir el menú"},
	{"id": "rumors", "name": "Ver rumores"},
	{"id": "seated", "name": "Modo sentado"},
	{"id": "turn_l", "name": "Girar a la izquierda"},
	{"id": "turn_r", "name": "Girar a la derecha"},
]

var main: Node
var gestures: Array = []        # [{"id": int, "action": String, "kind": "vr"|"pc", "samples": [[Vector3...]...]}]
var next_id := 1
var recording: Dictionary = {}  # {"action": String, "kind": String, "samples": []}
var capturing := false
var source := ""                # "left", "right" o "mouse"
var path: Array = []


func _ready() -> void:
	load_all()


func action_name(id: String) -> String:
	for a in ACTIONS:
		if a.id == id:
			return a.name
	return id


func kind_of(src: String) -> String:
	return "pc" if src == "mouse" else "vr"


# ---------- grabación ----------

func start_recording(action: String) -> void:
	recording = {"action": action, "samples": [], "kind": ""}
	main.on_gesture_record_start(action)


func cancel_recording() -> void:
	recording = {}


func delete_gesture(id: int) -> void:
	for g in gestures:
		if int(g.id) == id:
			gestures.erase(g)
			break
	save_all()


# ---------- captura ----------

func begin(src: String) -> void:
	capturing = true
	source = src
	path = []


func add_point(p: Vector3) -> void:
	if not capturing:
		return
	var min_step := 2.0 if source == "mouse" else 0.004
	if path.is_empty() or p.distance_to(path[-1]) > min_step:
		path.append(p)


func cancel_capture() -> void:
	capturing = false
	path = []


## Termina el trazo. Devuelve {"result": "short"|"sample"|"saved"|"match"|"unknown", ...}.
func end() -> Dictionary:
	capturing = false
	var min_len := 60.0 if source == "mouse" else 0.12
	if path.size() < 4 or path_len(path) < min_len:
		return {"result": "short"}
	var pts := normalize(path)
	var kind := kind_of(source)
	if not recording.is_empty():
		if recording.kind != "" and recording.kind != kind:
			return {"result": "short"}
		recording.kind = kind
		recording.samples.append(pts)
		var n: int = recording.samples.size()
		if n < SAMPLES_NEEDED:
			main.on_gesture_sample(n, SAMPLES_NEEDED)
			return {"result": "sample", "n": n}
		var clash := ""
		var m := recognize(recording.samples[0], kind)
		if not m.is_empty() and m.action != recording.action:
			clash = m.action
		gestures.append({"id": next_id, "action": recording.action, "kind": kind, "samples": recording.samples.duplicate()})
		next_id += 1
		save_all()
		var a: String = recording.action
		recording = {}
		main.on_gesture_saved(a, clash)
		return {"result": "saved", "action": a}
	var best := recognize(pts, kind)
	if best.is_empty():
		main.on_gesture_unknown()
		return {"result": "unknown"}
	main.do_action(best.action, source)
	return {"result": "match", "action": best.action, "dist": best.dist}


func recognize(pts: Array, kind: String) -> Dictionary:
	var best := {}
	for g in gestures:
		if g.kind != kind:
			continue
		for s in g.samples:
			var d := avg_dist(pts, s)
			if d < MATCH_MAX and (best.is_empty() or d < float(best.dist)):
				best = {"action": g.action, "dist": d, "id": g.id}
	return best


# ---------- geometría ----------

static func path_len(pts: Array) -> float:
	var t := 0.0
	for i in range(1, pts.size()):
		t += (pts[i] as Vector3).distance_to(pts[i - 1])
	return t


static func resample(pts: Array, n: int) -> Array:
	var src := pts.duplicate()
	var step := path_len(src) / float(n - 1)
	var out := [src[0]]
	var acc := 0.0
	var i := 1
	while i < src.size():
		var a: Vector3 = src[i - 1]
		var b: Vector3 = src[i]
		var d := a.distance_to(b)
		if d > 0.0 and acc + d >= step:
			var q := a.lerp(b, (step - acc) / d)
			out.append(q)
			src.insert(i, q)
			acc = 0.0
		else:
			acc += d
		i += 1
	while out.size() < n:
		out.append(src[-1])
	return out.slice(0, n)


static func normalize(pts: Array) -> Array:
	var r := resample(pts, N)
	var c := Vector3.ZERO
	for p in r:
		c += p
	c /= float(r.size())
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in r.size():
		var p: Vector3 = r[i] - c
		r[i] = p
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var s := maxf((hi - lo).length(), 0.0001)
	for i in r.size():
		r[i] = r[i] / s
	return r


static func avg_dist(a: Array, b: Array) -> float:
	var t := 0.0
	var n := mini(a.size(), b.size())
	for i in n:
		t += (a[i] as Vector3).distance_to(b[i])
	return t / maxf(float(n), 1.0)


# ---------- guardado ----------

func save_all() -> void:
	var out := []
	for g in gestures:
		var samples := []
		for s in g.samples:
			var flat := []
			for p in s:
				flat.append([p.x, p.y, p.z])
			samples.append(flat)
		out.append({"id": g.id, "action": g.action, "kind": g.kind, "samples": samples})
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"next_id": next_id, "gestures": out}))


func load_all() -> void:
	gestures = []
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	next_id = int(d.get("next_id", 1))
	for g in d.get("gestures", []):
		var samples := []
		for s in g.get("samples", []):
			var pts := []
			for p in s:
				pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			if pts.size() == N:
				samples.append(pts)
		if not samples.is_empty():
			gestures.append({"id": int(g.get("id", 0)), "action": str(g.get("action", "")), "kind": str(g.get("kind", "vr")), "samples": samples})
