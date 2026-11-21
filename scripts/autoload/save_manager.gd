extends Node
## Guardado de partidas. Solo guarda el host (que es el servidor y tiene el estado real).
##
## Cada mundo es un archivo en user://saves/<id>.save (en Windows:
## %APPDATA%/Godot/app_userdata/NEXORA/saves). Se guarda con store_var, que conserva
## los tipos de Godot (Vector3, enteros, diccionarios) sin conversiones.
##
## Se guarda solo: cada AUTOSAVE_SECONDS, al salir al menú y al cerrar el juego.

signal saved(ok: bool)

const DIR := "user://saves/"
const AUTOSAVE_SECONDS := 180.0
const VERSION := 1

var current_slot := ""  ## Archivo del mundo que se está jugando ("" = ninguno).
var current_name := ""
var play_time := 0.0  ## Segundos jugados en este mundo.
var _autosave_timer := AUTOSAVE_SECONDS


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## Lista de mundos guardados, el más reciente primero.
## Cada uno: {"slot", "name", "day", "play_time", "last_played"}
func list_saves() -> Array:
	var result: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return result
	for file in dir.get_files():
		if not file.ends_with(".save"):
			continue
		var data := load_data(file.trim_suffix(".save"))
		if data.is_empty():
			continue
		var meta: Dictionary = data.get("meta", {})
		result.append({
			"slot": file.trim_suffix(".save"), "name": meta.get("name", "Mundo"),
			"day": data.get("day", 1), "play_time": meta.get("play_time", 0.0),
			"last_played": meta.get("last_played", 0),
		})
	result.sort_custom(func(a, b): return a["last_played"] > b["last_played"])
	return result


func load_data(slot: String) -> Dictionary:
	var file := FileAccess.open(DIR + slot + ".save", FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var()
	return data if data is Dictionary else {}


func delete_save(slot: String) -> void:
	DirAccess.remove_absolute(DIR + slot + ".save")


## Empieza a jugar un mundo (nuevo o cargado). slot = "" crea uno nuevo.
func begin(slot: String, world_name: String, previous_play_time: float = 0.0) -> void:
	if slot == "":
		var clean := world_name.to_lower().validate_filename().replace(" ", "_").left(24)
		slot = "%s_%d" % [clean if clean != "" else "mundo", int(Time.get_unix_time_from_system())]
	current_slot = slot
	current_name = world_name
	play_time = previous_play_time
	_autosave_timer = AUTOSAVE_SECONDS


func end() -> void:
	current_slot = ""
	current_name = ""


func is_active() -> bool:
	return current_slot != "" and Network.is_online() and multiplayer.is_server()


## Guarda el mundo actual. Devuelve true si salió bien.
func save_game() -> bool:
	if not is_active():
		return false
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.generated:
		return false
	var data: Dictionary = world.build_save()
	data["meta"] = {
		"version": VERSION, "name": current_name, "play_time": play_time,
		"last_played": int(Time.get_unix_time_from_system()),
	}
	var file := FileAccess.open(DIR + current_slot + ".save", FileAccess.WRITE)
	var ok := file != null
	if ok:
		file.store_var(data)
		file.close()
	saved.emit(ok)
	return ok


func _process(delta: float) -> void:
	if not is_active():
		return
	play_time += delta
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = AUTOSAVE_SECONDS
		if save_game():
			Network.announce.rpc("Partida guardada automáticamente")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()  # Al cerrar la ventana del juego.


## "1 h 20 min", "12 min"...
static func format_play_time(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	if minutes < 60:
		return "%d min" % maxi(minutes, 1)
	return "%d h %d min" % [minutes / 60, minutes % 60]


## "hace 5 min", "hace 2 h", "hace 3 días"...
static func format_ago(unix_time: int) -> String:
	var seconds := int(Time.get_unix_time_from_system()) - unix_time
	if seconds < 3600:
		return "hace %d min" % maxi(seconds / 60, 1)
	if seconds < 86400:
		return "hace %d h" % (seconds / 3600)
	return "hace %d días" % (seconds / 86400)
