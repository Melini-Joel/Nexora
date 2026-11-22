extends Node3D
## El mundo compartido. Genera la isla con biomas (igual en todos los peers gracias a la semilla)
## y contiene la lógica autoritativa del servidor: jugadores (vida/hambre/muerte), recolección,
## inventarios, fabricación, combate, animales, sombras nocturnas, domesticación, construcción,
## cofres y el ciclo de día y noche.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DROP_SCENE := preload("res://scenes/item_drop.tscn")
const CREATURE_SCENE := preload("res://scenes/creature.tscn")
const PIECE_SCENE := preload("res://scenes/build_piece.tscn")

const PLACEMENT_ATTEMPTS := 14000  ## Puntos que se prueban para poner árboles, rocas y plantas.
const CHEST_COUNT := 30
const MAINLAND_CHEST_COUNT := 14
const RESPAWN_TIME := 90.0  ## Segundos hasta que reaparece un recurso agotado.
const CHEST_REFILL_TIME := 480.0
const GATHER_RANGE := 6.0  ## Distancia máxima aceptada por el servidor (anti-trampas).
const GATHER_MIN_INTERVAL_MS := 350
const STARTER_KIT := [["stone_hatchet", 1], ["berries", 5]]
const MAX_CRAFT_QUEUE := 8
const MOBS_PER_PLAYER := 2
const HUNGER_PER_SECOND := 100.0 / (40.0 * 60.0)  ## La comida dura ~40 minutos.
const BLUEPRINT_WEIGHTS := {"bp_foundation": 5, "bp_wall": 5, "bp_doorway": 3, "bp_roof": 3, "bp_campfire": 4, "bp_stone": 1}

## Qué aparece en cada bioma: [probabilidad acumulada, tipo]
const BIOME_SPAWNS := {
	"meadow": [[0.06, "round"], [0.1, "oak"], [0.15, "birch"], [0.18, "pine"], [0.23, "rock"], [0.3, "fiber"], [0.36, "berry"]],
	"forest": [[0.3, "pine"], [0.39, "round"], [0.47, "birch"], [0.54, "oak"], [0.58, "rock"], [0.62, "fiber"], [0.67, "berry"]],
	"desert": [[0.06, "cactus"], [0.08, "dead"], [0.15, "rock"]],
	"tundra": [[0.14, "snow_pine"], [0.17, "dead"], [0.25, "rock"]],
}
const ORE_CHANCE := {"meadow": 0.2, "forest": 0.25, "desert": 0.5, "tundra": 0.4}

var generated := false
var generated_at_ms := 0
var terrain: TerrainGenerator
var day_night: DayNight
## Lugares importantes para misiones y cinemáticas.
var landmarks: Dictionary = {}
var mainland: MainlandBuilder  ## Puerto, pueblo, castillo y bandidos de Valdoria.
## El Albatros: cuántas etapas de reparación están listas (ver ShipDB), lo aportado para la
## etapa actual y si ya hizo su primer viaje.
var ship_stage := 0
var ship_delivered: Dictionary = {}
var ship_sailed := false
var _ship_site: Interactable
var _ship_y := 0.0
var _pending_arrival := ""
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
## Jugadores que no están conectados (salieron o vienen de una partida guardada):
## nombre -> {"inventory": Array, "health", "hunger", "position": Vector3}
var _saved_players: Dictionary = {}
var _progress: Dictionary = {}  ## peer_id -> nivel, experiencia, puntos y habilidades (SkillDB)
var _stats: Dictionary = {}  ## peer_id -> {"health", "hunger"}
var _last_gather_ms: Dictionary = {}
var _last_attack_ms: Dictionary = {}
var _drop_counter := 0
var _creature_counter := 0
var _piece_counter := 0
var _storages: Dictionary = {}  ## nombre de la caja -> Inventory
var _storage_viewers: Dictionary = {}  ## nombre de la caja -> [peer_id que la tienen abierta]
var _beds: Dictionary = {}  ## nombre del jugador -> nombre de su cama
var _craft_queues: Dictionary = {}  ## peer_id -> [{recipe, remaining, time_left, time}]
var _animal_respawns: Array = []  ## [especie, segundos]
var _tick := 0.0
var _clear_zones: Array = []
var _spatial: Dictionary = {}  ## Grilla para separar objetos al ubicarlos.

var _crystal: Node3D
var _crystal_base_y := 0.0
var _sun: DirectionalLight3D
var _water_material: ShaderMaterial
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
	QuestManager.quest_changed.connect(func() -> void:
		if _ship_site:
			_refresh_ship_site_text()
	)


func _process(delta: float) -> void:
	if not generated:
		return
	_time += delta
	if _crystal:
		_crystal.rotation.y = _time * 0.8
		_crystal.position.y = _crystal_base_y + sin(_time * 1.5) * 0.25
	_update_audio()
	if multiplayer.is_server() and Network.is_online():
		_update_respawns(delta)
		_update_crafting(delta)
		_tick -= delta
		if _tick <= 0.0:
			_tick = 1.0
			_server_tick()


## Música y ambiente según la hora y dónde está el jugador.
func _update_audio() -> void:
	if Engine.get_process_frames() % 15 != 0 or Game.local_player == null:
		return
	if get_node_or_null("IntroStage") != null and Cinematics.playing:
		return  # La cinemática de inicio maneja su propio sonido.
	var night := is_night()
	Sound.set_music("night" if night else "day")
	var height: float = Game.local_player.global_position.y
	Sound.set_ambience("wind", clampf(0.3 + height / 60.0, 0.3, 1.2) * (0.6 if night else 1.0))
	Sound.set_ambience("night", 0.8 if night else 0.0)
	Sound.set_ambience("waves", clampf(1.0 - (height - TerrainGenerator.WATER_LEVEL) / 8.0, 0.0, 1.0))
	Sound.set_ambience("rain", 0.0)


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
	mainland = MainlandBuilder.new()
	mainland.name = "Mainland"
	add_child(mainland)
	mainland.build(self, world_seed)
	_place_resources(world_seed)
	_place_chests(world_seed)
	if DisplayServer.get_name() != "headless":
		var grass := GrassField.new()
		grass.name = "Grass"
		add_child(grass)
		grass.setup(terrain, world_seed)
		var decor := DecorField.new()
		decor.name = "Decor"
		add_child(decor)
		decor.setup(terrain, world_seed, _in_clear_zone)
	generated = true
	generated_at_ms = Time.get_ticks_msec()
	if multiplayer.is_server():
		_spawn_initial_animals()
		mainland.spawn_bandits()
	Game.world_generated.emit()


