extends Node
## Reproductor de cinemáticas: planos de cámara con movimiento suave, barras negras,
## subtítulos, textos sobre fondo negro, sacudones y destellos.
## Mientras se reproduce, el jugador no se puede mover y el HUD se oculta.
## Se puede saltear con Esc, Enter o Espacio.
##
## Cada plano es un Dictionary. Plano de cámara:
##   {
##     "from": Vector3, "to": Vector3,            # posición de la cámara (inicio → fin)
##     "look_from": Vector3, "look_to": Vector3,  # punto al que mira ("look_to" es opcional)
##     "duration": float, "text": String,         # duración en segundos y subtítulo
##     "follow": Node3D,                          # opcional: las posiciones son relativas a este nodo
##     "shake": float,                            # opcional: sacudón de cámara (0..1)
##     "callback": Callable,                      # opcional: se llama al empezar el plano
##     "fade_in": bool, "fade_out": bool          # opcional: fundido desde / hacia negro
##   }
## Placa de texto (pantalla negra): {"card": "texto", "duration": float, "callback": Callable}

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
var _flash_rect: ColorRect
var _subtitle: Label
var _card: Label
var _tween: Tween
var _shake := 0.0
var _shake_time := 0.0


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.far = 900.0
	add_child(_camera)

	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.visible = false
	add_child(_layer)

	_top_bar = _make_rect(0.0, 0.0, 1.0, 0.0)
	_bottom_bar = _make_rect(0.0, 1.0, 1.0, 1.0)
	_fade = _make_rect(0.0, 0.0, 1.0, 1.0)
	_fade.color = Color(0, 0, 0, 0)
	_flash_rect = _make_rect(0.0, 0.0, 1.0, 1.0)
	_flash_rect.color = Color(0.85, 0.9, 1.0, 0.0)

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

	_card = Label.new()
	_card.anchor_left = 0.15
	_card.anchor_right = 0.85
	_card.anchor_top = 0.3
	_card.anchor_bottom = 0.7
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = 1
	font.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)  # cursiva
	_card.add_theme_font_override("font", font)
	_card.add_theme_font_size_override("font_size", 34)
	_card.add_theme_color_override("font_color", Color(0.93, 0.88, 0.78))
	_card.modulate.a = 0.0
	_layer.add_child(_card)

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


## La cámara de las cinemáticas (para efectos que la siguen, como la lluvia).
func get_camera() -> Camera3D:
	return _camera


func play(shots: Array) -> void:
	if shots.is_empty():
		return
	if playing:
		stop()
	playing = true
	_previous_camera = get_viewport().get_camera_3d()
	var first_camera_shot: Dictionary = {}
	for shot in shots:
		if not shot.has("card"):
			first_camera_shot = shot
			break
	if not first_camera_shot.is_empty():
		_apply_shot(0.0, first_camera_shot)
	_camera.make_current()
	_subtitle.text = ""
	_card.modulate.a = 0.0
	_layer.visible = true
	started.emit()

	_tween = create_tween()
	# Entrada: fundido desde negro y barras.
	_tween.tween_property(_fade, "color:a", 0.0, 1.0).from(1.0)
	_tween.parallel().tween_property(_top_bar, "anchor_bottom", BAR_SIZE, 0.6)
	_tween.parallel().tween_property(_bottom_bar, "anchor_top", 1.0 - BAR_SIZE, 0.6)
	for shot in shots:
		var duration: float = shot.get("duration", 4.0)
		if shot.has("callback"):
			_tween.tween_callback(shot["callback"])
		if shot.has("card"):
			# Placa de texto sobre negro.
			_tween.tween_callback(_set_subtitle.bind(""))
			_tween.tween_property(_fade, "color:a", 1.0, 0.6)
			_tween.tween_callback(func(): _card.text = shot["card"])
			_tween.tween_property(_card, "modulate:a", 1.0, 0.8)
			_tween.tween_interval(maxf(0.5, duration - 2.2))
			_tween.tween_property(_card, "modulate:a", 0.0, 0.8)
			continue
		if shot.get("fade_in", false) or _fade_is_black_before(shots, shot):
			_tween.tween_callback(_apply_shot.bind(0.0, shot))
			_tween.tween_property(_fade, "color:a", 0.0, 0.9)
		_tween.tween_callback(_set_subtitle.bind(shot.get("text", "")))
		_tween.tween_callback(func(): _shake = shot.get("shake", 0.0))
		if shot.get("fade_out", false):
			_tween.tween_method(_apply_shot.bind(shot), 0.0, 1.0, duration) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.parallel().tween_property(_fade, "color:a", 1.0, 0.9).set_delay(maxf(0.0, duration - 0.9))
		else:
			_tween.tween_method(_apply_shot.bind(shot), 0.0, 1.0, duration) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Salida: fundido a negro y vuelta a la cámara del jugador.
	_tween.tween_callback(_set_subtitle.bind(""))
	_tween.tween_callback(func(): _shake = 0.0)
	_tween.tween_property(_fade, "color:a", 1.0, 0.5)
	_tween.tween_callback(_finish)


## Un plano que viene después de una placa de texto o de un fundido a negro arranca desde negro.
func _fade_is_black_before(shots: Array, shot: Dictionary) -> bool:
	var index := shots.find(shot)
	if index <= 0:
		return false
	var previous: Dictionary = shots[index - 1]
	return previous.has("card") or previous.get("fade_out", false)


func stop() -> void:
	if not playing:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_finish()


## Destello blanco (rayos, impactos).
func flash(strength: float = 0.8) -> void:
	var tween := create_tween()
	tween.tween_property(_flash_rect, "color:a", strength, 0.05)
	tween.tween_property(_flash_rect, "color:a", 0.0, 0.35)


func shake(amount: float) -> void:
	_shake = amount


func _finish() -> void:
	playing = false
	_shake = 0.0
	_layer.visible = false
	_fade.color.a = 0.0
	_flash_rect.color.a = 0.0
	_card.modulate.a = 0.0
	_top_bar.anchor_bottom = 0.0
	_bottom_bar.anchor_top = 1.0
	_camera.clear_current(false)
	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	finished.emit()


func _set_subtitle(text: String) -> void:
	_subtitle.text = text


func _apply_shot(t: float, shot: Dictionary) -> void:
	var base := Vector3.ZERO
	var follow: Variant = shot.get("follow", null)
	if is_instance_valid(follow) and follow is Node3D:
		base = follow.global_position
	var from: Vector3 = shot["from"]
	var to: Vector3 = shot.get("to", from)
	var look_from: Vector3 = shot["look_from"]
	var look_to: Vector3 = shot.get("look_to", look_from)
	var position := base + from.lerp(to, t)
	var target := base + look_from.lerp(look_to, t)
	if position.is_equal_approx(target):
		return
	_camera.global_position = position
	_camera.look_at(target, Vector3.UP)


func _process(delta: float) -> void:
	if not playing or _shake <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	_shake_time += delta
	_camera.h_offset = sin(_shake_time * 37.0) * _shake * 0.25
	_camera.v_offset = cos(_shake_time * 29.0) * _shake * 0.2


func _unhandled_input(event: InputEvent) -> void:
	if playing and event.is_action_pressed("skip_cinematic"):
		get_viewport().set_input_as_handled()
		stop()
