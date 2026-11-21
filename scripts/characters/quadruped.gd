class_name Quadruped
extends Node3D
## Animal de cuatro patas articulado (cuerpo, cuello, cabeza, 4 patas con rodilla y cola)
## con animaciones procedurales: quieto, caminar, correr, atacar y morir.
## look: {"size", "color", "ears", "tail", "antlers", "tusks", "legs", "snout"}

var move_speed := 0.0
var _body: Node3D
var _neck: Node3D
var _head: Node3D
var _tail: Node3D
var _legs: Array[Node3D] = []  ## [delantera izq, delantera der, trasera izq, trasera der]
var _knees: Array[Node3D] = []
var _phase := 0.0
var _time := 0.0
var _attack_t := -1.0
var _dead := false
var _stride := 1.0
var _leg_height := 0.6


func build(look: Dictionary) -> void:
	var size: float = look.get("size", 1.0)
	var color: Color = look.get("color", Color(0.5, 0.4, 0.3))
	var dark := color.darkened(0.35)
	var light := color.lightened(0.25)
	var leg_factor: float = look.get("legs", 1.0)
	_leg_height = 0.6 * leg_factor
	_stride = 0.9 * leg_factor
	scale = Vector3.ONE * size

	_body = _pivot(self, Vector3(0, _leg_height + 0.25, 0))
	_part(_body, Humanoid._capsule(0.27, 1.15), color, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_part(_body, Humanoid._capsule(0.2, 0.7), light, Vector3(0, -0.08, -0.05), Vector3(PI / 2, 0, 0))  # panza

	_neck = _pivot(_body, Vector3(0, 0.12, -0.5))
	_part(_neck, Humanoid._capsule(0.13, 0.42), color, Vector3(0, 0.12, -0.08), Vector3(-0.6, 0, 0))
	_head = _pivot(_neck, Vector3(0, 0.3, -0.18))
	_part(_head, Humanoid._sphere(0.16, 0.28), color, Vector3.ZERO)
	var snout: float = look.get("snout", 0.8)
	_part(_head, Humanoid._capsule(0.09, 0.2 + snout * 0.18), color.lightened(0.08), Vector3(0, -0.05, -0.17 - snout * 0.05), Vector3(PI / 2, 0, 0))
	_part(_head, Humanoid._box(Vector3(0.06, 0.05, 0.04)), Color(0.08, 0.06, 0.06), Vector3(0, -0.04, -0.3 - snout * 0.1))
	for side in [-1, 1]:
		_part(_head, Humanoid._box(Vector3(0.04, 0.04, 0.02)), Color(0.05, 0.05, 0.05), Vector3(0.09 * side, 0.05, -0.12))
		match look.get("ears", "small"):
			"long":
				_part(_head, Humanoid._capsule(0.04, 0.42), color, Vector3(0.06 * side, 0.27, 0.03), Vector3(-0.2, 0, 0.15 * side))
			"pointy":
				_part(_head, Humanoid._cylinder(0.0, 0.06, 0.16), dark, Vector3(0.09 * side, 0.18, 0.02), Vector3(0, 0, -0.2 * side))
			"round":
				_part(_head, Humanoid._sphere(0.06, 0.08), dark, Vector3(0.11 * side, 0.13, 0.03))
			"small":
				_part(_head, Humanoid._cylinder(0.02, 0.05, 0.1), color, Vector3(0.1 * side, 0.15, 0.03), Vector3(0, 0, -0.4 * side))
		if look.get("antlers", false):
			var antler := Color(0.85, 0.78, 0.62)
			_part(_head, Humanoid._cylinder(0.015, 0.025, 0.45), antler, Vector3(0.09 * side, 0.32, 0.02), Vector3(-0.2, 0, -0.35 * side))
			_part(_head, Humanoid._cylinder(0.01, 0.02, 0.22), antler, Vector3(0.17 * side, 0.42, -0.06), Vector3(-0.8, 0, -0.2 * side))
			_part(_head, Humanoid._cylinder(0.01, 0.02, 0.2), antler, Vector3(0.2 * side, 0.5, 0.05), Vector3(0.3, 0, -0.5 * side))
		if look.get("tusks", false):
			_part(_head, Humanoid._cylinder(0.0, 0.025, 0.14), Color(0.95, 0.92, 0.85), Vector3(0.07 * side, -0.06, -0.33), Vector3(-0.6, 0, 0))

	_tail = _pivot(_body, Vector3(0, 0.1, 0.55))
	match look.get("tail", "short"):
		"long":
			_part(_tail, Humanoid._capsule(0.06, 0.45), color, Vector3(0, -0.1, 0.18), Vector3(0.9, 0, 0))
		"puff":
			_part(_tail, Humanoid._sphere(0.08, 0.14), Color(0.95, 0.95, 0.92), Vector3(0, 0, 0.02))
		"thin":
			_part(_tail, Humanoid._capsule(0.02, 0.25), dark, Vector3(0, -0.1, 0.06), Vector3(0.3, 0, 0))
		"lizard":
			_part(_tail, Humanoid._cylinder(0.02, 0.12, 0.8), color, Vector3(0, -0.12, 0.35), Vector3(PI / 2 + 0.25, 0, 0))
		_:
			_part(_tail, Humanoid._sphere(0.06, 0.1), color, Vector3.ZERO)

	for pos in [Vector3(-0.17, -0.1, -0.38), Vector3(0.17, -0.1, -0.38), Vector3(-0.17, -0.1, 0.38), Vector3(0.17, -0.1, 0.38)]:
		var leg := _pivot(_body, pos)
		var upper := _leg_height * 0.5
		_part(leg, Humanoid._capsule(0.075, upper + 0.12), color, Vector3(0, -upper / 2, 0))
		var knee := _pivot(leg, Vector3(0, -upper, 0))
		_part(knee, Humanoid._capsule(0.05, upper + 0.08), color.darkened(0.1), Vector3(0, -upper / 2, 0))
		_part(knee, Humanoid._box(Vector3(0.09, 0.06, 0.11)), dark, Vector3(0, -upper + 0.02, -0.01))
		_legs.append(leg)
		_knees.append(knee)


## Mobs humanoides: ojos que brillan.
func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	parent.add_child(node)
	return node


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PropFactory.material(color)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func play_attack() -> void:
	_attack_t = 0.0


func play_death() -> void:
	if _dead:
		return
	_dead = true
	create_tween().tween_property(self, "rotation:z", PI / 2, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _body == null or _dead:
		return
	_time += delta
	var walk := clampf(move_speed / 2.0, 0.0, 1.0)
	var run := clampf((move_speed - 4.0) / 3.0, 0.0, 1.0)
	if move_speed > 0.05:
		_phase = fmod(_phase + delta * move_speed / (_stride * scale.x) * PI, TAU)
	var s := sin(_phase)
	var amp := lerpf(0.45, 0.8, run) * walk
	# Patas en diagonal: delantera izq. con trasera der.
	var offsets := [0.0, PI, PI, 0.0]
	for i in 4:
		var leg_phase: float = _phase + offsets[i] + (0.4 * run if i >= 2 else 0.0)
		_legs[i].rotation.x = sin(leg_phase) * amp
		_knees[i].rotation.x = (maxf(0.0, cos(leg_phase)) * 0.6 * walk) * (1.0 if i >= 2 else -1.0)
	_body.position.y = _leg_height + 0.25 + absf(s) * 0.05 * walk + sin(_time * 2.0) * 0.006
	_body.rotation.x = sin(_phase * 2.0) * 0.04 * run
	_neck.rotation.x = -0.15 * run + sin(_time * 0.8) * 0.06 * (1.0 - walk)
	_head.rotation.y = sin(_time * 0.5) * 0.3 * (1.0 - walk)
	_tail.rotation.y = sin(_time * (3.0 + run * 8.0)) * 0.35
	if _attack_t >= 0.0:
		_attack_t += delta / 0.4
		if _attack_t >= 1.0:
			_attack_t = -1.0
		else:
			var lunge := sin(_attack_t * PI)
			_neck.rotation.x += lunge * 0.6
			_body.position.z = -lunge * 0.2
