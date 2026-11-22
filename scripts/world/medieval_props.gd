class_name MedievalProps
extends RefCounted
## Modelos medievales de Valdoria hechos por código (como PropFactory): casas con entramado
## de madera, taberna, mercado, pozo, faroles, molino, cercos, murallas y torres del castillo,
## carpas de bandidos y trigo. Cada modelo es UNA malla con colores por vértice + colisión.
## La fachada (puerta) de las casas mira hacia -Z.

const PLASTER := Color(0.88, 0.84, 0.74)
const BEAM := Color(0.3, 0.2, 0.13)
const ROOF_TILE := Color(0.62, 0.27, 0.2)
const ROOF_SLATE := Color(0.32, 0.34, 0.4)
const THATCH := Color(0.74, 0.62, 0.36)
const FOUNDATION := Color(0.55, 0.53, 0.5)
const CASTLE_STONE := Color(0.68, 0.66, 0.61)
const WOOD := Color(0.52, 0.36, 0.22)
const GLASS := Color(0.25, 0.32, 0.4)
const GOLD := Color(1.0, 0.78, 0.25)
const ROYAL_RED := Color(0.62, 0.1, 0.12)

static var _cache: Dictionary = {}


static func _box(size: Vector3) -> BoxMesh:
	return PropFactory.box(size)


