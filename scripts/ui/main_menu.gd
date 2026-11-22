extends CanvasLayer
## Menú principal sobre el fondo animado (menu_backdrop.gd).
## Jugar solo · Multijugador (crear partida o unirse) · Opciones · Salir.

## slot = mundo guardado a cargar ("" = mundo nuevo llamado world_name).
signal start_pressed(player_name: String, solo: bool, slot: String, world_name: String)
signal join_pressed(player_name: String, address: String)

const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const VERSION := "Prototipo v1.0"
const WARM := Color(1.0, 0.86, 0.6)

var _main_box: VBoxContainer
var _multi_box: VBoxContainer
var _worlds_box: VBoxContainer
var _worlds_list: VBoxContainer
var _world_name_edit: LineEdit
var _worlds_title: Label
var _worlds_solo := true
var _name_edit: LineEdit
var _address_edit: LineEdit
var _status: Label
var _title: Label
var _emblem: TextureRect
var _fade: ColorRect
var _buttons: Array[Button] = []
var _time := 0.0


func _ready() -> void:
	layer = 20
	_build_shading()

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 110
	column.offset_right = 560
	column.offset_top = -380
	column.offset_bottom = 380
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	_emblem = TextureRect.new()
	_emblem.texture = load("res://logo/emblem.svg")
	_emblem.custom_minimum_size = Vector2(150, 150)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_emblem.pivot_offset = Vector2(75, 75)
	column.add_child(_emblem)

	_title = Label.new()
	_title.text = "NEXORA"
	_title.add_theme_font_override("font", _spaced_font(14))
	_title.add_theme_font_size_override("font_size", 104)
	_title.add_theme_color_override("font_color", WARM)
	_title.add_theme_color_override("font_shadow_color", Color(1.0, 0.5, 0.2, 0.45))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.add_theme_constant_override("shadow_outline_size", 26)
	column.add_child(_title)

	var tagline := Label.new()
	tagline.text = "SOBREVIVAN JUNTOS  ·  CONSTRUYAN  ·  DESCUBRAN LA ISLA"
	tagline.add_theme_font_override("font", _spaced_font(3))
	tagline.add_theme_font_size_override("font_size", 15)
	tagline.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	column.add_child(tagline)
	column.add_child(_spacer(46))

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 4)
	column.add_child(_main_box)
	var saves := SaveManager.list_saves()
	if not saves.is_empty():
		var last: Dictionary = saves[0]
		_main_box.add_child(_menu_button("Continuar", _on_continue.bind(last["slot"], last["name"])))
		var info := _caption("%s  ·  DÍA %d  ·  %s" % [last["name"].to_upper(), last["day"], SaveManager.format_ago(last["last_played"]).to_upper()])
		info.add_theme_color_override("font_color", Color(1, 0.86, 0.6, 0.6))
		var info_margin := MarginContainer.new()
		info_margin.add_theme_constant_override("margin_left", 20)
		info_margin.add_theme_constant_override("margin_bottom", 8)
		info_margin.add_child(info)
		_main_box.add_child(info_margin)
	_main_box.add_child(_menu_button("Jugar solo", _on_solo))
	_main_box.add_child(_menu_button("Multijugador", _show_multiplayer))
	_main_box.add_child(_menu_button("Opciones", func(): add_child(SettingsMenu.new())))
	_main_box.add_child(_menu_button("Salir", func(): get_tree().quit()))

	_build_multiplayer_box(column)
	_build_worlds_box(column)

	column.add_child(_spacer(16))
	_status = UIStyle.label("", 16, Color(1, 1, 1, 0.75))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 0)
	column.add_child(_status)

	_build_footer()

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_play_intro(column)

	if not Game.pending_menu_message.is_empty():
		set_status(Game.pending_menu_message, true)
		Game.pending_menu_message = ""


func _process(delta: float) -> void:
	_time += delta
	# El título "respira": su brillo sube y baja suave.
	_title.add_theme_color_override("font_shadow_color", Color(1.0, 0.5, 0.2, 0.3 + sin(_time * 1.3) * 0.15))
	# El emblema se mece despacio, como una brújula.
	_emblem.rotation = sin(_time * 0.6) * 0.035


# --- Construcción -------------------------------------------------------------------

