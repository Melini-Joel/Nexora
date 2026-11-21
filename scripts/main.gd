extends Node
## Punto de entrada: menú principal → mundo cooperativo.
##
## Para probar rápido desde la línea de comandos (todo lo que va después de "--"):
##   godot -- --solo --name=Ana        (partida individual)
##   godot -- --host --name=Ana
##   godot -- --join=127.0.0.1 --name=Beto

const MainMenu := preload("res://scripts/ui/main_menu.gd")
const Hud := preload("res://scripts/ui/hud.gd")

var menu: CanvasLayer
var hud: CanvasLayer
var _intro_pending := false
var _backdrop: Node3D

@onready var world: Node3D = $World


func _ready() -> void:
	# Fondo animado del menú (no hace falta si se arranca directo desde la línea de comandos).
	if OS.get_cmdline_user_args().is_empty():
		_backdrop = MenuBackdrop.new()
		add_child(_backdrop)
	menu = MainMenu.new()
	add_child(menu)
	menu.solo_pressed.connect(_on_solo_pressed)
	menu.host_pressed.connect(_on_host_pressed)
	menu.join_pressed.connect(_on_join_pressed)
	Network.joined_world.connect(_on_joined_world)
	Network.connection_failed.connect(_on_connection_failed)
	Network.disconnected.connect(func(): _return_to_menu("Se perdió la conexión con el host."))
	Game.local_player_spawned.connect(func(_player: Node): _try_play_intro())
	Game.quit_to_menu_requested.connect(func(): _return_to_menu(""))
	_handle_command_line()


func _on_solo_pressed(player_name: String) -> void:
	_start_hosting(player_name, true)


func _on_host_pressed(player_name: String) -> void:
	_start_hosting(player_name, false)


func _start_hosting(player_name: String, solo: bool) -> void:
	Network.player_name = player_name
	var err := Network.host_game(Network.DEFAULT_PORT, solo)
	if err != OK:
		menu.set_status("No se pudo crear la partida (¿el puerto %d está en uso?)." % Network.DEFAULT_PORT, true)
		return
	QuestManager.reset()
	_enter_world(Network.world_seed, {})
	Network.add_host_player()
	QuestManager.server_start()


func _on_join_pressed(player_name: String, address: String) -> void:
	Network.player_name = player_name
	var err := Network.join_game(address)
	if err != OK:
		menu.set_status("Dirección inválida.", true)
		return
	menu.set_status("Conectando a %s..." % address)
	menu.set_busy(true)


func _on_joined_world(world_seed: int, state: Dictionary) -> void:
	_enter_world(world_seed, state)


func _on_connection_failed(reason: String) -> void:
	menu.set_busy(false)
	menu.set_status(reason, true)


func _enter_world(world_seed: int, state: Dictionary) -> void:
	menu.visible = false
	if is_instance_valid(_backdrop):
		remove_child(_backdrop)
		_backdrop.queue_free()
	world.generate(world_seed)
	world.apply_state(state)
	hud = Hud.new()
	add_child(hud)
	_intro_pending = true
	_try_play_intro()


func _try_play_intro() -> void:
	if not _intro_pending or Game.local_player == null or not world.generated:
		return
	_intro_pending = false
	Cinematics.play(world.build_cinematic("intro"))


func _return_to_menu(message: String) -> void:
	Cinematics.stop()
	Network.leave_game()
	Game.reset()
	QuestManager.reset()
	Game.pending_menu_message = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _handle_command_line() -> void:
	var player_name := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--name="):
			player_name = arg.trim_prefix("--name=")
	for arg in OS.get_cmdline_user_args():
		if arg == "--solo":
			_on_solo_pressed(player_name if player_name else "Solo")
		elif arg == "--host":
			_on_host_pressed(player_name if player_name else "Host")
		elif arg.begins_with("--join="):
			_on_join_pressed(player_name if player_name else "Invitado", arg.trim_prefix("--join="))
