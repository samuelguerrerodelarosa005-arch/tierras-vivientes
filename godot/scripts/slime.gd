extends Node3D
## Limo: salta por su zona, persigue al jugador cercano y le hace daño al tocarlo.

const Util = preload("res://scripts/util.gd")

var main: Node
var zone: Dictionary
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var vy := 0.0
var hop := 0.0
var hp := 30.0
var alive := true
var hit_t := 0.0
var dmg_t := 0.0
var resp := 0.0
var blob: MeshInstance3D
var blob_mat: StandardMaterial3D
var mark: Label3D


func setup(m: Node, z: Dictionary) -> void:
	main = m
	zone = z
	blob_mat = StandardMaterial3D.new()
	blob_mat.albedo_color = Color(0.44, 0.83, 0.42, 0.85)
	blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_mat.emission_enabled = true
	blob_mat.emission = Color(0.05, 0.23, 0.05)
	blob_mat.roughness = 0.3
	blob = Util.sphere(self, 0.55, blob_mat, Vector3(0, 0.42, 0), 14, 8)
	var eye := Util.mat(Color(0.06, 0.12, 0.06))
	Util.sphere(blob, 0.07, eye, Vector3(-0.17, 0.15, 0.45), 6, 3)
	Util.sphere(blob, 0.07, eye, Vector3(0.17, 0.15, 0.45), 6, 3)
	mark = Util.label3d("◆", 70, Color(1, 0.25, 0.25), true)
	mark.position.y = 1.3
	mark.visible = false
	add_child(mark)
	hop = randf()
	_respawn()


func _respawn() -> void:
	var a := randf() * TAU
	var r := randf() * float(zone.r)
	pos = Vector3(float(zone.x) + cos(a) * r, 0, float(zone.z) + sin(a) * r)
	pos.y = Util.terrain_h(pos.x, pos.z)
	hp = 30.0
	alive = true
	visible = true


func update(dt: float) -> void:
	if not alive:
		resp -= dt
		if resp <= 0.0:
			_respawn()
		return
	var g := Util.terrain_h(pos.x, pos.z)
	var pp: Vector3 = main.player_pos()
	var dx := pp.x - pos.x
	var dz := pp.z - pos.z
	var d := sqrt(dx * dx + dz * dz)
	var grounded := pos.y <= g + 0.001
	if grounded:
		hop -= dt
		vel *= 0.8
		if hop <= 0.0:
			hop = randf_range(0.7, 1.4)
			vy = randf_range(3.5, 5.0)
			var tx := 0.0
			var tz := 0.0
			if d < 13.0 and Game.alive and d > 0.01:
				tx = dx / d
				tz = dz / d
			else:
				var a := randf() * TAU
				tx = cos(a)
				tz = sin(a)
				var zd := Vector2(pos.x - float(zone.x), pos.z - float(zone.z)).length()
				if zd > float(zone.r):
					tx = (float(zone.x) - pos.x) / zd
					tz = (float(zone.z) - pos.z) / zd
			vel = Vector3(tx * 2.6, 0, tz * 2.6)
	vy -= 16.0 * dt
	pos.x += vel.x * dt
	pos.z += vel.z * dt
	pos.y += vy * dt
	if pos.y < g:
		pos.y = g
		vy = 0.0
	position = pos
	var sq := 1.0 + sin(hop * 8.0) * 0.05 if grounded else 1.0
	blob.scale = Vector3(1.05 / sq, 0.72 * sq * (1.0 if grounded else 1.15), 1.05 / sq)
	if vel.length() > 0.05:
		rotation.y = atan2(vel.x, vel.z)
	if hit_t > 0.0:
		hit_t -= dt
		blob_mat.emission = Color(1, 1, 1)
	else:
		blob_mat.emission = Color(0.05, 0.23, 0.05)
	mark.visible = Game.has_job("rastreador") and d < (45.0 if Game.cls == "rastreador" else 25.0)
	dmg_t -= dt
	if d < 1.05 and absf(pp.y - pos.y) < 1.2 and dmg_t <= 0.0 and Game.alive:
		dmg_t = 1.0
		main.hurt_player(9.0)


func damage(amount: float) -> void:
	hp -= amount
	hit_t = 0.12
	Sfx.play("squish")
	if hp <= 0.0:
		alive = false
		visible = false
		resp = 90.0
		Util.burst(main, global_position + Vector3(0, 0.4, 0), Color(0.49, 1.0, 0.44), 22, 3.0, 0.9, 0.07)
		main.on_slime_killed(self)