## Oscurece los bordes y el lado izquierdo para que el texto se lea sobre la escena.
func _build_shading() -> void:
	var side := TextureRect.new()
	var side_gradient := Gradient.new()
	side_gradient.set_color(0, Color(0.02, 0.02, 0.05, 0.82))
	side_gradient.set_color(1, Color(0.02, 0.02, 0.05, 0.0))
	var side_texture := GradientTexture2D.new()
	side_texture.gradient = side_gradient
	side_texture.fill_from = Vector2(0, 0.5)
	side_texture.fill_to = Vector2(0.62, 0.5)
	side.texture = side_texture
	side.stretch_mode = TextureRect.STRETCH_SCALE
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side)

	var vignette := TextureRect.new()
	var vignette_gradient := Gradient.new()
	vignette_gradient.set_color(0, Color(0, 0, 0, 0.0))
	vignette_gradient.set_color(1, Color(0, 0, 0, 0.6))
	vignette_gradient.set_offset(0, 0.55)
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = vignette_gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.5)
	vignette_texture.fill_to = Vector2(1.05, 1.05)
	vignette.texture = vignette_texture
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


func _build_multiplayer_box(column: VBoxContainer) -> void:
	_multi_box = VBoxContainer.new()
	_multi_box.add_theme_constant_override("separation", 8)
	_multi_box.visible = false
	column.add_child(_multi_box)

	_multi_box.add_child(_caption("TU NOMBRE"))
	var saved_name: String = Settings.get_value("player_name")
	_name_edit = _field(saved_name if saved_name != "" else "Jugador%d" % randi_range(1, 99), "Nombre")
	_name_edit.max_length = 16
	_multi_box.add_child(_name_edit)
	_multi_box.add_child(_spacer(4))
	_multi_box.add_child(_menu_button("Crear partida", _on_host))
	_multi_box.add_child(_spacer(6))
	_multi_box.add_child(_caption("O UNITE A LA PARTIDA DE UN AMIGO"))
	_address_edit = _field(Settings.get_value("last_ip"), "IP del host, ej: 192.168.0.10")
	_multi_box.add_child(_address_edit)
	_multi_box.add_child(_menu_button("Unirse", _on_join))
	_multi_box.add_child(_spacer(6))
	_multi_box.add_child(_menu_button("‹  Volver", _show_main))


## Lista de mundos guardados + crear uno nuevo.
func _build_worlds_box(column: VBoxContainer) -> void:
	_worlds_box = VBoxContainer.new()
	_worlds_box.add_theme_constant_override("separation", 8)
	_worlds_box.visible = false
	column.add_child(_worlds_box)
	_worlds_title = _caption("ELEGÍ UN MUNDO")
	_worlds_box.add_child(_worlds_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_worlds_box.add_child(scroll)
	_worlds_list = VBoxContainer.new()
	_worlds_list.add_theme_constant_override("separation", 2)
	_worlds_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_worlds_list)
	_worlds_box.add_child(_spacer(6))
	_worlds_box.add_child(_caption("O CREÁ UN MUNDO NUEVO"))
	_world_name_edit = _field("", "Nombre del mundo")
	_world_name_edit.max_length = 24
	_worlds_box.add_child(_world_name_edit)
	_worlds_box.add_child(_menu_button("Crear mundo nuevo", _on_new_world))
	_worlds_box.add_child(_spacer(6))
	_worlds_box.add_child(_menu_button("‹  Volver", _back_from_worlds))


func _show_worlds(solo: bool) -> void:
	_worlds_solo = solo
	_main_box.visible = false
	_multi_box.visible = false
	_worlds_box.visible = true
	_worlds_title.text = "JUGAR SOLO  ·  ELEGÍ UN MUNDO" if solo else "CREAR PARTIDA  ·  ELEGÍ UN MUNDO"
	if _world_name_edit.text.strip_edges() == "":
		_world_name_edit.text = "Isla de %s" % _player_name()
	_refresh_worlds()


func _refresh_worlds() -> void:
	for child in _worlds_list.get_children():
		child.queue_free()
	var saves := SaveManager.list_saves()
	if saves.is_empty():
		var empty := UIStyle.label("Todavía no hay mundos guardados.", 15, Color(1, 1, 1, 0.5))
		_worlds_list.add_child(empty)
	(_worlds_list.get_parent() as Control).custom_minimum_size.y = clampf(saves.size() * 54.0, 30.0, 230.0)
	for save in saves:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var load := _menu_button("%s" % save["name"], _on_load_world.bind(save["slot"], save["name"]))
		load.custom_minimum_size = Vector2(330, 48)
		load.add_theme_font_size_override("font_size", 20)
		load.tooltip_text = "Día %d  ·  jugado %s  ·  %s" % [save["day"], SaveManager.format_play_time(save["play_time"]), SaveManager.format_ago(save["last_played"])]
		row.add_child(load)
		var detail := _caption("DÍA %d · %s" % [save["day"], SaveManager.format_ago(save["last_played"]).to_upper()])
		detail.custom_minimum_size = Vector2(0, 48)
		detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(detail)
		var delete := Button.new()
		delete.text = "Borrar"
		delete.flat = true
		delete.add_theme_font_size_override("font_size", 13)
		delete.add_theme_color_override("font_color", Color(1, 0.55, 0.5, 0.7))
		delete.pressed.connect(_on_delete_world.bind(save["slot"], delete))
		row.add_child(delete)
		_worlds_list.add_child(row)


