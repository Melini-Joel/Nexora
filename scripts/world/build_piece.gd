class_name BuildPiece
extends StaticBody3D
## Pieza construida por los jugadores (cimiento, pared, puerta, techo, fogata).
## La crea el servidor y el MultiplayerSpawner la replica a todos (también a los que entran tarde).
##
## Convenciones (cuadrícula de 3 m):
##   cimiento: origen en el centro de la celda, a la altura del piso
##   pared/puerta: origen en el centro del borde de la celda, a la altura del piso
##   techo: origen en el centro de la celda, a 3 m del piso (su parte de arriba es otro piso)

const WOOD := Color(0.56, 0.39, 0.22)
const STONE := Color(0.58, 0.57, 0.55)

var piece_id := ""
var owner_name := ""  ## Quién la construyó (las camas son personales).
var door_open := false:
	set(value):
		door_open = value
		if _door:
			Sound.play("door", global_position + Vector3.UP)
			create_tween().tween_property(_door, "rotation:y", -1.6 if value else 0.0, 0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

var _door: Node3D
var _world: Node

static var _mesh_cache: Dictionary = {}


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	var data := BuildDB.get_piece(piece_id)
	var kind: String = data.get("kind", "foundation")
	if kind == "campfire":
		add_child(PropFactory.make_campfire())
	elif kind in ["storage", "bed"]:
		PropFactory._add_mesh(self, piece_mesh(piece_id), Vector3.ZERO)
		for box in collision_boxes(kind):
			PropFactory._box_collision(self, box[0], box[1])
		if kind == "bed":
			var label := Label3D.new()
			label.text = "Cama de %s" % owner_name
			label.position = Vector3(0, 1.1, 0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 28
			label.outline_size = 8
			label.pixel_size = 0.005
			label.modulate = Color(1, 1, 1, 0.8)
			add_child(label)
	else:
		PropFactory._add_mesh(self, piece_mesh(piece_id), Vector3.ZERO)
		for box in collision_boxes(kind):
			PropFactory._box_collision(self, box[0], box[1])
	if kind == "doorway":
		_build_door(data)
	if _world:
		_world.register_piece(self)
		if _world.generated and Time.get_ticks_msec() - _world.generated_at_ms > 4000:
			Sound.play("build", global_position + Vector3.UP)


func _exit_tree() -> void:
	if _world:
		_world.unregister_piece(self)


func kind() -> String:
	return BuildDB.get_piece(piece_id).get("kind", "")


func floor_height() -> float:
	## Altura de piso que aporta esta pieza (para apoyar paredes encima).
	match kind():
		"foundation":
			return global_position.y
		"roof":
			return global_position.y + 0.25
	return INF


func get_interact_text() -> String:
	match kind():
		"doorway":
			return "Cerrar puerta" if door_open else "Abrir puerta"
		"storage":
			return "Abrir caja"
		"bed":
			if owner_name == Network.player_name:
				return "Tu cama: reaparecés acá al morir"
			return "Dormir acá (reaparecer en esta cama)"
	return ""


func _build_door(data: Dictionary) -> void:
	var hinge := AnimatableBody3D.new()
	hinge.sync_to_physics = false
	hinge.position = Vector3(-0.55, 0, 0)
	add_child(hinge)
	var color: Color = (WOOD if data["material"] == "wood" else WOOD.darkened(0.2))
	PropFactory._add_mesh(hinge, PropFactory.combine([
		[PropFactory.box(Vector3(1.1, 2.2, 0.1)), PropFactory._at(Vector3(0.55, 1.1, 0)), color],
		[PropFactory.box(Vector3(1.0, 0.1, 0.12)), PropFactory._at(Vector3(0.55, 0.5, 0)), color.darkened(0.2)],
		[PropFactory.box(Vector3(1.0, 0.1, 0.12)), PropFactory._at(Vector3(0.55, 1.7, 0)), color.darkened(0.2)],
		[PropFactory.box(Vector3(0.08, 0.08, 0.16)), PropFactory._at(Vector3(0.95, 1.1, 0)), Color(0.3, 0.3, 0.3)],
	]), Vector3.ZERO)
	PropFactory._box_collision(hinge, Vector3(1.1, 2.2, 0.1), Vector3(0.55, 1.1, 0))
	_door = hinge
	_door.rotation.y = -1.6 if door_open else 0.0


## Cajas de colisión por tipo: [tamaño, posición].
static func collision_boxes(kind: String) -> Array:
	var g := BuildDB.GRID
	var h := BuildDB.WALL_HEIGHT
	match kind:
		"foundation":
			return [[Vector3(g, 1.2, g), Vector3(0, -0.6, 0)]]
		"wall":
			return [[Vector3(g, h, 0.25), Vector3(0, h / 2, 0)]]
		"doorway":
			return [
				[Vector3(0.95, h, 0.25), Vector3(-1.025, h / 2, 0)],
				[Vector3(0.95, h, 0.25), Vector3(1.025, h / 2, 0)],
				[Vector3(1.1, h - 2.2, 0.25), Vector3(0, 2.2 + (h - 2.2) / 2, 0)],
			]
		"roof":
			return [[Vector3(g, 0.25, g), Vector3(0, 0.125, 0)]]
		"storage":
			return [[Vector3(1.3, 0.8, 0.8), Vector3(0, 0.4, 0)]]
		"bed":
			return [[Vector3(1.1, 0.5, 2.1), Vector3(0, 0.25, 0)]]
	return []


## Malla de la pieza (también se usa para la vista previa al construir).
static func piece_mesh(id: String) -> Mesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var data := BuildDB.get_piece(id)
	var stone: bool = data.get("material", "wood") == "stone"
	var base := STONE if stone else WOOD
	var g := BuildDB.GRID
	var h := BuildDB.WALL_HEIGHT
	var parts: Array = []
	match data.get("kind", ""):
		"foundation":
			parts.append([PropFactory.box(Vector3(g, 1.2, g)), PropFactory._at(Vector3(0, -0.62, 0)), base.darkened(0.25)])
			for i in 6:
				parts.append([PropFactory.box(Vector3(g / 6.0 - 0.02, 0.06, g)), PropFactory._at(Vector3(-g / 2 + g / 12.0 + i * g / 6.0, -0.02, 0)),
					base.darkened(0.06 * (i % 3)) if not stone else base.lightened(0.05 * (i % 2))])
		"wall":
			parts.append_array(_wall_parts(Vector3(g, h, 0.25), Vector3(0, h / 2, 0), base, stone))
		"doorway":
			parts.append_array(_wall_parts(Vector3(0.95, h, 0.25), Vector3(-1.025, h / 2, 0), base, stone))
			parts.append_array(_wall_parts(Vector3(0.95, h, 0.25), Vector3(1.025, h / 2, 0), base, stone))
			parts.append([PropFactory.box(Vector3(1.1, h - 2.2, 0.25)), PropFactory._at(Vector3(0, 2.2 + (h - 2.2) / 2, 0)), base.darkened(0.15)])
		"roof":
			for i in 6:
				parts.append([PropFactory.box(Vector3(g, 0.25, g / 6.0 - 0.02)), PropFactory._at(Vector3(0, 0.125, -g / 2 + g / 12.0 + i * g / 6.0)),
					base.darkened(0.06 * (i % 3))])
		"campfire":
			parts.append([PropFactory.cylinder(0.9, 0.9, 0.3, 8), PropFactory._at(Vector3(0, 0.15, 0)), Color(0.5, 0.5, 0.5)])
		"storage":
			parts.append([PropFactory.box(Vector3(1.3, 0.7, 0.8)), PropFactory._at(Vector3(0, 0.35, 0)), WOOD.darkened(0.1)])
			parts.append([PropFactory.box(Vector3(1.34, 0.12, 0.84)), PropFactory._at(Vector3(0, 0.74, 0)), WOOD.lightened(0.05)])
			for x in [-0.5, 0.5]:
				parts.append([PropFactory.box(Vector3(0.08, 0.82, 0.84)), PropFactory._at(Vector3(x, 0.4, 0)), Color(0.32, 0.3, 0.28)])
			parts.append([PropFactory.box(Vector3(0.14, 0.16, 0.05)), PropFactory._at(Vector3(0, 0.6, -0.42)), Color(0.85, 0.7, 0.3)])
		"bed":
			parts.append([PropFactory.box(Vector3(1.1, 0.3, 2.1)), PropFactory._at(Vector3(0, 0.15, 0)), WOOD])
			parts.append([PropFactory.box(Vector3(1.0, 0.16, 1.95)), PropFactory._at(Vector3(0, 0.38, 0)), Color(0.88, 0.85, 0.78)])
			parts.append([PropFactory.box(Vector3(0.6, 0.12, 0.35)), PropFactory._at(Vector3(0, 0.52, -0.75)), Color(0.95, 0.95, 0.92)])
			parts.append([PropFactory.box(Vector3(1.04, 0.06, 1.2)), PropFactory._at(Vector3(0, 0.48, 0.35)), Color(0.35, 0.5, 0.7)])
			parts.append([PropFactory.box(Vector3(1.1, 0.7, 0.1)), PropFactory._at(Vector3(0, 0.35, -1.05)), WOOD.darkened(0.15)])
	var mesh := PropFactory.combine(parts)
	_mesh_cache[id] = mesh
	return mesh


static func _wall_parts(size: Vector3, center: Vector3, base: Color, stone: bool) -> Array:
	var parts: Array = []
	if stone:
		var rows := 6
		for r in rows:
			var y := center.y - size.y / 2 + (r + 0.5) * size.y / rows
			parts.append([PropFactory.box(Vector3(size.x, size.y / rows - 0.04, size.z)), PropFactory._at(Vector3(center.x, y, center.z)),
				base.darkened(0.05 * (r % 3))])
	else:
		var planks := maxi(1, roundi(size.x / 0.5))
		for p in planks:
			var x := center.x - size.x / 2 + (p + 0.5) * size.x / planks
			parts.append([PropFactory.box(Vector3(size.x / planks - 0.03, size.y, size.z)), PropFactory._at(Vector3(x, center.y, center.z)),
				base.darkened(0.07 * (p % 3))])
		parts.append([PropFactory.box(Vector3(size.x, 0.16, size.z + 0.06)), PropFactory._at(Vector3(center.x, center.y - size.y / 2 + 0.5, center.z)), base.darkened(0.3)])
		parts.append([PropFactory.box(Vector3(size.x, 0.16, size.z + 0.06)), PropFactory._at(Vector3(center.x, center.y + size.y / 2 - 0.4, center.z)), base.darkened(0.3)])
	return parts
