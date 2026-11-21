class_name PropFactory
extends RefCounted
## Construye modelos low-poly por código: árboles, rocas, arbustos, monolito y fogata.
## Mallas y materiales se cachean y se comparten entre todas las instancias (menos memoria
## y mejor rendimiento). Más adelante se pueden reemplazar por modelos hechos en Blender.

const BARK := Color(0.45, 0.3, 0.18)
const LEAVES := [Color(0.25, 0.52, 0.22), Color(0.33, 0.6, 0.25), Color(0.2, 0.45, 0.27)]
const STONE := Color(0.56, 0.55, 0.53)
const ORE_STONE := Color(0.4, 0.38, 0.37)
const ORE := Color(0.9, 0.55, 0.2)
const SACK := Color(0.55, 0.42, 0.28)
const DARK_STONE := Color(0.24, 0.25, 0.3)
const CRYSTAL := Color(0.35, 0.9, 1.0)
const FIRE := Color(1.0, 0.55, 0.15)

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


## Convierte una malla primitiva a sombreado plano (facetado) y opcionalmente deforma
## sus vértices para que se vea irregular (rocas, copas de árboles).
static func flat_mesh(source: PrimitiveMesh, mat: Material, jitter: float = 0.0, jitter_seed: int = 0) -> ArrayMesh:
	# get_mesh_arrays() calcula la malla en CPU (funciona también en un servidor sin gráficos).
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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, count, 3):
		var a: Vector3 = verts[indices[i]] if has_indices else verts[i]
		var b: Vector3 = verts[indices[i + 1]] if has_indices else verts[i + 1]
		var c: Vector3 = verts[indices[i + 2]] if has_indices else verts[i + 2]
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 0.0000001:
			continue
		normal = normal.normalized()
		for v in [a, b, c]:
			st.set_normal(normal)
			st.add_vertex(v)
	st.set_material(mat)
	return st.commit()


# --- Mallas cacheadas ------------------------------------------------------------

static func trunk_mesh() -> Mesh:
	if not _cache.has("trunk"):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.16
		cylinder.bottom_radius = 0.26
		cylinder.height = 2.4
		cylinder.radial_segments = 6
		cylinder.rings = 1
		_cache["trunk"] = flat_mesh(cylinder, material(BARK))
	return _cache["trunk"]


static func cone_mesh(radius: float, height: float, color: Color) -> Mesh:
	var key := "cone_%.2f_%.2f_%s" % [radius, height, color.to_html()]
	if not _cache.has(key):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = radius
		cone.height = height
		cone.radial_segments = 7
		cone.rings = 1
		_cache[key] = flat_mesh(cone, material(color))
	return _cache[key]


static func blob_mesh(radius: float, color: Color, jitter: float, variant: int = 0) -> Mesh:
	var key := "blob_%.2f_%s_%.2f_%d" % [radius, color.to_html(), jitter, variant]
	if not _cache.has(key):
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 1.6
		sphere.radial_segments = 7
		sphere.rings = 4
		_cache[key] = flat_mesh(sphere, material(color), jitter, variant * 7919)
	return _cache[key]


static func box_mesh(size: Vector3, color: Color, emission: float = 0.0) -> Mesh:
	var key := "box_%s_%s_%.2f" % [size, color.to_html(), emission]
	if not _cache.has(key):
		var box := BoxMesh.new()
		box.size = size
		box.material = material(color, emission)
		_cache[key] = box
	return _cache[key]


static func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# --- Recursos ----------------------------------------------------------------------

static func make_tree(rng: RandomNumberGenerator) -> ResourceNode:
	var kind := rng.randi() % 3
	var s := rng.randf_range(0.8, 1.3)
	var leaves: Color = LEAVES[rng.randi() % LEAVES.size()]

	var node := ResourceNode.new()
	node.setup("wood", "árbol", "Talar", 5, "hatchet")
	var visual := Node3D.new()
	visual.name = "Visual"
	_add_mesh(visual, trunk_mesh(), Vector3(0, 1.2, 0))
	if kind < 2:  # Pino
		_add_mesh(visual, cone_mesh(1.5, 2.2, leaves), Vector3(0, 2.6, 0))
		_add_mesh(visual, cone_mesh(1.1, 1.9, leaves), Vector3(0, 3.6, 0))
		_add_mesh(visual, cone_mesh(0.7, 1.4, leaves), Vector3(0, 4.5, 0))
	else:  # Árbol frondoso
		_add_mesh(visual, blob_mesh(1.5, leaves, 0.18, 1), Vector3(0, 3.2, 0))
		_add_mesh(visual, blob_mesh(0.9, leaves, 0.12, 2), Vector3(0.7, 3.9, 0.3))
	visual.scale = Vector3.ONE * s
	node.add_child(visual)
	node.visual = visual

	var shape := CylinderShape3D.new()
	shape.radius = 0.4 * s
	shape.height = 3.0 * s
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 1.5 * s
	node.add_child(collision)
	return node


