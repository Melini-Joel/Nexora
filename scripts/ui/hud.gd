extends CanvasLayer
## HUD del juego: misión actual, jugadores conectados, mira, avisos y menú de pausa.
## El inventario y la barra rápida están en inventory_ui.gd.

const InventoryUI := preload("res://scripts/ui/inventory_ui.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const DialogUI := preload("res://scripts/ui/dialog_ui.gd")

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
var _bars: Dictionary = {}  ## "health" / "hunger" / "stamina" -> [ProgressBar, Label]
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

	var help := UIStyle.label("WASD mover · Shift correr · Espacio saltar · Click usar/atacar · E interactuar\n1-6 / rueda: barra rápida · R pieza (martillo) · V cámara · Tab inventario · Esc menú", 13, UIStyle.TEXT_DIM)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 20
	help.offset_right = 520
	help.offset_top = -60
	help.offset_bottom = -16
	help.modulate = Color(1, 1, 1, 0.7)
	_root.add_child(help)


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
	var options := UIStyle.button("Opciones")
	options.pressed.connect(_open_settings)
	box.add_child(options)
	var leave := UIStyle.button("Salir al menú principal")
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
	for id in active.slice(0, 4):
		var quest := QuestDB.get_quest(id)
		_quest_objectives.add_child(UIStyle.label(quest["title"], 19, UIStyle.ACCENT))
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
	panel.offset_top = -110
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
	_refresh_vitals()


func _refresh_vitals() -> void:
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
	elif not night and _was_night:
		show_notification("Amanece. Las sombras se queman con la luz del sol.")
	_was_night = night
	var player := Game.local_player
	if player:
		var biome: String = TerrainGenerator.BIOME_NAMES[world.terrain.get_biome(player.global_position.x, player.global_position.z)]
		_biome.text = biome
		if biome != _last_biome and _last_biome != "":
			show_notification("Entraste a: %s" % biome)
		_last_biome = biome
		_update_build_hint(player, world)
	(_bars["stamina"][0] as ProgressBar).value = Game.stamina


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
	var label := UIStyle.label(text, 18, color.lightened(0.3))
	_pickup_box.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)