static func _at(pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return PropFactory._at(pos, rot, scale)


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


static func _body(mesh: Mesh) -> StaticBody3D:
	var root := StaticBody3D.new()
	var mi := PropFactory._add_mesh(root, mesh, Vector3.ZERO)
	mi.visibility_range_end = 420.0
	return root


static func _cached(key: String, builder: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = PropFactory.combine(builder.call())
	return _cache[key]


# --- Casas ---------------------------------------------------------------------------------

## Casa con entramado de madera. size = ancho (X) y fondo (Z); floors = pisos (1 o 2).
static func make_house(size: Vector2, floors: int, roof_color: Color, variant: int = 0) -> StaticBody3D:
	var key := "house_%s_%d_%s_%d" % [size, floors, roof_color.to_html(), variant]
	var mesh := _cached(key, _house_parts.bind(size, floors, roof_color, variant, []))
	var root := _body(mesh)
	var wall_h := 2.9 * floors
	PropFactory._box_collision(root, Vector3(size.x, wall_h + 1.0, size.y), Vector3(0, (wall_h + 1.0) / 2.0 - 0.3, 0))
	return root


static func _house_parts(size: Vector2, floors: int, roof_color: Color, variant: int, extra: Array) -> Array:
	var w := size.x
	var d := size.y
	var wall_h := 2.9 * floors
	var base := 0.7
	var top := base + wall_h
	var plaster := PLASTER.darkened(0.04 * (variant % 3))
	var parts: Array = [
		[_box(Vector3(w + 0.3, 1.1, d + 0.3)), _at(Vector3(0, 0.15, 0)), FOUNDATION, 0.02, variant],
		[_box(Vector3(w, wall_h, d)), _at(Vector3(0, base + wall_h / 2.0, 0)), plaster],
	]
	# Entramado: vigas verticales, horizontales y diagonales (apenas por fuera de la pared).
	var o := 0.04
	for floor_i in floors + 1:
		var y := base + floor_i * 2.9
		parts.append([_box(Vector3(w + 0.1, 0.18, 0.12)), _at(Vector3(0, y, -d / 2.0 - o)), BEAM])
		parts.append([_box(Vector3(w + 0.1, 0.18, 0.12)), _at(Vector3(0, y, d / 2.0 + o)), BEAM])
		parts.append([_box(Vector3(0.12, 0.18, d + 0.1)), _at(Vector3(-w / 2.0 - o, y, 0)), BEAM])
		parts.append([_box(Vector3(0.12, 0.18, d + 0.1)), _at(Vector3(w / 2.0 + o, y, 0)), BEAM])
	var columns := maxi(2, int(w / 1.8) + 1)
	for i in columns:
		var x := -w / 2.0 + w * i / (columns - 1)
		for z in [-d / 2.0 - o, d / 2.0 + o]:
			parts.append([_box(Vector3(0.16, wall_h, 0.12)), _at(Vector3(x, base + wall_h / 2.0, z)), BEAM])
	var side_columns := maxi(2, int(d / 1.8) + 1)
	for i in side_columns:
		var z := -d / 2.0 + d * i / (side_columns - 1)
		for x in [-w / 2.0 - o, w / 2.0 + o]:
			parts.append([_box(Vector3(0.12, wall_h, 0.16)), _at(Vector3(x, base + wall_h / 2.0, z)), BEAM])
	for floor_i in floors:
		var y := base + floor_i * 2.9 + 1.45
		var brace := atan2(2.9, w / 2.0)
		for side in [-1.0, 1.0]:
			parts.append([_box(Vector3(0.1, sqrt(2.9 * 2.9 + w * w / 4.0) * 0.55, 0.1)),
				_at(Vector3(side * w / 4.0, y, d / 2.0 + o), Vector3(0, 0, side * (PI / 2.0 - brace))), BEAM])
	# Puerta y ventanas.
	parts.append([_box(Vector3(1.15, 2.05, 0.14)), _at(Vector3(0, base + 1.02, -d / 2.0 - 0.03)), WOOD.darkened(0.25)])
	parts.append([_box(Vector3(1.4, 0.16, 0.18)), _at(Vector3(0, base + 2.12, -d / 2.0 - 0.05)), BEAM])
	parts.append([_box(Vector3(1.6, 0.15, 0.7)), _at(Vector3(0, 0.62, -d / 2.0 - 0.45)), FOUNDATION.darkened(0.1)])  # escalón
	for floor_i in floors:
		var y := base + floor_i * 2.9 + 1.6
		for x in ([-w / 3.2, w / 3.2] if floor_i == 0 else [-w / 3.2, 0.0, w / 3.2]):
			for z in [-d / 2.0 - 0.05, d / 2.0 + 0.05]:
				parts.append([_box(Vector3(0.75, 0.85, 0.08)), _at(Vector3(x, y, z)), GLASS])
				parts.append([_box(Vector3(0.95, 0.12, 0.16)), _at(Vector3(x, y - 0.5, z)), BEAM])
		for x in [-w / 2.0 - 0.05, w / 2.0 + 0.05]:
			parts.append([_box(Vector3(0.08, 0.85, 0.75)), _at(Vector3(x, y, 0)), GLASS])
	# Techo a dos aguas (cumbrera a lo largo de X) con aleros y hastiales de revoque.
	var overhang := 0.5
	var half := d / 2.0 + overhang
	var roof_h := d * 0.55
	var slope := atan2(roof_h, half)
	var slab := sqrt(half * half + roof_h * roof_h)
	parts.append([_prism(Vector3(d, roof_h * d / 2.0 / half, w)), _at(Vector3(0, top + roof_h * d / 2.0 / half / 2.0, 0), Vector3(0, PI / 2.0, 0)), plaster])
	for side in [-1.0, 1.0]:
		parts.append([_box(Vector3(w + overhang * 2.0, 0.2, slab)),
			_at(Vector3(0, top + roof_h / 2.0, side * half / 2.0), Vector3(side * slope, 0, 0)), roof_color, 0.0, variant])
	parts.append([_box(Vector3(w + overhang * 2.0 + 0.1, 0.22, 0.3)), _at(Vector3(0, top + roof_h + 0.02, 0)), roof_color.darkened(0.2)])
	# Chimenea.
	if variant % 2 == 0:
		parts.append([_box(Vector3(0.7, roof_h + 1.4, 0.7)), _at(Vector3(w / 2.0 - 1.0, top + roof_h / 2.0 + 0.4, d / 6.0)), FOUNDATION])
	parts.append_array(extra)
	return parts


## Taberna "El Ancla Rota": casa grande de dos pisos con cartel y barriles.
static func make_tavern() -> StaticBody3D:
	var extra: Array = [
		[_box(Vector3(0.12, 0.12, 1.4)), _at(Vector3(-3.0, 3.0, -4.3)), BEAM],
		[_box(Vector3(1.1, 0.75, 0.08)), _at(Vector3(-3.0, 2.45, -4.9)), Color(0.55, 0.38, 0.2)],
		[_box(Vector3(0.6, 0.35, 0.1)), _at(Vector3(-3.0, 2.45, -4.95)), Color(0.2, 0.25, 0.32)],
		[PropFactory.cylinder(0.4, 0.4, 1.0, 8), _at(Vector3(3.8, 0.5, -4.3)), WOOD],
		[PropFactory.cylinder(0.4, 0.4, 1.0, 8), _at(Vector3(4.7, 0.5, -4.1)), WOOD.darkened(0.1)],
		[PropFactory.cylinder(0.4, 0.4, 1.0, 8), _at(Vector3(4.2, 1.5, -4.2)), WOOD],
		[_box(Vector3(1.8, 0.1, 0.8)), _at(Vector3(-4.8, 0.8, -4.8)), WOOD],
		[_box(Vector3(0.1, 0.8, 0.1)), _at(Vector3(-5.5, 0.4, -4.8)), WOOD],
		[_box(Vector3(0.1, 0.8, 0.1)), _at(Vector3(-4.1, 0.4, -4.8)), WOOD],
	]
	var mesh := _cached("tavern", _house_parts.bind(Vector2(11, 7.5), 2, ROOF_TILE, 4, extra))
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(11, 6.8, 7.5), Vector3(0, 3.1, 0))
	return root


# --- Plaza ---------------------------------------------------------------------------------

## Puesto de mercado con toldo a rayas y mercadería.
static func make_market_stall(stripe: Color, goods: Color) -> StaticBody3D:
	var key := "stall_%s_%s" % [stripe.to_html(), goods.to_html()]
	var mesh := _cached(key, func() -> Array:
		var parts: Array = [
			[_box(Vector3(3.0, 0.9, 1.2)), _at(Vector3(0, 0.45, 0)), WOOD],
			[_box(Vector3(3.1, 0.08, 1.3)), _at(Vector3(0, 0.92, 0)), WOOD.lightened(0.1)],
		]
		for x in [-1.45, 1.45]:
			for z in [-0.55, 0.55]:
				parts.append([_box(Vector3(0.1, 2.6 if z > 0 else 2.2, 0.1)), _at(Vector3(x, 1.3 if z > 0 else 1.1, z)), BEAM])
		for i in 6:
			var color := stripe if i % 2 == 0 else Color(0.95, 0.92, 0.85)
			parts.append([_box(Vector3(0.55, 0.06, 1.9)), _at(Vector3(-1.38 + i * 0.55, 2.4, -0.1), Vector3(-0.22, 0, 0)), color])
		for i in 5:
			parts.append([PropFactory.sphere(0.13, 0.22, 6, 3), _at(Vector3(-1.1 + i * 0.5, 1.05, -0.2)), goods.darkened(0.08 * (i % 3))])
			parts.append([_box(Vector3(0.35, 0.18, 0.3)), _at(Vector3(-1.0 + i * 0.5, 1.03, 0.25)), Color(0.6, 0.45, 0.28)])
		return parts
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(3.0, 1.0, 1.2), Vector3(0, 0.5, 0))
	return root


static func make_well() -> StaticBody3D:
	var mesh := _cached("well", func() -> Array:
		var parts: Array = [
			[PropFactory.cylinder(1.1, 1.2, 1.0, 10), _at(Vector3(0, 0.5, 0)), FOUNDATION, 0.03, 3],
			[PropFactory.cylinder(0.85, 0.85, 0.05, 10), _at(Vector3(0, 0.95, 0)), Color(0.15, 0.22, 0.28)],
			[_box(Vector3(0.15, 2.4, 0.15)), _at(Vector3(-1.0, 1.2, 0)), BEAM],
			[_box(Vector3(0.15, 2.4, 0.15)), _at(Vector3(1.0, 1.2, 0)), BEAM],
			[_box(Vector3(2.3, 0.1, 0.1)), _at(Vector3(0, 2.1, 0)), BEAM],
			[PropFactory.cylinder(0.18, 0.15, 0.3, 8), _at(Vector3(0, 1.6, 0)), WOOD],
		]
		for side in [-1.0, 1.0]:
			parts.append([_box(Vector3(2.6, 0.12, 1.1)), _at(Vector3(0, 2.6, side * 0.45), Vector3(side * 0.6, 0, 0)), ROOF_TILE])
		return parts
	)
	var root := _body(mesh)
	PropFactory._cylinder_collision(root, 1.2, 1.0)
	return root


## Farol con luz cálida.
static func make_lamp_post(with_light: bool = true) -> StaticBody3D:
	var mesh := _cached("lamp", func() -> Array:
		return [
			[_box(Vector3(0.14, 3.0, 0.14)), _at(Vector3(0, 1.5, 0)), BEAM],
			[_box(Vector3(0.5, 0.1, 0.1)), _at(Vector3(0.2, 2.9, 0)), BEAM],
			[_box(Vector3(0.3, 0.06, 0.3)), _at(Vector3(0.38, 2.86, 0)), BEAM],
		]
	)
	var root := _body(mesh)
	PropFactory._add_mesh(root, PropFactory.box_mesh(Vector3(0.22, 0.3, 0.22), PropFactory.FIRE, 4.0), Vector3(0.38, 2.66, 0))
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.4)
		light.light_energy = 1.4
		light.omni_range = 9.0
		light.position = Vector3(0.38, 2.6, 0)
		light.distance_fade_enabled = true
		light.distance_fade_begin = 60.0
		light.distance_fade_length = 20.0
		root.add_child(light)
	PropFactory._cylinder_collision(root, 0.15, 3.0)
	return root


