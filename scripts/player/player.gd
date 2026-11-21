extends CharacterBody3D
## Jugador en tercera persona. Cada cliente controla su propio personaje (autoridad = su peer id)
## y el MultiplayerSynchronizer replica posición, rotación, objeto en la mano y carga.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const ACCELERATION := 12.0
const JUMP_VELOCITY := 5.5
const INTERACT_DISTANCE := 3.5
const GATHER_COOLDOWN := 0.5
const RAY_MASK := 1 | ItemDrop.PICKUP_LAYER

var player_name := "Jugador":
	set(value):
		player_name = value
		if _name_label:
			_name_label.text = value
var sync_pos := Vector3.ZERO  ## Posición replicada (la escribe el dueño).
var sync_rot := 0.0  ## Rotación del modelo replicada.
var selected_slot := 0  ## Casillero de la barra rápida elegido (el servidor lo usa para saber la herramienta).
var held_item := "":  ## Objeto en la mano (para que todos lo vean).
	set(value):
		if value == held_item:
			return
		held_item = value
		_rebuild_held_model()
var load_ratio := 0.0:  ## Qué tan llena está la mochila (0 = vacía, 1 = al límite).
	set(value):
		load_ratio = value
		_update_backpack()
var grounded := true  ## Para animar el salto de los compañeros.
var busy := false  ## Fabricando algo (anima las manos).

var camera: Camera3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _world: Node
var _name_label: Label3D
var _hand: Node3D
var _body: Humanoid
var _last_remote_y := 0.0
var _backpack: MeshInstance3D
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _focused: Node = null
var _hint_text := ""
var _gather_cooldown := 0.0

@onready var model: Node3D = $Model


func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	if sync_pos == Vector3.ZERO:
		sync_pos = position
	_build_body()
	_rebuild_held_model()
	_update_backpack()
	if is_multiplayer_authority():
		_build_camera()
		_name_label.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.local_player = self
		Game.local_player_spawned.emit(self)


func _exit_tree() -> void:
	if is_multiplayer_authority() and Game.local_player == self:
		Game.local_player = null


# --- Construcción del personaje -------------------------------------------------------

