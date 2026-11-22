class_name TerrainGenerator
extends StaticBody3D
## Genera el terreno del mundo a partir de una semilla. Todos los jugadores usan la misma
## semilla, así que generan exactamente el mismo terreno sin tener que enviarlo por la red.
##
## El mundo tiene dos regiones separadas por cientos de metros de mar abierto:
##   · "island":   la isla del naufragio (512 x 512 m, centrada en 0,0) con 4 biomas.
##   · "mainland": el continente de Valdoria (640 x 640 m, al este), con el puerto, el
##                 pueblo, el castillo y el campamento de bandidos. Se llega en barco.

const SIZE := 512.0  ## Lado de la isla en metros.
const RESOLUTION := 200  ## Cuadrados por lado de la isla (más = más detalle, menos rendimiento).
const MAX_HEIGHT := 70.0
const WATER_LEVEL := 1.0
const SPAWN_HEIGHT := 5.0
const SPAWN_RADIUS := 14.0  ## Zona plana del campamento inicial.
const SNOW_HEIGHT := 38.0
const OCEAN_FLOOR := -16.0

const MAINLAND_CENTER := Vector2(1300, 0)
const MAINLAND_SIZE := 640.0
const MAINLAND_RESOLUTION := 240
## Lugares del continente (en coordenadas locales): [centro, radio aplanado, altura (-1 = natural)]
const MAINLAND_SITES := {
	"harbor": [Vector2(-200, 10), 50.0, 3.2],
	"village": [Vector2(20, 150), 54.0, -1.0],
	"castle": [Vector2(140, -100), 46.0, -2.0],  # -2 = meseta elevada
	"bandits": [Vector2(-70, -215), 26.0, -1.0],
}
## Caminos de tierra entre los lugares (locales).
const MAINLAND_ROADS := [
	[Vector2(-200, 10), Vector2(-110, 40)], [Vector2(-110, 40), Vector2(-40, 110)], [Vector2(-40, 110), Vector2(20, 150)],
	[Vector2(-110, 40), Vector2(20, -10)], [Vector2(20, -10), Vector2(90, -60)], [Vector2(90, -60), Vector2(140, -100)],
]
## Campos de trigo alrededor del pueblo (rectángulos locales: posición, tamaño).
const MAINLAND_FIELDS := [
	Rect2(52, 118, 34, 24), Rect2(52, 148, 34, 26), Rect2(-30, 180, 30, 22), Rect2(8, 186, 30, 20),
]

enum Biome { MEADOW, FOREST, DESERT, TUNDRA }
const BIOME_IDS := ["meadow", "forest", "desert", "tundra"]
const BIOME_NAMES := {"meadow": "Pradera", "forest": "Bosque", "desert": "Desierto", "tundra": "Tundra nevada"}
const REGION_NAMES := {"island": "La isla", "mainland": "Valdoria"}

const SAND := Color(0.86, 0.78, 0.55)
const SEABED := Color(0.5, 0.47, 0.38)
const ROCK := Color(0.5, 0.48, 0.45)
const SNOW := Color(0.92, 0.94, 0.98)
const DIRT := Color(0.55, 0.44, 0.31)
const TILLED := Color(0.48, 0.36, 0.22)
const BIOME_COLORS := {
	Biome.MEADOW: [Color(0.47, 0.7, 0.3), Color(0.33, 0.56, 0.24)],
	Biome.FOREST: [Color(0.3, 0.52, 0.23), Color(0.2, 0.4, 0.2)],
	Biome.DESERT: [Color(0.9, 0.78, 0.52), Color(0.8, 0.62, 0.4)],
	Biome.TUNDRA: [Color(0.86, 0.9, 0.94), Color(0.7, 0.76, 0.8)],
}