func _build_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 120.0
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
	sun.shadow_blur = 1.5
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
## Baja: sin sombras ni efectos · Media: sombras y brillo · Alta: + oclusión ambiental (SSAO),
## luz indirecta en pantalla (SSIL) y sombras suaves · Ultra: + iluminación global (SDFGI) y
## niebla volumétrica con rayos de sol. Los efectos de Alta/Ultra solo existen en Forward+.
func _apply_graphics() -> void:
	var quality: String = Settings.get_value("quality")
	var high := quality in ["high", "ultra"]
	_sun.shadow_enabled = quality != "low"
	_sun.directional_shadow_max_distance = 200.0 if quality == "ultra" else (150.0 if high else 80.0)
	_sun.light_angular_distance = 0.6 if high else 0.0
	_environment.glow_enabled = quality != "low"
	_environment.ssao_enabled = high
	_environment.ssil_enabled = high
	_environment.sdfgi_enabled = quality == "ultra"
	_environment.volumetric_fog_enabled = quality == "ultra"


func _build_water() -> void:
	var plane := PlaneMesh.new()
	# Un solo mar para la isla y el continente.
	plane.size = Vector2.ONE * 4600.0
	plane.subdivide_width = 180
	plane.subdivide_depth = 180
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	var ripples := FastNoiseLite.new()
	ripples.frequency = 0.03
	ripples.fractal_octaves = 3
	var ripple_texture := NoiseTexture2D.new()
	ripple_texture.width = 256
	ripple_texture.height = 256
	ripple_texture.seamless = true
	ripple_texture.as_normal_map = true
	ripple_texture.bump_strength = 6.0
	ripple_texture.noise = ripples
	mat.set_shader_parameter("ripple_normal", ripple_texture)
	plane.material = mat
	_water_material = mat
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.position = Vector3(TerrainGenerator.MAINLAND_CENTER.x * 0.5, TerrainGenerator.WATER_LEVEL, 0)
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
	_place_wreck((-to_monolith).rotated(PI * 0.6))

	var lookout := terrain.find_highest_point(TerrainGenerator.SIZE * 0.42, Vector2(monolith.x, monolith.z), 120.0)
	landmarks["lookout"] = lookout
	_place_prop(PropFactory.make_cairn(), lookout - Vector3(0, 0.2, 0), Vector3.ZERO)


## Altura de las olas (0.08 = calmo, 0.9 = tormenta). Lo usa la cinemática de inicio.
func set_wave_height(height: float) -> void:
	if _water_material:
		_water_material.set_shader_parameter("wave_height", height)


## Restos del Albatros en otra costa, con dos cofres. También define dónde navega
## el barco en la cinemática de inicio (mar adentro → arrecife → playa).
func _place_wreck(direction: Vector2) -> void:
	for attempt in 12:
		var dir := direction.rotated(attempt * 0.45 * (1 if attempt % 2 == 0 else -1))
		# Se busca la costa desde el mar abierto hacia adentro (así no confunde un lago con el mar).
		for step in range(int(TerrainGenerator.SIZE * 0.5), 30, -1):
			var p := dir * step
			if terrain.get_height(p.x, p.y) < TerrainGenerator.WATER_LEVEL + 0.2:
				continue
			p = dir * (step + 1)  # Primer punto con agua, del lado del mar.
			var beach := dir * (step - 2)
			var pos := _ground(beach)
			var wreck := Interactable.new()
			wreck.name = "Albatros"
			wreck.dialog_id = "albatros"
			wreck.position = pos
			wreck.rotation.y = atan2(dir.x, dir.y)  # La proa mira hacia la isla.
			add_child(wreck)
			_ship_site = wreck
			_ship_y = TerrainGenerator.WATER_LEVEL - 0.75 - pos.y
			_refresh_ship_site()
			landmarks["wreck"] = pos
			landmarks["reef"] = Vector3(p.x + dir.x * 50, TerrainGenerator.WATER_LEVEL, p.y + dir.y * 50)
			landmarks["ship_start"] = Vector3(p.x + dir.x * 230, TerrainGenerator.WATER_LEVEL, p.y + dir.y * 230)
			landmarks["ship_yaw"] = atan2(dir.x, dir.y)
			_clear_zones.append([beach, 14.0])
			var side := Vector2(-dir.y, dir.x)
			for i in 2:
				var spot := beach + side * (6.0 if i == 0 else -7.0) - dir * 3.0
				var chest := LootChest.new()
				chest.name = "Chest_W%d" % i
				chest.position = _ground(spot)
				chest.rotation.y = 0.7 * i
				add_child(chest)
				chests[str(chest.name)] = chest
			return


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
	var container := Node3D.new()
	container.name = "Resources"
	add_child(container)
	for region in terrain.regions:
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed if region.id == "island" else world_seed + 777
		var attempts := int(PLACEMENT_ATTEMPTS * pow(region.size / TerrainGenerator.SIZE, 2.0) * (1.0 if region.id == "island" else 0.75))
		_place_region_resources(region, rng, attempts, container, "R_" if region.id == "island" else "RM_")


func _place_region_resources(region: TerrainGenerator.Region, rng: RandomNumberGenerator, attempts: int, container: Node3D, prefix: String) -> void:
	var limit := region.size * 0.47
	var on_mainland := region.id == "mainland"
	for i in attempts:
		var p := region.center + Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 0.8 or _in_clear_zone(p):
			continue
		if on_mainland:
			var local := p - region.center
			if TerrainGenerator.road_factor(local.x, local.y) > 0.0 or TerrainGenerator.in_field(local.x, local.y):
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
		var spacing := 2.6 if kind in ["round", "pine", "snow_pine", "birch", "dead"] else (3.6 if kind == "oak" else 1.6)
		if slope > (0.55 if kind == "rock" else 0.35) or not _space_free(p, spacing):
			continue
		var node: ResourceNode
		match kind:
			"round", "pine", "snow_pine", "birch", "oak", "dead":
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
		var key := "%s%d" % [prefix, i]
		node.name = key
		node.position = Vector3(p.x, h - (0.2 if kind == "rock" else 0.08), p.y)
		node.rotation.y = yaw
		container.add_child(node)
		resource_nodes[key] = node


func _place_chests(world_seed: int) -> void:
	_place_region_chests(terrain.island, world_seed + 500, CHEST_COUNT, "Chest_")
	if terrain.mainland:
		_place_region_chests(terrain.mainland, world_seed + 900, MAINLAND_CHEST_COUNT, "Chest_M")


