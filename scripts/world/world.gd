extends Node3D
## El mundo compartido. Genera la isla con biomas (igual en todos los peers gracias a la semilla)
## y contiene la lógica autoritativa del servidor: jugadores (vida/hambre/muerte), recolección,
## inventarios, fabricación, combate, animales, sombras nocturnas, domesticación, construcción,
## cofres y el ciclo de día y noche.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DROP_SCENE := preload("res://scenes/item_drop.tscn")
const CREATURE_SCENE := preload("res://scenes/creature.tscn")
const PIECE_SCENE := preload("res://scenes/build_piece.tscn")

const PLACEMENT_ATTEMPTS := 9000  ## Puntos que se prueban para poner árboles, rocas y plantas.
const CHEST_COUNT := 30
const RESPAWN_TIME := 90.0  ## Segundos hasta que reaparece un recurso agotado.
const CHEST_REFILL_TIME := 480.0
const GATHER_RANGE := 6.0  ## Distancia máxima aceptada por el servidor (anti-trampas).
const GATHER_MIN_INTERVAL_MS := 350
const STARTER_KIT := [["stone_hatchet", 1], ["berries", 5]]
const MAX_CRAFT_QUEUE := 8
const MOBS_PER_PLAYER := 3
const HUNGER_PER_SECOND := 100.0 / (25.0 * 60.0)  ## La comida dura ~25 minutos.
const BLUEPRINT_WEIGHTS := {"bp_foundation": 5, "bp_wall": 5, "bp_doorway": 3, "bp_roof": 3, "bp_campfire": 4, "bp_stone": 1}

## Qué aparece en cada bioma: [probabilidad acumulada, tipo]
const BIOME_SPAWNS := {
	"meadow": [[0.09, "round"], [0.13, "pine"], [0.19, "rock"], [0.27, "fiber"], [0.34, "berry"]],
	"forest": [[0.34, "pine"], [0.46, "round"], [0.51, "rock"], [0.55, "fiber"], [0.6, "berry"]],
	"desert": [[0.06, "cactus"], [0.14, "rock"]],
	"tundra": [[0.12, "snow_pine"], [0.21, "rock"]],
}
const ORE_CHANCE := {"meadow": 0.2, "forest": 0.25, "desert": 0.5, "tundra": 0.4}

var generated := false
var terrain: TerrainGenerator
var day_night: DayNight
## Lugares importantes para misiones y cinemáticas.
var landmarks: Dictionary = {}
## nombre (String) -> ResourceNode / LootChest
var resource_nodes: Dictionary = {}
var chests: Dictionary = {}
## Planos que conoce el grupo (compartido).
var known_blueprints: Array = []

# Registro de construcción (en todos los peers): para encajar piezas.
var _floors: Dictionary = {}  ## "cx,cz" -> Array de alturas de piso
var _walls: Dictionary = {}  ## clave de borde -> Array de alturas de piso

# Solo en el servidor:
var _respawn_timers: Dictionary = {}
var _chest_timers: Dictionary = {}
var _inventories: Dictionary = {}  ## peer_id -> Inventory
var _saved_inventories: Dictionary = {}  ## nombre -> Array (para volver a entrar sin perder todo)
var _stats: Dictionary = {}  ## peer_id -> {"health", "hunger"}
var _last_gather_ms: Dictionary = {}
var _last_attack_ms: Dictionary = {}
var _drop_counter := 0
var _creature_counter := 0
var _piece_counter := 0
var _craft_queues: Dictionary = {}  ## peer_id -> [{recipe, remaining, time_left, time}]
var _animal_respawns: Array = []  ## [especie, segundos]
var _tick := 0.0
var _clear_zones: Array = []
var _spatial: Dictionary = {}  ## Grilla para separar objetos al ubicarlos.

var _crystal: Node3D
var _crystal_base_y := 0.0
var _sun: DirectionalLight3D
var _environment: Environment
var _time := 0.0

@onready var players_root: Node3D = $Players
@onready var drops_root: Node3D = $Drops
@onready var creatures_root: Node3D = $Creatures
@onready var pieces_root: Node3D = $Pieces


func _ready() -> void:
	add_to_group("world")
	$PlayerSpawner.add_spawnable_scene(PLAYER_SCENE.resource_path)
	$DropSpawner.add_spawnable_scene(DROP_SCENE.resource_path)
	$CreatureSpawner.add_spawnable_scene(CREATURE_SCENE.resource_path)
	$PieceSpawner.add_spawnable_scene(PIECE_SCENE.resource_path)
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)


func _process(delta: float) -> void:
	if not generated:
		return
	_time += delta
	if _crystal:
		_crystal.rotation.y = _time * 0.8
		_crystal.position.y = _crystal_base_y + sin(_time * 1.5) * 0.25
	if multiplayer.is_server() and Network.is_online():
		_update_respawns(delta)
		_update_crafting(delta)
		_tick -= delta
		if _tick <= 0.0:
			_tick = 1.0
			_server_tick()


