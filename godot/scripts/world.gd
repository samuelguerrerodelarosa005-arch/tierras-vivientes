extends Node3D
## Construye Valdeluz con primitivas: terreno con colisión, plaza, panadería, forja, taberna,
## granja, Santuario, puesto del jugador, rocas de hierro, portal, bosque y Ruinas Lunares.
## Para cambiar el arte, sustituye estas primitivas por modelos .glb en las mismas posiciones.

const Util = preload("res://scripts/util.gd")

const PATHS := [
	[0, 0, -14, -8], [0, 0, 14, -8], [0, 0, 13, 8], [0, 0, -15, 9], [0, 0, 0, -18], [0, 0, -5, 9],
	[4, 4, 25, 28], [6, -4, 40, -17], [6, 0, 52, 4], [-8, 6, -23, 12],
]

var win_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var anvil_top := Vector3(14.6, 0.78, -9.8)
var forge_light: OmniLight3D
var water: MeshInstance3D
var sheaves: Array = []   # [{"node": Node3D, "t": float}]
var apples: Array = []    # [{"node": MeshInstance3D, "t": float}]
var ores: Array = []      # [{"node": Node3D, "specks": Node3D, "id": String, "t": float}]
var portal_pos := Vector3.ZERO
var portal_mat: ShaderMaterial
var ruins_portal := Vector3(Util.RX, 0, 14)
var moon_crystal: MeshInstance3D
var sanct_crystal: MeshInstance3D
var anvil_ring: MeshInstance3D

const PORTAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float on = 1.0;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float sw = sin(a * 5.0 + r * 12.0 - TIME * 3.0) * 0.5 + 0.5;
	ALBEDO = mix(vec3(0.25, 0.12, 0.6), vec3(0.45, 0.95, 1.0), sw * (1.0 - r * 0.7));
	ALPHA = smoothstep(1.0, 0.8, r) * on * (0.55 + 0.45 * sw);
}
"""


func build() -> void:
	win_mat = StandardMaterial3D.new()
	win_mat.albedo_color = Color(0.16, 0.14, 0.09)
	win_mat.emission_enabled = true
	win_mat.emission = Color(1.0, 0.7, 0.28)
	win_mat.emission_energy_multiplier = 0.0
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.95, 0.75)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.78, 0.38)
	lamp_mat.emission_energy_multiplier = 0.0
	_terrain()
	_plaza()
	_bakery()
	_forge()
	_tavern()
	_farm()
	_sanctuary()
	_stall()
	_house(24, -4, 5, 5, 2.8, "#b9b2a6", "#4c5560", "-x")  # casa de Dorran
	_apple_tree()
	_ores()
	_portal()
	_trees()
	_ruins()


func set_night(night: float) -> void:
	win_mat.emission_energy_multiplier = night * 1.6
	lamp_mat.emission_energy_multiplier = night * 2.0


# ---------- terreno ----------

func _terrain() -> void:
	var n := 150
	var size := 330.0
	var step := size / n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n + 1:
		for ix in n + 1:
			var x := -size * 0.5 + ix * step
			var z := -size * 0.5 + iz * step
			var h := Util.terrain_h(x, z)
			var hx := Util.terrain_h(x + 0.5, z) - Util.terrain_h(x - 0.5, z)
			var hz := Util.terrain_h(x, z + 0.5) - Util.terrain_h(x, z - 0.5)
			st.set_normal(Vector3(-hx, 1.0, -hz).normalized())
			st.set_color(_ground_color(x, z))
			st.add_vertex(Vector3(x, h, z))
	for iz in n:
		for ix in n:
			var a := iz * (n + 1) + ix
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	cs.shape = shape
	sb.add_child(cs)
	add_child(sb)


func _ground_color(x: float, z: float) -> Color:
	var nn := sin(x * 0.31) * sin(z * 0.27) * 0.5 + sin(x * 0.11 + z * 0.07) * 0.5
	# Variación terrosa sutil: verde menos saturado y pequeñas diferencias de suelo.
	var r := 0.29 + nn * 0.055
	var g := 0.40 + nn * 0.065
	var b := 0.22 + nn * 0.035
	var pd := 99.0
	for s in PATHS:
		pd = minf(pd, Util.seg_dist(x, z, s[0], s[1], s[2], s[3]))
	var pm := 1.0 - Util.smooth(1.2, 2.4, pd)
	r = lerpf(r, 0.43, pm); g = lerpf(g, 0.36, pm); b = lerpf(b, 0.27, pm)
	if Util.in_field(x, z):
		r = lerpf(r, 0.66, 0.8); g = lerpf(g, 0.58, 0.8); b = lerpf(b, 0.3, 0.8)
	var rr := sqrt(x * x + z * z)
	if rr > 60.0:
		var k := Util.smooth(60.0, 140.0, rr)
		r = lerpf(r, 0.22, k); g = lerpf(g, 0.31, k); b = lerpf(b, 0.20, k)
	return Color(r, g, b)


# ---------- edificios ----------

func _house(cx: float, cz: float, w: float, d: float, h: float, wall: String, roof_c: String, door: String) -> Node3D:
	# Si hay un modelo GLB de casa, úsalo; si no, conserva la versión procedural.
	# El archivo opcional se documenta en godot/models/README.md.
	var glb_path := "res://models/environment/medieval_house.glb"
	if ResourceLoader.exists(glb_path):
		var packed := load(glb_path) as PackedScene
		if packed:
			var model_root := Node3D.new()
			model_root.name = "HouseModel"
			model_root.position = Vector3(cx, 0, cz)
			add_child(model_root)
			var model := packed.instantiate()
			model.name = "ImportedMedievalHouse"
			model_root.add_child(model)
			# Ajusta esta escala una vez al modelo elegido; el tamaño de referencia es ~8 m.
			model.scale = Vector3.ONE * clampf(maxf(w, d) / 8.0, 0.45, 1.8)
			if door == "-x":
				model.rotation.y = PI * 0.5
			elif door == "+x":
				model.rotation.y = -PI * 0.5
			Util.col_box(self, Vector3(w, h, d), Vector3(cx, h * 0.5, cz))
			return model_root
	var g := Node3D.new()
	g.position = Vector3(cx, 0, cz)
	add_child(g)
	var wall_m := Util.mat(Util.hex(wall))
	var timber_m := Util.mat(Util.hex("#49372a"))
	var stone_m := Util.mat(Util.hex("#777064"))
	var roof_m := Util.mat(Util.hex(roof_c))
	Util.box(g, Vector3(w, h, d), wall_m, Vector3(0, h * 0.5, 0))
	# Zócalo de piedra y entramado de madera: detalle geométrico barato para Quest.
	Util.box(g, Vector3(w + 0.12, 0.34, d + 0.12), stone_m, Vector3(0, 0.20, 0))
	Util.box(g, Vector3(w + 0.3, 0.25, d + 0.3), timber_m, Vector3(0, 0.12, 0))
	for x in [-w * 0.46, w * 0.46]:
		Util.box(g, Vector3(0.13, h - 0.12, 0.14), timber_m, Vector3(x, h * 0.52, d * 0.5 + 0.025))
		Util.box(g, Vector3(0.13, h - 0.12, 0.14), timber_m, Vector3(x, h * 0.52, -d * 0.5 - 0.025))
	for z in [-d * 0.46, d * 0.46]:
		Util.box(g, Vector3(0.14, h - 0.12, 0.13), timber_m, Vector3(w * 0.5 + 0.025, h * 0.52, z))
		Util.box(g, Vector3(0.14, h - 0.12, 0.13), timber_m, Vector3(-w * 0.5 - 0.025, h * 0.52, z))
	for y in [0.52, h - 0.22]:
		Util.box(g, Vector3(w + 0.08, 0.12, 0.12), timber_m, Vector3(0, y, d * 0.5 + 0.035))
		Util.box(g, Vector3(w + 0.08, 0.12, 0.12), timber_m, Vector3(0, y, -d * 0.5 - 0.035))
	Util.roof(g, w + 0.8, d + 0.8, h * 0.75, roof_m, Vector3(0, h + h * 0.375, 0))
	var dz := d * 0.5 + 0.02 if door == "+z" else (-d * 0.5 - 0.02 if door == "-z" else 0.0)
	var dx := w * 0.5 + 0.02 if door == "+x" else (-w * 0.5 - 0.02 if door == "-x" else 0.0)
	var door_m := Util.mat(Util.hex("#39271b"))
	Util.box(g, Vector3(0.08 if dx != 0.0 else 1.1, 2.0, 0.08 if dz != 0.0 else 1.1), door_m, Vector3(dx, 1.0, dz))
	if dz != 0.0:
		for x in [-w / 3.0, w / 3.0]:
			Util.box(g, Vector3(0.8, 0.7, 0.08), win_mat, Vector3(x, h * 0.6, dz))
			Util.box(g, Vector3(0.88, 0.08, 0.12), timber_m, Vector3(x, h * 0.6 + 0.39, dz))
			Util.box(g, Vector3(0.08, 0.78, 0.12), timber_m, Vector3(x, h * 0.6, dz))
	else:
		for z in [-d / 3.0, d / 3.0]:
			Util.box(g, Vector3(0.08, 0.7, 0.8), win_mat, Vector3(dx, h * 0.6, z))
			Util.box(g, Vector3(0.12, 0.08, 0.88), timber_m, Vector3(dx, h * 0.6 + 0.39, z))
			Util.box(g, Vector3(0.12, 0.78, 0.08), timber_m, Vector3(dx, h * 0.6, z))
	Util.col_box(self, Vector3(w, h, d), Vector3(cx, h * 0.5, cz))
	return g


func _plaza() -> void:
	var stone := Util.mat(Util.hex("#9a978d"))
	var floor_m := Util.cyl(self, 10.0, 10.0, 0.04, Util.mat(Util.hex("#8b8a84")), Vector3(0, 0.02, 0), 48)
	floor_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Util.cyl(self, 2.2, 2.4, 0.6, stone, Vector3(0, 0.3, 0), 24)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.29, 0.64, 0.79, 0.85)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.emission_enabled = true
	wm.emission = Color(0.04, 0.23, 0.33)
	wm.roughness = 0.1
	water = Util.cyl(self, 1.95, 1.95, 0.05, wm, Vector3(0, 0.56, 0), 24)
	Util.cyl(self, 0.25, 0.35, 1.6, stone, Vector3(0, 1.2, 0), 10)
	Util.sphere(self, 0.45, stone, Vector3(0, 2.05, 0))
	Util.col_cyl(self, 2.4, 1.2, Vector3(0, 0.6, 0))
	for i in 6:
		var a := i / 6.0 * TAU + 0.3
		var x := cos(a) * 10.8
		var z := sin(a) * 10.8
		Util.cyl(self, 0.07, 0.09, 2.6, Util.mat(Util.hex("#2d2a26")), Vector3(x, 1.3, z), 6)
		var l := Util.sphere(self, 0.22, lamp_mat, Vector3(x, 2.7, z), 10, 5)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Util.col_cyl(self, 0.15, 2.6, Vector3(x, 1.3, z))


func _bakery() -> void:
	_house(-14, -12, 8, 6, 3.4, "#e6d6b8", "#9c4a2c", "+z")
	Util.box(self, Vector3(3, 1, 1), Util.mat(Util.hex("#7a5634")), Vector3(-14, 0.5, -7.6))
	Util.col_box(self, Vector3(3, 1, 1), Vector3(-14, 0.5, -7.6))
	for i in 4:
		var b := Util.capsule(self, 0.12, 0.22, Util.mat(Util.hex("#c98a43")), Vector3(-15 + i * 0.65, 1.12, -7.6))
		b.rotation.z = PI / 2.0
	var awn := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.6, 0.08, 1.8)
	awn.mesh = bm
	var am := StandardMaterial3D.new()
	am.albedo_texture = Util.stripe_tex("#d8c9a6", "#a8452c")
	awn.material_override = am
	awn.position = Vector3(-14, 2.5, -7.9)
	awn.rotation.x = 0.25
	add_child(awn)
	# almacén detrás de la panadería (misión «¿Acapara Bruno?»)
	Util.box(self, Vector3(1.1, 1.1, 1.1), Util.mat(Util.hex("#6e4c2e")), Vector3(-14, 0.55, -16.2))
	Util.box(self, Vector3(1.4, 0.12, 1.4), Util.mat(Util.hex("#8a7a5a")), Vector3(-14, 1.16, -16.2))
	Util.col_box(self, Vector3(1.1, 1.1, 1.1), Vector3(-14, 0.55, -16.2))


func _forge() -> void:
	var g := Node3D.new()
	g.position = Vector3(14, 0, -11)
	add_child(g)
	for p in [Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(-3, 2.5), Vector2(3, 2.5)]:
		Util.box(g, Vector3(0.3, 3, 0.3), Util.mat(Util.hex("#4b3626")), Vector3(p.x, 1.5, p.y))
		Util.col_box(self, Vector3(0.3, 3, 0.3), Vector3(14 + p.x, 1.5, -11 + p.y))
	Util.roof(g, 7, 6.2, 1.4, Util.mat(Util.hex("#55606a")), Vector3(0, 3.7, 0))
	Util.box(g, Vector3(2.4, 1.8, 1), Util.mat(Util.hex("#5a5048")), Vector3(0, 0.9, -2))
	Util.col_box(self, Vector3(2.4, 1.8, 1), Vector3(14, 0.9, -13))
	var fire := Util.box(g, Vector3(1, 0.6, 0.1), Util.mat(Color(1, 0.48, 0.16), Color(1, 0.48, 0.16), 3.0, true), Vector3(0, 0.7, -1.48))
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Util.cyl(g, 0.3, 0.4, 2.6, Util.mat(Util.hex("#3e3630")), Vector3(0, 2.9, -2), 8)
	var anvil := Node3D.new()
	anvil.position = Vector3(14.6, 0, -9.8)
	add_child(anvil)
	Util.box(anvil, Vector3(0.5, 0.55, 0.4), Util.mat(Util.hex("#3b3936")), Vector3(0, 0.28, 0))
	Util.box(anvil, Vector3(0.9, 0.22, 0.36), Util.mat(Util.hex("#55534f")), Vector3(0, 0.66, 0))
	var horn := Util.cyl(anvil, 0.0, 0.16, 0.4, Util.mat(Util.hex("#55534f")), Vector3(0.62, 0.66, 0), 8)
	horn.rotation.z = -PI / 2.0
	Util.col_box(self, Vector3(0.9, 0.8, 0.5), Vector3(14.6, 0.4, -9.8))
	forge_light = OmniLight3D.new()
	forge_light.light_color = Color(1, 0.54, 0.24)
	forge_light.light_energy = 1.4
	forge_light.omni_range = 10.0
	forge_light.position = Vector3(14, 1.2, -12.2)
	add_child(forge_light)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1, 0.82, 0.48, 0.0)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	anvil_ring = Util.torus(self, 0.16, 0.04, rm, anvil_top + Vector3(0, 0.02, 0))
	anvil_ring.scale.y = 0.2


func _tavern() -> void:
	_house(14, 12, 9, 7, 3.8, "#c9b38f", "#6a3f2a", "-z")
	Util.box(self, Vector3(3, 0.45, 0.8), Util.mat(Util.hex("#6e4c2e")), Vector3(14, 0.45, 7.3))
	Util.col_box(self, Vector3(3, 0.9, 0.8), Vector3(14, 0.45, 7.3))


func _farm() -> void:
	_house(-15, 13, 7, 6, 3, "#e9e0c9", "#7a5a2a", "-z")
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.03
	stalk.bottom_radius = 0.05
	stalk.height = 1.0
	stalk.radial_segments = 4
	stalk.rings = 1
	stalk.material = Util.mat(Util.hex("#d8b54a"))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stalk
	var xforms := []
	var x := -39.0
	while x < -24.5:
		var z := 6.6
		while z < 21.6:
			var sy := randf_range(0.7, 1.15)
			xforms.append(Transform3D(Basis().scaled(Vector3(1, sy, 1)), Vector3(x + randf_range(-0.12, 0.12), 0.5 * sy, z + randf_range(-0.12, 0.12))))
			z += 0.55
		x += 0.55
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	var wood := Util.mat(Util.hex("#6b5134"))
	var fx := -40.0
	while fx <= -24.0:
		Util.box(self, Vector3(0.12, 0.8, 0.12), wood, Vector3(fx, 0.4, 5.8))
		Util.box(self, Vector3(0.12, 0.8, 0.12), wood, Vector3(fx, 0.4, 22.2))
		fx += 2.0
	Util.box(self, Vector3(16, 0.1, 0.08), wood, Vector3(-32, 0.6, 5.8))
	Util.box(self, Vector3(16, 0.1, 0.08), wood, Vector3(-32, 0.6, 22.2))
	for p in [Vector2(-30, 9), Vector2(-35, 12), Vector2(-28, 17), Vector2(-37, 19), Vector2(-32, 15), Vector2(-26, 20), Vector2(-38, 8)]:
		var g := Node3D.new()
		g.position = Vector3(p.x, 0, p.y)
		Util.cyl(g, 0.22, 0.3, 0.9, Util.mat(Util.hex("#e2c35a")), Vector3(0, 0.45, 0), 8)
		var band := Util.torus(g, 0.24, 0.04, Util.mat(Util.hex("#8a6a2a")), Vector3(0, 0.5, 0))
		band.scale.y = 0.6
		add_child(g)
		sheaves.append({"node": g, "t": 0.0})


func _sanctuary() -> void:
	var g := Node3D.new()
	g.position = Vector3(0, 0, -22)
	add_child(g)
	Util.cyl(g, 4, 4.3, 0.4, Util.mat(Util.hex("#a7a49a")), Vector3(0, 0.2, 0), 24)
	for i in 6:
		var a := i / 6.0 * TAU
		var x := cos(a) * 3.3
		var z := sin(a) * 3.3
		Util.cyl(g, 0.22, 0.26, 3.4, Util.mat(Util.hex("#d8d4c8")), Vector3(x, 2, z), 10)
		Util.col_cyl(self, 0.28, 3.4, Vector3(x, 1.7, -22 + z))
	Util.cyl(g, 3.8, 3.8, 0.3, Util.mat(Util.hex("#cfcabc")), Vector3(0, 3.85, 0), 24)
	Util.cyl(g, 0.4, 0.55, 1, Util.mat(Util.hex("#a7a49a")), Vector3(0, 0.9, 0), 8)
	Util.col_cyl(self, 0.6, 1.4, Vector3(0, 0.7, -22))
	sanct_crystal = Util.gem(self, 0.45, Util.mat(Color(0.56, 0.9, 1.0), Color(0.16, 0.66, 0.84), 1.5), Vector3(0, 1.9, -22))


func _stall() -> void:
	Util.box(self, Vector3(2.6, 0.9, 0.9), Util.mat(Util.hex("#7a5634")), Vector3(-5, 0.45, 10))
	Util.col_box(self, Vector3(2.6, 0.9, 0.9), Vector3(-5, 0.45, 10))
	var awn := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3, 0.08, 1.4)
	awn.mesh = bm
	var am := StandardMaterial3D.new()
	am.albedo_texture = Util.stripe_tex("#2f6e8a", "#e9e2d0")
	awn.material_override = am
	awn.position = Vector3(-5, 2.3, 10.2)
	awn.rotation.x = -0.2
	add_child(awn)
	for p in [Vector2(-6.2, 10.5), Vector2(-3.8, 10.5)]:
		Util.box(self, Vector3(0.1, 2.3, 0.1), Util.mat(Util.hex("#4b3626")), Vector3(p.x, 1.15, p.y))
	var tag := Util.label3d("Tu puesto", 48)
	tag.position = Vector3(-5, 2.9, 10.2)
	add_child(tag)


func _apple_tree() -> void:
	var g := Node3D.new()
	g.position = Vector3(6, 0, -14)
	add_child(g)
	Util.cyl(g, 0.22, 0.32, 2.4, Util.mat(Util.hex("#5b3f28")), Vector3(0, 1.2, 0), 8)
	Util.sphere(g, 1.7, Util.mat(Util.hex("#3f7a3a")), Vector3(0, 3.2, 0), 12, 8)
	Util.col_cyl(self, 0.4, 2.4, Vector3(6, 1.2, -14))
	for i in 5:
		var a := i / 5.0 * TAU
		var m := Util.sphere(g, 0.13, Util.mat(Util.hex("#c8332b")), Vector3(cos(a) * 1.4, 2.6 + sin(i * 2.0) * 0.4, sin(a) * 1.4), 8, 4)
		apples.append({"node": m, "t": 0.0})


func _ores() -> void:
	var i := 0
	for p in [Vector2(40, -18), Vector2(44, -12), Vector2(37, -24)]:
		var y := Util.terrain_h(p.x, p.y)
		var g := Node3D.new()
		g.position = Vector3(p.x, y, p.y)
		add_child(g)
		Util.sphere(g, 1.3, Util.mat(Util.hex("#6e6a66")), Vector3(0, 0.8, 0), 6, 3)
		var specks := Node3D.new()
		g.add_child(specks)
		for k in 6:
			var s := Util.box(specks, Vector3(0.18, 0.18, 0.18), Util.mat(Color(0.82, 0.48, 0.23), Color(0.35, 0.16, 0.06)), Vector3(cos(k) * 1.15, 0.6 + sin(k * 3.0) * 0.5, sin(k) * 1.15))
			s.rotation = Vector3(k, k * 2.0, 0)
		Util.col_cyl(self, 1.3, 2.0, Vector3(p.x, y + 0.8, p.y))
		ores.append({"node": g, "specks": specks, "id": "ore%d" % i, "t": 0.0})
		i += 1


func _portal_disc(parent: Node3D, pos: Vector3, rot_y: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = PORTAL_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(3.2, 3.2)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = sm
	mi.position = pos
	mi.rotation.y = rot_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return sm


func _portal() -> void:
	portal_pos = Vector3(27, Util.terrain_h(27, 30), 30)
	var g := Node3D.new()
	g.position = portal_pos
	add_child(g)
	for i in 6:
		var a := i / 6.0 * TAU
		var x := cos(a) * 4.4
		var z := sin(a) * 4.4
		var s := Util.box(g, Vector3(0.7, 2.6 + sin(i) * 0.5, 0.5), Util.mat(Util.hex("#6f6b75")), Vector3(x, 1.3, z))
		s.rotation.y = -a
		Util.col_cyl(self, 0.45, 3.0, portal_pos + Vector3(x, 1.5, z))
	var ring := Util.torus(g, 1.7, 0.16, Util.mat(Util.hex("#8a86a0"), Color(0.23, 0.16, 0.48), 1.0), Vector3(0, 2, 0))
	ring.rotation = Vector3(PI / 2.0, PI / 4.0, 0)
	portal_mat = _portal_disc(g, Vector3(0, 2, 0), PI / 4.0)


func _trees() -> void:
	var pts := []
	var guard := 0
	while pts.size() < 170 and guard < 4000:
		guard += 1
		var a := randf() * TAU
		var r := randf_range(30.0, 150.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if Util.in_field(x, z) or Vector2(x - portal_pos.x, z - portal_pos.z).length() < 9.0 or Vector2(x - 52, z - 4).length() < 15.0 \
				or Vector2(x - 40, z - 18).length() < 8.0 or Vector2(x - 40, z + 18).length() < 9.0 \
				or (x > -20.0 and x < 30.0 and z > -28.0 and z < 20.0 and r < 34.0):
			continue
		pts.append(Vector2(x, z))
	# Modelo externo opcional para primeros planos. El bosque lejano sigue usando MultiMesh.
	var tree_path := "res://models/environment/tree_oak.glb"
	var tree_scene: PackedScene
	if ResourceLoader.exists(tree_path):
		tree_scene = load(tree_path) as PackedScene
	if tree_scene:
		var sorted_pts: Array[Vector2] = []
		sorted_pts.assign(pts)
		sorted_pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())
		var near_count := mini(28, sorted_pts.size())
		for i in near_count:
			var p: Vector2 = sorted_pts[i]
			var y := Util.terrain_h(p.x, p.y)
			var instance := tree_scene.instantiate() as Node3D
			if instance:
				instance.name = "ImportedTree_%02d" % i
				instance.position = Vector3(p.x, y, p.y)
				var s := randf_range(0.85, 1.2)
				instance.scale = Vector3.ONE * s
				instance.rotation.y = randf() * TAU
				add_child(instance)
				if p.length() < 90.0:
					Util.col_cyl(self, 0.35 * s, 3.0, Vector3(p.x, y + 1.5 * s, p.y))
		# Evita dibujar también esos puntos con el bosque procedural.
		pts = sorted_pts.slice(near_count)
	var trunk_m := CylinderMesh.new()
	trunk_m.top_radius = 0.18
	trunk_m.bottom_radius = 0.26
	trunk_m.height = 2.2
	trunk_m.radial_segments = 6
	trunk_m.material = Util.mat(Util.hex("#5b3f28"))
	# Tres niveles de copa con verdes distintos: silueta más arbórea sin mallas individuales.
	var foliage_meshes: Array[Mesh] = []
	var foliage_specs := [
		[1.55, 2.15, "#344d30", 2.55],
		[1.28, 2.0, "#3d5a35", 3.25],
		[0.92, 1.75, "#49643b", 3.95],
	]
	for spec in foliage_specs:
		var fm := CylinderMesh.new()
		fm.top_radius = 0.02
		fm.bottom_radius = float(spec[0])
		fm.height = float(spec[1])
		fm.radial_segments = 8
		fm.rings = 1
		fm.material = Util.mat(Util.hex(str(spec[2])))
		foliage_meshes.append(fm)
	var mt := MultiMesh.new()
	mt.transform_format = MultiMesh.TRANSFORM_3D
	mt.mesh = trunk_m
	mt.instance_count = pts.size()
	var foliage_multimeshes: Array[MultiMesh] = []
	for fm in foliage_meshes:
		var fmm := MultiMesh.new()
		fmm.transform_format = MultiMesh.TRANSFORM_3D
		fmm.mesh = fm
		fmm.instance_count = pts.size()
		foliage_multimeshes.append(fmm)
	var col := StaticBody3D.new()
	add_child(col)
	for i in pts.size():
		var p: Vector2 = pts[i]
		var y := Util.terrain_h(p.x, p.y)
		var s := randf_range(0.8, 1.4)
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s))
		mt.set_instance_transform(i, Transform3D(b, Vector3(p.x, y + 1.1 * s, p.y)))
		for layer in foliage_multimeshes.size():
			var spec: Array = foliage_specs[layer]
			var layer_y := y + float(spec[3]) * s
			foliage_multimeshes[layer].set_instance_transform(i, Transform3D(b, Vector3(p.x, layer_y, p.y)))
		if p.length() < 90.0:
			var cs := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = 0.35 * s
			cy.height = 3.0
			cs.shape = cy
			cs.position = Vector3(p.x, y + 1.5, p.y)
			col.add_child(cs)
	var all_multimeshes: Array[MultiMesh] = [mt]
	all_multimeshes.append_array(foliage_multimeshes)
	for m in all_multimeshes:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		add_child(mmi)


func _ruins() -> void:
	var g := Node3D.new()
	g.position = Vector3(Util.RX, 0, 0)
	add_child(g)
	var ground := Util.cyl(g, 48, 48, 0.2, Util.mat(Util.hex("#3c4658")), Vector3(0, -0.1, 0), 48)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Util.col_box(self, Vector3(100, 1, 100), Vector3(Util.RX, -0.5, 0))
	for i in 12:
		var a := i / 12.0 * TAU
		var r := 16.0 + sin(i * 3.0) * 3.0
		var h := randf_range(1.2, 5.0)
		Util.cyl(g, 0.6, 0.7, h, Util.mat(Util.hex("#8c93a6")), Vector3(cos(a) * r, h * 0.5, sin(a) * r), 10)
		Util.col_cyl(self, 0.75, h, Vector3(Util.RX + cos(a) * r, h * 0.5, sin(a) * r))
	for i in 9:
		var a := randf() * TAU
		var r := randf_range(4.0, 13.0)
		var c := Util.gem(g, randf_range(0.4, 0.9), Util.mat(Color(0.62, 0.85, 1.0), Color(0.23, 0.48, 0.84), 1.6), Vector3(cos(a) * r, 0.8, sin(a) * r))
		c.rotation = Vector3(randf(), randf() * 3.0, 0)
	var ring := Util.torus(g, 1.7, 0.16, Util.mat(Util.hex("#8a86a0"), Color(0.23, 0.16, 0.48), 1.2), Vector3(0, 2, 14))
	ring.rotation.x = PI / 2.0
	_portal_disc(g, Vector3(0, 2, 14), 0.0)
	var pl := OmniLight3D.new()
	pl.light_color = Color(0.48, 0.72, 1.0)
	pl.light_energy = 1.2
	pl.omni_range = 30.0
	pl.position = Vector3(0, 4, 0)
	g.add_child(pl)
	moon_crystal = Util.gem(self, 0.5, Util.mat(Color(0.9, 0.96, 1.0), Color(0.63, 0.82, 1.0), 2.0), Vector3(Util.RX + 6, 1.4, -8))
