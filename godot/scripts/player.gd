extends CharacterBody3D
## Jugador en primera persona.
## PC: ratón + teclado, con brazos visibles.
## VR (OpenXR, Quest 3/3S): mandos o hand tracking. Pellizco = gatillo; puño = agarre.
##   Mano derecha: apuntar y usar; pellizcar el suelo y soltar = moverse (con manos).
##   Mano izquierda: pellizco/gatillo = canalizar hechizo, soltar mientras lanzas la mano.
##   Stick izquierdo = moverse, stick derecho = giro por pasos, A = saltar, X = cambiar hechizo.

const Util = preload("res://scripts/util.gd")

const GRAV := 18.0
const JUMP_V := 6.2
const SIDES := ["left", "right"]

var main: Node
var xr := false
var origin: XROrigin3D
var camera: XRCamera3D
var ctrl := {}       # side -> XRController3D
var palm := {}       # side -> Node3D que sigue la palma (manos)
var joints := {}     # side -> Array de esferas de las articulaciones
var glove := {}      # side -> guante para los mandos
var pads := {}       # side -> estado de entrada de este frame
var yaw := 0.0
var pitch := -0.05
var move_speed := 0.0
var grounded := true
var snap_latch := false
var turn_flash := 0.0
var head_vy := 0.0
var prev_head_y := 0.0
var seat_offset := 0.45
var vignette_mat: ShaderMaterial
var ray_root: Node3D
var ray_dot: MeshInstance3D
var tp_ring: MeshInstance3D
var tp_target = null
var tp_active := false
var channel: Dictionary = {}
var charge_orb: MeshInstance3D
var hover_host: Node = null
var press_host: Node = null
var target: Dictionary = {}
# brazos en PC
var fp: Node3D
var arm_l: Node3D
var arm_r: Node3D
var cast_anim := 0.0
var hit_anim := 0.0
var bob := 0.0

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix;
uniform float opacity = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(0.35, 0.9, r) * opacity;
}
"""


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	origin = XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	camera.near = 0.05
	camera.far = 700.0
	camera.fov = 72.0
	origin.add_child(camera)
	for side in SIDES:
		var c := XRController3D.new()
		c.tracker = &"left_hand" if side == "left" else &"right_hand"
		c.pose = &"aim"
		origin.add_child(c)
		ctrl[side] = c
		var p := Node3D.new()
		origin.add_child(p)
		palm[side] = p
		pads[side] = {"hand": false, "trig": false, "grip": false, "stick": Vector2.ZERO, "a": false, "b": false,
			"trig_down": false, "trig_up": false, "a_down": false, "b_down": false, "vel": Vector3.ZERO, "pp": Vector3.ZERO}


func setup(xr_on: bool) -> void:
	xr = xr_on
	var skin := _skin_mat()
	for side in SIDES:
		var jr := Node3D.new()
		origin.add_child(jr)
		var arr := []
		for j in XRHandTracker.HAND_JOINT_MAX:
			var m := Util.sphere(jr, 1.0, skin, Vector3.ZERO, 6, 3)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.visible = false
			arr.append(m)
		joints[side] = arr
		glove[side] = _make_glove(skin)
		ctrl[side].add_child(glove[side])
		ctrl[side].visible = xr
	if xr:
		_build_xr_helpers()
	else:
		camera.position = Vector3(0, eye_height(), 0)
		_build_fp_arms()


func eye_height() -> float:
	return float(Game.look.height) * 0.93


func _skin_mat() -> StandardMaterial3D:
	return Util.mat(Color.html(str(Game.look.skin)))


## Vuelve a pintar manos y brazos con el aspecto elegido en el creador.
func refresh_look() -> void:
	var skin := _skin_mat()
	for side in SIDES:
		if joints.has(side):
			for m in joints[side]:
				m.material_override = skin
		if glove.has(side) and is_instance_valid(glove[side]):
			glove[side].queue_free()
			glove[side] = _make_glove(skin)
			ctrl[side].add_child(glove[side])
	if not xr:
		camera.position.y = eye_height()
		_build_fp_arms()


func _make_glove(skin: Material) -> Node3D:
	var g := Node3D.new()
	Util.box(g, Vector3(0.075, 0.025, 0.09), skin, Vector3(0, 0, 0.02))
	for i in 4:
		Util.box(g, Vector3(0.016, 0.018, 0.06), skin, Vector3(-0.027 + i * 0.018, 0, -0.045))
	var th := Util.box(g, Vector3(0.018, 0.018, 0.05), skin, Vector3(0.045, 0, 0.005))
	th.rotation.y = -0.6
	for c in g.get_children():
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


func _build_xr_helpers() -> void:
	# viñeta de confort pegada a la cámara
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.4)
	var vm := MeshInstance3D.new()
	vm.mesh = q
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = sh
	vignette_mat.render_priority = 100
	vm.material_override = vignette_mat
	vm.position = Vector3(0, 0, -0.3)
	vm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(vm)
	# rayo de la mano derecha
	ray_root = Node3D.new()
	main.add_child(ray_root)
	var rm := Util.mat(Color(0.62, 0.88, 1.0), Color(0.62, 0.88, 1.0), 1.0, true, 0.6)
	var line := Util.box(ray_root, Vector3(0.004, 0.004, 1.0), rm, Vector3(0, 0, -0.5))
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ray_dot = Util.sphere(main, 0.015, Util.mat(Color(1, 1, 1), Color(1, 1, 1), 1.0, true), Vector3.ZERO, 8, 4)
	ray_dot.visible = false
	# anillo de teletransporte
	var tm := Util.mat(Color(0.42, 0.79, 0.9), Color(0.42, 0.79, 0.9), 1.0, true, 0.85)
	tp_ring = Util.torus(main, 0.28, 0.04, tm, Vector3.ZERO)
	tp_ring.scale.y = 0.2
	tp_ring.visible = false
	# orbe de hechizo
	charge_orb = Util.sphere(self, 0.06, Util.mat(Color(1, 0.6, 0.2), Color(1, 0.6, 0.2), 3.0, true, 0.85).duplicate(), Vector3.ZERO, 10, 5)
	charge_orb.visible = false


# ---------- brazos en primera persona (PC) ----------

func _build_fp_arms() -> void:
	if fp:
		fp.queue_free()
	fp = Node3D.new()
	camera.add_child(fp)
	arm_l = _arm(-1.0)
	arm_r = _arm(1.0)


func _arm(side: float) -> Node3D:
	var a := Node3D.new()
	fp.add_child(a)
	var outfit := Util.mat(Color.html(str(Game.look.outfit)))
	var skin := _skin_mat()
	var sl := Util.capsule(a, 0.048, 0.36, outfit, Vector3(0, 0, 0.14))
	sl.rotation.x = PI / 2.0
	var cuff := Util.cyl(a, 0.056, 0.056, 0.045, Util.mat(Color.html(str(Game.look.outfit)).darkened(0.45)), Vector3(0, 0, -0.05))
	cuff.rotation.x = PI / 2.0
	var hand := Node3D.new()
	hand.position = Vector3(0, 0, -0.11)
	hand.rotation.z = -side * 1.15
	hand.scale = Vector3.ONE * 0.85
	a.add_child(hand)
	Util.box(hand, Vector3(0.085, 0.03, 0.1), skin, Vector3.ZERO)
	for i in 4:
		var f := Util.box(hand, Vector3(0.019, 0.02, 0.07), skin, Vector3(-0.03 + i * 0.02, -0.004, -0.08))
		f.rotation.x = 0.25
	var th := Util.box(hand, Vector3(0.02, 0.02, 0.055), skin, Vector3(side * -0.052, -0.004, -0.012))
	th.rotation.y = side * 0.6
	for c in [sl, cuff]:
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.position = Vector3(side * 0.24, -0.3, -0.38)
	a.rotation.y = -side * 0.12
	return a


func update_fp_arms(dt: float) -> void:
	if fp == null:
		return
	fp.visible = Game.started and Game.alive
	bob += dt * move_speed * 2.1
	var bx := sin(bob) * 0.012
	var by := -absf(cos(bob)) * 0.012
	var r := Vector3(0.24, -0.3, -0.38)
	var l := Vector3(-0.24, -0.3, -0.38)
	var r_rot := 0.0
	if cast_anim > 0.0:
		cast_anim -= dt
		var k := sin(clampf(1.0 - cast_anim / 0.35, 0.0, 1.0) * PI)
		r += Vector3(-0.06 * k, 0.1 * k, -0.18 * k)
	if Game.shield_t > 0.0:
		l = Vector3(-0.24, -0.18, -0.42)
	if main.forge.active:
		r = Vector3(0.24, -0.14, -0.42)
		if hit_anim > 0.0:
			hit_anim -= dt
			var k2 := sin(clampf(1.0 - hit_anim / 0.3, 0.0, 1.0) * PI)
			r.y -= 0.14 * k2
			r_rot = -0.9 * k2
	var held = main.eat.held
	if is_instance_valid(held) and held.get_parent() == camera:
		arm_r.position = held.position + Vector3(-0.01, -0.04, 0.14)
	else:
		arm_r.position = r + Vector3(bx, by, 0)
	arm_r.rotation.x = r_rot
	arm_l.position = l + Vector3(bx, by, 0)


# ---------- física ----------

func _physics_process(delta: float) -> void:
	if not Game.started:
		return
	if xr:
		_xr_physics(delta)
	else:
		_desktop_physics(delta)
	if global_position.y < -30.0:
		main.teleport_to(main.RESPAWN)


func _desktop_physics(delta: float) -> void:
	var input := Vector2.ZERO
	if main.can_move():
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var run := Input.is_action_pressed("run") and Game.st > 1.0 and input.length() > 0.1
	var sp := 6.2 if run else 3.6
	if run:
		Game.st -= 10.0 * delta
	rotation.y = yaw
	camera.rotation.x = pitch
	var dir := transform.basis * Vector3(input.x, 0, input.y)
	velocity.x = dir.x * sp
	velocity.z = dir.z * sp
	move_speed = input.length() * sp
	velocity.y -= GRAV * delta
	move_and_slide()
	grounded = is_on_floor()
	if grounded and velocity.y < 0.0:
		velocity.y = -0.5


func _xr_physics(delta: float) -> void:
	# 1) el cuerpo sigue a la cabeza (escala de habitación) sin atravesar paredes
	var cam := camera.global_position
	var want := Vector3(cam.x - global_position.x, 0, cam.z - global_position.z)
	if want.length() > 0.002:
		var before := global_position
		var saved := velocity
		velocity = want / delta
		velocity.y = 0.0
		move_and_slide()
		velocity = saved
		var moved := global_position - before
		moved.y = 0.0
		origin.position -= moved
		var blocked := want - moved
		if blocked.length() > 0.02:
			origin.position -= blocked
	# 2) stick izquierdo + gravedad
	var stick: Vector2 = pads.left.stick if channel.is_empty() else Vector2.ZERO
	var fw := -camera.global_transform.basis.z
	fw.y = 0.0
	fw = fw.normalized() if fw.length() > 0.01 else Vector3(0, 0, -1)
	var rt := Vector3(-fw.z, 0, fw.x)
	var mv := fw * stick.y + rt * stick.x
	var ml := mv.length()
	var run := ml > 0.95 and Game.st > 1.0
	var sp := (4.6 if run else 2.9) * (0.0 if main.dialogue.npc else 1.0)
	if ml < 0.15:
		mv = Vector3.ZERO
	if run:
		Game.st -= 8.0 * delta
	velocity.x = mv.x * sp
	velocity.z = mv.z * sp
	velocity.y -= GRAV * delta
	move_and_slide()
	grounded = is_on_floor()
	if grounded and velocity.y < 0.0:
		velocity.y = -0.5
	origin.position.y = seat_offset if Game.seated else 0.0
	if vignette_mat:
		var op := (0.55 if ml > 0.15 else 0.0) + turn_flash
		vignette_mat.set_shader_parameter("opacity", clampf(op, 0.0, 0.75) if bool(Game.settings.vignette) else 0.0)


func jump() -> void:
	if grounded and Game.st >= 8.0 and Game.alive:
		velocity.y = JUMP_V
		grounded = false
		Game.st -= 8.0
		Sfx.play("jump")


func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO


func snap_turn(sgn: float) -> void:
	var ang := sgn * float(Game.settings.snap) * PI / 180.0
	var before := camera.global_position
	origin.rotate_y(ang)
	var after := camera.global_position
	origin.global_position += Vector3(before.x - after.x, 0, before.z - after.z)
	turn_flash = 0.6


func toggle_seated() -> void:
	Game.seated = not Game.seated
	if Game.seated and xr:
		seat_offset = clampf(1.62 - camera.position.y, 0.0, 0.95)


# ---------- manos (OpenXR) ----------

func _tracker(side: String) -> XRHandTracker:
	var t := XRServer.get_tracker(&"/user/hand_tracker/left" if side == "left" else &"/user/hand_tracker/right")
	return t as XRHandTracker


func _is_hand(side: String) -> bool:
	var ht := _tracker(side)
	if ht == null or not ht.has_tracking_data:
		return false
	if ht.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED:
		return true
	return ht.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN and not ctrl[side].get_has_tracking_data()


func _joint_local(ht: XRHandTracker, j: int) -> Vector3:
	return ht.get_hand_joint_transform(j).origin


func _joint_world(ht: XRHandTracker, j: int) -> Vector3:
	return origin.global_transform * _joint_local(ht, j)


func _update_hands() -> void:
	for side in SIDES:
		var hand: bool = pads[side].hand
		var arr: Array = joints[side]
		glove[side].visible = not hand
		if not hand:
			for m in arr:
				m.visible = false
			continue
		var ht := _tracker(side)
		for j in XRHandTracker.HAND_JOINT_MAX:
			var m: MeshInstance3D = arr[j]
			var flags := int(ht.get_hand_joint_flags(j))
			if flags & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID:
				m.visible = true
				m.transform = ht.get_hand_joint_transform(j)
				m.scale = Vector3.ONE * maxf(0.006, ht.get_hand_joint_radius(j) * 0.95)
			else:
				m.visible = false
		palm[side].transform = ht.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)


## El nombre de la pose depende del mapa de acciones («aim» o «aim_pose»): usa el que exista.
func _fix_pose(c: XRController3D) -> void:
	var tr := XRServer.get_tracker(c.tracker) as XRPositionalTracker
	if tr == null or tr.has_pose(c.pose):
		return
	for cand in [&"aim", &"aim_pose", &"default", &"default_pose", &"grip", &"grip_pose"]:
		if tr.has_pose(cand):
			c.pose = cand
			return


## Nodo donde se sujetan objetos: el mando o la palma de la mano.
func holder(side: String) -> Node3D:
	return palm[side] if pads[side].hand else ctrl[side]


func _read_pad(side: String, delta: float) -> void:
	var p: Dictionary = pads[side]
	var prev_t: bool = p.trig
	var prev_a: bool = p.a
	var prev_b: bool = p.b
	var was_hand: bool = p.hand
	p.hand = _is_hand(side)
	if p.hand:
		var ht := _tracker(side)
		var pinch := _joint_local(ht, XRHandTracker.HAND_JOINT_THUMB_TIP).distance_to(_joint_local(ht, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP))
		var wr := _joint_local(ht, XRHandTracker.HAND_JOINT_WRIST)
		var fist := 0.0
		for j in [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
			fist += _joint_local(ht, j).distance_to(wr)
		fist /= 3.0
		p.grip = fist < (0.11 if p.grip else 0.085)
		p.trig = (not p.grip) and (pinch < (0.04 if prev_t else 0.02))
		p.stick = Vector2.ZERO
		p.a = false
		p.b = false
	else:
		var c: XRController3D = ctrl[side]
		_fix_pose(c)
		p.trig = c.get_float("trigger") > 0.6 or c.is_button_pressed("trigger_click")
		p.grip = c.get_float("grip") > 0.6
		p.stick = c.get_vector2("primary")
		p.a = c.is_button_pressed("ax_button")
		p.b = c.is_button_pressed("by_button")
	p.trig_down = p.trig and not prev_t
	p.trig_up = prev_t and not p.trig
	p.a_down = p.a and not prev_a
	p.b_down = p.b and not prev_b
	if was_hand != p.hand:
		main.reattach_held()
		if xr:
			main.vr_toast("Manos detectadas: pellizca para usar; pellizca el suelo y suelta para moverte." if p.hand else "Mandos detectados.")
	var hd := holder(side)
	var pos := hd.global_position
	var v: Vector3 = (pos - p.pp) / maxf(delta, 0.001)
	p.vel = p.vel.lerp(v, 0.5)
	p.pp = pos


## Rayo para apuntar: [origen, dirección].
func ray(side: String) -> Array:
	var c: XRController3D = ctrl[side]
	if not pads[side].hand or c.get_has_tracking_data():
		return [c.global_position, -c.global_transform.basis.z]
	var ht := _tracker(side)
	var o := _joint_world(ht, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL)
	var d := (_joint_world(ht, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) - _joint_world(ht, XRHandTracker.HAND_JOINT_WRIST))
	return [o, d.normalized() if d.length() > 0.001 else -camera.global_transform.basis.z]


# ---------- bucle VR (lo llama main en _process) ----------

func xr_frame(delta: float) -> void:
	for side in SIDES:
		_read_pad(side, delta)
	_update_hands()
	turn_flash = maxf(0.0, turn_flash - delta * 4.0)
	var L: Dictionary = pads.left
	var R: Dictionary = pads.right
	# giro por pasos (mandos)
	if not R.hand:
		if absf(R.stick.x) > 0.7 and not snap_latch:
			snap_latch = true
			snap_turn(-signf(R.stick.x))
		if absf(R.stick.x) < 0.3:
			snap_latch = false
	# salto: A, o salto real de pie
	var hy := camera.position.y
	head_vy = lerpf(head_vy, (hy - prev_head_y) / maxf(delta, 0.001), 0.5)
	prev_head_y = hy
	if R.a_down:
		jump()
	elif not Game.seated and head_vy > 1.3 and grounded and main.dialogue.npc == null:
		jump()
	# hechizos con la mano izquierda
	if L.a_down:
		main.cycle_spell()
	var busy: bool = main.dialogue.npc != null or main.forge.active
	if L.trig_down and not busy and not main.ui.wrist_visible():
		channel = {"t": 0.0}
		charge_orb.visible = true
	if not channel.is_empty():
		channel.t += delta
		var hp := holder("left").global_position
		charge_orb.global_position = hp + Vector3(0, 0.05, 0)
		var col: Color = Game.SPELLS[Game.spell].color
		(charge_orb.material_override as StandardMaterial3D).albedo_color = col
		charge_orb.scale = Vector3.ONE * (1.0 + minf(channel.t, 1.2) * 1.2)
		if L.trig_up:
			var spd: float = L.vel.length()
			var pw := 0.85 + minf(channel.t, 1.0) * 0.15
			if spd > 2.4:
				pw *= 1.1
			if channel.t > 0.15:
				cast_from_left(pw)
			channel = {}
			charge_orb.visible = false
	# panel de la muñeca
	main.ui.update_wrist(holder("left"), camera, not channel.is_empty())
	# apuntar con la derecha
	_pointer(R)
	if R.b_down and main.dialogue.npc:
		main.dialogue.close()


func cast_from_left(power: float) -> void:
	var L: Dictionary = pads.left
	var o: Vector3 = holder("left").global_position
	var d: Vector3
	if L.vel.length() > 1.1:
		d = L.vel.normalized()
	else:
		d = ray("left")[1]
	main.cast_spell(Game.spell, o + d * 0.15, d, power)


func _pointer(R: Dictionary) -> void:
	var rd := ray("right")
	var o: Vector3 = rd[0]
	var d: Vector3 = rd[1]
	var hit: Dictionary = main.panel_hit(o, d)
	if hover_host and (hit.is_empty() or hit.host != hover_host):
		hover_host.pointer_exit()
		hover_host = null
	target = {}
	var length := 6.0
	if not hit.is_empty():
		hover_host = hit.host
		hover_host.pointer_move(hit.px)
		length = hit.dist
		ray_dot.visible = true
		ray_dot.global_position = hit.point
	else:
		ray_dot.visible = false
		if not tp_active:
			target = main.pick_interactable(o, d)
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	ray_root.global_transform = Transform3D(Basis.looking_at(d, up), o)
	ray_root.scale = Vector3(1, 1, maxf(length, 0.05))
	main.show_target(target)
	if R.trig_down:
		if hover_host:
			hover_host.press(true)
			press_host = hover_host
			main.buzz("right", 0.5, 0.03)
		elif main.forge.active:
			main.forge_trigger()
		elif not target.is_empty() and main.dialogue.npc == null:
			target.act.call()
			main.buzz("right", 0.4, 0.03)
		elif R.hand and main.dialogue.npc == null and main.eat.held == null:
			tp_active = true
	if R.trig_up:
		if press_host and is_instance_valid(press_host):
			press_host.press(false)
		press_host = null
		if tp_active:
			if tp_target != null:
				main.teleport_to(tp_target)
				turn_flash = 0.7
				Sfx.play("jump")
			tp_active = false
			tp_target = null
			tp_ring.visible = false
	if tp_active:
		tp_target = null
		tp_ring.visible = false
		if d.y < -0.05:
			var gy := global_position.y
			var k := (gy - o.y) / d.y
			var pt := o + d * k
			if Vector2(pt.x - global_position.x, pt.z - global_position.z).length() < 9.0:
				pt.y = 0.0 if pt.x > 250.0 else Util.terrain_h(pt.x, pt.z)
				tp_target = pt
				tp_ring.visible = true
				tp_ring.global_position = pt + Vector3(0, 0.03, 0)
