extends Node3D
## El mundo compartido. Genera la isla (igual en todos los peers gracias a la semilla) y
## contiene la lógica autoritativa del servidor: aparición de jugadores, recolección,
## inventarios y reaparición de recursos.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const TREE_COUNT := 260
const ROCK_COUNT := 110
const BUSH_COUNT := 450
const RESPAWN_TIME := 90.0  ## Segundos hasta que reaparece un recurso agotado.
const GATHER_RANGE := 6.0  ## Distancia máxima aceptada por el servidor (anti-trampas).
const GATHER_MIN_INTERVAL_MS := 350

var generated := false
var terrain: TerrainGenerator
## Lugares importantes para misiones y cinemáticas: "spawn", "monolith".
var landmarks: Dictionary = {}
## nombre (String) -> ResourceNode
var resource_nodes: Dictionary = {}

# Solo en el servidor:
var _respawn_timers: Dictionary = {}
var _inventories: Dictionary = {}
var _last_gather_ms: Dictionary = {}

var _crystal: Node3D
var _crystal_base_y := 0.0
var _fire_light: OmniLight3D
var _time := 0.0

@onready var players_root: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	add_to_group("world")
	player_spawner.add_spawnable_scene(PLAYER_SCENE.resource_path)
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
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


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
		var rock := PropFactory.make_rock(rng)
		_add_resource(container, rock, "Rock_%d" % i, spot - Vector3(0, 0.2, 0), rng.randf() * TAU)


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
		if p.length() < TerrainGenerator.SPAWN_RADIUS * 0.8:
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
		if h < TerrainGenerator.WATER_LEVEL + 0.8 or h > 18.0 or p.length() < 5.0:
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
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.player_name = Network.players[peer_id]["name"]
	player.position = get_spawn_point(peer_id)
	player.sync_pos = player.position
	players_root.add_child(player, true)


func _on_player_left(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	_inventories.erase(peer_id)
	_last_gather_ms.erase(peer_id)


## Estado que necesita un jugador que entra a una partida ya empezada.
func get_state_for_new_player() -> Dictionary:
	return {"depleted": _respawn_timers.keys()}


func apply_state(state: Dictionary) -> void:
	for node_name in state.get("depleted", []):
		_set_node_state(node_name, true)


# --- Recolección ---------------------------------------------------------------------

## Lo llama el jugador local al golpear un recurso.
func gather(node_name: String) -> void:
	if multiplayer.is_server():
		_server_gather(1, node_name)
	else:
		request_gather.rpc_id(1, node_name)


@rpc("any_peer", "reliable")
func request_gather(node_name: String) -> void:
	if multiplayer.is_server():
		_server_gather(multiplayer.get_remote_sender_id(), node_name)


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

	node.hits_left -= 1
	_add_item(peer_id, node.resource_type, 1)
	QuestManager.report_collect(node.resource_type, 1)
	if node.hits_left <= 0:
		_respawn_timers[node_name] = RESPAWN_TIME
		_set_node_state.rpc(node_name, true)
	else:
		_play_node_hit.rpc(node_name)


func _add_item(peer_id: int, item: String, amount: int) -> void:
	var inventory: Dictionary = _inventories.get(peer_id, {})
	inventory[item] = int(inventory.get(item, 0)) + amount
	_inventories[peer_id] = inventory
	if peer_id == multiplayer.get_unique_id():
		_receive_inventory(inventory)
	else:
		_receive_inventory.rpc_id(peer_id, inventory)


@rpc("authority", "reliable")
func _receive_inventory(inventory: Dictionary) -> void:
	Game.set_inventory(inventory.duplicate())


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