func is_night() -> bool:
	return day_night != null and day_night.is_night()


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
	_place_chests(world_seed)
	if DisplayServer.get_name() != "headless":
		var grass := GrassField.new()
		grass.name = "Grass"
		add_child(grass)
		grass.setup(terrain, world_seed)
	generated = true
	if multiplayer.is_server():
		_spawn_initial_animals()
	Game.world_generated.emit()


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05

	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.shadow_enabled = false
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	_sun = sun
	_environment = env

	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(sun, moon, env, sky_material)
	_apply_graphics()
	Settings.changed.connect(_apply_graphics)


## Calidad gráfica elegida en Opciones.
func _apply_graphics() -> void:
	var quality: String = Settings.get_value("quality")
	_sun.shadow_enabled = quality != "low"
	_sun.directional_shadow_max_distance = 160.0 if quality == "high" else 80.0
	_environment.glow_enabled = quality != "low"
	_environment.ssao_enabled = quality == "high"


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * TerrainGenerator.SIZE * 6.0
	plane.subdivide_width = 120
	plane.subdivide_depth = 120
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
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


## Campamento, forja, ermitaño, muelle y mirador. Todo se calcula a partir del terreno.
func _place_settlements() -> void:
	var monolith: Vector3 = landmarks["monolith"]
	var to_monolith := Vector2(monolith.x, monolith.z).normalized()

	landmarks["workbench"] = _ground(Vector2(5.5, -3.0))
	_place_prop(PropFactory.make_workbench(), landmarks["workbench"], Vector3.ZERO)
	landmarks["camp_npc"] = _ground(Vector2(6.8, -0.2))
	_spawn_npc("tomas", landmarks["camp_npc"])

	var forge := _find_flat_near(Vector2(monolith.x, monolith.z) * 0.45, 22.0)
	landmarks["furnace"] = forge
	_place_prop(PropFactory.make_furnace(), forge, Vector3.ZERO, -to_monolith)
	_place_prop(PropFactory.make_anvil(), _ground(Vector2(forge.x, forge.z) + Vector2(2.2, 1.0)), Vector3.ZERO)
	landmarks["forge_npc"] = _ground(Vector2(forge.x, forge.z) + Vector2(-2.2, -1.6))
	_spawn_npc("ilse", landmarks["forge_npc"])
	_clear_zones.append([Vector2(forge.x, forge.z), 6.0])

	landmarks["hermit_npc"] = _find_flat_near(Vector2(monolith.x, monolith.z) - to_monolith * 16.0, 10.0, 0.5)
	_spawn_npc("eco", landmarks["hermit_npc"])

	_place_dock(-to_monolith)

	var lookout := terrain.find_highest_point(TerrainGenerator.SIZE * 0.42, Vector2(monolith.x, monolith.z), 120.0)
	landmarks["lookout"] = lookout
	_place_prop(PropFactory.make_cairn(), lookout - Vector3(0, 0.2, 0), Vector3.ZERO)


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.get_height(p.x, p.y), p.y)


func _place_prop(prop: Node3D, pos: Vector3, rot: Vector3, facing: Vector2 = Vector2.ZERO) -> void:
	prop.position = pos
	prop.rotation = rot
	if facing != Vector2.ZERO:
		prop.rotation.y = atan2(-facing.x, -facing.y)
	add_child(prop)
	_clear_zones.append([Vector2(pos.x, pos.z), 4.0])


func _spawn_npc(id: String, pos: Vector3) -> void:
	var npc := NPC.new()
	npc.setup(id)
	npc.position = pos
	add_child(npc)
	_clear_zones.append([Vector2(pos.x, pos.z), 4.0])


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
				landmarks["dock_npc"] = _ground(dir * (step - 3))
				_spawn_npc("nilo", landmarks["dock_npc"])
				_clear_zones.append([shore, 6.0])
				return
	landmarks["dock_npc"] = _ground(Vector2(-7, 3))
	_spawn_npc("nilo", landmarks["dock_npc"])


## ¿Hay una estación de ese tipo cerca? (mesa, horno, fogata del campamento o construida)
func is_near_station(pos: Vector3, station: String) -> bool:
	for node in get_tree().get_nodes_in_group("stations"):
		if node.station_type == station and node.global_position.distance_to(pos) <= RecipeDB.STATION_RANGE:
			return true
	return false