static func make_barrels() -> StaticBody3D:
	var mesh := _cached("barrels", func() -> Array:
		return [
			[PropFactory.cylinder(0.38, 0.38, 1.0, 8), _at(Vector3(0, 0.5, 0)), WOOD],
			[PropFactory.cylinder(0.38, 0.38, 1.0, 8), _at(Vector3(0.8, 0.5, 0.2)), WOOD.darkened(0.1)],
			[PropFactory.cylinder(0.38, 0.38, 1.0, 8), _at(Vector3(0.4, 0.45, -0.75), Vector3(PI / 2, 0.4, 0)), WOOD.darkened(0.05)],
			[_box(Vector3(0.9, 0.9, 0.9)), _at(Vector3(-0.9, 0.45, 0.1), Vector3(0, 0.3, 0)), Color(0.6, 0.45, 0.28)],
			[_box(Vector3(0.7, 0.7, 0.7)), _at(Vector3(-0.85, 1.25, 0.1), Vector3(0, 0.8, 0)), Color(0.55, 0.42, 0.26)],
		]
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(2.4, 1.2, 1.4), Vector3(0, 0.6, -0.1))
	return root


static func make_cart() -> StaticBody3D:
	var mesh := _cached("cart", func() -> Array:
		var parts: Array = [
			[_box(Vector3(1.6, 0.12, 2.6)), _at(Vector3(0, 0.75, 0)), WOOD],
			[_box(Vector3(0.08, 0.5, 2.6)), _at(Vector3(-0.78, 1.05, 0)), WOOD.darkened(0.1)],
			[_box(Vector3(0.08, 0.5, 2.6)), _at(Vector3(0.78, 1.05, 0)), WOOD.darkened(0.1)],
			[_box(Vector3(1.6, 0.5, 0.08)), _at(Vector3(0, 1.05, 1.28)), WOOD.darkened(0.1)],
			[_box(Vector3(0.1, 0.1, 2.0)), _at(Vector3(-0.4, 0.6, -2.0)), BEAM],
			[_box(Vector3(0.1, 0.1, 2.0)), _at(Vector3(0.4, 0.6, -2.0)), BEAM],
			[PropFactory.sphere(0.6, 0.7, 7, 3), _at(Vector3(0, 1.2, 0.3), Vector3.ZERO, Vector3(1.1, 0.8, 1.6)), THATCH, 0.08, 7],
		]
		for x in [-0.88, 0.88]:
			parts.append([PropFactory.cylinder(0.5, 0.5, 0.1, 10), _at(Vector3(x, 0.5, 0.2), Vector3(0, 0, PI / 2)), BEAM])
		return parts
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(1.8, 1.4, 2.8), Vector3(0, 0.7, 0))
	return root


