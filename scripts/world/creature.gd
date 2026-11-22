class_name Creature
extends CharacterBody3D
## Animal o criatura nocturna. El servidor la controla (IA) y la replica a todos.
## Comportamientos: huir, defenderse, cazar de noche, atacar jugadores (mobs),
## y seguir/defender a su dueño cuando está domesticada.

const GRAVITY := 18.0

var species := "":
	set(value):
		species = value
		_data = CreatureDB.get_species(value)
var sync_pos := Vector3.ZERO
var sync_rot := 0.0
var anim_speed := 0.0
var health_ratio := 1.0:
	set(value):
		if value < health_ratio - 0.001 and is_inside_tree():
			Sound.play("creature_hurt", global_position + Vector3.UP, 0.0, 0.2)
			Sound.play("hit", global_position + Vector3.UP, -4.0)
		health_ratio = value
		_update_label()
var tamed_owner := "":  ## Nombre del dueño ("" = salvaje).
	set(value):
		tamed_owner = value
		_update_label()
var tame_progress := 0:
	set(value):
		tame_progress = value
		_update_label()
var follow_owner := true:
	set(value):
		follow_owner = value
		_update_label()
var attack_count := 0:
	set(value):
		if value != attack_count and _body is Quadruped:
			_body.play_attack()
		elif value != attack_count and _body is Humanoid:
			_body.play_swing()
		attack_count = value
var dead := false:
	set(value):
		if value and not dead and is_inside_tree():
			Sound.play("creature_die", global_position + Vector3.UP)
		dead = value
		if value and _body is Quadruped:
			_body.play_death()
		elif value and _body:
			create_tween().tween_property(_body, "scale", Vector3(1, 0.05, 1), 0.5)

# --- Solo en el servidor ---
var owner_peer := 0
var health := 1.0
var _data: Dictionary = {}
var _target: Node3D = null
var _aggro_time := 0.0
var _flee_from := Vector3.INF
var _flee_time := 0.0
var _wander_dir := Vector3.ZERO
var _wander_time := 0.0
var _attack_cooldown := 0.0
var _last_attacker_peer := 0
var _rng := RandomNumberGenerator.new()

var home := Vector3.ZERO  ## Donde apareció (los bandidos no se alejan de su campamento).
var _body: Node3D
var _label: Label3D
var _world: Node


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	collision_layer = 1
	collision_mask = 1
	var size: float = _data.get("look", {}).get("size", _data.get("scale", 1.0))
	if multiplayer.is_server():
		home = global_position
	if _data.get("body", "quadruped") == "humanoid":
		var humanoid := Humanoid.new()
		var is_shadow: bool = _data.get("behavior", "") == "mob"
		humanoid.build(_data.get("look", {}) if _data.has("look") else {
			"skin": Color(0.12, 0.1, 0.16), "hair": Color(0.05, 0.04, 0.07), "shirt": Color(0.1, 0.08, 0.14),
			"pants": Color(0.07, 0.06, 0.1), "boots": Color(0.05, 0.05, 0.06),
		})
		for side in ([-1, 1] if is_shadow else []):
			var eye := MeshInstance3D.new()
			eye.mesh = Humanoid._box(Vector3(0.05, 0.03, 0.02))
			eye.material_override = PropFactory.material(Color(1.0, 0.25, 0.15), 6.0)
			eye.position = Vector3(0.045 * side, 0.14, -0.125)
			humanoid.head.add_child(eye)
		humanoid.scale = Vector3.ONE * size
		_body = humanoid
		_add_collision(0.35 * size, 1.8 * size)
	else:
		var quadruped := Quadruped.new()
		quadruped.build(_data.get("look", {}))
		_body = quadruped
		var leg_height: float = 0.6 * _data.get("look", {}).get("legs", 1.0)
		_add_collision(0.35 * size, (leg_height + 0.55) * size)
	add_child(_body)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 34
	_label.outline_size = 10
	_label.pixel_size = 0.005
	_label.position.y = (2.3 if _data.get("body", "") == "humanoid" else 1.4) * size + 0.3
	add_child(_label)
	_update_label()

	if multiplayer.is_server():
		health = _data.get("health", 50.0)
		_rng.randomize()
		sync_pos = global_position
	if sync_pos == Vector3.ZERO:
		sync_pos = global_position


