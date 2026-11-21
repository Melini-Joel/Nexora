extends VBoxContainer
## Panel de fabricación (dentro del inventario): lista de recetas, detalle con los
## materiales que tenés / necesitás, estación requerida, cantidad y botón Fabricar.

var _list: VBoxContainer
var _buttons: Dictionary = {}  ## recipe_id -> Button
var _selected := ""
var _amount := 1
var _title: Label
var _ingredients: VBoxContainer
var _station: Label
var _time: Label
var _amount_label: Label
var _craft_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UIStyle.label("FABRICACIÓN", 18, UIStyle.ACCENT))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 170)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	for recipe_id: String in RecipeDB.RECIPES:
		_list.add_child(_make_recipe_button(recipe_id))

	add_child(HSeparator.new())
	_title = UIStyle.label("", 19, UIStyle.ACCENT)
	add_child(_title)
	_ingredients = VBoxContainer.new()
	add_child(_ingredients)
	_station = UIStyle.label("", 14)
	_station.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_station.custom_minimum_size = Vector2(330, 0)
	add_child(_station)
	_time = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	add_child(_time)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var minus := UIStyle.button("−")
	minus.custom_minimum_size = Vector2(42, 40)
	minus.pressed.connect(func(): _change_amount(-1))
	row.add_child(minus)
	_amount_label = UIStyle.label("x1", 18)
	_amount_label.custom_minimum_size = Vector2(46, 0)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_amount_label)
	var plus := UIStyle.button("+")
	plus.custom_minimum_size = Vector2(42, 40)
	plus.pressed.connect(func(): _change_amount(1))
	row.add_child(plus)
	_craft_button = UIStyle.button("Fabricar")
	_craft_button.custom_minimum_size = Vector2(0, 40)
	_craft_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_button.pressed.connect(_on_craft_pressed)
	row.add_child(_craft_button)

	Game.inventory_changed.connect(refresh)
	_select(RecipeDB.RECIPES.keys()[0])


func _make_recipe_button(recipe_id: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 42)
	button.toggle_mode = true
	button.add_theme_stylebox_override("normal", UIStyle.panel_style(Color(0.15, 0.16, 0.15), 4))
	button.add_theme_stylebox_override("hover", UIStyle.panel_style(Color(0.2, 0.22, 0.2), 4))
	button.add_theme_stylebox_override("pressed", UIStyle.panel_style(Color(0.26, 0.3, 0.22), 4))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var icon := ItemIcon.new()
	icon.item_id = RecipeDB.get_recipe(recipe_id)["result"]
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := UIStyle.label(RecipeDB.display_name(recipe_id), 16)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	button.pressed.connect(_select.bind(recipe_id))
	_buttons[recipe_id] = button
	return button


func _select(recipe_id: String) -> void:
	_selected = recipe_id
	_amount = 1
	for id in _buttons:
		_buttons[id].button_pressed = id == recipe_id
	refresh()


func _change_amount(delta: int) -> void:
	_amount = clampi(_amount + delta, 1, 20)
	refresh()


func refresh() -> void:
	# Opacar las recetas que no se pueden fabricar ahora.
	for id in _buttons:
		_buttons[id].modulate = Color.WHITE if RecipeDB.max_craftable(id, Game.inventory) > 0 else Color(1, 1, 1, 0.5)
	if _selected.is_empty():
		return
	var recipe := RecipeDB.get_recipe(_selected)
	_title.text = RecipeDB.display_name(_selected)
	for child in _ingredients.get_children():
		child.queue_free()
	var enough := true
	var ingredients: Dictionary = recipe["ingredients"]
	for item: String in ingredients:
		var need: int = ingredients[item] * _amount
		var have := Inventory.count_in(Game.inventory, item)
		enough = enough and have >= need
		var color := UIStyle.SUCCESS if have >= need else Color(1, 0.5, 0.45)
		_ingredients.add_child(UIStyle.label("%s  %d / %d" % [ItemDB.item_name(item), have, need], 15, color))
	var station_ok := true
	if recipe.has("station"):
		station_ok = _near_station(recipe["station"])
		_station.text = "Requiere: %s%s" % [RecipeDB.STATIONS[recipe["station"]], "" if station_ok else "  (estás lejos)"]
		_station.add_theme_color_override("font_color", UIStyle.SUCCESS if station_ok else Color(1, 0.5, 0.45))
	else:
		_station.text = "Se fabrica en cualquier lugar"
		_station.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_time.text = "Tiempo: %.0f s c/u  ·  Da: %s x%d" % [recipe["time"], ItemDB.item_name(recipe["result"]), recipe["amount"]]
	_amount_label.text = "x%d" % _amount
	_craft_button.disabled = not (enough and station_ok)


func _process(_delta: float) -> void:
	# La distancia a las estaciones cambia al moverse: refrescar de vez en cuando.
	if is_visible_in_tree() and Engine.get_process_frames() % 20 == 0:
		refresh()


func _near_station(station: String) -> bool:
	var world := get_tree().get_first_node_in_group("world")
	return world != null and Game.local_player != null \
		and world.is_near_station(Game.local_player.global_position, station)


func _on_craft_pressed() -> void:
	Game.send_action("craft", [_selected, _amount])
