extends CanvasLayer
## HUD del juego: misión actual, jugadores conectados, mira, avisos y menú de pausa.
## El inventario y la barra rápida están en inventory_ui.gd.

const InventoryUI := preload("res://scripts/ui/inventory_ui.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const DialogUI := preload("res://scripts/ui/dialog_ui.gd")
const MapUI := preload("res://scripts/ui/map_ui.gd")
const CharacterUI := preload("res://scripts/ui/character_ui.gd")


## Brújula: muestra hacia dónde mirás (N, NE, E...) y la dirección del campamento,
## de tu cama y del objetivo de misión.
class Compass extends Control:
	const SPAN := PI * 0.6  ## Ángulo visible de punta a punta.
	const POINTS := [["N", 0.0], ["NE", 0.25], ["E", 0.5], ["SE", 0.75], ["S", 1.0], ["SO", 1.25], ["O", 1.5], ["NO", 1.75]]

	func _process(_delta: float) -> void:
		queue_redraw()

	func _heading() -> float:
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return 0.0
		var forward := -camera.global_transform.basis.z
		return atan2(forward.x, -forward.z)

	func _draw() -> void:
		var player := Game.local_player
		if player == null:
			return
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.1, 0.55))
		var heading := _heading()
		for point in POINTS:
			var x := _x_for(point[1] * PI, heading)
			if x >= 0.0:
				var main: bool = point[0].length() == 1
				draw_string(font, Vector2(x - (6 if main else 9), size.y - 7), point[0], HORIZONTAL_ALIGNMENT_LEFT, -1,
					16 if main else 12, Color(1, 0.86, 0.6) if point[0] == "N" else Color(1, 1, 1, 0.85 if main else 0.5))
		for i in 24:
			var x := _x_for(i * TAU / 24.0, heading)
			if x >= 0.0:
				draw_line(Vector2(x, 0), Vector2(x, 5), Color(1, 1, 1, 0.35), 1.0)
		var world := get_tree().get_first_node_in_group("world")
		if world == null:
			return
		var markers: Array = [[world.landmarks.get("spawn", Vector3.INF), Color(1, 0.85, 0.45)]]
		for piece in world.pieces_root.get_children():
			if piece is BuildPiece and piece.kind() == "bed" and piece.owner_name == Network.player_name:
				markers.append([piece.global_position, Color(0.95, 0.5, 0.4)])
		for id in QuestManager.active_quests():
			for objective in QuestDB.get_quest(id)["objectives"]:
				if objective["type"] == "reach":
					markers.append([world.landmarks.get(objective["target"], Vector3.INF), Color(1, 0.8, 0.2)])
				elif objective["type"] in ["ship", "sail"]:
					markers.append([world.landmarks.get("wreck", Vector3.INF), Color(1, 0.8, 0.2)])
		for marker in markers:
			var target: Vector3 = marker[0]
			if target == Vector3.INF:
				continue
			var to: Vector3 = target - (player.global_position as Vector3)
			var x := _x_for(atan2(to.x, -to.z), heading)
			if x >= 0.0:
				draw_colored_polygon(PackedVector2Array([Vector2(x, size.y - 1), Vector2(x - 5, size.y - 9), Vector2(x + 5, size.y - 9)]), marker[1])

	## Posición horizontal de un rumbo en la brújula (-1 si queda fuera de vista).
	func _x_for(bearing: float, heading: float) -> float:
		var delta := wrapf(bearing - heading, -PI, PI)
		if absf(delta) > SPAN / 2.0:
			return -1.0
		return size.x / 2.0 + delta / SPAN * size.x

