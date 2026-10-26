extends Node3D
## Escena principal de Tierras Vivas: construye Valdeluz, crea al jugador, los habitantes y los
## limos, y lleva el bucle del juego (tiempo, rumores, misiones, hechizos, forja, comida,
## economía, portal y guardado). Funciona igual en PC y en VR (OpenXR).
## Prueba automática: godot --headless --path . -- --smoke

const Util = preload("res://scripts/util.gd")
const Data = preload("res://scripts/data.gd")
const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Humanoid = preload("res://scripts/humanoid.gd")
const Npc = preload("res://scripts/npc.gd")
const Slime = preload("res://scripts/slime.gd")
const UI = preload("res://scripts/ui.gd")
const Dialogue = preload("res://scripts/dialogue.gd")
const Panel3D = preload("res://scripts/panel3d.gd")
const Gestures = preload("res://scripts/gestures.gd")

const ZONES := [{"x": -32.0, "z": 14.0, "r": 7.0, "n": 3}, {"x": 54.0, "z": 4.0, "r": 12.0, "n": 5}]
const RESPAWN := Vector3(0, 0, -17.2)
const START := Vector3(0, 0, 7)

var xr := false
var world: Node3D
var player: CharacterBody3D
var ui: CanvasLayer
var dialogue: Node
var gestures: Node
var mouse_trail := Vector2.ZERO
var desk_ready: Dictionary = {}   # hechizo preparado con un gesto en PC
var avatar: Node3D
var npcs: Array = []
var slimes: Array = []
var shots: Array = []
var inter: Array = []
var panels: Array = []
var cur_inter: Dictionary = {}
var pair_cd := {}
var t_total := 0.0
var shop_t := 0.0
var hud_t := 0.0
var save_t := 20.0
var portal_cd := 0.0
var portal_on := 0.0
var forge := {"active": false, "hits": [], "x": 0.0, "dir": 1.0, "speed": 0.85, "zone": 0.5, "w": 0.11, "prev_h": null}
var eat := {"held": null, "key": "", "bites": 0, "anim": 0.0, "cd": 0.0}
var fragment: Dictionary = {}
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var moon: MeshInstance3D
var creator_cam: Camera3D
var creator_ang := 0.0
var shield_mesh: MeshInstance3D
var target_label: Label3D
var hammer: Node3D
var hammer_head: Node3D
var tts_voices := PackedStringArray()
var smoke := false


func _ready() -> void:
	smoke = "--smoke" in OS.get_cmdline_user_args()
	_setup_input()
	Game.world = self
	Game.load_settings()
	var xri := XRServer.find_interface("OpenXR")
	if xri and xri.is_initialized():
		xr = true
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if xri.has_method("get_available_display_refresh_rates"):
			var best := 0.0
			for r in xri.call("get_available_display_refresh_rates"):
				if float(r) <= 90.0 and float(r) > best:
					best = float(r)
			if best > 0.0:
				xri.set("display_refresh_rate", best)
				Engine.physics_ticks_per_second = int(best)
	_build_environment()
	world = World.new()
	add_child(world)
	world.build()
	player = Player.new()
	player.main = self
	add_child(player)
	player.setup(xr)
	player.global_position = START
	avatar = Humanoid.new()
	add_child(avatar)
	avatar.build(avatar_look())
	avatar.position = Vector3(0, 0, 5.2) if xr else Vector3(0, 0, 5.5)
	_spawn_npcs()
	_spawn_slimes()
	_build_interactables()
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.44, 0.83, 1.0, 0.18)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_mesh = Util.sphere(self, 1.1, sm, Vector3.ZERO, 20, 10)
	shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield_mesh.visible = false
	target_label = Util.label3d("", 34, Color(0.89, 0.94, 0.95), true)
	target_label.visible = false
	add_child(target_label)
	_build_hammer()
	ui = UI.new()
	ui.main = self
	add_child(ui)
	ui.setup(xr)
	gestures = Gestures.new()
	gestures.main = self
	add_child(gestures)
	dialogue = Dialogue.new()
	dialogue.main = self
	add_child(dialogue)
	if not xr:
		creator_cam = Camera3D.new()
		creator_cam.fov = 60.0
		add_child(creator_cam)
		creator_cam.current = true
		player.visible = false   # que los brazos en primera persona no salgan en la vista del creador
	_init_tts()
	ui.open_creator()
	if smoke:
		_run_smoke()
	elif "--soak" in OS.get_cmdline_user_args():
		_run_soak()
	elif "--shots" in OS.get_cmdline_user_args():
		_run_shots()


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "run": [KEY_SHIFT], "interact": [KEY_E], "eat": [KEY_F], "spell_1": [KEY_1], "spell_2": [KEY_2], "spell_3": [KEY_3],
		"inventory": [KEY_I], "rumors": [KEY_R], "help": [KEY_H],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.15
	env.ambient_light_sky_contribution = 0.75
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = not xr
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)
	var mm := Util.mat(Color(0.91, 0.93, 0.99), Color(0, 0, 0, 0), 1.0, true).duplicate() as StandardMaterial3D
	mm.set("disable_fog", true)
	moon = Util.sphere(self, 9.0, mm, Vector3.ZERO, 16, 8)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_hammer() -> void:
	hammer = Node3D.new()
	var handle := Util.cyl(hammer, 0.016, 0.018, 0.34, Util.mat(Util.hex("#5b3f28")), Vector3(0, -0.05, 0), 8)
	var headm := Util.box(hammer, Vector3(0.13, 0.065, 0.065), Util.mat(Util.hex("#5a5a5e")), Vector3(0, 0.12, 0))
	for c in [handle, headm]:
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hammer.rotation.x = -PI / 2.2
	hammer_head = Node3D.new()
	hammer_head.position = Vector3(0, 0.12, 0)
	hammer.add_child(hammer_head)
	hammer.visible = false
	add_child(hammer)


func avatar_look() -> Dictionary:
	var l: Dictionary = Game.look.duplicate()
	var out_c := Color.html(str(l.outfit))
	l["pants"] = "#" + out_c.darkened(0.55).to_html(false)
	l["cape_color"] = "#" + out_c.darkened(0.4).to_html(false)
	return l


func rebuild_avatar() -> void:
	avatar.build(avatar_look())
	player.refresh_look()


func player_pos() -> Vector3:
	return player.global_position if player else START


func _spawn_npcs() -> void:
	for d in Data.NPC_DEFS:
		var n := Npc.new()
		add_child(n)
		n.setup(d, self)
		npcs.append(n)
		Game.npcs[d.id] = n


func _spawn_slimes() -> void:
	for z in ZONES:
		for i in int(z.n):
			var s := Slime.new()
			add_child(s)
			s.setup(self, z)
			slimes.append(s)


func slimes_near_field() -> int:
	var c := 0
	for s in slimes:
		if s.alive and Vector2(s.pos.x + 32.0, s.pos.z - 14.0).length() < 16.0:
			c += 1
	return c


func on_hour_tick() -> void:
	if not fragment.is_empty() and Game.now_abs() > float(fragment.exp):
		fragment.node.queue_free()
		fragment = {}
		Game.say("Tu fragmento de recuerdo se desvaneció.", "bad")


# ---------- voz (texto a voz del sistema) ----------

func _init_tts() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		tts_voices = DisplayServer.tts_get_voices_for_language("es")


func speak(text: String, voice: Dictionary, npc: Node = null, vol: float = 1.0) -> void:
	if npc:
		npc.talk_until = t_total + minf(9.0, 0.5 + text.length() * 0.06)
		if npc.pos.distance_to(player_pos()) > 16.0:
			return
	if not bool(Game.settings.tts) or tts_voices.is_empty():
		return
	var v: String = tts_voices[int(voice.idx) % tts_voices.size()]
	DisplayServer.tts_speak(text, v, int(clampf(vol, 0.0, 1.0) * 80.0), float(voice.pitch), float(voice.rate))


# ---------- interactuables ----------

func _add_inter(pos_f: Callable, r: float, ok_f: Callable, label_f: Callable, act_f: Callable) -> void:
	inter.append({"pos": pos_f, "r": r, "ok": ok_f, "label": label_f, "act": act_f})


func _bruno_selling() -> bool:
	var b = Game.npcs["bruno"]
	return not b.away and b.place == "bakery" and b.path.is_empty()


