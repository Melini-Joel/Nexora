class_name TerrainGenerator
extends StaticBody3D
## Genera una isla low-poly (sombreado plano y colores por vértice) a partir de una semilla.
## Todos los jugadores usan la misma semilla, así que generan exactamente el mismo terreno
## sin tener que enviarlo por la red.

const SIZE := 256.0  ## Lado de la isla en metros.
const RESOLUTION := 128  ## Cuadrados por lado (más = más detalle, menos rendimiento).
const MAX_HEIGHT := 48.0
const WATER_LEVEL := 1.0
const SPAWN_HEIGHT := 5.0
const SPAWN_RADIUS := 12.0  ## Zona plana del campamento inicial.

const SAND := Color(0.86, 0.78, 0.55)
const SEABED := Color(0.55, 0.5, 0.4)
const GRASS := Color(0.45, 0.68, 0.3)
const GRASS_DARK := Color(0.28, 0.5, 0.24)
const ROCK := Color(0.5, 0.48, 0.45)
const SNOW := Color(0.94, 0.95, 0.98)

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()
var _heights := PackedFloat32Array()
var _faces := PackedVector3Array()
var _step := SIZE / RESOLUTION


func generate(world_seed: int) -> void:
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.006
	_noise.fractal_octaves = 4
	_detail.seed = world_seed + 1
	_detail.frequency = 0.05
	_color_noise.seed = world_seed + 2
	_color_noise.frequency = 0.03

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


func find_highest_point(max_radius: float) -> Vector3:
	var best := Vector3(0, -INF, 0)
	var half := SIZE * 0.5
	for iz in RESOLUTION + 1:
		for ix in RESOLUTION + 1:
			var x := -half + ix * _step
			var z := -half + iz * _step
			if Vector2(x, z).length() > max_radius:
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
	var h := pow(n, 1.8) * MAX_HEIGHT - 4.0
	h += _detail.get_noise_2d(x, z) * 0.8
	# Forma de isla: hacia los bordes el terreno se hunde bajo el agua.
	var edge := smoothstep(0.0, 1.0, clampf((1.0 - distance / (SIZE * 0.5)) / 0.35, 0.0, 1.0))
	h = lerpf(-14.0, h, edge)
	# Zona plana para el campamento donde aparecen los jugadores.
	var spawn_blend := smoothstep(SPAWN_RADIUS, SPAWN_RADIUS * 2.2, distance)
	return lerpf(SPAWN_HEIGHT, h, spawn_blend)


func _compute_heights() -> void:
	var half := SIZE * 0.5
	_heights.resize((RESOLUTION + 1) * (RESOLUTION + 1))
	for iz in RESOLUTION + 1:
		for ix in RESOLUTION + 1:
			_heights[iz * (RESOLUTION + 1) + ix] = _height_function(-half + ix * _step, -half + iz * _step)


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
			_add_triangle(st, a, b, c)
			_add_triangle(st, b, d, c)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	st.set_material(material)
	return st.commit()


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Una normal por triángulo = estilo low-poly facetado.
	var normal := (c - a).cross(b - a).normalized()
	var color := _triangle_color(a, b, c, normal)
	_faces.append_array([a, b, c])
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(v)


func _triangle_color(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> Color:
	var center := (a + b + c) / 3.0
	var h := center.y
	var color: Color
	if h < WATER_LEVEL - 0.5:
		color = SEABED
	elif h < WATER_LEVEL + 0.7:
		color = SAND
	elif normal.y < 0.75:
		color = ROCK
	elif h > 27.0:
		color = SNOW
	elif h > 17.0:
		color = GRASS_DARK.lerp(ROCK, clampf((h - 17.0) / 10.0, 0.0, 1.0))
	else:
		color = GRASS.lerp(GRASS_DARK, clampf(h / 17.0, 0.0, 1.0))
	var variation := _color_noise.get_noise_2d(center.x, center.z) * 0.08
	color = color.lightened(variation) if variation > 0.0 else color.darkened(-variation)
	# Los colores de vértice se pasan en espacio lineal (igual en Forward+ y Compatibility).
	return color.srgb_to_linear()
