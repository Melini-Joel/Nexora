extends CanvasLayer
## Menú principal: crear partida (host) o unirse por IP.

signal host_pressed(player_name: String)
signal join_pressed(player_name: String, address: String)

var _name_edit: LineEdit
var _address_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 20

	var background := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.13, 0.22, 0.2))
	gradient.set_color(1, Color(0.04, 0.06, 0.09))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0)
	texture.fill_to = Vector2(0.5, 1)
	background.texture = texture
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UIStyle.panel(Color(0.05, 0.07, 0.09, 0.85), 28)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := UIStyle.label("Tierras Compartidas", 42, UIStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := UIStyle.label("Aventura cooperativa · 2 a %d jugadores" % Network.MAX_PLAYERS, 16, UIStyle.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(_spacer(12))

	box.add_child(UIStyle.label("Tu nombre", 16, UIStyle.TEXT_DIM))
	_name_edit = UIStyle.line_edit("Jugador%d" % randi_range(1, 99), "Nombre")
	_name_edit.max_length = 16
	box.add_child(_name_edit)

	var host_button := UIStyle.button("Crear partida")
	host_button.pressed.connect(func(): host_pressed.emit(_get_name()))
	box.add_child(host_button)
	_buttons.append(host_button)

	box.add_child(_spacer(8))
	box.add_child(UIStyle.label("Dirección IP del host", 16, UIStyle.TEXT_DIM))
	_address_edit = UIStyle.line_edit("127.0.0.1", "Ej: 192.168.0.10")
	box.add_child(_address_edit)
	var join_button := UIStyle.button("Unirse a partida")
	join_button.pressed.connect(func(): join_pressed.emit(_get_name(), _address_edit.text.strip_edges()))
	box.add_child(join_button)
	_buttons.append(join_button)

	_status = UIStyle.label("", 16, UIStyle.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	var quit_button := UIStyle.button("Salir")
	quit_button.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_button)

	if not Game.pending_menu_message.is_empty():
		set_status(Game.pending_menu_message, true)
		Game.pending_menu_message = ""


func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if is_error else UIStyle.TEXT_DIM)


func set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy


func _get_name() -> String:
	var player_name := _name_edit.text.strip_edges()
	return player_name if not player_name.is_empty() else "Jugador"


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
