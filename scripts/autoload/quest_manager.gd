extends Node
## Misiones cooperativas. Los datos están en scripts/data/quest_db.gd.
## El servidor lleva el estado (qué misiones están activas y su progreso) y lo comparte
## con todos: el progreso es del grupo entero.
##
## Estados: "locked" (faltan requisitos) → "available" (un NPC la ofrece) → "active"
##          → "ready" (objetivos cumplidos, volver con el NPC) → "done".

signal quest_changed

var status: Dictionary = {}  ## id -> "active" | "ready" | "done"
var progress: Dictionary = {}  ## id -> Array con el progreso de cada objetivo
var _reach_timer := 0.0


## Para el guardado de partida.
func export_state() -> Dictionary:
	return {"status": status.duplicate(), "progress": progress.duplicate(true)}


func load_state(data: Dictionary) -> void:
	status = data.get("status", {}).duplicate()
	progress = data.get("progress", {}).duplicate(true)
	quest_changed.emit()


func reset() -> void:
	status = {}
	progress = {}
	quest_changed.emit()


# --- Consultas (en todos los peers) ----------------------------------------------------

func get_status(id: String) -> String:
	if status.has(id):
		return status[id]
	return "available" if _requirements_met(id) else "locked"


func _requirements_met(id: String) -> bool:
	for required: String in QuestDB.get_quest(id).get("requires", []):
		if status.get(required, "") != "done":
			return false
	return true


func active_quests() -> Array:
	var result: Array = []
	for id: String in QuestDB.QUESTS:
		if status.get(id, "") in ["active", "ready"]:
			result.append(id)
	return result


func quests_for_npc(npc_id: String) -> Array:
	var result: Array = []
	for id: String in QuestDB.QUESTS:
		if QuestDB.QUESTS[id].get("giver", "") == npc_id:
			result.append(id)
	return result


## "!" = tiene algo para ofrecer o hay que hablarle; "?" = misión lista para entregar.
func npc_marker(npc_id: String) -> String:
	for id in quests_for_npc(npc_id):
		if get_status(id) == "ready":
			return "?"
	for id in quests_for_npc(npc_id):
		if get_status(id) == "available":
			return "!"
	for id in active_quests():
		for objective in QuestDB.get_quest(id)["objectives"]:
			if objective["type"] == "talk" and objective["npc"] == npc_id:
				return "!"
	return ""


## Progreso de un objetivo. Las entregas se miden con el inventario local.
func objective_progress(id: String, index: int) -> int:
	var objective: Dictionary = QuestDB.get_quest(id)["objectives"][index]
	if objective["type"] == "deliver":
		return mini(Inventory.count_in(Game.inventory, objective["item"]), objective["amount"])
	var values: Array = progress.get(id, [])
	return values[index] if index < values.size() else 0


## Ítems a entregar que faltan en el inventario local ("" si está todo).
func missing_delivery(id: String) -> String:
	var missing := {}
	for objective in QuestDB.get_quest(id)["objectives"]:
		if objective["type"] == "deliver":
			var lacking: int = objective["amount"] - Inventory.count_in(Game.inventory, objective["item"])
			if lacking > 0:
				missing[objective["item"]] = lacking
	return ItemDB.list_text(missing)


# --- Servidor ------------------------------------------------------------------------

## Al crear la partida: activa las misiones que empiezan solas.
func server_start() -> void:
	_activate_auto_quests()
	_broadcast()


func send_state_to(peer_id: int) -> void:
	_sync_state.rpc_id(peer_id, status, progress)


func server_accept(peer_id: int, id: String) -> void:
	var quest := QuestDB.get_quest(id)
	if quest.is_empty() or not quest.has("giver") or get_status(id) != "available":
		return
	_activate(id)
	Network.announce.rpc("%s aceptó la misión «%s»" % [_player_name(peer_id), quest["title"]])
	if quest.has("on_accept_cinematic"):
		_play_cinematic.rpc(quest["on_accept_cinematic"])
	_after_progress()


func server_talk(_peer_id: int, npc_id: String) -> void:
	var changed := false
	for id in active_quests():
		var objectives: Array = QuestDB.get_quest(id)["objectives"]
		for i in objectives.size():
			if objectives[i]["type"] == "talk" and objectives[i]["npc"] == npc_id and progress[id][i] < objectives[i]["amount"]:
				progress[id][i] = objectives[i]["amount"]
				changed = true
	if changed:
		_after_progress()


func server_turn_in(peer_id: int, id: String) -> void:
	if get_status(id) != "ready":
		return
	var deliveries := {}
	for objective in QuestDB.get_quest(id)["objectives"]:
		if objective["type"] == "deliver":
			deliveries[objective["item"]] = int(deliveries.get(objective["item"], 0)) + objective["amount"]
	var world := _world()
	if not deliveries.is_empty() and not world.take_items(peer_id, deliveries):
		world.notify_peer(peer_id, "Te falta: %s" % ItemDB.list_text(deliveries))
		return
	_complete(id)
	_broadcast()