func _place_region_chests(region: TerrainGenerator.Region, chest_seed: int, amount: int, prefix: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = chest_seed
	var limit := region.size * 0.45
	var placed := 0
	for attempt in 600:
		if placed >= amount:
			break
		var p := region.center + Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var yaw := rng.randf() * TAU
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 1.0 or p.length() < 30.0 or _in_clear_zone(p) or h > TerrainGenerator.SNOW_HEIGHT + 6.0 \
				or terrain.get_slope(p.x, p.y) > 0.3 or not _space_free(p, 2.0):
			continue
		_mark_space(p)
		var chest := LootChest.new()
		chest.name = "%s%d" % [prefix, placed]
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
## region_id: "island" o "mainland" (solo cuenta si no se pasa "near").
func random_land_spot(biomes: Array, rng: RandomNumberGenerator, near: Vector3 = Vector3.INF, min_r: float = 0.0, max_r: float = 0.0, region_id: String = "island") -> Vector3:
	var region := terrain.region_of(region_id)
	if region == null:
		return Vector3.INF
	var limit := region.size * 0.46
	for attempt in 60:
		var p: Vector2
		if near != Vector3.INF:
			var angle := rng.randf() * TAU
			p = Vector2(near.x, near.z) + Vector2(cos(angle), sin(angle)) * rng.randf_range(min_r, max_r)
		else:
			p = region.center + Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var h := terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 1.0 or terrain.get_slope(p.x, p.y) > 0.5:
			continue
		if not biomes.is_empty() and not terrain.get_biome(p.x, p.y) in biomes:
			continue
		if p.length() < TerrainGenerator.SPAWN_RADIUS + 6.0 or (mainland and mainland.in_town(p)):
			continue
		return Vector3(p.x, h + 0.5, p.y)
	return Vector3.INF


# --- Jugadores (servidor) -------------------------------------------------------------

func get_players() -> Array[Node]:
	return players_root.get_children()


## Punto de aparición en el campamento de la isla, o en el puerto de Valdoria.
func get_spawn_point(peer_id: int, region_id: String = "island") -> Vector3:
	var angle := float(peer_id % Network.MAX_PLAYERS) / Network.MAX_PLAYERS * TAU
	var center := Vector2.ZERO
	if region_id == "mainland" and landmarks.has("harbor_spawn"):
		var harbor: Vector3 = landmarks["harbor_spawn"]
		center = Vector2(harbor.x, harbor.z)
	var p := center + Vector2(cos(angle), sin(angle)) * 4.0
	return Vector3(p.x, terrain.get_height(p.x, p.y) + 0.3, p.y)


## Región de un punto; en mar abierto, la más cercana.
func region_near(pos: Vector3) -> String:
	var region_id := terrain.region_at(pos.x, pos.z)
	if region_id != "":
		return region_id
	return "mainland" if terrain.mainland and pos.x > TerrainGenerator.MAINLAND_CENTER.x * 0.5 else "island"


## Nombre del lugar donde está un punto ("" si no está en ningún pueblo).
func place_name(pos: Vector3) -> String:
	return mainland.place_name(pos) if mainland else ""


func _on_player_joined(peer_id: int) -> void:
	if players_root.has_node(str(peer_id)):
		return
	var player_name: String = Network.players[peer_id]["name"]
	# Si ya había jugado en este mundo, recupera inventario, vida, hambre y posición.
	var saved: Dictionary = _saved_players.get(player_name, {})
	_saved_players.erase(player_name)
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.player_name = player_name
	player.position = saved.get("position", get_spawn_point(peer_id))
	player.sync_pos = player.position
	players_root.add_child(player, true)

	var inventory := Inventory.new()
	if saved.has("inventory"):
		inventory.load_from(saved["inventory"])
	else:
		for entry in STARTER_KIT:
			inventory.add(entry[0], entry[1])
	_inventories[peer_id] = inventory
	_progress[peer_id] = saved.get("progress", SkillDB.empty_progress()).duplicate(true)
	_stats[peer_id] = {"health": float(saved.get("health", _max_health(peer_id))), "hunger": float(saved.get("hunger", 80.0))}
	_send_progress(peer_id)
	# Sus mascotas lo vuelven a reconocer.
	for creature in creatures_root.get_children():
		if creature is Creature and creature.tamed_owner == player_name:
			creature.owner_peer = peer_id
			creature.follow_owner = true
	_send_inventory(peer_id)
	_send_stats(peer_id)


func _on_player_left(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player:
		if _inventories.has(peer_id):
			_saved_players[player.player_name] = _player_snapshot(peer_id)
		player.queue_free()
	for creature in creatures_root.get_children():
		if creature is Creature and creature.owner_peer == peer_id:
			creature.follow_owner = false  # La mascota espera a que vuelva.
	_inventories.erase(peer_id)
	_craft_queues.erase(peer_id)
	_stats.erase(peer_id)
	_progress.erase(peer_id)
	_last_gather_ms.erase(peer_id)


## Lo que se guarda de un jugador conectado (lo que estaba fabricando vuelve al inventario).
func _player_snapshot(peer_id: int) -> Dictionary:
	var inventory := Inventory.new()
	inventory.load_from(_inventories[peer_id].to_array())
	for job in _craft_queues.get(peer_id, []):
		var ingredients: Dictionary = RecipeDB.get_recipe(job["recipe"])["ingredients"]
		for item: String in ingredients:
			inventory.add(item, int(ingredients[item]) * int(job["remaining"]))
	var player := _player_node(peer_id)
	var stats: Dictionary = _stats.get(peer_id, {"health": 100.0, "hunger": 80.0})
	return {
		"inventory": inventory.to_array(), "health": stats["health"], "hunger": stats["hunger"],
		"progress": _progress.get(peer_id, SkillDB.empty_progress()).duplicate(true),
		"position": player.sync_pos if player else get_spawn_point(peer_id),
	}


# --- Guardado de partida (servidor) ------------------------------------------------------

## Todo lo necesario para volver a armar este mundo (ver SaveManager).
func build_save() -> Dictionary:
	var players := _saved_players.duplicate(true)
	for peer_id in _inventories.keys():
		players[Network.players.get(peer_id, {}).get("name", str(peer_id))] = _player_snapshot(peer_id)
	var pieces: Array = []
	for piece in pieces_root.get_children():
		if piece is BuildPiece and not piece.is_queued_for_deletion():
			var entry := {"id": piece.piece_id, "position": piece.position, "rotation": piece.rotation.y,
				"door_open": piece.door_open, "owner": piece.owner_name}
			if _storages.has(str(piece.name)):
				entry["storage"] = _storages[str(piece.name)].to_array()
			for owner in _beds:
				if _beds[owner] == str(piece.name):
					entry["bed_of"] = owner
			pieces.append(entry)
	var drops: Array = []
	for drop in drops_root.get_children():
		if not drop.is_queued_for_deletion():
			drops.append({"item": drop.item_id, "count": drop.count, "position": drop.position})
	var pets: Array = []
	for creature in creatures_root.get_children():
		if creature is Creature and creature.tamed_owner != "" and not creature.dead:
			pets.append({"species": creature.species, "position": creature.global_position, "owner": creature.tamed_owner,
				"follow": creature.follow_owner, "health": creature.health})
	return {
		"seed": Network.world_seed, "time": day_night.time, "day": day_night.day,
		"blueprints": known_blueprints.duplicate(), "quests": QuestManager.export_state(),
		"players": players, "pieces": pieces, "drops": drops, "pets": pets,
		"depleted": _respawn_timers.duplicate(), "chests": _chest_timers.duplicate(),
		"ship": {"stage": ship_stage, "delivered": ship_delivered.duplicate(), "sailed": ship_sailed},
	}


## Rearma un mundo guardado (se llama justo después de generar la isla con la misma semilla).
func load_save(data: Dictionary) -> void:
	day_night.set_time(data.get("time", 0.3), data.get("day", 1))
	known_blueprints = data.get("blueprints", []).duplicate()
	var ship: Dictionary = data.get("ship", {})
	_apply_ship(int(ship.get("stage", 0)), ship.get("delivered", {}), bool(ship.get("sailed", false)))
	_saved_players = data.get("players", {}).duplicate(true)
	_respawn_timers = data.get("depleted", {}).duplicate()
	for node_name in _respawn_timers:
		_set_node_state(node_name, true)
	_chest_timers = data.get("chests", {}).duplicate()
	for chest_name in _chest_timers:
		_set_chest_state(chest_name, true)
	for entry in data.get("pieces", []):
		_piece_counter += 1
		var piece := PIECE_SCENE.instantiate()
		piece.name = "P_%d" % _piece_counter
		piece.piece_id = entry["id"]
		piece.position = entry["position"]
		piece.rotation = Vector3(0, entry["rotation"], 0)
		piece.door_open = entry.get("door_open", false)
		piece.owner_name = entry.get("owner", "")
		pieces_root.add_child(piece, true)
		if BuildDB.get_piece(entry["id"]).get("kind", "") == "storage":
			var box := Inventory.new(BuildDB.STORAGE_SLOTS)
			box.load_from(entry.get("storage", []))
			_storages[str(piece.name)] = box
		if entry.has("bed_of"):
			_beds[entry["bed_of"]] = str(piece.name)
	for entry in data.get("drops", []):
		_spawn_drop(entry["item"], int(entry["count"]), entry["position"])
	for entry in data.get("pets", []):
		_creature_counter += 1
		var creature := CREATURE_SCENE.instantiate()
		creature.name = "C_%d" % _creature_counter
		creature.species = entry["species"]
		creature.position = entry["position"] + Vector3(0, 0.5, 0)
		creature.tamed_owner = entry["owner"]
		creature.follow_owner = false  # Espera a que su dueño se conecte.
		creature.tame_progress = int(CreatureDB.get_species(entry["species"]).get("tame", {}).get("amount", 0))
		creatures_root.add_child(creature, true)
		creature.health = entry.get("health", creature.health)


## Estado que necesita un jugador que entra a una partida ya empezada.
func get_state_for_new_player() -> Dictionary:
	var opened: Array = []
	for chest_name in _chest_timers:
		opened.append(chest_name)
	return {
		"depleted": _respawn_timers.keys(), "chests": opened, "blueprints": known_blueprints,
		"time": day_night.time, "day": day_night.day,
		"ship": {"stage": ship_stage, "delivered": ship_delivered, "sailed": ship_sailed},
	}


func apply_state(state: Dictionary) -> void:
	for node_name in state.get("depleted", []):
		_set_node_state(node_name, true)
	for chest_name in state.get("chests", []):
		_set_chest_state(chest_name, true)
	known_blueprints = state.get("blueprints", [])
	var ship: Dictionary = state.get("ship", {})
	_apply_ship(int(ship.get("stage", 0)), ship.get("delivered", {}), bool(ship.get("sailed", false)))
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
			stats["health"] = minf(_max_health(peer_id), stats["health"] + 0.5)
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
		_receive_stats(stats["health"], stats["hunger"], _max_health(peer_id))
	else:
		_receive_stats.rpc_id(peer_id, stats["health"], stats["hunger"], _max_health(peer_id))


@rpc("authority", "reliable")
func _receive_stats(health: float, hunger: float, max_health: float) -> void:
	Game.set_stats(health, hunger, max_health)


# --- Experiencia y niveles (servidor) ------------------------------------------------------

func _max_health(peer_id: int) -> float:
	return SkillDB.max_health(_progress.get(peer_id, {}))


## Suma experiencia. Al llenar la barra sube de nivel y gana puntos para mejorar habilidades.
func add_xp(peer_id: int, amount: int) -> void:
	var progress: Dictionary = _progress.get(peer_id, {})
	if progress.is_empty() or amount <= 0:
		return
	progress["xp"] = int(progress["xp"]) + amount
	var leveled := false
	while progress["xp"] >= SkillDB.xp_to_next(progress["level"]):
		progress["xp"] -= SkillDB.xp_to_next(progress["level"])
		progress["level"] += 1
		progress["points"] += SkillDB.points_for_level(progress["level"])
		leveled = true
	if leveled:
		Network.announce.rpc("%s subió a nivel %d" % [Network.players.get(peer_id, {}).get("name", "?"), progress["level"]])
	_send_progress(peer_id, leveled)


func add_xp_all(amount: int) -> void:
	for peer_id in _progress.keys():
		add_xp(peer_id, amount)


func _send_progress(peer_id: int, leveled: bool = false) -> void:
	var data: Dictionary = _progress.get(peer_id, {})
	if peer_id == multiplayer.get_unique_id():
		_receive_progress(data, leveled)
	else:
		_receive_progress.rpc_id(peer_id, data, leveled)


@rpc("authority", "reliable")
func _receive_progress(data: Dictionary, leveled: bool) -> void:
	Game.set_progress(data, leveled)


func _server_skill_up(peer_id: int, skill: String) -> void:
	var progress: Dictionary = _progress.get(peer_id, {})
	if progress.is_empty() or not SkillDB.SKILLS.has(skill) or int(progress["points"]) <= 0:
		return
	if SkillDB.skill_level(progress, skill) >= int(SkillDB.SKILLS[skill]["max"]):
		return
	progress["skills"][skill] = SkillDB.skill_level(progress, skill) + 1
	progress["points"] -= 1
	if skill == "vitality":
		_stats[peer_id]["health"] += 15.0
	_send_progress(peer_id)
	_send_stats(peer_id)


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
	_stats[peer_id] = {"health": _max_health(peer_id), "hunger": 60.0}
	_send_inventory(peer_id)
	_send_stats(peer_id)
	Network.announce.rpc("%s murió %s. Sus cosas quedaron en el suelo." % [player.player_name, cause])
	var spawn := _respawn_point(peer_id)
	if peer_id == multiplayer.get_unique_id():
		_respawn_at(spawn)
	else:
		_respawn_at.rpc_id(peer_id, spawn)


## Si tiene cama, reaparece al lado; si no, en el campamento.
func _respawn_point(peer_id: int) -> Vector3:
	var player_name: String = Network.players.get(peer_id, {}).get("name", "")
	var bed := pieces_root.get_node_or_null(_beds.get(player_name, "-"))
	if bed is BuildPiece:
		return bed.global_position + bed.global_transform.basis.x * 1.2 + Vector3(0, 0.6, 0)
	var player := _player_node(peer_id)
	return get_spawn_point(peer_id, region_near(player.sync_pos) if player else "island")


# --- Cajas de almacenamiento ------------------------------------------------------------

func _storage_in_range(peer_id: int, box_name: String) -> Inventory:
	var box := pieces_root.get_node_or_null(box_name)
	var player := _player_node(peer_id)
	if not box is BuildPiece or player == null or not _storages.has(box_name):
		return null
	var player_pos: Vector3 = player.sync_pos
	if player_pos.distance_to(box.global_position) > 5.0:
		return null
	return _storages[box_name]


func _server_storage_open(peer_id: int, box_name: String) -> void:
	if _storage_in_range(peer_id, box_name) == null:
		return
	if not _storage_viewers.has(box_name):
		_storage_viewers[box_name] = []
	if not peer_id in _storage_viewers[box_name]:
		_storage_viewers[box_name].append(peer_id)
	_send_storage(box_name, [peer_id], true)


## Mueve un objeto entre la mochila ("p") y la caja ("s"), o dentro de cada una.
func _server_storage_move(peer_id: int, box_name: String, from_side: String, from_index: int, to_side: String, to_index: int) -> void:
	var box := _storage_in_range(peer_id, box_name)
	if box == null:
		return
	var inventory: Inventory = _inventories[peer_id]
	var source: Inventory = box if from_side == "s" else inventory
	var target: Inventory = box if to_side == "s" else inventory
	if not source.is_valid(from_index) or not target.is_valid(to_index):
		return
	if source == target:
		source.move(from_index, to_index)
	else:
		var a: Dictionary = source.slots[from_index]
		var b: Dictionary = target.slots[to_index]
		if a.is_empty():
			return
		if b.is_empty():
			target.slots[to_index] = a
			source.slots[from_index] = {}
		elif b["id"] == a["id"]:
			var n := mini(a["count"], ItemDB.stack_size(a["id"]) - b["count"])
			b["count"] += n
			a["count"] -= n
			if a["count"] <= 0:
				source.slots[from_index] = {}
		else:
			target.slots[to_index] = a
			source.slots[from_index] = b
	_send_inventory(peer_id)
	_send_storage(box_name, _storage_viewers.get(box_name, []))


## Shift+Click: pasa todo el casillero al otro lado.
func _server_storage_quick(peer_id: int, box_name: String, side: String, index: int) -> void:
	var box := _storage_in_range(peer_id, box_name)
	if box == null:
		return
	var inventory: Inventory = _inventories[peer_id]
	var source: Inventory = box if side == "s" else inventory
	var target: Inventory = inventory if side == "s" else box
	var stack := source.get_slot(index)
	if stack.is_empty():
		return
	var leftover := target.add(stack["id"], stack["count"])
	if leftover == 0:
		source.slots[index] = {}
	else:
		stack["count"] = leftover
	_send_inventory(peer_id)
	_send_storage(box_name, _storage_viewers.get(box_name, []))


func _send_storage(box_name: String, peers: Array, opening: bool = false) -> void:
	var data: Array = _storages[box_name].to_array()
	for peer_id in peers:
		if peer_id == multiplayer.get_unique_id():
			_receive_storage(box_name, data, opening)
		elif _inventories.has(peer_id):
			_receive_storage.rpc_id(peer_id, box_name, data, opening)


@rpc("authority", "reliable")
func _receive_storage(box_name: String, slots: Array, opening: bool) -> void:
	Game.set_storage(box_name, slots, opening)


@rpc("authority", "reliable")
func _respawn_at(pos: Vector3) -> void:
	if Game.local_player:
		Game.last_death_position = Game.local_player.global_position
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
		"storage_open":
			if args.size() == 1:
				_server_storage_open(peer_id, str(args[0]))
		"storage_close":
			if args.size() == 1:
				_storage_viewers.get(str(args[0]), []).erase(peer_id)
		"storage_move":
			if args.size() == 5:
				_server_storage_move(peer_id, str(args[0]), str(args[1]), int(args[2]), str(args[3]), int(args[4]))
		"storage_quick":
			if args.size() == 3:
				_server_storage_quick(peer_id, str(args[0]), str(args[1]), int(args[2]))
		"skill_up":
			if args.size() == 1:
				_server_skill_up(peer_id, str(args[0]))
		"ship_contribute":
			_server_ship_contribute(peer_id)
		"sail":
			if args.size() == 1:
				_server_sail(peer_id, str(args[0]))
		"trade":
			if args.size() == 2:
				_server_trade(peer_id, str(args[0]), int(args[1]))
		"bed_claim":
			if args.size() == 1:
				var bed := pieces_root.get_node_or_null(str(args[0]))
				if bed is BuildPiece and bed.kind() == "bed":
					var player_name: String = Network.players[peer_id]["name"]
					_beds[player_name] = str(bed.name)
					_notify_peer(peer_id, "Ahora reaparecés en esta cama.")
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
	stats["health"] = clampf(stats["health"] + item.get("heal", 0), 1.0, _max_health(peer_id))
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
	creature.take_damage(ItemDB.damage(held) * SkillDB.damage_multiplier(_progress.get(peer_id, {})), player)


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
		var xp_key := "kill_animal"
		if creature.species == "shade":
			xp_key = "kill_shade"
		elif creature.species == "brute":
			xp_key = "kill_brute"
		elif SkillDB.XP.has("kill_" + creature.species):
			xp_key = "kill_" + creature.species
		add_xp(killer_peer, SkillDB.XP[xp_key])
	if CreatureDB.get_species(creature.species).has("camp"):
		mainland.on_bandit_died(creature.species)
	elif not CreatureDB.is_mob(creature.species):
		var region_id := terrain.region_at(creature.global_position.x, creature.global_position.z)
		_animal_respawns.append([creature.species, 120.0, region_id if region_id != "" else "island"])


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
		add_xp(peer_id, SkillDB.XP["tame"])


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
		# En Valdoria también hay animales (menos), salvo los del desierto.
		if terrain.mainland and not data.get("biomes", []).has("desert"):
			for i in int(data.get("count", 0) * 0.8):
				var pos := random_land_spot(data.get("biomes", []), rng, Vector3.INF, 0.0, 0.0, "mainland")
				if pos != Vector3.INF:
					_spawn_creature(species, pos)


func _update_animals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for entry in _animal_respawns.duplicate():
		entry[1] -= 1.0
		if entry[1] <= 0.0:
			_animal_respawns.erase(entry)
			var region_id: String = entry[2] if entry.size() > 2 else "island"
			var pos := random_land_spot(CreatureDB.get_species(entry[0]).get("biomes", []), rng, Vector3.INF, 0.0, 0.0, region_id)
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
		if nearby >= MOBS_PER_PLAYER + mini(day_night.day - 1, 2):
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
	add_xp(peer_id, SkillDB.XP["chest"])


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
		"campfire", "storage", "bed":
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
	piece.owner_name = Network.players.get(peer_id, {}).get("name", "")
	pieces_root.add_child(piece, true)
	match data["kind"]:
		"storage":
			_storages[str(piece.name)] = Inventory.new(BuildDB.STORAGE_SLOTS)
		"bed":
			_beds[piece.owner_name] = str(piece.name)
			_notify_peer(peer_id, "Cama lista: si morís, reaparecés acá.")
	QuestManager.report_build(piece_id)
	add_xp(peer_id, SkillDB.XP["build"])


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
	var key := str(piece.name)
	if _storages.has(key):  # Lo que había en la caja queda en el suelo.
		for i in BuildDB.STORAGE_SLOTS:
			var stack: Dictionary = _storages[key].take(i)
			if not stack.is_empty():
				_spawn_drop(stack["id"], stack["count"], piece.global_position + Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)))
		_storages.erase(key)
		_storage_viewers.erase(key)
	for owner in _beds.keys():
		if _beds[owner] == key:
			_beds.erase(owner)
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
		add_xp(peer_id, SkillDB.XP["craft"])
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
	amount = ceili(amount * SkillDB.gather_multiplier(_progress.get(peer_id, {})))
	node.hits_left -= 1
	add_xp(peer_id, SkillDB.XP["gather"])
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

