extends CanvasLayer
## Inventario estilo survival: barra rápida siempre visible abajo, indicador de carga, y con
## Tab se abre la mochila (grilla de 6x4) encima de la barra, más un panel de detalles.

const CraftingPanel := preload("res://scripts/ui/crafting_panel.gd")
const GAP := 6.0
const COLUMNS := 6

var _hotbar_slots: Array[ItemSlot] = []
var _main_slots: Array[ItemSlot] = []
var _window: Control
var _weight_bar: ProgressBar
var _weight_fill := StyleBoxFlat.new()
var _weight_label: Label
var _speed_label: Label
var _details_name: Label
var _details_description: Label
var _details_stats: Label
var _queue_panel: PanelContainer
var _queue_box: VBoxContainer
var _queue_progress: ProgressBar


## Zona invisible detrás del inventario: soltar un objeto acá lo tira al suelo.
class DropZone extends Control:
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("inventory_slot")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		Game.send_action("drop", [data["inventory_slot"]])


func _ready() -> void:
	layer = 12
	var row_width := COLUMNS * ItemSlot.SLOT_SIZE + (COLUMNS - 1) * GAP

	# Ventana del inventario (oculta hasta apretar Tab). Va primero para quedar detrás de la barra.
	_window = Control.new()
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.visible = false
	add_child(_window)

	var drop_zone := DropZone.new()
	drop_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.add_child(drop_zone)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone.add_child(dim)

	_build_main_grid(row_width)
	_build_details_panel(row_width)
	_build_crafting_panel(row_width)
	_build_hotbar(row_width)
	_build_weight_panel(row_width)
	_build_queue_panel(row_width)

	Game.inventory_changed.connect(_refresh)
	Game.craft_queue_changed.connect(_refresh_queue)
	Game.selected_slot_changed.connect(func(_i: int): _refresh())
	Game.inventory_toggled.connect(_on_inventory_toggled)
	Cinematics.started.connect(func(): visible = false)
	Cinematics.finished.connect(func(): visible = true)
	visible = not Cinematics.playing
	_refresh()


func _bottom_center(control: Control, left: float, right: float, top: float, bottom: float,
		grow: Control.GrowDirection = Control.GROW_DIRECTION_BOTH) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = left
	control.offset_right = right
	control.offset_top = top
	control.offset_bottom = bottom
	control.grow_horizontal = grow
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_hotbar(row_width: float) -> void:
	var hotbar := HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", int(GAP))
	_bottom_center(hotbar, -row_width / 2, row_width / 2, -20 - ItemSlot.SLOT_SIZE, -20)
	add_child(hotbar)
	for i in Inventory.HOTBAR_SIZE:
		var slot := ItemSlot.new(i, true)
		slot.mouse_entered.connect(_show_details.bind(i))
		hotbar.add_child(slot)
		_hotbar_slots.append(slot)


func _build_main_grid(row_width: float) -> void:
	var panel := UIStyle.panel(Color(0.08, 0.09, 0.09, 0.88), 10)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bottom := -20 - ItemSlot.SLOT_SIZE - 14
	_bottom_center(panel, -row_width / 2 - 10, row_width / 2 + 10, bottom - 360, bottom)
	_window.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UIStyle.label("INVENTARIO", 18, UIStyle.ACCENT))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", int(GAP))
	box.add_child(grid)
	for i in range(Inventory.HOTBAR_SIZE, Inventory.SIZE):
		var slot := ItemSlot.new(i)
		slot.mouse_entered.connect(_show_details.bind(i))
		grid.add_child(slot)
		_main_slots.append(slot)
	var help := UIStyle.label("Arrastrar: mover · Shift+Click: mover rápido · Click der.: dividir · Soltar afuera: tirar", 12, UIStyle.TEXT_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(row_width, 0)
	box.add_child(help)


func _build_details_panel(row_width: float) -> void:
	var panel := UIStyle.panel(Color(0.08, 0.09, 0.09, 0.88), 14)
	var bottom := -20 - ItemSlot.SLOT_SIZE - 14
	_bottom_center(panel, row_width / 2 + 24, row_width / 2 + 304, bottom - 200, bottom, Control.GROW_DIRECTION_END)
	_window.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_details_name = UIStyle.label("", 20, UIStyle.ACCENT)
	box.add_child(_details_name)
	_details_description = UIStyle.label("", 15, UIStyle.TEXT_DIM)
	_details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_description.custom_minimum_size = Vector2(250, 0)
	box.add_child(_details_description)
	_details_stats = UIStyle.label("", 15)
	box.add_child(_details_stats)
	_show_details(-1)


func _build_weight_panel(row_width: float) -> void:
	var panel := UIStyle.panel(Color(0.08, 0.09, 0.09, 0.82), 10)
	_bottom_center(panel, row_width / 2 + 24, row_width / 2 + 254, -20 - ItemSlot.SLOT_SIZE, -20, Control.GROW_DIRECTION_END)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_weight_label = UIStyle.label("", 15)
	box.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(210, 10)
	_weight_bar.max_value = 1.3
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.2, 0.2, 0.2)
	background.set_corner_radius_all(3)
	_weight_fill.set_corner_radius_all(3)
	_weight_bar.add_theme_stylebox_override("background", background)
	_weight_bar.add_theme_stylebox_override("fill", _weight_fill)
	box.add_child(_weight_bar)
	_speed_label = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	box.add_child(_speed_label)


