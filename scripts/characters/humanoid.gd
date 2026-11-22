class_name Humanoid
extends Node3D
## Personaje humanoide articulado (cadera, columna, cabeza, hombros, codos, manos,
## caderas, rodillas y tobillos) con animaciones procedurales:
##   quieto (respiración), caminar, correr, saltar, caer, aterrizar, golpear,
##   fabricar y caminar encorvado cuando la mochila pesa mucho.
##
## Las animaciones se calculan por código a partir de la velocidad y el estado, así
## funcionan igual para el jugador local, los compañeros por red y los NPCs.
## Más adelante se puede reemplazar por un modelo con esqueleto (Blender / Mixamo)
## manteniendo la misma interfaz: move_speed, grounded, vertical_speed, play_swing()...

const HIP_HEIGHT := 0.92

signal step  ## Cada vez que un pie toca el suelo (para el sonido de pasos).

# --- Estado de animación (lo actualiza el dueño cada frame) ---
var move_speed := 0.0  ## Velocidad horizontal en m/s.
var grounded := true
var vertical_speed := 0.0
var load_ratio := 0.0  ## 0..1+: encorva al personaje.
var busy := false  ## Fabricando: mueve las manos al frente.
var holding_item := false

# --- Huesos ---
var hips: Node3D
var spine: Node3D
var head: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var ankle_l: Node3D
var ankle_r: Node3D
var hand_attach: Node3D  ## Herramientas en la mano derecha.
var back_attach: Node3D  ## Mochila.

var _phase := 0.0
var _time := 0.0
var _walk_blend := 0.0
var _air := 0.0
var _land := 0.0
var _busy_blend := 0.0
var _was_grounded := true
var _swing_t := -1.0  ## -1 = sin golpe; 0..1 durante el golpe.

const SWING_DURATION := 0.45


## Arma el cuerpo. look: {"skin", "hair", "shirt", "pants", "boots", "accessories": [...]}
func build(look: Dictionary) -> void:
	var skin: Color = look.get("skin", Color(0.9, 0.74, 0.6))
	var hair: Color = look.get("hair", Color(0.25, 0.17, 0.1))
	var shirt: Color = look.get("shirt", Color(0.3, 0.5, 0.8))
	var pants: Color = look.get("pants", Color(0.25, 0.27, 0.32))
	var boots: Color = look.get("boots", Color(0.28, 0.2, 0.14))
	var dark := Color(0.08, 0.07, 0.07)

	hips = _pivot(self, Vector3(0, HIP_HEIGHT, 0))
	_part(hips, _capsule(0.16, 0.4), pants, Vector3(0, 0.0, 0), Vector3(0, 0, PI / 2))
	_part(hips, _box(Vector3(0.34, 0.05, 0.22)), boots.darkened(0.2), Vector3(0, 0.08, 0))  # cinturón

	spine = _pivot(hips, Vector3(0, 0.08, 0))
	_part(spine, _cylinder(0.19, 0.15, 0.48), shirt, Vector3(0, 0.26, 0))  # torso
	_part(spine, _capsule(0.1, 0.5), shirt, Vector3(0, 0.46, 0), Vector3(0, 0, PI / 2))  # hombros
	_part(spine, _cylinder(0.055, 0.065, 0.12), skin, Vector3(0, 0.57, 0))  # cuello

	head = _pivot(spine, Vector3(0, 0.62, 0))
	_part(head, _sphere(0.125, 0.29), skin, Vector3(0, 0.12, 0))
	_part(head, _hemisphere(0.133), hair, Vector3(0, 0.15, 0.012))
	_part(head, _box(Vector3(0.04, 0.035, 0.02)), dark, Vector3(-0.045, 0.14, -0.115))
	_part(head, _box(Vector3(0.04, 0.035, 0.02)), dark, Vector3(0.045, 0.14, -0.115))
	_part(head, _box(Vector3(0.03, 0.05, 0.04)), skin.darkened(0.08), Vector3(0, 0.105, -0.125))
	_part(head, _box(Vector3(0.05, 0.012, 0.01)), skin.darkened(0.35), Vector3(0, 0.06, -0.118))

	for side in [-1, 1]:
		var shoulder := _pivot(spine, Vector3(0.245 * side, 0.47, 0))
		_part(shoulder, _capsule(0.058, 0.33), shirt, Vector3(0, -0.14, 0))
		var elbow := _pivot(shoulder, Vector3(0, -0.29, 0))
		_part(elbow, _capsule(0.047, 0.3), skin, Vector3(0, -0.13, 0))
		_part(elbow, _cylinder(0.06, 0.06, 0.06), shirt.darkened(0.1), Vector3(0, -0.01, 0))  # puño de la manga
		var hand := _pivot(elbow, Vector3(0, -0.28, 0))
		_part(hand, _box(Vector3(0.075, 0.1, 0.05)), skin, Vector3(0, -0.04, 0))
		var hip := _pivot(hips, Vector3(0.1 * side, -0.02, 0))
		_part(hip, _capsule(0.078, 0.46), pants, Vector3(0, -0.21, 0))
		var knee := _pivot(hip, Vector3(0, -0.44, 0))
		_part(knee, _capsule(0.062, 0.44), pants, Vector3(0, -0.2, 0))
		var ankle := _pivot(knee, Vector3(0, -0.42, 0))
		_part(ankle, _box(Vector3(0.11, 0.09, 0.24)), boots, Vector3(0, -0.035, -0.04))
		_part(ankle, _cylinder(0.07, 0.07, 0.12), boots, Vector3(0, 0.04, 0))
		if side < 0:
			shoulder_l = shoulder
			elbow_l = elbow
			hip_l = hip
			knee_l = knee
			ankle_l = ankle
		else:
			shoulder_r = shoulder
			elbow_r = elbow
			hip_r = hip
			knee_r = knee
			ankle_r = ankle
			hand_attach = _pivot(hand, Vector3(0, -0.06, 0))

	back_attach = _pivot(spine, Vector3(0, 0.3, 0.16))
	for accessory in look.get("accessories", []):
		_add_accessory(accessory, hair, shirt)