## La historia del comienzo (~1 minuto): el naufragio del Albatros.
## Arma un escenario temporal (barco, tormenta, lluvia) que se borra al terminar.
func _intro_cinematic() -> Array:
	var stage := IntroStage.new()
	stage.setup(self)
	add_child(stage)
	var ship := stage.ship
	var spawn: Vector3 = landmarks["spawn"]
	var wreck: Vector3 = landmarks["wreck"]
	var monolith: Vector3 = landmarks["monolith"]
	var yaw: float = landmarks["ship_yaw"]
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))  # Hacia donde navega el barco (la isla).
	var side := Vector3(fwd.z, 0, -fwd.x)
	var up := Vector3.UP
	var to_monolith: Vector3 = monolith - (landmarks["ship_start"] as Vector3)
	return [
		{"card": "Hace tres semanas, el Albatros zarpó de Puerto Esperanza con cuarenta pasajeros\ny una carga que nadie quiso nombrar.", "duration": 6.5},
		{"card": "En la cuarta noche, una tormenta nos arrancó de toda ruta conocida.", "duration": 5.0,
			"callback": stage.begin_storm.bind(18.0)},
		{
			"follow": ship, "from": side * -26 + up * 9 - fwd * 14, "to": side * -18 + up * 6 + fwd * 6,
			"look_from": up * 4, "look_to": up * 4 + fwd * 6, "shake": 0.25, "duration": 7.0,
			"text": "Las olas eran más altas que el mástil. La brújula giraba sin control.",
		},
		{
			"follow": ship, "from": side * 4 + up * 6 - fwd * 10, "to": side * 2.5 + up * 5 - fwd * 4,
			"look_from": up * 5 + fwd * 6, "shake": 0.45, "duration": 5.0,
			"text": "El capitán juraba que no había tierra en cientos de millas...",
		},
		{
			"follow": ship, "from": up * 14 - fwd * 34, "to": up * 11 - fwd * 24,
			"look_from": to_monolith.normalized() * 120 + up * 25, "shake": 0.2, "duration": 6.0,
			"callback": stage.set_storm.bind(0.45),
			"text": "...hasta que, entre los relámpagos, apareció una isla. En su cima brillaba una luz azul.",
		},
		{
			"follow": ship, "from": side * 16 + up * 4 + fwd * 18, "to": side * 13 + up * 3 + fwd * 14,
			"look_from": up * 3, "shake": 0.8, "duration": 4.5, "fade_out": true,
			"callback": stage.crash, "text": "Las rocas partieron el casco en dos.",
		},
		{"card": "...", "duration": 3.5, "callback": stage.end_storm},
		{"card": "Desperté en la arena. Solo se oía el mar.", "duration": 4.5},
		{
			"from": wreck + side * 16 + up * 2.5 - fwd * 6, "to": wreck + side * 11 + up * 3.5 + fwd * 4,
			"look_from": wreck + up * 1.5, "duration": 7.0,
			"text": "Del Albatros solo quedaban restos. Y nosotros.",
		},
		{
			"from": wreck + up * 6 - fwd * 4, "to": spawn + Vector3(18, 16, 20),
			"look_from": wreck + fwd * 20, "look_to": spawn + up, "duration": 6.0,
			"text": "Alguien nos arrastró tierra adentro, hasta un campamento. Las huellas en la arena eran viejas.",
		},
		{
			"from": spawn + Vector3(14, 9, 16), "to": spawn + Vector3(5, 3.5, 7),
			"look_from": spawn + up, "duration": 5.5,
			"text": "Sobrevivan. Descubran qué es esta isla. Y nunca salgan solos de noche.",
		},
	]


