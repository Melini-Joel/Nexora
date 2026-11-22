class_name TouchControls
extends CanvasLayer
## Controles táctiles para celular (se activan solos en Android, o desde Opciones → Cámara).
##
##   · Mitad izquierda de la pantalla: joystick para moverse (aparece donde apoyás el dedo).
##   · Deslizar el dedo en el resto de la pantalla: girar la cámara.
##   · Botones a la derecha: golpear (mantener), usar, saltar y correr.
##   · Botones a la izquierda: pausa, mochila, mapa, personaje y cámara.
##   · Con el martillo en la mano: cambiar de pieza y desarmar.
##   · En las cinemáticas: saltear escena.
## Los botones disparan las mismas acciones que el teclado, así el resto del juego no cambia.

const JOY_RADIUS := 95.0
const JOY_ZONE := 0.42  ## Parte izquierda de la pantalla donde se puede apoyar el joystick.

## id -> [texto, acción, esquina ("br" abajo-der., "tl" arriba-izq., "tr" arriba-der.), posición, radio, modo]
## modo: "hold" (mientras se toca), "tap" (un toque) o "toggle" (prende / apaga)
const BUTTONS := {
	"attack": ["Golpear", "attack", "br", Vector2(-140, -330), 78.0, "hold"],
	"interact": ["Usar", "interact", "br", Vector2(-300, -262), 58.0, "hold"],
	"jump": ["Saltar", "jump", "br", Vector2(-292, -425), 56.0, "hold"],
	"sprint": ["Correr", "sprint", "br", Vector2(-140, -500), 48.0, "toggle"],
	"rotate": ["Pieza", "build_rotate", "br", Vector2(-440, -370), 44.0, "tap"],
	"demolish": ["Desarmar", "secondary", "br", Vector2(-450, -225), 44.0, "tap"],
	"pause": ["≡", "pause", "tl", Vector2(62, 120), 36.0, "tap"],
	"inventory": ["Mochila", "inventory", "tl", Vector2(62, 205), 36.0, "tap"],
	"map": ["Mapa", "map", "tl", Vector2(62, 290), 36.0, "tap"],
	"character": ["Pers.", "character", "tl", Vector2(62, 375), 36.0, "tap"],
	"camera": ["Cám.", "camera_toggle", "tl", Vector2(62, 460), 36.0, "tap"],
	"skip": ["Saltear ▸", "skip_cinematic", "tr", Vector2(-110, 70), 46.0, "tap"],
}
const MENU_BUTTONS := ["pause", "inventory", "map", "character", "camera"]
const MOVE_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]

var _view: TouchView
var _touches: Dictionary = {}  ## índice del dedo -> "joy" | "look" | id de botón
var _joy_center := Vector2.ZERO
var _joy_vector := Vector2.ZERO
var _pressed: Dictionary = {}  ## botones apretados ahora
var _sprint_on := false
var _mouse_fallback := false  ## En PC sin pantalla táctil, el mouse simula el dedo (para probar).


