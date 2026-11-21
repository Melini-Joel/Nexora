extends Node
## Reproductor de cinemáticas: planos de cámara con movimiento suave, barras negras y subtítulos.
## Mientras se reproduce, el jugador no se puede mover y el HUD se oculta.
## Se puede saltear con Esc, Enter o Espacio.
##
## Cada plano es un Dictionary:
##   {
##     "from": Vector3, "to": Vector3,            # posición de la cámara (inicio → fin)
##     "look_from": Vector3, "look_to": Vector3,  # punto al que mira (inicio → fin, "look_to" es opcional)
##     "duration": float, "text": String          # duración en segundos y subtítulo
##   }

signal started
signal finished

const BAR_SIZE := 0.11  ## Alto de cada barra negra (fracción de la pantalla).

var playing := false

var _camera: Camera3D
var _previous_camera: Camera3D
var _layer: CanvasLayer
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _fade: ColorRect
var _subtitle: Label
var _tween: Tween


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)

	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.visible = false
	add_child(_layer)

	_fade = _make_rect(0.0, 0.0, 1.0, 1.0)
	_fade.color = Color(0, 0, 0, 0)
	_top_bar = _make_rect(0.0, 0.0, 1.0, 0.0)
	_bottom_bar = _make_rect(0.0, 1.0, 1.0, 1.0)

	_subtitle = Label.new()
	_subtitle.anchor_left = 0.1
	_subtitle.anchor_right = 0.9
	_subtitle.anchor_top = 1.0 - BAR_SIZE
	_subtitle.anchor_bottom = 1.0
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_layer.add_child(_subtitle)

	var hint := Label.new()
	hint.text = "Esc / Enter: saltear"
	hint.anchor_left = 0.8
	hint.anchor_right = 0.98
	hint.anchor_top = 0.015
	hint.anchor_bottom = 0.08
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.5)
	_layer.add_child(hint)


func _make_rect(left: float, top: float, right: float, bottom: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.anchor_left = left
	rect.anchor_top = top
	rect.anchor_right = right
	rect.anchor_bottom = bottom
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(rect)
	return rect


func play(shots: Array) -> void:
	if shots.is_empty():
		return
	if playing:
		stop()
	playing = true
	_previous_camera = get_viewport().get_camera_3d()
	_apply_shot(0.0, shots[0])
	_camera.make_current()
	_subtitle.text = ""
	_layer.visible = true
	started.emit()

	_tween = create_tween()
	# Entrada: fundido desde negro y barras.
	_tween.tween_property(_fade, "color:a", 0.0, 1.0).from(1.0)
	_tween.parallel().tween_property(_top_bar, "anchor_bottom", BAR_SIZE, 0.6)
	_tween.parallel().tween_property(_bottom_bar, "anchor_top", 1.0 - BAR_SIZE, 0.6)
	for shot in shots:
		_tween.tween_callback(_set_subtitle.bind(shot.get("text", "")))
		_tween.tween_method(_apply_shot.bind(shot), 0.0, 1.0, shot.get("duration", 4.0)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Salida: fundido a negro y vuelta a la cámara del jugador.
	_tween.tween_callback(_set_subtitle.bind(""))
	_tween.tween_property(_fade, "color:a", 1.0, 0.5)
	_tween.tween_callback(_finish)


func stop() -> void:
	if not playing:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_finish()


func _finish() -> void:
	playing = false
	_layer.visible = false
	_fade.color.a = 0.0
	_top_bar.anchor_bottom = 0.0
	_bottom_bar.anchor_top = 1.0
	_camera.clear_current(false)
	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	finished.emit()


func _set_subtitle(text: String) -> void:
	_subtitle.text = text


func _apply_shot(t: float, shot: Dictionary) -> void:
	var from: Vector3 = shot["from"]
	var to: Vector3 = shot.get("to", from)
	var look_from: Vector3 = shot["look_from"]
	var look_to: Vector3 = shot.get("look_to", look_from)
	var position := from.lerp(to, t)
	var target := look_from.lerp(look_to, t)
	if position.is_equal_approx(target):
		return
	_camera.global_position = position
	_camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if playing and event.is_action_pressed("skip_cinematic"):
		get_viewport().set_input_as_handled()
		stop()