# --- El Albatros: reparación y viajes ---------------------------------------------------

## Rearma el barco de la playa según la etapa (en todos los peers).
func _refresh_ship_site() -> void:
	if _ship_site == null:
		return
	PropFactory.fill_ship_site(_ship_site, ship_stage, _ship_y)
	_ship_site.interact_text = "Zarpar en el Albatros" if ship_stage >= ShipDB.stage_count() else \
		("Reparar el Albatros" if QuestManager.get_status("m_albatros") == "done" else "Revisar los restos del Albatros")
	if mainland:
		mainland.set_ship_visible(ship_sailed)


func _apply_ship(stage: int, delivered: Dictionary, sailed: bool) -> void:
	var changed := stage != ship_stage
	ship_stage = stage
	ship_delivered = delivered.duplicate()
	ship_sailed = sailed
	if changed or _ship_site == null or (mainland and mainland.ship_visible != sailed):
		_refresh_ship_site()
	elif _ship_site:
		_refresh_ship_site_text()


func _refresh_ship_site_text() -> void:
	_ship_site.interact_text = "Zarpar en el Albatros" if ship_stage >= ShipDB.stage_count() else \
		("Reparar el Albatros" if QuestManager.get_status("m_albatros") == "done" else "Revisar los restos del Albatros")


