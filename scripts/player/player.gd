extends CharacterBody3D
## Jugador en tercera persona. Cada cliente controla su propio personaje (autoridad = su peer id)
## y el MultiplayerSynchronizer replica posición y rotación al resto, que las interpola.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const ACCELERATION := 12.0
const JUMP_VELOCITY := 5.5
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_DISTANCE := 3.5
const GATHER_COOLDOWN := 0.5
const HAND_REST := -0.6

var player_name := "Jugador":
	set(value):
		player_name = value
		if _name_label:
			_name_label.text = value
var sync_pos := Vector3.ZERO  ## Posición replicada (la escribe el dueño).
var sync_rot := 0.0  ## Rotación del modelo replicada.

var camera: Camera3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _world: Node
var _name_label: Label3D
var _hand: Node3D
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _focused: ResourceNode = null
var _hint_text := ""
var _gather_cooldown := 0.0
var _anim_time := 0.0

@onready var model: Node3D = $Model


func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	if sync_pos == Vector3.ZERO:
		sync_pos = position
	_build_body()
	if is_multiplayer_authority():
		_build_camera()
		_name_label.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.local_player = self
		Game.local_player_spawned.emit(self)


func _exit_tree() -> void:
	if is_multiplayer_authority() and Game.local_player == self:
		Game.local_player = null


# --- Construcción del personaje (low-poly por código) ------------------------------

func _build_body() -> void:
	var peer_id := str(name).to_int()
	var color := Color.from_hsv(fmod(peer_id * 0.618034, 1.0), 0.55, 0.9)
	var body := _mesh_part(_capsule(0.32, 1.1), color, Vector3(0, 0.75, 0))
	body.name = "Body"
	_mesh_part(_sphere(0.26), Color(0.96, 0.8, 0.65), Vector3(0, 1.55, 0))
	_mesh_part(_box(Vector3(0.06, 0.08, 0.02)), Color(0.1, 0.1, 0.12), Vector3(-0.09, 1.58, -0.245))
	_mesh_part(_box(Vector3(0.06, 0.08, 0.02)), Color(0.1, 0.1, 0.12), Vector3(0.09, 1.58, -0.245))
	_mesh_part(_box(Vector3(0.42, 0.45, 0.2)), Color(0.45, 0.32, 0.2), Vector3(0, 0.95, 0.3))

	# Mano con herramienta (hacha/pico simple).
	_hand = Node3D.new()
	_hand.position = Vector3(0.4, 1.0, -0.1)
	_hand.rotation.x = HAND_REST
	model.add_child(_hand)
	_mesh_part(_box(Vector3(0.06, 0.06, 0.7)), Color(0.45, 0.3, 0.18), Vector3(0, 0, -0.3), _hand)
	_mesh_part(_box(Vector3(0.08, 0.26, 0.16)), Color(0.6, 0.6, 0.62), Vector3(0, 0.08, -0.6), _hand)

	_name_label = Label3D.new()
	_name_label.text = player_name
	_name_label.position = Vector3(0, 2.15, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 40
	_name_label.outline_size = 10
	_name_label.pixel_size = 0.006
	_name_label.modulate = color.lightened(0.4)
	add_child(_name_label)


func _mesh_part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PropFactory.material(color)
	mi.position = pos
	(parent if parent else model).add_child(mi)
	return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 8
	m.rings = 2
	return m


func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 5
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.position = Vector3(0, 1.6, 0)
	add_child(_camera_pivot)

	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = 4.5
	_spring_arm.margin = 0.2
	_spring_arm.position = Vector3(0.5, 0, 0)  # Cámara apenas sobre el hombro.
	_spring_arm.rotation.x = -0.3
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	_spring_arm.shape = shape
	_spring_arm.add_excluded_object(get_rid())
	_camera_pivot.add_child(_spring_arm)

	camera = Camera3D.new()
	camera.fov = 70.0
	_spring_arm.add_child(camera)
	camera.make_current()


# --- Entrada ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or Cinematics.playing:
		return
	if event.is_action_pressed("pause"):
		Game.set_pause_open(not Game.ui_open)
		get_viewport().set_input_as_handled()
	elif Game.ui_open:
		return
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_pivot.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_spring_arm.rotation.x = clampf(_spring_arm.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Movimiento ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_update_remote(delta)
		return
	if _world == null or not _world.generated:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Vector2.ZERO
	var can_move := Game.can_control_player()
	if can_move:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

	var direction := _camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized() * minf(input_dir.length(), 1.0)
	var speed := SPRINT_SPEED if can_move and Input.is_action_pressed("sprint") else WALK_SPEED
	if global_position.y < TerrainGenerator.WATER_LEVEL - 0.6:
		speed *= 0.5  # Más lento en el agua.
	var weight := clampf(ACCELERATION * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)
	move_and_slide()

	if direction.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-direction.x, -direction.z), clampf(delta * 12.0, 0.0, 1.0))
	if global_position.y < -25.0:
		global_position = _world.get_spawn_point(str(name).to_int())
		velocity = Vector3.ZERO

	_animate(delta, Vector2(velocity.x, velocity.z).length(), is_on_floor())
	sync_pos = global_position
	sync_rot = model.rotation.y

	_update_focus()
	_handle_gather(delta)