static func make_haystack() -> StaticBody3D:
	var mesh := _cached("hay", func() -> Array:
		return [
			[PropFactory.sphere(1.3, 2.0, 8, 4), _at(Vector3(0, 0.6, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.0)), THATCH, 0.12, 2],
			[PropFactory.cylinder(0.0, 1.1, 1.0, 8), _at(Vector3(0, 1.75, 0)), THATCH.darkened(0.08), 0.06, 3],
		]
	)
	var root := _body(mesh)
	PropFactory._cylinder_collision(root, 1.2, 2.0)
	return root


## Tramo de cerco de madera a lo largo de X.
static func make_fence(length: float) -> StaticBody3D:
	var key := "fence_%.1f" % length
	var mesh := _cached(key, func() -> Array:
		var parts: Array = []
		var posts := maxi(2, int(length / 2.0) + 1)
		for i in posts:
			parts.append([_box(Vector3(0.12, 1.1, 0.12)), _at(Vector3(-length / 2.0 + length * i / (posts - 1), 0.5, 0)), WOOD.darkened(0.15)])
		parts.append([_box(Vector3(length, 0.08, 0.06)), _at(Vector3(0, 0.75, 0)), WOOD])
		parts.append([_box(Vector3(length, 0.08, 0.06)), _at(Vector3(0, 0.4, 0)), WOOD])
		return parts
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(length, 1.0, 0.2), Vector3(0, 0.5, 0))
	return root