func _build_crafting_panel(row_width: float) -> void:
	var panel := UIStyle.panel(Color(0.08, 0.09, 0.09, 0.88), 12)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bottom := -20 - ItemSlot.SLOT_SIZE - 14
	_bottom_center(panel, -row_width / 2 - 384, -row_width / 2 - 24, bottom - 360, bottom, Control.GROW_DIRECTION_BEGIN)
	_window.add_child(panel)
	panel.add_child(CraftingPanel.new())


## Cola de fabricación: a la izquierda de la barra rápida, visible mientras se fabrica algo.
func _build_queue_panel(row_width: float) -> void:
	_queue_panel = UIStyle.panel(Color(0.08, 0.09, 0.09, 0.82), 10)
	_queue_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_bottom_center(_queue_panel, -row_width / 2 - 254, -row_width / 2 - 24, -20 - ItemSlot.SLOT_SIZE, -20, Control.GROW_DIRECTION_BEGIN)
	_queue_panel.visible = false
	add_child(_queue_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_queue_panel.add_child(box)
	box.add_child(UIStyle.label("Fabricando", 14, UIStyle.ACCENT))
	_queue_progress = ProgressBar.new()
	_queue_progress.show_percentage = false
	_queue_progress.custom_minimum_size = Vector2(210, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIStyle.ACCENT
	fill.set_corner_radius_all(3)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.2, 0.2, 0.2)
	background.set_corner_radius_all(3)
	_queue_progress.add_theme_stylebox_override("fill", fill)
	_queue_progress.add_theme_stylebox_override("background", background)
	box.add_child(_queue_progress)
	_queue_box = VBoxContainer.new()
	box.add_child(_queue_box)


func _refresh_queue() -> void:
	_queue_panel.visible = not Game.craft_queue.is_empty()
	for child in _queue_box.get_children():
		child.queue_free()
	for i in Game.craft_queue.size():
		var job: Dictionary = Game.craft_queue[i]
		var button := Button.new()
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s  x%d" % [RecipeDB.display_name(job["recipe"]), job["remaining"]]
		button.tooltip_text = "Click para cancelar (se devuelven los materiales)"
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func(): Game.send_action("craft_cancel", [i]))
		_queue_box.add_child(button)


func _process(_delta: float) -> void:
	if not Game.craft_queue.is_empty():
		var job: Dictionary = Game.craft_queue[0]
		_queue_progress.value = 100.0 * (1.0 - job["time_left"] / maxf(job["time"], 0.01))


func _refresh() -> void:
	for slot in _hotbar_slots:
		slot.selected = slot.index == Game.selected_slot
		slot.refresh()
	for slot in _main_slots:
		slot.refresh()

	var ratio := Game.load_ratio()
	_weight_bar.value = ratio
	_weight_label.text = "Mochila  %.1f / %.0f kg" % [Game.carried_weight(), Game.capacity()]
	if ratio > 1.0:
		_weight_fill.bg_color = Color(0.9, 0.3, 0.25)
		_speed_label.text = "¡SOBRECARGADO! Velocidad %d%%" % roundi(Game.speed_multiplier() * 100)
		_speed_label.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
	else:
		_weight_fill.bg_color = Color(0.45, 0.8, 0.4).lerp(Color(0.95, 0.75, 0.25), clampf((ratio - 0.4) / 0.6, 0.0, 1.0))
		_speed_label.text = "Velocidad %d%%" % roundi(Game.speed_multiplier() * 100)
		_speed_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)


func _show_details(index: int) -> void:
	var slot := Game.get_slot(index)
	if slot.is_empty():
		_details_name.text = "Detalles"
		_details_description.text = "Pasá el mouse sobre un objeto para ver su información."
		_details_stats.text = ""
		return
	var id: String = slot["id"]
	_details_name.text = ItemDB.item_name(id)
	_details_description.text = ItemDB.description(id)
	_details_stats.text = "Cantidad: %d / %d\nPeso: %.2f kg c/u · %.1f kg total" % [
		slot["count"], ItemDB.stack_size(id), ItemDB.weight(id), ItemDB.weight(id) * slot["count"]]


func _on_inventory_toggled(is_open: bool) -> void:
	_window.visible = is_open
	if not is_open:
		_show_details(-1)
