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


## Malla suave: cada vértice tiene su normal (promedio del relieve) y su color, así las
## laderas y los cambios de bioma se ven graduales y no facetados.
func _build_mesh() -> ArrayMesh:
	var count := RESOLUTION + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(count * count)
	normals.resize(count * count)
	colors.resize(count * count)
	for iz in count:
		for ix in count:
			var i := iz * count + ix
			var v := _vertex(ix, iz)
			var dx := _h(mini(ix + 1, RESOLUTION), iz) - _h(maxi(ix - 1, 0), iz)
			var dz := _h(ix, mini(iz + 1, RESOLUTION)) - _h(ix, maxi(iz - 1, 0))
			var normal := Vector3(-dx, 2.0 * _step, -dz).normalized()
			vertices[i] = v
			normals[i] = normal
			colors[i] = _vertex_color(v, normal, _biomes[i])
	var indices := PackedInt32Array()
	indices.resize(RESOLUTION * RESOLUTION * 6)
	var k := 0
	for iz in RESOLUTION:
		for ix in RESOLUTION:
			var a := iz * count + ix
			var b := a + 1
			var c := a + count
			var d := c + 1
			for index in [a, b, c, b, d, c]:
				indices[k] = index
				k += 1
			_faces.append_array([vertices[a], vertices[b], vertices[c], vertices[b], vertices[d], vertices[c]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.generate_mipmaps = true
	material.set_shader_parameter("detail_noise", texture)
	mesh.surface_set_material(0, material)
	return mesh


func _vertex_color(v: Vector3, normal: Vector3, biome: int) -> Color:
	var h := v.y
	var colors: Array = BIOME_COLORS[biome]
	var color: Color
	var variation := _color_noise.get_noise_2d(v.x, v.z)
	if h < WATER_LEVEL - 0.5:
		color = SEABED
	elif h < WATER_LEVEL + 0.8 and biome != Biome.TUNDRA:
		color = SAND.lerp(colors[0], clampf((h - WATER_LEVEL) / 1.6, 0.0, 0.4))
	else:
		var t := clampf(h / SNOW_HEIGHT + variation * 0.3, 0.0, 1.0)
		color = (colors[0] as Color).lerp(colors[1], t)
		# Las pendientes fuertes muestran roca, con una transición suave.
		var rock := ROCK.lightened(0.15) if biome == Biome.TUNDRA else (Color(0.76, 0.56, 0.38) if biome == Biome.DESERT else ROCK)
		color = color.lerp(rock, smoothstep(0.82, 0.66, normal.y))
		if h > SNOW_HEIGHT + 2.0:
			color = color.lerp(SNOW, smoothstep(SNOW_HEIGHT + 2.0, SNOW_HEIGHT + 7.0, h) * smoothstep(0.6, 0.8, normal.y))
	color = color.lightened(variation * 0.06) if variation > 0.0 else color.darkened(-variation * 0.08)
	# Los colores de vértice se pasan en espacio lineal (igual en Forward+ y Compatibility).
	return color.srgb_to_linear()
