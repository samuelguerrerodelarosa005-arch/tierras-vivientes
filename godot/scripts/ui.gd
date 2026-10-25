extends CanvasLayer
## Interfaz. En PC las ventanas van sobre la pantalla; en VR la misma ventana se dibuja en un
## panel 3D (panel3d.gd) que se pulsa con el rayo de la mano o del mando.

const Util = preload("res://scripts/util.gd")
const Panel3D = preload("res://scripts/panel3d.gd")

const C_TEXT := Color(0.89, 0.94, 0.95)
const C_MUTED := Color(0.58, 0.68, 0.73)
const C_SYS := Color(0.42, 0.79, 0.9)
const C_BRASS := Color(0.91, 0.71, 0.3)
const C_OK := Color(0.49, 0.81, 0.54)
const C_BAD := Color(0.88, 0.38, 0.36)
const SKINS := ["#f1c9a5", "#e0b08a", "#d9a07a", "#b97a52", "#8d5a3b", "#5e3a26"]
const HAIRS := ["#1b1410", "#3a2618", "#8a5a2b", "#d9b36a", "#b23a2a", "#e8e4dc", "#4b6fb5"]
const OUTFITS := ["#3f6e8c", "#7a3b3b", "#4f6b3a", "#6b4f8a", "#b07a32", "#2f3540"]

var main: Node
var xr := false
var th: Theme
var root: Control
var hud: Control
var refs := {}
var windows := {}
var dirty := {}
var menu_tab := "inv"
var menu_mode := "menu"
var toasts_box: VBoxContainer
var toast3d: Node3D
var toast3d_label: Label
var toast3d_t := 0.0
var forge_refs := {}
var wrist_refs := {}
var wrist_t := 0.0
var hurt_rect: ColorRect
var wipe_confirm := false


func setup(xr_on: bool) -> void:
	xr = xr_on
	th = Util.make_theme(20)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = th
	add_child(root)
	hurt_rect = ColorRect.new()
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.color = Color(0.8, 0.1, 0.1, 0.0)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt_rect)
	toasts_box = VBoxContainer.new()
	toasts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts_box.anchor_left = 0.5
	toasts_box.anchor_right = 0.5
	toasts_box.offset_left = -270
	toasts_box.offset_right = 270
	toasts_box.offset_top = 14
	toasts_box.add_theme_constant_override("separation", 6)
	if xr:
		_build_toast3d()
	else:
		_build_hud()
		root.add_child(toasts_box)
	Game.toast.connect(_on_toast)
	Game.changed.connect(func(): mark_all())


# ---------- helpers de construcción ----------

func L(text: String, size: int = 20, color: Color = C_TEXT, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func B(text: String, cb: Callable, selected: bool = false, min_h: int = 48) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Sfx.play("ui")
		cb.call()
	)
	if selected:
		b.add_theme_stylebox_override("normal", Util.sel_style())
		b.add_theme_stylebox_override("hover", Util.sel_style())
		b.add_theme_color_override("font_color", Color(0.1, 0.07, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.07, 0.02))
	return b


