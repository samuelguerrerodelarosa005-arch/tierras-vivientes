extends RefCounted
## Utilidades compartidas: terreno, materiales, mallas, colisiones, partículas y tema de la interfaz.
## Uso: const Util = preload("res://scripts/util.gd")

const RX := 400.0  # las Ruinas Lunares están lejos, en x = 400

static var _mats: Dictionary = {}


static func smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func terrain_h(x: float, z: float) -> float:
	if x > 250.0:
		return 0.0
	var r := sqrt(x * x + z * z)
	var k := smooth(36.0, 60.0, r)
	if k <= 0.0:
		return 0.0
	return k * (sin(x * 0.045) * cos(z * 0.038) * 2.2 + sin(x * 0.013 + z * 0.021) * 3.2 + 1.6)


static func seg_dist(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	var t := clampf(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0.0, 1.0)
	return Vector2(px - ax - dx * t, pz - az - dz * t).length()


static func in_field(x: float, z: float) -> bool:
	return x > -40.0 and x < -24.0 and z > 6.0 and z < 22.0


# ---------- materiales ----------

static func mat(c: Color, emission: Color = Color(0, 0, 0, 0), energy: float = 1.0, unshaded: bool = false, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%s|%.2f" % [c.to_html(), emission.to_html(), energy, unshaded, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = 0.85
	if emission.a > 0.0:
		m.emission_enabled = true
		m.emission = Color(emission.r, emission.g, emission.b)
		m.emission_energy_multiplier = energy
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func hex(s: String) -> Color:
	return Color.html(s)


static func stripe_tex(a: String, b: String) -> ImageTexture:
	var img := Image.create(64, 8, false, Image.FORMAT_RGB8)
	for i in 8:
		img.fill_rect(Rect2i(i * 8, 0, 8, 8), hex(a) if i % 2 == 1 else hex(b))
	return ImageTexture.create_from_image(img)


# ---------- mallas ----------

static func add_mesh(parent: Node, mesh: Mesh, m: Material, pos: Vector3, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, m: Material, pos: Vector3) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return add_mesh(parent, bm, m, pos)


static func cyl(parent: Node, rt: float, rb: float, h: float, m: Material, pos: Vector3, segs: int = 12) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return add_mesh(parent, cm, m, pos)


static func sphere(parent: Node, r: float, m: Material, pos: Vector3, segs: int = 12, rings: int = 6) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = rings
	return add_mesh(parent, sm, m, pos)


static func gem(parent: Node, r: float, m: Material, pos: Vector3) -> MeshInstance3D:
	# octaedro: esfera de 4 segmentos y 2 anillos
	return sphere(parent, r, m, pos, 4, 2)


## Cápsula al estilo three.js: `length` es solo la parte cilíndrica.
static func capsule(parent: Node, r: float, length: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = length + 2.0 * r
	c.radial_segments = 10
	c.rings = 4
	return add_mesh(parent, c, m, pos)


static func torus(parent: Node, r: float, thick: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	t.rings = 32
	t.ring_segments = 8
	return add_mesh(parent, t, m, pos)


static func roof(parent: Node, w: float, d: float, h: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 4
	cm.rings = 1
	var mi := add_mesh(parent, cm, m, pos)
	mi.rotation.y = PI / 4.0
	mi.scale = Vector3(w * 0.74, h, d * 0.74)
	return mi


# ---------- colisiones ----------

static func col_box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)


static func col_cyl(parent: Node, r: float, h: float, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	cs.shape = cy
	sb.add_child(cs)
	parent.add_child(sb)


# ---------- texto 3D y partículas ----------

static func label3d(text: String, size_px: int = 48, color: Color = Color(0.89, 0.94, 0.95), no_depth: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = 0.005
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 12
	l.outline_modulate = Color(0.04, 0.08, 0.12, 0.95)
	l.no_depth_test = no_depth
	l.double_sided = true
	return l


static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 14, speed: float = 2.5, life: float = 0.8, size: float = 0.06, up: float = 0.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, up * 2.0 - 1.5, 0)
	p.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = mat(color, color, 2.0, true)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)


# ---------- tema de la interfaz ----------

static func sbox(bg: Color, border: Color, radius: int = 8, bw: int = 2, margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


static func sel_style() -> StyleBoxFlat:
	return sbox(Color(0.91, 0.71, 0.30, 0.9), Color(0.95, 0.78, 0.4, 1.0))


static func make_theme(font_size: int = 20) -> Theme:
	var th := Theme.new()
	th.default_font_size = font_size
	# Paleta de cuero, hierro pavonado y latón: menos aspecto de HUD futurista.
	var edge := Color(0.58, 0.48, 0.32, 0.62)
	var edge_soft := Color(0.45, 0.39, 0.29, 0.48)
	var panel_bg := Color(0.035, 0.055, 0.065, 0.94)
	var button_bg := Color(0.10, 0.12, 0.12, 0.88)
	var brass := Color(0.78, 0.61, 0.32, 0.95)
	th.set_stylebox("panel", "PanelContainer", sbox(panel_bg, edge, 9, 1, 16.0))
	th.set_stylebox("normal", "Button", sbox(button_bg, edge_soft, 6, 1, 12.0))
	th.set_stylebox("hover", "Button", sbox(Color(0.20, 0.17, 0.11, 0.96), brass, 6, 1, 12.0))
	th.set_stylebox("pressed", "Button", sbox(Color(0.29, 0.22, 0.12, 0.98), brass, 6, 1, 12.0))
	th.set_stylebox("disabled", "Button", sbox(Color(0.08, 0.09, 0.09, 0.65), Color(0.24, 0.23, 0.20, 0.35), 6, 1, 12.0))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.90, 0.87, 0.79))
	th.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.82))
	th.set_color("font_pressed_color", "Button", Color(0.97, 0.86, 0.61))
	th.set_color("font_focus_color", "Button", Color(0.90, 0.87, 0.79))
	th.set_color("font_color", "Label", Color(0.88, 0.86, 0.79))
	th.set_stylebox("normal", "LineEdit", sbox(Color(0.025, 0.035, 0.04, 0.88), edge_soft, 5, 1, 10.0))
	th.set_stylebox("focus", "LineEdit", sbox(Color(0.025, 0.035, 0.04, 0.95), brass, 5, 1, 10.0))
	th.set_stylebox("background", "ProgressBar", sbox(Color(0.015, 0.02, 0.022, 0.82), Color(0, 0, 0, 0), 4, 0, 0.0))
	th.set_stylebox("fill", "ProgressBar", sbox(Color(0.68, 0.31, 0.25), Color(0, 0, 0, 0), 4, 0, 0.0))
	return th