## Molino de viento. Las aspas (nodo "Blades") giran desde mainland_builder.gd.
static func make_windmill() -> StaticBody3D:
	var mesh := _cached("windmill", func() -> Array:
		var parts: Array = [
			[PropFactory.cylinder(2.2, 3.0, 9.0, 10), _at(Vector3(0, 4.5, 0)), PLASTER.darkened(0.05)],
			[PropFactory.cylinder(3.15, 3.15, 0.8, 10), _at(Vector3(0, 0.3, 0)), FOUNDATION, 0.03, 4],
			[PropFactory.cylinder(0.0, 2.8, 3.2, 10), _at(Vector3(0, 10.6, 0)), THATCH.darkened(0.1)],
			[_box(Vector3(1.2, 2.1, 0.2)), _at(Vector3(0, 1.75, -2.9), Vector3(-0.08, 0, 0)), WOOD.darkened(0.25)],
			[_box(Vector3(0.7, 0.8, 0.15)), _at(Vector3(0, 6.0, -2.45), Vector3(-0.08, 0, 0)), GLASS],
			[_box(Vector3(0.5, 0.5, 1.6)), _at(Vector3(0, 8.6, -2.6)), BEAM],
		]
		for i in 4:
			var angle := TAU * i / 10.0 + 0.4
			parts.append([_box(Vector3(0.14, 9.0, 0.14)), _at(Vector3(sin(angle) * 2.55, 4.5, cos(angle) * 2.55), Vector3(cos(angle) * 0.09, 0, -sin(angle) * 0.09)), BEAM])
		return parts
	)
	var root := _body(mesh)
	var blades := Node3D.new()
	blades.name = "Blades"
	blades.position = Vector3(0, 8.6, -3.5)
	root.add_child(blades)
	var blade_parts: Array = [[PropFactory.cylinder(0.3, 0.3, 0.5, 8), _at(Vector3.ZERO, Vector3(PI / 2, 0, 0)), BEAM]]
	for i in 4:
		var angle := TAU * i / 4.0
		var dir := Vector3(cos(angle), sin(angle), 0)
		blade_parts.append([_box(Vector3(0.16, 7.0, 0.12)), _at(dir * 3.5, Vector3(0, 0, angle - PI / 2)), BEAM])
		blade_parts.append([_box(Vector3(1.4, 5.4, 0.04)), _at(dir * 4.0 + Vector3(-dir.y, dir.x, 0) * 0.8, Vector3(0, 0, angle - PI / 2)), Color(0.9, 0.86, 0.76)])
	PropFactory._add_mesh(blades, PropFactory.combine(blade_parts), Vector3.ZERO)
	PropFactory._cylinder_collision(root, 2.8, 9.0)
	return root


# --- Castillo ------------------------------------------------------------------------------

## Muralla con almenas a lo largo de X (de -length/2 a length/2).
static func make_castle_wall(length: float, height: float) -> StaticBody3D:
	var key := "wall_%.1f_%.1f" % [length, height]
	var thickness := 2.4
	var mesh := _cached(key, func() -> Array:
		var parts: Array = [
			[_box(Vector3(length, height, thickness)), _at(Vector3(0, height / 2.0 - 0.5, 0)), CASTLE_STONE, 0.04, 9],
			[_box(Vector3(length, 0.4, thickness + 0.3)), _at(Vector3(0, height - 0.5, 0)), CASTLE_STONE.darkened(0.08)],
			[_box(Vector3(length, 1.2, thickness + 0.4)), _at(Vector3(0, 0.0, 0)), CASTLE_STONE.darkened(0.15), 0.05, 4],
		]
		var count := int(length / 1.6)
		for i in count:
			var x := -length / 2.0 + (i + 0.5) * length / count
			for z in [-thickness / 2.0 - 0.05, thickness / 2.0 + 0.05]:
				if i % 2 == 0:
					parts.append([_box(Vector3(length / count * 0.95, 1.1, 0.5)), _at(Vector3(x, height + 0.25, z)), CASTLE_STONE])
		# Hileras de piedra para dar textura.
		for row in int(height / 1.2):
			parts.append([_box(Vector3(length + 0.02, 0.06, thickness + 0.04)), _at(Vector3(0, row * 1.2 + 0.6, 0)), CASTLE_STONE.darkened(0.12)])
		return parts
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(length, height + 1.0, thickness), Vector3(0, height / 2.0, 0))
	return root