## Una región del mundo: su propia grilla de alturas y biomas.
class Region:
	var id := ""
	var center := Vector2.ZERO
	var size := 0.0
	var resolution := 0
	var step := 0.0
	var heights := PackedFloat32Array()
	var biomes := PackedByteArray()

	func _init(p_id: String, p_center: Vector2, p_size: float, p_resolution: int) -> void:
		id = p_id
		center = p_center
		size = p_size
		resolution = p_resolution
		step = size / resolution

	func contains(x: float, z: float, margin: float = 0.0) -> bool:
		var half := size * 0.5 + margin
		return absf(x - center.x) <= half and absf(z - center.y) <= half

	func h(ix: int, iz: int) -> float:
		return heights[iz * (resolution + 1) + ix]

	func vertex(ix: int, iz: int) -> Vector3:
		var half := size * 0.5
		return Vector3(center.x - half + ix * step, h(ix, iz), center.y - half + iz * step)

	## Altura exacta (sigue los mismos triángulos que la malla).
	func get_height(x: float, z: float) -> float:
		var half := size * 0.5
		var gx := clampf((x - center.x + half) / step, 0.0, resolution - 0.001)
		var gz := clampf((z - center.y + half) / step, 0.0, resolution - 0.001)
		var ix := int(gx)
		var iz := int(gz)
		var fx := gx - ix
		var fz := gz - iz
		var ha := h(ix, iz)
		var hb := h(ix + 1, iz)
		var hc := h(ix, iz + 1)
		var hd := h(ix + 1, iz + 1)
		if fx + fz <= 1.0:
			return ha + (hb - ha) * fx + (hc - ha) * fz
		return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)

	func get_biome(x: float, z: float) -> int:
		var half := size * 0.5
		var ix := clampi(roundi((x - center.x + half) / step), 0, resolution)
		var iz := clampi(roundi((z - center.y + half) / step), 0, resolution)
		return biomes[iz * (resolution + 1) + ix]


var regions: Array[Region] = []
var island: Region
var mainland: Region

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _site_heights: Dictionary = {}  ## Altura final de cada lugar del continente.


func generate(world_seed: int, with_mainland: bool = true) -> void:
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
	_ridges.seed = world_seed + 5
	_ridges.frequency = 0.012
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 4

	island = Region.new("island", Vector2.ZERO, SIZE, RESOLUTION)
	regions.append(island)
	if with_mainland:
		mainland = Region.new("mainland", MAINLAND_CENTER, MAINLAND_SIZE, MAINLAND_RESOLUTION)
		regions.append(mainland)
		for site: String in MAINLAND_SITES:
			var data: Array = MAINLAND_SITES[site]
			var natural := _mainland_raw(data[0].x, data[0].y)
			var target: float = data[2]
			if target == -1.0:
				target = clampf(natural, 5.0, 14.0)
			elif target == -2.0:
				target = clampf(natural, 20.0, 30.0)
			_site_heights[site] = target
	for region in regions:
		_compute_heights(region)
		_build_region(region)


## Región en la que cae un punto ("" = mar abierto).
func region_at(x: float, z: float) -> String:
	var region := _region(x, z)
	return region.id if region else ""


func region_of(id: String) -> Region:
	for region in regions:
		if region.id == id:
			return region
	return null


func _region(x: float, z: float) -> Region:
	for region in regions:
		if region.contains(x, z):
			return region
	return null


## Altura exacta del terreno. En mar abierto (fuera de las regiones), el fondo del mar.
func get_height(x: float, z: float) -> float:
	var region := _region(x, z)
	return region.get_height(x, z) if region else OCEAN_FLOOR


## 0 = plano, 1 = vertical.
func get_slope(x: float, z: float) -> float:
	var dx := get_height(x + 1.0, z) - get_height(x - 1.0, z)
	var dz := get_height(x, z + 1.0) - get_height(x, z - 1.0)
	return 1.0 - Vector3(-dx * 0.5, 1.0, -dz * 0.5).normalized().y


## Bioma en un punto: "meadow", "forest", "desert" o "tundra".
func get_biome(x: float, z: float) -> String:
	var region := _region(x, z)
	return BIOME_IDS[region.get_biome(x, z)] if region else "meadow"


## Posición en el mundo de un lugar del continente.
func site_position(site: String) -> Vector3:
	var local: Vector2 = MAINLAND_SITES[site][0]
	var p := MAINLAND_CENTER + local
	return Vector3(p.x, get_height(p.x, p.y), p.y)