func _update_remote(delta: float) -> void:
	var previous := global_position
	if global_position.distance_to(sync_pos) > 8.0:
		global_position = sync_pos  # Teletransporte (respawn, lag grande).
	else:
		global_position = global_position.lerp(sync_pos, clampf(delta * 12.0, 0.0, 1.0))
	model.rotation.y = lerp_angle(model.rotation.y, sync_rot, clampf(delta * 12.0, 0.0, 1.0))
	var moved := global_position - previous
	_animate(delta, Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001), true)


func _animate(delta: float, horizontal_speed: float, grounded: bool) -> void:
	if horizontal_speed > 0.5 and grounded:
		_anim_time += delta * horizontal_speed * 2.2
		model.position.y = absf(sin(_anim_time)) * 0.08
	else:
		model.position.y = lerpf(model.position.y, 0.0, clampf(delta * 10.0, 0.0, 1.0))


# --- Interacción y recolección ---------------------------------------------------------

func _update_focus() -> void:
	var new_focus: ResourceNode = null
	if Game.can_control_player():
		var from := camera.global_position
		var forward := -camera.global_transform.basis.z
		var to := from + forward * (_spring_arm.get_hit_length() + INTERACT_DISTANCE + 1.0)
		var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit and hit["collider"] is ResourceNode and not hit["collider"].depleted:
			var hit_pos: Vector3 = hit["position"]
			if hit_pos.distance_to(global_position + Vector3.UP) <= INTERACT_DISTANCE:
				new_focus = hit["collider"]
	_focused = new_focus
	var text := "[E / Click] %s" % _focused.get_interact_text() if _focused else ""
	if text != _hint_text:
		_hint_text = text
		Game.interaction_hint_changed.emit(text)


func _handle_gather(delta: float) -> void:
	_gather_cooldown -= delta
	if _focused == null or _gather_cooldown > 0.0 or not Input.is_action_pressed("interact"):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_gather_cooldown = GATHER_COOLDOWN
	var to_target := _focused.global_position - global_position
	model.rotation.y = atan2(-to_target.x, -to_target.z)
	sync_rot = model.rotation.y
	play_swing.rpc()
	_world.gather(str(_focused.name))


@rpc("authority", "call_local", "unreliable")
func play_swing() -> void:
	var tween := create_tween()
	tween.tween_property(_hand, "rotation:x", 1.3, 0.12)
	tween.tween_property(_hand, "rotation:x", -0.5, 0.1)
	tween.tween_property(_hand, "rotation:x", HAND_REST, 0.2)
