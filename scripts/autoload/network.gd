extends Node
## Conexión cooperativa de 2 a 6 jugadores usando ENet.
## El jugador que crea la partida (host) es también el servidor y tiene la autoridad
## sobre el mundo: recursos, inventarios y misiones.

signal player_joined(peer_id: int)  ## Solo en el servidor.
signal player_left(peer_id: int)  ## Solo en el servidor.
signal players_changed  ## En todos los peers.
signal joined_world(world_seed: int, world_state: Dictionary)  ## En los clientes.
signal connection_failed(reason: String)
signal disconnected

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 6

var player_name := "Jugador"
## peer_id -> {"name": String}
var players: Dictionary = {}
var world_seed := 0
var is_solo := false  ## Partida individual: nadie más se puede unir.


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT, solo: bool = false, seed_value: int = -1) -> Error:
	# En modo solo el servidor escucha solo en esta PC y no acepta a nadie más
	# (así no aparece el aviso del firewall). Si el puerto está ocupado, prueba los siguientes.
	var err := ERR_CANT_CREATE
	for attempt in (10 if solo else 1):
		var peer := ENetMultiplayerPeer.new()
		if solo:
			peer.set_bind_ip("127.0.0.1")
		# El host ocupa un lugar, así que aceptamos MAX_PLAYERS - 1 clientes.
		err = peer.create_server(port + attempt, 1 if solo else MAX_PLAYERS - 1)
		if err == OK:
			if solo:
				peer.refuse_new_connections = true
			multiplayer.multiplayer_peer = peer
			is_solo = solo
			randomize()
			world_seed = seed_value if seed_value >= 0 else randi()
			return OK
	return err


## Se llama después de generar el mundo en el host.
func add_host_player() -> void:
	_register_player(1, player_name)


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	is_solo = false


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


# --- Flujo de conexión ---------------------------------------------------------

func _on_connected_to_server() -> void:
	_request_register.rpc_id(1, player_name)


@rpc("any_peer", "reliable")
func _request_register(requested_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var clean_name := requested_name.strip_edges().substr(0, 16)
	if clean_name.is_empty():
		clean_name = "Jugador %d" % (players.size() + 1)
	var world := get_tree().get_first_node_in_group("world")
	var state: Dictionary = world.get_state_for_new_player() if world else {}
	_welcome.rpc_id(peer_id, world_seed, state)
	QuestManager.send_state_to(peer_id)
	_register_player(peer_id, clean_name)


func _register_player(peer_id: int, display_name: String) -> void:
	players[peer_id] = {"name": display_name}
	_sync_players.rpc(players)
	player_joined.emit(peer_id)
	announce.rpc("%s se unió a la partida" % display_name)


@rpc("authority", "reliable")
func _welcome(seed_value: int, state: Dictionary) -> void:
	world_seed = seed_value
	joined_world.emit(seed_value, state)


@rpc("authority", "call_local", "reliable")
func _sync_players(new_players: Dictionary) -> void:
	players = new_players
	players_changed.emit()


## Muestra un mensaje a todos los jugadores.
@rpc("authority", "call_local", "reliable")
func announce(text: String) -> void:
	Game.notify.emit(text)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or not players.has(peer_id):
		return
	var display_name: String = players[peer_id]["name"]
	players.erase(peer_id)
	_sync_players.rpc(players)
	player_left.emit(peer_id)
	announce.rpc("%s salió de la partida" % display_name)


func _on_connection_failed() -> void:
	leave_game()
	connection_failed.emit("No se pudo conectar. Revisá la IP, que el host esté abierto y que la partida no esté llena (máx. %d)." % MAX_PLAYERS)


func _on_server_disconnected() -> void:
	leave_game()
	disconnected.emit()
