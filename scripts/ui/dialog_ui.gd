extends CanvasLayer
## Ventana de diálogo con un NPC: saludo, ofrecer misiones, ver progreso y entregarlas.
## Las opciones se eligen con el mouse o con las teclas 1-9. Esc cierra.

var npc_id := ""
var _name_label: Label
var _text: Label
var _options: VBoxContainer
var _text_tween: Tween
var _on_root := false
var _root_text := ""


func _ready() -> void:
	layer = 30
	var panel := UIStyle.panel(Color(0.05, 0.07, 0.08, 0.94), 22)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -330
	panel.offset_bottom = -30
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var data := NpcDB.get_npc(npc_id)
	_name_label = UIStyle.label("%s  ·  %s" % [data.get("name", ""), data.get("title", "")], 24, UIStyle.ACCENT)
	box.add_child(_name_label)
	_text = UIStyle.label("", 19)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(750, 70)
	box.add_child(_text)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	box.add_child(_options)

	QuestManager.quest_changed.connect(_on_quest_changed)
	Cinematics.started.connect(_close)
	_show_root(_pick_greeting())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var number: int = event.physical_keycode - KEY_1
		var buttons := _options.get_children()
		if number >= 0 and number < buttons.size() and not buttons[number].disabled:
			get_viewport().set_input_as_handled()
			buttons[number].pressed.emit()


func _close() -> void:
	if Game.dialog_open:
		Game.close_dialog()
	queue_free()


func _pick_greeting() -> String:
	# Saludo especial si hay que hablar con este NPC para una misión.
	for id in QuestManager.active_quests():
		for objective in QuestDB.get_quest(id)["objectives"]:
			if objective["type"] == "talk" and objective["npc"] == npc_id:
				return NpcDB.get_npc(npc_id)["greetings"][0]
	var greetings: Array = NpcDB.get_npc(npc_id).get("greetings", ["..."])
	return greetings[randi() % greetings.size()]


func _say(text: String) -> void:
	_text.text = text
	_text.visible_ratio = 0.0
	if _text_tween:
		_text_tween.kill()
	_text_tween = create_tween()
	_text_tween.tween_property(_text, "visible_ratio", 1.0, clampf(text.length() * 0.018, 0.3, 2.0))


func _set_options(options: Array) -> void:
	for child in _options.get_children():
		child.queue_free()
	for i in options.size():
		var option: Array = options[i]
		var button := UIStyle.button("%d.  %s" % [i + 1, option[0]])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_font_size_override("font_size", 17)
		if option.size() > 2 and option[2]:
			button.disabled = true
		else:
			button.pressed.connect(option[1])
		_options.add_child(button)


# --- Pantallas del diálogo ---------------------------------------------------------------

func _show_root(text: String, animate: bool = true) -> void:
	_on_root = true
	_root_text = text
	if animate:
		_say(text)
	else:
		_text.text = text
	var options: Array = []
	var offered := false
	for id in QuestManager.quests_for_npc(npc_id):
		var quest := QuestDB.get_quest(id)
		match QuestManager.get_status(id):
			"ready":
				var missing := QuestManager.missing_delivery(id)
				if missing.is_empty():
					options.append(["Entregar: %s" % quest["title"], _turn_in.bind(id)])
				else:
					options.append(["Entregar: %s  (te falta %s)" % [quest["title"], missing], Callable(), true])
			"active":
				options.append(["Sobre «%s»..." % quest["title"], _show_progress.bind(id)])
			"available":
				if not offered:
					offered = true
					options.append(["¿Necesitás ayuda con algo?", _show_offer.bind(id)])
	if options.is_empty() and QuestManager.npc_marker(npc_id) == "":
		_text.text = "%s\n\n%s" % [text, NpcDB.get_npc(npc_id).get("idle", "")]
	options.append(["Adiós", _close])
	_set_options(options)


func _show_offer(id: String) -> void:
	_on_root = false
	var quest := QuestDB.get_quest(id)
	_say("%s\n\nObjetivo: %s\nRecompensa: %s" % [quest["offer"], _objectives_text(id),
		ItemDB.list_text(quest.get("rewards", {}))])
	_set_options([
		["Aceptar misión", _accept.bind(id)],
		["Ahora no", _show_root.bind("Cuando quieran, acá estoy.")],
	])


func _show_progress(id: String) -> void:
	_on_root = false
	var quest := QuestDB.get_quest(id)
	_say("%s\n\nProgreso: %s" % [quest.get("progress", ""), _objectives_text(id, true)])
	_set_options([["Volver", _show_root.bind("¿Algo más?")], ["Adiós", _close]])


func _accept(id: String) -> void:
	_on_root = false
	Game.send_action("quest_accept", [id])
	_say("¡Perfecto! Cuento con ustedes.")
	_set_options([["Volver", _show_root.bind("¿Algo más?")], ["Adiós", _close]])


func _turn_in(id: String) -> void:
	_on_root = false
	Game.send_action("quest_turn_in", [id])
	_say(QuestDB.get_quest(id).get("complete", "¡Gracias!"))
	_set_options([["Volver", _show_root.bind("¿Algo más?")], ["Adiós", _close]])


## Cuando el servidor confirma algo (por ejemplo, la charla con el NPC), se actualizan las opciones.
func _on_quest_changed() -> void:
	if _on_root:
		_show_root(_root_text, false)


func _objectives_text(id: String, with_progress: bool = false) -> String:
	var parts: Array[String] = []
	var objectives: Array = QuestDB.get_quest(id)["objectives"]
	for i in objectives.size():
		var objective: Dictionary = objectives[i]
		var text: String = objective["text"]
		if objective.has("item"):
			text += " (%s x%d)" % [ItemDB.item_name(objective["item"]), objective["amount"]]
		if with_progress and objective["type"] in ["collect", "craft", "deliver"]:
			text += " %d/%d" % [QuestManager.objective_progress(id, i), objective["amount"]]
		parts.append(text)
	return ", ".join(parts)
