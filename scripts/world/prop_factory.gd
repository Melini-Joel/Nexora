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


## Material compartido para todas las mallas con colores por vértice.
static func vertex_material() -> StandardMaterial3D:
	if not _cache.has("vertex_mat"):
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		_cache["vertex_mat"] = mat
	return _cache["vertex_mat"]


## Junta varias piezas en una sola malla facetada con colores por vértice.
## Cada pieza: [PrimitiveMesh, Transform3D, Color, jitter (opcional), semilla (opcional)]
static func combine(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var source: PrimitiveMesh = part[0]
		var xf: Transform3D = part[1]
		var color: Color = (part[2] as Color).srgb_to_linear()
		var jitter: float = part[3] if part.size() > 3 else 0.0
		var jitter_seed: int = part[4] if part.size() > 4 else 0
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
			for v in [a, b, c]:
				st.set_color(color)
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
	var parts: Array = [[cylinder(0.16, 0.26, 2.4, 6), _at(Vector3(0, 1.2, 0)), BARK]]
	match kind:
		"pine", "snow_pine":
			var leaves: Color = LEAVES[variant % LEAVES.size()]
			for layer in [[1.5, 2.2, 2.6], [1.1, 1.9, 3.6], [0.7, 1.4, 4.5]]:
				parts.append([cylinder(0.0, layer[0], layer[1]), _at(Vector3(0, layer[2], 0)), leaves])
				if kind == "snow_pine":
					parts.append([cylinder(0.0, layer[0] * 0.75, layer[1] * 0.45), _at(Vector3(0, layer[2] + layer[1] * 0.3, 0)), SNOW])
		"round":
			var leaves: Color = ROUND_LEAVES[variant % ROUND_LEAVES.size()]
			parts.append([sphere(1.5, 2.4), _at(Vector3(0, 3.2, 0)), leaves, 0.18, variant * 31 + 1])
			parts.append([sphere(0.9, 1.44), _at(Vector3(0.7, 3.9, 0.3)), leaves.lightened(0.06), 0.12, variant * 31 + 2])
			parts.append([sphere(0.8, 1.3), _at(Vector3(-0.6, 3.6, -0.4)), leaves.darkened(0.06), 0.1, variant * 31 + 3])
	_cache[key] = combine(parts)
	return _cache[key]


static func make_tree(rng: RandomNumberGenerator, kind: String) -> ResourceNode:
	var variant := rng.randi() % 3
	var s := rng.randf_range(0.8, 1.35)
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
				Vector3(1, r.randf_range(0.8, 1.3), 1)), stalk.darkened(r.randf() * 0.15)])
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
		var parts: Array = [[sphere(0.7, 1.0), _at(Vector3(0, 0.45, 0)), Color(0.25, 0.48, 0.22), 0.1, variant]]
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
