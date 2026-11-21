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

## Copia local del inventario (la verdad la tiene el servidor).
var inventory: Array = []
var selected_slot := 0
var inventory_open := false
var ui_open := false  ## Menú de pausa abierto.
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


func load_ratio() -> float:
	return carried_weight() / Inventory.CAPACITY_KG


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
	return not ui_open and not Cinematics.playing


## ¿Se puede mirar con el mouse, golpear y recoger?
func can_act() -> bool:
	return can_control_player() and not inventory_open


func set_inventory_open(is_open: bool) -> void:
	inventory_open = is_open
	_update_mouse()
	inventory_toggled.emit(is_open)


func set_pause_open(is_open: bool) -> void:
	if is_open and inventory_open:
		set_inventory_open(false)
	ui_open = is_open
	_update_mouse()
	pause_toggled.emit(is_open)


func _update_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (ui_open or inventory_open) else Input.MOUSE_MODE_CAPTURED


func reset() -> void:
	inventory = []
	selected_slot = 0
	inventory_open = false
	ui_open = false
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