func _place_resources(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var container := Node3D.new()
	container.name = "Resources"
	add_child(container)
	var limit := TerrainGenerator.SIZE * 0.47
	for i in PLACEMENT_ATTEMPTS:
		var p := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 0.8 or _in_clear_zone(p):
			continue
		var biome := terrain.get_biome(p.x, p.y)
		var kind := ""
		for entry in BIOME_SPAWNS[biome]:
			if roll < entry[0]:
				kind = entry[1]
				break
		if kind == "":
			continue
		var slope := terrain.get_slope(p.x, p.y)
		var spacing := 2.6 if kind in ["round", "pine", "snow_pine"] else 1.6
		if slope > (0.55 if kind == "rock" else 0.35) or not _space_free(p, spacing):
			continue
		var node: ResourceNode
		match kind:
			"round", "pine", "snow_pine":
				node = PropFactory.make_tree(rng, kind)
			"rock":
				node = PropFactory.make_rock(rng, rng.randf() < ORE_CHANCE[biome])
			"fiber":
				node = PropFactory.make_fiber_plant(rng)
			"berry":
				node = PropFactory.make_berry_bush(rng)
			"cactus":
				node = PropFactory.make_cactus(rng)
		_mark_space(p)
		var key := "R_%d" % i
		node.name = key
		node.position = Vector3(p.x, h - (0.2 if kind == "rock" else 0.08), p.y)
		node.rotation.y = yaw
		container.add_child(node)
		resource_nodes[key] = node


func _place_chests(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 500
	var limit := TerrainGenerator.SIZE * 0.45
	var placed := 0
	for attempt in 600:
		if placed >= CHEST_COUNT:
			break
		var p := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var yaw := rng.randf() * TAU
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 1.0 or p.length() < 30.0 or _in_clear_zone(p) \
				or terrain.get_slope(p.x, p.y) > 0.3 or not _space_free(p, 2.0):
			continue
		_mark_space(p)
		var chest := LootChest.new()
		chest.name = "Chest_%d" % placed
		chest.position = Vector3(p.x, h - 0.05, p.y)
		chest.rotation.y = yaw
		add_child(chest)
		chests[str(chest.name)] = chest
		placed += 1


func _in_clear_zone(p: Vector2) -> bool:
	for zone in _clear_zones:
		if p.distance_to(zone[0]) < zone[1]:
			return true
	return false


func _space_free(p: Vector2, min_distance: float) -> bool:
	var cell := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: Vector2 in _spatial.get(cell + Vector2i(dx, dz), []):
				if other.distance_squared_to(p) < min_distance * min_distance:
					return false
	return true


func _mark_space(p: Vector2) -> void:
	var cell := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	if not _spatial.has(cell):
		_spatial[cell] = []
	_spatial[cell].append(p)


## Lugar al azar en tierra firme dentro de ciertos biomas.
func random_land_spot(biomes: Array, rng: RandomNumberGenerator, near: Vector3 = Vector3.INF, min_r: float = 0.0, max_r: float = 0.0) -> Vector3:
	var limit := TerrainGenerator.SIZE * 0.46
	for attempt in 60:
		var p: Vector2
		if near != Vector3.INF:
			var angle := rng.randf() * TAU
			p = Vector2(near.x, near.z) + Vector2(cos(angle), sin(angle)) * rng.randf_range(min_r, max_r)
		else:
			p = Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 1.0 or terrain.get_slope(p.x, p.y) > 0.5:
			continue
		if not biomes.is_empty() and not terrain.get_biome(p.x, p.y) in biomes:
			continue
		if p.length() < TerrainGenerator.SPAWN_RADIUS + 6.0:
			continue
		return Vector3(p.x, h + 0.5, p.y)
	return Vector3.INF


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

	var inventory := Inventory.new()
	if _saved_inventories.has(player_name):
		inventory.load_from(_saved_inventories[player_name])
		_saved_inventories.erase(player_name)
	else:
		for entry in STARTER_KIT:
			inventory.add(entry[0], entry[1])
	_inventories[peer_id] = inventory
	_stats[peer_id] = {"health": 100.0, "hunger": 80.0}
	_send_inventory(peer_id)
	_send_stats(peer_id)


func _on_player_left(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		var inventory: Inventory = _inventories.get(peer_id)
		if inventory:
			for job in _craft_queues.get(peer_id, []):
				var ingredients: Dictionary = RecipeDB.get_recipe(job["recipe"])["ingredients"]
				for item: String in ingredients:
					inventory.add(item, int(ingredients[item]) * int(job["remaining"]))
			_saved_inventories[player.player_name] = inventory.to_array()
		player.queue_free()
	for creature in creatures_root.get_children():
		if creature is Creature and creature.owner_peer == peer_id:
			creature.follow_owner = false  # La mascota espera a que vuelva.
	_inventories.erase(peer_id)
	_craft_queues.erase(peer_id)
	_stats.erase(peer_id)
	_last_gather_ms.erase(peer_id)


## Estado que necesita un jugador que entra a una partida ya empezada.
func get_state_for_new_player() -> Dictionary:
	var opened: Array = []
	for chest_name in _chest_timers:
		opened.append(chest_name)
	return {
		"depleted": _respawn_timers.keys(), "chests": opened, "blueprints": known_blueprints,
		"time": day_night.time, "day": day_night.day,
	}


func apply_state(state: Dictionary) -> void:
	for node_name in state.get("depleted", []):
		_set_node_state(node_name, true)
	for chest_name in state.get("chests", []):
		_set_chest_state(chest_name, true)
	known_blueprints = state.get("blueprints", [])
	if state.has("time"):
		day_night.set_time(state["time"], state["day"])


# --- Vida, hambre y muerte (servidor) ----------------------------------------------------

func _server_tick() -> void:
	for peer_id in _stats.keys():
		var stats: Dictionary = _stats[peer_id]
		stats["hunger"] = maxf(0.0, stats["hunger"] - HUNGER_PER_SECOND)
		if stats["hunger"] <= 0.0:
			stats["health"] -= 1.0  # Hambre: se pierde vida.
		elif stats["hunger"] > 50.0:
			stats["health"] = minf(100.0, stats["health"] + 0.5)
		if stats["health"] <= 0.0:
			_kill_player(peer_id, "de hambre")
		else:
			_send_stats(peer_id)
	_sync_time.rpc(day_night.time, day_night.day)
	_update_animals()
	if is_night():
		_spawn_night_mobs()


func _send_stats(peer_id: int) -> void:
	var stats: Dictionary = _stats.get(peer_id, {})
	if stats.is_empty():
		return
	if peer_id == multiplayer.get_unique_id():
		_receive_stats(stats["health"], stats["hunger"])
	else:
		_receive_stats.rpc_id(peer_id, stats["health"], stats["hunger"])


@rpc("authority", "reliable")
func _receive_stats(health: float, hunger: float) -> void:
	Game.set_stats(health, hunger)


@rpc("authority", "call_local", "unreliable")
func _sync_time(time: float, day: int) -> void:
	if not multiplayer.is_server():
		day_night.set_time(time, day)


## Daño a un jugador (lo llaman las criaturas).
func damage_player(peer_id: int, amount: float) -> void:
	var stats: Dictionary = _stats.get(peer_id, {})
	if stats.is_empty():
		return
	stats["health"] -= amount
	if peer_id == multiplayer.get_unique_id():
		_on_hit(amount)
	else:
		_on_hit.rpc_id(peer_id, amount)
	if stats["health"] <= 0.0:
		_kill_player(peer_id, "en combate")
	else:
		_send_stats(peer_id)


@rpc("authority", "unreliable")
func _on_hit(amount: float) -> void:
	Game.player_hit.emit(amount)


## Muerte: deja todo en el suelo y reaparece en el campamento.
func _kill_player(peer_id: int, cause: String) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	var inventory: Inventory = _inventories.get(peer_id)
	if player == null or inventory == null:
		return
	var pos: Vector3 = player.sync_pos
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in Inventory.SIZE:
		var stack := inventory.take(i)
		if not stack.is_empty():
			var offset := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
			var drop_pos := pos + offset
			drop_pos.y = maxf(terrain.get_height(drop_pos.x, drop_pos.z), TerrainGenerator.WATER_LEVEL - 0.3)
			_spawn_drop(stack["id"], stack["count"], drop_pos)
	_stats[peer_id] = {"health": 100.0, "hunger": 60.0}
	_send_inventory(peer_id)
	_send_stats(peer_id)
	Network.announce.rpc("%s murió %s. Sus cosas quedaron en el suelo." % [player.player_name, cause])
	var spawn := get_spawn_point(peer_id)
	if peer_id == multiplayer.get_unique_id():
		_respawn_at(spawn)
	else:
		_respawn_at.rpc_id(peer_id, spawn)


@rpc("authority", "reliable")
func _respawn_at(pos: Vector3) -> void:
	Game.player_died.emit()
	if Game.local_player:
		Game.local_player.respawn(pos)


# --- Acciones de los jugadores ---------------------------------------------------------
# Todo pasa por el servidor: el cliente pide, el servidor valida y responde.

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
		"drop":
			if args.size() == 1:
				var stack := inventory.take(int(args[0]))
				if not stack.is_empty():
					_spawn_drop(stack["id"], stack["count"], _drop_position(peer_id))
					changed = true
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
		"eat":
			if args.size() == 1:
				_server_eat(peer_id, int(args[0]))
		"learn":
			if args.size() == 1:
				_server_learn(peer_id, int(args[0]))
		"attack":
			if args.size() == 1:
				_server_attack(peer_id, str(args[0]))
		"feed":
			if args.size() == 1:
				_server_feed(peer_id, str(args[0]))
		"pet":
			if args.size() == 1:
				_server_pet_command(peer_id, str(args[0]))
		"chest":
			if args.size() == 1:
				_server_open_chest(peer_id, str(args[0]))
		"build":
			if args.size() == 3:
				_server_build(peer_id, str(args[0]), args[1], float(args[2]))
		"demolish":
			if args.size() == 1:
				_server_demolish(peer_id, str(args[0]))
		"door":
			if args.size() == 1:
				_server_door(peer_id, str(args[0]))
	if changed:
		_send_inventory(peer_id)


func _player_node(peer_id: int) -> Node3D:
	return players_root.get_node_or_null(str(peer_id))


func _held_item(peer_id: int) -> String:
	var player := _player_node(peer_id)
	var inventory: Inventory = _inventories.get(peer_id)
	if player == null or inventory == null:
		return ""
	return inventory.get_slot(int(player.selected_slot)).get("id", "")


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


func notify_peer(peer_id: int, text: String) -> void:
	_notify_peer(peer_id, text)


## Da ítems a un jugador. Si no le entran, se tiran al suelo en una bolsa.
func _give(peer_id: int, id: String, amount: int) -> void:
	var inventory: Inventory = _inventories.get(peer_id)
	if inventory == null:
		return
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


# --- Comer y aprender planos -----------------------------------------------------------

func _server_eat(peer_id: int, slot: int) -> void:
	var inventory: Inventory = _inventories[peer_id]
	var id: String = inventory.get_slot(slot).get("id", "")
	if not ItemDB.is_food(id) or not inventory.take_amount(slot, 1):
		return
	var item := ItemDB.get_item(id)
	var stats: Dictionary = _stats[peer_id]
	stats["hunger"] = minf(100.0, stats["hunger"] + item["food"])
	stats["health"] = clampf(stats["health"] + item.get("heal", 0), 1.0, 100.0)
	_send_inventory(peer_id)
	_send_stats(peer_id)


func _server_learn(peer_id: int, slot: int) -> void:
	var inventory: Inventory = _inventories[peer_id]
	var id: String = inventory.get_slot(slot).get("id", "")
	if not ItemDB.is_blueprint(id):
		return
	if id in known_blueprints:
		_notify_peer(peer_id, "El grupo ya conoce ese plano. Podés guardarlo o tirarlo.")
		return
	inventory.take_amount(slot, 1)
	known_blueprints.append(id)
	_send_inventory(peer_id)
	_sync_blueprints.rpc(known_blueprints)
	Network.announce.rpc("%s aprendió %s (sirve para todo el grupo)" % [Network.players[peer_id]["name"], ItemDB.item_name(id)])


@rpc("authority", "call_local", "reliable")
func _sync_blueprints(list: Array) -> void:
	known_blueprints = list
	Game.blueprints_changed.emit()


# --- Combate, caza y domesticación -----------------------------------------------------

func _server_attack(peer_id: int, creature_name: String) -> void:
	var creature := creatures_root.get_node_or_null(creature_name)
	var player := _player_node(peer_id)
	if not creature is Creature or player == null or creature.dead or creature.tamed_owner != "":
		return
	var held := _held_item(peer_id)
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(creature.global_position) > ItemDB.attack_range(held) + 2.5:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_attack_ms.get(peer_id, -100000)) < int(ItemDB.attack_cooldown(held) * 800.0):
		return
	_last_attack_ms[peer_id] = now
	creature.take_damage(ItemDB.damage(held), player)


func on_creature_died(creature: Creature, killer_peer: int) -> void:
	var data := CreatureDB.get_species(creature.species)
	if killer_peer != 0 and _inventories.has(killer_peer):
		var drops: Dictionary = data.get("drops", {})
		for item: String in drops:
			_give(killer_peer, item, int(drops[item]))
		if randf() < data.get("blueprint_chance", 0.0):
			var blueprint := _random_blueprint()
			_give(killer_peer, blueprint, 1)
			_notify_peer(killer_peer, "¡La sombra dejó un plano: %s!" % ItemDB.item_name(blueprint))
		QuestManager.report_kill(creature.species)
	if not CreatureDB.is_mob(creature.species):
		_animal_respawns.append([creature.species, 120.0])


func _server_feed(peer_id: int, creature_name: String) -> void:
	var creature := creatures_root.get_node_or_null(creature_name)
	var player := _player_node(peer_id)
	var held := _held_item(peer_id)
	if not creature is Creature or player == null or not creature.is_tameable_with(held):
		return
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(creature.global_position) > 5.0:
		return
	var inventory: Inventory = _inventories[peer_id]
	if not inventory.take_amount(int(player.selected_slot), 1):
		return
	_send_inventory(peer_id)
	var player_name: String = Network.players[peer_id]["name"]
	if creature.add_tame_progress(peer_id, player_name):
		Network.announce.rpc("¡%s domesticó un %s!" % [player_name, CreatureDB.display_name(creature.species)])
		QuestManager.report_tame(creature.species)


func _server_pet_command(peer_id: int, creature_name: String) -> void:
	var creature := creatures_root.get_node_or_null(creature_name)
	if creature is Creature and creature.owner_peer == peer_id:
		creature.follow_owner = not creature.follow_owner
		_notify_peer(peer_id, "%s: %s" % [CreatureDB.display_name(creature.species), "te sigue" if creature.follow_owner else "se queda acá"])


func _spawn_creature(species: String, pos: Vector3) -> void:
	_creature_counter += 1
	var creature := CREATURE_SCENE.instantiate()
	creature.name = "C_%d" % _creature_counter
	creature.species = species
	creature.position = pos
	creatures_root.add_child(creature, true)


func _spawn_initial_animals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for species: String in CreatureDB.SPECIES:
		var data := CreatureDB.get_species(species)
		if data["behavior"] == "mob":
			continue
		for i in int(data.get("count", 0)):
			var pos := random_land_spot(data.get("biomes", []), rng)
			if pos != Vector3.INF:
				_spawn_creature(species, pos)


func _update_animals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for entry in _animal_respawns.duplicate():
		entry[1] -= 1.0
		if entry[1] <= 0.0:
			_animal_respawns.erase(entry)
			var pos := random_land_spot(CreatureDB.get_species(entry[0]).get("biomes", []), rng)
			if pos != Vector3.INF:
				_spawn_creature(entry[0], pos)


## De noche aparecen sombras cerca de cada jugador.
func _spawn_night_mobs() -> void:
	if randf() > 0.25:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for player in get_players():
		var nearby := 0
		for creature in creatures_root.get_children():
			if creature is Creature and CreatureDB.is_mob(creature.species) and not creature.dead \
					and creature.global_position.distance_to(player.global_position) < 60.0:
				nearby += 1
		if nearby >= MOBS_PER_PLAYER + mini(day_night.day - 1, 3):
			continue
		var pos := random_land_spot([], rng, player.global_position, 25.0, 40.0)
		if pos == Vector3.INF:
			continue
		var species := "brute" if day_night.day >= 2 and rng.randf() < 0.2 else "shade"
		_spawn_creature(species, pos)


func _random_blueprint() -> String:
	var total := 0
	for id in BLUEPRINT_WEIGHTS:
		total += BLUEPRINT_WEIGHTS[id]
	var roll := randi() % total
	for id: String in BLUEPRINT_WEIGHTS:
		roll -= BLUEPRINT_WEIGHTS[id]
		if roll < 0:
			return id
	return "bp_foundation"


# --- Cofres ----------------------------------------------------------------------------

func _server_open_chest(peer_id: int, chest_name: String) -> void:
	var chest: LootChest = chests.get(chest_name)
	var player := _player_node(peer_id)
	if chest == null or player == null or chest.opened:
		return
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(chest.global_position) > GATHER_RANGE:
		return
	_chest_timers[chest_name] = CHEST_REFILL_TIME
	_set_chest_state.rpc(chest_name, true)
	var loot := _roll_loot()
	for item: String in loot:
		_give(peer_id, item, int(loot[item]))
	_notify_peer(peer_id, "Cofre: %s" % ItemDB.list_text(loot))


func _roll_loot() -> Dictionary:
	var loot := {}
	if randf() < 0.65:
		loot[_random_blueprint()] = 1
	var pool := [["wood", 20, 60], ["stone", 15, 40], ["fiber", 10, 30], ["metal_fragments", 5, 20],
		["cooked_meat", 1, 3], ["berries", 5, 12], ["torch", 1, 1], ["leather", 3, 8]]
	for i in randi_range(2, 3):
		var entry: Array = pool[randi() % pool.size()]
		loot[entry[0]] = int(loot.get(entry[0], 0)) + randi_range(entry[1], entry[2])
	return loot


@rpc("authority", "call_local", "reliable")
func _set_chest_state(chest_name: String, is_open: bool) -> void:
	var chest: LootChest = chests.get(chest_name)
	if chest:
		chest.set_opened(is_open)


# --- Construcción ----------------------------------------------------------------------

func _cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / BuildDB.GRID), floori(pos.z / BuildDB.GRID))


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _edge_key(pos: Vector3, rot_y: float) -> String:
	if absf(sin(rot_y)) < 0.5:  # Pared a lo largo del eje X
		return "h,%d,%d" % [floori(pos.x / BuildDB.GRID), roundi(pos.z / BuildDB.GRID)]
	return "v,%d,%d" % [roundi(pos.x / BuildDB.GRID), floori(pos.z / BuildDB.GRID)]


