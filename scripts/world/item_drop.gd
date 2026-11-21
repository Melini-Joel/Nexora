class_name ItemDrop
extends StaticBody3D
## Bolsa con objetos tirada en el suelo. Cualquier jugador la puede recoger con E.
## La crea y la borra el servidor; el MultiplayerSpawner la replica a todos.

const LIFETIME := 300.0  ## Segundos hasta que desaparece sola.
const PICKUP_LAYER := 2  ## Capa propia: los jugadores no chocan con las bolsas.

var item_id := "":
	set(value):
		item_id = value
		_refresh()
var count := 1:
	set(value):
		count = value
		_refresh()

var _age := 0.0
var _visual: Node3D
var _tag: MeshInstance3D


func _ready() -> void:
	collision_layer = PICKUP_LAYER
	collision_mask = 0
	_visual = Node3D.new()
	add_child(_visual)
	PropFactory._add_mesh(_visual, PropFactory.blob_mesh(0.32, PropFactory.SACK, 0.05, 1), Vector3(0, 0.28, 0))
	PropFactory._add_mesh(_visual, PropFactory.cone_mesh(0.14, 0.2, PropFactory.SACK), Vector3(0, 0.6, 0))
	# Etiqueta con el color del objeto que contiene.
	_tag = PropFactory._add_mesh(_visual, PropFactory.box_mesh(Vector3(0.2, 0.2, 0.05), Color.WHITE), Vector3(0, 0.3, -0.33))
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.3
	add_child(collision)
	_refresh()
	_visual.scale = Vector3.ONE * 0.2
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_visual.rotation.y += delta * 0.6
	if multiplayer.is_server():
		_age += delta
		if _age > LIFETIME:
			queue_free()


func get_interact_text() -> String:
	return "Recoger %s x%d" % [ItemDB.item_name(item_id), count]


func _refresh() -> void:
	if _tag:
		_tag.material_override = PropFactory.material(ItemDB.color(item_id), 0.4)