func _build_interactables() -> void:
	for n in npcs:
		_add_inter(func(): return n.pos + Vector3(0, 1.4, 0), 2.6, func(): return not n.away and n.busy != "chat",
			func(): return "Hablar con " + n.npc_name, func(): dialogue.open(n))
	_add_inter(func(): return Vector3(-14, 1.1, -7.6), 2.6, _bruno_selling, func(): return "Comprar pan (%d monedas)" % Game.bread_cost(), buy_bread)
	_add_inter(func(): return Vector3(-14, 1.0, -16.2), 2.2, func(): return not Game.active_q("investigar").is_empty() and int(Game.active_q("investigar").progress) == 0,
		func(): return "Revisar el almacén de Bruno", inspect_store)
	_add_inter(func(): return world.anvil_top, 2.4, func(): return not forge.active, func(): return "Forjar una espada (1 mineral de hierro)", start_forge)
	_add_inter(func(): return Vector3(-5, 1.0, 10), 2.6, func(): return true, func(): return "Abrir tu puesto de venta", func(): ui.open_menu("stall"))
	for a in world.apples:
		_add_inter(func(): return a.node.global_position, 3.4, func(): return a.t <= 0.0, func(): return "Recoger manzana", func():
			a.t = 240.0
			a.node.visible = false
			Game.add_item("manzana")
			Sfx.play("pick")
			Game.say("Recogiste una manzana.")
		)
	for s in world.sheaves:
		_add_inter(func(): return s.node.global_position + Vector3(0, 0.6, 0), 2.4, func(): return s.t <= 0.0, func(): return "Recoger gavilla de trigo", func():
			s.t = 180.0
			s.node.visible = false
			Game.add_item("trigo")
			Sfx.play("pick")
			Game.say("Recogiste una gavilla de trigo.")
		)
	for o in world.ores:
		_add_inter(func(): return o.node.global_position + Vector3(0, 0.9, 0), 2.8, func(): return o.t <= 0.0, func(): return "Picar mineral de hierro", func():
			o.t = 150.0
			o.specks.visible = false
			Game.add_item("hierro", 2 if Game.has_syn("herrero+rastreador") else 1)
			Sfx.play("clang", 0.6)
			Util.burst(self, o.node.global_position + Vector3(0, 1, 0), Color(0.82, 0.48, 0.23), 14, 2.5, 0.6, 0.05)
			Game.say("Obtuviste mineral de hierro.")
		)
	_add_inter(func(): return world.moon_crystal.global_position, 2.6, func(): return world.moon_crystal.visible, func(): return "Tomar el Cristal lunar", func():
		world.moon_crystal.visible = false
		Game.crystal_day = Game.day
		Game.add_item("cristal")
		Sfx.play("heal")
		Game.say("Tomaste un Cristal lunar. Brilla con luz fría.", "gold")
	)
	_add_inter(func(): return world.portal_pos + Vector3(0, 2, 0), 4.0, func(): return not Game.portal_open(),
		func(): return "Portal cerrado — " + ("luna llena: abre de 19:00 a 05:00" if Game.moon_phase() == 4 else "abre de 19:00 a 24:00"),
		func(): Game.say("El portal duerme. Vuelve a las 19:00 o descansa una hora."))
	_add_inter(func(): return world.sanct_crystal.global_position, 3.0, func(): return true, func(): return "Santuario — punto de renacimiento",
		func(): Game.say("Si caes, renacerás aquí. Tu recuerdo quedará donde caíste."))


func _desktop_pick() -> Dictionary:
	if not Game.alive or dialogue.npc or forge.active or ui.any_open():
		return {}
	var cam: Camera3D = player.camera
	var fw: Vector3 = -cam.global_transform.basis.z
	fw.y = 0.0
	fw = fw.normalized()
	var pp := player_pos()
	var best := {}
	var bd := 1e9
	for it in inter:
		if not it.ok.call():
			continue
		var p: Vector3 = it.pos.call()
		var dx := p.x - pp.x
		var dz := p.z - pp.z
		var d := sqrt(dx * dx + dz * dz)
		if d > float(it.r):
			continue
		var dot: float = (dx * fw.x + dz * fw.z) / maxf(d, 0.001)
		if dot < 0.45 and d > 1.2:
			continue
		if d < bd:
			bd = d
			best = it
	return best


## VR: el interactuable más cercano dentro de un cono alrededor del rayo.
func pick_interactable(o: Vector3, d: Vector3) -> Dictionary:
	var best := {}
	var bd := 1e9
	for it in inter:
		if not it.ok.call():
			continue
		var p: Vector3 = it.pos.call()
		var v := p - o
		var along := v.dot(d)
		if along < 0.2 or along > 9.0:
			continue
		var perp := (v - d * along).length()
		if perp < 0.35 + float(it.r) * 0.15 and along < bd:
			bd = along
			best = it
	return best


func show_target(it: Dictionary) -> void:
	if it.is_empty():
		target_label.visible = false
		return
	target_label.visible = true
	target_label.text = it.label.call()
	target_label.global_position = it.pos.call() + Vector3(0, 0.55, 0)


func panel_hit(o: Vector3, d: Vector3) -> Dictionary:
	var best := {}
	for p in panels:
		if not is_instance_valid(p):
			continue
		var h: Dictionary = p.ray_hit(o, d)
		if not h.is_empty() and (best.is_empty() or h.dist < best.dist):
			best = h
	return best


func buzz(side: String, amp: float = 0.5, secs: float = 0.04) -> void:
	if not xr:
		return
	var c: XRController3D = player.ctrl[side]
	c.trigger_haptic_pulse("haptic", 0.0, amp, secs, 0.0)


func vr_toast(msg: String) -> void:
	if ui:
		ui.vr_toast(msg)


# ---------- inicio de partida ----------

func start_game(continuing: bool) -> void:
	Game.started = true
	Game.alive = true
	if continuing:
		var s := Game.load_save()
		var pos := Game.restore(s)
		for x in s.get("stall", []):
			Game.stall.append({"key": str(x.key), "price": int(x.price), "node": null})
		_stall_meshes()
		for n in npcs:
			n.place = ""
			var pl: String = n.sched_place()
			var last: Vector2 = Data.PLACES[pl].path[-1]
			n.pos = Vector3(last.x, 0, last.y)
			n.place = pl
			n.path = []
			n.away = Data.PLACES[pl].hide
		teleport_to(pos)
	else:
		Game.max_hp = Game.base_hp()
		Game.hp = Game.max_hp
		Game.max_mp = float(Game.JOBS[Game.cls].mp)
		Game.mp = Game.max_mp
		teleport_to(START)
		player.yaw = 0.0
	ui.close_creator()
	player.visible = true
	if creator_cam:
		creator_cam.current = false
	player.camera.current = true
	avatar.visible = false
	player.refresh_look()
	ui.show_hud()
	ui.refresh_hotbar()
	if not xr and not smoke:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.say("Bienvenido de vuelta, %s." % Game.player_name if continuing else "Bienvenido a Valdeluz, %s. Habla con los habitantes y pregúntales si tienen trabajo." % Game.player_name)
	if not continuing:
		get_tree().create_timer(5.5).timeout.connect(func():
			Game.say("El portal del noreste abre a las 19:00. Faltan %d minutos de juego (1 minuto = 1 segundo)." % maxi(0, 19 * 60 - int(Game.minute)))
		)


func can_move() -> bool:
	return Game.started and Game.alive and dialogue.npc == null and not forge.active and not ui.any_open()


func teleport_to(p: Vector3) -> void:
	var y := 0.0 if p.x > 250.0 else Util.terrain_h(p.x, p.z)
	player.teleport(Vector3(p.x, y + 0.05, p.z))


func jump() -> void:
	player.jump()


func set_spell(i: int) -> void:
	Game.spell = i
	ui.refresh_hotbar()


func cycle_spell() -> void:
	set_spell((Game.spell + 1) % Game.SPELLS.size())
	vr_toast("Hechizo: " + Game.SPELLS[Game.spell].name)


# ---------- gestos personalizados ----------

## Ejecuta la acción asignada a un gesto.
func do_action(a: String, src: String = "") -> void:
	if not Game.alive:
		return
	if a.begins_with("spell:"):
		var i := int(a.split(":")[1])
		set_spell(i)
		if Game.SPELLS[i].id == "fuego":
			# hechizo que se lanza: se prepara, se apunta y se lanza
			if xr:
				player.prepare_spell(i, src if src in ["left", "right"] else "right")
			elif Game.mp < float(Game.SPELLS[i].mp):
				Game.say("No te alcanza el maná.", "bad")
			else:
				desk_ready = {"spell": i, "t": 0.0}
				Sfx.play("shield", 1.6)
				ui.set_ready("%s preparada · apunta y haz clic para lanzarla" % Game.SPELLS[i].name, Game.SPELLS[i].color)
			return
		# escudo y curar actúan sobre ti: se lanzan al momento
		if xr:
			var side := src if src in ["left", "right"] else "right"
			var r: Array = player.ray(side)
			var d: Vector3 = r[1]
			cast_spell(i, player.holder(side).global_position + d * 0.2, d, 1.0)
		else:
			cast_from_camera()
	else:
		match a:
			"eat":
				var k := Game.food_key()
				if k == "":
					Game.say("No tienes comida.", "bad")
				else:
					start_hold(k)
					if not xr:
						eat.anim = 1.0
			"jump":
				jump()
			"rest":
				rest_hour()
			"menu":
				ui.open_menu("menu", "inv")
			"rumors":
				ui.open_menu("menu", "rumors")
			"seated":
				toggle_seated()
			"turn_l":
				if xr:
					player.snap_turn(1.0)
				else:
					player.yaw += PI / 6.0
			"turn_r":
				if xr:
					player.snap_turn(-1.0)
				else:
					player.yaw -= PI / 6.0
	Sfx.play("pick", 1.3)
	if src in ["left", "right"]:
		buzz(src, 0.7, 0.06)
	vr_toast("Gesto: " + gestures.action_name(a))
	if not xr:
		ui.set_gesture_hint("Gesto: " + gestures.action_name(a))