@rpc("authority", "call_local", "reliable")
func _sync_ship(stage: int, delivered: Dictionary, sailed: bool) -> void:
	_apply_ship(stage, delivered, sailed)
	QuestManager.quest_changed.emit()  # Refresca el panel de misiones y la ventana del barco.


## Lo que falta de una etapa, por ejemplo "Tablón 12/40 · Clavos 0/30" ("" si no es la actual).
func ship_progress_text(stage_id: String) -> String:
	var stage := ShipDB.get_stage(ship_stage)
	if stage.is_empty() or stage["id"] != stage_id:
		return ""
	var parts: Array[String] = []
	var items: Dictionary = stage["items"]
	for item: String in items:
		parts.append("%s %d/%d" % [ItemDB.item_name(item), int(ship_delivered.get(item, 0)), int(items[item])])
	return " · ".join(parts)


## ¿El jugador está al lado de un barco? ("island" = el de la playa, "mainland" = el del puerto)
func _near_ship(peer_id: int, where: String) -> bool:
	var player := _player_node(peer_id)
	if player == null:
		return false
	var key := "wreck" if where == "island" else "harbor_ship"
	return landmarks.has(key) and (player.sync_pos as Vector3).distance_to(landmarks[key]) < 32.0


func _server_ship_contribute(peer_id: int) -> void:
	if ship_stage >= ShipDB.stage_count() or not _near_ship(peer_id, "island"):
		return
	if QuestManager.get_status("m_albatros") != "done":
		_notify_peer(peer_id, "Nilo, el pescador, sabe de barcos. Primero hablen con él.")
		return
	var inventory: Inventory = _inventories[peer_id]
	var stage := ShipDB.get_stage(ship_stage)
	var items: Dictionary = stage["items"]
	var given: Dictionary = {}
	for item: String in items:
		var missing := int(items[item]) - int(ship_delivered.get(item, 0))
		var amount := mini(missing, inventory.count(item))
		if amount > 0 and inventory.remove(item, amount):
			ship_delivered[item] = int(ship_delivered.get(item, 0)) + amount
			given[item] = amount
	if given.is_empty():
		_notify_peer(peer_id, "No tenés nada de lo que falta: %s" % ship_progress_text(stage["id"]))
		return
	_send_inventory(peer_id)
	var player_name: String = Network.players[peer_id]["name"]
	var complete := true
	for item: String in items:
		if int(ship_delivered.get(item, 0)) < int(items[item]):
			complete = false
	if complete:
		ship_stage += 1
		ship_delivered = {}
		Network.announce.rpc("¡%s terminó de reparar: %s! (%d/%d)" % [player_name, stage["name"], ship_stage, ShipDB.stage_count()])
		_play_ship_sound.rpc()
		add_xp_all(SkillDB.XP["ship_stage"])
		_sync_ship.rpc(ship_stage, ship_delivered, ship_sailed)
		QuestManager.report_ship(stage["id"])
		if ship_stage >= ShipDB.stage_count():
			Network.announce.rpc("¡El Albatros está listo para zarpar! Apretá E sobre el barco.")
	else:
		Network.announce.rpc("%s aportó al Albatros: %s" % [player_name, ItemDB.list_text(given)])
		_sync_ship.rpc(ship_stage, ship_delivered, ship_sailed)
	add_xp(peer_id, SkillDB.XP["build"])