func report_collect(item: String, amount: int) -> void:
	_report("collect", item, amount)


func report_craft(item: String, amount: int) -> void:
	_report("craft", item, amount)


func report_kill(species: String) -> void:
	_report("kill", species, 1)


func report_tame(species: String) -> void:
	_report("tame", species, 1)


func report_build(piece_id: String) -> void:
	_report("build", piece_id, 1)


func _report(type: String, item: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var changed := false
	for id in active_quests():
		if status[id] != "active":
			continue
		var objectives: Array = QuestDB.get_quest(id)["objectives"]
		for i in objectives.size():
			var objective: Dictionary = objectives[i]
			if objective["type"] == type and objective["item"] in [item, "any"] and progress[id][i] < objective["amount"]:
				progress[id][i] = mini(progress[id][i] + amount, objective["amount"])
				changed = true
	if changed:
		_after_progress()


func _process(delta: float) -> void:
	if not Network.is_online() or not multiplayer.is_server():
		return
	_reach_timer -= delta
	if _reach_timer > 0.0:
		return
	_reach_timer = 0.5
	var world := _world()
	if world == null or not world.generated:
		return
	var changed := false
	for id in active_quests():
		var objectives: Array = QuestDB.get_quest(id)["objectives"]
		for i in objectives.size():
			var objective: Dictionary = objectives[i]
			if objective["type"] != "reach" or progress[id][i] >= objective["amount"]:
				continue
			var target: Vector3 = world.landmarks.get(objective["target"], Vector3.INF)
			for player in world.get_players():
				if player.sync_pos.distance_to(target) <= objective["radius"]:
					progress[id][i] = objective["amount"]
					changed = true
					break
	if changed:
		_after_progress()


func _activate(id: String) -> void:
	status[id] = "active"
	var values: Array = []
	for _objective in QuestDB.get_quest(id)["objectives"]:
		values.append(0)
	progress[id] = values


func _activate_auto_quests() -> void:
	for id: String in QuestDB.QUESTS:
		if not QuestDB.QUESTS[id].has("giver") and get_status(id) == "available":
			_activate(id)


## Revisa qué misiones cumplieron sus objetivos y lo comparte con todos.
func _after_progress() -> void:
	for id in active_quests():
		if status[id] != "active" or not _objectives_done(id):
			continue
		var quest := QuestDB.get_quest(id)
		if quest.get("auto_complete", false) or not quest.has("giver"):
			_complete(id)
		else:
			status[id] = "ready"
			_quest_ready.rpc(id)
	_broadcast()


func _objectives_done(id: String) -> bool:
	var objectives: Array = QuestDB.get_quest(id)["objectives"]
	for i in objectives.size():
		if objectives[i]["type"] != "deliver" and progress[id][i] < objectives[i]["amount"]:
			return false
	return true


func _complete(id: String) -> void:
	status[id] = "done"
	var rewards: Dictionary = QuestDB.get_quest(id).get("rewards", {})
	if not rewards.is_empty():
		_world().give_to_all(rewards)
	_quest_completed.rpc(id)
	_activate_auto_quests()


func _broadcast() -> void:
	_sync_state.rpc(status, progress)


func _world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _player_name(peer_id: int) -> String:
	return Network.players.get(peer_id, {}).get("name", "Alguien")


# --- RPCs (todos los peers) ------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_state(new_status: Dictionary, new_progress: Dictionary) -> void:
	status = new_status
	progress = new_progress
	quest_changed.emit()


@rpc("authority", "call_local", "reliable")
func _quest_ready(id: String) -> void:
	var quest := QuestDB.get_quest(id)
	Game.notify.emit("«%s» lista: volvé con %s" % [quest["title"], NpcDB.display_name(quest.get("giver", ""))])


@rpc("authority", "call_local", "reliable")
func _quest_completed(id: String) -> void:
	var quest := QuestDB.get_quest(id)
	Game.notify.emit("Misión completada: %s" % quest["title"])
	var rewards: Dictionary = quest.get("rewards", {})
	if not rewards.is_empty():
		Game.notify.emit("Recompensa: %s" % ItemDB.list_text(rewards))
	if quest.has("on_complete_cinematic"):
		_play_cinematic(quest["on_complete_cinematic"])


@rpc("authority", "call_local", "reliable")
func _play_cinematic(cinematic_id: String) -> void:
	var world := _world()
	if world and world.generated:
		if Game.dialog_open:
			Game.close_dialog()
		Cinematics.play(world.build_cinematic(cinematic_id))
