class_name IntroStage
extends Node3D
## Escenario temporal de la cinemática de inicio: el Albatros navegando en la tormenta,
## lluvia, rayos y mar picado. Se borra solo cuando termina (o se saltea) la cinemática.

var world: Node
var ship: Node3D
var _rain: CPUParticles3D
var _storming := false
var _time := 0.0
var _next_lightning := 1.5
var _tilt := Vector3.ZERO
var _sail_tween: Tween


func setup(p_world: Node) -> void:
	world = p_world


func _ready() -> void:
	ship = PropFactory.make_ship()
	add_child(ship)
	var start: Vector3 = world.landmarks["ship_start"]
	ship.global_position = Vector3(start.x, TerrainGenerator.WATER_LEVEL - 0.7, start.z)
	ship.rotation.y = world.landmarks["ship_yaw"]

	_rain = CPUParticles3D.new()
	_rain.amount = 1400
	_rain.lifetime = 0.7
	_rain.emitting = false
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22, 0.5, 22)
	_rain.direction = Vector3(0.15, -1, 0)
	_rain.spread = 4.0
	_rain.gravity = Vector3(0, -30, 0)
	_rain.initial_velocity_min = 18.0
	_rain.initial_velocity_max = 24.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.015, 0.55, 0.015)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 0.8, 0.95, 0.35)
	drop.material = material
	_rain.mesh = drop
	add_child(_rain)
	Cinematics.finished.connect(_cleanup, CONNECT_ONE_SHOT)


## Empieza la tormenta y el barco navega hacia los arrecifes durante "duration" segundos.
func begin_storm(duration: float) -> void:
	_storming = true
	_rain.emitting = true
	Sound.set_music("")
	Sound.set_ambience("rain", 1.3)
	Sound.set_ambience("waves", 1.4)
	Sound.set_ambience("wind", 1.3)
	world.day_night.override_time = 0.96
	world.day_night.storm = 1.0
	world.set_wave_height(0.9)
	var reef: Vector3 = world.landmarks["reef"]
	_sail_tween = create_tween()
	_sail_tween.tween_property(ship, "global_position", Vector3(reef.x, ship.global_position.y, reef.z), duration)


func set_storm(amount: float) -> void:
	world.day_night.storm = amount


## Choque contra las rocas: el barco se clava y se inclina.
func crash() -> void:
	if _sail_tween:
		_sail_tween.kill()
	Cinematics.flash(1.0)
	Cinematics.shake(1.0)
	Sound.play("thunder", Vector3.INF, 2.0, 0.0)
	Sound.play("hit", Vector3.INF, 4.0, 0.0)
	var forward := Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	var tween := create_tween().set_parallel()
	tween.tween_property(ship, "global_position", ship.global_position + forward * 5.0 + Vector3(0, -1.2, 0), 1.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_tilt", Vector3(-0.22, 0, 0.5), 1.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Fin de la tormenta: amanece y el mar se calma.
func end_storm() -> void:
	_storming = false
	_rain.emitting = false
	ship.visible = false
	Sound.set_ambience("rain", 0.0)
	Sound.set_ambience("wind", 0.3)
	Sound.set_ambience("waves", 0.8)
	Sound.set_music("menu")
	world.day_night.storm = 0.0
	world.day_night.override_time = 0.36
	world.set_wave_height(0.08)


func _process(delta: float) -> void:
	_time += delta
	# El barco se mece con las olas.
	if ship.visible:
		var rock := 1.0 if _storming else 0.2
		ship.rotation.x = sin(_time * 0.9) * 0.09 * rock + _tilt.x
		ship.rotation.z = sin(_time * 0.7 + 1.0) * 0.12 * rock + _tilt.z
	# La lluvia sigue a la cámara.
	var camera := Cinematics.get_camera()
	if camera:
		_rain.global_position = camera.global_position + Vector3(0, 7, 0)
	# Rayos al azar.
	if _storming:
		_next_lightning -= delta
		if _next_lightning <= 0.0:
			_next_lightning = randf_range(1.8, 4.5)
			Cinematics.flash(randf_range(0.4, 0.8))
			Sound.play("thunder", Vector3.INF, -3.0, 0.1)


func _cleanup() -> void:
	world.day_night.override_time = -1.0
	world.day_night.storm = 0.0
	world.set_wave_height(0.08)
	queue_free()
