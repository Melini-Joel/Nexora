extends CanvasLayer
## Menú de opciones: Pantalla, Cámara y Gráficos. Los cambios se ven al instante
## y se guardan al cerrar.

signal closed


func _ready() -> void:
	layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIStyle.panel(Color(0.05, 0.07, 0.09, 0.96), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UIStyle.label("Opciones", 30, UIStyle.ACCENT))

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 400)
	tabs.add_theme_font_size_override("font_size", 17)
	tabs.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.1, 0.12, 0.13), 18))
	box.add_child(tabs)
	_build_display_tab(_add_tab(tabs, "Pantalla"))
	_build_camera_tab(_add_tab(tabs, "Cámara"))
	_build_graphics_tab(_add_tab(tabs, "Gráficos"))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var reset := UIStyle.button("Restablecer")
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		Settings.reset_to_defaults()
		_reopen())
	buttons.add_child(reset)
	var close := UIStyle.button("Listo")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(close_menu)
	buttons.add_child(close)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close_menu()


func close_menu() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


## Después de restablecer, vuelve a abrir el menú para mostrar los valores por defecto.
func _reopen() -> void:
	var copy: CanvasLayer = (get_script() as GDScript).new()
	copy.closed.connect(func(): closed.emit())
	get_parent().add_child(copy)
	queue_free()


func _add_tab(tabs: TabContainer, title: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	tabs.add_child(grid)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	return grid


# --- Pestañas ---------------------------------------------------------------------

func _build_display_tab(grid: GridContainer) -> void:
	_add_option(grid, "Modo de pantalla", "window_mode", Settings.WINDOW_MODES)
	var resolutions := {}
	for res: String in Settings.available_resolutions():
		resolutions[res] = res.replace("x", " × ")
	_add_option(grid, "Resolución (modo ventana)", "resolution", resolutions)
	_add_slider(grid, "Tamaño de la interfaz", "ui_scale", 0.6, 1.6, 0.05, "%d%%", 100.0)
	_add_check(grid, "Sincronización vertical (VSync)", "vsync")
	_add_check(grid, "Mostrar FPS", "show_fps")


func _build_camera_tab(grid: GridContainer) -> void:
	_add_slider(grid, "Distancia de la cámara", "camera_distance", 1.5, 9.0, 0.1, "%.1f m")
	_add_slider(grid, "Altura de la cámara", "camera_height", 0.8, 3.0, 0.05, "%.2f m")
	_add_slider(grid, "Hombro (izq. ← → der.)", "camera_shoulder", -1.0, 1.0, 0.05, "%.2f")
	_add_slider(grid, "Campo de visión (FOV)", "fov", 50.0, 100.0, 1.0, "%d°")
	_add_slider(grid, "Sensibilidad del mouse", "mouse_sensitivity", 0.2, 3.0, 0.05, "%.2fx")
	_add_check(grid, "Invertir eje vertical", "invert_y")
	var tip := UIStyle.label("Tip: en el juego, la tecla V cambia entre cámara cerca / normal / lejos.", 14, UIStyle.TEXT_DIM)
	grid.add_child(tip)


func _build_graphics_tab(grid: GridContainer) -> void:
	_add_option(grid, "Calidad gráfica", "quality", Settings.QUALITY_LEVELS)
	var info := UIStyle.label(
		"Baja: sin sombras ni suavizado, render al 75%. Ideal para PCs viejas o notebooks.\n" +
		"Media: sombras y suavizado 2x.\nAlta: sombras de largo alcance y suavizado 4x.", 14, UIStyle.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	grid.add_child(info)


# --- Controles ----------------------------------------------------------------------

func _row_label(grid: GridContainer, text: String) -> void:
	var label := UIStyle.label(text, 17)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)


func _add_option(grid: GridContainer, text: String, key: String, options: Dictionary) -> void:
	_row_label(grid, text)
	var button := OptionButton.new()
	button.custom_minimum_size = Vector2(260, 38)
	button.add_theme_font_size_override("font_size", 16)
	var keys: Array = options.keys()
	for i in keys.size():
		button.add_item(options[keys[i]], i)
		if keys[i] == Settings.get_value(key):
			button.select(i)
	button.item_selected.connect(func(i: int): Settings.set_value(key, keys[i]))
	grid.add_child(button)


func _add_slider(grid: GridContainer, text: String, key: String, min_value: float, max_value: float,
		step: float, format: String, display_scale: float = 1.0) -> void:
	_row_label(grid, text)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(260, 0)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = float(Settings.get_value(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UIStyle.label("", 15, UIStyle.TEXT_DIM)
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var update_label := func(v: float):
		value_label.text = format % (v * display_scale)
	update_label.call(slider.value)
	slider.value_changed.connect(func(v: float):
		update_label.call(v)
		Settings.set_value(key, v))
	row.add_child(slider)
	row.add_child(value_label)
	grid.add_child(row)


func _add_check(grid: GridContainer, text: String, key: String) -> void:
	_row_label(grid, text)
	var check := CheckButton.new()
	check.button_pressed = bool(Settings.get_value(key))
	check.toggled.connect(func(on: bool): Settings.set_value(key, on))
	grid.add_child(check)