func _add_collision(radius: float, height: float) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height / 2.0
	add_child(collision)


func _update_label() -> void:
	if _label == null:
		return
	var text := CreatureDB.display_name(species)
	if tamed_owner != "":
		text = "%s de %s%s" % [text, tamed_owner, "" if follow_owner else " (quieto)"]
		_label.modulate = Color(0.6, 1.0, 0.6)
	elif CreatureDB.is_mob(species):
		_label.modulate = Color(1.0, 0.45, 0.4)
	else:
		_label.modulate = Color(1.0, 1.0, 0.9)
		if tame_progress > 0:
			text += "  (domando %d/%d)" % [tame_progress, _data.get("tame", {}).get("amount", 0)]
	if health_ratio < 0.999:
		text += "\n" + "|".repeat(maxi(1, roundi(health_ratio * 20)))
	_label.text = text


func get_interact_text() -> String:
	if dead:
		return ""
	if tamed_owner != "":
		return "Ordenar: %s" % ("quedarse quieto" if follow_owner else "seguirte")
	var tame: Dictionary = _data.get("tame", {})
	if not tame.is_empty():
		return "Domesticar con %s (%d/%d)" % [ItemDB.item_name(tame["food"]), tame_progress, tame["amount"]]
	return ""


func is_tameable_with(item: String) -> bool:
	return tamed_owner == "" and not dead and _data.get("tame", {}).get("food", "") == item


# --- Clientes: interpolar lo que manda el servidor ---------------------------------------

var _whisper_timer := 3.0


func _process(delta: float) -> void:
	# Las sombras susurran cuando están cerca del jugador.
	if dead or not CreatureDB.is_mob(species) or Game.local_player == null:
		return
	_whisper_timer -= delta
	if _whisper_timer <= 0.0:
		_whisper_timer = randf_range(4.0, 9.0)
		if global_position.distance_to(Game.local_player.global_position) < 30.0:
			Sound.play("shade_whisper", global_position + Vector3.UP * 1.5, -2.0, 0.2)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		if global_position.distance_to(sync_pos) > 10.0:
			global_position = sync_pos
		else:
			global_position = global_position.lerp(sync_pos, clampf(delta * 10.0, 0.0, 1.0))
		_body.rotation.y = lerp_angle(_body.rotation.y, sync_rot, clampf(delta * 10.0, 0.0, 1.0))
		_set_body_speed(anim_speed)
		return
	if dead:
		return
	_server_think(delta)


func _set_body_speed(speed: float) -> void:
	if _body is Quadruped:
		_body.move_speed = speed
	elif _body:
		_body.move_speed = speed
		_body.grounded = true


# --- IA (servidor) ------------------------------------------------------------------------

