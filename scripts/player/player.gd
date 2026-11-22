extends CharacterBody3D
## Jugador en tercera persona. Cada cliente controla su propio personaje (autoridad = su peer id)
## y el MultiplayerSynchronizer replica posición, rotación, objeto en la mano y animación.
##
## Click izquierdo según lo que tengas en la mano y a lo que apuntes:
##   recurso → recolectar · criatura → atacar · comida → comer · plano → aprenderlo
##   martillo → construir (R cambia de pieza, click derecho desarma)
## E: hablar, recoger, usar estaciones, abrir cofres y puertas, domesticar / dar órdenes a mascotas.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const ACCELERATION := 12.0
const JUMP_VELOCITY := 5.5
const INTERACT_DISTANCE := 3.6
const GATHER_COOLDOWN := 0.5
const RAY_MASK := 1 | ItemDrop.PICKUP_LAYER
const SPRINT_COST := 8.0  ## Energía por segundo al correr.
const JUMP_COST := 6.0
const ATTACK_COST := 4.0
const STAMINA_REGEN := 30.0

var player_name := "Jugador":
	set(value):
		player_name = value
		if _name_label:
			_name_label.text = value
var sync_pos := Vector3.ZERO  ## Posición replicada (la escribe el dueño).
var sync_rot := 0.0  ## Rotación del modelo replicada.
var selected_slot := 0  ## Casillero de la barra rápida elegido (el servidor lo usa para saber qué tenés en la mano).
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
var _backpack: MeshInstance3D
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _focused: Node = null
var _focus_point := Vector3.ZERO
var _hint_text := ""
var _action_cooldown := 0.0
var _stamina_delay := 0.0
var _last_remote_y := 0.0
var _shake := 0.0
# Construcción
var _build_index := 0
var _ghost: MeshInstance3D
var _ghost_piece := ""
var _placement: Dictionary = {}

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
		Game.player_hit.connect(func(_amount: float): _shake = 0.35)
		Game.local_player_spawned.emit(self)


func _exit_tree() -> void:
	if is_multiplayer_authority() and Game.local_player == self:
		Game.local_player = null


## Reaparecer después de morir (lo llama el servidor).
func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	Game.stamina = Game.max_stamina()


# --- Construcción del personaje -------------------------------------------------------

func _build_body() -> void:
	var peer_id := str(name).to_int()
	var look := Humanoid.look_for_player(peer_id)
	_body = Humanoid.new()
	_body.build(look)
	model.add_child(_body)
	_body.step.connect(func(): Sound.play("step", global_position, -14.0 if _body.move_speed < 6.0 else -9.0, 0.15))
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


