extends Node
## Opciones del jugador: pantalla, cámara y gráficos.
## Se guardan en user://settings.cfg y se cargan al abrir el juego.

signal changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"window_mode": "maximized",
	"resolution": "1280x720",
	"vsync": true,
	"ui_scale": 1.0,
	"show_fps": false,
	"camera_distance": 4.5,
	"camera_height": 1.6,
	"camera_shoulder": 0.5,
	"fov": 70.0,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"quality": "medium",
	"player_name": "",
	"music_volume": 0.6,
	"sfx_volume": 0.8,
	"last_ip": "127.0.0.1",
}
const WINDOW_MODES := {"windowed": "Ventana", "maximized": "Ventana maximizada", "fullscreen": "Pantalla completa"}
const QUALITY_LEVELS := {"low": "Baja (más FPS)", "medium": "Media", "high": "Alta", "ultra": "Ultra (PC potente)"}
const RESOLUTIONS := ["1024x576", "1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
## Distancias de cámara que se recorren con la tecla V.
const CAMERA_PRESETS := {2.8: "Cerca", 4.5: "Normal", 7.0: "Lejos"}
const DISPLAY_KEYS := ["window_mode", "resolution", "vsync", "ui_scale", "quality"]

var values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	load_settings()
	apply_display()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	if key in DISPLAY_KEYS:
		apply_display()
	changed.emit()


func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply_display()
	changed.emit()
	save_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in DEFAULTS:
		values[key] = config.get_value("settings", key, DEFAULTS[key])


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("settings", key, values[key])
	config.save(PATH)


## Sensibilidad real del mouse (radianes por pixel).
func mouse_sensitivity() -> float:
	return 0.0025 * float(get_value("mouse_sensitivity"))


## Tecla V: pasa a la siguiente distancia de cámara. Devuelve el nombre del modo.
func cycle_camera_distance() -> String:
	var presets: Array = CAMERA_PRESETS.keys()
	var current: float = get_value("camera_distance")
	var next: float = presets[0]
	for preset: float in presets:
		if preset > current + 0.05:
			next = preset
			break
	set_value("camera_distance", next)
	save_settings()
	return CAMERA_PRESETS[next]


## Resoluciones que entran en la pantalla del jugador.
func available_resolutions() -> Array:
	var screen := DisplayServer.screen_get_size()
	var result: Array = []
	for res: String in RESOLUTIONS:
		var size := _parse_resolution(res)
		if size.x <= screen.x and size.y <= screen.y:
			result.append(res)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	return result


func apply_display() -> void:
	var root := get_tree().root
	root.content_scale_factor = float(get_value("ui_scale"))
	_apply_graphics(root)
	if DisplayServer.get_name() == "headless":
		return
	match get_value("window_mode"):
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"maximized":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var screen_size := DisplayServer.screen_get_size()
			var size := _parse_resolution(get_value("resolution"))
			# Nunca más grande que la pantalla (dejamos lugar para la barra de tareas).
			size = Vector2i(mini(size.x, screen_size.x), mini(size.y, screen_size.y - 60))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen_size - size) / 2)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)


func _apply_graphics(root: Viewport) -> void:
	match get_value("quality"):
		"low":
			root.msaa_3d = Viewport.MSAA_DISABLED
			root.scaling_3d_scale = 0.75
		"high", "ultra":
			root.msaa_3d = Viewport.MSAA_4X
			root.scaling_3d_scale = 1.0
		_:
			root.msaa_3d = Viewport.MSAA_2X
			root.scaling_3d_scale = 1.0


func _parse_resolution(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2:
		return Vector2i(1280, 720)
	return Vector2i(parts[0].to_int(), parts[1].to_int())
