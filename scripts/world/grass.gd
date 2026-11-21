class_name GrassField
extends Node3D
## Pasto denso que se mueve con el viento, dividido en parcelas de 32 x 32 m.
## Cada parcela es un MultiMesh (miles de matas en una sola llamada de dibujo) que solo
## se dibuja cerca de la cámara. Las parcelas se generan de a poco, empezando por las
## más cercanas al jugador, para no trabar el juego al cargar.

const CHUNK := 32.0
const DENSITY_BY_BIOME := {"meadow": 1.0, "forest": 0.55, "desert": 0.05, "tundra": 0.12}
const TINT_BY_BIOME := {
	"meadow": Color(1.0, 1.0, 1.0),
	"forest": Color(0.78, 0.9, 0.8),
	"desert": Color(1.45, 1.2, 0.6),
	"tundra": Color(1.1, 1.15, 1.1),
}
const QUALITY := {"low": [220, 40.0], "medium": [600, 70.0], "high": [1000, 100.0], "ultra": [1500, 130.0]}  ## [matas por parcela, distancia visible]

var terrain: TerrainGenerator
var _pending: Array[Vector2i] = []
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _per_chunk := 480
var _view_distance := 65.0
var _seed := 0


func setup(p_terrain: TerrainGenerator, world_seed: int) -> void:
	terrain = p_terrain
	_seed = world_seed
	var quality: Array = QUALITY.get(Settings.get_value("quality"), QUALITY["medium"])
	_per_chunk = quality[0]
	_view_distance = quality[1]
	_mesh = _build_tuft_mesh()
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/grass.gdshader")
	var count := int(TerrainGenerator.SIZE / CHUNK)
	for cz in count:
		for cx in count:
			_pending.append(Vector2i(cx, cz))


func _process(_delta: float) -> void:
	if _pending.is_empty() or terrain == null:
		return
	# Generar primero las parcelas más cercanas a la cámara.
	var camera := get_viewport().get_camera_3d()
	var focus := camera.global_position if camera else Vector3.ZERO
	var best_index := 0
	var best_distance := INF
	for i in _pending.size():
		var d := _chunk_center(_pending[i]).distance_squared_to(Vector2(focus.x, focus.z))
		if d < best_distance:
			best_distance = d
			best_index = i
	var chunk: Vector2i = _pending[best_index]
	_pending.remove_at(best_index)
	_build_chunk(chunk)


func _chunk_center(chunk: Vector2i) -> Vector2:
	var half := TerrainGenerator.SIZE * 0.5
	return Vector2(-half + (chunk.x + 0.5) * CHUNK, -half + (chunk.y + 0.5) * CHUNK)


func _build_chunk(chunk: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + chunk.x * 7919 + chunk.y * 104729
	var half := TerrainGenerator.SIZE * 0.5
	var origin := Vector2(-half + chunk.x * CHUNK, -half + chunk.y * CHUNK)
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in _per_chunk:
		var p := origin + Vector2(rng.randf() * CHUNK, rng.randf() * CHUNK)
		var biome := terrain.get_biome(p.x, p.y)
		var keep := rng.randf()
		var scale := rng.randf_range(0.7, 1.3)
		var yaw := rng.randf() * TAU
		if keep > DENSITY_BY_BIOME[biome]:
			continue
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 0.6 or h > TerrainGenerator.SNOW_HEIGHT:
			continue
		var dx := terrain.get_height(p.x + 1.0, p.y) - h
		var dz := terrain.get_height(p.x, p.y + 1.0) - h
		if absf(dx) > 0.7 or absf(dz) > 0.7:
			continue  # Muy empinado.
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.25), scale))
		transforms.append(Transform3D(basis, Vector3(p.x, h - 0.02, p.y)))
		var tint: Color = TINT_BY_BIOME[biome]
		colors.append(tint * rng.randf_range(0.85, 1.1))
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = _view_distance + CHUNK * 0.5
	add_child(instance)


## Una mata de pasto: 5 hojas finas en distintas direcciones.
func _build_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for blade in 5:
		var angle := TAU * blade / 5.0 + rng.randf() * 0.5
		var offset := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.02, 0.12)
		var side := Vector3(-sin(angle), 0, cos(angle)) * 0.035
		var height := rng.randf_range(0.35, 0.6)
		var lean := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.05, 0.15)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(offset - side)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(offset + side)
		st.set_uv(Vector2(0, 1))
		st.add_vertex(offset + lean + Vector3(0, height, 0))
	st.generate_normals()
	return st.commit()