## PC: lanza el hechizo preparado hacia la mira.
func release_ready() -> void:
	if desk_ready.is_empty():
		return
	var i: int = desk_ready.spell
	desk_ready = {}
	ui.set_ready("")
	var cam: Camera3D = player.camera
	var d: Vector3 = -cam.global_transform.basis.z
	if cast_spell(i, cam.global_position + d * 0.7 + Vector3(0, -0.15, 0), d, 1.05):
		player.cast_anim = 0.35


func on_gesture_record_start(action: String) -> void:
	ui.close_menu()
	if not xr and not smoke:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var how := "mantén el agarre (puño o botón lateral) y traza el gesto en el aire" if xr else "mantén el clic derecho y dibuja el gesto con el ratón"
	Game.say("Graba el gesto para «%s»: %s. Hazlo %d veces igual. Esc para cancelar." % [gestures.action_name(action), how, gestures.SAMPLES_NEEDED])


func on_gesture_sample(n: int, need: int) -> void:
	Sfx.play("pick")
	Game.say("Muestra %d de %d. Repítelo otra vez." % [n, need])


func on_gesture_saved(action: String, clash: String) -> void:
	Sfx.play("level")
	var warn := " Ojo: se parece a tu gesto de «%s»; si se confunden, bórralo y grábalo más distinto." % gestures.action_name(clash) if clash != "" else ""
	Game.say("Gesto guardado: ahora hace «%s».%s" % [gestures.action_name(action), warn], "gold")
	ui.mark("menu")


func on_gesture_unknown() -> void:
	vr_toast("Gesto no reconocido.")
	if not xr:
		ui.set_gesture_hint("Gesto no reconocido")


func rest_hour() -> void:
	Game.advance(60.0)
	Game.st = Game.max_st
	Game.say("Descansaste una hora. Son las %s." % Game.time_str())


func toggle_seated() -> void:
	player.toggle_seated()
	Game.say("Modo sentado: la altura se compensa; salta con A o desde la muñeca." if Game.seated else "Modo de pie: puedes saltar de verdad.")


func on_dialog_open() -> void:
	if not xr:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.open_dialog()


func on_dialog_close() -> void:
	ui.close_dialog()
	if not xr and not ui.any_open() and not smoke:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- entrada de PC ----------

func _unhandled_input(ev: InputEvent) -> void:
	if xr or not Game.started:
		return
	# gestos con el ratón: mantener clic derecho y dibujar
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT:
		if ev.pressed and can_move():
			gestures.begin("mouse")
			mouse_trail = Vector2.ZERO
			gestures.add_point(Vector3.ZERO)
			ui.gesture_trail_begin()
		elif not ev.pressed and gestures.capturing and gestures.source == "mouse":
			ui.gesture_trail_end()
			gestures.end()
		return
	if ev is InputEventMouseMotion and gestures.capturing and gestures.source == "mouse":
		mouse_trail += Vector2(ev.relative.x, -ev.relative.y)
		gestures.add_point(Vector3(mouse_trail.x, mouse_trail.y, 0))
		ui.gesture_trail_add(mouse_trail)
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.yaw -= ev.relative.x * 0.0025
		player.pitch = clampf(player.pitch - ev.relative.y * 0.0022, -1.35, 1.35)
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if forge.active:
			forge_desktop_hit()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if not desk_ready.is_empty():
				release_ready()
			elif dialogue.npc == null:
				cast_from_camera()
		elif not ui.any_open() and dialogue.npc == null:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if ev.is_action_pressed("ui_cancel"):
		if not gestures.recording.is_empty():
			gestures.cancel_recording()
			Game.say("Grabación de gesto cancelada.")
		elif forge.active:
			cancel_forge()
		elif ui.is_open("menu"):
			ui.close_menu()
		elif ui.is_open("help"):
			ui.hide_win("help")
		elif dialogue.npc:
			dialogue.close()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not ui.any_open() and dialogue.npc == null and not forge.active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			pass
		return
	if forge.active:
		if ev.is_action_pressed("jump"):
			forge_desktop_hit()
		return
	if dialogue.npc or ui.is_open("creator"):
		return
	if ev.is_action_pressed("interact") and not cur_inter.is_empty():
		cur_inter.act.call()
	elif ev.is_action_pressed("spell_1"):
		set_spell(0)
		cast_from_camera()
	elif ev.is_action_pressed("spell_2"):
		set_spell(1)
		cast_from_camera()
	elif ev.is_action_pressed("spell_3"):
		set_spell(2)
		cast_from_camera()
	elif ev.is_action_pressed("jump"):
		jump()
	elif ev.is_action_pressed("eat"):
		eat_desktop()
	elif ev.is_action_pressed("inventory"):
		if ui.is_open("menu"):
			ui.close_menu()
		else:
			ui.open_menu("menu", "inv")
	elif ev.is_action_pressed("rumors"):
		if ui.is_open("menu"):
			ui.close_menu()
		else:
			ui.open_menu("menu", "rumors")
	elif ev.is_action_pressed("help"):
		ui.open_help()


# ---------- hechizos ----------

func cast_from_camera() -> void:
	var cam: Camera3D = player.camera
	var d: Vector3 = -cam.global_transform.basis.z
	var o: Vector3 = cam.global_position + d * 0.7 + Vector3(0, -0.15, 0)
	if cast_spell(Game.spell, o, d, 1.0):
		player.cast_anim = 0.35


func cast_spell(i: int, origin: Vector3, dir: Vector3, power: float = 1.0) -> bool:
	var sp: Dictionary = Game.SPELLS[i]
	if not Game.alive:
		return false
	if Game.mp < float(sp.mp):
		Game.say("No te alcanza el maná.", "bad")
		return false
	Game.mp -= float(sp.mp)
	match sp.id:
		"fuego":
			var fb := Node3D.new()
			Util.sphere(fb, 0.16, Util.mat(Color(1, 0.63, 0.25), Color(1, 0.48, 0.16), 4.0, true), Vector3.ZERO, 10, 5)
			var l := OmniLight3D.new()
			l.light_color = Color(1, 0.55, 0.2)
			l.light_energy = 1.5
			l.omni_range = 4.0
			fb.add_child(l)
			add_child(fb)
			fb.global_position = origin
			shots.append({"node": fb, "vel": dir.normalized() * 19.0, "life": 2.2, "power": power, "trail": 0.0})
			Sfx.play("fire")
		"escudo":
			Game.shield_t = 6.0 * (1.0 + Game.jw("guardian")) * power
			Sfx.play("shield")
			Util.burst(self, player_pos() + Vector3(0, 1.1, 0), sp.color, 20, 2.0, 0.8, 0.06)
		"curar":
			Game.hp = minf(Game.max_hp, Game.hp + 30.0 * (1.0 + Game.jw("sanador")) * power)
			if Game.has_syn("cocinero+sanador"):
				Game.st = minf(Game.max_st, Game.st + 40.0)
			if Game.has_syn("guardian+sanador"):
				Game.shield_t = maxf(Game.shield_t, 3.0)
			Sfx.play("heal")
			Util.burst(self, player_pos() + Vector3(0, 1.0, 0), sp.color, 26, 1.6, 1.1, 0.05, 1.4)
	return true


