extends Node3D
## Habitante de Valdeluz: agenda por horas, rutas, visitas a otros habitantes,
## memoria del jugador, afinidad, rumores, globo de diálogo y voz.

const Util = preload("res://scripts/util.gd")
const Data = preload("res://scripts/data.gd")
const Humanoid = preload("res://scripts/humanoid.gd")

var main: Node
var def: Dictionary
var id := ""
var npc_name := ""
var role := ""
var body: Node3D
var pos := Vector3.ZERO
var path: Array = []        # Array de Vector2 (x, z)
var place := ""
var away := false           # dentro de su casa
var busy := ""              # "", "chat", "player"
var aff := 0.0
var memory: Array = []
var rumors: Array = []
var convo: Array = []
var visit_t := randf_range(20.0, 45.0)
var visiting: Node = null
var visit_timer := 0.0
var exit_q: Array = []
var wander_t := 2.0
var face: Node3D = null
var speed := 1.45
var other_idx := 0
var talk_until := 0.0
var label: Label3D
var marker: Label3D
var bubble: Label3D
var bubble_t := 0.0


func setup(d: Dictionary, m: Node) -> void:
	def = d
	main = m
	id = d.id
	npc_name = d.name
	role = d.role
	body = Humanoid.new()
	add_child(body)
	body.build(d.look)
	var top: float = float(d.look.height) * 1.07
	label = Util.label3d(npc_name, 44)
	label.position.y = top + 0.25
	add_child(label)
	marker = Util.label3d("", 90, Color(0.91, 0.71, 0.3))
	marker.position.y = top + 0.7
	add_child(marker)
	bubble = Util.label3d("", 34)
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 520.0
	bubble.position.y = top + 1.2
	add_child(bubble)
	var p := sched_place()
	var last: Vector2 = Data.PLACES[p].path[-1]
	pos = Vector3(last.x, 0, last.y)
	place = p
	away = Data.PLACES[p].hide
	position = pos


func sched_place() -> String:
	var h: int = Game.hour_now()
	var s: Array = def.sched
	var cur: String = s[-1][1]
	for e in s:
		if h >= int(e[0]):
			cur = e[1]
	return cur


func set_place(key: String) -> void:
	var exit := []
	if place != "" and Data.PLACES.has(place):
		var pp: Array = Data.PLACES[place].path
		exit = pp.slice(0, pp.size() - 1)
		exit.reverse()
	if away:
		away = false
		if place != "" and Data.PLACES.has(place):
			var l: Vector2 = Data.PLACES[place].path[-1]
			pos = Vector3(l.x, 0, l.y)
	path = exit + Data.PLACES[key].path.duplicate()
	place = key


func remember(text: String) -> void:
	memory.append(text)
	if memory.size() > 10:
		memory.pop_front()


func show_bubble(text: String, dur: float = 6.0) -> void:
	bubble.text = text
	bubble_t = dur


func say(text: String, gesture: String = "hablar", vol: float = 1.0, with_bubble: bool = true) -> void:
	body.gest = gesture
	body.gest_t = minf(7.0, 1.5 + text.length() * 0.05)
	if with_bubble:
		show_bubble(text, minf(9.0, 2.5 + text.length() * 0.06))
	main.speak(text, def.voice, self, vol)


func end_visit() -> void:
	visiting = null
	exit_q = []
	place = ""
	set_place(sched_place())


func update(dt: float, t: float) -> void:
	var want := "" if visiting else sched_place()
	if want != "" and want != place:
		set_place(want)
	if away:
		visible = false
		return
	visible = true
	var spd := 0.0
	if busy != "":
		if face and is_instance_valid(face):
			var fp := face.global_position
			body.rotation.y = lerp_angle(body.rotation.y, atan2(fp.x - pos.x, fp.z - pos.z), 0.15)
	else:
		if visiting:
			visit_timer -= dt
			var o: Node3D = visiting
			var away_v := Vector3(pos.x - o.pos.x, 0, pos.z - o.pos.z)
			var dlen := maxf(away_v.length(), 0.001)
			if not exit_q.is_empty():
				path = exit_q
			else:
				path = [Vector2(o.pos.x + away_v.x / dlen * 1.6, o.pos.z + away_v.z / dlen * 1.6)]
			if visit_timer <= 0.0 or o.away:
				end_visit()
		if not path.is_empty():
			var tgt: Vector2 = path[0]
			var dx := tgt.x - pos.x
			var dz := tgt.y - pos.z
			var d := sqrt(dx * dx + dz * dz)
			if d < 0.2:
				path.pop_front()
				if path.is_empty() and Data.PLACES.has(place) and Data.PLACES[place].hide and visiting == null:
					away = true
			else:
				var stp := minf(d, speed * dt)
				pos.x += dx / d * stp
				pos.z += dz / d * stp
				spd = speed
				body.rotation.y = lerp_angle(body.rotation.y, atan2(dx, dz), 0.18)
		else:
			if place == "forge" and body.gest == "martillar" and body.gest_t > 0.0:
				# de cara al yunque mientras martilla
				var at: Vector3 = main.world.anvil_top
				body.rotation.y = lerp_angle(body.rotation.y, atan2(at.x - pos.x, at.z - pos.z), 0.15)
			wander_t -= dt
			if wander_t <= 0.0:
				wander_t = randf_range(4.0, 9.0)
				if place == "forge" and randf() < 0.7:
					body.gest = "martillar"
					body.gest_t = 3.5
		visit_t -= dt
		if visit_t <= 0.0:
			visit_t = randf_range(55.0, 110.0)
			var can: bool = path.is_empty() and Data.PLACES.has(place) and not Data.PLACES[place].hide
			var others := []
			for o2 in main.npcs:
				if o2 != self and not o2.away and o2.busy == "" and o2.visiting == null and o2.pos.distance_to(pos) < 45.0:
					others.append(o2)
			if can and not others.is_empty() and randf() < 0.65:
				visiting = others.pick_random()
				visit_timer = 30.0
				path = []
				var pp: Array = Data.PLACES[place].path
				exit_q = pp.slice(0, pp.size() - 1)
				exit_q.reverse()
				place = ""
	pos.y = Util.terrain_h(pos.x, pos.z)
	position = pos
	# mira al jugador cuando está cerca
	var pp2: Vector3 = main.player_pos()
	var dp := pos.distance_to(pp2)
	if dp < 5.0 and busy == "":
		body.look_yaw = wrapf(atan2(pp2.x - pos.x, pp2.z - pos.z) - body.rotation.y, -PI, PI)
	else:
		body.look_yaw = 0.0
	body.talk = main.t_total < talk_until
	body.animate(dt, spd, t)
	label.visible = dp < 22.0
	if bubble_t > 0.0:
		bubble_t -= dt
		bubble.visible = dp < 26.0
		if bubble_t <= 0.0:
			bubble.text = ""
	else:
		bubble.visible = false
