class_name ItemSlot
extends Panel
## Un casillero del inventario. Soporta:
##   arrastrar y soltar en otro casillero  → mover / juntar pilas / intercambiar
##   Shift + Click                         → mover rápido (barra rápida ↔ mochila)
##   Click derecho                          → dividir la pila a la mitad
##   soltar fuera del inventario            → tirar al suelo (lo maneja DropZone)

const SLOT_SIZE := 68.0

var index := 0
var source := "player"  ## "player" = tu inventario · "storage" = la caja abierta
var selected := false:
	set(value):
		selected = value
		_update_style()

var _icon: ItemIcon
var _count: Label
var _style := StyleBoxFlat.new()


func _init(p_index: int, show_number: bool = false, p_source: String = "player") -> void:
	index = p_index
	source = p_source
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.set_corner_radius_all(4)
	_style.set_border_width_all(2)
	add_theme_stylebox_override("panel", _style)

	_icon = ItemIcon.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 7
	_icon.offset_top = 7
	_icon.offset_right = -7
	_icon.offset_bottom = -7
	add_child(_icon)

	_count = UIStyle.label("", 15)
	_count.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count.offset_right = -5
	_count.offset_bottom = -2
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_count)

	if show_number:
		var number := UIStyle.label(str(index + 1), 12, UIStyle.TEXT_DIM)
		number.position = Vector2(5, 2)
		add_child(number)
	_update_style()


func _slot() -> Dictionary:
	return Game.get_storage_slot(index) if source == "storage" else Game.get_slot(index)


func refresh() -> void:
	var slot := _slot()
	var id: String = slot.get("id", "")
	_icon.item_id = id
	var count: int = slot.get("count", 0)
	_count.text = "x%d" % count if count > 1 else ""
	tooltip_text = "" if id.is_empty() else "%s\n%s\nPeso: %.1f kg" % [
		ItemDB.item_name(id), ItemDB.description(id), ItemDB.weight(id) * count]


func _update_style() -> void:
	_style.bg_color = Color(0.17, 0.18, 0.17, 0.9) if not selected else Color(0.24, 0.26, 0.22, 0.95)
	_style.border_color = UIStyle.ACCENT if selected else Color(0.32, 0.33, 0.3, 0.7)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not Game.inventory_open or _slot().is_empty():
		return null
	var preview := ItemIcon.new()
	preview.item_id = _slot()["id"]
	preview.size = Vector2(56, 56)
	preview.position = -preview.size / 2
	preview.modulate.a = 0.85
	var holder := Control.new()
	holder.add_child(preview)
	set_drag_preview(holder)
	return {"inventory_slot": index, "source": source}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("inventory_slot")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var from_source: String = data.get("source", "player")
	if from_source == "player" and source == "player":
		if data["inventory_slot"] != index:
			Game.send_action("move", [data["inventory_slot"], index])
	elif Game.storage_box != "":
		# Entre la mochila y la caja (o dentro de la caja).
		Game.send_action("storage_move", [Game.storage_box, "s" if from_source == "storage" else "p",
			data["inventory_slot"], "s" if source == "storage" else "p", index])


func _gui_input(event: InputEvent) -> void:
	if not Game.inventory_open or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and source == "player":
		Game.send_action("split", [index])
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
		if Game.storage_box != "":
			Game.send_action("storage_quick", [Game.storage_box, "s" if source == "storage" else "p", index])
		else:
			Game.send_action("quick_move", [index])
		accept_event()
