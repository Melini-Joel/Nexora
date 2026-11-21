extends Node
## Estado global del lado local: inventario, barra rápida, jugador local, menús y controles.

signal inventory_changed
signal selected_slot_changed(index: int)
signal inventory_toggled(is_open: bool)
signal notify(text: String)
signal interaction_hint_changed(text: String)
signal local_player_spawned(player: Node)
signal world_generated
signal pause_toggled(is_open: bool)
signal quit_to_menu_requested
signal craft_queue_changed
signal dialog_requested(npc_id: String)
signal dialog_closed
signal stats_changed
signal player_hit(amount: float)
signal player_died
signal blueprints_changed
signal station_opened(station: String)
signal storage_changed
signal map_open_changed(is_open: bool)
signal progress_changed(leveled: bool)
signal character_open_changed(is_open: bool)

## Copia local del inventario (la verdad la tiene el servidor).
var inventory: Array = []
var selected_slot := 0
var inventory_open := false
var ui_open := false  ## Menú de pausa abierto.
var dialog_open := false  ## Hablando con un NPC.
## Cola de fabricación local: [{recipe, remaining, time_left, time}]
var craft_queue: Array = []
## Estadísticas del jugador local (vida y hambre las manda el servidor; la energía es local).
var health := 100.0
var max_health := 100.0
## Nivel, experiencia, puntos y habilidades (ver SkillDB). Lo manda el servidor.
var progress: Dictionary = SkillDB.empty_progress()
var character_open := false
var hunger := 100.0
var stamina := 100.0
## Estación abierta con E ("" = inventario normal con Tab).
var current_station := ""
## Caja de almacenamiento abierta ("" = ninguna) y su contenido.
var storage_box := ""
var storage_slots: Array = []
var map_open := false
## Dónde murió el jugador por última vez (se marca en el mapa).
var last_death_position := Vector3.INF
var local_player: Node = null
## Mensaje para mostrar en el menú después de volver (p. ej. "se cayó la conexión").
var pending_menu_message := ""


func _ready() -> void:
	_setup_input()


# --- Inventario -----------------------------------------------------------------

func set_inventory(slots: Array) -> void:
	inventory = slots
	inventory_changed.emit()


func get_slot(index: int) -> Dictionary:
	return inventory[index] if index >= 0 and index < inventory.size() else {}


func get_selected_item() -> String:
	return get_slot(selected_slot).get("id", "")


func select_slot(index: int) -> void:
	selected_slot = wrapi(index, 0, Inventory.HOTBAR_SIZE)
	selected_slot_changed.emit(selected_slot)


func carried_weight() -> float:
	return Inventory.weight_of(inventory)


func capacity() -> float:
	return Inventory.capacity_for(inventory) + SkillDB.carry_bonus(progress)


func max_stamina() -> float:
	return SkillDB.max_stamina(progress)


func set_progress(data: Dictionary, leveled: bool) -> void:
	progress = data
	if leveled:
		Sound.play("quest_complete")
		notify.emit("¡Subiste a nivel %d! Tenés %d punto(s) para mejorar: apretá C." % [data["level"], data["points"]])
	progress_changed.emit(leveled)


func set_character_open(is_open: bool) -> void:
	if is_open and inventory_open:
		set_inventory_open(false)
	if is_open and map_open:
		set_map_open(false)
	character_open = is_open
	_update_mouse()
	character_open_changed.emit(is_open)


func load_ratio() -> float:
	return carried_weight() / capacity()


func set_stats(new_health: float, new_hunger: float, new_max_health: float = 100.0) -> void:
	health = new_health
	hunger = new_hunger
	max_health = new_max_health
	stats_changed.emit()


## Abre el inventario mostrando las recetas de una estación (mesa, horno, fogata).
func open_station(station: String) -> void:
	current_station = station
	set_inventory_open(true)
	station_opened.emit(station)


func set_storage(box_name: String, slots: Array, opening: bool) -> void:
	if not opening and box_name != storage_box:
		return  # Llegó una actualización de una caja que ya cerré.
	storage_box = box_name
	storage_slots = slots
	if opening and not inventory_open:
		set_inventory_open(true)
	storage_changed.emit()