func _update_shots(dt: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var node: Node3D = s.node
		s.life -= dt
		if Game.has_syn("elementalista+rastreador"):
			var best: Node3D = null
			var bd := 14.0
			for sl in slimes:
				if sl.alive:
					var dd: float = sl.global_position.distance_to(node.global_position)
					if dd < bd:
						bd = dd
						best = sl
			if best:
				var want: Vector3 = (best.global_position + Vector3(0, 0.4, 0) - node.global_position).normalized() * 19.0
				s.vel = s.vel.lerp(want, 0.08)
		node.global_position += s.vel * dt
		s.trail -= dt
		if s.trail <= 0.0:
			s.trail = 0.05
			Util.burst(self, node.global_position, Color(1, 0.54, 0.24), 2, 0.4, 0.35, 0.04)
		var hit: Node = null
		for sl in slimes:
			if sl.alive and (sl.global_position + Vector3(0, 0.42, 0)).distance_to(node.global_position) < 0.95:
				hit = sl
				break
		var np := node.global_position
		var g := 0.0 if np.x > 250.0 else Util.terrain_h(np.x, np.z)
		if hit or s.life <= 0.0 or np.y < g:
			if hit:
				var dmg := 22.0 * float(s.power) * (1.0 + 0.4 * Game.jw("elementalista")) * (1.15 if Game.cls == "rastreador" else 1.0)
				dmg *= (1.1 if Game.title_active("Azote de Limos") else 1.0) * (1.25 if Game.fire_buff_t > 0.0 else 1.0)
				hit.damage(dmg)
			Util.burst(self, np, Color(1, 0.48, 0.16), 18, 3.0, 0.6, 0.07)
			Sfx.play("boom")
			node.queue_free()
			shots.remove_at(i)


func on_slime_killed(_s: Node) -> void:
	Game.kills += 1
	Game.add_item("gel")
	Game.gold += randi_range(2, 4)
	Game.add_xp(12)
	var q := Game.active_q("limos")
	if not q.is_empty():
		q.progress = int(q.progress) + 1
	Game.check_titles()
	Game.changed.emit()


func hurt_player(n: float) -> void:
	if Game.shield_t > 0.0:
		n *= 0.2 if (Game.has_syn("guardian+herrero") and Game.forged_own) else 0.3
	if Game.has_syn("guardian+rastreador"):
		n *= 0.8
	Game.hp -= n
	Sfx.play("hurt")
	ui.flash_hurt()
	buzz("left", 0.8, 0.1)
	buzz("right", 0.8, 0.1)
	if Game.hp <= 0.0:
		_die()


func _die() -> void:
	Game.alive = false
	Game.hp = 0.0
	var lost := int(Game.xp * 0.3)
	Game.xp -= lost
	if not fragment.is_empty():
		fragment.node.queue_free()
	var fnode := Node3D.new()
	Util.gem(fnode, 0.25, Util.mat(Color(0.75, 0.91, 1.0), Color(0.62, 0.85, 1.0), 2.0, true), Vector3.ZERO)
	add_child(fnode)
	fnode.global_position = player_pos() + Vector3(0, 1, 0)
	fragment = {"node": fnode, "xp": lost, "exp": Game.now_abs() + 180.0}
	get_tree().create_timer(0.9).timeout.connect(func():
		teleport_to(RESPAWN)
		Game.hp = roundf(Game.max_hp * 0.6)
		Game.alive = true
		Game.say("Renaciste en el Santuario. Tu fragmento de recuerdo (%d XP) quedó donde caíste: recupéralo antes de 3 horas." % lost, "bad")
	)


# ---------- forja ----------

func forge_width() -> float:
	var w := 0.11 * (1.0 + 0.8 * Game.jw("herrero"))
	if Game.has_syn("cocinero+herrero") and Game.buff_t > 0.0:
		w *= 1.15
	if Game.title_active("Martillo Firme"):
		w *= 1.2
	return w


func start_forge() -> void:
	if Game.count("hierro") <= 0:
		Game.say("Necesitas 1 mineral de hierro. Hay rocas al este del pueblo.", "bad")
		return
	Game.remove_item("hierro")
	forge.active = true
	forge.hits = []
	forge.x = 0.0
	forge.dir = 1.0
	forge.speed = 0.85
	forge.w = forge_width()
	forge.zone = randf_range(0.25, 0.75)
	forge.prev_h = null
	var d = Game.npcs["dorran"]
	if not d.away and d.pos.distance_to(player_pos()) < 8.0:
		d.say(["Veamos esas manos.", "No golpees con rabia. Golpea con oído.", "El metal te dirá cuándo."].pick_random(), "pensar")
	if not xr:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var hd: Node3D = player.holder("right")
		hammer.get_parent().remove_child(hammer)
		hd.add_child(hammer)
		hammer.position = Vector3(0, -0.02, 0.02)
		hammer.visible = true
	ui.open_forge()


func forge_acc() -> float:
	return clampf(1.0 - absf(float(forge.x) - float(forge.zone)) / (float(forge.w) * 2.2), 0.0, 1.0)


func forge_hit(acc: float) -> void:
	if not forge.active:
		return
	forge.hits.append(acc)
	Sfx.play("clang", 0.9 + acc * 0.25)
	Util.burst(self, world.anvil_top, Color(1, 0.75, 0.38), 10 + roundi(acc * 20.0), 3.0, 0.5, 0.04, 1.0)
	forge.zone = randf_range(0.15, 0.85)
	forge.speed = float(forge.speed) + 0.12
	buzz("right", 0.9, 0.07)
	if forge.hits.size() >= 5:
		_finish_forge()
	else:
		ui.mark("forge")


func forge_desktop_hit() -> void:
	player.hit_anim = 0.3
	forge_hit(forge_acc())


func forge_trigger() -> void:
	forge_hit(clampf(forge_acc() + (0.05 if Game.title_active("Martillo Firme") else 0.0), 0.0, 1.0))


func cancel_forge() -> void:
	if not forge.active:
		return
	forge.active = false
	_hide_hammer()
	ui.close_forge()
	Game.add_item("hierro")
	Game.say("Dejaste la forja. Recuperaste el mineral.")
	if not xr and not smoke:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _hide_hammer() -> void:
	hammer.visible = false
	if hammer.get_parent() != self:
		hammer.get_parent().remove_child(hammer)
		add_child(hammer)


func _finish_forge() -> void:
	forge.active = false
	_hide_hammer()
	ui.close_forge()
	var total := 0.0
	for a in forge.hits:
		total += float(a)
	var avg: float = total / float(forge.hits.size())
	var g := 4 if avg > 0.92 else (3 if avg > 0.8 else (2 if avg > 0.62 else (1 if avg > 0.4 else 0)))
	if Game.cls == "herrero" and avg > 0.7:
		g = mini(4, g + 1)
	if Game.title_active("Heredero del Yunque"):
		g = mini(4, g + 1)
	if Game.has_syn("elementalista+herrero") and Game.fire_buff_t > 0.0:
		g = mini(4, g + 1)
	Game.add_item("espada:%d" % g)
	Game.best_grade = maxi(Game.best_grade, g)
	Game.forged_own = true
	Game.say("Forjaste: %s — precisión %d %%." % [Game.item_name("espada:%d" % g), roundi(avg * 100.0)], "gold")
	var d = Game.npcs["dorran"]
	if g >= 2:
		Game.award_title("Martillo Firme")
		d.remember("%s forjó una espada %s en mi yunque" % [Game.player_name, Game.GRADES[g].to_lower()])
	else:
		d.remember("%s forjó una espada %s; le falta oído" % [Game.player_name, Game.GRADES[g].to_lower()])
	if not d.away and d.pos.distance_to(player_pos()) < 10.0:
		d.aff = clampf(d.aff + (5.0 if g >= 2 else 1.0), -100.0, 100.0)
		d.say("…Esto no lo hizo la suerte. Bien." if g >= 3 else ("Aceptable. Para ser tu primera semana." if g >= 2 else "Metal triste. Otra vez."), "reir" if g >= 2 else "enojado")
	if not xr and not smoke:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_forge(dt: float) -> void:
	if not forge.active:
		return
	forge.x = float(forge.x) + float(forge.dir) * float(forge.speed) * dt
	if forge.x > 1.0:
		forge.x = 1.0
		forge.dir = -1.0
	elif forge.x < 0.0:
		forge.x = 0.0
		forge.dir = 1.0
	var in_zone: bool = absf(float(forge.x) - float(forge.zone)) < float(forge.w)
	var rm := world.anvil_ring.material_override as StandardMaterial3D
	rm.albedo_color.a = 1.0 if in_zone else 0.3
	world.anvil_ring.scale = Vector3(1.5, 0.3, 1.5) if in_zone else Vector3(1.0, 0.2, 1.0)
	if xr and hammer.visible:
		var hp := hammer_head.global_position
		if forge.prev_h != null:
			var prev: Vector3 = forge.prev_h
			var vy := (hp.y - prev.y) / maxf(dt, 0.001)
			var at: Vector3 = world.anvil_top
			var dxz := Vector2(hp.x - at.x, hp.z - at.z).length()
			if vy < -0.8 and hp.y < at.y + 0.08 and prev.y >= at.y + 0.08 and dxz < 0.45:
				forge_hit(clampf(forge_acc() * (1.0 + 0.1 * Game.jw("herrero")) + (0.05 if Game.title_active("Martillo Firme") else 0.0), 0.0, 1.0))
		forge.prev_h = hp


# ---------- comida ----------

func _item_mesh(k: String) -> Node3D:
	var g := Node3D.new()
	if k == "pan":
		var m := Util.capsule(g, 0.05, 0.1, Util.mat(Util.hex("#c98a43")), Vector3.ZERO)
		m.rotation.z = PI / 2.0
	elif k == "manzana":
		Util.sphere(g, 0.045, Util.mat(Util.hex("#c8332b")), Vector3.ZERO, 10, 6)
		Util.cyl(g, 0.004, 0.004, 0.03, Util.mat(Util.hex("#4b3626")), Vector3(0, 0.05, 0), 4)
	elif k == "trigo":
		Util.cyl(g, 0.05, 0.07, 0.22, Util.mat(Util.hex("#e2c35a")), Vector3.ZERO, 8)
	elif k == "hierro":
		Util.sphere(g, 0.06, Util.mat(Util.hex("#8a6e5a")), Vector3.ZERO, 5, 3)
	elif k == "gel":
		Util.sphere(g, 0.05, Util.mat(Color(0.55, 0.88, 0.54), Color(0, 0, 0, 0), 1.0, false, 0.8), Vector3.ZERO, 10, 6)
	elif k == "cristal":
		Util.gem(g, 0.06, Util.mat(Color(0.9, 0.96, 1.0), Color(0.5, 0.72, 1.0), 1.5), Vector3.ZERO)
	elif k.begins_with("espada"):
		var gr := int(k.split(":")[1])
		var col: Color = Game.GRADE_COL[gr]
		Util.box(g, Vector3(0.04, 0.6, 0.012), Util.mat(Color(0.85, 0.87, 0.89), col if gr >= 2 else Color(0, 0, 0, 0), 0.6), Vector3(0, 0.36, 0))
		Util.box(g, Vector3(0.16, 0.025, 0.04), Util.mat(Util.hex("#6a5232")), Vector3(0, 0.05, 0))
		Util.cyl(g, 0.015, 0.015, 0.12, Util.mat(Util.hex("#3a2a1e")), Vector3(0, -0.02, 0), 6)
	else:
		Util.box(g, Vector3(0.08, 0.08, 0.08), Util.mat(Color(0.5, 0.5, 0.5)), Vector3.ZERO)
	for c in g.get_children():
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


func start_hold(k: String) -> void:
	drop_held()
	eat.key = k
	eat.bites = 0
	var m := _item_mesh(k)
	if xr:
		player.holder("right").add_child(m)
		m.position = Vector3(0, -0.02, -0.06)
	else:
		player.camera.add_child(m)
		m.scale = Vector3.ONE * 1.1
		m.position = Vector3(0.25, -0.27, -0.5)
	eat.held = m


func reattach_held() -> void:
	if is_instance_valid(eat.held) and xr:
		var m: Node3D = eat.held
		m.get_parent().remove_child(m)
		player.holder("right").add_child(m)
		m.position = Vector3(0, -0.02, -0.06)
	if hammer.visible and xr:
		hammer.get_parent().remove_child(hammer)
		player.holder("right").add_child(hammer)


func drop_held() -> void:
	if is_instance_valid(eat.held):
		eat.held.queue_free()
	eat.held = null
	eat.key = ""


func bite() -> void:
	if not is_instance_valid(eat.held) or eat.cd > 0.0:
		return
	eat.cd = 0.55
	eat.bites = int(eat.bites) + 1
	Sfx.play("crunch")
	var m: Node3D = eat.held
	m.scale *= 0.8
	var cam: Camera3D = player.camera
	var mouth: Vector3 = cam.global_position - cam.global_transform.basis.z * 0.3 + Vector3(0, -0.1, 0)
	Util.burst(self, mouth, Color(0.91, 0.78, 0.56), 6, 0.8, 0.4, 0.015)
	if eat.bites >= 3:
		var k: String = eat.key
		var f: Dictionary = Game.ITEMS[k].food
		var mul := 1.0 + 1.5 * Game.jw("cocinero")
		Game.remove_item(k)
		Game.hp = minf(Game.max_hp, Game.hp + f.hp * mul)
		Game.st = minf(Game.max_st, Game.st + f.st * mul)
		if f.buff > 0:
			Game.buff_t = float(f.buff) * (2.0 if Game.cls == "cocinero" else 1.0)
		if Game.has_syn("cocinero+elementalista"):
			Game.fire_buff_t = 60.0
		Game.say("Comiste %s: +%d vida, +%d energía%s" % [Game.ITEMS[k].name.to_lower(), roundi(f.hp * mul), roundi(f.st * mul), ". Te sientes bien alimentado." if f.buff > 0 else "."])
		drop_held()


func eat_desktop() -> void:
	var k := Game.food_key()
	if k == "":
		Game.say("No tienes comida. Compra pan a Bruno o recoge manzanas.", "bad")
		return
	if not is_instance_valid(eat.held) or eat.key != k:
		start_hold(k)
	eat.anim = 1.0


func _update_eat(dt: float) -> void:
	if eat.cd > 0.0:
		eat.cd = float(eat.cd) - dt
	if not is_instance_valid(eat.held):
		return
	var m: Node3D = eat.held
	if xr:
		var cam: Camera3D = player.camera
		var mouth: Vector3 = cam.global_position - cam.global_transform.basis.z * 0.05 + Vector3(0, -0.07, 0)
		if m.global_position.distance_to(mouth) < 0.16:
			bite()
	elif eat.anim > 0.0:
		var prev: float = eat.anim
		eat.anim = minf(2.0, prev + dt * 2.4)
		var k := sin((float(eat.anim) - 1.0) * PI)
		m.position = Vector3(lerpf(0.25, 0.0, k), lerpf(-0.27, -0.08, k), lerpf(-0.5, -0.2, k))
		if eat.anim >= 1.45 and prev < 1.45:
			bite()
		if eat.anim >= 2.0:
			eat.anim = 0.0


# ---------- pan, almacén y puesto ----------

func buy_bread() -> void:
	var c := Game.bread_cost()
	if Game.gold < c:
		Game.say("No tienes monedas suficientes.", "bad")
		return
	Game.gold -= c
	Game.add_item("pan")
	Sfx.play("coin")
	var b = Game.npcs["bruno"]
	b.aff = clampf(b.aff + 1.0, -100.0, 100.0)
	if randf() < 0.5 and dialogue.npc != b:
		b.say(["Crujiente. Como debe ser.", "No lo aplastes.", "Hecho a mano, no por menú."].pick_random())
	if int(b.aff) % 5 == 0:
		b.remember("%s me compra pan seguido" % Game.player_name)
	Game.check_titles()


func inspect_store() -> void:
	var q := Game.active_q("investigar")
	if q.is_empty():
		return
	q.progress = 1
	Sfx.play("pick")
	Game.say("Bajo una lona hay seis sacos de harina escondidos. Vuelve con Sira." if Game.hoarding == true else "El almacén está casi vacío: unos sacos rotos y nada más. Vuelve con Sira.", "gold")
	Game.changed.emit()


func _stall_meshes() -> void:
	for i in Game.stall.size():
		var s: Dictionary = Game.stall[i]
		if s.node == null or not is_instance_valid(s.node):
			s.node = _item_mesh(s.key)
			s.node.scale = Vector3.ONE * 2.2
			add_child(s.node)
		s.node.position = Vector3(-5.9 + i * 0.9, 1.02, 10)


func place_on_stall(k: String, price: int) -> bool:
	if Game.stall.size() >= 3:
		Game.say("Tu puesto solo tiene 3 espacios.", "bad")
		return false
	if Game.count(k) <= 0:
		return false
	Game.remove_item(k)
	Game.stall.append({"key": k, "price": maxi(1, price), "node": null})
	_stall_meshes()
	Sfx.play("pick")
	return true


func take_from_stall(i: int) -> void:
	if i < 0 or i >= Game.stall.size():
		return
	var s: Dictionary = Game.stall[i]
	if s.node and is_instance_valid(s.node):
		s.node.queue_free()
	Game.stall.remove_at(i)
	Game.add_item(s.key)
	_stall_meshes()


func _update_shop(dt: float) -> void:
	shop_t -= dt
	if shop_t > 0.0 or Game.stall.is_empty():
		return
	shop_t = 6.0
	for n in npcs:
		if n.away or n.busy != "" or Vector2(n.pos.x + 5.0, n.pos.z - 10.0).length() > 9.0:
			continue
		var i := randi() % Game.stall.size()
		var s: Dictionary = Game.stall[i]
		var base := Game.item_base(s.key) * (1.0 + 0.35 * Game.jw("comerciante"))
		if Game.has_syn("comerciante+herrero") and str(s.key).begins_with("espada"):
			base *= 1.3
		var ch: float = clampf(1.5 - float(s.price) / base, 0.0, 1.0) * 0.45 * (1.0 + n.aff / 200.0)
		if randf() < ch:
			Game.gold += int(s.price)
			if s.node and is_instance_valid(s.node):
				s.node.queue_free()
			Game.stall.remove_at(i)
			_stall_meshes()
			Sfx.play("coin")
			if Game.has_syn("comerciante+sanador"):
				Game.mp = minf(Game.max_mp, Game.mp + 10.0)
			n.aff = clampf(n.aff + 1.0, -100.0, 100.0)
			n.remember("Le compré %s a %s por %d monedas" % [Game.item_name(s.key).to_lower(), Game.player_name, s.price])
			Game.say("%s compró %s en tu puesto por %d monedas." % [n.npc_name, Game.item_name(s.key), s.price], "gold")
			if n.pos.distance_to(player_pos()) < 14.0:
				n.say(["Me lo llevo.", "Buen precio.", "Esto me sirve."].pick_random(), "reir")
			Game.changed.emit()
			break
		elif float(s.price) > base * 1.5 and randf() < 0.25 and n.pos.distance_to(player_pos()) < 14.0:
			n.say("¿%d monedas? Ni loco." % s.price, "enojado")
			break


# ---------- conversaciones entre habitantes → rumores → misiones ----------

func _rumor_for() -> Dictionary:
	var pool := []
	if Game.bread_price >= 5 and not Game.flags.get("investigated", false):
		pool.append({"w": 3, "a": "¿Viste el pan a %d monedas? Dicen que Bruno acapara harina." % Game.bread_price, "b": ["¿Bruno? No sé… habrá que ver.", "Eso hay que comprobarlo."].pick_random(), "tag": "acaparamiento"})
	var pests := slimes_near_field()
	if pests >= 3:
		pool.append({"w": 2, "a": "Los limos se están comiendo el trigo de Lía. Ya van %d." % pests, "b": "Alguien tendría que espantarlos.", "tag": "limos"})
	if Game.best_grade >= 2:
		pool.append({"w": 2, "a": "%s forjó una espada %s. Dorran dice que fue suerte." % [Game.player_name, Game.GRADES[Game.best_grade].to_lower()], "b": "Dorran nunca dice que algo está bien.", "tag": "forja"})
	for n in npcs:
		if n.aff >= 20:
			pool.append({"w": 2, "a": "%s ayudó a %s. Parece de fiar." % [Game.player_name, n.npc_name], "b": "Me alegra oír eso.", "tag": "fama"})
			break
	if Game.kills >= 5:
		pool.append({"w": 1, "a": "El Viajero lleva %d limos. El campo respira." % Game.kills, "b": "Ya era hora.", "tag": "caza"})
	pool.append({"w": 1, "a": "Esta noche la luna está %s. %s" % [Game.moon_name(), Game.portal_text()], "b": "Sira lo sabrá mejor.", "tag": "luna"})
	pool.append({"w": 1, "a": ["El trigo está caro este año.", "¿Oíste ruidos en las Ruinas?", "Bruno quemó una hornada esta mañana."].pick_random(), "b": ["No me digas.", "Ajá.", "Vaya."].pick_random(), "tag": "charla"})
	var tot := 0.0
	for p in pool:
		tot += float(p.w)
	var r := randf() * tot
	for p in pool:
		r -= float(p.w)
		if r <= 0.0:
			return p
	return pool[0]


func npc_chat(a: Node, b: Node) -> void:
	var ids := [a.id, b.id]
	ids.sort()
	var key := "%s+%s" % [ids[0], ids[1]]
	if float(pair_cd.get(key, 0.0)) > t_total:
		return
	pair_cd[key] = t_total + 90.0
	for n in [a, b]:
		n.busy = "chat"
		n.path = []
	a.face = b
	b.face = a
	var r := _rumor_for()
	var near: bool = a.pos.distance_to(player_pos()) < 12.0
	a.rumors.append(r.a)
	b.rumors.append(r.a)
	for n in [a, b]:
		if n.rumors.size() > 6:
			n.rumors.pop_front()
	Game.rumor_log.push_front({"t": Game.time_str(), "text": "%s a %s: %s" % [a.npc_name, b.npc_name, r.a], "day": Game.day})
	if Game.rumor_log.size() > 25:
		Game.rumor_log.pop_back()
	if r.tag == "acaparamiento" and not Game.flags.get("rumor_hoard", false):
		Game.flags["rumor_hoard"] = true
		Game.hoarding = randf() < 0.5
		Game.say("Nuevo rumor en el pueblo: Bruno acapara harina. Sira querrá investigarlo.")
	if r.tag == "fama":
		b.aff = clampf(b.aff + 2.0, -100.0, 100.0)
	a.show_bubble(r.a, 6.0)
	a.body.gest = "hablar"
	a.body.gest_t = 5.0
	if near:
		speak(r.a, a.def.voice, a, 0.7)
	var reply: String = r.b
	get_tree().create_timer(3.2).timeout.connect(func():
		b.show_bubble(reply, 4.0)
		b.body.gest = ["reir", "pensar", "hablar"].pick_random()
		b.body.gest_t = 3.0
		if near:
			speak(reply, b.def.voice, b, 0.7)
	)
	get_tree().create_timer(7.6).timeout.connect(func():
		for n in [a, b]:
			if n.busy == "chat":
				n.busy = ""
				n.face = null
			if n.visiting:
				n.end_visit()
	)
	Game.changed.emit()


func _npc_chats() -> void:
	for i in npcs.size():
		for j in range(i + 1, npcs.size()):
			var a = npcs[i]
			var b = npcs[j]
			if a.away or b.away or a.busy != "" or b.busy != "":
				continue
			if a.pos.distance_to(b.pos) < 2.4 and (a.visiting == b or b.visiting == a or randf() < 0.004):
				npc_chat(a, b)


# ---------- bucle principal ----------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	t_total += dt
	if Game.started:
		Game.advance(dt)  # 1 segundo real = 1 minuto de juego
		Game.mp = minf(Game.max_mp, Game.mp + dt * 2.2 * (1.5 if Game.title_active("Viajero Lunar") else 1.0))
		Game.st = minf(Game.max_st, Game.st + dt * (9.0 if Game.buff_t > 0.0 else 5.0))
		if Game.buff_t > 0.0:
			Game.buff_t -= dt
			Game.hp = minf(Game.max_hp, Game.hp + dt * 1.2)
		if Game.fire_buff_t > 0.0:
			Game.fire_buff_t -= dt
		if Game.shield_t > 0.0:
			Game.shield_t -= dt
			shield_mesh.visible = true
			shield_mesh.global_position = player_pos() + Vector3(0, 1, 0)
		else:
			shield_mesh.visible = false
		if not desk_ready.is_empty():
			desk_ready.t += dt
			if desk_ready.t > 8.0:
				desk_ready = {}
				ui.set_ready("")
				Game.say("El hechizo preparado se desvaneció.")
		if xr:
			player.xr_frame(dt)
		else:
			player.update_fp_arms(dt)
		_update_eat(dt)
		_update_forge(dt)
		for n in npcs:
			n.update(dt, t_total)
		_npc_chats()
		for s in slimes:
			s.update(dt)
		_update_shots(dt)
		_update_shop(dt)
		_update_resources(dt)
		_update_portals(dt)
		_update_bounds()
		if not xr:
			cur_inter = _desktop_pick()
			ui.set_prompt("" if cur_inter.is_empty() else cur_inter.label.call())
		hud_t -= dt
		if hud_t <= 0.0:
			hud_t = 0.25
			ui.refresh_hud()
			_update_markers()
		save_t -= dt
		if save_t <= 0.0:
			save_t = 20.0
			Game.save_game()
	else:
		if xr:
			# antes de empezar (creador de personaje) también hay que leer mandos/manos y apuntar
			player.xr_menu_frame(dt)
		if creator_cam:
			creator_ang += dt * 0.25
			var c := avatar.position
			# el personaje queda a la derecha, fuera de la ventana de creación
			creator_cam.global_position = Vector3(c.x + sin(creator_ang) * 3.2 - 1.8, 1.45, c.z + cos(creator_ang) * 3.2)
			creator_cam.look_at(Vector3(c.x - 1.7, 1.0, c.z), Vector3.UP)
		avatar.rotation.y = sin(t_total * 0.5) * 0.4
		avatar.animate(dt, 0.0, t_total)
		for n in npcs:
			n.update(dt, t_total)
	world.water.rotation.y += dt * 0.2
	world.forge_light.light_energy = 1.2 + sin(t_total * 13.0) * 0.2 + sin(t_total * 7.3) * 0.15
	world.sanct_crystal.rotation.y += dt * 0.6
	_update_sky()


func _update_resources(dt: float) -> void:
	for a in world.apples:
		if a.t > 0.0:
			a.t -= dt
			if a.t <= 0.0:
				a.node.visible = true
	for s in world.sheaves:
		if s.t > 0.0:
			s.t -= dt
			if s.t <= 0.0:
				s.node.visible = true
	for o in world.ores:
		if o.t > 0.0:
			o.t -= dt
			if o.t <= 0.0:
				o.specks.visible = true
	var mc: MeshInstance3D = world.moon_crystal
	if not mc.visible and Game.crystal_day != Game.day:
		mc.visible = true
	mc.rotation.y += dt
	mc.position.y = 1.4 + sin(t_total * 1.5) * 0.15
	if not fragment.is_empty():
		var fn: Node3D = fragment.node
		fn.rotation.y += dt * 2.0
		var pp := player_pos()
		if Vector2(pp.x - fn.global_position.x, pp.z - fn.global_position.z).length() < 1.3:
			Game.add_xp(int(fragment.xp))
			Game.say("Recuperaste tu fragmento de recuerdo (+%d XP)." % int(fragment.xp), "gold")
			Sfx.play("heal")
			fn.queue_free()
			fragment = {}


func _update_portals(dt: float) -> void:
	portal_cd -= dt
	portal_on = lerpf(portal_on, 1.0 if Game.portal_open() else 0.0, 0.05)
	world.portal_mat.set_shader_parameter("on", portal_on)
	if portal_cd > 0.0 or not Game.alive:
		return
	var pp := player_pos()
	var pt: Vector3 = world.portal_pos
	if Game.portal_open() and Vector2(pp.x - pt.x, pp.z - pt.z).length() < 1.5:
		portal_cd = 3.0
		Sfx.play("portal")
		teleport_to(Vector3(Util.RX, 0, 9))
		if not Game.ruins_seen:
			Game.ruins_seen = true
			Game.award_title("Viajero Lunar")
		Game.say("Ruinas Lunares. El portal de regreso está a tu espalda.")
		return
	var rp: Vector3 = world.ruins_portal
	if Vector2(pp.x - rp.x, pp.z - rp.z).length() < 1.5:
		portal_cd = 3.0
		Sfx.play("portal")
		teleport_to(pt + Vector3(-3, 0, -3))


func _update_bounds() -> void:
	var pp := player_pos()
	if pp.x > 250.0:
		var v := Vector2(pp.x - Util.RX, pp.z)
		if v.length() > 46.0:
			var n := v.normalized() * 45.0
			teleport_to(Vector3(Util.RX + n.x, 0, n.y))
	elif Vector2(pp.x, pp.z).length() > 150.0:
		var n2 := Vector2(pp.x, pp.z).normalized() * 149.0
		teleport_to(Vector3(n2.x, 0, n2.y))


func _update_markers() -> void:
	var pp := player_pos()
	for n in npcs:
		var del := not Game.deliverable(n.id).is_empty()
		var off := not Game.offerable(n.id).is_empty()
		n.marker.text = "?" if del else ("!" if off else "")
		n.marker.modulate = Color(0.49, 0.81, 0.54) if del else Color(0.91, 0.71, 0.3)
		n.marker.visible = not n.away and (del or off) and n.pos.distance_to(pp) < 40.0


func _update_sky() -> void:
	var m := fmod(Game.minute, 1440.0) / 1440.0
	var a := m * TAU - PI / 2.0
	var sy := sin(a)
	var dayk := Util.smooth(-0.15, 0.25, sy)
	var dusk := 1.0 - absf(clampf(sy * 3.0, -1.0, 1.0))
	var top := Color(0.027, 0.043, 0.11).lerp(Color(0.2, 0.45, 0.82), dayk).lerp(Color(0.23, 0.29, 0.48), dusk * 0.5 * (1.0 - dayk * 0.5))
	var bot := Color(0.086, 0.125, 0.227).lerp(Color(0.6, 0.77, 0.9), dayk).lerp(Color(0.94, 0.63, 0.38), dusk * 0.75)
	var pp := player_pos()
	if pp.x > 250.0:
		top = Color(0.043, 0.06, 0.165)
		bot = Color(0.165, 0.19, 0.376)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = bot
	sky_mat.ground_horizon_color = bot
	sky_mat.ground_bottom_color = bot.darkened(0.6)
	env.fog_light_color = bot.lerp(top, 0.35)
	env.ambient_light_energy = 0.25 + dayk * 0.45
	if sy > -0.05:
		sun.look_at_from_position(pp + Vector3(cos(a) * 60.0, maxf(sy, 0.05) * 80.0, 25.0), pp, Vector3.UP)
		sun.light_color = Color(1, 0.95, 0.84).lerp(Color(1, 0.63, 0.38), dusk * 0.7)
		sun.light_energy = 0.15 + dayk * 1.15
	else:
		sun.look_at_from_position(pp + Vector3(-cos(a) * 60.0, -sy * 70.0, -20.0), pp, Vector3.UP)
		sun.light_color = Color(0.56, 0.65, 0.85)
		sun.light_energy = 0.22
	world.set_night(1.0 - dayk)
	moon.global_position = pp + Vector3(-cos(a) * 300.0, -sy * 260.0 + 20.0, -120.0)
	moon.visible = sy < 0.1


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		Game.save_game()


# ---------- prueba automática (godot --headless --path . -- --smoke) ----------

func _feed_gesture(pts: Array) -> Dictionary:
	gestures.begin("mouse")
	for p in pts:
		gestures.add_point(p)
	return gestures.end()


func _g_circle(start: float, noise: float) -> Array:
	var out := []
	for i in 48:
		var a := start + i / 47.0 * TAU
		out.append(Vector3(cos(a) * 120.0 + randf_range(-noise, noise), sin(a) * 120.0 + randf_range(-noise, noise), 0))
	return out


func _g_line(noise: float) -> Array:
	var out := []
	for i in 30:
		out.append(Vector3(randf_range(-noise, noise), i * 8.0, 0))
	return out


func _g_zigzag() -> Array:
	var out := []
	for i in 40:
		out.append(Vector3(i * 6.0, 80.0 if (i / 5) % 2 == 0 else -80.0, 0) + Vector3(0, (i % 5) * 4.0, 0))
	return out


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _check(cond: bool, what: String, fails: Array) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


## Capturas para revisar el aspecto: godot --path . -- --shots  (guarda PNG en SHOT_DIR o user://shots)
func _look_from(p: Vector3, target: Vector3, eye_drop: float = 0.0) -> void:
	teleport_to(p)
	var d := target - p
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = clampf(atan2(target.y - (p.y + 1.6 - eye_drop), Vector2(d.x, d.z).length()), -1.2, 1.2)


func _run_shots() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.0)
	get_viewport().get_texture().get_image().save_png(dir + "/creador.png")
	start_game(false)
	Game.minute = 15.0 * 60.0
	await _wait(0.5)
	var views := [
		["pueblo", Vector3(-2, 0, 24), Vector3(0, 2.0, -6)],
		["plaza", Vector3(0, 0, 9), Vector3(0, 1.5, -10)],
		["panaderia", Vector3(-9, 0, -2), Vector3(-14, 1.5, -11)],
		["forja", Vector3(9, 0, -3), Vector3(14, 1.2, -11)],
		["taberna", Vector3(6, 0, 3), Vector3(14, 2.0, 12)],
		["granja", Vector3(-8, 0, 6), Vector3(-25, 1.0, 14)],
		["bosque", Vector3(20, 0, 20), Vector3(40, 3.0, 40)],
	]
	for v in views:
		_look_from(v[1], v[2])
		await _wait(1.0)
		get_viewport().get_texture().get_image().save_png(dir + "/" + str(v[0]) + ".png")
	for id in ["bruno", "lia", "dorran", "sira"]:
		var n = Game.npcs[id]
		var np: Vector3 = n.global_position
		var fwd := Vector3(sin(n.body.rotation.y), 0, cos(n.body.rotation.y))
		_look_from(np + fwd * 2.6 + Vector3(0.6, 0, 0), np + Vector3(0, 1.1, 0))
		await _wait(0.8)
		get_viewport().get_texture().get_image().save_png(dir + "/npc_" + id + ".png")
	var dn = Game.npcs["dorran"]
	for k in 3:
		dn.body.gest = "martillar"
		dn.body.gest_t = 6.0
		_look_from(dn.global_position + Vector3(2.4, 0, 1.6), world.anvil_top + Vector3(-0.4, 0, 0.4))
		await _wait(0.45 + k * 0.25)
		get_viewport().get_texture().get_image().save_png(dir + "/martillar_%d.png" % k)
	print("SHOTS: OK ", ProjectSettings.globalize_path(dir))
	get_tree().quit()