func find_highest_point(max_radius: float, avoid: Vector2 = Vector2.INF, avoid_radius: float = 0.0) -> Vector3:
	var best := Vector3(0, -INF, 0)
	for iz in island.resolution + 1:
		for ix in island.resolution + 1:
			var v := island.vertex(ix, iz)
			var p := Vector2(v.x, v.z)
			if p.length() > max_radius:
				continue
			if avoid != Vector2.INF and p.distance_to(avoid) < avoid_radius:
				continue
			if v.y > best.y:
				best = v
	return best


# --- Alturas ----------------------------------------------------------------------------

func _island_height(x: float, z: float) -> float:
	var distance := Vector2(x, z).length()
	var n := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	var h := pow(n, 2.0) * MAX_HEIGHT * 1.15 - 5.0
	h += _detail.get_noise_2d(x, z) * 1.0
	# Forma de isla: hacia los bordes el terreno se hunde bajo el agua.
	var edge := smoothstep(0.0, 1.0, clampf((1.0 - distance / (SIZE * 0.5)) / 0.3, 0.0, 1.0))
	h = lerpf(OCEAN_FLOOR, h, edge)
	# Zona plana para el campamento donde aparecen los jugadores.
	var spawn_blend := smoothstep(SPAWN_RADIUS, SPAWN_RADIUS * 2.5, distance)
	return lerpf(SPAWN_HEIGHT, h, spawn_blend)


## Continente sin aplanar: colinas suaves, montañas al norte, sur y este, y costa al oeste.
func _mainland_raw(lx: float, lz: float) -> float:
	var half := MAINLAND_SIZE * 0.5
	var wx := lx + 5000.0
	var wz := lz - 3000.0
	var n := _noise.get_noise_2d(wx, wz) * 0.5 + 0.5
	var h := 3.5 + pow(n, 1.5) * 30.0 + _detail.get_noise_2d(wx, wz) * 0.8
	# Cordillera en los bordes que no dan al mar: el continente sigue más allá.
	var edge := maxf(absf(lz) / half, lx / half)
	var mountains := smoothstep(0.7, 0.97, edge)
	h += mountains * (35.0 + (_ridges.get_noise_2d(wx, wz) * 0.5 + 0.5) * 45.0)
	# Costa al oeste (mirando a la isla).
	var coast_x := -half * 0.78 + _noise.get_noise_2d(wz * 0.6, 900.0) * 22.0
	var land := smoothstep(coast_x - 22.0, coast_x + 18.0, lx)
	return lerpf(OCEAN_FLOOR, h, land)


func _mainland_height(lx: float, lz: float) -> float:
	var h := _mainland_raw(lx, lz)
	for site: String in MAINLAND_SITES:
		var data: Array = MAINLAND_SITES[site]
		var d := Vector2(lx, lz).distance_to(data[0])
		var radius: float = data[1]
		if d < radius:
			h = lerpf(_site_heights[site], h, smoothstep(radius * 0.55, radius, d))
	# Bahía del puerto: el mar entra hasta unos 28 m de la plaza, para el muelle.
	var harbor: Vector2 = MAINLAND_SITES["harbor"][0]
	var bay := smoothstep(harbor.x - 24.0, harbor.x - 58.0, lx) * (1.0 - smoothstep(38.0, 66.0, absf(lz - harbor.y)))
	if bay > 0.0:
		h = lerpf(h, minf(h, -5.0), bay)
	# Los caminos alisan un poco el relieve.
	var road := road_factor(lx, lz)
	if road > 0.0:
		h -= road * 0.12
	return h


## 1 en el centro de un camino, 0 fuera (coordenadas locales del continente).
static func road_factor(lx: float, lz: float) -> float:
	var p := Vector2(lx, lz)
	var best := INF
	for segment: Array in MAINLAND_ROADS:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return 1.0 - smoothstep(1.6, 3.4, best)


static func in_field(lx: float, lz: float) -> bool:
	for field: Rect2 in MAINLAND_FIELDS:
		if field.has_point(Vector2(lx, lz)):
			return true
	return false


func _island_biome(x: float, z: float, h: float) -> int:
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


