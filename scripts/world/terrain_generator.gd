class_name TerrainGenerator
extends StaticBody3D
## Genera una isla low-poly de 512 x 512 m con biomas (pradera, bosque, desierto y tundra)
## a partir de una semilla. Todos los jugadores usan la misma semilla, así que generan
## exactamente el mismo terreno sin tener que enviarlo por la red.

const SIZE := 512.0  ## Lado de la isla en metros.
const RESOLUTION := 200  ## Cuadrados por lado (más = más detalle, menos rendimiento).
const MAX_HEIGHT := 70.0
const WATER_LEVEL := 1.0
const SPAWN_HEIGHT := 5.0
const SPAWN_RADIUS := 14.0  ## Zona plana del campamento inicial.
const SNOW_HEIGHT := 38.0

enum Biome { MEADOW, FOREST, DESERT, TUNDRA }
const BIOME_IDS := ["meadow", "forest", "desert", "tundra"]
const BIOME_NAMES := {"meadow": "Pradera", "forest": "Bosque", "desert": "Desierto", "tundra": "Tundra nevada"}

const SAND := Color(0.86, 0.78, 0.55)
const SEABED := Color(0.5, 0.47, 0.38)
const ROCK := Color(0.5, 0.48, 0.45)
const SNOW := Color(0.92, 0.94, 0.98)
const BIOME_COLORS := {
	Biome.MEADOW: [Color(0.47, 0.7, 0.3), Color(0.33, 0.56, 0.24)],
	Biome.FOREST: [Color(0.3, 0.52, 0.23), Color(0.2, 0.4, 0.2)],
	Biome.DESERT: [Color(0.9, 0.78, 0.52), Color(0.8, 0.62, 0.4)],
	Biome.TUNDRA: [Color(0.86, 0.9, 0.94), Color(0.7, 0.76, 0.8)],
}

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _heights := PackedFloat32Array()
var _biomes := PackedByteArray()
var _faces := PackedVector3Array()
var _step := SIZE / RESOLUTION


func generate(world_seed: int) -> void:
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 5
	_detail.seed = world_seed + 1
	_detail.frequency = 0.04
	_color_noise.seed = world_seed + 2
	_color_noise.frequency = 0.03
	_temperature.seed = world_seed + 3
	_temperature.frequency = 0.0055
	_moisture.seed = world_seed + 4
	_moisture.frequency = 0.0065

	_compute_heights()
	var mesh := _build_mesh()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	# La colisión se arma con los mismos triángulos (no depende del renderizador).
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	_faces = PackedVector3Array()  # Ya no hace falta: liberamos memoria.


## Altura exacta del terreno (sigue los mismos triángulos que la malla).
func get_height(x: float, z: float) -> float:
	var half := SIZE * 0.5
	var gx := clampf((x + half) / _step, 0.0, RESOLUTION - 0.001)
	var gz := clampf((z + half) / _step, 0.0, RESOLUTION - 0.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var ha := _h(ix, iz)
	var hb := _h(ix + 1, iz)
	var hc := _h(ix, iz + 1)
	var hd := _h(ix + 1, iz + 1)
	if fx + fz <= 1.0:
		return ha + (hb - ha) * fx + (hc - ha) * fz
	return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)


## 0 = plano, 1 = vertical.
func get_slope(x: float, z: float) -> float:
	var dx := get_height(x + 1.0, z) - get_height(x - 1.0, z)
	var dz := get_height(x, z + 1.0) - get_height(x, z - 1.0)
	return 1.0 - Vector3(-dx * 0.5, 1.0, -dz * 0.5).normalized().y


## Bioma en un punto: "meadow", "forest", "desert" o "tundra".
func get_biome(x: float, z: float) -> String:
	var half := SIZE * 0.5
	var ix := clampi(roundi((x + half) / _step), 0, RESOLUTION)
	var iz := clampi(roundi((z + half) / _step), 0, RESOLUTION)
	return BIOME_IDS[_biomes[iz * (RESOLUTION + 1) + ix]]


func find_highest_point(max_radius: float, avoid: Vector2 = Vector2.INF, avoid_radius: float = 0.0) -> Vector3:
	var best := Vector3(0, -INF, 0)
	var half := SIZE * 0.5
	for iz in RESOLUTION + 1:
		for ix in RESOLUTION + 1:
			var x := -half + ix * _step
			var z := -half + iz * _step
			if Vector2(x, z).length() > max_radius:
				continue
			if avoid != Vector2.INF and Vector2(x, z).distance_to(avoid) < avoid_radius:
				continue
			var h := _h(ix, iz)
			if h > best.y:
				best = Vector3(x, h, z)
	return best