func _server_think(delta: float) -> void:
	var players: Array = _world.get_players()
	var nearest_player: Node3D = null
	var nearest_distance := INF
	for player in players:
		var d: float = player.global_position.distance_to(global_position)
		if d < nearest_distance:
			nearest_distance = d
			nearest_player = player

	# Lejos de todos los jugadores: duerme para ahorrar CPU.
	if nearest_distance > 150.0 and tamed_owner == "":
		if CreatureDB.is_mob(species):
			queue_free()
		return

	_attack_cooldown -= delta
	_aggro_time -= delta
	_flee_time -= delta
	var behavior: String = _data.get("behavior", "flee")
	var speed: float = _data.get("speed", 5.0)
	var night: bool = _world.is_night()
	var desired := Vector3.ZERO

	if behavior == "mob" and not night:
		_take_damage_internal(20.0 * delta, null)  # Las sombras se queman con la luz del día.

	if tamed_owner != "":
		desired = _think_pet(players, speed)
	else:
		match behavior:
			"flee":
				if nearest_distance < 9.0:
					_flee_from = nearest_player.global_position
					_flee_time = 3.0
			"wolf":
				if night and nearest_distance < 16.0 and _target == null:
					_target = nearest_player
					_aggro_time = 15.0
			"mob":
				_target = _nearest_enemy_for_mob(players)
				_aggro_time = 1.0
			"hostile":
				var leash := global_position.distance_to(home)
				if leash > 38.0:
					_target = null
					_aggro_time = 0.0
				elif nearest_player != null and nearest_distance < _data.get("aggro", 14.0) and not _is_dead_target(nearest_player):
					_target = nearest_player
					_aggro_time = 6.0
		if _target != null and (not is_instance_valid(_target) or _aggro_time <= 0.0 or _is_dead_target(_target)):
			_target = null
		if _flee_time > 0.0 and _flee_from != Vector3.INF:
			var away := (global_position - _flee_from)
			away.y = 0
			desired = away.normalized() * speed
		elif _target != null:
			desired = _chase_and_attack(_target, speed)
		elif behavior == "hostile" and global_position.distance_to(home) > 14.0:
			var back := home - global_position
			back.y = 0.0
			desired = back.normalized() * speed * 0.6  # Vuelve al campamento.
		else:
			desired = _wander(delta, speed * (0.4 if behavior == "hostile" else 1.0))

	# No meterse al agua.
	var ahead := global_position + desired.normalized() * 2.0
	if desired.length() > 0.1 and _world.terrain.get_height(ahead.x, ahead.z) < TerrainGenerator.WATER_LEVEL + 0.2:
		desired = Vector3.ZERO
		_wander_time = 0.0

	velocity.x = lerpf(velocity.x, desired.x, clampf(delta * 6.0, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, desired.z, clampf(delta * 6.0, 0.0, 1.0))
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	if is_on_wall() and is_on_floor() and desired.length() > 0.5:
		velocity.y = 6.0  # Salta obstáculos chicos.
	move_and_slide()
	if global_position.y < -30.0:
		if tamed_owner != "":
			# Una mascota nunca se pierde: vuelve a la superficie.
			global_position.y = _world.terrain.get_height(global_position.x, global_position.z) + 1.0
			velocity = Vector3.ZERO
		else:
			queue_free()

	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > 0.3:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-velocity.x, -velocity.z), clampf(delta * 8.0, 0.0, 1.0))
	sync_pos = global_position
	sync_rot = _body.rotation.y
	var speed_now := snappedf(horizontal.length(), 0.5)
	if not is_equal_approx(speed_now, anim_speed):
		anim_speed = speed_now
	_set_body_speed(horizontal.length())


func _wander(delta: float, speed: float) -> Vector3:
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = _rng.randf_range(2.5, 6.0)
		if _rng.randf() < 0.4:
			_wander_dir = Vector3.ZERO
		else:
			var angle := _rng.randf() * TAU
			_wander_dir = Vector3(cos(angle), 0, sin(angle))
	return _wander_dir * speed * 0.3


func _chase_and_attack(target: Node3D, speed: float) -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0
	var size: float = _data.get("look", {}).get("size", _data.get("scale", 1.0))
	if multiplayer.is_server():
		home = global_position
	var reach := 1.4 + size * 0.6
	if to_target.length() <= reach:
		_body.rotation.y = atan2(-to_target.x, -to_target.z)
		if _attack_cooldown <= 0.0:
			_attack_cooldown = 1.8 if CreatureDB.is_mob(species) else 1.3
			attack_count += 1
			var damage: float = _data.get("damage", 5.0)
			if target is Creature:
				target.take_damage(damage, self)
			else:
				_world.damage_player(str(target.name).to_int(), damage)
		return Vector3.ZERO
	return to_target.normalized() * speed


