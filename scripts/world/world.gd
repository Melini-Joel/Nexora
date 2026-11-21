extends Node3D
## El mundo compartido. Genera la isla (igual en todos los peers gracias a la semilla) y
## contiene la lógica autoritativa del servidor: aparición de jugadores, recolección,
## inventarios, bolsas en el suelo y reaparición de recursos.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DROP_SCENE := preload("res://scenes/item_drop.tscn")
const TREE_COUNT := 260
const ROCK_COUNT := 130
const ORE_CHANCE := 0.3  ## Porcentaje de rocas que tienen metal.
const BUSH_COUNT := 450
const RESPAWN_TIME := 90.0  ## Segundos hasta que reaparece un recurso agotado.
const GATHER_RANGE := 6.0  ## Distancia máxima aceptada por el servidor (anti-trampas).
const GATHER_MIN_INTERVAL_MS := 350
const FIBER_COUNT := 160
const STARTER_KIT := [["stone_hatchet", 1]]
const MAX_CRAFT_QUEUE := 8

var generated := false
var terrain: TerrainGenerator
## Lugares importantes para misiones y cinemáticas: "spawn", "monolith".
var landmarks: Dictionary = {}
## nombre (String) -> ResourceNode
var resource_nodes: Dictionary = {}

# Solo en el servidor:
var _respawn_timers: Dictionary = {}
var _inventories: Dictionary = {}  ## peer_id -> Inventory
var _saved_inventories: Dictionary = {}  ## nombre -> Array (para volver a entrar sin perder todo)
var _last_gather_ms: Dictionary = {}
var _drop_counter := 0
var _craft_queues: Dictionary = {}  ## peer_id -> [{recipe, remaining, time_left, time}]
## Zonas donde no se ponen árboles ni rocas (campamento, NPCs, estaciones): [Vector2, radio]
var _clear_zones: Array = []

var _crystal: Node3D
var _crystal_base_y := 0.0
var _fire_light: OmniLight3D
var _sun: DirectionalLight3D
var _environment: Environment
var _time := 0.0

@onready var players_root: Node3D = $Players
@onready var drops_root: Node3D = $Drops
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var drop_spawner: MultiplayerSpawner = $DropSpawner


func _ready() -> void:
	add_to_group("world")
	player_spawner.add_spawnable_scene(PLAYER_SCENE.resource_path)
	drop_spawner.add_spawnable_scene(DROP_SCENE.resource_path)
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)


func _process(delta: float) -> void:
	if not generated:
		return
	_time += delta
	if _crystal:
		_crystal.rotation.y = _time * 0.8
		_crystal.position.y = _crystal_base_y + sin(_time * 1.5) * 0.25
	if _fire_light:
		_fire_light.light_energy = 2.0 + sin(_time * 17.0) * 0.25 + sin(_time * 7.3) * 0.2
	if multiplayer.is_server():
		_update_respawns(delta)
		_update_crafting(delta)


# --- Generación --------------------------------------------------------------------

func generate(world_seed: int) -> void:
	if generated:
		return
	_build_environment()
	terrain = TerrainGenerator.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(world_seed)
	_build_water()
	_place_landmarks()
	_place_resources(world_seed)
	_place_bushes(world_seed)
	generated = true
	Game.world_generated.emit()


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.5, 0.82)
	sky_material.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky_material.ground_horizon_color = Color(0.5, 0.65, 0.75)
	sky_material.ground_bottom_color = Color(0.12, 0.3, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.88)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.3

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	_sun = sun
	_environment = env
	_apply_graphics()
	Settings.changed.connect(_apply_graphics)