## Modelo del objeto que tiene en la mano. Con el brazo colgando, el mango apunta hacia
## adelante (-Z) y la cabeza de la herramienta hacia arriba.
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
		"hammer":
			_mesh_part(_box(Vector3(0.045, 0.045, 0.5)), handle, Vector3(0, 0, -0.18), _hand)
			_mesh_part(_box(Vector3(0.09, 0.22, 0.12)), head_color, Vector3(0, 0.0, -0.42), _hand)
		"club":
			_mesh_part(Humanoid._cylinder(0.08, 0.035, 0.75), head_color, Vector3(0, 0, -0.3), _hand).rotation.x = PI / 2
		"spear":
			_mesh_part(_box(Vector3(0.04, 0.04, 1.6)), handle, Vector3(0, 0, -0.45), _hand)
			_mesh_part(Humanoid._cylinder(0.0, 0.05, 0.25), head_color, Vector3(0, 0, -1.35), _hand).rotation.x = -PI / 2
		"sword":
			_mesh_part(_box(Vector3(0.04, 0.04, 0.18)), handle, Vector3(0, 0, -0.02), _hand)
			_mesh_part(_box(Vector3(0.2, 0.04, 0.04)), Color(0.4, 0.35, 0.2), Vector3(0, 0, -0.12), _hand)
			_mesh_part(_box(Vector3(0.07, 0.015, 0.75)), head_color, Vector3(0, 0, -0.5), _hand)
		"torch":
			var stick := _mesh_part(_box(Vector3(0.045, 0.045, 0.5)), handle, Vector3(0, 0.12, -0.16), _hand)
			stick.rotation.x = 0.9
			var flame := _mesh_part(PropFactory.cone_mesh(0.07, 0.2, PropFactory.FIRE), PropFactory.FIRE, Vector3(0, 0.34, -0.33), _hand)
			flame.material_override = PropFactory.material(PropFactory.FIRE, 3.0)
			var light := OmniLight3D.new()
			light.light_color = PropFactory.FIRE
			light.light_energy = 2.0
			light.omni_range = 12.0
			light.shadow_enabled = true
			light.position = Vector3(0, 0.45, -0.35)
			_hand.add_child(light)
		"":
			pass
		_:
			_mesh_part(_box(Vector3(0.14, 0.14, 0.14)), head_color, Vector3(0, -0.02, -0.08), _hand)


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
	camera.far = 900.0
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
	if event.is_action_pressed("character") and not Game.ui_open and not Game.dialog_open:
		Game.set_character_open(not Game.character_open)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") and not Game.ui_open and not Game.dialog_open:
		Game.set_map_open(not Game.map_open)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if Game.character_open:
			Game.set_character_open(false)
		elif Game.map_open:
			Game.set_map_open(false)
		elif Game.inventory_open:
			Game.set_inventory_open(false)
		else:
			Game.set_pause_open(not Game.ui_open)
		get_viewport().set_input_as_handled()
		return
	if Game.ui_open or Game.dialog_open:
		return
	if event.is_action_pressed("inventory"):
		Game.set_inventory_open(not Game.inventory_open)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("camera_toggle"):
		Game.notify.emit("Cámara: %s" % Settings.cycle_camera_distance())
		return
	if event.is_action_pressed("build_rotate") and held_item == "hammer":
		_cycle_build_piece()
		return
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Game.select_slot(i)
			return
	if Game.inventory_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative, Settings.mouse_sensitivity())
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Settings.touch_enabled():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			Game.select_slot(Game.selected_slot - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Game.select_slot(Game.selected_slot + 1)


## Gira la cámara (mouse o dedo deslizándose en la pantalla).
func apply_look(relative: Vector2, sensitivity: float) -> void:
	var vertical: float = relative.y * (-1.0 if Settings.get_value("invert_y") else 1.0)
	_camera_pivot.rotation.y -= relative.x * sensitivity
	_spring_arm.rotation.x = clampf(_spring_arm.rotation.x - vertical * sensitivity, -1.2, 0.45)


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
		if Input.is_action_just_pressed("jump") and is_on_floor() and Game.stamina >= JUMP_COST:
			velocity.y = JUMP_VELOCITY * (0.6 if overloaded else 1.0)
			_use_stamina(JUMP_COST)

	var direction := _camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized() * minf(input_dir.length(), 1.0)
	var sprinting := can_move and not overloaded and Input.is_action_pressed("sprint") \
		and direction.length() > 0.1 and Game.stamina > 1.0
	if sprinting:
		_use_stamina(SPRINT_COST * delta)
	_regen_stamina(delta)
	# Cuanto más pesa la mochila, más lento. Con hambre extrema, también.
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * Game.speed_multiplier() * SkillDB.speed_multiplier(Game.progress)
	if Game.hunger <= 0.0:
		speed *= 0.8
	if global_position.y < TerrainGenerator.WATER_LEVEL - 0.6:
		speed *= 0.5  # Más lento en el agua.
	var weight := clampf(ACCELERATION * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)
	move_and_slide()

	if direction.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-direction.x, -direction.z), clampf(delta * 12.0, 0.0, 1.0))
	if global_position.y < -25.0:
		global_position = _world.get_spawn_point(str(name).to_int(), _world.region_near(global_position))
		velocity = Vector3.ZERO

	_animate(Vector2(velocity.x, velocity.z).length(), is_on_floor(), velocity.y)
	_sync_local_state()
	_update_focus()
	_update_build_ghost()
	_handle_actions(delta)
	_update_camera_shake(delta)


func _use_stamina(amount: float) -> void:
	Game.stamina = maxf(0.0, Game.stamina - amount)
	_stamina_delay = 0.6


func _regen_stamina(delta: float) -> void:
	_stamina_delay -= delta
	if _stamina_delay <= 0.0:
		var regen := STAMINA_REGEN * SkillDB.stamina_regen_multiplier(Game.progress) * (0.5 if Game.hunger < 15.0 else 1.0)
		Game.stamina = minf(Game.max_stamina(), Game.stamina + regen * delta)