static func make_rock(rng: RandomNumberGenerator, is_ore: bool) -> ResourceNode:
	var s := rng.randf_range(0.7, 1.3)
	var variant := rng.randi() % 4
	var stretch_x := rng.randf_range(0.9, 1.4)
	var stretch_z := rng.randf_range(0.9, 1.4)

	var node := ResourceNode.new()
	var visual := Node3D.new()
	visual.name = "Visual"
	if is_ore:
		node.setup("metal_ore", "roca con metal", "Picar", 5, "pickaxe")
		_add_mesh(visual, blob_mesh(1.0, ORE_STONE, 0.22, variant), Vector3(0, 0.3, 0))
		# Vetas de metal que brillan un poco.
		for vein in [Vector3(0.55, 0.55, 0.3), Vector3(-0.4, 0.7, 0.45), Vector3(0.1, 0.5, -0.7), Vector3(-0.6, 0.35, -0.3)]:
			_add_mesh(visual, blob_mesh(0.2, ORE, 0.05, variant), vein)
	else:
		node.setup("stone", "roca", "Picar", 4, "pickaxe")
		_add_mesh(visual, blob_mesh(1.0, STONE, 0.22, variant), Vector3(0, 0.3, 0))
	visual.scale = Vector3(s * stretch_x, s, s * stretch_z)
	node.add_child(visual)
	node.visual = visual

	var shape := SphereShape3D.new()
	shape.radius = 0.9 * s
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.3 * s
	node.add_child(collision)
	return node


# --- Decoración y lugares importantes -------------------------------------------------

static func bush_mesh() -> Mesh:
	return blob_mesh(0.6, LEAVES[1], 0.1, 3)


static func make_monolith() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "Monolith"
	_add_mesh(root, box_mesh(Vector3(5, 0.6, 5), DARK_STONE), Vector3(0, 0.1, 0))
	_add_mesh(root, box_mesh(Vector3(3.4, 0.5, 3.4), DARK_STONE), Vector3(0, 0.6, 0))
	_add_mesh(root, box_mesh(Vector3(1.1, 6.0, 1.1), DARK_STONE), Vector3(0, 3.8, 0), Vector3(0, 0.3, 0.04))
	_add_mesh(root, box_mesh(Vector3(0.7, 2.8, 0.7), DARK_STONE), Vector3(1.7, 1.9, 1.0), Vector3(0.1, 0.4, -0.15))
	_add_mesh(root, box_mesh(Vector3(0.7, 2.2, 0.7), DARK_STONE), Vector3(-1.6, 1.6, -0.9), Vector3(-0.12, 0.2, 0.1))

	var crystal_mesh := SphereMesh.new()
	crystal_mesh.radius = 0.6
	crystal_mesh.height = 1.8
	crystal_mesh.radial_segments = 4
	crystal_mesh.rings = 2
	var crystal := _add_mesh(root, flat_mesh(crystal_mesh, material(CRYSTAL, 4.0)), Vector3(0, 8.0, 0))
	crystal.name = "Crystal"

	var light := OmniLight3D.new()
	light.light_color = CRYSTAL
	light.light_energy = 2.5
	light.omni_range = 14.0
	light.position = Vector3(0, 8.0, 0)
	root.add_child(light)

	for data in [[Vector3(5, 0.6, 5), Vector3(0, 0.1, 0)], [Vector3(1.1, 6.0, 1.1), Vector3(0, 3.8, 0)]]:
		var shape := BoxShape3D.new()
		shape.size = data[0]
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = data[1]
		root.add_child(collision)
	return root


static func make_campfire() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "Campfire"
	for i in 8:
		var angle := TAU * i / 8.0
		var stone := _add_mesh(root, blob_mesh(0.25, STONE, 0.05, i % 4), Vector3(cos(angle) * 0.8, 0.1, sin(angle) * 0.8))
		stone.rotation.y = angle
	_add_mesh(root, box_mesh(Vector3(1.2, 0.18, 0.18), BARK), Vector3(0, 0.15, 0), Vector3(0, 0.6, 0.2))
	_add_mesh(root, box_mesh(Vector3(1.2, 0.18, 0.18), BARK), Vector3(0, 0.15, 0), Vector3(0, -0.6, -0.2))
	_add_mesh(root, cone_mesh(0.3, 0.8, FIRE), Vector3(0, 0.55, 0)).material_override = material(FIRE, 2.5)

	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = FIRE
	light.light_energy = 2.0
	light.omni_range = 9.0
	light.position = Vector3(0, 1.2, 0)
	root.add_child(light)

	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 0.4
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.2
	root.add_child(collision)
	return root