func _h(ix: int, iz: int) -> float:
	return _heights[iz * (RESOLUTION + 1) + ix]


func _height_function(x: float, z: float) -> float:
	var distance := Vector2(x, z).length()
	var n := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	var h := pow(n, 2.0) * MAX_HEIGHT * 1.15 - 5.0
	h += _detail.get_noise_2d(x, z) * 1.0
	# Forma de isla: hacia los bordes el terreno se hunde bajo el agua.
	var edge := smoothstep(0.0, 1.0, clampf((1.0 - distance / (SIZE * 0.5)) / 0.3, 0.0, 1.0))
	h = lerpf(-16.0, h, edge)
	# Zona plana para el campamento donde aparecen los jugadores.
	var spawn_blend := smoothstep(SPAWN_RADIUS, SPAWN_RADIUS * 2.5, distance)
	return lerpf(SPAWN_HEIGHT, h, spawn_blend)


func _biome_function(x: float, z: float, h: float) -> int:
	if h > SNOW_HEIGHT:
		return Biome.TUNDRA
	if Vector2(x, z).length() < 50.0:
		return Biome.MEADOW  # Alrededor del campamento siempre es pradera.
	var t := _temperature.get_noise_2d(x, z)
	var m := _moisture.get_noise_2d(x, z)
	if t < -0.17:
		return Biome.TUNDRA
	if t > 0.13 and m < 0.08:
		return Biome.DESERT
	if m > 0.02:
		return Biome.FOREST
	return Biome.MEADOW


func _compute_heights() -> void:
	var half := SIZE * 0.5
	var count := (RESOLUTION + 1) * (RESOLUTION + 1)
	_heights.resize(count)
	_biomes.resize(count)
	for iz in RESOLUTION + 1:
		for ix in RESOLUTION + 1:
			var x := -half + ix * _step
			var z := -half + iz * _step
			var h := _height_function(x, z)
			_heights[iz * (RESOLUTION + 1) + ix] = h
			_biomes[iz * (RESOLUTION + 1) + ix] = _biome_function(x, z, h)


func _vertex(ix: int, iz: int) -> Vector3:
	var half := SIZE * 0.5
	return Vector3(-half + ix * _step, _h(ix, iz), -half + iz * _step)


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in RESOLUTION:
		for ix in RESOLUTION:
			var a := _vertex(ix, iz)
			var b := _vertex(ix + 1, iz)
			var c := _vertex(ix, iz + 1)
			var d := _vertex(ix + 1, iz + 1)
			var biome: int = _biomes[iz * (RESOLUTION + 1) + ix]
			_add_triangle(st, a, b, c, biome)
			_add_triangle(st, b, d, c, _biomes[(iz + 1) * (RESOLUTION + 1) + ix + 1])
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	st.set_material(material)
	return st.commit()


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, biome: int) -> void:
	# Una normal por triángulo = estilo low-poly facetado.
	var normal := (c - a).cross(b - a).normalized()
	var color := _triangle_color(a, b, c, normal, biome)
	_faces.append_array([a, b, c])
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(v)


func _triangle_color(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, biome: int) -> Color:
	var center := (a + b + c) / 3.0
	var h := center.y
	var colors: Array = BIOME_COLORS[biome]
	var color: Color
	if h < WATER_LEVEL - 0.5:
		color = SEABED
	elif h < WATER_LEVEL + 0.8 and biome != Biome.TUNDRA:
		color = SAND
	elif normal.y < 0.72:
		color = ROCK if biome != Biome.DESERT else Color(0.76, 0.56, 0.38)
		if biome == Biome.TUNDRA:
			color = ROCK.lightened(0.15)
	elif h > SNOW_HEIGHT + 4.0:
		color = SNOW
	else:
		var t := clampf(h / SNOW_HEIGHT + _color_noise.get_noise_2d(center.x * 0.5, center.z * 0.5) * 0.3, 0.0, 1.0)
		color = (colors[0] as Color).lerp(colors[1], t)
	var variation := _color_noise.get_noise_2d(center.x, center.z) * 0.07
	color = color.lightened(variation) if variation > 0.0 else color.darkened(-variation)
	# Los colores de vértice se pasan en espacio lineal (igual en Forward+ y Compatibility).
	return color.srgb_to_linear()
