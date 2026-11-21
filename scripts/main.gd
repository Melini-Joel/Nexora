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
	Sound.stop_all_ambience()
	Sound.set_music("menu")
	Sound.set_ambience("fire", 0.5 if _backdrop else 0.0)
	Sound.set_ambience("wind", 0.4 if _backdrop else 0.0)
	menu.start_pressed.connect(_start_hosting)
	menu.join_pressed.connect(_on_join_pressed)
	Network.joined_world.connect(_on_joined_world)
	Network.connection_failed.connect(_on_connection_failed)
	Network.disconnected.connect(func(): _return_to_menu("Se perdió la conexión con el host."))
	Game.local_player_spawned.connect(func(_player: Node): _try_play_intro())
	Game.quit_to_menu_requested.connect(func(): _return_to_menu(""))
	_handle_command_line()


## Crea la partida (solo o para amigos). slot = mundo guardado a cargar, "" = mundo nuevo.
## save = false solo para pruebas rápidas desde la línea de comandos (no guarda nada).
func _start_hosting(player_name: String, solo: bool, slot: String, world_name: String, save: bool = true) -> void:
	var data := SaveManager.load_data(slot) if slot != "" else {}
	if slot != "" and data.is_empty():
		menu.set_status("No se pudo leer ese mundo guardado.", true)
		return
	Network.player_name = player_name
	var err := Network.host_game(Network.DEFAULT_PORT, solo, int(data.get("seed", -1)))
	if err != OK:
		menu.set_status("No se pudo crear la partida (¿el puerto %d está en uso?)." % Network.DEFAULT_PORT, true)
		return
	QuestManager.reset()
	if save:
		var meta: Dictionary = data.get("meta", {})
		SaveManager.begin(slot, meta.get("name", world_name), meta.get("play_time", 0.0))
	_enter_world(Network.world_seed, {}, data.is_empty())
	if not data.is_empty():
		world.load_save(data)
		QuestManager.load_state(data.get("quests", {}))
	Network.add_host_player()
	QuestManager.server_start()
	if save and data.is_empty():
		SaveManager.save_game()  # El mundo nuevo ya aparece en la lista.
	elif not data.is_empty():
		Game.notify.emit("Mundo cargado: %s (día %d)" % [SaveManager.current_name, world.day_night.day])


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


func _enter_world(world_seed: int, state: Dictionary, play_intro: bool = true) -> void:
	menu.visible = false
	Sound.stop_all_ambience()
	if is_instance_valid(_backdrop):
		remove_child(_backdrop)
		_backdrop.queue_free()
	world.generate(world_seed)
	world.apply_state(state)
	hud = Hud.new()
	add_child(hud)
	_intro_pending = play_intro
	_try_play_intro()


func _try_play_intro() -> void:
	if not _intro_pending or Game.local_player == null or not world.generated:
		return
	_intro_pending = false
	Cinematics.play(world.build_cinematic("intro"))


func _return_to_menu(message: String) -> void:
	SaveManager.save_game()  # Solo hace algo si sos el host de un mundo guardado.
	SaveManager.end()
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
			_start_hosting(player_name if player_name else "Solo", true, "", "", false)
		elif arg == "--host":
			_start_hosting(player_name if player_name else "Host", false, "", "", false)
		elif arg.begins_with("--load="):  # Cargar un mundo guardado: --load=<archivo sin .save>
			_start_hosting(player_name if player_name else "Host", false, arg.trim_prefix("--load="), "")
		elif arg.begins_with("--world="):  # Mundo nuevo que se guarda: --world=<nombre>
			_start_hosting(player_name if player_name else "Host", false, "", arg.trim_prefix("--world="))
		elif arg.begins_with("--join="):
			_on_join_pressed(player_name if player_name else "Invitado", arg.trim_prefix("--join="))