func _build_body() -> void:
	var peer_id := str(name).to_int()
	var look := Humanoid.look_for_player(peer_id)
	_body = Humanoid.new()
	_body.build(look)
	model.add_child(_body)
	_hand = _body.hand_attach
	_backpack = _mesh_part(_box(Vector3(0.36, 0.42, 0.2)), Color(0.45, 0.32, 0.2), Vector3.ZERO, _body.back_attach)
	_mesh_part(_box(Vector3(0.3, 0.12, 0.06)), Color(0.38, 0.27, 0.17), Vector3(0, -0.12, 0.1), _backpack)

	_name_label = Label3D.new()
	_name_label.text = player_name
	_name_label.position = Vector3(0, 2.2, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 40
	_name_label.outline_size = 10
	_name_label.pixel_size = 0.006
	_name_label.modulate = (look["shirt"] as Color).lightened(0.45)
	add_child(_name_label)


## Modelo del objeto que tiene en la mano: hacha, pico, antorcha, un recurso o nada.
## Con el brazo colgando, el mango apunta hacia adelante (-Z) y la cabeza hacia arriba.
func _rebuild_held_model() -> void:
	if _hand == null:
		return
	for child in _hand.get_children():
		child.queue_free()
	if _body:
		_body.holding_item = held_item != ""
	var handle := Color(0.45, 0.3, 0.18)
	var head_color := ItemDB.color(held_item)
	match ItemDB.icon(held_item):
		"hatchet":
			_mesh_part(_box(Vector3(0.045, 0.045, 0.62)), handle, Vector3(0, 0, -0.22), _hand)
			_mesh_part(_box(Vector3(0.04, 0.24, 0.16)), head_color, Vector3(0, 0.08, -0.48), _hand)
		"pickaxe":
			_mesh_part(_box(Vector3(0.045, 0.045, 0.66)), handle, Vector3(0, 0, -0.24), _hand)
			_mesh_part(_box(Vector3(0.05, 0.46, 0.06)), head_color, Vector3(0, 0.02, -0.52), _hand)
		"torch":
			var stick := _mesh_part(_box(Vector3(0.045, 0.045, 0.5)), handle, Vector3(0, 0.12, -0.16), _hand)
			stick.rotation.x = 0.9
			var flame := _mesh_part(PropFactory.cone_mesh(0.07, 0.2, PropFactory.FIRE), PropFactory.FIRE, Vector3(0, 0.34, -0.33), _hand)
			flame.material_override = PropFactory.material(PropFactory.FIRE, 3.0)
			var light := OmniLight3D.new()
			light.light_color = PropFactory.FIRE
			light.light_energy = 1.6
			light.omni_range = 9.0
			light.position = Vector3(0, 0.45, -0.35)
			_hand.add_child(light)
		"":
			pass
		_:
			_mesh_part(_box(Vector3(0.16, 0.16, 0.16)), head_color, Vector3(0, -0.02, -0.08), _hand)


## La mochila crece a medida que se llena.
func _update_backpack() -> void:
	if _backpack == null:
		return
	var fill := clampf(load_ratio, 0.0, 1.3)
	_backpack.scale = Vector3(1.0 + fill * 0.25, 1.0 + fill * 0.5, 1.0 + fill * 1.0)
	_backpack.position = Vector3(0, fill * 0.06, fill * 0.1)
	if _body:
		_body.load_ratio = load_ratio


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
	_spring_arm.margin = 0.2
	_spring_arm.rotation.x = -0.3
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	_spring_arm.shape = shape
	_spring_arm.add_excluded_object(get_rid())
	_camera_pivot.add_child(_spring_arm)

	camera = Camera3D.new()
	_spring_arm.add_child(camera)
	camera.make_current()
	_apply_camera_settings()
	Settings.changed.connect(_apply_camera_settings)


## Aplica las opciones de cámara (distancia, altura, hombro, FOV) del menú de Opciones.
func _apply_camera_settings() -> void:
	_camera_pivot.position.y = Settings.get_value("camera_height")
	_spring_arm.spring_length = Settings.get_value("camera_distance")
	_spring_arm.position.x = Settings.get_value("camera_shoulder")
	camera.fov = Settings.get_value("fov")


# --- Entrada ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or Cinematics.playing:
		return
	if event.is_action_pressed("pause"):
		if Game.inventory_open:
			Game.set_inventory_open(false)
		else:
			Game.set_pause_open(not Game.ui_open)
		get_viewport().set_input_as_handled()
		return
	if Game.ui_open:
		return
	if event.is_action_pressed("inventory"):
		Game.set_inventory_open(not Game.inventory_open)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("camera_toggle"):
		Game.notify.emit("Cámara: %s" % Settings.cycle_camera_distance())
		return
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Game.select_slot(i)
			return
	if Game.inventory_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := Settings.mouse_sensitivity()
		var vertical: float = event.relative.y * (-1.0 if Settings.get_value("invert_y") else 1.0)
		_camera_pivot.rotation.y -= event.relative.x * sensitivity
		_spring_arm.rotation.x = clampf(_spring_arm.rotation.x - vertical * sensitivity, -1.2, 0.45)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			Game.select_slot(Game.selected_slot - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Game.select_slot(Game.selected_slot + 1)


# --- Movimiento ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_update_remote(delta)
		return
	if _world == null or not _world.generated:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	var overloaded := Game.is_overloaded()
	var input_dir := Vector2.ZERO
	var can_move := Game.can_control_player()
	if can_move:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY * (0.6 if overloaded else 1.0)

	var direction := _camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized() * minf(input_dir.length(), 1.0)
	var sprinting := can_move and not overloaded and Input.is_action_pressed("sprint")
	# Cuanto más pesa la mochila, más lento.
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * Game.speed_multiplier()
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

	_animate(Vector2(velocity.x, velocity.z).length(), is_on_floor(), velocity.y)
	_sync_local_state()
	_update_focus()
	_handle_actions(delta)


## Copia el estado local (posición, barra rápida, carga) a las variables replicadas.
func _sync_local_state() -> void:
	sync_pos = global_position
	sync_rot = model.rotation.y
	selected_slot = Game.selected_slot
	held_item = Game.get_selected_item()
	grounded = is_on_floor()
	busy = not Game.craft_queue.is_empty()
	var ratio := snappedf(Game.load_ratio(), 0.05)
	if not is_equal_approx(ratio, load_ratio):
		load_ratio = ratio


func _update_remote(delta: float) -> void:
	var previous := global_position
	if global_position.distance_to(sync_pos) > 8.0:
		global_position = sync_pos  # Teletransporte (respawn, lag grande).
	else:
		global_position = global_position.lerp(sync_pos, clampf(delta * 12.0, 0.0, 1.0))
	model.rotation.y = lerp_angle(model.rotation.y, sync_rot, clampf(delta * 12.0, 0.0, 1.0))
	var moved := global_position - previous
	var vertical := (sync_pos.y - _last_remote_y) / maxf(delta, 0.0001)
	_last_remote_y = sync_pos.y
	_animate(Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001), grounded, vertical)


## Le pasa al cuerpo los datos para animarse (caminar, correr, saltar...).
func _animate(horizontal_speed: float, on_floor: bool, vertical_speed: float) -> void:
	_body.move_speed = horizontal_speed
	_body.grounded = on_floor
	_body.vertical_speed = vertical_speed
	_body.busy = busy


# --- Interacción y recolección ---------------------------------------------------------

func _update_focus() -> void:
	var new_focus: Node = null
	if Game.can_act():
		var from := camera.global_position
		var forward := -camera.global_transform.basis.z
		var to := from + forward * (_spring_arm.get_hit_length() + INTERACT_DISTANCE + 1.0)
		var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			var collider: Object = hit["collider"]
			var hit_pos: Vector3 = hit["position"]
			var in_range := hit_pos.distance_to(global_position + Vector3.UP) <= INTERACT_DISTANCE
			if in_range and (collider is ItemDrop or collider is NPC or (collider is ResourceNode and not collider.depleted)):
				new_focus = collider
	_focused = new_focus
	var text := _hint_for(_focused)
	if text != _hint_text:
		_hint_text = text
		Game.interaction_hint_changed.emit(text)


func _hint_for(target: Node) -> String:
	if target is ItemDrop or target is NPC:
		return "[E] %s" % target.get_interact_text()
	if target is ResourceNode:
		var text := "[Click] %s" % target.get_interact_text()
		if target.preferred_tool == "":
			return text
		var tool_name: String = ItemDB.TOOL_NAMES.get(target.preferred_tool, "")
		if ItemDB.tool_type(held_item) == target.preferred_tool:
			text += "   (%s x%d)" % [tool_name, ItemDB.tool_power(held_item)]
		else:
			text += "   (con un %s sacás más)" % tool_name
		return text
	return ""


func _handle_actions(delta: float) -> void:
	_gather_cooldown -= delta
	if _focused == null or not Game.can_act():
		return
	if _focused is NPC:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack"):
			Game.send_action("talk", [_focused.npc_id])
			Game.open_dialog(_focused.npc_id)
		return
	if _focused is ItemDrop:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack"):
			Game.send_action("pickup", [str(_focused.name)])
		return
	# Recurso: mantener click (o E) para golpear.
	if _gather_cooldown > 0.0 or not (Input.is_action_pressed("attack") or Input.is_action_pressed("interact")):
		return
	_gather_cooldown = GATHER_COOLDOWN
	var to_target: Vector3 = _focused.global_position - global_position
	model.rotation.y = atan2(-to_target.x, -to_target.z)
	sync_rot = model.rotation.y
	play_swing.rpc()
	Game.send_action("gather", [str(_focused.name)])


@rpc("authority", "call_local", "unreliable")
func play_swing() -> void:
	_body.play_swing()
