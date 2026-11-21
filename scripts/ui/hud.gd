extends CanvasLayer
## HUD del juego: misión actual, jugadores conectados, mira, avisos y menú de pausa.
## El inventario y la barra rápida están en inventory_ui.gd.

const InventoryUI := preload("res://scripts/ui/inventory_ui.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")

var _root: Control
var _quest_title: Label
var _quest_description: Label
var _quest_objectives: VBoxContainer
var _players_label: Label
var _hint: Label
var _pickup_box: VBoxContainer
var _notifications: VBoxContainer
var _pause_overlay: Control
var _last_totals: Dictionary = {}
var _crosshair: Label
var _fps_label: Label
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
	_build_pause_menu()

	Game.inventory_changed.connect(_on_inventory_changed)
	Game.notify.connect(show_notification)
	Game.interaction_hint_changed.connect(func(text: String): _hint.text = text)
	Game.pause_toggled.connect(func(is_open: bool): _pause_overlay.visible = is_open)
	Game.inventory_toggled.connect(func(is_open: bool): _crosshair.visible = not is_open)
	QuestManager.quest_changed.connect(_refresh_quest)
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
	panel.offset_left = -380
	panel.offset_right = -20
	panel.offset_top = 20
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(UIStyle.label("MISIÓN", 13, UIStyle.TEXT_DIM))
	_quest_title = UIStyle.label("", 22, UIStyle.ACCENT)
	box.add_child(_quest_title)
	_quest_description = UIStyle.label("", 15, UIStyle.TEXT_DIM)
	_quest_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_description.custom_minimum_size = Vector2(330, 0)
	box.add_child(_quest_description)
	_quest_objectives = VBoxContainer.new()
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

	var help := UIStyle.label("WASD mover · Shift correr · Espacio saltar · Click golpear · E recoger\n1-6 / rueda: barra rápida · V cámara · Tab inventario · Esc menú", 13, UIStyle.TEXT_DIM)
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


func _refresh_quest() -> void:
	for child in _quest_objectives.get_children():
		child.queue_free()
	if QuestManager.is_finished():
		_quest_title.text = "Demo completada"
		_quest_description.text = "No hay más misiones por ahora. ¡Exploren la isla!"
		return
	var quest := QuestManager.current_quest()
	_quest_title.text = quest["title"]
	_quest_description.text = quest["description"]
	var objectives: Array = quest["objectives"]
	for i in objectives.size():
		var objective: Dictionary = objectives[i]
		var current: int = QuestManager.progress[i] if i < QuestManager.progress.size() else 0
		var done: bool = current >= objective["amount"]
		var text: String
		if objective["type"] == "collect":
			text = "• %s: %d / %d" % [objective["text"], current, objective["amount"]]
		else:
			text = "• %s%s" % [objective["text"], " (hecho)" if done else ""]
		_quest_objectives.add_child(UIStyle.label(text, 17, UIStyle.SUCCESS if done else UIStyle.TEXT))


func _process(_delta: float) -> void:
	_fps_label.visible = Settings.get_value("show_fps")
	if _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


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
