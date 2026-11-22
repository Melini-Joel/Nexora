class_name MainlandBuilder
extends Node3D
## Arma el continente de Valdoria sobre el terreno (ver TerrainGenerator.MAINLAND_SITES):
##   · Puerto Albor: muelle, el Albatros amarrado, plaza con mercado, taberna y herrería.
##   · Robledal: pueblo de granjeros con molino, casas de paja y campos de trigo.
##   · Castillo de Valdoria: murallas, torres, portón, torre del homenaje y la reina.
##   · Campamento bandido: empalizada, carpas y los bandidos de Rurik.
## Todo se calcula a partir del terreno, así que es igual en todos los jugadores.
## Los bandidos los maneja el servidor (aparecen, mueren y vuelven a aparecer).

const PLACES := {
	"harbor": ["Puerto Albor", 48.0], "village": ["Robledal", 64.0],
	"castle": ["Castillo de Valdoria", 40.0], "bandits": ["Campamento bandido", 30.0],
}
const BANDIT_COUNT := 5
const BANDIT_RESPAWN := 240.0
const CHIEF_RESPAWN := 600.0

var world: Node
var terrain: TerrainGenerator
var ship_visible := false
var _harbor_ship: Interactable
var _blades: Node3D
var _bandit_timers: Array = []  ## Segundos hasta que vuelve cada bandido muerto.
var _chief_timer := 0.0
var _chief_alive := false
var _tick := 0.0


func build(p_world: Node, world_seed: int) -> void:
	world = p_world
	terrain = world.terrain
	if terrain.mainland == null:
		return
	_build_harbor()
	_build_village(world_seed)
	_build_castle()
	_build_bandit_camp()
	set_ship_visible(false)


## ¿El punto está dentro de algún pueblo o campamento? (ahí no aparecen animales ni sombras)
func in_town(p: Vector2) -> bool:
	if terrain.mainland == null:
		return false
	for site: String in PLACES:
		var center := terrain.site_position(site)
		if p.distance_to(Vector2(center.x, center.z)) < PLACES[site][1]:
			return true
	return false


func place_name(pos: Vector3) -> String:
	if terrain == null or terrain.mainland == null:
		return ""
	for site: String in PLACES:
		var center := terrain.site_position(site)
		if Vector2(pos.x, pos.z).distance_to(Vector2(center.x, center.z)) < PLACES[site][1]:
			return PLACES[site][0]
	return ""


func set_ship_visible(value: bool) -> void:
	ship_visible = value
	if _harbor_ship:
		_harbor_ship.visible = value
		_harbor_ship.collision_layer = 1 if value else 0


# --- Ubicación -----------------------------------------------------------------------------

## Pone un objeto en un punto (relativo a "origin", girado "frame" radianes) sobre el terreno.
func _put(node: Node3D, origin: Vector3, offset: Vector2, frame: float, yaw: float, clear: float = 3.0, y: float = INF) -> Node3D:
	var p := Vector2(origin.x, origin.z) + offset.rotated(-frame)
	node.position = Vector3(p.x, terrain.get_height(p.x, p.y) if y == INF else y, p.y)
	node.rotation.y = frame + yaw
	add_child(node)
	if clear > 0.0:
		world._clear_zones.append([p, clear])
		world._mark_space(p)
	return node


func _point(origin: Vector3, offset: Vector2, frame: float) -> Vector3:
	var p := Vector2(origin.x, origin.z) + offset.rotated(-frame)
	return Vector3(p.x, terrain.get_height(p.x, p.y), p.y)


## Ángulo para que la fachada (-Z) mire desde "from" hacia "to".
static func _facing(from: Vector2, to: Vector2) -> float:
	var v := to - from
	return atan2(-v.x, -v.y)


# --- Puerto Albor --------------------------------------------------------------------------

