class_name DecorField
extends Node3D
## Vegetación y detalles decorativos (sin interacción): helechos, flores, hongos, piedritas,
## troncos caídos, juncos, arbustos y matorrales secos. Igual que el pasto, se arma por
## parcelas de 32 m con MultiMesh (miles de objetos en pocas llamadas de dibujo) y solo se
## dibuja cerca de la cámara.

const CHUNK := 32.0
## tipo -> [intentos por parcela, {bioma: probabilidad}, distancia visible, condición]
const TYPES := {
	"fern": [70, {"forest": 0.7, "meadow": 0.08}, 90.0, ""],
	"flower_white": [40, {"meadow": 0.5, "forest": 0.05}, 70.0, ""],
	"flower_yellow": [40, {"meadow": 0.5}, 70.0, ""],
	"flower_purple": [35, {"meadow": 0.45, "forest": 0.08}, 70.0, ""],
	"flower_red": [25, {"meadow": 0.4}, 70.0, ""],
	"mushroom": [20, {"forest": 0.6}, 60.0, ""],
	"pebbles": [30, {"meadow": 0.3, "forest": 0.3, "desert": 0.7, "tundra": 0.5}, 70.0, ""],
	"log": [3, {"forest": 0.5, "meadow": 0.1}, 140.0, "flat"],
	"reeds": [60, {"meadow": 1.0, "forest": 1.0, "desert": 0.4}, 90.0, "shore"],
	"bush": [16, {"meadow": 0.5, "forest": 0.7}, 130.0, ""],
	"dry_shrub": [22, {"desert": 0.7, "tundra": 0.3}, 110.0, ""],
}

var terrain: TerrainGenerator
var _pending: Array[Vector2i] = []
var _seed := 0
var _density := 1.0
var _clear_check: Callable


func setup(p_terrain: TerrainGenerator, world_seed: int, clear_check: Callable = Callable()) -> void:
	terrain = p_terrain
	_seed = world_seed
	_clear_check = clear_check
	_density = {"low": 0.4, "medium": 0.75, "high": 1.0, "ultra": 1.3}.get(Settings.get_value("quality"), 0.75)
	var count := int(TerrainGenerator.SIZE / CHUNK)
	for cz in count:
		for cx in count:
			_pending.append(Vector2i(cx, cz))


func _process(_delta: float) -> void:
	if _pending.is_empty() or terrain == null:
		return
	var camera := get_viewport().get_camera_3d()
	var focus := camera.global_position if camera else Vector3.ZERO
	var best_index := 0
	var best_distance := INF
	for i in _pending.size():
		var center := _chunk_origin(_pending[i]) + Vector2.ONE * CHUNK * 0.5
		var d := center.distance_squared_to(Vector2(focus.x, focus.z))
		if d < best_distance:
			best_distance = d
			best_index = i
	var chunk: Vector2i = _pending[best_index]
	_pending.remove_at(best_index)
	_build_chunk(chunk)


func _chunk_origin(chunk: Vector2i) -> Vector2:
	var half := TerrainGenerator.SIZE * 0.5
	return Vector2(-half + chunk.x * CHUNK, -half + chunk.y * CHUNK)


func _build_chunk(chunk: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + chunk.x * 92821 + chunk.y * 68917 + 5
	var origin := _chunk_origin(chunk)
	for type: String in TYPES:
		var info: Array = TYPES[type]
		var transforms: Array[Transform3D] = []
		for i in int(info[0] * _density):
			var p := origin + Vector2(rng.randf() * CHUNK, rng.randf() * CHUNK)
			var roll := rng.randf()
			var scale := rng.randf_range(0.75, 1.3)
			var yaw := rng.randf() * TAU
			var h := terrain.get_height(p.x, p.y)
			var condition: String = info[3]
			if condition == "shore":
				if h < TerrainGenerator.WATER_LEVEL - 0.4 or h > TerrainGenerator.WATER_LEVEL + 0.9:
					continue
			elif h < TerrainGenerator.WATER_LEVEL + 0.7:
				continue
			if roll > info[1].get(terrain.get_biome(p.x, p.y), 0.0):
				continue
			if h > TerrainGenerator.SNOW_HEIGHT + 3.0 and type != "pebbles":
				continue
			var slope := absf(terrain.get_height(p.x + 1.0, p.y) - h) + absf(terrain.get_height(p.x, p.y + 1.0) - h)
			if slope > (0.4 if condition == "flat" else 1.1):
				continue
			if _clear_check.is_valid() and _clear_check.call(p):
				continue
			transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(p.x, h - 0.03, p.y)))
		if transforms.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = PropFactory.decor_mesh(type)
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if type in ["log", "bush"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = info[2]
		add_child(instance)