var _root: Control
var _quest_objectives: VBoxContainer
var _players_label: Label
var _hint: Label
var _pickup_box: VBoxContainer
var _notifications: VBoxContainer
var _pause_overlay: Control
var _last_totals: Dictionary = {}
var _crosshair: Label
var _fps_label: Label
var _bars: Dictionary = {}
var _xp_label: Label
var _xp_bar: ProgressBar  ## "health" / "hunger" / "stamina" -> [ProgressBar, Label]
var _clock: Label
var _biome: Label
var _damage_flash: ColorRect
var _build_hint: Label
var _was_night := false
var _last_biome := ""
var _pause_box: Control


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_players_panel()
	_build_quest_panel()
	_build_center()
	_build_bottom()
	_build_vitals()
	_build_clock()
	_build_effects()
	_build_pause_menu()

	Game.inventory_changed.connect(_on_inventory_changed)
	Game.notify.connect(show_notification)
	Game.interaction_hint_changed.connect(func(text: String): _hint.text = text)
	Game.pause_toggled.connect(func(is_open: bool): _pause_overlay.visible = is_open)
	Game.inventory_toggled.connect(func(is_open: bool): _crosshair.visible = not is_open)
	QuestManager.quest_changed.connect(_refresh_quest)
	Game.inventory_changed.connect(_refresh_quest)
	Game.dialog_requested.connect(_open_dialog)
	Game.dialog_closed.connect(func(): _crosshair.visible = true)
	Game.stats_changed.connect(_refresh_vitals)
	Game.player_hit.connect(_on_player_hit)
	Game.player_died.connect(func(): show_notification("Moriste. Tus cosas quedaron donde caíste: volvé a buscarlas."))
	Network.players_changed.connect(_refresh_players)
	Cinematics.started.connect(func(): _root.visible = false)
	Cinematics.finished.connect(func(): _root.visible = true)

	_root.visible = not Cinematics.playing
	add_child(InventoryUI.new())
	add_child(MapUI.new())
	add_child(CharacterUI.new())
	add_child(TouchControls.new())  # Solo se ve en el celular (o si se activa en Opciones).
	_last_totals = _item_totals()
	_refresh_quest()
	_refresh_players()


# --- Construcción ------------------------------------------------------------------

func _build_players_panel() -> void:
	var panel := UIStyle.panel(UIStyle.PANEL_BG, 10)
	panel.position = Vector2(20, 20)
	_root.add_child(panel)
	_players_label = UIStyle.label("", 15, UIStyle.TEXT_DIM)
	panel.add_child(_players_label)
	_fps_label = UIStyle.label("", 14, UIStyle.SUCCESS)
	_fps_label.position = Vector2(24, 64)
	_root.add_child(_fps_label)


func _build_quest_panel() -> void:
	var panel := UIStyle.panel()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -400
	panel.offset_right = -20
	panel.offset_top = 20
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(UIStyle.label("MISIONES", 13, UIStyle.TEXT_DIM))
	_quest_objectives = VBoxContainer.new()
	_quest_objectives.add_theme_constant_override("separation", 3)
	box.add_child(_quest_objectives)


func _build_center() -> void:
	var crosshair := UIStyle.label("+", 22)
	_crosshair = crosshair
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -20
	crosshair.offset_right = 20
	crosshair.offset_top = -16
	crosshair.offset_bottom = 16
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.modulate = Color(1, 1, 1, 0.8)
	_root.add_child(crosshair)

	_hint = UIStyle.label("", 18, UIStyle.ACCENT)
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.offset_left = -250
	_hint.offset_right = 250
	_hint.offset_top = 30
	_hint.offset_bottom = 60
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)

	_pickup_box = VBoxContainer.new()
	_pickup_box.set_anchors_preset(Control.PRESET_CENTER)
	_pickup_box.offset_left = 40
	_pickup_box.offset_right = 300
	_pickup_box.offset_top = -60
	_pickup_box.offset_bottom = 0
	_pickup_box.alignment = BoxContainer.ALIGNMENT_END
	_pickup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pickup_box)


