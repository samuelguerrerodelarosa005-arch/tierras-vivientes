extends Node3D
## Personaje humanoide. Si el aspecto trae "model", usa un modelo animado (.glb de KayKit, CC0) con
## sus animaciones (quieto, caminar, correr, saludar…); si no, lo construye con primitivas.
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

# ---- modelo animado ----
const MODELS := {
	"caballero": "res://models/characters/Knight.glb",
	"barbaro": "res://models/characters/Barbarian.glb",
	"maga": "res://models/characters/Mage.glb",
	"picara": "res://models/characters/Rogue.glb",
}
const LOOPED := ["Unarmed_Idle", "Idle", "Walking_A", "Walking_B", "Running_A", "Interact", "1H_Melee_Attack_Chop", "Sit_Floor_Idle"]
const GEST_ANIM := {
	"saludar": "Cheer", "hablar": "Interact", "reir": "Cheer", "enojado": "Hit_A",
	"martillar": "1H_Melee_Attack_Chop", "pensar": "Unarmed_Idle",
}
const WALK_SPEED := 2.2   # m/s a la que la animación de caminar coincide con los pies
var model: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var head_bone := -1
var cur_anim := ""
var look_cur := 0.0
var nod := 0.0


func build(o: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	model = null
	anim = null
	skel = null
	torso = null
	cur_anim = ""
	if MODELS.has(str(o.get("model", ""))) and _build_model(o):
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
	Util.cyl(self, 0.205 * b, 0.205 * b, 0.09, Util.mat(Color.html("#3a2a1e")), Vector3(0, 0.98, 0))
	if o.get("apron", false):
		Util.box(self, Vector3(0.34 * b, 0.55, 0.02), Util.mat(Color.html("#f2ede2")), Vector3(0, 1.05, 0.16 * b))

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
	var skull := Util.sphere(head, 0.135, m_skin, Vector3.ZERO, 14, 8)
	skull.scale.y = 1.1
	var m_eye := Util.mat(Color.html("#15100c"))
	Util.sphere(head, 0.018, m_eye, Vector3(-0.048, 0.02, 0.122), 6, 3)
	Util.sphere(head, 0.018, m_eye, Vector3(0.048, 0.02, 0.122), 6, 3)
	mouth = Util.box(head, Vector3(0.06, 0.012, 0.01), Util.mat(Color.html("#5a2a24")), Vector3(0, -0.055, 0.128))

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


func _build_model(o: Dictionary) -> bool:
	var path: String = MODELS[str(o.model)]
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	model = ps.instantiate() as Node3D
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	# armas y objetos en las manos ocultos salvo los que pida el aspecto ("show")
	var keep: Array = o.get("show", [])
	for slot in ["handslot_l", "handslot_r"]:
		var sn := model.find_child(slot, true, false)
		if sn:
			for c in sn.get_children():
				(c as Node3D).visible = c.name in keep
	for hn in o.get("hide", []):
		var n := model.find_child(str(hn), true, false)
		if n:
			(n as Node3D).visible = false
	# altura: la del cuerpo en reposo (sin armas)
	var top := 0.0
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.get_parent() is BoneAttachment3D or not mi.visible:
			continue
		top = maxf(top, mi.get_aabb().end.y)
	height = float(o.get("height", 1.75))
	scale = Vector3.ONE * (height / (top if top > 0.5 else 2.4))
	if anim:
		for a in LOOPED:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		anim.mixer_applied.connect(_after_anim)
		_play("Unarmed_Idle", 0.0)
		anim.seek(randf() * 1.0, true)
	if skel:
		head_bone = skel.find_bone("head")
	return true


func _play(a: String, blend: float = 0.2) -> void:
	if anim == null or a == cur_anim or not anim.has_animation(a):
		return
	anim.play(a, blend)
	cur_anim = a


## Después de aplicar la animación: gira la cabeza hacia quien mira y asiente al hablar.
func _after_anim() -> void:
	if skel == null or head_bone < 0:
		return
	var q := skel.get_bone_pose_rotation(head_bone)
	q = q * Quaternion(Vector3.UP, look_cur) * Quaternion(Vector3.RIGHT, nod)
	skel.set_bone_pose_rotation(head_bone, q)


func _animate_model(dt: float, speed: float, t: float) -> void:
	var want := "Unarmed_Idle"
	var rate := 1.0
	if speed > 3.2:
		want = "Running_A"
		rate = clampf(speed / 5.0, 0.7, 1.4)
	elif speed > 0.1:
		want = "Walking_A"
		rate = clampf(speed / WALK_SPEED, 0.6, 1.5)
	if gest_t > 0.0:
		gest_t -= dt
		if speed <= 0.1 and GEST_ANIM.has(gest):
			want = GEST_ANIM[gest]
	_play(want)
	anim.speed_scale = rate
	look_cur = lerpf(look_cur, clampf(look_yaw, -1.0, 1.0), 0.12)
	nod = lerpf(nod, sin(t * 7.0 + phase) * 0.09 if talk else 0.0, 0.2)


func animate(dt: float, speed: float, t: float) -> void:
	if model != null and anim != null:
		_animate_model(dt, speed, t)
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
