extends CanvasLayer
## Menú de personaje (tecla C): nivel, experiencia y habilidades para mejorar con puntos.

var _level: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _points: Label
var _rows: Dictionary = {}  ## habilidad -> [Label nivel, Button +]
var _summary: Label


func _ready() -> void:
	layer = 26
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIStyle.panel(Color(0.05, 0.07, 0.09, 0.95), 26)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(660, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UIStyle.label("PERSONAJE", 26, UIStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_level = UIStyle.label("", 22)
	header.add_child(_level)

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.7, 1.0)
	fill.set_corner_radius_all(4)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.15, 0.15, 0.18)
	background.set_corner_radius_all(4)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	_xp_bar.add_theme_stylebox_override("background", background)
	box.add_child(_xp_bar)
	_xp_label = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	box.add_child(_xp_label)
	_points = UIStyle.label("", 18, UIStyle.SUCCESS)
	box.add_child(_points)
	box.add_child(HSeparator.new())

	for skill: String in SkillDB.SKILLS:
		var data: Dictionary = SkillDB.SKILLS[skill]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(texts)
		texts.add_child(UIStyle.label(data["name"], 19, UIStyle.ACCENT))
		texts.add_child(UIStyle.label(data["description"], 14, UIStyle.TEXT_DIM))
		var level := UIStyle.label("", 17)
		level.custom_minimum_size = Vector2(150, 0)
		level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(level)
		var plus := UIStyle.button("+")
		plus.custom_minimum_size = Vector2(46, 40)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus.pressed.connect(func(): Game.send_action("skill_up", [skill]))
		row.add_child(plus)
		_rows[skill] = [level, plus]

	box.add_child(HSeparator.new())
	_summary = UIStyle.label("", 15)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)
	var help := UIStyle.label("Ganás experiencia recolectando, fabricando, construyendo, cazando, derrotando sombras, domesticando, abriendo cofres y completando misiones.  ·  C o Esc: cerrar", 13, UIStyle.TEXT_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(640, 0)
	box.add_child(help)

	Game.progress_changed.connect(func(_l: bool): _refresh())
	Game.character_open_changed.connect(func(is_open: bool):
		visible = is_open
		_refresh())
	_refresh()


func _refresh() -> void:
	var progress := Game.progress
	var level: int = progress.get("level", 1)
	var needed := SkillDB.xp_to_next(level)
	_level.text = "Nivel %d" % level
	_xp_bar.max_value = needed
	_xp_bar.value = progress.get("xp", 0)
	_xp_label.text = "Experiencia: %d / %d" % [progress.get("xp", 0), needed]
	var points: int = progress.get("points", 0)
	_points.text = "Puntos para gastar: %d" % points if points > 0 else "Sin puntos: subí de nivel para conseguir más."
	_points.add_theme_color_override("font_color", UIStyle.SUCCESS if points > 0 else UIStyle.TEXT_DIM)
	for skill: String in _rows:
		var current := SkillDB.skill_level(progress, skill)
		var maximum: int = SkillDB.SKILLS[skill]["max"]
		var dots := "●".repeat(current) + "○".repeat(maximum - current)
		(_rows[skill][0] as Label).text = "%s  %d/%d" % [dots, current, maximum]
		(_rows[skill][1] as Button).disabled = points <= 0 or current >= maximum
	_summary.text = "Vida máx. %d  ·  Energía máx. %d  ·  Daño x%.1f  ·  Recolección x%.2f  ·  Carga %d kg  ·  Velocidad x%.2f" % [
		SkillDB.max_health(progress), SkillDB.max_stamina(progress), SkillDB.damage_multiplier(progress),
		SkillDB.gather_multiplier(progress), Game.capacity(), SkillDB.speed_multiplier(progress)]