func _update_camera_shake(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta)
	camera.h_offset = randf_range(-1, 1) * _shake * 0.3
	camera.v_offset = randf_range(-1, 1) * _shake * 0.3


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


# --- Interacción -----------------------------------------------------------------------

func _update_focus() -> void:
	var new_focus: Node = null
	if Game.can_act():
		var from := camera.global_position
		var forward := -camera.global_transform.basis.z
		var to := from + forward * (_spring_arm.get_hit_length() + 5.0)
		var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			var collider: Object = hit["collider"]
			_focus_point = hit["position"]
			if collider is CollisionObject3D and not (collider is BuildPiece or collider is Station or collider is LootChest
					or collider is NPC or collider is ItemDrop or collider is ResourceNode or collider is Creature or collider is Interactable):
				var parent: Node = collider.get_parent()
				if parent is BuildPiece or parent is Station:
					collider = parent
			var reach := INTERACT_DISTANCE
			if collider is Creature:
				reach = maxf(INTERACT_DISTANCE, ItemDB.attack_range(held_item) + 0.8)
			if _focus_point.distance_to(global_position + Vector3.UP) <= reach and _is_interesting(collider):
				new_focus = collider
	_focused = new_focus
	var text := _hint_for(_focused)
	if text != _hint_text:
		_hint_text = text
		Game.interaction_hint_changed.emit(text)


func _is_interesting(target: Object) -> bool:
	if target is ResourceNode:
		return not target.depleted
	if target is Creature:
		return not target.dead
	if target is LootChest:
		return not target.opened
	return target is ItemDrop or target is NPC or target is Station or target is BuildPiece or target is Interactable


func _hint_for(target: Node) -> String:
	if target == null:
		return ""
	if target is ItemDrop or target is NPC or target is Station or target is LootChest or target is Interactable:
		return "[E] %s" % target.get_interact_text()
	if target is BuildPiece:
		var lines: Array[String] = []
		if target.get_interact_text() != "":
			lines.append("[E] %s" % target.get_interact_text())
		if held_item == "hammer":
			lines.append("[Click der.] Desarmar (devuelve la mitad)")
		return "   ".join(lines)
	if target is Creature:
		var lines: Array[String] = []
		var interact: String = target.get_interact_text()
		if target.tamed_owner != "":
			if target.tamed_owner == player_name:
				lines.append("[E] %s" % interact)
			return "   ".join(lines)
		lines.append("[Click] Atacar %s" % CreatureDB.display_name(target.species))
		if interact != "" and target.is_tameable_with(held_item):
			lines.append("[E] %s" % interact)
		elif interact != "":
			lines.append("(%s)" % interact)
		return "   ".join(lines)
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
	_action_cooldown -= delta
	if not Game.can_act():
		return
	var interact := Input.is_action_just_pressed("interact")
	var click := Input.is_action_pressed("attack")
	var click_once := Input.is_action_just_pressed("attack")
	var right_click := Input.is_action_just_pressed("secondary")

	# E: interactuar
	if interact and _focused != null:
		if _focused is NPC:
			Game.send_action("talk", [_focused.npc_id])
			Game.open_dialog(_focused.npc_id)
		elif _focused is Interactable:
			Game.open_dialog(_focused.dialog_id)
		elif _focused is ItemDrop:
			Game.send_action("pickup", [str(_focused.name)])
		elif _focused is Station:
			Game.open_station(_focused.station_type)
		elif _focused is LootChest:
			Game.send_action("chest", [str(_focused.name)])
		elif _focused is BuildPiece and _focused.kind() == "doorway":
			Game.send_action("door", [str(_focused.name)])
		elif _focused is BuildPiece and _focused.kind() == "storage":
			Game.send_action("storage_open", [str(_focused.name)])
		elif _focused is BuildPiece and _focused.kind() == "bed":
			Game.send_action("bed_claim", [str(_focused.name)])
		elif _focused is Creature:
			if _focused.tamed_owner != "":
				Game.send_action("pet", [str(_focused.name)])
			elif _focused.is_tameable_with(held_item):
				Game.send_action("feed", [str(_focused.name)])
		return

	# Martillo: construir / desarmar
	if held_item == "hammer":
		if right_click and _focused is BuildPiece:
			Game.send_action("demolish", [str(_focused.name)])
		elif right_click and _focused is Station and _focused.get_parent() is BuildPiece:
			Game.send_action("demolish", [str(_focused.get_parent().name)])
		elif click_once and _ghost_piece != "" and _placement.get("valid", false):
			Game.send_action("build", [_ghost_piece, _placement["hit"], model.rotation.y])
			play_swing.rpc()
		elif click_once and _ghost_piece != "":
			Game.notify.emit(_placement.get("reason", "No se puede construir acá"))
		return

	# Click: según lo que apuntás y lo que tenés en la mano
	if _action_cooldown > 0.0:
		return
	if click and _focused is Creature and _focused.tamed_owner == "":
		if Game.stamina < ATTACK_COST * 0.5:
			return
		_action_cooldown = ItemDB.attack_cooldown(held_item)
		_use_stamina(ATTACK_COST)
		_face(_focused.global_position)
		play_swing.rpc()
		Game.send_action("attack", [str(_focused.name)])
	elif click and _focused is ResourceNode:
		_action_cooldown = GATHER_COOLDOWN
		_face(_focused.global_position)
		play_swing.rpc()
		Game.send_action("gather", [str(_focused.name)])
	elif click_once and ItemDB.is_food(held_item):
		_action_cooldown = 0.6
		Sound.play("eat")
		Game.send_action("eat", [Game.selected_slot])
	elif click_once and ItemDB.is_blueprint(held_item):
		_action_cooldown = 0.6
		Game.send_action("learn", [Game.selected_slot])
	elif click_once:
		_action_cooldown = ItemDB.attack_cooldown(held_item)
		play_swing.rpc()  # Golpe al aire.