## Calidad gráfica elegida en Opciones (sombras y brillo).
func _apply_graphics() -> void:
	var quality: String = Settings.get_value("quality")
	_sun.shadow_enabled = quality != "low"
	_sun.directional_shadow_max_distance = 140.0 if quality == "high" else 70.0
	_environment.glow_enabled = quality != "low"


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * TerrainGenerator.SIZE * 16.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.42, 0.6, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.2
	plane.material = mat
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.position.y = TerrainGenerator.WATER_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _place_landmarks() -> void:
	landmarks["spawn"] = Vector3(0, terrain.get_height(0, 0), 0)
	var campfire := PropFactory.make_campfire()
	campfire.position = landmarks["spawn"]
	add_child(campfire)
	_fire_light = campfire.get_node("FireLight")

	var top := terrain.find_highest_point(TerrainGenerator.SIZE * 0.38)
	landmarks["monolith"] = top
	var monolith := PropFactory.make_monolith()
	monolith.position = top - Vector3(0, 0.3, 0)
	add_child(monolith)
	_crystal = monolith.get_node("Crystal")
	_crystal_base_y = _crystal.position.y
	_clear_zones.append([Vector2(0, 0), TerrainGenerator.SPAWN_RADIUS])
	_clear_zones.append([Vector2(top.x, top.z), 5.0])
	_place_settlements()


## Campamento, forja, ermitaño, muelle y mirador. Todo se calcula a partir del terreno,
## así que es igual para todos los jugadores.
func _place_settlements() -> void:
	var monolith: Vector3 = landmarks["monolith"]
	var to_monolith := Vector2(monolith.x, monolith.z).normalized()

	# Campamento: mesa de trabajo y Tomás.
	landmarks["workbench"] = _ground(Vector2(5.5, -3.0))
	_place_prop(PropFactory.make_workbench(), landmarks["workbench"], Vector3.ZERO)
	landmarks["camp_npc"] = _ground(Vector2(6.8, -0.2))
	_spawn_npc("tomas", landmarks["camp_npc"])

	# Forja de Ilse: a mitad de camino hacia el monolito, en un lugar plano.
	var forge := _find_flat_near(Vector2(monolith.x, monolith.z) * 0.45, 22.0)
	landmarks["furnace"] = forge
	_place_prop(PropFactory.make_furnace(), forge, Vector3.ZERO, -to_monolith)
	_place_prop(PropFactory.make_anvil(), _ground(Vector2(forge.x, forge.z) + Vector2(2.2, 1.0)), Vector3.ZERO)
	landmarks["forge_npc"] = _ground(Vector2(forge.x, forge.z) + Vector2(-2.2, -1.6))
	_spawn_npc("ilse", landmarks["forge_npc"])
	_clear_zones.append([Vector2(forge.x, forge.z), 6.0])

	# Ermitaño: en la ladera, antes de la cima.
	landmarks["hermit_npc"] = _find_flat_near(Vector2(monolith.x, monolith.z) - to_monolith * 16.0, 10.0, 0.5)
	_spawn_npc("eco", landmarks["hermit_npc"])
	_clear_zones.append([Vector2(landmarks["hermit_npc"].x, landmarks["hermit_npc"].z), 4.0])

	# Muelle de Nilo: en la costa del lado opuesto al monolito.
	_place_dock(-to_monolith)

	# Mirador: el punto más alto lejos del monolito.
	var lookout := terrain.find_highest_point(TerrainGenerator.SIZE * 0.4, Vector2(monolith.x, monolith.z), 70.0)
	landmarks["lookout"] = lookout
	_place_prop(PropFactory.make_cairn(), lookout - Vector3(0, 0.2, 0), Vector3.ZERO)
	_clear_zones.append([Vector2(lookout.x, lookout.z), 4.0])


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.get_height(p.x, p.y), p.y)


func _place_prop(prop: Node3D, pos: Vector3, rot: Vector3, facing: Vector2 = Vector2.ZERO) -> void:
	prop.position = pos
	prop.rotation = rot
	if facing != Vector2.ZERO:
		prop.rotation.y = atan2(-facing.x, -facing.y)
	add_child(prop)
	_clear_zones.append([Vector2(pos.x, pos.z), 3.5])


func _spawn_npc(id: String, pos: Vector3) -> void:
	var npc := NPC.new()
	npc.setup(id)
	npc.position = pos
	add_child(npc)
	_clear_zones.append([Vector2(pos.x, pos.z), 3.5])


