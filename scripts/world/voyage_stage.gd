class_name VoyageStage
extends Node3D
## Escenario temporal de la cinemática del viaje: el Albatros navegando entre la isla y
## Valdoria, meciéndose con las olas. Se borra solo cuando termina (o se saltea) la cinemática.

var ship: Node3D
var _tween: Tween
var _time := 0.0


func _ready() -> void:
	ship = PropFactory.make_ship()
	add_child(ship)
	ship.visible = false
	# Se conecta al terminar el cuadro: así no lo borra el final de una cinemática anterior.
	Cinematics.finished.connect.call_deferred(queue_free, CONNECT_ONE_SHOT)


## El barco navega en línea recta de "from" a "to" en "duration" segundos.
func sail(from: Vector3, to: Vector3, duration: float) -> void:
	ship.visible = true
	ship.global_position = from
	var heading := to - from
	ship.rotation.y = atan2(-heading.x, -heading.z)  # La proa (-Z) mira hacia el destino.
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(ship, "global_position", to, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	if ship:
		ship.rotation.z = sin(_time * 0.9) * 0.04
		ship.rotation.x = sin(_time * 0.6 + 1.0) * 0.025