@rpc("authority", "call_local", "reliable")
func _play_ship_sound() -> void:
	Sound.play("quest_complete")


func _server_sail(peer_id: int, destination: String) -> void:
	if ship_stage < ShipDB.stage_count() or not destination in ["mainland", "island"]:
		return
	if not _near_ship(peer_id, "island" if destination == "mainland" else "mainland"):
		return
	ship_sailed = true
	_sync_ship.rpc(ship_stage, ship_delivered, ship_sailed)
	var player_name: String = Network.players[peer_id]["name"]
	Network.announce.rpc("%s hizo zarpar al Albatros rumbo a %s." % [player_name, "Valdoria" if destination == "mainland" else "la isla"])
	QuestManager.report_sail(destination)
	_start_voyage.rpc(destination)


## Todos viajan juntos: cinemática del viaje y, a mitad de camino, cada uno aparece en destino.
@rpc("authority", "call_local", "reliable")
func _start_voyage(destination: String) -> void:
	if Game.dialog_open:
		Game.close_dialog()
	if Cinematics.playing:
		Cinematics.stop()  # Corta cualquier otra cinemática (por ejemplo la de inicio).
	_pending_arrival = destination
	Cinematics.play(_voyage_cinematic(destination))
	if not Cinematics.finished.is_connected(_arrive):
		Cinematics.finished.connect(_arrive, CONNECT_ONE_SHOT)


## Lleva al jugador local al destino del viaje (también si saltea la cinemática).
func _arrive() -> void:
	if _pending_arrival == "":
		return
	var destination := _pending_arrival
	_pending_arrival = ""
	if Game.local_player:
		Game.local_player.respawn(get_spawn_point(multiplayer.get_unique_id(), destination))


