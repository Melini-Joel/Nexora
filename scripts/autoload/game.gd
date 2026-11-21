extends Node
## Estado global del lado local: inventario, jugador local, menú de pausa y controles.

signal inventory_changed
signal notify(text: String)
signal interaction_hint_changed(text: String)
signal local_player_spawned(player: Node)
signal world_generated
signal pause_toggled(is_open: bool)
signal quit_to_menu_requested

## Ítems del juego. Agregá nuevos materiales acá (hierro, fibra, cuero...).
const ITEMS := {
	"wood": {"name": "Madera", "color": Color(0.62, 0.42, 0.24)},
	"stone": {"name": "Piedra", "color": Color(0.62, 0.62, 0.64)},
}

var inventory: Dictionary = {}
var local_player: Node = null
var ui_open := false
## Mensaje para mostrar en el menú después de volver (p. ej. "se cayó la conexión").
var pending_menu_message := ""


func _ready() -> void:
	_setup_input()


func item_name(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id)


func item_color(id: String) -> Color:
	return ITEMS.get(id, {}).get("color", Color.WHITE)


func set_inventory(new_inventory: Dictionary) -> void:
	inventory = new_inventory
	inventory_changed.emit()


func can_control_player() -> bool:
	return not ui_open and not Cinematics.playing


func set_pause_open(is_open: bool) -> void:
	ui_open = is_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED
	pause_toggled.emit(is_open)


func reset() -> void:
	inventory = {}
	local_player = null
	ui_open = false


# --- Controles ---------------------------------------------------------------

func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("interact", [KEY_E])
	_add_mouse_button("interact", MOUSE_BUTTON_LEFT)
	_add_keys("pause", [KEY_ESCAPE])
	_add_keys("skip_cinematic", [KEY_ESCAPE, KEY_ENTER, KEY_SPACE])


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
