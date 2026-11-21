class_name LootChest
extends StaticBody3D
## Cofre con botín escondido en la isla (planos, materiales, comida).
## Aparece igual para todos; al abrirlo, el servidor sortea el contenido y se lo da a quien lo abrió.
## Se vuelve a llenar después de un rato.

var opened := false
var _lid: Node3D


func _ready() -> void:
	var wood := Color(0.48, 0.32, 0.18)
	var metal := Color(0.35, 0.33, 0.3)
	PropFactory._add_mesh(self, PropFactory.combine([
		[PropFactory.box(Vector3(1.0, 0.55, 0.65)), PropFactory._at(Vector3(0, 0.28, 0)), wood],
		[PropFactory.box(Vector3(1.04, 0.08, 0.69)), PropFactory._at(Vector3(0, 0.1, 0)), metal],
		[PropFactory.box(Vector3(0.08, 0.57, 0.69)), PropFactory._at(Vector3(-0.35, 0.28, 0)), metal],
		[PropFactory.box(Vector3(0.08, 0.57, 0.69)), PropFactory._at(Vector3(0.35, 0.28, 0)), metal],
	]), Vector3.ZERO)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, 0.32)
	add_child(_lid)
	PropFactory._add_mesh(_lid, PropFactory.combine([
		[PropFactory.box(Vector3(1.0, 0.2, 0.65)), PropFactory._at(Vector3(0, 0.1, -0.32)), wood.lightened(0.05)],
		[PropFactory.box(Vector3(0.12, 0.14, 0.05)), PropFactory._at(Vector3(0, 0.0, -0.66)), Color(0.85, 0.7, 0.3)],
	]), Vector3.ZERO)
	PropFactory._box_collision(self, Vector3(1.0, 0.75, 0.65), Vector3(0, 0.37, 0))


func get_interact_text() -> String:
	return "" if opened else "Abrir cofre"


func set_opened(value: bool) -> void:
	if value and not opened:
		Sound.play("chest_open", global_position + Vector3.UP)
	opened = value
	create_tween().tween_property(_lid, "rotation:x", -1.7 if value else 0.0, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
