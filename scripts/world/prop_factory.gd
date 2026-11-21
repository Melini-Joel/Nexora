class_name PropFactory
extends RefCounted
## Construye modelos low-poly por código: árboles, rocas, plantas, estaciones y lugares.
##
## Para rendir bien con miles de objetos, cada modelo se arma como UNA sola malla con
## colores por vértice (una llamada de dibujo por objeto) y se cachea para reutilizarla.
## Más adelante se pueden reemplazar por modelos hechos en Blender.

const BARK := Color(0.45, 0.3, 0.18)
const LEAVES := [Color(0.25, 0.52, 0.22), Color(0.33, 0.6, 0.25), Color(0.2, 0.45, 0.27)]
const ROUND_LEAVES := [Color(0.38, 0.62, 0.26), Color(0.45, 0.66, 0.28), Color(0.3, 0.55, 0.3)]
const STONE := Color(0.56, 0.55, 0.53)
const DARK_STONE := Color(0.24, 0.25, 0.3)
const CRYSTAL := Color(0.35, 0.9, 1.0)
const FIRE := Color(1.0, 0.55, 0.15)
const ORE_STONE := Color(0.4, 0.38, 0.37)
const ORE := Color(0.9, 0.55, 0.2)
const SACK := Color(0.55, 0.42, 0.28)
const SNOW := Color(0.93, 0.95, 0.98)
const CACTUS := Color(0.35, 0.55, 0.3)

const FAR := 260.0  ## Distancia a la que dejan de dibujarse los objetos grandes.
const NEAR := 120.0  ## Distancia para objetos chicos.

static var _cache: Dictionary = {}


