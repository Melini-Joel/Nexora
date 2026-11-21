class_name MenuBackdrop
extends Node3D
## Fondo animado del menú principal: una isla generada al azar al atardecer, la cámara
## girando despacio alrededor de una fogata con personajes calentándose las manos,
## un lobo, luciérnagas, pasto con viento y el cielo cambiando de color.
## Se borra en cuanto empieza la partida.

const TREE_COUNT := 420

var _camera: Camera3D
var _day_night: DayNight
var _terrain: TerrainGenerator
var _focus := Vector3.ZERO
var _time := 0.0


func _ready() -> void:
	var world_seed := randi()
	_build_environment()
	_terrain = TerrainGenerator.new()
	add_child(_terrain)
	_terrain.generate(world_seed)
	_build_water()
	_focus = Vector3(0, _terrain.get_height(0, 0), 0)
	_build_camp()
	_scatter_trees(world_seed)
	if DisplayServer.get_name() != "headless":
		var grass := GrassField.new()
		add_child(grass)
		grass.setup(_terrain, world_seed)
	_build_fireflies()
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.make_current()
	_process(0.0)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.06
	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = Settings.get_value("quality") != "low"
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	_day_night = DayNight.new()
	add_child(_day_night)
	_day_night.setup(sun, moon, env, sky_material)
	_day_night.set_process(false)  # La hora la controla el menú.


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * TerrainGenerator.SIZE * 6.0
	plane.subdivide_width = 120
	plane.subdivide_depth = 120
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	plane.material = mat
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position.y = TerrainGenerator.WATER_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


## Fogata con tres personajes calentándose las manos y un lobo echado al lado.
func _build_camp() -> void:
	var campfire := PropFactory.make_campfire()
	campfire.position = _focus
	add_child(campfire)
	var looks := [
		Humanoid.look_for_player(2024), NpcDB.get_npc("tomas")["look"], Humanoid.look_for_player(77),
	]
	for i in looks.size():
		var angle := TAU * i / 3.0 + 0.4
		var person := Humanoid.new()
		person.build(looks[i])
		var pos := _focus + Vector3(cos(angle), 0, sin(angle)) * 2.1
		pos.y = _terrain.get_height(pos.x, pos.z)
		person.position = pos
		var to_fire := _focus - pos
		person.rotation.y = atan2(-to_fire.x, -to_fire.z)
		person.busy = true  # Manos hacia el fuego.
		add_child(person)
	var wolf := Quadruped.new()
	wolf.build(CreatureDB.get_species("wolf")["look"])
	var wolf_pos := _focus + Vector3(cos(4.6), 0, sin(4.6)) * 2.6
	wolf_pos.y = _terrain.get_height(wolf_pos.x, wolf_pos.z)
	wolf.position = wolf_pos
	wolf.rotation.y = 1.2
	add_child(wolf)


func _scatter_trees(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var placed := 0
	for attempt in TREE_COUNT * 4:
		if placed >= TREE_COUNT:
			break
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(11.0, 190.0)
		var p := Vector2(cos(angle), sin(angle)) * distance
		var h := _terrain.get_height(p.x, p.y)
		if h < TerrainGenerator.WATER_LEVEL + 1.0 or _terrain.get_slope(p.x, p.y) > 0.35:
			continue
		var kind := ""
		match _terrain.get_biome(p.x, p.y):
			"forest":
				kind = "pine" if rng.randf() < 0.7 else "round"
			"tundra":
				kind = "snow_pine"
			"meadow":
				kind = "round" if rng.randf() < 0.65 else "pine"
		var node: Node3D
		if kind == "":
			node = PropFactory.make_cactus(rng)
		else:
			node = PropFactory.make_tree(rng, kind)
		node.position = Vector3(p.x, h - 0.1, p.y)
		node.rotation.y = rng.randf() * TAU
		add_child(node)
		placed += 1


## Luciérnagas: puntitos de luz que flotan alrededor del campamento.
func _build_fireflies() -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 70
	particles.lifetime = 7.0
	particles.preprocess = 7.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(14, 1.5, 14)
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.1
	particles.initial_velocity_max = 0.4
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = PropFactory.material(Color(1.0, 0.85, 0.4), 8.0)
	particles.mesh = mesh
	particles.position = _focus + Vector3(0, 1.8, 0)
	add_child(particles)


func _process(delta: float) -> void:
	_time += delta
	# Cámara: gira despacio alrededor de la fogata, acercándose y alejándose.
	var angle := _time * 0.05 + 0.8
	var radius := 12.0 + sin(_time * 0.09) * 3.5
	var pos := _focus + Vector3(cos(angle), 0, sin(angle)) * radius
	pos.y = maxf(_terrain.get_height(pos.x, pos.z) + 1.6, _focus.y + 3.2 + sin(_time * 0.12) * 1.2)
	_camera.global_position = pos
	_camera.look_at(_focus + Vector3(0, 1.4, 0))
	# Cielo: va y viene entre el atardecer y el anochecer.
	_day_night.set_time(0.748 + sin(_time * 0.045) * 0.032, 1)