func _add_accessory(kind: String, hair: Color, shirt: Color) -> void:
	match kind:
		"beard":
			_part(head, _box(Vector3(0.2, 0.09, 0.08)), hair, Vector3(0, 0.05, -0.08))
		"long_beard":
			_part(head, _box(Vector3(0.18, 0.22, 0.07)), hair, Vector3(0, -0.01, -0.1))
		"cap":
			_part(head, _cylinder(0.135, 0.14, 0.08), Color(0.25, 0.35, 0.25), Vector3(0, 0.24, 0))
			_part(head, _box(Vector3(0.2, 0.02, 0.12)), Color(0.22, 0.3, 0.22), Vector3(0, 0.21, -0.15))
		"straw_hat":
			_part(head, _cylinder(0.3, 0.3, 0.02), Color(0.85, 0.75, 0.45), Vector3(0, 0.22, 0))
			_part(head, _cylinder(0.11, 0.14, 0.12), Color(0.85, 0.75, 0.45), Vector3(0, 0.28, 0))
		"hood":
			var hood := _part(head, _hemisphere(0.165), shirt.darkened(0.15), Vector3(0, 0.11, 0.03))
			hood.scale = Vector3(1, 1.3, 1.1)
		"apron":
			_part(spine, _box(Vector3(0.3, 0.6, 0.02)), Color(0.4, 0.28, 0.17), Vector3(0, 0.12, -0.18))
		"bun":
			_part(head, _sphere(0.07, 0.14), hair, Vector3(0, 0.2, 0.12))
		# --- Valdoria (medieval) ---
		"crown":
			var gold := Color(1.0, 0.8, 0.25)
			_part(head, _cylinder(0.14, 0.14, 0.07), gold, Vector3(0, 0.25, 0))
			for i in 5:
				var angle := TAU * i / 5.0
				_part(head, _box(Vector3(0.04, 0.07, 0.03)), gold, Vector3(sin(angle) * 0.13, 0.31, cos(angle) * 0.13), Vector3(0, angle, 0))
			_part(head, _sphere(0.025, 0.05), Color(0.85, 0.1, 0.2), Vector3(0, 0.26, -0.14))
		"helmet":
			var steel := Color(0.6, 0.62, 0.66)
			_part(head, _hemisphere(0.15), steel, Vector3(0, 0.15, 0.0))
			_part(head, _cylinder(0.152, 0.152, 0.05), steel.darkened(0.15), Vector3(0, 0.16, 0))
			_part(head, _box(Vector3(0.025, 0.1, 0.02)), steel, Vector3(0, 0.11, -0.14))
		"chainmail":
			_part(spine, _cylinder(0.205, 0.17, 0.5), Color(0.55, 0.57, 0.6), Vector3(0, 0.25, 0))
			_part(spine, _box(Vector3(0.24, 0.42, 0.02)), shirt, Vector3(0, 0.24, -0.2))  # sobreveste
		"cape_red", "cape_blue":
			var cloth := Color(0.65, 0.1, 0.12) if kind == "cape_red" else Color(0.15, 0.25, 0.55)
			var cape := _part(spine, _box(Vector3(0.46, 1.0, 0.03)), cloth, Vector3(0, 0.0, 0.17))
			cape.rotation.x = 0.08
		"dress":
			_part(hips, _cylinder(0.2, 0.33, 0.85), shirt.darkened(0.1), Vector3(0, -0.4, 0))
		"bandana":
			_part(head, _box(Vector3(0.24, 0.09, 0.05)), Color(0.45, 0.1, 0.1), Vector3(0, 0.07, -0.11))
		"sword":
			_part(hand_attach, _box(Vector3(0.04, 0.04, 0.18)), Color(0.35, 0.24, 0.15), Vector3(0, 0, -0.02))
			_part(hand_attach, _box(Vector3(0.2, 0.04, 0.04)), Color(0.45, 0.38, 0.2), Vector3(0, 0, -0.12))
			_part(hand_attach, _box(Vector3(0.07, 0.015, 0.75)), Color(0.75, 0.77, 0.8), Vector3(0, 0, -0.5))
		"spear":
			_part(hand_attach, _box(Vector3(0.04, 0.04, 1.8)), Color(0.45, 0.3, 0.18), Vector3(0, 0, -0.5))
			_part(hand_attach, _cylinder(0.0, 0.05, 0.25), Color(0.7, 0.72, 0.76), Vector3(0, 0, -1.5), Vector3(-PI / 2, 0, 0))