func _build_harbor() -> void:
	var h := terrain.site_position("harbor")
	world.landmarks["harbor"] = h
	var west := Vector2(-1, 0)
	# Muelle: desde la costa hacia el mar (oeste).
	var shore := Vector2(h.x, h.z)
	for step in range(0, 140):
		var p := Vector2(h.x, h.z) + west * step
		if terrain.get_height(p.x, p.y) < TerrainGenerator.WATER_LEVEL + 0.3:
			shore = p - west
			break
	var dock := PropFactory.make_dock(20.0)
	dock.position = Vector3(shore.x, TerrainGenerator.WATER_LEVEL + 0.45, shore.y)
	dock.rotation.y = atan2(-west.x, -west.y)
	add_child(dock)
	var dock2 := PropFactory.make_dock(12.0)
	dock2.position = Vector3(shore.x, TerrainGenerator.WATER_LEVEL + 0.45, shore.y - 9.0)
	dock2.rotation.y = dock.rotation.y
	add_child(dock2)
	world._clear_zones.append([shore, 8.0])
	world.landmarks["harbor_dock"] = Vector3(shore.x, TerrainGenerator.WATER_LEVEL + 0.5, shore.y)

	# El Albatros amarrado al costado del muelle (aparece después del primer viaje).
	_harbor_ship = Interactable.new()
	_harbor_ship.name = "AlbatrosPuerto"
	_harbor_ship.dialog_id = "albatros"
	_harbor_ship.interact_text = "Subir al Albatros"
	_harbor_ship.position = Vector3(shore.x - 13.0, TerrainGenerator.WATER_LEVEL - 0.75, shore.y + 4.6)
	_harbor_ship.rotation.y = atan2(-west.x, -west.y)
	add_child(_harbor_ship)
	PropFactory.fill_ship_site(_harbor_ship, ShipDB.stage_count(), 0.0)
	# fill_ship_site corre el casco 6 m hacia +Z local: lo compensamos.
	for child in _harbor_ship.get_children():
		(child as Node3D).position.z -= 6.0
	world.landmarks["harbor_ship"] = _harbor_ship.position
	var land := Vector2(shore.x, shore.y) - west * 7.0
	world.landmarks["harbor_spawn"] = Vector3(land.x, terrain.get_height(land.x, land.y), land.y)

	world.landmarks["odon_npc"] = _point(Vector3(shore.x, 0, shore.y), Vector2(4.5, 3.0), 0.0)
	world._spawn_npc("odon", world.landmarks["odon_npc"])
	_put(MedievalProps.make_barrels(), Vector3(shore.x, 0, shore.y), Vector2(3.5, -4.5), 0.0, 0.3)
	_put(MedievalProps.make_barrels(), Vector3(shore.x, 0, shore.y), Vector2(5.0, 6.5), 0.0, 2.0)
	_put(MedievalProps.make_lamp_post(), Vector3(shore.x, 0, shore.y), Vector2(2.0, 2.2), 0.0, 0.0)

	# Plaza: casas al norte y al sur, la herrería al este y el mercado en el centro.
	var plaza := h + Vector3(4, 0, 0)
	var center := Vector2(plaza.x, plaza.z)
	world._clear_zones.append([center, 34.0])  # Sin árboles en el pueblo.
	var houses := [
		[Vector2(-12, -17), Vector2(7, 6), 2, MedievalProps.ROOF_TILE], [Vector2(-1, -19), Vector2(8, 6), 2, MedievalProps.ROOF_SLATE],
		[Vector2(11, -17), Vector2(7, 6.5), 1, MedievalProps.ROOF_TILE], [Vector2(-13, 17), Vector2(7, 6), 1, MedievalProps.ROOF_SLATE],
		[Vector2(15, 16), Vector2(7.5, 6), 2, MedievalProps.ROOF_TILE], [Vector2(22, 3), Vector2(6.5, 6), 1, MedievalProps.ROOF_TILE],
	]
	for i in houses.size():
		var entry: Array = houses[i]
		var offset: Vector2 = entry[0]
		var yaw := _facing(center + offset, center)
		_put(MedievalProps.make_house(entry[1], entry[2], entry[3], i), plaza, offset, 0.0, yaw, 6.5)
	var tavern_offset := Vector2(1, 18)
	_put(MedievalProps.make_tavern(), plaza, tavern_offset, 0.0, _facing(center + tavern_offset, center), 8.0)
	world.landmarks["bruno_npc"] = _point(plaza, Vector2(5, 12.5), 0.0)
	world._spawn_npc("bruno", world.landmarks["bruno_npc"])

	_put(MedievalProps.make_well(), plaza, Vector2(2, 0), 0.0, 0.0, 2.5)
	_put(MedievalProps.make_market_stall(Color(0.7, 0.2, 0.2), Color(0.85, 0.3, 0.2)), plaza, Vector2(-5, -7), 0.0, PI, 2.5)
	_put(MedievalProps.make_market_stall(Color(0.2, 0.4, 0.7), Color(0.85, 0.65, 0.3)), plaza, Vector2(6, -7.5), 0.0, PI, 2.5)
	_put(MedievalProps.make_market_stall(Color(0.25, 0.55, 0.3), Color(0.55, 0.75, 0.3)), plaza, Vector2(-5, 7.5), 0.0, 0.0, 2.5)
	world.landmarks["berta_npc"] = _point(plaza, Vector2(1, -5.5), 0.0)
	world._spawn_npc("berta", world.landmarks["berta_npc"])
	world.landmarks["marta_npc"] = _point(plaza, Vector2(-8, 4), 0.0)
	world._spawn_npc("marta", world.landmarks["marta_npc"])
	for offset in [Vector2(-9, 0), Vector2(12, 0), Vector2(2, -11), Vector2(2, 11)]:
		_put(MedievalProps.make_lamp_post(), plaza, offset, 0.0, 0.0, 1.0)

	# Herrería del puerto: mesa de trabajo, horno y yunque (para fabricar tablones, clavos...).
	_put(PropFactory.make_workbench(), plaza, Vector2(14, -6), 0.0, -PI / 2, 2.5)
	_put(PropFactory.make_furnace(), plaza, Vector2(17, -9), 0.0, -PI / 2, 2.5)
	_put(PropFactory.make_anvil(), plaza, Vector2(14.5, -9.5), 0.0, 0.0, 1.5)
	_put(PropFactory.make_campfire(), plaza, Vector2(13, 7), 0.0, 0.0, 2.0)
	_put(MedievalProps.make_cart(), plaza, Vector2(-16, 6), 0.0, 1.2, 2.5)