## Busca en espiral un lugar plano y sobre el agua cerca de un punto.
func _find_flat_near(center: Vector2, radius: float, max_slope: float = 0.25) -> Vector3:
	for ring in 12:
		var r := radius * ring / 11.0
		var samples := maxi(1, ring * 6)
		for i in samples:
			var angle := TAU * i / samples
			var p := center + Vector2(cos(angle), sin(angle)) * r
			var h := terrain.get_height(p.x, p.y)
			if h > TerrainGenerator.WATER_LEVEL + 1.5 and terrain.get_slope(p.x, p.y) <= max_slope:
				return Vector3(p.x, h, p.y)
	return _ground(center)


func _place_dock(direction: Vector2) -> void:
	for attempt in 12:
		var dir := direction.rotated(attempt * 0.5 * (1 if attempt % 2 == 0 else -1))
		for step in range(20, int(TerrainGenerator.SIZE * 0.5)):
			var p := dir * step
			if terrain.get_height(p.x, p.y) < TerrainGenerator.WATER_LEVEL + 0.3:
				var shore := dir * (step - 1)
				var dock := PropFactory.make_dock(10.0)
				dock.position = Vector3(shore.x, TerrainGenerator.WATER_LEVEL + 0.45, shore.y)
				dock.rotation.y = atan2(-dir.x, -dir.y)
				add_child(dock)
				var npc_spot := dir * (step - 3)
				landmarks["dock_npc"] = _ground(npc_spot)
				_spawn_npc("nilo", landmarks["dock_npc"])
				_clear_zones.append([shore, 6.0])
				return
	# Si no hay costa (no debería pasar), Nilo se queda cerca del campamento.
	landmarks["dock_npc"] = _ground(Vector2(-7, 3))
	_spawn_npc("nilo", landmarks["dock_npc"])


func is_near_station(pos: Vector3, station: String) -> bool:
	return landmarks.has(station) and pos.distance_to(landmarks[station]) <= RecipeDB.STATION_RANGE


func _place_resources(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var container := Node3D.new()
	container.name = "Resources"
	add_child(container)
	var used: Array[Vector2] = [Vector2(landmarks["monolith"].x, landmarks["monolith"].z)]

	for i in TREE_COUNT:
		var spot := _find_spot(rng, TerrainGenerator.WATER_LEVEL + 1.2, 19.0, 0.3, 2.6, used)
		if spot == Vector3.INF:
			continue
		var tree := PropFactory.make_tree(rng)
		_add_resource(container, tree, "Tree_%d" % i, spot - Vector3(0, 0.1, 0), rng.randf() * TAU)

	for i in ROCK_COUNT:
		var spot := _find_spot(rng, TerrainGenerator.WATER_LEVEL + 0.5, 30.0, 0.55, 3.0, used)
		if spot == Vector3.INF:
			continue
		var is_ore := rng.randf() < ORE_CHANCE
		var rock := PropFactory.make_rock(rng, is_ore)
		_add_resource(container, rock, "Rock_%d" % i, spot - Vector3(0, 0.2, 0), rng.randf() * TAU)

	for i in FIBER_COUNT:
		var spot := _find_spot(rng, TerrainGenerator.WATER_LEVEL + 0.8, 16.0, 0.35, 1.5, used)
		if spot == Vector3.INF:
			continue
		var plant := PropFactory.make_fiber_plant(rng)
		_add_resource(container, plant, "Fiber_%d" % i, spot - Vector3(0, 0.05, 0), rng.randf() * TAU)


func _add_resource(container: Node3D, node: ResourceNode, key: String, pos: Vector3, yaw: float) -> void:
	node.name = key
	node.position = pos
	node.rotation.y = yaw
	container.add_child(node)
	resource_nodes[key] = node


## Busca un lugar válido para un objeto. Determinístico: misma semilla, mismos lugares.
func _find_spot(rng: RandomNumberGenerator, min_h: float, max_h: float, max_slope: float,
		min_distance: float, used: Array[Vector2]) -> Vector3:
	var limit := TerrainGenerator.SIZE * 0.46
	for attempt in 30:
		var p := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		if _in_clear_zone(p):
			continue
		var h := terrain.get_height(p.x, p.y)
		if h < min_h or h > max_h or terrain.get_slope(p.x, p.y) > max_slope:
			continue
		var free := true
		for other in used:
			if other.distance_squared_to(p) < min_distance * min_distance:
				free = false
				break
		if free:
			used.append(p)
			return Vector3(p.x, h, p.y)
	return Vector3.INF


func _in_clear_zone(p: Vector2) -> bool:
	for zone in _clear_zones:
		if p.distance_to(zone[0]) < zone[1]:
			return true
	return false


## Arbustos decorativos con MultiMesh: cientos de objetos en una sola llamada de dibujo.
func _place_bushes(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 99
	var transforms: Array[Transform3D] = []
	var limit := TerrainGenerator.SIZE * 0.46
	for i in BUSH_COUNT * 3:
		if transforms.size() >= BUSH_COUNT:
			break
		var p := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 0.8 or h > 18.0 or _in_clear_zone(p):
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.3))
		transforms.append(Transform3D(basis, Vector3(p.x, h + 0.1, p.y)))

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = PropFactory.bush_mesh()
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var bushes := MultiMeshInstance3D.new()
	bushes.name = "Bushes"
	bushes.multimesh = multimesh
	add_child(bushes)


