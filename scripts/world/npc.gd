class_name NPC
extends StaticBody3D
## Personaje no jugable. Se acerca uno, aprieta E y se abre el diálogo.
## Muestra "!" si tiene una misión para dar y "?" si hay una misión lista para entregar.
## Los NPCs existen igual en todos los jugadores (no hace falta sincronizarlos por red).

const TALK_RANGE := 8.0

var npc_id := ""
var _body: Humanoid
var _marker: Label3D
var _time := 0.0


func setup(id: String) -> void:
	npc_id = id
	name = "NPC_" + id


func _ready() -> void:
	var data := NpcDB.get_npc(npc_id)
	_body = Humanoid.new()
	_body.build(data.get("look", {}))
	add_child(_body)

	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.85
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.92
	add_child(collision)

	var label := Label3D.new()
	label.text = "%s\n%s" % [data.get("name", npc_id), data.get("title", "")]
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 10
	label.pixel_size = 0.005
	label.modulate = Color(1.0, 0.92, 0.7)
	add_child(label)

	_marker = Label3D.new()
	_marker.position = Vector3(0, 2.65, 0)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.font_size = 110
	_marker.outline_size = 18
	_marker.pixel_size = 0.006
	_marker.no_depth_test = true
	_marker.modulate = Color(1.0, 0.8, 0.2)
	add_child(_marker)

	QuestManager.quest_changed.connect(_refresh_marker)
	_refresh_marker()


func get_interact_text() -> String:
	return "Hablar con %s" % NpcDB.display_name(npc_id)


func _refresh_marker() -> void:
	_marker.text = QuestManager.npc_marker(npc_id)


func _process(delta: float) -> void:
	_time += delta
	_marker.position.y = 2.65 + sin(_time * 3.0) * 0.08
	# Mira al jugador más cercano.
	var target := _nearest_player()
	if target != Vector3.INF:
		var to_target := target - global_position
		var yaw := atan2(-to_target.x, -to_target.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, clampf(delta * 3.0, 0.0, 1.0))


func _nearest_player() -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_distance := TALK_RANGE
	for player in world.get_players():
		var distance: float = player.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player.global_position
	return best