func _back_from_worlds() -> void:
	_worlds_box.visible = false
	if _worlds_solo:
		_show_main()
	else:
		_show_multiplayer()


func _on_delete_world(slot: String, button: Button) -> void:
	# Primer click pide confirmación; el segundo borra.
	if button.text != "¿Seguro?":
		button.text = "¿Seguro?"
		get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(button): button.text = "Borrar")
		return
	SaveManager.delete_save(slot)
	_refresh_worlds()


func _on_continue(slot: String, world_name: String) -> void:
	var player_name := _player_name()
	_fade_then(func(): start_pressed.emit(player_name, true, slot, world_name))


func _on_load_world(slot: String, world_name: String) -> void:
	var player_name := _player_name()
	var solo := _worlds_solo
	_fade_then(func(): start_pressed.emit(player_name, solo, slot, world_name))


func _on_new_world() -> void:
	var player_name := _player_name()
	var world_name := _world_name_edit.text.strip_edges()
	if world_name == "":
		world_name = "Isla de %s" % player_name
	var solo := _worlds_solo
	_fade_then(func(): start_pressed.emit(player_name, solo, "", world_name))


func _build_footer() -> void:
	var left := UIStyle.label("%s  ·  Hecho con Godot" % VERSION, 13, Color(1, 1, 1, 0.45))
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 28
	left.offset_top = -44
	left.offset_right = 600
	left.offset_bottom = -20
	add_child(left)
	var right := UIStyle.label("Cooperativo de 2 a %d jugadores" % Network.MAX_PLAYERS, 13, Color(1, 1, 1, 0.45))
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -400
	right.offset_right = -28
	right.offset_top = -44
	right.offset_bottom = -20
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(right)


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(380, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_override("font", _spaced_font(2))
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	button.add_theme_color_override("font_hover_color", WARM)
	button.add_theme_color_override("font_pressed_color", WARM)
	button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 0.85))
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = 18
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 0.8, 0.5, 0.1)
	hover.border_width_left = 3
	hover.border_color = WARM
	hover.content_margin_left = 26
	hover.set_corner_radius_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(action)
	button.pressed.connect(func(): Sound.play("ui_click"))
	button.mouse_entered.connect(func(): Sound.play("ui_hover", Vector3.INF, -4.0))
	_buttons.append(button)
	return button


func _field(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(380, 44)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	edit.add_theme_font_size_override("font_size", 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.3)
	style.set_content_margin_all(10)
	var focus := style.duplicate()
	focus.border_color = WARM
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", focus)
	return edit


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _spaced_font(3))
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	return label


func _spaced_font(spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = spacing
	return font


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _play_intro(column: VBoxContainer) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 1.6).from(1.0)
	column.modulate.a = 0.0
	column.position.x -= 30
	var slide := create_tween().set_parallel()
	slide.tween_property(column, "modulate:a", 1.0, 1.2).set_delay(0.5)
	slide.tween_property(column, "position:x", column.position.x + 30, 1.2).set_delay(0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Acciones --------------------------------------------------------------------------

func _show_main() -> void:
	_multi_box.visible = false
	_worlds_box.visible = false
	_main_box.visible = true
	set_status("")


func _show_multiplayer() -> void:
	_main_box.visible = false
	_multi_box.visible = true


func _player_name() -> String:
	var typed := _name_edit.text.strip_edges()
	var player_name := typed if typed != "" else "Jugador"
	Settings.set_value("player_name", player_name)
	Settings.save_settings()
	return player_name


## Fundido a negro y recién ahí avisa (se ve como una transición de película).
func _fade_then(callback: Callable) -> void:
	set_busy(true)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.45)
	tween.tween_callback(callback)


func _on_solo() -> void:
	_show_worlds(true)


func _on_host() -> void:
	_show_worlds(false)


func _on_join() -> void:
	var address := _address_edit.text.strip_edges()
	Settings.set_value("last_ip", address)
	join_pressed.emit(_player_name(), address)


func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if is_error else Color(1, 1, 1, 0.75))
	if is_error:
		_fade.color.a = 0.0
		set_busy(false)


func set_busy(busy: bool) -> void:
	for button in _buttons:
		button.disabled = busy