func _face(target: Vector3) -> void:
	var to_target := target - global_position
	model.rotation.y = atan2(-to_target.x, -to_target.z)
	sync_rot = model.rotation.y


@rpc("authority", "call_local", "unreliable")
func play_swing() -> void:
	_body.play_swing()
	Sound.play("swing", global_position + Vector3.UP, -6.0)


# --- Modo construcción -----------------------------------------------------------------

func _cycle_build_piece() -> void:
	var pieces := BuildDB.unlocked_pieces(_world.known_blueprints)
	if pieces.is_empty():
		Game.notify.emit("No conocen ningún plano. Búsquenlos en cofres o derrotando sombras.")
		return
	_build_index = (_build_index + 1) % pieces.size()
	Game.notify.emit("Construir: %s" % BuildDB.get_piece(pieces[_build_index])["name"])


func current_build_piece() -> String:
	var pieces := BuildDB.unlocked_pieces(_world.known_blueprints)
	if pieces.is_empty():
		return ""
	return pieces[_build_index % pieces.size()]


func build_placement() -> Dictionary:
	return _placement


## Vista previa transparente (verde = se puede, rojo = no) de la pieza a construir.
func _update_build_ghost() -> void:
	var piece := current_build_piece() if held_item == "hammer" and Game.can_act() else ""
	if piece != _ghost_piece:
		_ghost_piece = piece
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		if piece != "":
			_ghost = MeshInstance3D.new()
			_ghost.mesh = BuildPiece.piece_mesh(piece)
			_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_world.add_child(_ghost)
	if _ghost == null:
		_placement = {}
		return
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var to := from + forward * (_spring_arm.get_hit_length() + BuildDB.BUILD_RANGE)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit["position"] if hit else to
	if not hit:
		point.y = _world.terrain.get_height(point.x, point.z)
	_placement = _world.compute_placement(piece, point, model.rotation.y)
	_placement["hit"] = point
	_ghost.global_position = _placement["position"]
	_ghost.rotation = Vector3(0, _placement["rotation"], 0)
	_ghost.material_override = _ghost_material(_placement["valid"])


static var _ghost_materials: Dictionary = {}


static func _ghost_material(valid: bool) -> StandardMaterial3D:
	if not _ghost_materials.has(valid):
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1.0, 0.4, 0.35) if valid else Color(1.0, 0.3, 0.25, 0.35)
		_ghost_materials[valid] = mat
	return _ghost_materials[valid]


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_ghost):
		_ghost.queue_free()