# --- Animación ------------------------------------------------------------------------

func play_swing() -> void:
	_swing_t = 0.0


func _process(delta: float) -> void:
	if hips == null:
		return
	_time += delta
	var speed := move_speed
	_walk_blend = move_toward(_walk_blend, clampf(speed / 3.5, 0.0, 1.0), delta * 6.0)
	var walk := _walk_blend
	var run := clampf((speed - 5.5) / 2.5, 0.0, 1.0)
	var stride := lerpf(1.1, 1.9, run)
	if speed > 0.05:
		var previous_half := int(_phase / PI)
		_phase = fmod(_phase + delta * speed / stride * PI, TAU)
		if int(_phase / PI) != previous_half and grounded and speed > 1.0:
			step.emit()

	_air = move_toward(_air, 0.0 if grounded else 1.0, delta * 7.0)
	if grounded and not _was_grounded:
		_land = 1.0
	_was_grounded = grounded
	_land = move_toward(_land, 0.0, delta * 4.5)
	_busy_blend = move_toward(_busy_blend, 1.0 if busy and walk < 0.3 else 0.0, delta * 4.0)

	var s := sin(_phase)
	var c := cos(_phase)
	var ground := 1.0 - _air
	var hunch := clampf(load_ratio - 0.4, 0.0, 0.9) * 0.35
	var breathe := sin(_time * 1.8)
	var rising := 1.0 if vertical_speed > 0.0 else 0.0

	# Piernas
	var leg_amp := lerpf(0.5, 0.9, run) * walk * ground
	var knee_amp := lerpf(0.7, 1.4, run) * walk * ground
	var knee_base := 0.08 + run * 0.15 * walk
	hip_l.rotation.x = s * leg_amp + _air * lerpf(0.25, 0.7, rising) + _land * 0.45
	hip_r.rotation.x = -s * leg_amp + _air * lerpf(0.05, -0.15, rising) + _land * 0.45
	knee_l.rotation.x = -(maxf(0.0, c) * knee_amp + knee_base + _air * lerpf(0.4, 1.1, rising) + _land * 0.9)
	knee_r.rotation.x = -(maxf(0.0, -c) * knee_amp + knee_base + _air * 0.35 + _land * 0.9)
	ankle_l.rotation.x = -(hip_l.rotation.x + knee_l.rotation.x) * 0.6
	ankle_r.rotation.x = -(hip_r.rotation.x + knee_r.rotation.x) * 0.6

	# Cadera: sube y baja con los pasos, gira un poco y se agacha al aterrizar.
	hips.position.y = HIP_HEIGHT - absf(s) * lerpf(0.025, 0.06, run) * walk * ground \
		- _land * 0.16 - hunch * 0.1 + breathe * 0.004 * (1.0 - walk)
	hips.rotation.y = s * 0.12 * walk * ground

	# Torso: se inclina al correr, al cargar mucho peso y en el aire.
	spine.rotation.x = -(run * 0.28 + walk * 0.05 + hunch + _land * 0.15 + _air * 0.08) \
		+ breathe * 0.015 * (1.0 - walk)
	spine.rotation.y = -s * 0.2 * walk * ground
	head.rotation.x = run * 0.2 + hunch * 0.6 + _land * 0.1
	head.rotation.y = sin(_time * 0.35) * 0.15 * (1.0 - walk) * (1.0 - _busy_blend)

	# Brazos: se balancean al revés que las piernas; en el aire se abren.
	var arm_amp := lerpf(0.4, 1.0, run) * walk * ground
	var elbow_base := lerpf(0.15, 1.35, run * walk) + 0.05
	shoulder_l.rotation.x = -s * arm_amp + _air * 0.35 * rising
	shoulder_r.rotation.x = s * arm_amp + _air * 0.35 * rising + (0.15 if holding_item else 0.0)
	shoulder_l.rotation.z = -0.07 - _air * lerpf(0.9, 0.5, rising) - breathe * 0.01
	shoulder_r.rotation.z = 0.07 + _air * lerpf(0.9, 0.5, rising) + breathe * 0.01
	elbow_l.rotation.x = elbow_base + maxf(0.0, s) * 0.35 * walk + _air * 0.5
	elbow_r.rotation.x = elbow_base + maxf(0.0, -s) * 0.35 * walk + _air * 0.5 + (0.35 if holding_item else 0.0)

	# Fabricando: manos al frente trabajando.
	if _busy_blend > 0.0:
		var work := sin(_time * 9.0) * 0.12
		shoulder_l.rotation.x = lerpf(shoulder_l.rotation.x, 0.75 + work, _busy_blend)
		shoulder_r.rotation.x = lerpf(shoulder_r.rotation.x, 0.75 - work, _busy_blend)
		elbow_l.rotation.x = lerpf(elbow_l.rotation.x, 1.0, _busy_blend)
		elbow_r.rotation.x = lerpf(elbow_r.rotation.x, 1.0, _busy_blend)
		head.rotation.x = lerpf(head.rotation.x, 0.35, _busy_blend)

	# Golpe con la herramienta (sobrescribe el brazo derecho).
	if _swing_t >= 0.0:
		_swing_t += delta / SWING_DURATION
		if _swing_t >= 1.0:
			_swing_t = -1.0
		else:
			var weight := minf(1.0, minf(_swing_t * 6.0, (1.0 - _swing_t) * 4.0))
			shoulder_r.rotation.x = lerpf(shoulder_r.rotation.x, _swing_angle(_swing_t), weight)
			shoulder_r.rotation.z = lerpf(shoulder_r.rotation.z, 0.25, weight)
			elbow_r.rotation.x = lerpf(elbow_r.rotation.x, 0.25 if _swing_t > 0.35 else 0.9, weight)
			spine.rotation.y += sin(_swing_t * PI) * -0.35
			spine.rotation.x -= (0.2 if _swing_t > 0.35 else -0.05) * weight