func register_piece(piece: BuildPiece) -> void:
	var kind := piece.kind()
	if kind in ["foundation", "roof"]:
		var key := _cell_key(_cell(piece.global_position))
		if not _floors.has(key):
			_floors[key] = []
		_floors[key].append(piece.floor_height())
	elif kind in ["wall", "doorway"]:
		var key := _edge_key(piece.global_position, piece.rotation.y)
		if not _walls.has(key):
			_walls[key] = []
		_walls[key].append(piece.global_position.y)


func unregister_piece(piece: BuildPiece) -> void:
	var kind := piece.kind()
	if kind in ["foundation", "roof"]:
		_floors.get(_cell_key(_cell(piece.global_position)), []).erase(piece.floor_height())
	elif kind in ["wall", "doorway"]:
		_walls.get(_edge_key(piece.global_position, piece.rotation.y), []).erase(piece.global_position.y)


func _has_level(list: Array, y: float) -> bool:
	for value: float in list:
		if absf(value - y) < 0.3:
			return true
	return false


## Calcula dónde iría una pieza según el punto al que apunta el jugador.
## Devuelve {"valid", "position", "rotation", "reason"}. Lo usan el cliente (vista previa) y el servidor.
func compute_placement(piece_id: String, hit: Vector3, yaw: float) -> Dictionary:
	var data := BuildDB.get_piece(piece_id)
	var kind: String = data.get("kind", "")
	var g := BuildDB.GRID
	var cell := _cell(hit)
	var result := {"valid": false, "position": hit, "rotation": 0.0, "reason": ""}
	match kind:
		"foundation":
			var center := Vector3((cell.x + 0.5) * g, 0, (cell.y + 0.5) * g)
			var heights: Array[float] = []
			for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
				heights.append(terrain.get_height(center.x + offset.x * g * 0.5, center.z + offset.y * g * 0.5))
			var top: float = heights.max() + 0.15
			# Si hay un cimiento al lado a una altura parecida, se alinea con él (piso parejo).
			for neighbor in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for f: float in _floors.get(_cell_key(cell + neighbor), []):
					if f >= heights.max() - 0.3 and f <= top + 0.8:
						top = f
			center.y = top
			result["position"] = center
			if top - heights.min() > 1.15:
				result["reason"] = "Terreno muy inclinado"
			elif heights.min() < TerrainGenerator.WATER_LEVEL:
				result["reason"] = "No se puede construir en el agua"
			elif _has_level(_floors.get(_cell_key(cell), []), top):
				result["reason"] = "Ya hay un cimiento acá"
			else:
				result["valid"] = true
		"wall", "doorway":
			var local := Vector2(hit.x - cell.x * g, hit.z - cell.y * g)
			var edges := [
				[local.x, Vector3(cell.x * g, 0, (cell.y + 0.5) * g), PI / 2, Vector2i(-1, 0)],
				[g - local.x, Vector3((cell.x + 1) * g, 0, (cell.y + 0.5) * g), PI / 2, Vector2i(1, 0)],
				[local.y, Vector3((cell.x + 0.5) * g, 0, cell.y * g), 0.0, Vector2i(0, -1)],
				[g - local.y, Vector3((cell.x + 0.5) * g, 0, (cell.y + 1) * g), 0.0, Vector2i(0, 1)],
			]
			edges.sort_custom(func(a, b): return a[0] < b[0])
			var edge: Array = edges[0]
			var pos: Vector3 = edge[1]
			var floors: Array = _floors.get(_cell_key(cell), []).duplicate()
			floors.append_array(_floors.get(_cell_key(cell + edge[3]), []))
			var best := INF
			for f: float in floors:
				if absf(f - hit.y) < absf(best - hit.y) and f <= hit.y + 1.5:
					best = f
			result["rotation"] = edge[2]
			if best == INF:
				result["position"] = Vector3(pos.x, hit.y, pos.z)
				result["reason"] = "Necesita un cimiento o un techo debajo"
			else:
				pos.y = best
				result["position"] = pos
				if _has_level(_walls.get(_edge_key(pos, edge[2]), []), best):
					result["reason"] = "Ya hay una pared acá"
				else:
					result["valid"] = true
		"roof":
			var center := Vector3((cell.x + 0.5) * g, 0, (cell.y + 0.5) * g)
			var floors: Array = _floors.get(_cell_key(cell), [])
			var best := INF
			for f: float in floors:
				var y := f + BuildDB.WALL_HEIGHT
				if absf(y - hit.y) < absf(best - hit.y):
					best = y
			if best == INF:
				center.y = hit.y
				result["position"] = center
				result["reason"] = "Necesita un cimiento con paredes"
			else:
				center.y = best
				result["position"] = center
				var base := best - BuildDB.WALL_HEIGHT
				var has_wall := false
				for key in [_edge_key(Vector3(cell.x * g, 0, (cell.y + 0.5) * g), PI / 2),
						_edge_key(Vector3((cell.x + 1) * g, 0, (cell.y + 0.5) * g), PI / 2),
						_edge_key(Vector3((cell.x + 0.5) * g, 0, cell.y * g), 0.0),
						_edge_key(Vector3((cell.x + 0.5) * g, 0, (cell.y + 1) * g), 0.0)]:
					if _has_level(_walls.get(key, []), base):
						has_wall = true
				if not has_wall:
					result["reason"] = "Necesita al menos una pared"
				elif _has_level(floors, best + 0.25):
					result["reason"] = "Ya hay un techo acá"
				else:
					result["valid"] = true
		"campfire":
			result["position"] = hit
			result["rotation"] = yaw
			result["valid"] = hit.y > TerrainGenerator.WATER_LEVEL + 0.2
			if not result["valid"]:
				result["reason"] = "No se puede construir en el agua"
	return result


