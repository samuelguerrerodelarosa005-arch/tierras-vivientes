extends Node3D
## Panel de interfaz flotante para VR: dibuja un Control dentro de un SubViewport sobre un
## plano 3D y le pasa los clics del rayo de la mano o del mando como eventos de ratón.

const Util = preload("res://scripts/util.gd")

var vp: SubViewport
var quad: MeshInstance3D
var cursor: MeshInstance3D
var size_px := Vector2i(1024, 700)
var width_m := 1.0
var hover_px := Vector2(-100, -100)
var is_pressed := false
var interactive := true


func setup(content: Control, px: Vector2i, w_m: float) -> void:
	size_px = px
	width_m = w_m
	vp = SubViewport.new()
	vp.size = px
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_embed_subwindows = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	content.position = Vector2.ZERO
	content.size = Vector2(px)
	content.custom_minimum_size = Vector2(px)
	vp.add_child(content)
	quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w_m, height_m())
	quad.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10
	m.albedo_texture = vp.get_texture()
	quad.material_override = m
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	cursor = Util.sphere(self, 0.008, Util.mat(Color(1, 1, 1), Color(1, 1, 1), 1.0, true), Vector3.ZERO, 8, 4)
	var cm := cursor.material_override as StandardMaterial3D
	cm.no_depth_test = true
	cm.render_priority = 11
	cursor.visible = false


func height_m() -> float:
	return width_m * float(size_px.y) / float(size_px.x)


## Coloca el panel delante de la cámara, mirando hacia ella.
func place_in_front(cam: Node3D, dist: float = 1.05, drop: float = 0.12) -> void:
	var fw := -cam.global_transform.basis.z
	fw.y = 0.0
	if fw.length() < 0.01:
		fw = Vector3(0, 0, -1)
	fw = fw.normalized()
	var cp := cam.global_position
	var p := cp + fw * dist
	p.y = cp.y - drop
	face_from(p, Vector3(cp.x, p.y, cp.z))


func face_from(p: Vector3, look_target: Vector3) -> void:
	global_position = p
	if p.distance_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP, true)


## Intersección del rayo con el panel. Devuelve {} si no toca.
func ray_hit(o: Vector3, d: Vector3) -> Dictionary:
	if not visible or not interactive or not is_inside_tree():
		return {}
	var inv := global_transform.affine_inverse()
	var lo := inv * o
	var ld := inv.basis * d
	if absf(ld.z) < 0.00001:
		return {}
	var t := -lo.z / ld.z
	if t <= 0.0:
		return {}
	var hit := lo + ld * t
	var w := width_m
	var h := height_m()
	if absf(hit.x) > w * 0.5 or absf(hit.y) > h * 0.5:
		return {}
	var uv := Vector2(hit.x / w + 0.5, 0.5 - hit.y / h)
	return {"host": self, "dist": t, "px": uv * Vector2(size_px), "point": o + d * t}


func pointer_move(px: Vector2) -> void:
	hover_px = px
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	if is_pressed:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(ev, true)
	cursor.visible = true
	cursor.position = Vector3((px.x / size_px.x - 0.5) * width_m, (0.5 - px.y / size_px.y) * height_m(), 0.003)


func press(down: bool) -> void:
	is_pressed = down
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = hover_px
	ev.global_position = hover_px
	if down:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(ev, true)


func pointer_exit() -> void:
	if is_pressed:
		press(false)
	pointer_move(Vector2(-100, -100))
	cursor.visible = false
