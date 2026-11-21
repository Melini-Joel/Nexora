class_name UIStyle
extends RefCounted
## Estilos compartidos de la interfaz (paneles, textos y botones).

const PANEL_BG := Color(0.06, 0.08, 0.1, 0.72)
const ACCENT := Color(0.98, 0.78, 0.4)
const TEXT := Color(0.95, 0.94, 0.9)
const TEXT_DIM := Color(0.75, 0.75, 0.72)
const SUCCESS := Color(0.55, 0.9, 0.5)


static func panel_style(bg: Color = PANEL_BG, padding: float = 14.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(10)
	style.set_content_margin_all(padding)
	return style


static func panel(bg: Color = PANEL_BG, padding: float = 14.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, padding))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	return l


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_stylebox_override("normal", panel_style(Color(0.2, 0.3, 0.26), 10))
	b.add_theme_stylebox_override("hover", panel_style(Color(0.27, 0.4, 0.33), 10))
	b.add_theme_stylebox_override("pressed", panel_style(Color(0.16, 0.24, 0.2), 10))
	b.add_theme_stylebox_override("disabled", panel_style(Color(0.18, 0.18, 0.18), 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func line_edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 42)
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_stylebox_override("normal", panel_style(Color(0.1, 0.12, 0.14), 10))
	e.add_theme_stylebox_override("focus", panel_style(Color(0.14, 0.17, 0.2), 10))
	return e
