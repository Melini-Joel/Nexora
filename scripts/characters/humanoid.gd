class_name Humanoid
extends Node3D
## Personaje con modelo 3D y esqueleto (models/*.glb) y animaciones procedurales sobre sus
## articulaciones (cadera, columna, cabeza, hombros, codos, manos, caderas, rodillas y tobillos):
##   quieto (respiración), caminar, correr, saltar, caer, aterrizar, golpear,
##   fabricar y caminar encorvado cuando la mochila pesa mucho.
##
## Las animaciones se calculan por código a partir de la velocidad y el estado, así
## funcionan igual para el jugador local, los compañeros por red y los NPCs.
## Los modelos se generan con tools/gen_characters.py (Blender) y se pueden retocar en Blender
## mientras mantengan los nombres de los huesos.

const MODELS := {
	"humanoid": preload("res://models/humanoid.glb"),
	"shade": preload("res://models/shade.glb"),
	"brute": preload("res://models/brute.glb"),
}

static var _material_cache: Dictionary = {}

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
var _skeleton: Skeleton3D
var _joints: Dictionary = {}  ## índice de hueso -> articulación (Node3D)
var _hips_bone := -1
var _hip_height := 0.92
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


## Arma el cuerpo con un modelo 3D (models/*.glb, ver tools/gen_characters.py).
## look: {"model", "skin", "hair", "shirt", "pants", "boots", "accessories": [...]}
##   model: "humanoid" (por defecto), "shade" (sombra) o "brute" (bruto sombrío)
## Las articulaciones (hips, spine, head, shoulder_l...) se arman a partir del esqueleto del
## modelo: la animación por código las mueve y en cada cuadro se copian a los huesos.
func build(look: Dictionary) -> void:
	var model: String = look.get("model", "humanoid")
	var scene: Node3D = (MODELS.get(model, MODELS["humanoid"]) as PackedScene).instantiate()
	scene.name = "Model"
	add_child(scene)
	_skeleton = scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D

	# Una articulación (Node3D) por hueso, en la posición de reposo del esqueleto.
	var to_self := Transform3D.IDENTITY
	var node: Node = _skeleton
	while node != self:
		to_self = (node as Node3D).transform * to_self
		node = node.get_parent()
	for i in _skeleton.get_bone_count():
		var pivot := Node3D.new()
		pivot.name = "Joint_" + _skeleton.get_bone_name(i)
		var parent := _skeleton.get_bone_parent(i)
		if parent < 0:
			pivot.position = to_self * _skeleton.get_bone_rest(i).origin
			add_child(pivot)
		else:
			pivot.position = _skeleton.get_bone_rest(i).origin
			(_joints[parent] as Node3D).add_child(pivot)
		_joints[i] = pivot
	hips = _joint("hips")
	spine = _joint("spine")
	head = _joint("head")
	shoulder_l = _joint("shoulder_l")
	shoulder_r = _joint("shoulder_r")
	elbow_l = _joint("elbow_l")
	elbow_r = _joint("elbow_r")
	hip_l = _joint("hip_l")
	hip_r = _joint("hip_r")
	knee_l = _joint("knee_l")
	knee_r = _joint("knee_r")
	ankle_l = _joint("ankle_l")
	ankle_r = _joint("ankle_r")
	_hips_bone = _skeleton.find_bone("hips")
	_hip_height = hips.position.y
	hand_attach = _pivot(_joint("hand_r"), Vector3(0, -0.06, 0))
	# Mochila: en la espalda, a media altura entre la cintura y el cuello (sirve para cualquier proporción).
	back_attach = _pivot(spine, Vector3(0, head.position.y * 0.45, 0.17))

	# Colores de este personaje y accesorios visibles.
	var accessories: Array = look.get("accessories", [])
	var colors := {
		"Skin": look.get("skin", Color(0.9, 0.74, 0.6)), "Hair": look.get("hair", Color(0.25, 0.17, 0.1)),
		"Shirt": look.get("shirt", Color(0.3, 0.5, 0.8)), "Pants": look.get("pants", Color(0.25, 0.27, 0.32)),
		"Boots": look.get("boots", Color(0.28, 0.2, 0.14)),
		"Cape": Color(0.15, 0.25, 0.55) if accessories.has("cape_blue") else Color(0.62, 0.1, 0.12),
	}
	for mesh_instance in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var mesh_name := String(mi.name)
		if mesh_name.begins_with("acc_"):
			mi.visible = _shows_accessory(mesh_name.trim_prefix("acc_"), accessories, model)
		if model == "humanoid":
			_recolor(mi, colors)
	for accessory in accessories:
		if accessory in ["sword", "spear"]:
			_add_weapon(accessory)
	_sync_bones()


func _joint(bone: String) -> Node3D:
	return _joints.get(_skeleton.find_bone(bone)) as Node3D


static func _shows_accessory(id: String, accessories: Array, model: String) -> bool:
	if model != "humanoid":
		return true  # Las sombras muestran todo lo suyo (jirones...).
	match id:
		"hair_short":
			return not accessories.has("hair_long") and not accessories.has("bald")
		"cape":
			return accessories.has("cape_red") or accessories.has("cape_blue")
	return accessories.has(id)


## Pinta las partes Skin, Hair, Shirt, Pants, Boots y Cape con los colores del personaje.
static func _recolor(mi: MeshInstance3D, colors: Dictionary) -> void:
	for i in mi.mesh.get_surface_count():
		var material := mi.mesh.surface_get_material(i)
		if material == null or not colors.has(material.resource_name):
			continue
		var color: Color = colors[material.resource_name]
		var key := "%s_%s" % [material.resource_name, color.to_html()]
		if not _material_cache.has(key):
			var copy := material.duplicate() as BaseMaterial3D
			copy.albedo_color = color
			_material_cache[key] = copy
		mi.set_surface_override_material(i, _material_cache[key])


## Armas que lleva en la mano (guardias y bandidos).
func _add_weapon(kind: String) -> void:
	match kind:
		"sword":
			_part(hand_attach, _box(Vector3(0.04, 0.04, 0.18)), Color(0.35, 0.24, 0.15), Vector3(0, 0, -0.02))
			_part(hand_attach, _box(Vector3(0.2, 0.04, 0.04)), Color(0.45, 0.38, 0.2), Vector3(0, 0, -0.12))
			_part(hand_attach, _box(Vector3(0.07, 0.015, 0.75)), Color(0.75, 0.77, 0.8), Vector3(0, 0, -0.5))
		"spear":
			_part(hand_attach, _box(Vector3(0.04, 0.04, 1.8)), Color(0.45, 0.3, 0.18), Vector3(0, 0, -0.5))
			_part(hand_attach, _cylinder(0.0, 0.05, 0.25), Color(0.7, 0.72, 0.76), Vector3(0, 0, -1.5), Vector3(-PI / 2, 0, 0))


## Copia las articulaciones animadas a los huesos del modelo.
func _sync_bones() -> void:
	for i: int in _joints:
		_skeleton.set_bone_pose_rotation(i, (_joints[i] as Node3D).quaternion)
	if _hips_bone >= 0:
		_skeleton.set_bone_pose_position(_hips_bone, hips.position)


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
	hips.position.y = _hip_height - absf(s) * lerpf(0.025, 0.06, run) * walk * ground \
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
	_sync_bones()


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
		"accessories": [["hair_long"], [], ["beard"], [], ["hair_long", "bun"]][(h / 17) % 5],
	}