func _nearest_enemy_for_mob(players: Array) -> Node3D:
	var best: Node3D = null
	var best_distance := 45.0
	for player in players:
		var d: float = player.global_position.distance_to(global_position)
		if d < best_distance:
			best_distance = d
			best = player
	for creature in _world.creatures_root.get_children():
		if creature is Creature and creature.tamed_owner != "" and not creature.dead:
			var d: float = creature.global_position.distance_to(global_position)
			if d < best_distance:
				best_distance = d
				best = creature
	if best == null and not players.is_empty():
		# Si no hay nadie cerca, se acerca despacio al jugador más cercano.
		best = players[0]
		for player in players:
			if player.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
				best = player
	return best


func _think_pet(_players: Array, speed: float) -> Vector3:
	var owner_node: Node3D = _world.players_root.get_node_or_null(str(owner_peer))
	var tame: Dictionary = _data.get("tame", {})
	# Mascotas que pelean: atacan sombras cerca.
	if tame.get("combat", false):
		if _target == null or not is_instance_valid(_target) or _target.dead:
			_target = null
			for creature in _world.creatures_root.get_children():
				if creature is Creature and CreatureDB.is_mob(creature.species) and not creature.dead \
						and creature.global_position.distance_to(global_position) < 14.0:
					_target = creature
					break
		if _target != null:
			return _chase_and_attack(_target, speed)
	if owner_node == null or not follow_owner:
		return Vector3.ZERO
	var to_owner := owner_node.global_position - global_position
	to_owner.y = 0
	if to_owner.length() > 45.0:
		# Se teletransporta cerca del dueño, siempre sobre el terreno (nunca bajo tierra).
		var spot := owner_node.global_position + Vector3(2, 0, 2)
		spot.y = _world.terrain.get_height(spot.x, spot.z) + 0.5
		global_position = spot
		velocity = Vector3.ZERO
		return Vector3.ZERO
	if to_owner.length() > 4.0:
		return to_owner.normalized() * speed * (1.0 if to_owner.length() > 10.0 else 0.6)
	return Vector3.ZERO


func _is_dead_target(target: Node3D) -> bool:
	return target is Creature and target.dead


## Daño (servidor). attacker: jugador (Node3D) o criatura que atacó.
func take_damage(amount: float, attacker: Node3D) -> void:
	if not multiplayer.is_server() or dead:
		return
	if attacker != null and not attacker is Creature:
		_last_attacker_peer = str(attacker.name).to_int()
		var behavior: String = _data.get("behavior", "flee")
		if behavior == "flee":
			_flee_from = attacker.global_position
			_flee_time = 5.0
		else:
			_target = attacker
			_aggro_time = 20.0
		if tame_progress > 0:
			tame_progress = 0  # Si lo lastimás, pierde la confianza.
	elif attacker is Creature:
		_target = attacker
		_aggro_time = 10.0
	_take_damage_internal(amount, attacker)


func _take_damage_internal(amount: float, _attacker: Node3D) -> void:
	health -= amount
	var ratio := clampf(health / float(_data.get("health", 50.0)), 0.0, 1.0)
	if absf(ratio - health_ratio) > 0.01 or ratio <= 0.0:
		health_ratio = ratio
	if health <= 0.0:
		_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	_world.on_creature_died(self, _last_attacker_peer)
	get_tree().create_timer(4.0).timeout.connect(queue_free)


## Darle comida para domesticarlo (servidor). Devuelve true si quedó domesticado.
func add_tame_progress(peer_id: int, owner_name: String) -> bool:
	_target = null
	_flee_time = 0.0
	tame_progress += 1
	if tame_progress >= int(_data.get("tame", {}).get("amount", 999)):
		owner_peer = peer_id
		tamed_owner = owner_name
		follow_owner = true
		health = _data.get("health", 50.0)
		health_ratio = 1.0
		return true
	return false