func _voyage_cinematic(destination: String) -> Array:
	var stage := VoyageStage.new()
	add_child(stage)
	var up := Vector3.UP
	var island_ship: Vector3 = _ship_site.global_transform * Vector3(0, _ship_y, 6.0)
	var out: Vector3 = _ship_site.global_transform.basis.z  # De la playa hacia el mar.
	out.y = 0.0
	out = out.normalized()
	var out_side := Vector3(out.z, 0, -out.x)
	var harbor_ship: Vector3 = landmarks.get("harbor_ship", Vector3(TerrainGenerator.MAINLAND_CENTER.x, 0, 0))
	var east := Vector3(1, 0, 0)
	var south := Vector3(0, 0, 1)
	var sea_y := TerrainGenerator.WATER_LEVEL - 0.75
	if destination == "mainland":
		var harbor: Vector3 = landmarks.get("harbor", harbor_ship)
		var leave_from := Vector3(island_ship.x, sea_y, island_ship.z)
		var arrive_from := Vector3(harbor_ship.x - 230.0, sea_y, harbor_ship.z)
		var arrive_to := Vector3(harbor_ship.x - 45.0, sea_y, harbor_ship.z)
		return [
			{"card": "Con el Albatros reparado, el grupo zarpó al amanecer, rumbo al este.", "duration": 4.5,
				"callback": stage.sail.bind(leave_from, leave_from + out * 170.0, 17.0)},
			{
				"follow": stage.ship, "from": out_side * -22 + up * 8 - out * 18, "to": out_side * -14 + up * 5 + out * 4,
				"look_from": up * 4, "look_to": up * 4 + out * 6, "duration": 7.0,
				"text": "La isla quedó atrás. En su cima, la luz azul seguía brillando.",
			},
			{
				"follow": stage.ship, "from": out * 34 + up * 14 + out_side * 6, "to": out * 26 + up * 10 + out_side * 3,
				"look_from": up * 5 - out * 30, "duration": 5.5,
				"text": "Nadie supo nunca qué era esa luz. Quizás algún día vuelvan a averiguarlo.",
			},
			{"card": "Tres días de mar abierto después...", "duration": 3.5,
				"callback": _sail_and_arrive.bind(stage, arrive_from, arrive_to, 15.0)},
			{
				"follow": stage.ship, "from": south * 26 + up * 7 - east * 18, "to": south * 12 + up * 5 - east * 12,
				"look_from": up * 4 + east * 40, "duration": 7.0,
				"text": "...apareció la costa de un reino: Valdoria.",
			},
			{
				"from": harbor + Vector3(-70, 34, 50), "to": harbor + Vector3(-40, 20, 34),
				"look_from": harbor + up * 3, "duration": 6.5, "fade_out": true,
				"text": "Puerto Albor. Campanas, gaviotas y olor a pan recién horneado.",
			},
		]
	var back_from := Vector3(island_ship.x, sea_y, island_ship.z) + out * 220.0
	var back_to := back_from - out * 190.0
	return [
		{"card": "El Albatros soltó amarras y puso rumbo a la isla.", "duration": 4.0,
			"callback": _sail_and_arrive.bind(stage, back_from, back_to, 14.0)},
		{
			"follow": stage.ship, "from": out_side * -20 + up * 8 + out * 20, "to": out_side * -14 + up * 5 + out * 6,
			"look_from": up * 4 - out * 30, "duration": 7.0, "fade_out": true,
			"text": "La isla los esperaba, igual que siempre.",
		},
	]


func _sail_and_arrive(stage: VoyageStage, from: Vector3, to: Vector3, duration: float) -> void:
	stage.sail(from, to, duration)
	_arrive()


# --- Comercio (Berta, en Puerto Albor) -----------------------------------------------------

func _server_trade(peer_id: int, kind: String, index: int) -> void:
	var offers: Array = NpcDB.TRADES.get(kind, [])
	var player := _player_node(peer_id)
	if index < 0 or index >= offers.size() or player == null or not landmarks.has("berta_npc"):
		return
	if (player.sync_pos as Vector3).distance_to(landmarks["berta_npc"]) > 10.0:
		return
	var offer: Array = offers[index]
	var item: String = offer[0]
	var amount: int = offer[1]
	var price: int = offer[2]
	var inventory: Inventory = _inventories[peer_id]
	if kind == "buy":
		if not inventory.remove("coin", price):
			_notify_peer(peer_id, "No te alcanza: cuesta %d monedas." % price)
			return
		_give(peer_id, item, amount)
	else:
		if not inventory.remove(item, amount):
			_notify_peer(peer_id, "Te falta: %s x%d" % [ItemDB.item_name(item), amount])
			return
		_give(peer_id, "coin", price)
	_send_inventory(peer_id)
	add_xp(peer_id, SkillDB.XP["trade"])
	if peer_id == multiplayer.get_unique_id():
		_play_trade_sound()
	else:
		_play_trade_sound.rpc_id(peer_id)


@rpc("authority", "reliable")
func _play_trade_sound() -> void:
	Sound.play("pickup")


func build_cinematic(id: String) -> Array:
	var spawn: Vector3 = landmarks["spawn"]
	var monolith: Vector3 = landmarks["monolith"]
	var crystal := monolith + Vector3(0, 8, 0)
	match id:
		"intro":
			return _intro_cinematic()
		"reveal_monolith":
			return [
				{
					"from": crystal + Vector3(-28, 10, 28), "to": crystal + Vector3(28, 6, 28),
					"look_from": crystal,
					"duration": 6.0, "text": "En lo alto de la montaña, una luz antigua despierta...",
				},
			]
		"royal_audience":
			var castle: Vector3 = landmarks.get("castle", spawn)
			var queen: Vector3 = landmarks.get("isolda_npc", castle)
			return [
				{
					"from": queen + (castle - queen).normalized() * -9.0 + Vector3(0, 2.4, 0), "to": queen + (castle - queen).normalized() * -4.0 + Vector3(0, 1.9, 0),
					"look_from": queen + Vector3(0, 1.6, 0), "duration": 6.0,
					"text": "«Llegaron del mar sin nada, y le devolvieron la paz a mi reino.»",
				},
				{
					"from": castle + Vector3(60, 45, 60), "to": castle + Vector3(90, 70, -30),
					"look_from": castle + Vector3(0, 8, 0), "duration": 7.0,
					"text": "«Desde hoy, Valdoria es su hogar. Y sus enemigos, nuestros enemigos.»",
				},
				{"card": "Los náufragos del Albatros se convirtieron en héroes de Valdoria.\n\nPero la luz azul de la isla seguía brillando... y alguien, del otro lado del mar, ya la había visto.", "duration": 8.0},
				{"card": "Continuará...", "duration": 3.5},
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