func _server_build(peer_id: int, piece_id: String, hit: Variant, yaw: float) -> void:
	var data := BuildDB.get_piece(piece_id)
	var player := _player_node(peer_id)
	var inventory: Inventory = _inventories[peer_id]
	if data.is_empty() or player == null or not hit is Vector3 or _held_item(peer_id) != "hammer":
		return
	if not BuildDB.is_unlocked(piece_id, known_blueprints):
		_notify_peer(peer_id, "El grupo todavía no conoce ese plano")
		return
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(hit) > BuildDB.BUILD_RANGE + 2.0:
		return
	var placement := compute_placement(piece_id, hit, yaw)
	if not placement["valid"]:
		_notify_peer(peer_id, placement["reason"])
		return
	if not inventory.remove_items(data["cost"]):
		_notify_peer(peer_id, "Te falta: %s" % ItemDB.list_text(data["cost"]))
		return
	_send_inventory(peer_id)
	_piece_counter += 1
	var piece := PIECE_SCENE.instantiate()
	piece.name = "P_%d" % _piece_counter
	piece.piece_id = piece_id
	piece.position = placement["position"]
	piece.rotation = Vector3(0, placement["rotation"], 0)
	pieces_root.add_child(piece, true)
	QuestManager.report_build(piece_id)