func _run_smoke() -> void:
	var fails := []
	await _wait(0.5)
	print("SMOKE: inicio")
	_check(ui.is_open("creator"), "creador abierto", fails)
	Game.cls = "herrero"
	Game.sub = "elementalista"
	ui.mark("creator")
	await _wait(0.2)
	start_game(false)
	await _wait(0.6)
	_check(Game.started and Game.max_hp == 120.0, "partida iniciada como Herrero (vida 120)", fails)
	var e400: String = dialogue.explain_error(400, "invalid_request_error", "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.")
	_check("saldo" in e400 and "console.anthropic.com" in e400, "error 400 de la IA explicado: sin saldo", fails)
	var animated := 0
	for n in npcs:
		if n.body.model != null and n.body.anim != null and n.body.anim.is_playing() and n.body.cur_anim != "":
			animated += 1
	_check(animated == npcs.size(), "habitantes con modelo animado, sin pose T (%d/%d)" % [animated, npcs.size()], fails)
	var p0 := player_pos()
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	_check(player_pos().distance_to(p0) > 1.0, "el jugador camina (%.2f m)" % player_pos().distance_to(p0), fails)
	var bruno = Game.npcs["bruno"]
	dialogue.open(bruno)
	await _wait(0.3)
	_check(dialogue.reply != "" and not dialogue.busy, "saludo de Bruno: " + dialogue.reply, fails)
	_check(ui.is_open("dialog"), "ventana de diálogo abierta", fails)
	var pan0 := Game.count("pan")
	for o in dialogue.options():
		if o.i == "special":
			dialogue.choose(o)
	await _wait(0.2)
	_check(Game.count("pan") == pan0 + 1, "comprar pan desde el diálogo", fails)
	for o in dialogue.options():
		if o.i == "about":
			dialogue.choose(o)
	await _wait(0.2)
	_check(dialogue.you == "¿Quién eres?" and dialogue.reply.begins_with("Bruno") or dialogue.reply.begins_with("Soy"), "opción «¿Quién eres?» responde", fails)
	for o in dialogue.options():
		if o.i == "work":
			dialogue.choose(o)
	await _wait(0.2)
	_check(dialogue.offer == "trigo", "Bruno ofrece la misión del trigo", fails)
	Game.accept_quest(dialogue.offer)
	dialogue.offer = ""
	dialogue.close()
	_check(not Game.active_q("trigo").is_empty(), "misión aceptada", fails)
	start_forge()
	await _wait(0.2)
	_check(forge.active and ui.is_open("forge"), "forja abierta", fails)
	for k in 5:
		forge_hit(0.9)
		await _wait(0.05)
	_check(not forge.active and Game.best_grade >= 3, "espada forjada (grado %d)" % Game.best_grade, fails)
	var hp_before := Game.hp
	Game.hp = 50.0
	eat_desktop()
	for k in 3:
		await _wait(0.9)
		eat.cd = 0.0
		if is_instance_valid(eat.held):
			eat.anim = 1.0
	await _wait(0.9)
	_check(Game.hp > 50.0 and not is_instance_valid(eat.held), "comer con 3 mordidas (vida %.0f)" % Game.hp, fails)
	Game.hp = hp_before
	var mp0 := Game.mp
	set_spell(0)
	cast_from_camera()
	await _wait(0.3)
	_check(Game.mp < mp0, "bola de fuego lanzada", fails)
	npc_chat(npcs[1], npcs[2])
	await _wait(0.2)
	_check(Game.rumor_log.size() >= 1, "conversación entre habitantes crea un rumor", fails)
	ui.open_menu("menu", "inv")
	await _wait(0.2)
	_check(ui.is_open("menu"), "menú abierto", fails)
	ui.open_menu("stall")
	var k0: String = Game.inv.keys()[0]
	_check(place_on_stall(k0, Game.item_base(k0)), "poner objeto en el puesto", fails)
	await _wait(0.1)
	take_from_stall(0)
	ui.close_menu()
	Game.advance(120.0)
	await _wait(0.2)
	_check(Game.portal_open(), "portal abierto de noche (%s)" % Game.time_str(), fails)
	portal_cd = 0.0
	teleport_to(world.portal_pos)
	await _wait(0.6)
	_check(player_pos().x > 250.0, "el portal lleva a las Ruinas Lunares", fails)
	# panel VR: un botón dentro de un panel 3D debe recibir el clic del rayo
	var clicked := [false]
	var pc := PanelContainer.new()
	var btn := Button.new()
	btn.text = "Probar"
	btn.pressed.connect(func(): clicked[0] = true)
	pc.add_child(btn)
	var host := Panel3D.new()
	add_child(host)
	host.setup(pc, Vector2i(400, 200), 0.4)
	host.global_position = Vector3(0, 50, 0)
	await _wait(0.2)
	var hit := host.ray_hit(Vector3(0, 50, 1), Vector3(0, 0, -1))
	_check(not hit.is_empty(), "el rayo toca el panel 3D", fails)
	if not hit.is_empty():
		host.pointer_move(hit.px)
		await get_tree().process_frame
		host.press(true)
		await get_tree().process_frame
		host.press(false)
		await _wait(0.1)
	_check(clicked[0], "clic en un botón del panel 3D (VR)", fails)
	Game.save_game()
	var s := Game.load_save()
	_check(s.has("p") and s.p.cls == "herrero", "guardar y leer la partida", fails)
	# gestos personalizados
	gestures.gestures = []
	gestures.start_recording("spell:0")
	for k in 3:
		_feed_gesture(_g_circle(k * 0.08, 6.0))
	_check(gestures.gestures.size() == 1 and gestures.recording.is_empty(), "grabar gesto: círculo → Bola de fuego", fails)
	gestures.start_recording("jump")
	for k in 3:
		_feed_gesture(_g_line(6.0))
	_check(gestures.gestures.size() == 2, "grabar gesto: línea hacia arriba → Saltar", fails)
	Game.mp = Game.max_mp
	var mp_g := Game.mp
	var r1 := _feed_gesture(_g_circle(0.15, 10.0))
	_check(r1.result == "match" and r1.action == "spell:0" and not desk_ready.is_empty() and Game.mp == mp_g, "repetir el círculo prepara la Bola de fuego sin gastar maná (%s)" % str(r1), fails)
	release_ready()
	_check(Game.mp < mp_g and desk_ready.is_empty(), "clic: se lanza el hechizo preparado", fails)
	var aim: Dictionary = player.aim_hit(Vector3(10, 20, 10), Vector3(0, -1, 0))
	_check(absf(aim.point.y - Util.terrain_h(10, 10)) < 0.35, "el láser de puntería encuentra el suelo", fails)
	var r2 := _feed_gesture(_g_line(10.0))
	_check(r2.result == "match" and r2.action == "jump", "repetir la línea hace Saltar", fails)
	var r3 := _feed_gesture(_g_zigzag())
	_check(r3.result == "unknown", "un garabato distinto no se reconoce (%s)" % str(r3), fails)
	gestures.save_all()
	gestures.load_all()
	_check(gestures.gestures.size() == 2, "los gestos se guardan en el dispositivo", fails)
	# VR: preparar, apuntar con el láser y lanzar con el movimiento de la mano
	if player.aim_root == null:
		player._build_xr_helpers()
	Game.mp = Game.max_mp
	var mp_v := Game.mp
	player.prepare_spell(0, "right")
	player._update_ready(0.1)
	_check(not player.ready_spell.is_empty() and player.aim_root.visible and Game.mp == mp_v, "VR: hechizo preparado con láser, sin gastar maná", fails)
	var aim_d: Vector3 = player.ray("right")[1]
	player.pads.right.vel = aim_d * 1.0
	player._update_ready(0.5)
	_check(not player.ready_spell.is_empty(), "VR: mover la mano despacio no lo lanza", fails)
	player.pads.right.vel = aim_d * 3.5
	player._update_ready(0.02)
	_check(player.ready_spell.is_empty() and Game.mp < mp_v and not player.aim_root.visible, "VR: el gesto de lanzar dispara el hechizo", fails)
	player.pads.right.vel = Vector3.ZERO
	player.ray_root.visible = false
	ui.open_menu("menu", "gestos")
	await _wait(0.2)
	_check(ui.is_open("menu"), "pestaña Gestos del menú", fails)
	ui.close_menu()
	print("SMOKE: %s" % ("OK" if fails.is_empty() else "FALLOS: " + ", ".join(fails)))
	get_tree().quit(0 if fails.is_empty() else 1)