# --- Robledal ------------------------------------------------------------------------------

func _build_village(world_seed: int) -> void:
	var v := terrain.site_position("village")
	world.landmarks["village"] = v
	var center := Vector2(v.x, v.z)
	world._clear_zones.append([center, 31.0])
	var houses := [
		[Vector2(-19, -13), Vector2(6.5, 5.5)], [Vector2(-6, -21), Vector2(7, 5.5)], [Vector2(8, -19), Vector2(6, 5)],
		[Vector2(-23, 3), Vector2(6, 5.5)], [Vector2(-15, 17), Vector2(7, 6)], [Vector2(2, 12), Vector2(6, 5)],
	]
	for i in houses.size():
		var entry: Array = houses[i]
		var offset: Vector2 = entry[0]
		_put(MedievalProps.make_house(entry[1], 1, MedievalProps.THATCH, i + 1), v, offset, 0.0, _facing(center + offset, center), 6.0)
	var mill := _put(MedievalProps.make_windmill(), v, Vector2(20, -3), 0.0, 0.0, 5.0)
	_blades = mill.get_node("Blades")
	world.landmarks["windmill"] = mill.position
	world.landmarks["fermin_npc"] = _point(v, Vector2(17.5, -8.0), 0.0)
	world._spawn_npc("fermin", world.landmarks["fermin_npc"])
	world.landmarks["ines_npc"] = _point(v, Vector2(26, 20), 0.0)
	world._spawn_npc("ines", world.landmarks["ines_npc"])
	_put(MedievalProps.make_well(), v, Vector2(-4, -2), 0.0, 0.4, 2.5)
	_put(MedievalProps.make_haystack(), v, Vector2(27, 9), 0.0, 0.0, 2.0)
	_put(MedievalProps.make_haystack(), v, Vector2(9, 25), 0.0, 0.0, 2.0)
	_put(MedievalProps.make_cart(), v, Vector2(-3, 22), 0.0, 0.6, 2.5)
	_put(PropFactory.make_campfire(), v, Vector2(-8, 6), 0.0, 0.0, 2.0)
	for offset in [Vector2(6, 0), Vector2(-12, -4)]:
		_put(MedievalProps.make_lamp_post(), v, offset, 0.0, 0.0, 1.0)

	# Campos de trigo con cerco (el lado que da al pueblo queda abierto).
	var origin := terrain.mainland.center
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 4242
	var container := Node3D.new()
	container.name = "Wheat"
	add_child(container)
	var index := 0
	for field: Rect2 in TerrainGenerator.MAINLAND_FIELDS:
		var rect := Rect2(field.position + origin, field.size)
		var sides := [
			[rect.position + Vector2(rect.size.x / 2.0, 0), rect.size.x, 0.0],
			[rect.position + Vector2(rect.size.x / 2.0, rect.size.y), rect.size.x, 0.0],
			[rect.position + Vector2(rect.size.x, rect.size.y / 2.0), rect.size.y, PI / 2],
			[rect.position + Vector2(0, rect.size.y / 2.0), rect.size.y, PI / 2],
		]
		for side: Array in sides:
			var mid: Vector2 = side[0]
			if mid.distance_to(center) < rect.get_center().distance_to(center) - 4.0:
				continue  # Lado que mira al pueblo: sin cerco, para entrar.
			var fence := MedievalProps.make_fence(side[1])
			fence.position = Vector3(mid.x, terrain.get_height(mid.x, mid.y), mid.y)
			fence.rotation.y = side[2]
			add_child(fence)
		var x := rect.position.x + 1.5
		while x < rect.end.x - 1.0:
			var z := rect.position.y + 1.5
			while z < rect.end.y - 1.0:
				var p := Vector2(x + rng.randf_range(-0.5, 0.5), z + rng.randf_range(-0.5, 0.5))
				var node := MedievalProps.make_wheat(rng)
				var key := "W_%d" % index
				index += 1
				node.name = key
				node.position = Vector3(p.x, terrain.get_height(p.x, p.y) - 0.05, p.y)
				node.rotation.y = rng.randf() * TAU
				container.add_child(node)
				world.resource_nodes[key] = node
				z += 2.6
			x += 2.6


