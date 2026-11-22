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
var _screen := ""  ## "buy" / "sell" mientras se comercia.


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
	Game.inventory_changed.connect(_on_inventory_changed)
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
		_options.remove_child(child)
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
	_screen = ""
	if npc_id == "albatros":
		_show_ship(animate)
		return
	if animate:
		_say(text)
	else:
		_text.text = text
	var options: Array = []
	var offered := false
	# La historia principal se ofrece primero.
	var quests: Array = QuestManager.quests_for_npc(npc_id)
	quests.sort_custom(func(a: String, b: String) -> bool:
		return QuestDB.get_quest(a).get("main", false) and not QuestDB.get_quest(b).get("main", false)
	)
	for id in quests:
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
	if NpcDB.get_npc(npc_id).get("trader", false):
		options.append(["Quiero comprar", _show_trade.bind("buy", true)])
		options.append(["Quiero vender", _show_trade.bind("sell", true)])
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


func _on_inventory_changed() -> void:
	if _screen in ["buy", "sell"]:
		_show_trade(_screen, false)
	elif _on_root and npc_id == "albatros":
		_show_ship(false)


# --- El Albatros: reparación y viajes --------------------------------------------------------

func _show_ship(animate: bool) -> void:
	_on_root = true
	var world := get_tree().get_first_node_in_group("world")
	var me: Node3D = Game.local_player
	var on_mainland: bool = me != null and world.terrain.region_at(me.global_position.x, me.global_position.z) == "mainland"
	var text := ""
	var options: Array = []
	var total := ShipDB.stage_count()
	if on_mainland:
		text = "El Albatros espera amarrado en el muelle de Puerto Albor, listo para volver a la isla cuando quieran."
		options.append(["Volver a la isla (viaja todo el grupo)", _sail.bind("island")])
	elif world.ship_stage >= total:
		text = "¡El Albatros está reparado y listo para navegar! Velas nuevas, casco firme y la bodega llena de provisiones.\nAl zarpar viaja todo el grupo."
		options.append(["Zarpar hacia Valdoria", _sail.bind("mainland")])
	elif QuestManager.get_status("m_albatros") != "done":
		text = "Los restos del Albatros. El casco está partido, pero la madera es de roble y parece sana...\nNilo, el pescador del muelle, sabe de barcos. Quizás él sepa cómo repararlo."
	else:
		var stage := ShipDB.get_stage(world.ship_stage)
		var lines: Array[String] = []
		var can_give := false
		var items: Dictionary = stage["items"]
		for item: String in items:
			var delivered := int(world.ship_delivered.get(item, 0))
			var have := Inventory.count_in(Game.inventory, item)
			var done := delivered >= int(items[item])
			if not done and have > 0:
				can_give = true
			lines.append("   %s %s: %d / %d%s" % ["✔" if done else "•", ItemDB.item_name(item), delivered, int(items[item]),
				"" if done else "   (tenés %d)" % have])
		text = "Reparación del Albatros  ·  Etapa %d de %d: %s\n%s\n%s" % [world.ship_stage + 1, total, stage["name"],
			stage["description"], "\n".join(lines)]
		if can_give:
			options.append(["Aportar lo que tengo", _contribute])
		else:
			options.append(["No tengo nada de lo que falta", Callable(), true])
	options.append(["Alejarse", _close])
	if animate:
		_say(text)
	else:
		_text.text = text
	_set_options(options)


func _contribute() -> void:
	Game.send_action("ship_contribute")


func _sail(destination: String) -> void:
	Game.send_action("sail", [destination])
	_close()


# --- Comercio -------------------------------------------------------------------------------

func _show_trade(kind: String, animate: bool) -> void:
	_on_root = false
	_screen = kind
	var coins := Inventory.count_in(Game.inventory, "coin")
	var text := "Tenés %d monedas de oro. %s" % [coins, "¿Qué te llevás?" if kind == "buy" else "¿Qué me traés?"]
	if animate:
		_say(text)
	else:
		_text.text = text
	var options: Array = []
	var offers: Array = NpcDB.TRADES[kind]
	for i in mini(offers.size(), 8):
		var offer: Array = offers[i]
		var label := "%s x%d  →  %d monedas" % [ItemDB.item_name(offer[0]), offer[1], offer[2]]
		var possible: bool = coins >= int(offer[2]) if kind == "buy" else Inventory.count_in(Game.inventory, offer[0]) >= int(offer[1])
		if kind == "sell":
			label = "%s x%d  →  +%d monedas" % [ItemDB.item_name(offer[0]), offer[1], offer[2]]
		options.append([label, _trade.bind(kind, i), not possible])
	options.append(["Volver", _show_root.bind("¿Algo más?")])
	_set_options(options)


func _trade(kind: String, index: int) -> void:
	Game.send_action("trade", [kind, index])


func _objectives_text(id: String, with_progress: bool = false) -> String:
	var parts: Array[String] = []
	var objectives: Array = QuestDB.get_quest(id)["objectives"]
	for i in objectives.size():
		var objective: Dictionary = objectives[i]
		var text: String = objective["text"]
		if objective.has("item") and objective["type"] in ["collect", "craft", "deliver", "kill", "tame"]:
			text += " (%s x%d)" % [ItemDB.item_name(objective["item"]), objective["amount"]]
		if with_progress and objective["type"] in ["collect", "craft", "deliver"]:
			text += " %d/%d" % [QuestManager.objective_progress(id, i), objective["amount"]]
		parts.append(text)
	return ", ".join(parts)