## Prueba larga: varios días de juego acelerados para ejercitar agendas, visitas, rumores y tienda.
func _run_soak() -> void:
	smoke = true
	await _wait(0.3)
	start_game(false)
	Game.stall.append({"key": "manzana", "price": 2, "node": null})
	Game.inv["hierro"] = 5
	_stall_meshes()
	Engine.time_scale = 10.0
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		if frames < 2400:
			Game.advance(0.0)
		if frames % 1500 == 0:
			print("SOAK día %d %s · rumores %d · trigo %.0f · pan %d · oro %d" % [Game.day, Game.time_str(), Game.rumor_log.size(), Game.wheat, Game.bread_price, Game.gold])
		if frames == 600:
			for o in dialogue.options():
				pass
			dialogue.open(Game.npcs["sira"])
		if frames == 650:
			for o in dialogue.options():
				if o.i == "other":
					dialogue.choose(o)
		if frames == 700:
			dialogue.close()
			ui.open_help()
		if frames == 720:
			ui.hide_win("help")
			ui.open_menu("menu", "settings")
		if frames == 740:
			ui.open_menu("menu", "titles")
		if frames == 760:
			ui.close_menu()
		await get_tree().process_frame
		frames += 1
	print("SOAK: OK")
	get_tree().quit(0)