# --- Castillo de Valdoria ------------------------------------------------------------------

func _build_castle() -> void:
	var c := terrain.site_position("castle")
	world.landmarks["castle"] = c
	# El portón mira hacia el camino que llega desde el puerto.
	var road_end: Vector2 = TerrainGenerator.MAINLAND_ROADS[TerrainGenerator.MAINLAND_ROADS.size() - 1][0] + terrain.mainland.center
	var frame := _facing(Vector2(c.x, c.z), road_end)
	var y := c.y
	var s := 17.0
	var gate_gap := 6.2
	var side_length := s - gate_gap
	_put(MedievalProps.make_castle_wall(side_length, 9.0), c, Vector2(-(s + gate_gap) / 2.0, -s), frame, 0.0, 0.0, y)
	_put(MedievalProps.make_castle_wall(side_length, 9.0), c, Vector2((s + gate_gap) / 2.0, -s), frame, 0.0, 0.0, y)
	_put(MedievalProps.make_gatehouse(), c, Vector2(0, -s), frame, 0.0, 0.0, y)
	_put(MedievalProps.make_castle_wall(s * 2.0, 9.0), c, Vector2(0, s), frame, 0.0, 0.0, y)
	_put(MedievalProps.make_castle_wall(s * 2.0, 9.0), c, Vector2(-s, 0), frame, PI / 2, 0.0, y)
	_put(MedievalProps.make_castle_wall(s * 2.0, 9.0), c, Vector2(s, 0), frame, PI / 2, 0.0, y)
	for corner in [Vector2(-s, -s), Vector2(s, -s), Vector2(-s, s), Vector2(s, s)]:
		_put(MedievalProps.make_tower(3.0, 13.0), c, corner, frame, 0.0, 0.0, y)
	_put(MedievalProps.make_keep(), c, Vector2(0, 6), frame, 0.0, 0.0, y)
	_put(MedievalProps.make_throne(), c, Vector2(0, -2.5), frame, 0.0, 0.0, y)
	for offset in [Vector2(9, -9), Vector2(11, -5.5)]:
		_put(MedievalProps.make_training_dummy(), c, offset, frame, 0.0, 0.0, y)
	_put(MedievalProps.make_weapon_rack(), c, Vector2(-11, -9), frame, 0.3, 0.0, y)
	_put(MedievalProps.make_barrels(), c, Vector2(-12, 9), frame, 0.0, 0.0, y)
	_put(MedievalProps.make_well(), c, Vector2(-9, 0), frame, 0.0, 0.0, y)
	world._clear_zones.append([Vector2(c.x, c.z), 27.0])
	for offset in [Vector2(-4.5, -s - 3.5), Vector2(4.5, -s - 3.5)]:
		_put(MedievalProps.make_lamp_post(), c, offset, frame, 0.0, 0.0)

	var queen := _point(c, Vector2(0, -4.0), frame)
	queen.y = y
	world.landmarks["isolda_npc"] = queen
	world._spawn_npc("isolda", queen)
	var captain := _point(c, Vector2(-4.5, -11), frame)
	captain.y = y
	world.landmarks["galvan_npc"] = captain
	world._spawn_npc("galvan", captain)
	for i in 2:
		var key := "guard_%s" % ["a", "b"][i]
		world.landmarks[key] = _point(c, Vector2(-3.0 + i * 6.0, -s - 5.0), frame)
		world._spawn_npc(key, world.landmarks[key])