func row(children: Array, sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


func grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g


func section(text: String) -> Label:
	return L(text.to_upper(), 13, C_SYS)


func _clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 12)
	b.max_value = 100
	b.add_theme_stylebox_override("fill", Util.sbox(color, Color(0, 0, 0, 0), 5, 0, 0.0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


# ---------- ventanas ----------

## Crea (una vez) una ventana. En VR vive en un panel 3D de `px` píxeles y `w_m` metros.
func win(wname: String, px: Vector2i, w_m: float, desk_w: int = 720, align: String = "center", desk_h: int = 0) -> Dictionary:
	if windows.has(wname):
		return windows[wname]
	var panel := PanelContainer.new()
	panel.theme = th
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var w := {"name": wname, "panel": panel, "body": body, "host": null, "holder": null}
	if xr:
		panel.add_child(body)
		var host := Panel3D.new()
		main.add_child(host)
		host.setup(panel, px, w_m)
		host.visible = false
		w.host = host
		main.panels.append(host)
	else:
		if desk_h > 0:
			var sc := ScrollContainer.new()
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			sc.custom_minimum_size = Vector2(0, desk_h)
			sc.add_child(body)
			panel.add_child(sc)
		else:
			panel.add_child(body)
		panel.custom_minimum_size = Vector2(desk_w, 0)
		var holder: Control
		if align == "left":
			var mc := MarginContainer.new()
			mc.set_anchors_preset(Control.PRESET_FULL_RECT)
			for side in ["left", "top", "bottom"]:
				mc.add_theme_constant_override("margin_" + side, 14)
			panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			holder = mc
		else:
			holder = CenterContainer.new()
			holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(panel)
		holder.visible = false
		root.add_child(holder)
		w.holder = holder
	windows[wname] = w
	return w


func is_open(wname: String) -> bool:
	if not windows.has(wname):
		return false
	var w: Dictionary = windows[wname]
	return w.host.visible if xr else w.holder.visible


func any_open() -> bool:
	for n in ["creator", "menu", "help", "forge"]:
		if is_open(n):
			return true
	return false


func show_win(wname: String) -> void:
	var w: Dictionary = windows[wname]
	if xr:
		w.host.visible = true
	else:
		w.holder.visible = true
	mark(wname)


func hide_win(wname: String) -> void:
	if not windows.has(wname):
		return
	var w: Dictionary = windows[wname]
	if xr:
		w.host.visible = false
		w.host.pointer_exit()
	else:
		w.holder.visible = false


func place_front(wname: String, dist: float = 1.05, drop: float = 0.12) -> void:
	if xr and windows.has(wname):
		windows[wname].host.place_in_front(main.player.camera, dist, drop)


func mark(wname: String) -> void:
	dirty[wname] = true


func mark_all() -> void:
	for k in windows:
		dirty[k] = true


func _process(delta: float) -> void:
	for k in dirty.keys():
		if is_open(k):
			call("_build_" + k)
	dirty.clear()
	if is_open("forge"):
		_update_forge_bar()
	if hurt_rect.color.a > 0.0:
		hurt_rect.color.a = maxf(0.0, hurt_rect.color.a - delta * 1.5)
	if xr and toast3d_t > 0.0:
		toast3d_t -= delta
		if toast3d_t <= 0.0:
			toast3d.visible = false


func flash_hurt() -> void:
	hurt_rect.color.a = 0.35


# ---------- avisos ----------

func _on_toast(msg: String, kind: String) -> void:
	if xr:
		vr_toast(msg)
		return
	var p := PanelContainer.new()
	var col := C_BRASS if kind == "gold" else (C_BAD if kind == "bad" else C_SYS)
	var sb := Util.sbox(Color(0.04, 0.09, 0.13, 0.95), col, 6, 2, 12.0)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(L(msg, 16))
	toasts_box.add_child(p)
	while toasts_box.get_child_count() > 4:
		var old := toasts_box.get_child(0)
		toasts_box.remove_child(old)
		old.queue_free()
	get_tree().create_timer(5.2).timeout.connect(p.queue_free)


func _build_toast3d() -> void:
	var pc := PanelContainer.new()
	pc.theme = th
	toast3d_label = L("", 26)
	toast3d_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast3d_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast3d_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc.add_child(toast3d_label)
	var host := Panel3D.new()
	main.player.camera.add_child(host)
	host.setup(pc, Vector2i(1000, 150), 0.9)
	host.interactive = false
	host.position = Vector3(0, 0.32, -1.2)
	host.visible = false
	toast3d = host


func vr_toast(msg: String) -> void:
	if toast3d == null:
		return
	toast3d_label.text = msg
	toast3d.visible = true
	toast3d_t = 4.5


# ---------- HUD de PC ----------

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	var left := VBoxContainer.new()
	left.position = Vector2(12, 12)
	left.custom_minimum_size = Vector2(290, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 8)
	hud.add_child(left)
	var stats := PanelContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(stats)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	stats.add_child(sv)
	refs.name = L("", 22)
	refs.jobs = L("", 14, C_MUTED)
	refs.title = L("", 14, C_BRASS)
	sv.add_child(refs.name)
	sv.add_child(refs.jobs)
	sv.add_child(refs.title)
	for k in [["hp", "Vida", C_BAD], ["mp", "Maná", Color(0.36, 0.55, 1.0)], ["st", "Energía", C_OK], ["xp", "Nivel", C_BRASS]]:
		var lbl := L("", 13, C_MUTED, false)
		refs[k[0] + "_l"] = lbl
		sv.add_child(lbl)
		var bar := _bar(k[2])
		refs[k[0]] = bar
		sv.add_child(bar)
	var qp := PanelContainer.new()
	qp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(qp)
	var qv := VBoxContainer.new()
	qp.add_child(qv)
	qv.add_child(L("Misiones", 16, C_SYS))
	refs.quests = VBoxContainer.new()
	qv.add_child(refs.quests)
	var clock := PanelContainer.new()
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.anchor_left = 1.0
	clock.anchor_right = 1.0
	clock.offset_left = -270
	clock.offset_right = -12
	clock.offset_top = 12
	clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.add_child(clock)
	var cv := VBoxContainer.new()
	clock.add_child(cv)
	refs.clock = L("17:30", 28, C_TEXT, false)
	refs.sub = L("", 14, C_MUTED)
	refs.portal = L("", 14, C_MUTED)
	refs.gold = L("", 16, C_BRASS, false)
	for k in ["clock", "sub", "portal", "gold"]:
		refs[k].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cv.add_child(refs[k])
	var cross := L("+", 26, Color(1, 1, 1, 0.8), false)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -8
	cross.offset_top = -18
	hud.add_child(cross)
	var prompt := PanelContainer.new()
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_left = -220
	prompt.offset_right = 220
	prompt.offset_top = -150
	prompt.offset_bottom = -110
	prompt.visible = false
	refs.prompt_lbl = L("", 17, C_TEXT, false)
	refs.prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_child(refs.prompt_lbl)
	hud.add_child(prompt)
	refs.prompt = prompt
	var hot := HBoxContainer.new()
	hot.anchor_left = 0.5
	hot.anchor_right = 0.5
	hot.anchor_top = 1.0
	hot.anchor_bottom = 1.0
	hot.offset_left = -190
	hot.offset_right = 190
	hot.offset_top = -78
	hot.offset_bottom = -14
	hot.add_theme_constant_override("separation", 6)
	hud.add_child(hot)
	refs.hot = hot
	var tools := HFlowContainer.new()
	tools.anchor_left = 1.0
	tools.anchor_right = 1.0
	tools.anchor_top = 1.0
	tools.anchor_bottom = 1.0
	tools.offset_left = -420
	tools.offset_right = -12
	tools.offset_top = -120
	tools.offset_bottom = -12
	tools.alignment = FlowContainer.ALIGNMENT_END
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	hud.add_child(tools)
	for t in [["Inventario (I)", func(): open_menu("menu", "inv")], ["Rumores (R)", func(): open_menu("menu", "rumors")],
			["Descansar 1 h", func(): main.rest_hour()], ["Ajustes", func(): open_menu("menu", "settings")], ["Controles (H)", func(): open_help()]]:
		var b := B(t[0], t[1], false, 40)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.clip_text = false
		tools.add_child(b)
	refresh_hotbar()


func show_hud() -> void:
	if hud:
		hud.visible = true
	refresh_hud()


func refresh_hotbar() -> void:
	if not refs.has("hot"):
		return
	_clear(refs.hot)
	for i in Game.SPELLS.size():
		var sp: Dictionary = Game.SPELLS[i]
		var b := B("%d · %s\n%d MP" % [i + 1, sp.name, sp.mp], func():
			main.set_spell(i)
			main.cast_from_camera()
		, Game.spell == i, 58)
		b.add_theme_font_size_override("font_size", 15)
		refs.hot.add_child(b)


func refresh_hud() -> void:
	if hud == null or not hud.visible:
		return
	refs.name.text = Game.player_name
	refs.jobs.text = "%s · %s" % [Game.JOBS[Game.cls].name, Game.JOBS[Game.sub].name]
	refs.title.text = "«%s»" % Game.title if Game.title != "" else ""
	refs.title.visible = Game.title != ""
	refs.hp.value = Game.hp / Game.max_hp * 100.0
	refs.mp.value = Game.mp / Game.max_mp * 100.0
	refs.st.value = Game.st / Game.max_st * 100.0
	refs.xp.value = float(Game.xp) / float(Game.lvl * 100) * 100.0
	refs.hp_l.text = "Vida %d/%d" % [ceili(Game.hp), roundi(Game.max_hp)]
	refs.mp_l.text = "Maná %d/%d" % [floori(Game.mp), roundi(Game.max_mp)]
	refs.st_l.text = "Energía %d" % floori(Game.st)
	refs.xp_l.text = "Nivel %d · %d/%d XP" % [Game.lvl, Game.xp, Game.lvl * 100]
	refs.clock.text = Game.time_str()
	refs.sub.text = "Día %d · Luna %s · Pan %d" % [Game.day, Game.moon_name(), Game.bread_cost()]
	refs.portal.text = "● Portal abierto" if Game.portal_open() else "○ Portal: abre 19:00"
	refs.portal.add_theme_color_override("font_color", C_SYS if Game.portal_open() else C_MUTED)
	refs.gold.text = "%d monedas" % Game.gold
	_clear(refs.quests)
	if Game.quests.is_empty():
		refs.quests.add_child(L("Habla con los habitantes. Pregúntales si tienen trabajo.", 13, C_MUTED))
	for q in Game.quests:
		var d: Dictionary = Game.QT[q.id]
		var done := Game.q_done(q)
		refs.quests.add_child(L("%s  %d/%d" % [d.title, Game.q_progress(q), d.need], 15, C_OK if done else C_TEXT))
		refs.quests.add_child(L("Vuelve con %s para entregarla." % Game.npcs[d.giver].npc_name if done else d.desc, 12, C_MUTED))


func set_prompt(text: String) -> void:
	if not refs.has("prompt"):
		return
	refs.prompt.visible = text != ""
	refs.prompt_lbl.text = "[E]  " + text


# ---------- creador de personaje ----------

func open_creator() -> void:
	win("creator", Vector2i(1400, 900), 1.35, 820, "left", 680)
	show_win("creator")
	if xr:
		get_tree().create_timer(0.6).timeout.connect(func(): place_front("creator", 1.3, 0.25))


func close_creator() -> void:
	hide_win("creator")


func _swatches(list: Array, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for c in list:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.focus_mode = Control.FOCUS_NONE
		var sel: bool = str(Game.look[key]) == c
		var sb := Util.sbox(Color.html(c), C_BRASS if sel else Color(1, 1, 1, 0.2), 22, 4 if sel else 2, 0.0)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			Game.look[key] = c
			Sfx.play("ui")
			main.rebuild_avatar()
			mark("creator")
		)
		h.add_child(b)
	return h


func _stepper(text: String, minus: Callable, plus: Callable) -> HBoxContainer:
	var m := B("−", minus, false, 44)
	m.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.custom_minimum_size.x = 56
	var p := B("+", plus, false, 44)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.custom_minimum_size.x = 56
	var l := L(text, 20, C_TEXT, false)
	l.custom_minimum_size.x = 110
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return row([m, l, p])


func _adj(key: String, delta: float, lo: float, hi: float) -> void:
	Game.look[key] = clampf(float(Game.look[key]) + delta, lo, hi)
	main.rebuild_avatar()
	mark("creator")


func _choice(options: Array, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for o in options:
		h.add_child(B(o[1], func():
			Game.look[key] = o[0]
			main.rebuild_avatar()
			mark("creator")
		, Game.look[key] == o[0], 44))
	return h


func _job_grid(slot: String) -> GridContainer:
	var g := grid(4)
	for k in Game.JOB_ORDER:
		var cur: String = Game.cls if slot == "cls" else Game.sub
		g.add_child(B(Game.JOBS[k].name, func():
			var other := "sub" if slot == "cls" else "cls"
			if Game.get(other) == k:
				Game.set(other, Game.get(slot))
			Game.set(slot, k)
			mark("creator")
		, cur == k, 46))
	return g


func _build_creator() -> void:
	var b: VBoxContainer = windows.creator.body
	_clear(b)
	b.add_child(L("VENTANA DE CREACIÓN · VIAJERO NUEVO", 13, C_SYS))
	b.add_child(L("Tierras Vivas", 38, C_BRASS))
	b.add_child(L("Valdeluz, al atardecer. Sus habitantes recordarán lo que hagas.", 16, C_MUTED))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	b.add_child(cols)
	var a := VBoxContainer.new()
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_constant_override("separation", 8)
	var j := VBoxContainer.new()
	j.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	j.add_theme_constant_override("separation", 8)
	cols.add_child(a)
	cols.add_child(j)
	a.add_child(section("Nombre"))
	if xr:
		a.add_child(L(Game.player_name, 22))
	else:
		var le := LineEdit.new()
		le.text = Game.player_name
		le.max_length = 16
		le.text_changed.connect(func(t): Game.player_name = t.strip_edges() if t.strip_edges() != "" else "Viajero")
		a.add_child(le)
	a.add_child(section("Altura"))
	a.add_child(_stepper("%.2f m" % float(Game.look.height), func(): _adj("height", -0.04, 1.55, 1.95), func(): _adj("height", 0.04, 1.55, 1.95)))
	a.add_child(section("Complexión"))
	a.add_child(_stepper("%d %%" % roundi(float(Game.look.build) * 100.0), func(): _adj("build", -0.05, 0.85, 1.3), func(): _adj("build", 0.05, 0.85, 1.3)))
	a.add_child(section("Piel"))
	a.add_child(_swatches(SKINS, "skin"))
	a.add_child(section("Peinado"))
	a.add_child(_choice([["corto", "Corto"], ["largo", "Largo"], ["coleta", "Coleta"], ["rapado", "Rapado"]], "hair_style"))
	a.add_child(section("Color de cabello"))
	a.add_child(_swatches(HAIRS, "hair"))
	a.add_child(section("Ropa"))
	a.add_child(_swatches(OUTFITS, "outfit"))
	a.add_child(section("Capa"))
	a.add_child(_choice([[true, "Con capa"], [false, "Sin capa"]], "cape"))
	j.add_child(section("Trabajo principal · efecto completo y vida/maná base"))
	j.add_child(_job_grid("cls"))
	j.add_child(L("%s: %s" % [Game.JOBS[Game.cls].name, Game.JOBS[Game.cls].p], 15, C_MUTED))
	j.add_child(section("Trabajo secundario · mitad del efecto"))
	j.add_child(_job_grid("sub"))
	j.add_child(L("%s: %s" % [Game.JOBS[Game.sub].name, Game.JOBS[Game.sub].s], 15, C_MUTED))
	var syn: String = Game.SYNERGY.get(Game.syn_key(), "")
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", Util.sbox(Color(0, 0, 0, 0.2), C_SYS, 8, 1, 14.0))
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	sv.add_child(L("%s (principal) + %s (secundario)" % [Game.JOBS[Game.cls].name, Game.JOBS[Game.sub].name], 14, C_SYS))
	sv.add_child(L("Sinergia: " + syn if syn != "" else "Sin sinergia especial para esta pareja; cada trabajo aporta su efecto.", 16))
	sv.add_child(L("Vida %d · Maná %d" % [roundi(Game.base_hp()), int(Game.JOBS[Game.cls].mp)], 14, C_MUTED))
	j.add_child(sp)
	var start := B("Entrar a Valdeluz", func(): main.start_game(false), true, 54)
	var btns := [start]
	if not Game.load_save().is_empty():
		btns.append(B("Continuar partida", func(): main.start_game(true), false, 54))
	j.add_child(row(btns))


# ---------- diálogo ----------

func open_dialog() -> void:
	win("dialog", Vector2i(1060, 760), 1.1, 700)
	show_win("dialog")
	place_front("dialog", 1.15, 0.15)


func close_dialog() -> void:
	hide_win("dialog")


func _build_dialog() -> void:
	var b: VBoxContainer = windows.dialog.body
	_clear(b)
	var d = main.dialogue
	var n = d.npc
	if n == null:
		return
	var head := L(n.npc_name, 30, C_BRASS, false)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(row([head, L("Afinidad %d" % roundi(n.aff), 15, C_MUTED, false)]))
	b.add_child(L(n.role, 15, C_MUTED))
	if d.you != "":
		b.add_child(L("Tú: " + d.you, 18, C_SYS))
	b.add_child(L(("%s está pensando…" % n.npc_name) if d.thinking else d.reply, 22))
	if d.offer != "":
		var q: Dictionary = Game.QT[d.offer]
		var op := PanelContainer.new()
		op.add_theme_stylebox_override("panel", Util.sbox(Color(0.91, 0.71, 0.3, 0.08), C_BRASS, 8, 2, 14.0))
		var ov := VBoxContainer.new()
		op.add_child(ov)
		ov.add_child(L(("MISIÓN OCULTA" if q.get("hidden", false) else "MISIÓN") + " · LA DECIDE EL JUEGO", 12, C_SYS))
		ov.add_child(L(q.title, 22, C_BRASS))
		ov.add_child(L(q.desc, 16))
		var rw: Dictionary = q.reward
		ov.add_child(L("Recompensa: %d monedas · %d XP · +%d afinidad%s" % [rw.gold, rw.xp, rw.aff, (" · título «%s»" % rw.title) if rw.has("title") else ""], 14, C_MUTED))
		ov.add_child(row([B("Aceptar misión", _accept_offer.bind(str(d.offer)), true), B("Ahora no", _decline_offer)]))
		b.add_child(op)
	else:
		var g := grid(2)
		for o in d.options():
			var btn := B(o.t, func(): d.choose(o), o.i == "deliver")
			btn.disabled = d.busy and o.i != "bye"
			g.add_child(btn)
		b.add_child(g)
	if not xr:
		var le := LineEdit.new()
		le.placeholder_text = "Escribe lo que le dices…"
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_submitted.connect(func(t): d.say_free(t))
		var send := B("Decir", func(): d.say_free(le.text), false, 40)
		send.size_flags_horizontal = Control.SIZE_SHRINK_END
		send.custom_minimum_size.x = 100
		b.add_child(row([le, send]))
	b.add_child(L("Diálogo generado por Claude con tu clave de API." if d.ai_enabled() else "Diálogo con guion de respaldo. Pon tu clave de API en Ajustes para que improvisen.", 13, C_MUTED))


# ---------- menú, puesto y ajustes ----------

func open_menu(mode: String = "menu", tab: String = "") -> void:
	menu_mode = mode
	if tab != "":
		menu_tab = tab
	win("menu", Vector2i(1060, 860), 1.05, 680, "center", 560)
	show_win("menu")
	place_front("menu", 1.0, 0.1)
	if not xr:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_menu() -> void:
	hide_win("menu")


func _build_menu() -> void:
	var b: VBoxContainer = windows.menu.body
	_clear(b)
	var title := L("Tu puesto" if menu_mode == "stall" else "Menú", 30, C_BRASS, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := B("Cerrar", func(): close_menu(), false, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size.x = 140
	b.add_child(row([title, close]))
	if menu_mode == "stall":
		_menu_stall(b)
		return
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in [["inv", "Inventario"], ["quests", "Misiones"], ["rumors", "Rumores"], ["titles", "Títulos"], ["settings", "Ajustes"]]:
		tabs.add_child(B(t[1], func():
			menu_tab = t[0]
			mark("menu")
		, menu_tab == t[0], 44))
	b.add_child(tabs)
	match menu_tab:
		"inv":
			b.add_child(L("%d monedas · Nivel %d" % [Game.gold, Game.lvl], 16, C_MUTED))
			if Game.inv.is_empty():
				b.add_child(L("Vacío.", 18, C_MUTED))
			for k in Game.inv:
				var name_l := L("%s ×%d" % [Game.item_name(k), Game.inv[k]], 19, C_TEXT, false)
				name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var items: Array = [name_l]
				if Game.ITEMS.has(k) and Game.ITEMS[k].has("food"):
					var eat := B("Comer", func():
						close_menu()
						main.start_hold(k)
						if xr:
							vr_toast("Lleva la comida de tu mano derecha a la boca.")
						else:
							main.eat.anim = 1.0
					, false, 42)
					eat.size_flags_horizontal = Control.SIZE_SHRINK_END
					eat.custom_minimum_size.x = 140
					items.append(eat)
				b.add_child(row(items))
		"quests":
			if Game.quests.is_empty():
				b.add_child(L("Sin misiones. Pregunta a los habitantes si tienen trabajo.", 18, C_MUTED))
			for q in Game.quests:
				var d: Dictionary = Game.QT[q.id]
				var done := Game.q_done(q)
				b.add_child(L("%s  %d/%d" % [d.title, Game.q_progress(q), d.need], 20, C_OK if done else C_TEXT))
				b.add_child(L("Vuelve con %s para entregarla." % Game.npcs[d.giver].npc_name if done else d.desc, 15, C_MUTED))
		"rumors":
			b.add_child(L("Lo que los habitantes se dicen entre ellos. Los rumores abren misiones.", 15, C_MUTED))
			if Game.rumor_log.is_empty():
				b.add_child(L("Aún no oyes rumores. Los habitantes se visitan y conversan solos.", 18, C_MUTED))
			for r in Game.rumor_log.slice(0, 7):
				b.add_child(L(str(r.text), 17))
				b.add_child(L("Día %d · %s" % [int(r.day), r.t], 13, C_MUTED))
		"titles":
			if Game.titles.is_empty():
				b.add_child(L("Gana títulos con tus hazañas. Solo uno está activo a la vez.", 18, C_MUTED))
			for t in Game.titles:
				var tl := L("%s — %s" % [t, Game.TITLES[t]], 17, C_BRASS if Game.title == t else C_TEXT)
				tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var act := B("Activo" if Game.title == t else "Activar", func():
					Game.title = t
					mark("menu")
				, Game.title == t, 42)
				act.size_flags_horizontal = Control.SIZE_SHRINK_END
				act.custom_minimum_size.x = 140
				b.add_child(row([tl, act]))
		"settings":
			_menu_settings(b)


func _setting_row(b: VBoxContainer, text: String, controls: Array) -> void:
	var l := L(text, 18, C_TEXT, false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var items: Array = [l]
	for c in controls:
		c.size_flags_horizontal = Control.SIZE_SHRINK_END
		c.custom_minimum_size.x = maxf(c.custom_minimum_size.x, 110)
		items.append(c)
	b.add_child(row(items))


func _set_opt(key: String, value) -> void:
	Game.settings[key] = value
	Game.save_settings()
	mark("menu")


func _vol(step: float) -> void:
	_set_opt("volume", clampf(float(Game.settings.volume) + step, 0.0, 1.0))
	Sfx.set_volume(float(Game.settings.volume))


func _accept_offer(off_id: String) -> void:
	Game.accept_quest(off_id)
	main.dialogue.offer = ""
	mark("dialog")


func _decline_offer() -> void:
	main.dialogue.offer = ""
	mark("dialog")


func _menu_settings(b: VBoxContainer) -> void:
	_setting_row(b, "Voces de los habitantes", [B("Activadas" if Game.settings.tts else "Desactivadas", func(): _set_opt("tts", not bool(Game.settings.tts)), bool(Game.settings.tts), 42)])
	_setting_row(b, "Volumen de efectos: %d %%" % roundi(float(Game.settings.volume) * 100.0), [B("−", _vol.bind(-0.1), false, 42), B("+", _vol.bind(0.1), false, 42)])
	b.add_child(section("Confort en VR"))
	var snaps: Array = []
	for v in [15, 30, 45]:
		snaps.append(B("%d°" % v, func(): _set_opt("snap", v), int(Game.settings.snap) == v, 42))
	_setting_row(b, "Giro por pasos", snaps)
	_setting_row(b, "Viñeta al moverte", [B("Activada" if Game.settings.vignette else "Desactivada", func(): _set_opt("vignette", not bool(Game.settings.vignette)), bool(Game.settings.vignette), 42)])
	_setting_row(b, "Modo sentado", [B("Sí" if Game.seated else "No", func():
		main.toggle_seated()
		mark("menu")
	, Game.seated, 42)])
	b.add_child(section("IA de los habitantes"))
	var has_key := str(Game.settings.api_key).strip_edges() != ""
	b.add_child(L("Estado: " + ("clave guardada en este dispositivo." if has_key else "sin clave (usan frases de respaldo)."), 16, C_OK if has_key else C_MUTED))
	if xr:
		b.add_child(L("Para poner la clave, abre el juego en PC (Ajustes) o define tierras_vivas/ai/api_key en Proyecto → Configuración antes de exportar tu APK personal. No compartas un APK con tu clave dentro.", 15, C_MUTED))
	else:
		var le := LineEdit.new()
		le.placeholder_text = "sk-ant-…"
		le.secret = true
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var save := B("Guardar", func():
			if le.text.strip_edges() != "":
				_set_opt("api_key", le.text.strip_edges())
				Game.say("Clave guardada en este dispositivo.")
		, false, 42)
		save.size_flags_horizontal = Control.SIZE_SHRINK_END
		save.custom_minimum_size.x = 120
		var del := B("Borrar", func():
			_set_opt("api_key", "")
			Game.say("Clave borrada.")
		, false, 42)
		del.size_flags_horizontal = Control.SIZE_SHRINK_END
		del.custom_minimum_size.x = 120
		b.add_child(row([le, save, del]))
		b.add_child(L("La clave se guarda solo en este dispositivo (user://). Úsala solo en tu propio equipo.", 13, C_BRASS))
	b.add_child(section("Partida"))
	_setting_row(b, "Borrar la partida guardada", [B("Pulsa otra vez" if wipe_confirm else "Borrar", func():
		if wipe_confirm:
			Game.delete_save()
			Game.say("Partida borrada. Se empezará de cero la próxima vez.")
			wipe_confirm = false
		else:
			wipe_confirm = true
		mark("menu")
	, wipe_confirm, 42)])


func _menu_stall(b: VBoxContainer) -> void:
	b.add_child(L("%d monedas · los habitantes que pasan compran si el precio les parece justo.%s" % [Game.gold, " Tu trabajo de Comerciante hace que acepten precios más altos." if Game.has_job("comerciante") else ""], 15, C_MUTED))
	b.add_child(section("En venta (%d/3)" % Game.stall.size()))
	if Game.stall.is_empty():
		b.add_child(L("Vacío.", 18, C_MUTED))
	for i in Game.stall.size():
		var s: Dictionary = Game.stall[i]
		var l := L("%s · %d monedas" % [Game.item_name(s.key), s.price], 18, C_TEXT, false)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var take := B("Retirar", func():
			main.take_from_stall(i)
			mark("menu")
		, false, 42)
		take.size_flags_horizontal = Control.SIZE_SHRINK_END
		take.custom_minimum_size.x = 140
		b.add_child(row([l, take]))
	b.add_child(section("Tu inventario"))
	var shown := 0
	for k in Game.inv:
		if shown >= 7:
			break
		shown += 1
		var base := Game.item_base(k)
		var hi := maxi(base + 1, roundi(base * 1.3))
		var l2 := L("%s ×%d" % [Game.item_name(k), Game.inv[k]], 18, C_TEXT, false)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var items: Array = [l2]
		for price in [base, hi]:
			var sb := B("Vender %d" % price, func():
				main.place_on_stall(k, price)
				mark("menu")
			, false, 42)
			sb.size_flags_horizontal = Control.SIZE_SHRINK_END
			sb.custom_minimum_size.x = 140
			items.append(sb)
		b.add_child(row(items))


# ---------- forja ----------

func open_forge() -> void:
	win("forge", Vector2i(900, 360), 0.8, 560)
	show_win("forge")
	if xr:
		var at: Vector3 = main.world.anvil_top
		var cam: Vector3 = main.player.camera.global_position
		windows.forge.host.face_from(at + Vector3(0, 0.85, 0), Vector3(cam.x, at.y + 0.85, cam.z))


func close_forge() -> void:
	hide_win("forge")


func _build_forge() -> void:
	var b: VBoxContainer = windows.forge.body
	_clear(b)
	b.add_child(L("YUNQUE DE MAESE DORRAN", 12, C_SYS))
	forge_refs.title = L("", 26, C_BRASS, false)
	b.add_child(forge_refs.title)
	b.add_child(L("Golpea el yunque o pulsa el gatillo cuando la marca esté en la luz." if xr else "Pulsa Espacio o haz clic cuando la marca blanca esté en la zona brillante. Esc para salir.", 15, C_MUTED))
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 40)
	var bg := ColorRect.new()
	bg.color = Color(0.23, 0.09, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bg)
	var zone := ColorRect.new()
	zone.color = Color(1, 0.84, 0.47, 0.8)
	bar.add_child(zone)
	var mark_r := ColorRect.new()
	mark_r.color = Color(1, 1, 1)
	bar.add_child(mark_r)
	b.add_child(bar)
	forge_refs.bar = bar
	forge_refs.zone = zone
	forge_refs.mark = mark_r
	forge_refs.hits = L("", 18, C_TEXT, false)
	b.add_child(forge_refs.hits)
	var ex := B("Salir de la forja", func(): main.cancel_forge(), false, 44)
	ex.size_flags_horizontal = Control.SIZE_SHRINK_END
	ex.custom_minimum_size.x = 240
	b.add_child(ex)
	_update_forge_bar()


func _update_forge_bar() -> void:
	if not forge_refs.has("bar") or not is_instance_valid(forge_refs.bar):
		return
	var f: Dictionary = main.forge
	var w: float = forge_refs.bar.size.x
	var h: float = forge_refs.bar.size.y
	forge_refs.zone.position = Vector2((f.zone - f.w) * w, 0)
	forge_refs.zone.size = Vector2(f.w * 2.0 * w, h)
	forge_refs.mark.position = Vector2(f.x * w - 3, -4)
	forge_refs.mark.size = Vector2(6, h + 8)
	forge_refs.title.text = "Forjar espada · golpe %d de 5" % mini(5, f.hits.size() + 1)
	var parts := []
	for a in f.hits:
		parts.append("%d %%" % roundi(a * 100.0))
	forge_refs.hits.text = "   ".join(parts)


# ---------- ayuda ----------

func open_help() -> void:
	win("help", Vector2i(1060, 860), 1.05, 720, "center", 560)
	show_win("help")
	place_front("help", 1.0, 0.1)
	if not xr:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_help() -> void:
	var b: VBoxContainer = windows.help.body
	_clear(b)
	var t := L("Controles", 30, C_BRASS, false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c := B("Cerrar", func(): hide_win("help"), false, 44)
	c.size_flags_horizontal = Control.SIZE_SHRINK_END
	c.custom_minimum_size.x = 140
	b.add_child(row([t, c]))
	var blocks := [
		["PC", "WASD moverte · Mayús correr · ratón mirar (clic para fijarlo) · clic lanzar hechizo · 1/2/3 fuego, escudo, curar · E hablar/recoger/forjar · F comer · Espacio saltar · I inventario · R rumores · H controles · Esc cerrar"],
		["Quest con mandos", "Stick izquierdo moverte · stick derecho girar · gatillo derecho apuntar y usar · gatillo izquierdo canalizar el hechizo y soltar lanzando la mano · X cambiar hechizo · A saltar · B cerrar diálogo · baja la mano izquierda para ver tu panel de muñeca"],
		["Quest con las manos", "Pellizco derecho apuntando: usar · pellizca el suelo y suelta: moverte · pellizco izquierdo: canalizar hechizo, suelta mientras lanzas la mano · baja la mano izquierda: panel (girar, saltar, comer, menú)"],
		["Comer y forjar", "La comida aparece en tu mano derecha: llévala a la boca, tres mordidas. En la forja, golpea el yunque con el martillo o pulsa el gatillo cuando la marca esté en la luz."],
	]
	for bl in blocks:
		b.add_child(section(bl[0]))
		b.add_child(L(bl[1], 17))


# ---------- panel de muñeca (solo VR) ----------

func wrist_visible() -> bool:
	return is_open("wrist")


func update_wrist(hand: Node3D, cam: Node3D, hide_it: bool) -> void:
	if not xr or not Game.started:
		return
	var w := win("wrist", Vector2i(560, 680), 0.27)
	if w.body.get_child_count() == 0:
		_build_wrist()
	var hp := hand.global_position
	var cp := cam.global_position
	var show_it := not hide_it and hp.y < cp.y - 0.22 and hp.distance_to(cp) < 0.85
	if show_it != w.host.visible:
		w.host.visible = show_it
		if not show_it:
			w.host.pointer_exit()
	if show_it:
		w.host.face_from(hp + Vector3(0, 0.16, 0), cp)
		wrist_t -= get_process_delta_time()
		if wrist_t <= 0.0:
			wrist_t = 0.5
			_update_wrist_values()


func _build_wrist() -> void:
	var b: VBoxContainer = windows.wrist.body
	_clear(b)
	wrist_refs.time = L("", 26, C_TEXT, false)
	wrist_refs.moon = L("", 17, C_MUTED, false)
	b.add_child(wrist_refs.time)
	b.add_child(wrist_refs.moon)
	for k in [["hp", C_BAD], ["mp", Color(0.36, 0.55, 1.0)], ["st", C_OK]]:
		var bar := _bar(k[1])
		bar.custom_minimum_size.y = 16
		wrist_refs[k[0]] = bar
		b.add_child(bar)
	wrist_refs.quest = L("", 16, C_MUTED)
	b.add_child(wrist_refs.quest)
	var g := grid(2)
	wrist_refs.spell = B("Hechizo", func():
		main.cycle_spell()
		_update_wrist_values()
	, false, 64)
	g.add_child(wrist_refs.spell)
	g.add_child(B("Comer", func():
		var k := Game.food_key()
		if k != "":
			main.start_hold(k)
			vr_toast("Lleva la comida a tu boca.")
		else:
			vr_toast("No tienes comida.")
	, false, 64))
	g.add_child(B("◀ Girar", func(): main.player.snap_turn(1.0), false, 64))
	g.add_child(B("Girar ▶", func(): main.player.snap_turn(-1.0), false, 64))
	g.add_child(B("Saltar", func(): main.player.jump(), false, 64))
	g.add_child(B("Descansar 1 h", func(): main.rest_hour(), false, 64))
	wrist_refs.seat = B("Sentado", func():
		main.toggle_seated()
		_update_wrist_values()
	, false, 64)
	g.add_child(wrist_refs.seat)
	wrist_refs.menu = B("Menú", func():
		if main.dialogue.npc:
			main.dialogue.close()
		else:
			open_menu("menu", "inv")
	, false, 64)
	g.add_child(wrist_refs.menu)
	b.add_child(g)
	_update_wrist_values()


func _update_wrist_values() -> void:
	if not wrist_refs.has("time"):
		return
	wrist_refs.time.text = "%s · Día %d" % [Game.time_str(), Game.day]
	wrist_refs.moon.text = "Luna %s · portal %s · %d monedas" % [Game.moon_name(), "abierto" if Game.portal_open() else "cerrado", Game.gold]
	wrist_refs.hp.value = Game.hp / Game.max_hp * 100.0
	wrist_refs.mp.value = Game.mp / Game.max_mp * 100.0
	wrist_refs.st.value = Game.st / Game.max_st * 100.0
	var q_text := "Nivel %d" % Game.lvl
	if not Game.quests.is_empty():
		var q: Dictionary = Game.quests[0]
		q_text = "%s %d/%d" % [Game.QT[q.id].title, Game.q_progress(q), Game.QT[q.id].need]
	wrist_refs.quest.text = q_text
	wrist_refs.spell.text = "Hechizo: " + Game.SPELLS[Game.spell].name
	wrist_refs.seat.text = "Sentado: sí" if Game.seated else "Sentado: no"
	wrist_refs.menu.text = "Cerrar diálogo" if main.dialogue.npc else "Menú"
