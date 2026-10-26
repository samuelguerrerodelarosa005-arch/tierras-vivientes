extends SceneTree
## Herramienta: alinea modelos junto a una persona de referencia (1,75 m) y guarda una captura.
## godot --path . -s tools/preview_models.gd -- <carpeta_salida> [grupo]

func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D:
		var a: AABB = t * (n as VisualInstance3D).get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_aabb(c, t, acc)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var group: String = args[1] if args.size() > 1 else "village"
	var filt: String = args[2] if args.size() > 2 else ""
	var sc: float = float(args[3]) if args.size() > 3 else 1.0
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var files := []
	var dir := "res://models/" + group
	for f in DirAccess.get_files_at(dir):
		if (f.ends_with(".gltf") or f.ends_with(".glb")) and (filt == "" or filt in f):
			files.append(dir + "/" + f)
	var x := 0.0
	for f in files:
		var ps := load(f) as PackedScene
		if ps == null:
			print("NO CARGA ", f); continue
		var inst := ps.instantiate()
		root.add_child(inst)
		(inst as Node3D).scale = Vector3.ONE * sc
		var acc := [null]
		_aabb(inst, Transform3D.IDENTITY, acc)
		var a: AABB = acc[0]
		print("%-40s size=%s pos=%s" % [f.get_file(), str(a.size.snapped(Vector3.ONE * 0.01)), str(a.position.snapped(Vector3.ONE * 0.01))])
		(inst as Node3D).position = Vector3(x - a.position.x, 0, 0)
		print("   scaled size ", a.size.snapped(Vector3.ONE * 0.01))
		var lab := Label3D.new()
		lab.text = f.get_file().get_basename().replace("building_", "")
		lab.font_size = 40
		lab.pixel_size = 0.004
		lab.position = Vector3(x + a.size.x * 0.5, a.end.y + 0.25, 0)
		root.add_child(lab)
		x += a.size.x + 0.4
	var ref := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.2; cm.height = 1.75
	ref.mesh = cm
	ref.position = Vector3(-0.6, 0.875, 0)
	root.add_child(ref)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(x * 0.5, x * 0.12 + 1.5, x * 0.45 + 3.0)
	cam.look_at(Vector3(x * 0.5, x * 0.04, 0))
	cam.current = true
	for i in 12:
		await process_frame
	get_root().get_texture().get_image().save_png(out)
	print("PREVIEW OK")
	quit()
