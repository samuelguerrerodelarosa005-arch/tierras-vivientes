extends Node3D
## Personaje humanoide hecho con primitivas, con animación de caminar, gestos y boca al hablar.
## Mira hacia +Z. Se usa para los habitantes y para la vista previa del jugador.

const Util = preload("res://scripts/util.gd")

var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var torso: MeshInstance3D
var head: Node3D
var mouth: MeshInstance3D
var cape: Node3D
var phase := randf() * 6.0
var gest := ""
var gest_t := 0.0
var talk := false
var look_yaw := 0.0
var height := 1.75
var imported_model: Node3D
var imported_anim_player: AnimationPlayer
var imported_animation := ""


func build(o: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	imported_model = null
	imported_anim_player = null
	imported_animation = ""
	torso = null
	var model_path := "res://models/characters/villager.glb"
	if ResourceLoader.exists(model_path):
		var packed_model := load(model_path) as PackedScene
		if packed_model:
			imported_model = packed_model.instantiate() as Node3D
			if imported_model:
				imported_model.name = "ImportedVillager"
				add_child(imported_model)
				imported_model.scale = Vector3.ONE * float(o.get("model_scale", 1.0))
				imported_anim_player = _find_animation_player(imported_model)
				height = float(o.get("height", 1.75))
				scale = Vector3.ONE * (height / 1.75)
				return
	var b: float = float(o.get("build", 1.0))
	height = float(o.get("height", 1.75))
	var m_skin := Util.mat(Color.html(str(o.skin)))
	var m_out := Util.mat(Color.html(str(o.outfit)))
	var m_pants := Util.mat(Color.html(str(o.get("pants", "#3b3430"))))
	var m_hair := Util.mat(Color.html(str(o.hair)))
	var m_boot := Util.mat(Color.html("#2b2018"))

	leg_l = Node3D.new()
	leg_r = Node3D.new()
	leg_l.position = Vector3(-0.1 * b, 0.92, 0)
	leg_r.position = Vector3(0.1 * b, 0.92, 0)
	for leg in [leg_l, leg_r]:
		Util.capsule(leg, 0.075 * b, 0.6, m_pants, Vector3(0, -0.38, 0))
		Util.box(leg, Vector3(0.15 * b, 0.12, 0.26), m_boot, Vector3(0, -0.84, 0.04))
		add_child(leg)

	torso = Util.capsule(self, 0.2 * b, 0.42, m_out, Vector3(0, 1.24, 0))
	torso.scale.z = 0.72
	# Capas discretas de ropa para romper la silueta de una sola cápsula.
	var m_leather := Util.mat(Color.html("#493626"))
	var m_stitch := Util.mat(Color.html(str(o.outfit)).darkened(0.18))
	Util.cyl(self, 0.205 * b, 0.205 * b, 0.09, m_leather, Vector3(0, 0.98, 0), 12)
	Util.box(self, Vector3(0.39 * b, 0.12, 0.025), m_leather, Vector3(0, 1.08, 0.151 * b))
	Util.box(self, Vector3(0.035 * b, 0.30, 0.018), m_stitch, Vector3(-0.105 * b, 1.28, 0.147 * b))
	Util.box(self, Vector3(0.035 * b, 0.30, 0.018), m_stitch, Vector3(0.105 * b, 1.28, 0.147 * b))
	# Cuello y hombros suavizan la transición entre torso y brazos.
	Util.cyl(self, 0.105 * b, 0.12, 0.08, m_leather, Vector3(0, 1.51, 0), 12)
	Util.sphere(self, 0.09 * b, m_out, Vector3(-0.245 * b, 1.45, 0), 8, 5)
	Util.sphere(self, 0.09 * b, m_out, Vector3(0.245 * b, 1.45, 0), 8, 5)
	if o.get("apron", false):
		var apron_m := Util.mat(Color.html("#d9d0bb"))
		Util.box(self, Vector3(0.34 * b, 0.55, 0.025), apron_m, Vector3(0, 1.05, 0.16 * b))
		Util.box(self, Vector3(0.36 * b, 0.045, 0.035), m_leather, Vector3(0, 1.31, 0.18 * b))

	arm_l = Node3D.new()
	arm_r = Node3D.new()
	arm_l.position = Vector3(-0.27 * b, 1.46, 0)
	arm_r.position = Vector3(0.27 * b, 1.46, 0)
	for arm in [arm_l, arm_r]:
		Util.capsule(arm, 0.058 * b, 0.46, m_out, Vector3(0, -0.27, 0))
		Util.sphere(arm, 0.065, m_skin, Vector3(0, -0.6, 0), 8, 4)
		add_child(arm)

	Util.cyl(self, 0.06, 0.07, 0.1, m_skin, Vector3(0, 1.6, 0), 8)
	head = Node3D.new()
	head.position = Vector3(0, 1.75, 0)
	add_child(head)
	var skull := Util.sphere(head, 0.135, m_skin, Vector3.ZERO, 16, 10)
	skull.scale.y = 1.1
	var m_eye := Util.mat(Color.html("#211b16"))
	var m_brow := Util.mat(Color.html(str(o.hair)).darkened(0.12))
	Util.sphere(head, 0.018, m_eye, Vector3(-0.048, 0.02, 0.122), 8, 4)
	Util.sphere(head, 0.018, m_eye, Vector3(0.048, 0.02, 0.122), 8, 4)
	Util.box(head, Vector3(0.045, 0.009, 0.012), m_brow, Vector3(-0.048, 0.049, 0.121))
	Util.box(head, Vector3(0.045, 0.009, 0.012), m_brow, Vector3(0.048, 0.049, 0.121))
	# Nariz muy sutil, para que el rostro no parezca una esfera lisa.
	Util.sphere(head, 0.018, m_skin, Vector3(0, -0.018, 0.132), 8, 4)
	mouth = Util.box(head, Vector3(0.05, 0.009, 0.01), Util.mat(Color.html("#693c32")), Vector3(0, -0.055, 0.128))

	var hs := str(o.get("hair_style", "corto"))
	if hs == "rapado":
		var short_hair := Util.mat(Color.html(str(o.hair)).lerp(Color.html(str(o.skin)), 0.55))
		var cap0 := Util.sphere(head, 0.139, short_hair, Vector3(0, 0.02, -0.005), 14, 8)
		cap0.scale = Vector3(1, 0.85, 1)
	else:
		var cap := Util.sphere(head, 0.146, m_hair, Vector3(0, 0.03, -0.012), 14, 8)
		cap.scale = Vector3(1, 0.9, 1)
		if hs == "largo":
			Util.box(head, Vector3(0.27, 0.32, 0.08), m_hair, Vector3(0, -0.14, -0.1))
		elif hs == "coleta":
			Util.sphere(head, 0.06, m_hair, Vector3(0, -0.02, -0.16), 8, 4)
			Util.capsule(head, 0.04, 0.16, m_hair, Vector3(0, -0.15, -0.18))
	if o.get("beard", false):
		Util.box(head, Vector3(0.18, 0.1, 0.06), m_hair, Vector3(0, -0.09, 0.1))

	cape = null
	if o.get("cape", false):
		cape = Node3D.new()
		cape.position = Vector3(0, 1.5, -0.15 * b)
		Util.box(cape, Vector3(0.5 * b, 0.95, 0.03), Util.mat(Color.html(str(o.get("cape_color", "#2a3a4a")))), Vector3(0, -0.48, 0))
		add_child(cape)
	scale = Vector3.ONE * (height / 1.85)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _play_imported_animation(candidates: Array[String]) -> void:
	if imported_anim_player == null:
		return
	for candidate in candidates:
		if imported_anim_player.has_animation(candidate):
			if imported_animation != candidate:
				imported_anim_player.play(candidate)
				imported_animation = candidate
			return


func animate(dt: float, speed: float, t: float) -> void:
	if imported_model != null:
		if gest_t > 0.0:
			gest_t -= dt
			match gest:
				"saludar": _play_imported_animation(["Wave", "wave", "Salute", "salute", "Talk", "talk"])
				"hablar": _play_imported_animation(["Talk", "talk", "Idle", "idle"])
				"pensar": _play_imported_animation(["Think", "think", "Idle", "idle"])
				_: _play_imported_animation(["Walk", "walk", "Idle", "idle"] if speed > 0.1 else ["Idle", "idle"])
		else:
			_play_imported_animation(["Walk", "walk", "Run", "run"] if speed > 0.1 else ["Idle", "idle"])
		return
	if torso == null:
		return
	phase += dt * speed * 3.4
	var amp := minf(0.7, speed * 0.38) if speed > 0.1 else 0.0
	var sw := sin(phase) * amp
	leg_l.rotation.x = lerpf(leg_l.rotation.x, sw, 0.3)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -sw, 0.3)
	var a_l := -sw * 0.8
	var a_r := sw * 0.8
	var z_l := 0.06
	var z_r := -0.06
	torso.position.y = 1.24
	if gest_t > 0.0:
		gest_t -= dt
		match gest:
			"saludar":
				a_r = -2.7
				z_r = -0.3 + sin(t * 11.0) * 0.35
			"pensar":
				a_r = -2.2
				z_r = 0.5
			"reir":
				torso.position.y = 1.24 + absf(sin(t * 14.0)) * 0.03
				a_l = -0.3
				a_r = -0.3
			"enojado":
				z_l = 0.9
				z_r = -0.9
				a_l = -0.5
				a_r = -0.5
			"martillar":
				a_r = -1.6 + absf(sin(t * 5.0)) * 1.4
			"hablar":
				a_r = -0.6 + sin(t * 4.0) * 0.3
				z_r = -0.2
	arm_l.rotation.x = lerpf(arm_l.rotation.x, a_l, 0.25)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, a_r, 0.25)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, z_l, 0.25)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, z_r, 0.25)
	torso.scale.y = 1.0 + sin(t * 2.0 + phase * 0.1) * 0.015
	mouth.scale.y = 1.0 + absf(sin(t * 17.0 + phase)) * 4.0 if talk else 1.0
	head.rotation.y = lerpf(head.rotation.y, clampf(look_yaw, -1.0, 1.0), 0.12)
	if cape:
		cape.rotation.x = lerpf(cape.rotation.x, 0.08 + speed * 0.12, 0.1)