## Torre redonda con almenas y techo cónico de pizarra.
static func make_tower(radius: float, height: float, banner: bool = true) -> StaticBody3D:
	var key := "tower_%.1f_%.1f_%s" % [radius, height, banner]
	var mesh := _cached(key, func() -> Array:
		var parts: Array = [
			[PropFactory.cylinder(radius, radius * 1.08, height, 12), _at(Vector3(0, height / 2.0 - 0.5, 0)), CASTLE_STONE, 0.03, 5],
			[PropFactory.cylinder(radius + 0.4, radius + 0.4, 0.6, 12), _at(Vector3(0, height - 0.3, 0)), CASTLE_STONE.darkened(0.08)],
			[PropFactory.cylinder(0.0, radius + 0.5, radius * 2.0, 12), _at(Vector3(0, height + radius + 0.3, 0)), ROOF_SLATE],
		]
		for i in 10:
			var angle := TAU * i / 10.0
			parts.append([_box(Vector3(0.9, 0.9, 0.5)), _at(Vector3(sin(angle) * (radius + 0.2), height + 0.4, cos(angle) * (radius + 0.2)), Vector3(0, angle, 0)), CASTLE_STONE])
		for i in 3:
			var angle := TAU * i / 3.0 + 0.5
			parts.append([_box(Vector3(0.35, 0.9, 0.2)), _at(Vector3(sin(angle) * radius, height * 0.6, cos(angle) * radius), Vector3(0, angle, 0)), Color(0.12, 0.1, 0.1)])
		if banner:
			var tip := height + radius * 2.0 + 0.3
			parts.append([_box(Vector3(0.08, 2.2, 0.08)), _at(Vector3(0, tip + 0.6, 0)), BEAM])
			parts.append([_box(Vector3(1.3, 0.8, 0.04)), _at(Vector3(0.68, tip + 1.3, 0)), ROYAL_RED])
			parts.append([_box(Vector3(0.4, 0.3, 0.05)), _at(Vector3(0.68, tip + 1.3, 0)), GOLD])
		return parts
	)
	var root := _body(mesh)
	PropFactory._cylinder_collision(root, radius, height + 1.0)
	return root


## Portón del castillo: dos torres cuadradas unidas por un arco, con el portón abierto.
static func make_gatehouse() -> StaticBody3D:
	var mesh := _cached("gatehouse", func() -> Array:
		var parts: Array = []
		for side in [-1.0, 1.0]:
			parts.append([_box(Vector3(3.6, 11.0, 4.2)), _at(Vector3(side * 4.4, 5.0, 0)), CASTLE_STONE, 0.04, 6])
			for i in 3:
				parts.append([_box(Vector3(0.9, 1.0, 0.5)), _at(Vector3(side * 4.4 - 1.2 + i * 1.2, 11.0, -2.15)), CASTLE_STONE])
			parts.append([_box(Vector3(1.4, 2.6, 0.06)), _at(Vector3(side * 4.4, 6.5, -2.15)), ROYAL_RED])
			parts.append([_box(Vector3(0.6, 0.6, 0.07)), _at(Vector3(side * 4.4, 6.9, -2.17)), GOLD])
		parts.append([_box(Vector3(5.2, 3.2, 4.2)), _at(Vector3(0, 8.4, 0)), CASTLE_STONE])
		parts.append([_box(Vector3(5.4, 0.4, 4.6)), _at(Vector3(0, 6.7, 0)), CASTLE_STONE.darkened(0.15)])
		for i in 3:
			parts.append([_box(Vector3(0.9, 1.0, 0.5)), _at(Vector3(-1.6 + i * 1.6, 10.5, -2.15)), CASTLE_STONE])
		# Hojas del portón abiertas hacia adentro.
		for side in [-1.0, 1.0]:
			parts.append([_box(Vector3(2.5, 5.8, 0.25)), _at(Vector3(side * 2.4, 2.9, 2.2), Vector3(0, side * 1.3, 0)), WOOD.darkened(0.2)])
		return parts
	)
	var root := _body(mesh)
	for side in [-1.0, 1.0]:
		PropFactory._box_collision(root, Vector3(3.6, 12.0, 4.2), Vector3(side * 4.4, 5.5, 0))
	PropFactory._box_collision(root, Vector3(5.2, 3.6, 4.2), Vector3(0, 8.6, 0))
	return root