func _swing_angle(t: float) -> float:
	if t < 0.35:
		return lerpf(0.3, 2.8, ease(t / 0.35, 0.6))  # Levanta el brazo.
	if t < 0.6:
		return lerpf(2.8, 0.35, (t - 0.35) / 0.25)  # Golpe hacia abajo.
	return 0.35


# --- Construcción de piezas -----------------------------------------------------------

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


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 10
	m.rings = 3
	return m


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 10
	m.rings = 1
	return m


static func _sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 6
	return m


static func _hemisphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius
	m.is_hemisphere = true
	m.radial_segments = 12
	m.rings = 4
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Apariencia variada para cada jugador según su id de red.
static func look_for_player(peer_id: int) -> Dictionary:
	var skins := [Color(0.96, 0.8, 0.67), Color(0.87, 0.68, 0.52), Color(0.7, 0.5, 0.36), Color(0.5, 0.35, 0.24), Color(0.36, 0.25, 0.18)]
	var hairs := [Color(0.12, 0.09, 0.07), Color(0.35, 0.22, 0.12), Color(0.7, 0.5, 0.25), Color(0.55, 0.2, 0.1), Color(0.2, 0.2, 0.22)]
	var pants := [Color(0.22, 0.27, 0.38), Color(0.3, 0.28, 0.22), Color(0.2, 0.2, 0.2), Color(0.35, 0.3, 0.25)]
	var h := absi(hash(peer_id))
	return {
		"skin": skins[h % skins.size()],
		"hair": hairs[(h / 7) % hairs.size()],
		"shirt": Color.from_hsv(fmod(peer_id * 0.618034, 1.0), 0.5, 0.75),
		"pants": pants[(h / 13) % pants.size()],
		"boots": Color(0.3, 0.21, 0.14),
	}
