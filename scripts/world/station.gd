class_name Station
extends StaticBody3D
## Estación de trabajo interactuable (mesa de trabajo, horno, fogata).
## Al apretar E se abre el inventario con sus recetas.

var station_type := "workbench"
var _flame: Node3D
var _light: OmniLight3D
var _time := 0.0


func _ready() -> void:
	add_to_group("stations")
	_flame = get_node_or_null("Flame")
	_light = get_node_or_null("FireLight")
	_time = randf() * 10.0


func get_interact_text() -> String:
	return "Usar %s" % RecipeDB.STATIONS.get(station_type, station_type)


func _process(delta: float) -> void:
	_time += delta
	if _light:
		_light.light_energy = 2.0 + sin(_time * 17.0) * 0.25 + sin(_time * 7.3) * 0.2
	if _flame:
		_flame.scale = Vector3(1.0 + sin(_time * 11.0) * 0.08, 1.0 + sin(_time * 13.0) * 0.15, 1.0 + cos(_time * 9.0) * 0.08)