## Torre del homenaje: el edificio principal del castillo, donde vive la reina.
static func make_keep() -> StaticBody3D:
	var mesh := _cached("keep", func() -> Array:
		var parts: Array = [
			[_box(Vector3(14, 13, 11)), _at(Vector3(0, 6.0, 0)), CASTLE_STONE, 0.04, 8],
			[_box(Vector3(14.6, 0.5, 11.6)), _at(Vector3(0, 12.6, 0)), CASTLE_STONE.darkened(0.1)],
			[_box(Vector3(3.2, 4.6, 0.3)), _at(Vector3(0, 2.0, -5.55)), WOOD.darkened(0.3)],
			[PropFactory.cylinder(1.6, 1.6, 0.3, 10), _at(Vector3(0, 4.3, -5.55), Vector3(PI / 2, 0, 0)), WOOD.darkened(0.3)],
			[_box(Vector3(6, 0.3, 3)), _at(Vector3(0, 0.0, -7.0)), CASTLE_STONE.darkened(0.1)],
		]
		for i in 9:
			for z in [-5.75, 5.75]:
				parts.append([_box(Vector3(0.9, 1.0, 0.5)), _at(Vector3(-6.4 + i * 1.6, 13.3, z)), CASTLE_STONE])
		for i in 7:
			for x in [-7.25, 7.25]:
				parts.append([_box(Vector3(0.5, 1.0, 0.9)), _at(Vector3(x, 13.3, -4.8 + i * 1.6)), CASTLE_STONE])
		for x in [-4.5, 4.5]:
			for y in [4.5, 9.0]:
				parts.append([_box(Vector3(0.9, 1.8, 0.2)), _at(Vector3(x, y, -5.55)), Color(0.12, 0.1, 0.1)])
				parts.append([PropFactory.cylinder(0.45, 0.45, 0.2, 8), _at(Vector3(x, y + 0.9, -5.55), Vector3(PI / 2, 0, 0)), Color(0.12, 0.1, 0.1)])
		for x in [-2.4, 2.4]:
			parts.append([_box(Vector3(1.4, 4.0, 0.06)), _at(Vector3(x, 8.6, -5.55)), ROYAL_RED])
			parts.append([_box(Vector3(0.6, 0.6, 0.07)), _at(Vector3(x, 9.2, -5.57)), GOLD])
		# Torrecilla en una esquina.
		parts.append([PropFactory.cylinder(2.0, 2.0, 18.0, 10), _at(Vector3(5.5, 9.0, 3.5)), CASTLE_STONE])
		parts.append([PropFactory.cylinder(0.0, 2.5, 5.0, 10), _at(Vector3(5.5, 20.5, 3.5)), ROOF_SLATE])
		parts.append([_box(Vector3(0.08, 2.5, 0.08)), _at(Vector3(5.5, 24.0, 3.5)), BEAM])
		parts.append([_box(Vector3(1.8, 1.1, 0.05)), _at(Vector3(6.45, 24.6, 3.5)), ROYAL_RED])
		return parts
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(14, 14, 11), Vector3(0, 6.5, 0))
	PropFactory._cylinder_collision(root, 2.0, 18.0)
	return root


## Trono y alfombra roja para la audiencia con la reina.
static func make_throne() -> StaticBody3D:
	var mesh := _cached("throne", func() -> Array:
		return [
			[_box(Vector3(2.4, 0.25, 2.0)), _at(Vector3(0, 0.12, 0)), CASTLE_STONE.darkened(0.1)],
			[_box(Vector3(1.3, 0.6, 1.0)), _at(Vector3(0, 0.55, 0.1)), GOLD.darkened(0.2)],
			[_box(Vector3(1.3, 2.2, 0.25)), _at(Vector3(0, 1.4, 0.55)), GOLD.darkened(0.2)],
			[_box(Vector3(1.0, 1.6, 0.05)), _at(Vector3(0, 1.4, 0.41)), ROYAL_RED],
			[_box(Vector3(1.0, 0.12, 0.85)), _at(Vector3(0, 0.88, 0.05)), ROYAL_RED],
			[_box(Vector3(1.6, 0.03, 9.0)), _at(Vector3(0, 0.03, -5.4)), ROYAL_RED],
			[_box(Vector3(1.7, 0.02, 9.1)), _at(Vector3(0, 0.02, -5.4)), GOLD],
		]
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(1.4, 1.2, 1.2), Vector3(0, 0.6, 0.2))
	return root


## Muñeco de entrenamiento de la guardia.
static func make_training_dummy() -> StaticBody3D:
	var mesh := _cached("dummy", func() -> Array:
		return [
			[_box(Vector3(0.15, 2.0, 0.15)), _at(Vector3(0, 1.0, 0)), BEAM],
			[_box(Vector3(1.2, 0.12, 0.12)), _at(Vector3(0, 1.4, 0)), BEAM],
			[PropFactory.sphere(0.35, 0.8, 7, 4), _at(Vector3(0, 1.3, 0), Vector3.ZERO, Vector3(1, 1.2, 0.8)), THATCH, 0.05, 1],
			[PropFactory.sphere(0.2, 0.36, 7, 4), _at(Vector3(0, 2.05, 0)), THATCH.darkened(0.1)],
		]
	)
	var root := _body(mesh)
	PropFactory._cylinder_collision(root, 0.4, 2.2)
	return root