# --- Jugadores (servidor) -------------------------------------------------------------

func get_players() -> Array[Node]:
	return players_root.get_children()


func get_spawn_point(peer_id: int) -> Vector3:
	var angle := float(peer_id % Network.MAX_PLAYERS) / Network.MAX_PLAYERS * TAU
	var p := Vector2(cos(angle), sin(angle)) * 4.0
	return Vector3(p.x, terrain.get_height(p.x, p.y) + 0.3, p.y)


func _on_player_joined(peer_id: int) -> void:
	if players_root.has_node(str(peer_id)):
		return
	var player_name: String = Network.players[peer_id]["name"]
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.player_name = player_name
	player.position = get_spawn_point(peer_id)
	player.sync_pos = player.position
	players_root.add_child(player, true)

	# Inventario: si ya había jugado en esta partida, recupera lo que tenía.
	var inventory := Inventory.new()
	if _saved_inventories.has(player_name):
		inventory.load_from(_saved_inventories[player_name])
		_saved_inventories.erase(player_name)
	else:
		for entry in STARTER_KIT:
			inventory.add(entry[0], entry[1])
	_inventories[peer_id] = inventory
	_send_inventory(peer_id)


func _on_player_left(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		var inventory: Inventory = _inventories.get(peer_id)
		if inventory:
			# Lo que estaba fabricando vuelve al inventario.
			for job in _craft_queues.get(peer_id, []):
				var ingredients: Dictionary = RecipeDB.get_recipe(job["recipe"])["ingredients"]
				for item: String in ingredients:
					inventory.add(item, int(ingredients[item]) * int(job["remaining"]))
			_saved_inventories[player.player_name] = inventory.to_array()
		player.queue_free()
	_inventories.erase(peer_id)
	_craft_queues.erase(peer_id)
	_last_gather_ms.erase(peer_id)


## Estado que necesita un jugador que entra a una partida ya empezada.
func get_state_for_new_player() -> Dictionary:
	return {"depleted": _respawn_timers.keys()}


func apply_state(state: Dictionary) -> void:
	for node_name in state.get("depleted", []):
		_set_node_state(node_name, true)


# --- Acciones de los jugadores ---------------------------------------------------------
# Todo pasa por el servidor: el cliente pide, el servidor valida y responde con el
# inventario actualizado. Así nadie puede hacer trampa duplicando objetos.

func send_action(action: String, args: Array = []) -> void:
	if multiplayer.is_server():
		_handle_action(multiplayer.get_unique_id(), action, args)
	else:
		_request_action.rpc_id(1, action, args)


@rpc("any_peer", "reliable")
func _request_action(action: String, args: Array) -> void:
	if multiplayer.is_server():
		_handle_action(multiplayer.get_remote_sender_id(), action, args)


func _handle_action(peer_id: int, action: String, args: Array) -> void:
	var inventory: Inventory = _inventories.get(peer_id)
	if inventory == null:
		return
	var changed := false
	match action:
		"gather":
			if args.size() == 1:
				_server_gather(peer_id, str(args[0]))
		"pickup":
			if args.size() == 1:
				_server_pickup(peer_id, str(args[0]))
		"move":
			if args.size() == 2:
				changed = inventory.move(int(args[0]), int(args[1]))
		"split":
			if args.size() == 1:
				changed = inventory.split(int(args[0]))
		"quick_move":
			if args.size() == 1:
				changed = inventory.quick_move(int(args[0]))
		"craft":
			if args.size() == 2:
				_server_craft(peer_id, str(args[0]), int(args[1]))
		"craft_cancel":
			if args.size() == 1:
				_server_craft_cancel(peer_id, int(args[0]))
		"talk":
			if args.size() == 1:
				QuestManager.server_talk(peer_id, str(args[0]))
		"quest_accept":
			if args.size() == 1:
				QuestManager.server_accept(peer_id, str(args[0]))
		"quest_turn_in":
			if args.size() == 1:
				QuestManager.server_turn_in(peer_id, str(args[0]))
		"drop":
			if args.size() == 1:
				var stack := inventory.take(int(args[0]))
				if not stack.is_empty():
					_spawn_drop(stack["id"], stack["count"], _drop_position(peer_id))
					changed = true
	if changed:
		_send_inventory(peer_id)


func _send_inventory(peer_id: int) -> void:
	var data: Array = _inventories[peer_id].to_array()
	if peer_id == multiplayer.get_unique_id():
		_receive_inventory(data)
	else:
		_receive_inventory.rpc_id(peer_id, data)


@rpc("authority", "reliable")
func _receive_inventory(slots: Array) -> void:
	Game.set_inventory(slots)


func _notify_peer(peer_id: int, text: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_notify(text)
	else:
		_notify.rpc_id(peer_id, text)


@rpc("authority", "reliable")
func _notify(text: String) -> void:
	Game.notify.emit(text)


## Da ítems a un jugador. Si no le entran, se tiran al suelo en una bolsa.
func _give(peer_id: int, id: String, amount: int) -> void:
	var inventory: Inventory = _inventories[peer_id]
	var leftover := inventory.add(id, amount)
	if leftover < amount:
		_send_inventory(peer_id)
	if leftover > 0:
		_spawn_drop(id, leftover, _drop_position(peer_id))
		_notify_peer(peer_id, "Inventario lleno: %s x%d quedó en el suelo" % [ItemDB.item_name(id), leftover])


## Recompensas de misiones: cada jugador conectado recibe todo.
func give_to_all(items: Dictionary) -> void:
	for peer_id in _inventories.keys():
		for item: String in items:
			_give(peer_id, item, int(items[item]))


## Saca ítems del inventario de un jugador (entregas de misiones).
func take_items(peer_id: int, items: Dictionary) -> bool:
	var inventory: Inventory = _inventories.get(peer_id)
	if inventory == null or not inventory.remove_items(items):
		return false
	_send_inventory(peer_id)
	return true


func notify_peer(peer_id: int, text: String) -> void:
	_notify_peer(peer_id, text)


# --- Fabricación ---------------------------------------------------------------------
# Los materiales se descuentan al encargar; si se cancela, se devuelven.

func _server_craft(peer_id: int, recipe_id: String, amount: int) -> void:
	var recipe := RecipeDB.get_recipe(recipe_id)
	var inventory: Inventory = _inventories.get(peer_id)
	var player := players_root.get_node_or_null(str(peer_id))
	if recipe.is_empty() or inventory == null or player == null or amount < 1:
		return
	var queue: Array = _craft_queues.get(peer_id, [])
	if queue.size() >= MAX_CRAFT_QUEUE:
		_notify_peer(peer_id, "La cola de fabricación está llena")
		return
	if recipe.has("station") and not is_near_station(player.sync_pos, recipe["station"]):
		_notify_peer(peer_id, "Tenés que estar cerca de: %s" % RecipeDB.STATIONS[recipe["station"]])
		return
	var count := mini(amount, RecipeDB.max_craftable(recipe_id, inventory.slots))
	if count <= 0:
		_notify_peer(peer_id, "Te faltan materiales")
		return
	var ingredients: Dictionary = recipe["ingredients"]
	for item: String in ingredients:
		inventory.remove(item, int(ingredients[item]) * count)
	queue.append({"recipe": recipe_id, "remaining": count, "time_left": recipe["time"], "time": recipe["time"]})
	_craft_queues[peer_id] = queue
	_send_inventory(peer_id)
	_send_craft_queue(peer_id)


func _server_craft_cancel(peer_id: int, index: int) -> void:
	var queue: Array = _craft_queues.get(peer_id, [])
	if index < 0 or index >= queue.size():
		return
	var job: Dictionary = queue[index]
	queue.remove_at(index)
	var ingredients: Dictionary = RecipeDB.get_recipe(job["recipe"])["ingredients"]
	for item: String in ingredients:
		_give(peer_id, item, int(ingredients[item]) * int(job["remaining"]))
	_send_craft_queue(peer_id)


func _update_crafting(delta: float) -> void:
	for peer_id in _craft_queues.keys():
		var queue: Array = _craft_queues[peer_id]
		if queue.is_empty():
			continue
		var job: Dictionary = queue[0]
		job["time_left"] -= delta
		if job["time_left"] > 0.0:
			continue
		var recipe := RecipeDB.get_recipe(job["recipe"])
		_give(peer_id, recipe["result"], recipe["amount"])
		QuestManager.report_craft(recipe["result"], recipe["amount"])
		job["remaining"] -= 1
		if job["remaining"] > 0:
			job["time_left"] = job["time"]
		else:
			queue.pop_front()
		_send_craft_queue(peer_id)


func _send_craft_queue(peer_id: int) -> void:
	var data: Array = []
	for job in _craft_queues.get(peer_id, []):
		data.append(job.duplicate())
	if peer_id == multiplayer.get_unique_id():
		_receive_craft_queue(data)
	else:
		_receive_craft_queue.rpc_id(peer_id, data)


@rpc("authority", "reliable")
func _receive_craft_queue(queue: Array) -> void:
	Game.set_craft_queue(queue)


# --- Recolección ---------------------------------------------------------------------

func _server_gather(peer_id: int, node_name: String) -> void:
	var node: ResourceNode = resource_nodes.get(node_name)
	if node == null or node.depleted:
		return
	var player := players_root.get_node_or_null(str(peer_id))
	if player == null:
		return
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(node.global_position) > GATHER_RANGE:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_gather_ms.get(peer_id, -100000)) < GATHER_MIN_INTERVAL_MS:
		return
	_last_gather_ms[peer_id] = now

	# La herramienta correcta en la mano rinde más.
	var inventory: Inventory = _inventories[peer_id]
	var held: String = inventory.get_slot(int(player.selected_slot)).get("id", "")
	var amount := node.base_yield
	if node.preferred_tool != "" and ItemDB.tool_type(held) == node.preferred_tool:
		amount *= ItemDB.tool_power(held)

	node.hits_left -= 1
	_give(peer_id, node.resource_type, amount)
	QuestManager.report_collect(node.resource_type, amount)
	if node.hits_left <= 0:
		_respawn_timers[node_name] = RESPAWN_TIME
		_set_node_state.rpc(node_name, true)
	else:
		_play_node_hit.rpc(node_name)


@rpc("authority", "call_local", "reliable")
func _set_node_state(node_name: String, is_depleted: bool) -> void:
	var node: ResourceNode = resource_nodes.get(node_name)
	if node:
		node.set_depleted(is_depleted)


@rpc("authority", "call_local", "unreliable")
func _play_node_hit(node_name: String) -> void:
	var node: ResourceNode = resource_nodes.get(node_name)
	if node:
		node.play_hit()


func _update_respawns(delta: float) -> void:
	for node_name in _respawn_timers.keys():
		_respawn_timers[node_name] -= delta
		if _respawn_timers[node_name] <= 0.0:
			_respawn_timers.erase(node_name)
			_set_node_state.rpc(node_name, false)


# --- Bolsas en el suelo -----------------------------------------------------------------

func _spawn_drop(id: String, count: int, pos: Vector3) -> void:
	_drop_counter += 1
	var drop := DROP_SCENE.instantiate()
	drop.name = "Drop_%d" % _drop_counter
	drop.item_id = id
	drop.count = count
	drop.position = pos
	drops_root.add_child(drop, true)


func _drop_position(peer_id: int) -> Vector3:
	var player := players_root.get_node_or_null(str(peer_id))
	if player == null:
		return landmarks.get("spawn", Vector3.ZERO)
	var rot: float = player.sync_rot
	var pos: Vector3 = player.sync_pos + Vector3(-sin(rot), 0, -cos(rot)) * 1.3
	pos += Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	pos.y = maxf(terrain.get_height(pos.x, pos.z), TerrainGenerator.WATER_LEVEL - 0.3)
	return pos


func _server_pickup(peer_id: int, drop_name: String) -> void:
	var drop := drops_root.get_node_or_null(drop_name)
	var player := players_root.get_node_or_null(str(peer_id))
	if drop == null or player == null or drop.is_queued_for_deletion():
		return
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(drop.global_position) > GATHER_RANGE:
		return
	var leftover: int = _inventories[peer_id].add(drop.item_id, drop.count)
	if leftover == drop.count:
		_notify_peer(peer_id, "No tenés lugar en el inventario")
		return
	_send_inventory(peer_id)
	if leftover == 0:
		drop.queue_free()
	else:
		drop.count = leftover


# --- Cinemáticas ---------------------------------------------------------------------

func build_cinematic(id: String) -> Array:
	var spawn: Vector3 = landmarks["spawn"]
	var monolith: Vector3 = landmarks["monolith"]
	var crystal := monolith + Vector3(0, 8, 0)
	match id:
		"intro":
			return [
				{
					"from": Vector3(-140, 75, 140), "to": Vector3(40, 60, 150),
					"look_from": Vector3(0, 0, 0), "look_to": Vector3(0, 5, 0),
					"duration": 6.0, "text": "Una isla olvidada emerge entre la niebla...",
				},
				{
					"from": spawn + Vector3(14, 9, 16), "to": spawn + Vector3(5, 3.5, 7),
					"look_from": spawn + Vector3(0, 1, 0),
					"duration": 4.5, "text": "Juntos, tendrán que sobrevivir y descubrir sus secretos.",
				},
			]
		"reveal_monolith":
			return [
				{
					"from": crystal + Vector3(-28, 10, 28), "to": crystal + Vector3(28, 6, 28),
					"look_from": crystal,
					"duration": 6.0, "text": "En lo alto de la montaña, una luz antigua despierta...",
				},
			]
		"monolith_awakens":
			return [
				{
					"from": monolith + Vector3(8, 2, 8), "to": crystal + Vector3(3, 1, 3),
					"look_from": monolith + Vector3(0, 3, 0), "look_to": crystal,
					"duration": 5.0, "text": "El cristal reconoce al grupo. Esto es solo el comienzo.",
				},
				{
					"from": crystal + Vector3(0, 30, 40), "to": crystal + Vector3(0, 70, 90),
					"look_from": crystal,
					"duration": 5.0, "text": "Fin de la demo. ¡Gracias por jugar!",
				},
			]
	return []
