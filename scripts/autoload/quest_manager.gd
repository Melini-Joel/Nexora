extends Node
## Misiones cooperativas. El progreso es compartido por todo el grupo y lo controla el servidor:
## si cualquier jugador tala un árbol, cuenta para todos.
##
## Tipos de objetivo soportados:
##   collect: {"type": "collect", "item": "wood", "amount": 10, "text": "..."}
##   reach:   {"type": "reach", "target": "<landmark>", "radius": 7.0, "amount": 1, "text": "..."}

signal quest_changed

const QUESTS := [
	{
		"title": "Un nuevo comienzo",
		"description": "El grupo despertó en una isla desconocida. Junten madera para reforzar el campamento.",
		"objectives": [
			{"type": "collect", "item": "wood", "amount": 10, "text": "Talar árboles"},
		],
	},
	{
		"title": "Herramientas de piedra",
		"description": "Con piedra y madera podremos fabricar mejores herramientas.",
		"objectives": [
			{"type": "collect", "item": "stone", "amount": 8, "text": "Picar rocas"},
			{"type": "collect", "item": "wood", "amount": 6, "text": "Más madera"},
		],
		"on_complete_cinematic": "reveal_monolith",
	},
	{
		"title": "El monolito de la cima",
		"description": "Una luz extraña brilla en lo alto de la montaña. Lleguen hasta el monolito.",
		"objectives": [
			{"type": "reach", "target": "monolith", "radius": 7.0, "amount": 1, "text": "Llegar al monolito"},
		],
		"on_complete_cinematic": "monolith_awakens",
	},
]

var current_index := 0
var progress: Array = []
var _reach_check_timer := 0.0


func _ready() -> void:
	_reset_progress()


func reset() -> void:
	current_index = 0
	_reset_progress()
	quest_changed.emit()


func current_quest() -> Dictionary:
	if current_index < QUESTS.size():
		return QUESTS[current_index]
	return {}


func is_finished() -> bool:
	return current_index >= QUESTS.size()


func _reset_progress() -> void:
	progress = []
	for _objective in current_quest().get("objectives", []):
		progress.append(0)


# --- Servidor ------------------------------------------------------------------

func report_collect(item: String, amount: int) -> void:
	if not multiplayer.is_server() or is_finished():
		return
	var changed := false
	var objectives: Array = current_quest()["objectives"]
	for i in objectives.size():
		var objective: Dictionary = objectives[i]
		if objective["type"] == "collect" and objective["item"] == item and progress[i] < objective["amount"]:
			progress[i] = mini(progress[i] + amount, objective["amount"])
			changed = true
	if changed:
		_after_progress()


func _process(delta: float) -> void:
	if not Network.is_online() or not multiplayer.is_server() or is_finished():
		return
	_reach_check_timer -= delta
	if _reach_check_timer > 0.0:
		return
	_reach_check_timer = 0.5
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.generated:
		return
	var changed := false
	var objectives: Array = current_quest()["objectives"]
	for i in objectives.size():
		var objective: Dictionary = objectives[i]
		if objective["type"] != "reach" or progress[i] >= objective["amount"]:
			continue
		var target: Vector3 = world.landmarks.get(objective["target"], Vector3.INF)
		for player in world.get_players():
			if player.sync_pos.distance_to(target) <= objective["radius"]:
				progress[i] = objective["amount"]
				changed = true
				break
	if changed:
		_after_progress()


func _after_progress() -> void:
	if _all_objectives_done():
		var finished_index := current_index
		current_index += 1
		_reset_progress()
		_quest_completed.rpc(finished_index)
	_sync_state.rpc(current_index, progress)


func _all_objectives_done() -> bool:
	var objectives: Array = current_quest()["objectives"]
	for i in objectives.size():
		if progress[i] < objectives[i]["amount"]:
			return false
	return true


func send_state_to(peer_id: int) -> void:
	_sync_state.rpc_id(peer_id, current_index, progress)


# --- Todos los peers --------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_state(index: int, new_progress: Array) -> void:
	current_index = index
	progress = new_progress
	quest_changed.emit()


@rpc("authority", "call_local", "reliable")
func _quest_completed(index: int) -> void:
	var quest: Dictionary = QUESTS[index]
	Game.notify.emit("Misión completada: %s" % quest["title"])
	if index + 1 < QUESTS.size():
		Game.notify.emit("Nueva misión: %s" % QUESTS[index + 1]["title"])
	else:
		Game.notify.emit("¡Completaron todas las misiones de la demo!")
	if quest.has("on_complete_cinematic"):
		var world := get_tree().get_first_node_in_group("world")
		if world and world.generated:
			Cinematics.play(world.build_cinematic(quest["on_complete_cinematic"]))