# --- Bandidos ------------------------------------------------------------------------------

static func make_tent(color: Color) -> StaticBody3D:
	var key := "tent_%s" % color.to_html()
	var mesh := _cached(key, func() -> Array:
		return [
			[_prism(Vector3(3.6, 2.4, 4.0)), _at(Vector3(0, 1.2, 0)), color, 0.04, 3],
			[_box(Vector3(1.0, 1.6, 0.05)), _at(Vector3(0, 0.8, -2.02)), color.darkened(0.45)],
			[_box(Vector3(0.1, 2.8, 0.1)), _at(Vector3(0, 1.4, -2.1)), BEAM],
			[_box(Vector3(0.1, 2.8, 0.1)), _at(Vector3(0, 1.4, 2.1)), BEAM],
		]
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(3.4, 2.2, 4.0), Vector3(0, 1.1, 0))
	return root


## Empalizada de troncos afilados a lo largo de X.
static func make_palisade(length: float) -> StaticBody3D:
	var key := "palisade_%.1f" % length
	var mesh := _cached(key, func() -> Array:
		var parts: Array = []
		var logs := int(length / 0.45)
		for i in logs:
			var x := -length / 2.0 + (i + 0.5) * length / logs
			var h := 2.8 + float((i * 37) % 5) * 0.15
			parts.append([PropFactory.cylinder(0.22, 0.24, h, 6), _at(Vector3(x, h / 2.0 - 0.3, 0)), WOOD.darkened(0.1 + 0.05 * (i % 3))])
			parts.append([PropFactory.cylinder(0.0, 0.22, 0.6, 6), _at(Vector3(x, h - 0.0, 0)), WOOD.lightened(0.1)])
		parts.append([_box(Vector3(length, 0.15, 0.15)), _at(Vector3(0, 1.8, -0.25)), BEAM])
		return parts
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(length, 3.2, 0.6), Vector3(0, 1.3, 0))
	return root


static func make_weapon_rack() -> StaticBody3D:
	var mesh := _cached("rack", func() -> Array:
		var parts: Array = [
			[_box(Vector3(2.0, 0.1, 0.1)), _at(Vector3(0, 1.4, 0)), BEAM],
			[_box(Vector3(2.0, 0.1, 0.1)), _at(Vector3(0, 0.3, 0)), BEAM],
			[_box(Vector3(0.12, 1.6, 0.12)), _at(Vector3(-0.95, 0.8, 0)), BEAM],
			[_box(Vector3(0.12, 1.6, 0.12)), _at(Vector3(0.95, 0.8, 0)), BEAM],
		]
		for i in 4:
			parts.append([_box(Vector3(0.05, 1.8, 0.05)), _at(Vector3(-0.6 + i * 0.4, 1.0, 0.08), Vector3(0, 0, 0.08)), Color(0.7, 0.72, 0.76)])
		return parts
	)
	var root := _body(mesh)
	PropFactory._box_collision(root, Vector3(2.0, 1.6, 0.4), Vector3(0, 0.8, 0))
	return root


# --- Trigo ---------------------------------------------------------------------------------

## Mata de trigo cosechable (da "wheat").
static func make_wheat(rng: RandomNumberGenerator) -> ResourceNode:
	var variant := rng.randi() % 3
	var mesh := _cached("wheat_%d" % variant, func() -> Array:
		var parts: Array = []
		var r := RandomNumberGenerator.new()
		r.seed = variant + 300
		var stalk := Color(0.82, 0.68, 0.32)
		for i in 14:
			var angle := r.randf() * TAU
			var radius := r.randf_range(0.0, 0.45)
			var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			var h := r.randf_range(0.9, 1.25)
			var tilt := Vector3(r.randf_range(-0.12, 0.12), 0, r.randf_range(-0.12, 0.12))
			parts.append([PropFactory.cylinder(0.012, 0.02, h, 3), _at(pos + Vector3(0, h / 2.0, 0), tilt), stalk.darkened(r.randf() * 0.12), 0.0, 0, 0.8])
			parts.append([PropFactory.sphere(0.035, 0.22, 4, 2), _at(pos + Vector3(tilt.z * -h, h + 0.08, tilt.x * h)), Color(0.93, 0.78, 0.4), 0.0, 0, 1.0])
		return parts
	)
	var node := ResourceNode.new()
	node.setup("wheat", "trigo", "Cosechar", 1, "")
	node.base_yield = 3
	node.visual = PropFactory._visual(node, mesh, PropFactory.NEAR)
	PropFactory._cylinder_collision(node, 0.4, 1.1)
	return node