func _mainland_biome(lx: float, lz: float, h: float) -> int:
	if h > SNOW_HEIGHT:
		return Biome.TUNDRA
	for site: String in MAINLAND_SITES:
		var data: Array = MAINLAND_SITES[site]
		if Vector2(lx, lz).distance_to(data[0]) < data[1] + 8.0:
			return Biome.FOREST if site == "bandits" else Biome.MEADOW
	if road_factor(lx, lz) > 0.0 or in_field(lx, lz):
		return Biome.MEADOW
	var m := _moisture.get_noise_2d(lx + 5000.0, lz - 3000.0)
	return Biome.FOREST if m > -0.02 else Biome.MEADOW


func _compute_heights(region: Region) -> void:
	var half := region.size * 0.5
	var count := (region.resolution + 1) * (region.resolution + 1)
	region.heights.resize(count)
	region.biomes.resize(count)
	for iz in region.resolution + 1:
		for ix in region.resolution + 1:
			var x := region.center.x - half + ix * region.step
			var z := region.center.y - half + iz * region.step
			var i := iz * (region.resolution + 1) + ix
			if region.id == "island":
				var h := _island_height(x, z)
				region.heights[i] = h
				region.biomes[i] = _island_biome(x, z, h)
			else:
				var lx := x - region.center.x
				var lz := z - region.center.y
				var h := _mainland_height(lx, lz)
				region.heights[i] = h
				region.biomes[i] = _mainland_biome(lx, lz, h)


# --- Malla y colisión ---------------------------------------------------------------------

func _build_region(region: Region) -> void:
	var faces := PackedVector3Array()
	var mesh := _build_mesh(region, faces)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh_" + region.id
	mesh_instance.mesh = mesh
	add_child(mesh_instance)
	# La colisión se arma con los mismos triángulos (no depende del renderizador).
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.name = "Collision_" + region.id
	collision.shape = shape
	add_child(collision)


## Malla suave: cada vértice tiene su normal (promedio del relieve) y su color, así las
## laderas y los cambios de bioma se ven graduales y no facetados.
func _build_mesh(region: Region, faces: PackedVector3Array) -> ArrayMesh:
	var res := region.resolution
	var count := res + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(count * count)
	normals.resize(count * count)
	colors.resize(count * count)
	for iz in count:
		for ix in count:
			var i := iz * count + ix
			var v := region.vertex(ix, iz)
			var dx := region.h(mini(ix + 1, res), iz) - region.h(maxi(ix - 1, 0), iz)
			var dz := region.h(ix, mini(iz + 1, res)) - region.h(ix, maxi(iz - 1, 0))
			var normal := Vector3(-dx, 2.0 * region.step, -dz).normalized()
			vertices[i] = v
			normals[i] = normal
			colors[i] = _vertex_color(region, v, normal, region.biomes[i])
	var indices := PackedInt32Array()
	indices.resize(res * res * 6)
	faces.resize(res * res * 6)
	var k := 0
	for iz in res:
		for ix in res:
			var a := iz * count + ix
			var b := a + 1
			var c := a + count
			var d := c + 1
			for index in [a, b, c, b, d, c]:
				indices[k] = index
				faces[k] = vertices[index]
				k += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_material())
	return mesh


func _terrain_material() -> ShaderMaterial:
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
	return material


func _vertex_color(region: Region, v: Vector3, normal: Vector3, biome: int) -> Color:
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
		if region.id == "mainland":
			var lx := v.x - region.center.x
			var lz := v.z - region.center.y
			if in_field(lx, lz):
				color = TILLED.lerp(Color(0.62, 0.52, 0.3), absf(variation))
			color = color.lerp(DIRT, road_factor(lx, lz) * 0.9)
		# Las pendientes fuertes muestran roca, con una transición suave.
		var rock := ROCK.lightened(0.15) if biome == Biome.TUNDRA else (Color(0.76, 0.56, 0.38) if biome == Biome.DESERT else ROCK)
		color = color.lerp(rock, smoothstep(0.82, 0.66, normal.y))
		if h > SNOW_HEIGHT + 2.0:
			color = color.lerp(SNOW, smoothstep(SNOW_HEIGHT + 2.0, SNOW_HEIGHT + 7.0, h) * smoothstep(0.6, 0.8, normal.y))
	color = color.lightened(variation * 0.06) if variation > 0.0 else color.darkened(-variation * 0.08)
	# Los colores de vértice se pasan en espacio lineal (igual en Forward+ y Compatibility).
	return color.srgb_to_linear()