## Dibuja el joystick y los botones.
class TouchView extends Control:
	var owner_controls: TouchControls

	func _draw() -> void:
		var c := owner_controls
		var font := ThemeDB.fallback_font
		if c._touches.values().has("joy"):
			draw_circle(c._joy_center, JOY_RADIUS, Color(0, 0, 0, 0.25))
			draw_arc(c._joy_center, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.45), 3.0, true)
			draw_circle(c._joy_center + c._joy_vector * JOY_RADIUS, 38.0, Color(1, 1, 1, 0.55))
		else:
			var hint := Vector2(size.x * 0.16, size.y * 0.74)
			draw_arc(hint, JOY_RADIUS * 0.8, 0, TAU, 40, Color(1, 1, 1, 0.18), 2.0, true)
			draw_string(font, hint + Vector2(-40, 6), "Mover", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, Color(1, 1, 1, 0.3))
		for id: String in BUTTONS:
			if not c._is_visible(id):
				continue
			var data: Array = BUTTONS[id]
			var center := c._button_center(id)
			var radius: float = data[4]
			var active: bool = c._pressed.has(id) or (id == "sprint" and c._sprint_on)
			draw_circle(center, radius, Color(1.0, 0.75, 0.35, 0.55) if active else Color(0.05, 0.07, 0.09, 0.5))
			draw_arc(center, radius, 0, TAU, 36, Color(1, 0.9, 0.7, 0.75 if active else 0.45), 2.5, true)
			var text: String = data[0]
			var font_size := 22 if radius >= 56.0 else (17 if text.length() > 2 else 30)
			draw_string(font, center + Vector2(-radius, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color(1, 1, 1, 0.95))


func _ready() -> void:
	layer = 28
	_view = TouchView.new()
	_view.owner_controls = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	Settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = Settings.touch_enabled()
	_mouse_fallback = not Settings.is_mobile() and not DisplayServer.is_touchscreen_available()
	if not visible:
		_release_all()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Si se abrió un menú o una ventana, se sueltan los controles de movimiento.
	if not _gameplay_active():
		for index in _touches.keys():
			if _touches[index] == "joy" or _touches[index] == "look":
				_touches.erase(index)
		_set_joystick(Vector2.ZERO)
		if _sprint_on:
			_sprint_on = false
			Input.action_release("sprint")
	elif _touches.values().has("joy"):
		_set_joystick(_joy_vector)  # Se reaplica cada cuadro (por si el sistema soltó las teclas).
	_view.queue_redraw()


# --- Estado -------------------------------------------------------------------------------

func _gameplay_active() -> bool:
	return Game.local_player != null and not Cinematics.playing and Game.can_act()


func _is_visible(id: String) -> bool:
	if Game.local_player == null or Game.ui_open or Game.dialog_open:
		return false
	if Cinematics.playing:
		return id == "skip"
	if id == "skip":
		return false
	if id in MENU_BUTTONS:
		return true
	if not Game.can_act():
		return false
	if id in ["rotate", "demolish"]:
		return Game.get_selected_item() == "hammer"
	return true


func _button_center(id: String) -> Vector2:
	var data: Array = BUTTONS[id]
	var size := _view.size
	var offset: Vector2 = data[3]
	match data[2]:
		"br":
			return size + offset
		"tr":
			return Vector2(size.x + offset.x, offset.y)
	return offset


func _button_at(pos: Vector2) -> String:
	for id: String in BUTTONS:
		if _is_visible(id) and pos.distance_to(_button_center(id)) <= float(BUTTONS[id][4]) + 10.0:
			return id
	return ""


# --- Toques -------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_on_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
	elif _mouse_fallback and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_on_touch(-1, event.position, event.pressed)
	elif _mouse_fallback and event is InputEventMouseMotion and _touches.has(-1):
		_on_drag(-1, event.position, event.relative)


## Las posiciones de los eventos vienen en pixeles de la ventana: se pasan a la escala de la interfaz.
func _to_canvas(pos: Vector2) -> Vector2:
	return _view.get_global_transform_with_canvas().affine_inverse() * pos


func _on_touch(index: int, screen_pos: Vector2, pressed: bool) -> void:
	var pos := _to_canvas(screen_pos)
	if pressed:
		var id := _button_at(pos)
		if id != "":
			_touches[index] = id
			_press_button(id)
		elif _gameplay_active() and pos.x < _view.size.x * JOY_ZONE and pos.y > _view.size.y * 0.3:
			_touches[index] = "joy"
			_joy_center = pos
			_set_joystick(Vector2.ZERO)
		elif _gameplay_active():
			_touches[index] = "look"
		return
	var role: String = _touches.get(index, "")
	_touches.erase(index)
	if role == "joy":
		_set_joystick(Vector2.ZERO)
	elif BUTTONS.has(role):
		_release_button(role)


func _on_drag(index: int, screen_pos: Vector2, screen_relative: Vector2) -> void:
	var role: String = _touches.get(index, "")
	if role == "joy":
		var offset := _to_canvas(screen_pos) - _joy_center
		if offset.length() > JOY_RADIUS:
			_joy_center += offset - offset.normalized() * JOY_RADIUS  # El joystick sigue al dedo.
			offset = offset.normalized() * JOY_RADIUS
		_set_joystick(offset / JOY_RADIUS)
	elif role == "look" and Game.local_player and _gameplay_active():
		Game.local_player.apply_look(screen_relative, Settings.touch_sensitivity())


func _set_joystick(vector: Vector2) -> void:
	_joy_vector = vector
	var dead := 0.15
	var strengths := {
		"move_left": maxf(0.0, -vector.x), "move_right": maxf(0.0, vector.x),
		"move_forward": maxf(0.0, -vector.y), "move_back": maxf(0.0, vector.y),
	}
	for action: String in MOVE_ACTIONS:
		var strength: float = strengths[action]
		if strength > dead:
			Input.action_press(action, clampf((strength - dead) / (1.0 - dead), 0.0, 1.0))
		else:
			Input.action_release(action)


# --- Botones ------------------------------------------------------------------------------

func _press_button(id: String) -> void:
	var data: Array = BUTTONS[id]
	var action: String = data[1]
	match data[5]:
		"toggle":
			_sprint_on = not _sprint_on
			_send_action(action, _sprint_on)
		"tap":
			_pressed[id] = true
			_send_action(action, true)
			_send_action(action, false)
		_:
			_pressed[id] = true
			_send_action(action, true)


func _release_button(id: String) -> void:
	_pressed.erase(id)
	if BUTTONS[id][5] == "hold":
		_send_action(BUTTONS[id][1], false)


## Igual que apretar o soltar la tecla: llega a todos los scripts que leen esa acción.
func _send_action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _release_all() -> void:
	for index in _touches.keys():
		var role: String = _touches[index]
		if BUTTONS.has(role):
			_release_button(role)
	_touches.clear()
	_set_joystick(Vector2.ZERO)
	if _sprint_on:
		_sprint_on = false
		_send_action("sprint", false)