func _build_bottom() -> void:
	_notifications = VBoxContainer.new()
	_notifications.anchor_top = 1.0
	_notifications.anchor_bottom = 1.0
	_notifications.offset_left = 20
	_notifications.offset_right = 620
	_notifications.offset_top = -330
	_notifications.offset_bottom = -72
	_notifications.alignment = BoxContainer.ALIGNMENT_END
	_notifications.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_notifications)

	var help := UIStyle.label("WASD mover · Shift correr · Espacio saltar · Click usar/atacar · E interactuar\n1-6 / rueda: barra rápida · R pieza (martillo) · M mapa · C personaje · V cámara · Tab inventario · Esc menú", 13, UIStyle.TEXT_DIM)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 20
	help.offset_right = 520
	help.offset_top = -60
	help.offset_bottom = -16
	help.modulate = Color(1, 1, 1, 0.7)
	_root.add_child(help)
	# En el celular la ayuda de teclado no sirve: se oculta con los controles táctiles.
	var update_help := func() -> void: help.visible = not Settings.touch_enabled()
	Settings.changed.connect(update_help)
	update_help.call()


func _build_pause_menu() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0, 0, 0, 0.55)
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var panel := UIStyle.panel(Color(0.05, 0.07, 0.09, 0.92), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	_pause_box = panel
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UIStyle.label("Pausa", 30, UIStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := UIStyle.label("El juego sigue corriendo para tus compañeros.", 14, UIStyle.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	var resume := UIStyle.button("Continuar")
	resume.pressed.connect(func(): Game.set_pause_open(false))
	box.add_child(resume)
	# Guardar: solo el host (es quien tiene el mundo).
	if SaveManager.is_active():
		note.text = "Mundo: %s  ·  se guarda solo cada 3 minutos." % SaveManager.current_name
		var save := UIStyle.button("Guardar partida")
		save.pressed.connect(func():
			if SaveManager.save_game():
				Network.announce.rpc("Partida guardada")
			else:
				show_notification("No se pudo guardar la partida"))
		box.add_child(save)
	elif multiplayer.is_server():
		note.text = "Partida de prueba: este mundo no se guarda."
	else:
		note.text = "El host de la partida es quien la guarda."
	var options := UIStyle.button("Opciones")
	options.pressed.connect(_open_settings)
	box.add_child(options)
	var leave := UIStyle.button("Guardar y salir al menú" if SaveManager.is_active() else "Salir al menú principal")
	leave.pressed.connect(func(): Game.quit_to_menu_requested.emit())
	box.add_child(leave)


# --- Actualización -------------------------------------------------------------------

func _item_totals() -> Dictionary:
	var totals := {}
	for slot in Game.inventory:
		if not slot.is_empty():
			totals[slot["id"]] = int(totals.get(slot["id"], 0)) + slot["count"]
	return totals


## Muestra "+3 Madera" junto a la mira cuando entra algo nuevo al inventario.
func _on_inventory_changed() -> void:
	var totals := _item_totals()
	for item in totals:
		var gained: int = totals[item] - int(_last_totals.get(item, 0))
		if gained > 0:
			_show_pickup("+%d %s" % [gained, ItemDB.item_name(item)], ItemDB.color(item))
	_last_totals = totals


## Lista de misiones activas con su progreso (máximo 4 a la vista).
func _refresh_quest() -> void:
	for child in _quest_objectives.get_children():
		child.queue_free()
	var active := QuestManager.active_quests()
	if active.is_empty():
		var hint := UIStyle.label("Buscá a los habitantes con  !  sobre la cabeza para conseguir misiones.", 15, UIStyle.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(350, 0)
		_quest_objectives.add_child(hint)
		return
	# La historia principal va primero, marcada con una estrella.
	var sorted: Array = active.filter(func(q: String) -> bool: return QuestDB.get_quest(q).get("main", false))
	sorted.append_array(active.filter(func(q: String) -> bool: return not QuestDB.get_quest(q).get("main", false)))
	for id in sorted.slice(0, 4):
		var quest := QuestDB.get_quest(id)
		var main: bool = quest.get("main", false)
		_quest_objectives.add_child(UIStyle.label(("★ " if main else "") + quest["title"], 19, Color(1.0, 0.82, 0.35) if main else UIStyle.ACCENT))
		if QuestManager.get_status(id) == "ready" and QuestManager.missing_delivery(id).is_empty():
			_quest_objectives.add_child(UIStyle.label("  → Volvé con %s para entregarla" % NpcDB.display_name(quest.get("giver", "")), 15, UIStyle.SUCCESS))
			continue
		var objectives: Array = quest["objectives"]
		for i in objectives.size():
			var objective: Dictionary = objectives[i]
			var current := QuestManager.objective_progress(id, i)
			var done: bool = current >= objective["amount"]
			var text: String
			if objective["type"] in ["collect", "craft", "deliver"]:
				text = "  • %s: %d / %d" % [objective["text"], current, objective["amount"]]
			elif objective["type"] == "ship" and not done:
				var world := get_tree().get_first_node_in_group("world")
				text = "  • %s\n     %s" % [objective["text"], world.ship_progress_text(objective["item"]) if world else ""]
			else:
				text = "  • %s%s" % [objective["text"], " (hecho)" if done else ""]
			_quest_objectives.add_child(UIStyle.label(text, 15, UIStyle.SUCCESS if done else UIStyle.TEXT))
	if active.size() > 4:
		_quest_objectives.add_child(UIStyle.label("  ... y %d más" % (active.size() - 4), 14, UIStyle.TEXT_DIM))


## Vida, hambre y energía (abajo a la derecha).
func _build_vitals() -> void:
	var panel := UIStyle.panel(Color(0.06, 0.08, 0.1, 0.75), 10)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -260
	panel.offset_right = -20
	panel.offset_top = -150
	panel.offset_bottom = -20
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	for entry in [["health", "Vida", Color(0.85, 0.25, 0.22)], ["hunger", "Hambre", Color(0.9, 0.6, 0.2)], ["stamina", "Energía", Color(0.45, 0.8, 0.35)]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var label := UIStyle.label(entry[1], 14)
		label.custom_minimum_size = Vector2(62, 0)
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = entry[2]
		fill.set_corner_radius_all(3)
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.15, 0.15, 0.15, 0.9)
		background.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", background)
		row.add_child(bar)
		_bars[entry[0]] = [bar, label]
	# Nivel y experiencia.
	_xp_label = UIStyle.label("", 14, Color(0.6, 0.8, 1.0))
	box.add_child(_xp_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(220, 6)
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color(0.45, 0.7, 1.0)
	var xp_background := StyleBoxFlat.new()
	xp_background.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	_xp_bar.add_theme_stylebox_override("fill", xp_fill)
	_xp_bar.add_theme_stylebox_override("background", xp_background)
	box.add_child(_xp_bar)
	_refresh_vitals()


func _refresh_vitals() -> void:
	(_bars["health"][0] as ProgressBar).max_value = Game.max_health
	(_bars["health"][0] as ProgressBar).value = Game.health
	(_bars["hunger"][0] as ProgressBar).value = Game.hunger
	(_bars["hunger"][1] as Label).add_theme_color_override("font_color", Color(1, 0.45, 0.4) if Game.hunger < 15 else UIStyle.TEXT)


## Reloj, día y bioma (arriba al centro).
func _build_clock() -> void:
	var panel := UIStyle.panel(Color(0.06, 0.08, 0.1, 0.65), 8)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -130
	panel.offset_right = 130
	panel.offset_top = 16
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_clock = UIStyle.label("", 17)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_clock)
	_biome = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	_biome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_biome)
	var compass := Compass.new()
	compass.anchor_left = 0.5
	compass.anchor_right = 0.5
	compass.offset_left = -200
	compass.offset_right = 200
	compass.offset_top = 92
	compass.offset_bottom = 122
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(compass)


func _build_effects() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_damage_flash)
	_build_hint = UIStyle.label("", 16, UIStyle.ACCENT)
	_build_hint.anchor_left = 0.5
	_build_hint.anchor_right = 0.5
	_build_hint.anchor_top = 1.0
	_build_hint.anchor_bottom = 1.0
	_build_hint.offset_left = -400
	_build_hint.offset_right = 400
	_build_hint.offset_top = -150
	_build_hint.offset_bottom = -100
	_build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_build_hint)


func _on_player_hit(_amount: float) -> void:
	Sound.play("hurt")
	var tween := create_tween()
	tween.tween_property(_damage_flash, "color:a", 0.35, 0.05)
	tween.tween_property(_damage_flash, "color:a", 0.0, 0.4)


func _update_world_info() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.generated:
		return
	var day_night: DayNight = world.day_night
	_clock.text = "Día %d  ·  %s  ·  %s" % [day_night.day, day_night.clock_text(), day_night.period_name()]
	var night := day_night.is_night()
	if night and not _was_night:
		show_notification("Cae la noche... las sombras salen a cazar. Prendé una antorcha.")
		Sound.play("night_sting", Vector3.INF, -3.0)
	elif not night and _was_night:
		show_notification("Amanece. Las sombras se queman con la luz del sol.")
	_was_night = night
	var player := Game.local_player
	if player:
		var pos: Vector3 = player.global_position
		var biome: String = TerrainGenerator.BIOME_NAMES[world.terrain.get_biome(pos.x, pos.z)]
		var place: String = world.place_name(pos)
		if place != "":
			biome = place
		elif world.terrain.region_at(pos.x, pos.z) == "mainland":
			biome = "Valdoria · " + biome
		elif world.terrain.region_at(pos.x, pos.z) == "":
			biome = "Mar abierto"
		_biome.text = biome
		if biome != _last_biome and _last_biome != "":
			show_notification("Entraste a: %s" % biome)
		_last_biome = biome
		_update_build_hint(player, world)
	(_bars["stamina"][0] as ProgressBar).max_value = Game.max_stamina()
	(_bars["stamina"][0] as ProgressBar).value = Game.stamina
	var progress := Game.progress
	_xp_label.text = "Nivel %d%s" % [progress.get("level", 1), "  ·  %d punto(s): C" % progress["points"] if int(progress.get("points", 0)) > 0 else ""]
	_xp_bar.max_value = SkillDB.xp_to_next(progress.get("level", 1))
	_xp_bar.value = progress.get("xp", 0)


func _update_build_hint(player: Node, world: Node) -> void:
	if player.held_item != "hammer" or Game.inventory_open:
		_build_hint.text = ""
		return
	var piece: String = player.current_build_piece()
	if piece == "":
		_build_hint.text = "No conocen ningún plano. Encuéntrenlos en cofres o derrotando sombras de noche."
		return
	var data := BuildDB.get_piece(piece)
	var placement: Dictionary = player.build_placement()
	var status: String = "Click: construir" if placement.get("valid", false) else placement.get("reason", "")
	_build_hint.text = "%s  (%s)   ·   %s   ·   R: cambiar pieza   ·   Click der.: desarmar" % [
		data["name"], ItemDB.list_text(data["cost"]), status]


func _process(_delta: float) -> void:
	_update_world_info()
	_fps_label.visible = Settings.get_value("show_fps")
	if _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _open_dialog(npc_id: String) -> void:
	_crosshair.visible = false
	var dialog := DialogUI.new()
	dialog.npc_id = npc_id
	add_child(dialog)


func _open_settings() -> void:
	_pause_box.visible = false
	var menu := SettingsMenu.new()
	menu.closed.connect(func(): _pause_box.visible = true)
	add_child(menu)


func _refresh_players() -> void:
	if Network.is_solo:
		_players_label.text = "Partida individual"
	else:
		_players_label.text = "Jugadores: %d / %d" % [Network.players.size(), Network.MAX_PLAYERS]


func show_notification(text: String) -> void:
	var panel := UIStyle.panel(Color(0.06, 0.08, 0.1, 0.8), 10)
	panel.add_child(UIStyle.label(text, 17))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_notifications.add_child(panel)
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25).from(0.0)
	tween.tween_interval(5.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(panel.queue_free)


func _show_pickup(text: String, color: Color) -> void:
	Sound.play("pickup", Vector3.INF, -6.0)
	var label := UIStyle.label(text, 18, color.lightened(0.3))
	_pickup_box.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)