static func material(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "mat_%s_%.2f" % [color.to_html(), emission_energy]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy
	_cache[key] = mat
	return mat


## Material compartido para todas las mallas con colores por vértice (con viento para las hojas).
static func vertex_material() -> ShaderMaterial:
	if not _cache.has("vertex_mat"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/props.gdshader")
		_cache["vertex_mat"] = mat
	return _cache["vertex_mat"]


## Junta varias piezas en una sola malla con colores por vértice.
## Cada pieza: [PrimitiveMesh, Transform3D, Color, jitter, semilla, viento, suave]
##   jitter/semilla: deforma los vértices (rocas, copas) · viento: 0..1 cuánto se mece
##   suave: sombreado redondeado (copas de árboles) en vez de facetado
static func combine(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var source: PrimitiveMesh = part[0]
		var xf: Transform3D = part[1]
		var color: Color = (part[2] as Color).srgb_to_linear()
		var jitter: float = part[3] if part.size() > 3 else 0.0
		var jitter_seed: int = part[4] if part.size() > 4 else 0
		color.a = part[5] if part.size() > 5 else 0.0
		var smooth: bool = part[6] if part.size() > 6 else false
		var center := xf.origin
		var arrays := source.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if jitter > 0.0:
			var rng := RandomNumberGenerator.new()
			for i in verts.size():
				var v := verts[i]
				# Vértices en la misma posición reciben el mismo desplazamiento: no quedan huecos.
				rng.seed = hash("%.3f,%.3f,%.3f" % [v.x, v.y, v.z]) + jitter_seed
				verts[i] = v + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
		var has_indices := not indices.is_empty()
		var count := indices.size() if has_indices else verts.size()
		for i in range(0, count, 3):
			var a: Vector3 = xf * (verts[indices[i]] if has_indices else verts[i])
			var b: Vector3 = xf * (verts[indices[i + 1]] if has_indices else verts[i + 1])
			var c: Vector3 = xf * (verts[indices[i + 2]] if has_indices else verts[i + 2])
			var normal := (c - a).cross(b - a)
			if normal.length_squared() < 0.0000001:
				continue
			normal = normal.normalized()
			for v: Vector3 in [a, b, c]:
				st.set_color(color)
				if smooth:
					# Normal hacia afuera y un poco hacia arriba: las copas se ven redondeadas y
					# reciben luz de abajo (como las hojas reales, que dejan pasar la luz).
					var outward := ((v - center).normalized() + Vector3(0, 0.45, 0)).normalized()
					st.set_normal(outward.lerp(normal, 0.25).normalized())
				else:
					st.set_normal(normal)
				st.add_vertex(v)
	st.set_material(vertex_material())
	return st.commit()


## Igual que combine() pero con material propio (para piezas que brillan).
static func flat_mesh(source: PrimitiveMesh, mat: Material, jitter: float = 0.0, jitter_seed: int = 0) -> ArrayMesh:
	var mesh := combine([[source, Transform3D.IDENTITY, Color.WHITE, jitter, jitter_seed]])
	mesh.surface_set_material(0, mat)
	return mesh


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scale), pos)


static func cylinder(top: float, bottom: float, height: float, segments: int = 7) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func sphere(radius: float, height: float, segments: int = 7, rings: int = 4) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = rings
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Mallas sueltas cacheadas (para piezas animadas o que brillan).
static func cone_mesh(radius: float, height: float, color: Color) -> Mesh:
	var key := "cone_%.2f_%.2f_%s" % [radius, height, color.to_html()]
	if not _cache.has(key):
		_cache[key] = combine([[cylinder(0.0, radius, height), Transform3D.IDENTITY, color]])
	return _cache[key]


static func blob_mesh(radius: float, color: Color, jitter: float, variant: int = 0) -> Mesh:
	var key := "blob_%.2f_%s_%.2f_%d" % [radius, color.to_html(), jitter, variant]
	if not _cache.has(key):
		_cache[key] = combine([[sphere(radius, radius * 1.6), Transform3D.IDENTITY, color, jitter, variant * 7919]])
	return _cache[key]


static func box_mesh(size: Vector3, color: Color, emission: float = 0.0) -> Mesh:
	var key := "box_%s_%s_%.2f" % [size, color.to_html(), emission]
	if not _cache.has(key):
		var b := box(size)
		b.material = material(color, emission)
		_cache[key] = b
	return _cache[key]


static func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _visual(node: Node3D, mesh: Mesh, range_end: float) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Visual"
	var mi := _add_mesh(visual, mesh, Vector3.ZERO)
	mi.visibility_range_end = range_end
	node.add_child(visual)
	return visual


static func _cylinder_collision(node: Node3D, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = height / 2.0
	node.add_child(collision)


static func _box_collision(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = pos
	parent.add_child(collision)


# --- Árboles --------------------------------------------------------------------------

static func tree_mesh(kind: String, variant: int) -> Mesh:
	var key := "tree_%s_%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var parts: Array = []
	match kind:
		"pine", "snow_pine":
			parts.append([cylinder(0.16, 0.26, 2.4, 8), _at(Vector3(0, 1.2, 0)), BARK, 0.0, 0, 0.15, true])
			var leaves: Color = LEAVES[variant % LEAVES.size()]
			for layer in [[1.55, 2.2, 2.6], [1.15, 1.9, 3.55], [0.75, 1.45, 4.45], [0.4, 0.9, 5.15]]:
				parts.append([cylinder(0.0, layer[0], layer[1], 9), _at(Vector3(0, layer[2], 0)), leaves.darkened(0.04 * (layer[2] - 2.6)), 0.06, variant, 1.0, true])
				if kind == "snow_pine":
					parts.append([cylinder(0.0, layer[0] * 0.78, layer[1] * 0.42), _at(Vector3(0, layer[2] + layer[1] * 0.32, 0)), SNOW, 0.0, 0, 1.0, true])
		"round":
			parts.append([cylinder(0.17, 0.27, 2.6, 8), _at(Vector3(0, 1.3, 0)), BARK, 0.0, 0, 0.15, true])
			var leaves: Color = ROUND_LEAVES[variant % ROUND_LEAVES.size()]
			parts.append([sphere(1.5, 2.4, 10, 6), _at(Vector3(0, 3.2, 0)), leaves, 0.2, variant * 31 + 1, 1.0, true])
			parts.append([sphere(0.95, 1.5, 9, 5), _at(Vector3(0.75, 3.9, 0.3)), leaves.lightened(0.06), 0.14, variant * 31 + 2, 1.0, true])
			parts.append([sphere(0.85, 1.35, 9, 5), _at(Vector3(-0.65, 3.6, -0.45)), leaves.darkened(0.06), 0.12, variant * 31 + 3, 1.0, true])
		"birch":
			var bark := Color(0.9, 0.88, 0.82)
			parts.append([cylinder(0.11, 0.16, 4.2, 8), _at(Vector3(0, 2.1, 0)), bark, 0.0, 0, 0.2, true])
			for i in 5:  # Manchas oscuras de la corteza.
				parts.append([box(Vector3(0.12, 0.05, 0.04)), _at(Vector3(0.1 * (1 if i % 2 == 0 else -1), 0.8 + i * 0.65, 0.09), Vector3(0, i, 0)), Color(0.15, 0.14, 0.13), 0.0, 0, 0.2])
			var leaves := Color(0.52, 0.72, 0.3).darkened(0.05 * variant)
			parts.append([sphere(1.0, 2.2, 9, 6), _at(Vector3(0, 4.6, 0)), leaves, 0.16, variant + 40, 1.0, true])
			parts.append([sphere(0.7, 1.4, 8, 5), _at(Vector3(0.45, 5.4, 0.2)), leaves.lightened(0.07), 0.12, variant + 41, 1.0, true])
			parts.append([sphere(0.65, 1.2, 8, 5), _at(Vector3(-0.4, 3.9, -0.3)), leaves.darkened(0.05), 0.1, variant + 42, 1.0, true])
		"oak":
			parts.append([cylinder(0.28, 0.45, 2.4, 9), _at(Vector3(0, 1.2, 0)), BARK.darkened(0.1), 0.03, variant, 0.1, true])
			parts.append([cylinder(0.12, 0.2, 1.8, 6), _at(Vector3(0.6, 2.6, 0), Vector3(0, 0, -0.7)), BARK.darkened(0.1), 0.0, 0, 0.3, true])
			parts.append([cylinder(0.12, 0.2, 1.8, 6), _at(Vector3(-0.55, 2.7, 0.2), Vector3(0.2, 0, 0.7)), BARK.darkened(0.1), 0.0, 0, 0.3, true])
			var leaves := Color(0.27, 0.48, 0.2).lightened(0.04 * variant)
			for blob in [[Vector3(0, 4.0, 0), 2.0], [Vector3(1.5, 3.6, 0.4), 1.4], [Vector3(-1.4, 3.7, -0.3), 1.4],
					[Vector3(0.3, 4.6, 1.2), 1.2], [Vector3(-0.2, 4.5, -1.3), 1.2]]:
				var r: float = blob[1]
				parts.append([sphere(r, r * 1.5, 10, 6), _at(blob[0]), leaves.darkened(0.03 * r), 0.22, variant * 17 + int(r * 10), 1.0, true])
		"dead":
			var wood := Color(0.42, 0.36, 0.3)
			parts.append([cylinder(0.12, 0.22, 3.4, 7), _at(Vector3(0, 1.7, 0)), wood, 0.02, variant, 0.0, true])
			for branch in [[Vector3(0.45, 2.6, 0), Vector3(0, 0, -0.8), 1.4], [Vector3(-0.4, 3.0, 0.2), Vector3(0.3, 0, 0.9), 1.2],
					[Vector3(0.1, 3.4, -0.4), Vector3(-0.8, 0.4, 0), 1.0], [Vector3(0.3, 3.6, 0.3), Vector3(0.6, 0, -0.5), 0.8]]:
				parts.append([cylinder(0.03, 0.08, branch[2], 5), _at(branch[0], branch[1]), wood.darkened(0.1), 0.0, 0, 0.0, true])
	_cache[key] = combine(parts)
	return _cache[key]


static func make_tree(rng: RandomNumberGenerator, kind: String) -> ResourceNode:
	var variant := rng.randi() % 3
	var s := rng.randf_range(0.8, 1.35)
	if kind == "oak":
		s *= 1.25
	var node := ResourceNode.new()
	node.setup("wood", "árbol", "Talar", 5, "hatchet")
	node.visual = _visual(node, tree_mesh(kind, variant), FAR)
	node.visual.scale = Vector3.ONE * s
	_cylinder_collision(node, 0.4 * s, 3.0 * s)
	return node


static func make_cactus(rng: RandomNumberGenerator) -> ResourceNode:
	var variant := rng.randi() % 2
	var key := "cactus_%d" % variant
	if not _cache.has(key):
		var parts: Array = [[cylinder(0.22, 0.26, 2.2, 8), _at(Vector3(0, 1.1, 0)), CACTUS]]
		parts.append([cylinder(0.14, 0.16, 0.9, 6), _at(Vector3(0.38, 1.3, 0), Vector3(0, 0, 0)), CACTUS.darkened(0.05)])
		parts.append([cylinder(0.12, 0.12, 0.4, 6), _at(Vector3(0.25, 0.9, 0), Vector3(0, 0, PI / 2)), CACTUS.darkened(0.05)])
		if variant == 1:
			parts.append([cylinder(0.13, 0.15, 0.7, 6), _at(Vector3(-0.36, 1.6, 0)), CACTUS])
			parts.append([cylinder(0.11, 0.11, 0.35, 6), _at(Vector3(-0.24, 1.3, 0), Vector3(0, 0, PI / 2)), CACTUS])
		parts.append([sphere(0.1, 0.16), _at(Vector3(0, 2.25, 0)), Color(0.95, 0.5, 0.6)])
		_cache[key] = combine(parts)
	var node := ResourceNode.new()
	node.setup("fiber", "cactus", "Cortar", 2, "")
	node.base_yield = 4
	node.visual = _visual(node, _cache[key], FAR)
	node.visual.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
	_cylinder_collision(node, 0.35, 2.2)
	return node


# --- Rocas y plantas ------------------------------------------------------------------

static func make_rock(rng: RandomNumberGenerator, is_ore: bool) -> ResourceNode:
	var s := rng.randf_range(0.7, 1.3)
	var variant := rng.randi() % 4
	var stretch_x := rng.randf_range(0.9, 1.4)
	var stretch_z := rng.randf_range(0.9, 1.4)
	var key := "rock_%s_%d" % [is_ore, variant]
	if not _cache.has(key):
		var base_color := ORE_STONE if is_ore else STONE
		var parts: Array = [[sphere(1.0, 1.6), _at(Vector3(0, 0.3, 0)), base_color, 0.22, variant * 7919]]
		if is_ore:
			for vein in [Vector3(0.55, 0.55, 0.3), Vector3(-0.4, 0.7, 0.45), Vector3(0.1, 0.5, -0.7), Vector3(-0.6, 0.35, -0.3)]:
				parts.append([sphere(0.2, 0.32), _at(vein), ORE, 0.05, variant])
		_cache[key] = combine(parts)
	var node := ResourceNode.new()
	if is_ore:
		node.setup("metal_ore", "roca con metal", "Picar", 5, "pickaxe")
		node.base_yield = 1
	else:
		node.setup("stone", "roca", "Picar", 4, "pickaxe")
	node.visual = _visual(node, _cache[key], FAR)
	node.visual.scale = Vector3(s * stretch_x, s, s * stretch_z)
	var shape := SphereShape3D.new()
	shape.radius = 0.9 * s
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.3 * s
	node.add_child(collision)
	return node


static func make_fiber_plant(rng: RandomNumberGenerator) -> ResourceNode:
	var variant := rng.randi() % 3
	var key := "fiber_%d" % variant
	if not _cache.has(key):
		var parts: Array = []
		var r := RandomNumberGenerator.new()
		r.seed = variant + 100
		var stalk := Color(0.72, 0.75, 0.32)
		for i in 7:
			var angle := TAU * i / 7.0 + r.randf() * 0.4
			var radius := r.randf_range(0.05, 0.22)
			var tilt := Vector3(sin(angle) * 0.25, 0, -cos(angle) * 0.25)
			parts.append([cylinder(0.0, 0.06, 1.1, 4), _at(Vector3(cos(angle) * radius, 0.5, sin(angle) * radius), tilt,
				Vector3(1, r.randf_range(0.8, 1.3), 1)), stalk.darkened(r.randf() * 0.15), 0.0, 0, 1.0])
		parts.append([sphere(0.09, 0.14), _at(Vector3(0, 1.1, 0)), Color(0.9, 0.85, 0.5)])
		_cache[key] = combine(parts)
	var node := ResourceNode.new()
	node.setup("fiber", "planta de fibra", "Arrancar", 1, "")
	node.base_yield = 6
	node.visual = _visual(node, _cache[key], NEAR)
	_cylinder_collision(node, 0.35, 1.2)
	return node


static func make_berry_bush(rng: RandomNumberGenerator) -> ResourceNode:
	var variant := rng.randi() % 3
	var key := "berry_%d" % variant
	if not _cache.has(key):
		var parts: Array = [[sphere(0.7, 1.0, 10, 6), _at(Vector3(0, 0.45, 0)), Color(0.25, 0.48, 0.22), 0.1, variant, 0.6, true]]
		var r := RandomNumberGenerator.new()
		r.seed = variant + 200
		for i in 10:
			var dir := Vector3(r.randf_range(-1, 1), r.randf_range(0.1, 1), r.randf_range(-1, 1)).normalized()
			parts.append([sphere(0.07, 0.12, 5, 3), _at(Vector3(0, 0.45, 0) + dir * Vector3(0.68, 0.5, 0.68)), Color(0.85, 0.12, 0.2)])
		_cache[key] = combine(parts)
	var node := ResourceNode.new()
	node.setup("berries", "arbusto de bayas", "Juntar", 1, "")
	node.base_yield = 5
	node.visual = _visual(node, _cache[key], NEAR)
	node.visual.scale = Vector3.ONE * rng.randf_range(0.85, 1.2)
	_cylinder_collision(node, 0.6, 1.0)
	return node


static func bush_mesh() -> Mesh:
	return blob_mesh(0.6, LEAVES[1], 0.1, 3)


# --- Lugares ---------------------------------------------------------------------------

static func make_monolith() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "Monolith"
	var parts: Array = [
		[box(Vector3(5, 0.6, 5)), _at(Vector3(0, 0.1, 0)), DARK_STONE],
		[box(Vector3(3.4, 0.5, 3.4)), _at(Vector3(0, 0.6, 0)), DARK_STONE.lightened(0.05)],
		[box(Vector3(1.1, 6.0, 1.1)), _at(Vector3(0, 3.8, 0), Vector3(0, 0.3, 0.04)), DARK_STONE],
		[box(Vector3(0.7, 2.8, 0.7)), _at(Vector3(1.7, 1.9, 1.0), Vector3(0.1, 0.4, -0.15)), DARK_STONE],
		[box(Vector3(0.7, 2.2, 0.7)), _at(Vector3(-1.6, 1.6, -0.9), Vector3(-0.12, 0.2, 0.1)), DARK_STONE],
	]
	_add_mesh(root, combine(parts), Vector3.ZERO)
	var crystal := _add_mesh(root, flat_mesh(sphere(0.6, 1.8, 4, 2), material(CRYSTAL, 4.0)), Vector3(0, 8.0, 0))
	crystal.name = "Crystal"
	var light := OmniLight3D.new()
	light.light_color = CRYSTAL
	light.light_energy = 2.5
	light.omni_range = 14.0
	light.position = Vector3(0, 8.0, 0)
	root.add_child(light)
	_box_collision(root, Vector3(5, 0.6, 5), Vector3(0, 0.1, 0))
	_box_collision(root, Vector3(1.1, 6.0, 1.1), Vector3(0, 3.8, 0))
	return root


## Muelle de madera que entra al agua (hacia -Z local).
static func make_dock(length: float) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "Dock"
	var wood := Color(0.5, 0.36, 0.22)
	var planks := int(length / 0.5)
	var parts: Array = []
	for i in planks:
		parts.append([box(Vector3(2.2, 0.1, 0.45)), _at(Vector3(0, 0, -i * 0.5)), wood.darkened(0.08 * (i % 3))])
	for i in range(0, planks, 4):
		for x in [-1.0, 1.0]:
			parts.append([cylinder(0.12, 0.12, 3.0, 6), _at(Vector3(x, -1.2, -i * 0.5)), wood.darkened(0.3)])
	_add_mesh(root, combine(parts), Vector3.ZERO)
	_box_collision(root, Vector3(2.2, 0.2, planks * 0.5), Vector3(0, -0.05, -planks * 0.25 + 0.25))
	return root


## Mirador: pila de piedras con una bandera.
static func make_cairn() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "Cairn"
	var parts: Array = [
		[sphere(0.8, 1.28), _at(Vector3(0, 0.3, 0)), STONE, 0.15, 1],
		[sphere(0.55, 0.88), _at(Vector3(0.1, 0.95, 0)), STONE.darkened(0.1), 0.12, 2],
		[sphere(0.35, 0.56), _at(Vector3(-0.05, 1.4, 0.05)), STONE, 0.08, 3],
		[box(Vector3(0.07, 2.4, 0.07)), _at(Vector3(0, 2.6, 0)), BARK],
		[box(Vector3(0.9, 0.5, 0.03)), _at(Vector3(0.47, 3.5, 0)), Color(0.8, 0.2, 0.15)],
	]
	_add_mesh(root, combine(parts), Vector3.ZERO)
	_box_collision(root, Vector3(1.4, 1.6, 1.4), Vector3(0, 0.8, 0))
	return root


# --- Estaciones (interactuables con E) ----------------------------------------------------

static func make_workbench() -> Station:
	var root := Station.new()
	root.station_type = "workbench"
	var wood := Color(0.55, 0.38, 0.22)
	var parts: Array = [[box(Vector3(1.9, 0.12, 0.85)), _at(Vector3(0, 0.88, 0)), wood]]
	for x in [-0.8, 0.8]:
		for z in [-0.32, 0.32]:
			parts.append([box(Vector3(0.12, 0.85, 0.12)), _at(Vector3(x, 0.42, z)), wood.darkened(0.2)])
	parts.append([box(Vector3(1.7, 0.06, 0.6)), _at(Vector3(0, 0.25, 0)), wood.darkened(0.25)])
	parts.append([box(Vector3(0.5, 0.06, 0.06)), _at(Vector3(-0.4, 0.97, 0.1), Vector3(0, 0.4, 0)), BARK])
	parts.append([box(Vector3(0.1, 0.16, 0.06)), _at(Vector3(-0.2, 1.0, 0.0)), STONE])
	parts.append([box(Vector3(0.35, 0.2, 0.25)), _at(Vector3(0.55, 1.04, -0.1)), Color(0.6, 0.45, 0.3)])
	parts.append([box(Vector3(0.3, 0.05, 0.4)), _at(Vector3(0.05, 0.96, 0.15)), Color(0.85, 0.8, 0.65)])
	_add_mesh(root, combine(parts), Vector3.ZERO)
	_box_collision(root, Vector3(1.9, 0.95, 0.85), Vector3(0, 0.47, 0))
	return root


static func make_furnace() -> Station:
	var root := Station.new()
	root.station_type = "furnace"
	var parts: Array = [
		[sphere(1.0, 1.6), _at(Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1.0, 1.1, 1.0)), STONE.darkened(0.15), 0.08, 2],
		[box(Vector3(0.5, 1.3, 0.5)), _at(Vector3(0.2, 1.9, 0.25)), STONE.darkened(0.25)],
	]
	_add_mesh(root, combine(parts), Vector3.ZERO)
	_add_mesh(root, box_mesh(Vector3(0.55, 0.4, 0.1), FIRE, 3.0), Vector3(0, 0.55, -0.92))
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 1.8
	light.omni_range = 6.0
	light.position = Vector3(0, 0.7, -1.4)
	root.add_child(light)
	_box_collision(root, Vector3(1.8, 1.6, 1.8), Vector3(0, 0.8, 0))
	return root


static func make_anvil() -> StaticBody3D:
	var root := StaticBody3D.new()
	var metal := Color(0.25, 0.26, 0.3)
	var parts: Array = [
		[box(Vector3(0.35, 0.5, 0.35)), _at(Vector3(0, 0.25, 0)), BARK],
		[box(Vector3(0.3, 0.15, 0.25)), _at(Vector3(0, 0.57, 0)), metal],
		[box(Vector3(0.6, 0.12, 0.25)), _at(Vector3(0.05, 0.7, 0)), metal],
	]
	_add_mesh(root, combine(parts), Vector3.ZERO)
	_box_collision(root, Vector3(0.6, 0.8, 0.4), Vector3(0, 0.4, 0))
	return root


## Fogata: estación para cocinar. La usan tanto el campamento como las que construyen los jugadores.
static func make_campfire() -> Station:
	var root := Station.new()
	root.station_type = "campfire"
	root.name = "Campfire"
	var parts: Array = []
	for i in 8:
		var angle := TAU * i / 8.0
		parts.append([sphere(0.25, 0.4), _at(Vector3(cos(angle) * 0.8, 0.1, sin(angle) * 0.8), Vector3(0, angle, 0)), STONE, 0.05, i % 4])
	parts.append([box(Vector3(1.2, 0.18, 0.18)), _at(Vector3(0, 0.15, 0), Vector3(0, 0.6, 0.2)), BARK])
	parts.append([box(Vector3(1.2, 0.18, 0.18)), _at(Vector3(0, 0.15, 0), Vector3(0, -0.6, -0.2)), BARK])
	_add_mesh(root, combine(parts), Vector3.ZERO)
	var flame := _add_mesh(root, cone_mesh(0.3, 0.8, FIRE), Vector3(0, 0.55, 0))
	flame.material_override = material(FIRE, 2.5)
	flame.name = "Flame"
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = FIRE
	light.light_energy = 2.0
	light.omni_range = 10.0
	light.position = Vector3(0, 1.2, 0)
	root.add_child(light)
	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 0.5
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.25
	root.add_child(collision)
	return root


# --- Barco y naufragio (historia) ---------------------------------------------------------

const SHIP_WOOD := Color(0.36, 0.22, 0.13)
const SAIL := Color(0.9, 0.86, 0.74)


## El barco "Albatros" (la proa apunta hacia -Z). Unos 20 m de largo.
static func make_ship() -> Node3D:
	var root := Node3D.new()
	root.name = "Ship"
	var parts: Array = [
		[box(Vector3(4.2, 2.2, 16)), _at(Vector3(0, 1.1, 0)), SHIP_WOOD],
		[cylinder(0.0, 2.15, 4.5, 4), _at(Vector3(0, 1.1, -10.2), Vector3(-PI / 2, PI / 4, 0), Vector3(1, 1, 0.75)), SHIP_WOOD],
		[box(Vector3(4.3, 0.3, 16.1)), _at(Vector3(0, 1.9, 0)), Color(0.5, 0.16, 0.12)],
		[box(Vector3(3.9, 0.15, 15.5)), _at(Vector3(0, 2.25, 0)), Color(0.6, 0.45, 0.3)],
		[box(Vector3(3.0, 1.8, 3.5)), _at(Vector3(0, 3.2, 4.8)), Color(0.85, 0.82, 0.76)],
		[box(Vector3(3.3, 0.2, 3.8)), _at(Vector3(0, 4.15, 4.8)), SHIP_WOOD],
		[cylinder(0.12, 0.17, 11.0, 6), _at(Vector3(0, 7.7, -3.0)), SHIP_WOOD.darkened(0.2)],
		[cylinder(0.1, 0.15, 9.0, 6), _at(Vector3(0, 6.7, 2.2)), SHIP_WOOD.darkened(0.2)],
		[box(Vector3(5.2, 4.6, 0.08)), _at(Vector3(0, 8.0, -3.2)), SAIL],
		[box(Vector3(4.2, 3.6, 0.08)), _at(Vector3(0, 7.0, 2.0)), SAIL],
		[box(Vector3(5.6, 0.12, 0.12)), _at(Vector3(0, 10.4, -3.1)), SHIP_WOOD],
		[box(Vector3(0.9, 0.5, 0.03)), _at(Vector3(0.45, 13.0, -3.0)), Color(0.75, 0.2, 0.15)],
	]
	_add_mesh(root, combine(parts), Vector3.ZERO)
	var lantern := _add_mesh(root, box_mesh(Vector3(0.3, 0.4, 0.3), FIRE, 4.0), Vector3(0, 4.5, 7.6))
	lantern.name = "Lantern"
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 2.5
	light.omni_range = 14.0
	light.position = Vector3(0, 4.6, 7.6)
	root.add_child(light)
	return root


## Restos del Albatros en la playa: el casco partido, un mástil caído, cajas y barriles.
static func make_shipwreck() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "Shipwreck"
	var old_wood := Color(0.42, 0.32, 0.24)
	var parts: Array = [
		# Proa clavada en la arena, inclinada.
		[box(Vector3(4.2, 2.2, 8)), _at(Vector3(0, 0.6, -3.5), Vector3(0.12, 0.1, 0.45)), old_wood],
		[cylinder(0.0, 2.15, 4.0, 4), _at(Vector3(0.4, 0.9, -9.3), Vector3(-PI / 2 + 0.12, PI / 4 + 0.1, 0.45), Vector3(1, 1, 0.75)), old_wood],
		[box(Vector3(4.3, 0.3, 8.1)), _at(Vector3(-0.35, 1.35, -3.5), Vector3(0.12, 0.1, 0.45)), Color(0.45, 0.2, 0.16)],
		# Popa separada, más adentro del agua.
		[box(Vector3(4.2, 2.0, 6)), _at(Vector3(2.5, 0.2, 7.0), Vector3(-0.15, -0.35, -0.3)), old_wood.darkened(0.1)],
		[box(Vector3(3.0, 1.6, 3.0)), _at(Vector3(2.9, 1.6, 7.8), Vector3(-0.15, -0.35, -0.3)), Color(0.7, 0.68, 0.62)],
		# Mástil caído y vela rota.
		[cylinder(0.12, 0.17, 10.0, 6), _at(Vector3(-4.5, 0.3, 1.0), Vector3(0, 0.3, PI / 2 - 0.08)), old_wood.darkened(0.25)],
		[box(Vector3(3.6, 0.05, 2.6)), _at(Vector3(-5.0, 0.12, 3.0), Vector3(0.05, 0.4, 0.02)), SAIL.darkened(0.15)],
		# Cajas y barriles desparramados.
		[box(Vector3(0.9, 0.9, 0.9)), _at(Vector3(-2.5, 0.35, -6.0), Vector3(0, 0.5, 0.2)), Color(0.6, 0.45, 0.28)],
		[box(Vector3(0.8, 0.8, 0.8)), _at(Vector3(-3.4, 0.3, -5.0), Vector3(0.2, 1.1, 0)), Color(0.55, 0.42, 0.26)],
		[box(Vector3(0.9, 0.9, 0.9)), _at(Vector3(3.8, 0.3, -2.0), Vector3(0, 0.2, 0.3)), Color(0.58, 0.44, 0.27)],
		[cylinder(0.38, 0.38, 1.0, 8), _at(Vector3(-1.5, 0.35, 3.5), Vector3(PI / 2, 0.6, 0)), Color(0.45, 0.3, 0.18)],
		[cylinder(0.38, 0.38, 1.0, 8), _at(Vector3(4.6, 0.45, 2.5)), Color(0.45, 0.3, 0.18)],
	]
	_add_mesh(root, combine(parts), Vector3.ZERO)
	_box_collision(root, Vector3(4.4, 2.6, 8.5), Vector3(0, 0.6, -3.5))
	_box_collision(root, Vector3(4.2, 2.2, 6.0), Vector3(2.5, 0.3, 7.0))
	return root


# --- Vegetación decorativa (ver decor_field.gd) -------------------------------------------

static func decor_mesh(type: String) -> Mesh:
	var key := "decor_" + type
	if _cache.has(key):
		return _cache[key]
	var parts: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = hash(type)
	match type:
		"fern":
			for i in 8:
				var angle := TAU * i / 8.0 + r.randf() * 0.3
				var length := r.randf_range(0.55, 0.85)
				var dir := Vector3(sin(angle), 0, cos(angle))
				parts.append([box(Vector3(0.16, 0.02, length)), _at(dir * length * 0.42 + Vector3(0, 0.22, 0), Vector3(-0.5, angle, 0)),
					Color(0.2, 0.42, 0.18).lightened(r.randf() * 0.08), 0.0, 0, 1.0])
		"flower_white", "flower_yellow", "flower_purple", "flower_red":
			var petal: Color = {"flower_white": Color(0.95, 0.95, 0.92), "flower_yellow": Color(1.0, 0.85, 0.25),
				"flower_purple": Color(0.6, 0.4, 0.85), "flower_red": Color(0.9, 0.2, 0.22)}[type]
			for i in 4:
				var offset := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2))
				var height := r.randf_range(0.25, 0.45)
				parts.append([cylinder(0.012, 0.015, height, 4), _at(offset + Vector3(0, height / 2, 0)), Color(0.3, 0.55, 0.22), 0.0, 0, 1.0])
				parts.append([sphere(0.06, 0.04, 6, 2), _at(offset + Vector3(0, height, 0)), petal, 0.0, 0, 1.0])
				parts.append([sphere(0.022, 0.03, 5, 2), _at(offset + Vector3(0, height + 0.015, 0)), Color(1.0, 0.8, 0.2), 0.0, 0, 1.0])
		"mushroom":
			for i in 3:
				var offset := Vector3(r.randf_range(-0.18, 0.18), 0, r.randf_range(-0.18, 0.18))
				var height := r.randf_range(0.08, 0.18)
				parts.append([cylinder(0.025, 0.03, height, 6), _at(offset + Vector3(0, height / 2, 0)), Color(0.92, 0.9, 0.82), 0.0, 0, 0.0, true])
				var cap := Color(0.75, 0.2, 0.15) if i == 0 else Color(0.55, 0.38, 0.25)
				var hemi := SphereMesh.new()
				hemi.radius = r.randf_range(0.06, 0.1)
				hemi.height = hemi.radius
				hemi.is_hemisphere = true
				hemi.radial_segments = 8
				hemi.rings = 3
				parts.append([hemi, _at(offset + Vector3(0, height, 0)), cap, 0.0, 0, 0.0, true])
		"pebbles":
			for i in 4:
				var size := r.randf_range(0.08, 0.2)
				parts.append([sphere(size, size * 1.2, 6, 3), _at(Vector3(r.randf_range(-0.4, 0.4), size * 0.25, r.randf_range(-0.4, 0.4))),
					STONE.darkened(r.randf() * 0.25), 0.03, i])
		"log":
			parts.append([cylinder(0.24, 0.28, 3.2, 9), _at(Vector3(0, 0.2, 0), Vector3(0, 0, PI / 2)), BARK.darkened(0.1), 0.02, 3, 0.0, true])
			parts.append([cylinder(0.25, 0.25, 0.04, 9), _at(Vector3(1.61, 0.2, 0), Vector3(0, 0, PI / 2)), Color(0.75, 0.6, 0.4)])
			for i in 3:
				parts.append([sphere(0.14, 0.08, 6, 2), _at(Vector3(r.randf_range(-1.2, 1.2), 0.42, r.randf_range(-0.08, 0.08))), Color(0.3, 0.5, 0.2), 0.02, i])
		"reeds":
			for i in 9:
				var offset := Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3))
				var height := r.randf_range(0.9, 1.6)
				parts.append([cylinder(0.0, 0.025, height, 4), _at(offset + Vector3(0, height / 2, 0), Vector3(r.randf_range(-0.1, 0.1), 0, r.randf_range(-0.1, 0.1))),
					Color(0.45, 0.55, 0.25).darkened(r.randf() * 0.15), 0.0, 0, 1.0])
				if i % 3 == 0:
					parts.append([cylinder(0.03, 0.03, 0.18, 5), _at(offset + Vector3(0, height * 0.85, 0)), Color(0.4, 0.26, 0.15), 0.0, 0, 1.0])
		"bush":
			parts.append([sphere(0.65, 0.9, 10, 6), _at(Vector3(0, 0.38, 0)), Color(0.24, 0.45, 0.2), 0.12, 7, 0.6, true])
			parts.append([sphere(0.45, 0.65, 9, 5), _at(Vector3(0.45, 0.32, 0.2)), Color(0.28, 0.5, 0.22), 0.1, 8, 0.6, true])
			parts.append([sphere(0.4, 0.6, 9, 5), _at(Vector3(-0.4, 0.3, -0.25)), Color(0.22, 0.42, 0.19), 0.1, 9, 0.6, true])
		"dry_shrub":
			for i in 7:
				var angle := TAU * i / 7.0
				var length := r.randf_range(0.4, 0.7)
				parts.append([cylinder(0.008, 0.02, length, 4), _at(Vector3(sin(angle), 0, cos(angle)) * 0.12 + Vector3(0, length * 0.4, 0),
					Vector3(cos(angle) * 0.6, 0, -sin(angle) * 0.6)), Color(0.55, 0.45, 0.3), 0.0, 0, 0.6])
	_cache[key] = combine(parts)
	return _cache[key]