func get_storage_slot(index: int) -> Dictionary:
	return storage_slots[index] if index >= 0 and index < storage_slots.size() else {}


func set_map_open(is_open: bool) -> void:
	if is_open and inventory_open:
		set_inventory_open(false)
	map_open = is_open
	_update_mouse()
	map_open_changed.emit(is_open)


func set_craft_queue(queue: Array) -> void:
	if _queue_total(queue) < _queue_total(craft_queue):
		Sound.play("craft_done", Vector3.INF, -4.0)
	craft_queue = queue


func _queue_total(queue: Array) -> int:
	var total := 0
	for job in queue:
		total += int(job["remaining"])
	return total
	craft_queue_changed.emit()


func _process(delta: float) -> void:
	# Cuenta regresiva local de la fabricación (solo para mostrar la barra de progreso).
	if not craft_queue.is_empty():
		craft_queue[0]["time_left"] = maxf(0.0, craft_queue[0]["time_left"] - delta)


func open_dialog(npc_id: String) -> void:
	dialog_open = true
	if inventory_open:
		set_inventory_open(false)
	_update_mouse()
	dialog_requested.emit(npc_id)


func close_dialog() -> void:
	dialog_open = false
	_update_mouse()
	dialog_closed.emit()


func speed_multiplier() -> float:
	return Inventory.speed_multiplier_for(load_ratio())


func is_overloaded() -> bool:
	return load_ratio() > 1.0


## Envía una acción al servidor ("move", "split", "quick_move", "drop", "pickup", "gather").
func send_action(action: String, args: Array = []) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.send_action(action, args)


# --- Estados de la interfaz --------------------------------------------------------

## ¿Se puede mover el personaje? (con el inventario abierto también se puede, como en los survival).
func can_control_player() -> bool:
	return not ui_open and not dialog_open and not Cinematics.playing


## ¿Se puede mirar con el mouse, golpear y recoger?
func can_act() -> bool:
	return can_control_player() and not inventory_open and not map_open and not character_open


func set_inventory_open(is_open: bool) -> void:
	inventory_open = is_open
	if not is_open:
		current_station = ""
		if storage_box != "":
			send_action("storage_close", [storage_box])
			storage_box = ""
			storage_slots = []
			storage_changed.emit()
	_update_mouse()
	inventory_toggled.emit(is_open)


func set_pause_open(is_open: bool) -> void:
	if is_open and inventory_open:
		set_inventory_open(false)
	ui_open = is_open
	_update_mouse()
	pause_toggled.emit(is_open)


func _update_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (ui_open or inventory_open or dialog_open or map_open or character_open) else Input.MOUSE_MODE_CAPTURED


func reset() -> void:
	inventory = []
	selected_slot = 0
	inventory_open = false
	ui_open = false
	dialog_open = false
	craft_queue = []
	health = 100.0
	hunger = 100.0
	stamina = 100.0
	current_station = ""
	storage_box = ""
	storage_slots = []
	map_open = false
	character_open = false
	progress = SkillDB.empty_progress()
	max_health = 100.0
	last_death_position = Vector3.INF
	local_player = null


# --- Controles ---------------------------------------------------------------------

func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("interact", [KEY_E])
	_add_mouse_button("attack", MOUSE_BUTTON_LEFT)
	_add_keys("inventory", [KEY_TAB, KEY_I])
	_add_keys("camera_toggle", [KEY_V])
	_add_keys("build_rotate", [KEY_R])
	_add_keys("map", [KEY_M])
	_add_keys("character", [KEY_C])
	_add_mouse_button("secondary", MOUSE_BUTTON_RIGHT)
	_add_keys("pause", [KEY_ESCAPE])
	_add_keys("skip_cinematic", [KEY_ESCAPE, KEY_ENTER, KEY_SPACE])
	for i in Inventory.HOTBAR_SIZE:
		_add_keys("hotbar_%d" % (i + 1), [KEY_1 + i])


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func _add_mouse_button(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
