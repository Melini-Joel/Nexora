class_name ItemIcon
extends Control
## Ícono de un ítem dibujado por código (no necesita imágenes).
## Para un ítem nuevo, agregá su "icon" en ItemDB y un caso en _draw().
## Más adelante se pueden reemplazar por imágenes PNG sin cambiar el resto del inventario.

var item_id := "":
	set(value):
		item_id = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if item_id.is_empty():
		return
	var c := ItemDB.color(item_id)
	match ItemDB.icon(item_id):
		"wood":
			_draw_wood(c)
		"stone":
			_draw_rock(c, [])
		"ore":
			_draw_rock(Color(0.45, 0.43, 0.42), [Vector2(0.4, 0.5), Vector2(0.6, 0.38), Vector2(0.62, 0.62), Vector2(0.32, 0.66)])
		"hatchet":
			_draw_hatchet()
		"pickaxe":
			_draw_pickaxe()
		_:
			draw_circle(size * 0.5, size.x * 0.3, c)


func _p(x: float, y: float) -> Vector2:
	return Vector2(x * size.x, y * size.y)


func _poly(points: Array, color: Color) -> void:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(_p(point.x, point.y))
	draw_colored_polygon(packed, color)


func _draw_wood(c: Color) -> void:
	draw_set_transform(size * 0.5, -0.5, Vector2.ONE)
	for offset: float in [-0.14, 0.12]:
		var length := size.x * 0.66
		var thickness := size.y * 0.2
		var y := offset * size.y
		draw_rect(Rect2(-length / 2, y - thickness / 2, length, thickness), c)
		draw_rect(Rect2(-length / 2, y - thickness / 2, length, thickness * 0.3), c.lightened(0.15))
		draw_circle(Vector2(length / 2, y), thickness / 2, c.lightened(0.35))
		draw_circle(Vector2(length / 2, y), thickness / 4, c.darkened(0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_rock(c: Color, veins: Array) -> void:
	_poly([Vector2(0.18, 0.68), Vector2(0.28, 0.36), Vector2(0.52, 0.22), Vector2(0.8, 0.36), Vector2(0.84, 0.68), Vector2(0.52, 0.82)], c)
	_poly([Vector2(0.28, 0.36), Vector2(0.52, 0.22), Vector2(0.58, 0.48), Vector2(0.36, 0.54)], c.lightened(0.2))
	_poly([Vector2(0.52, 0.82), Vector2(0.84, 0.68), Vector2(0.58, 0.48)], c.darkened(0.2))
	for vein in veins:
		draw_circle(_p(vein.x, vein.y), size.x * 0.06, Color(0.95, 0.6, 0.2))


func _draw_hatchet() -> void:
	draw_line(_p(0.28, 0.86), _p(0.62, 0.18), Color(0.5, 0.34, 0.2), size.x * 0.09)
	_poly([Vector2(0.5, 0.14), Vector2(0.84, 0.16), Vector2(0.86, 0.46), Vector2(0.58, 0.38)], Color(0.68, 0.68, 0.7))
	_poly([Vector2(0.74, 0.16), Vector2(0.84, 0.16), Vector2(0.86, 0.46), Vector2(0.78, 0.42)], Color(0.82, 0.82, 0.84))


func _draw_pickaxe() -> void:
	draw_line(_p(0.3, 0.88), _p(0.58, 0.26), Color(0.5, 0.34, 0.2), size.x * 0.09)
	var head := PackedVector2Array([_p(0.16, 0.36), _p(0.36, 0.22), _p(0.58, 0.2), _p(0.8, 0.28), _p(0.9, 0.46)])
	draw_polyline(head, Color(0.68, 0.68, 0.7), size.x * 0.1)