# --- Campamento bandido --------------------------------------------------------------------

func _build_bandit_camp() -> void:
	var b := terrain.site_position("bandits")
	world.landmarks["bandit_camp"] = b
	var radius := 12.0
	for i in 6:
		if i == 4:
			continue  # Entrada.
		var angle := TAU * (i + 0.5) / 6.0
		var mid := Vector2(cos(angle), sin(angle)) * radius * cos(PI / 6.0)
		var palisade := MedievalProps.make_palisade(radius)
		_put(palisade, b, mid, 0.0, 0.0, 0.0)
		palisade.rotation.y = -angle - PI / 2
	var colors := [Color(0.55, 0.45, 0.32), Color(0.4, 0.3, 0.25), Color(0.5, 0.2, 0.18), Color(0.45, 0.42, 0.3)]
	for i in 4:
		var angle := TAU * i / 4.0 + 0.3
		var offset := Vector2(cos(angle), sin(angle)) * 6.5
		_put(MedievalProps.make_tent(colors[i]), b, offset, 0.0, _facing(Vector2(b.x, b.z) + offset, Vector2(b.x, b.z)), 3.0)
	_put(PropFactory.make_campfire(), b, Vector2.ZERO, 0.0, 0.0, 2.0)
	_put(MedievalProps.make_weapon_rack(), b, Vector2(2.5, -3.0), 0.0, 0.5, 1.0)
	_put(MedievalProps.make_barrels(), b, Vector2(-3.0, 3.0), 0.0, 1.0, 1.5)
	world._clear_zones.append([Vector2(b.x, b.z), 13.0])


# --- Bandidos (servidor) -------------------------------------------------------------------

func spawn_bandits() -> void:
	if terrain == null or terrain.mainland == null:
		return
	for i in BANDIT_COUNT:
		_spawn_bandit("bandit")


func _spawn_bandit(species: String) -> void:
	var b: Vector3 = world.landmarks["bandit_camp"]
	var angle := randf() * TAU
	var p := Vector2(b.x, b.z) + Vector2(cos(angle), sin(angle)) * (1.5 if species == "bandit_chief" else randf_range(3.0, 8.0))
	world._spawn_creature(species, Vector3(p.x, terrain.get_height(p.x, p.y) + 0.5, p.y))
	if species == "bandit_chief":
		_chief_alive = true


## Lo avisa world.gd cuando muere un bandido.
func on_bandit_died(species: String) -> void:
	if species == "bandit_chief":
		_chief_alive = false
		_chief_timer = CHIEF_RESPAWN
	else:
		_bandit_timers.append(BANDIT_RESPAWN)


func _players_near(pos: Vector3, distance: float) -> bool:
	for player in world.get_players():
		if (player.global_position as Vector3).distance_to(pos) < distance:
			return true
	return false


func _process(delta: float) -> void:
	if _blades:
		var spinning := QuestManager.get_status("f_mill") == "done"
		_blades.rotation.z += delta * (0.9 if spinning else 0.0)
	if not world or not world.generated or not multiplayer.is_server() or not Network.is_online():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if terrain.mainland == null:
		return
	var camp: Vector3 = world.landmarks["bandit_camp"]
	var watched := _players_near(camp, 45.0)  # No aparecen bandidos frente a los jugadores.
	for i in range(_bandit_timers.size() - 1, -1, -1):
		_bandit_timers[i] -= 1.0
		if _bandit_timers[i] <= 0.0 and not watched:
			_bandit_timers.remove_at(i)
			_spawn_bandit("bandit")
	_chief_timer -= 1.0
	var chief_wanted := QuestManager.get_status("g_bandits") == "done"
	if chief_wanted and not _chief_alive and _chief_timer <= 0.0 and not watched:
		_spawn_bandit("bandit_chief")
