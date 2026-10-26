extends SceneTree
## Herramienta: añade al mapa de acciones los mandos de PC VR (Index, Vive, WMR) que el mapa
## por defecto de Godot 4.8 solo cubre con el perfil genérico. Uso:
## godot --headless --path . -s tools/add_pcvr_profiles.gd

const PROFILES := {
	"/interaction_profiles/valve/index_controller": {
		"aim_pose": "input/aim/pose", "grip_pose": "input/grip/pose",
		"trigger": "input/trigger/value", "trigger_click": "input/trigger/click", "trigger_touch": "input/trigger/touch",
		"grip": "input/squeeze/value", "grip_force": "input/squeeze/force",
		"primary": "input/thumbstick", "primary_click": "input/thumbstick/click", "primary_touch": "input/thumbstick/touch",
		"secondary": "input/trackpad", "secondary_touch": "input/trackpad/touch",
		"ax_button": "input/a/click", "ax_touch": "input/a/touch", "by_button": "input/b/click", "by_touch": "input/b/touch",
		"haptic": "output/haptic",
	},
	"/interaction_profiles/htc/vive_controller": {
		"aim_pose": "input/aim/pose", "grip_pose": "input/grip/pose",
		"trigger": "input/trigger/value", "trigger_click": "input/trigger/click",
		"grip_click": "input/squeeze/click",
		"primary": "input/trackpad", "primary_click": "input/trackpad/click", "primary_touch": "input/trackpad/touch",
		"menu_button": "input/menu/click", "ax_button": "input/menu/click",
		"haptic": "output/haptic",
	},
	"/interaction_profiles/microsoft/motion_controller": {
		"aim_pose": "input/aim/pose", "grip_pose": "input/grip/pose",
		"trigger": "input/trigger/value", "grip_click": "input/squeeze/click",
		"primary": "input/thumbstick", "primary_click": "input/thumbstick/click",
		"secondary": "input/trackpad", "secondary_click": "input/trackpad/click", "secondary_touch": "input/trackpad/touch",
		"menu_button": "input/menu/click", "ax_button": "input/menu/click",
		"haptic": "output/haptic",
	},
}


func _initialize() -> void:
	var path := "res://openxr_action_map.tres"
	var map := load(path) as OpenXRActionMap
	var actions := {}
	for s in map.action_sets:
		for a in s.actions:
			actions[a.resource_name] = a
	for prof_path in PROFILES:
		var existing := map.get_interaction_profile_count()
		for i in range(existing - 1, -1, -1):
			if map.get_interaction_profile(i).interaction_profile_path == prof_path:
				map.remove_interaction_profile(map.get_interaction_profile(i))
		var prof := OpenXRInteractionProfile.new()
		prof.interaction_profile_path = prof_path
		var binds := []
		for act_name in PROFILES[prof_path]:
			for hand in ["left", "right"]:
				var b := OpenXRIPBinding.new()
				b.action = actions[act_name]
				b.binding_path = "/user/hand/%s/%s" % [hand, PROFILES[prof_path][act_name]]
				binds.append(b)
		prof.bindings = binds
		map.add_interaction_profile(prof)
		print("perfil ", prof_path, ": ", binds.size(), " enlaces")
	var err := ResourceSaver.save(map, path)
	print("guardado: ", err)
	quit()
