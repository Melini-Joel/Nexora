extends Node
## Sonido del juego: efectos (2D o en una posición 3D), ambientes en loop y música con
## fundido entre temas. Todos los audios están en res://audio y se generan por síntesis
## con tools/gen_audio.py (no hay samples de terceros).
##
## Uso: Sound.play("chop", posicion)  ·  Sound.set_music("day")  ·  Sound.set_ambience("rain", 1.0)

const EFFECTS := ["chop", "pick", "pluck", "swing", "hit", "hurt", "creature_hurt", "creature_die",
	"shade_whisper", "pickup", "craft_done", "build", "door", "chest_open", "eat", "ui_click", "ui_hover",
	"quest_complete", "night_sting", "thunder", "step_1", "step_2", "step_3"]
const AMBIENCES := ["wind", "rain", "fire", "waves", "night"]
const MUSIC := ["menu", "day", "night"]
const VARIANTS := {"step": 3}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _ambience: Dictionary = {}  ## nombre -> AudioStreamPlayer (loop)
var _ambience_target: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for name in EFFECTS:
		_streams[name] = _load("res://audio/%s.wav" % name, false)
	for name in AMBIENCES:
		_streams["amb_" + name] = _load("res://audio/amb_%s.wav" % name, true)
	for name in MUSIC:
		_streams["music_" + name] = _load("res://audio/music_%s.wav" % name, true)
	for i in 12:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)
	for name in AMBIENCES:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.stream = _streams["amb_" + name]
		player.volume_db = -80.0
		add_child(player)
		_ambience[name] = player
		_ambience_target[name] = 0.0
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	Settings.changed.connect(_apply_volumes)
	_apply_volumes()


func _load(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if loop and stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return stream


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(float(Settings.get_value("music_volume")), 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(float(Settings.get_value("sfx_volume")), 0.0001)))


func _make_music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "Music"
	player.volume_db = -80.0
	add_child(player)
	return player


## Efecto de sonido. Con posición: suena en 3D (más bajo cuanto más lejos).
func play(name: String, position: Vector3 = Vector3.INF, volume_db: float = 0.0, pitch_variation: float = 0.08) -> void:
	if VARIANTS.has(name):
		name = "%s_%d" % [name, randi_range(1, VARIANTS[name])]
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var pitch := 1.0 + randf_range(-pitch_variation, pitch_variation)
	if position == Vector3.INF or get_viewport().get_camera_3d() == null:
		for player in _pool:
			if not player.playing:
				player.stream = stream
				player.volume_db = volume_db
				player.pitch_scale = pitch
				player.play()
				return
		return
	var player3d := AudioStreamPlayer3D.new()
	player3d.stream = stream
	player3d.bus = "SFX"
	player3d.volume_db = volume_db
	player3d.pitch_scale = pitch
	player3d.unit_size = 6.0
	player3d.max_distance = 45.0
	get_tree().current_scene.add_child(player3d)
	player3d.global_position = position
	player3d.finished.connect(player3d.queue_free)
	player3d.play()


func get_stream(name: String) -> AudioStream:
	return _streams.get(name)


## Ambiente en loop (viento, lluvia, fuego, olas, noche). volume: 0 = apagado, 1 = normal.
func set_ambience(name: String, volume: float) -> void:
	_ambience_target[name] = clampf(volume, 0.0, 1.5)


func stop_all_ambience() -> void:
	for name in _ambience_target:
		_ambience_target[name] = 0.0


## Cambia la música con un fundido de 2 segundos ("" = silencio).
func set_music(track: String) -> void:
	if track == _music_track:
		return
	_music_track = track
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	var tween := create_tween().set_parallel()
	tween.tween_property(_music_b, "volume_db", -60.0, 2.0)
	if track != "" and _streams.has("music_" + track):
		_music_a.stream = _streams["music_" + track]
		_music_a.volume_db = -60.0
		_music_a.play()
		tween.tween_property(_music_a, "volume_db", -6.0, 2.0)


func _process(delta: float) -> void:
	for name in _ambience:
		var player: AudioStreamPlayer = _ambience[name]
		var target: float = _ambience_target[name]
		var current := db_to_linear(player.volume_db) if player.playing else 0.0
		var next := move_toward(current, target * 0.5, delta * 0.4)
		if next > 0.001 and not player.playing and player.stream:
			player.play()
		elif next <= 0.001 and player.playing:
			player.stop()
		player.volume_db = linear_to_db(maxf(next, 0.0001))