func _server_demolish(peer_id: int, piece_name: String) -> void:
	var piece := pieces_root.get_node_or_null(piece_name)
	var player := _player_node(peer_id)
	if not piece is BuildPiece or player == null or _held_item(peer_id) != "hammer":
		return
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(piece.global_position) > BuildDB.BUILD_RANGE + 2.0:
		return
	var cost: Dictionary = BuildDB.get_piece(piece.piece_id)["cost"]
	for item: String in cost:
		_give(peer_id, item, int(cost[item]) / 2)  # Se devuelve la mitad.
	piece.queue_free()


func _server_door(peer_id: int, piece_name: String) -> void:
	var piece := pieces_root.get_node_or_null(piece_name)
	var player := _player_node(peer_id)
	if piece is BuildPiece and player != null and piece.kind() == "doorway":
		var player_pos: Vector3 = player.sync_pos
		if player_pos.distance_to(piece.global_position) < 5.0:
			piece.door_open = not piece.door_open


# --- Fabricación -----------------------------------------------------------------------
# Los materiales se descuentan al encargar; si se cancela, se devuelven.

func _server_craft(peer_id: int, recipe_id: String, amount: int) -> void:
	var recipe := RecipeDB.get_recipe(recipe_id)
	var inventory: Inventory = _inventories.get(peer_id)
	var player := _player_node(peer_id)
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
	var player := _player_node(peer_id)
	if node == null or node.depleted or player == null:
		return
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(node.global_position) > GATHER_RANGE:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_gather_ms.get(peer_id, -100000)) < GATHER_MIN_INTERVAL_MS:
		return
	_last_gather_ms[peer_id] = now
	var held := _held_item(peer_id)
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
	for chest_name in _chest_timers.keys():
		_chest_timers[chest_name] -= delta
		if _chest_timers[chest_name] <= 0.0:
			_chest_timers.erase(chest_name)
			_set_chest_state.rpc(chest_name, false)


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
	var player := _player_node(peer_id)
	if player == null:
		return landmarks.get("spawn", Vector3.ZERO)
	var rot: float = player.sync_rot
	var pos: Vector3 = player.sync_pos + Vector3(-sin(rot), 0, -cos(rot)) * 1.3
	pos += Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	pos.y = maxf(terrain.get_height(pos.x, pos.z), TerrainGenerator.WATER_LEVEL - 0.3)
	return pos


func _server_pickup(peer_id: int, drop_name: String) -> void:
	var drop := drops_root.get_node_or_null(drop_name)
	var player := _player_node(peer_id)
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
					"from": Vector3(-280, 130, 280), "to": Vector3(60, 110, 300),
					"look_from": Vector3(0, 0, 0), "look_to": Vector3(0, 10, 0),
					"duration": 7.0, "text": "Una isla olvidada emerge entre la niebla...",
				},
				{
					"from": spawn + Vector3(14, 9, 16), "to": spawn + Vector3(5, 3.5, 7),
					"look_from": spawn + Vector3(0, 1, 0),
					"duration": 4.5, "text": "Juntos, tendrán que sobrevivir a sus noches y descubrir sus secretos.",
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
					"from": crystal + Vector3(0, 40, 60), "to": crystal + Vector3(0, 90, 130),
					"look_from": crystal,
					"duration": 5.0, "text": "La isla es grande. Explórenla, constrúyanse un refugio... y cuídense de las sombras.",
				},
			]
	return []
