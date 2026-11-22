extends CanvasLayer
## Mapa de la región donde estás, la isla o Valdoria (tecla M): relieve y biomas vistos desde arriba, con los jugadores,
## los NPCs, los lugares importantes, las camas, las mascotas, el objetivo de las misiones
## y el lugar donde moriste por última vez.

const MAP_PIXELS := 320  ## Resolución de la imagen del mapa.
const LANDMARKS := {
	"spawn": "Campamento", "furnace": "Forja", "hermit_npc": "Ermitaño", "dock_npc": "Muelle",
	"lookout": "Mirador", "monolith": "Monolito", "wreck": "El Albatros",
	"harbor": "Puerto Albor", "village": "Robledal", "castle": "Castillo de Valdoria", "bandit_camp": "Campamento bandido",
}

var _title: Label
var _region := ""

var _view: MapView


## Dibuja el mapa y los marcadores (se redibuja mientras está abierto).
class MapView extends Control:
	var texture: Texture2D
	var world: Node
	var time := 0.0
	var region_center := Vector2.ZERO
	var region_size := TerrainGenerator.SIZE

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _map_rect() -> Rect2:
		var side := minf(size.x - 380.0, size.y - 120.0)
		return Rect2(Vector2((size.x - 300.0 - side) / 2.0, (size.y - side) / 2.0 + 20.0), Vector2(side, side))

	func to_map(p: Vector3) -> Vector2:
		var rect := _map_rect()
		var half := region_size * 0.5
		return rect.position + Vector2((p.x - region_center.x + half) / region_size, (p.z - region_center.y + half) / region_size) * rect.size

	## ¿El punto está en la región que muestra el mapa?
	func shows(p: Vector3) -> bool:
		return absf(p.x - region_center.x) <= region_size * 0.5 and absf(p.z - region_center.y) <= region_size * 0.5

	func _draw() -> void:
		if texture == null or world == null:
			return
		var rect := _map_rect()
		var font := ThemeDB.fallback_font
		draw_rect(rect.grow(6), Color(0.05, 0.06, 0.07, 0.95))
		draw_texture_rect(texture, rect, false)
		draw_rect(rect, Color(0.9, 0.85, 0.7, 0.6), false, 2.0)
		draw_string(font, rect.position + Vector2(rect.size.x / 2 - 6, -10), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.6))
		# Lugares importantes.
		for key: String in LANDMARKS:
			if world.landmarks.has(key) and shows(world.landmarks[key]):
				var p := to_map(world.landmarks[key])
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)]), Color(1, 0.85, 0.45))
				_label(p + Vector2(10, 5), LANDMARKS[key], Color(1, 0.92, 0.75), 15)
		# Objetivos de misiones activas ("llegar a").
		for id in QuestManager.active_quests():
			for objective in QuestDB.get_quest(id)["objectives"]:
				if objective["type"] == "reach" and world.landmarks.has(objective["target"]) and shows(world.landmarks[objective["target"]]):
					var p := to_map(world.landmarks[objective["target"]])
					draw_arc(p, 12.0 + sin(time * 4.0) * 3.0, 0, TAU, 24, Color(1, 0.8, 0.2), 2.5)
		# NPCs.
		for npc in world.get_children():
			if npc is NPC and shows(npc.global_position):
				var p := to_map(npc.global_position)
				draw_circle(p, 5.0, Color(0.45, 0.75, 1.0))
				_label(p + Vector2(8, -6), NpcDB.display_name(npc.npc_id), Color(0.7, 0.85, 1.0), 13)
		# Construcciones (un punto por pieza) y camas.
		for piece in world.pieces_root.get_children():
			if piece is BuildPiece and shows(piece.global_position):
				var p := to_map(piece.global_position)
				if piece.kind() == "bed":
					draw_rect(Rect2(p - Vector2(5, 4), Vector2(10, 8)), Color(0.95, 0.5, 0.4))
					if piece.owner_name == Network.player_name:
						_label(p + Vector2(8, 4), "Tu cama", Color(1, 0.7, 0.6), 13)
				else:
					draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(0.85, 0.65, 0.4))
		# Mascotas.
		for creature in world.creatures_root.get_children():
			if creature is Creature and creature.tamed_owner != "" and not creature.dead and shows(creature.global_position):
				draw_circle(to_map(creature.global_position), 4.0, Color(0.5, 1.0, 0.5))
		# Donde moriste.
		if Game.last_death_position != Vector3.INF and shows(Game.last_death_position):
			var p := to_map(Game.last_death_position)
			draw_line(p - Vector2(6, 6), p + Vector2(6, 6), Color(1, 0.3, 0.3), 3.0)
			draw_line(p - Vector2(6, -6), p + Vector2(6, -6), Color(1, 0.3, 0.3), 3.0)
			_label(p + Vector2(9, 5), "Tus cosas", Color(1, 0.55, 0.5), 13)
		# Jugadores: flecha en la dirección en la que miran.
		for player in world.get_players():
			if not shows(player.global_position):
				continue
			var p := to_map(player.global_position)
			var yaw: float = player.model.rotation.y
			var dir := Vector2(-sin(yaw), -cos(yaw))
			var side := Vector2(-dir.y, dir.x)
			var is_me: bool = player == Game.local_player
			var color := Color(1, 1, 1) if is_me else Color(0.6, 1.0, 0.85)
			draw_colored_polygon(PackedVector2Array([p + dir * 11, p - dir * 7 + side * 7, p - dir * 3, p - dir * 7 - side * 7]), color)
			_label(p + Vector2(12, -8), "Vos" if is_me else player.player_name, color, 14)

	func _label(pos: Vector2, text: String, color: Color, size: int) -> void:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _ready() -> void:
	layer = 25
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_view = MapView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	_build_legend()
	Game.map_open_changed.connect(_on_toggled)


func _build_legend() -> void:
	var panel := UIStyle.panel(Color(0.05, 0.07, 0.09, 0.9), 16)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_right = -30
	panel.offset_top = -220
	panel.offset_bottom = 220
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_title = UIStyle.label("MAPA DE LA ISLA", 20, UIStyle.ACCENT)
	box.add_child(_title)
	for entry in [["Pradera", TerrainGenerator.BIOME_COLORS[0][0]], ["Bosque", TerrainGenerator.BIOME_COLORS[1][0]],
			["Desierto", TerrainGenerator.BIOME_COLORS[2][0]], ["Tundra nevada", TerrainGenerator.BIOME_COLORS[3][0]],
			["Vos y tus compañeros", Color(0.7, 1.0, 0.9)], ["Habitantes", Color(0.45, 0.75, 1.0)],
			["Lugares", Color(1, 0.85, 0.45)], ["Objetivo de misión", Color(1, 0.8, 0.2)],
			["Construcciones / camas", Color(0.9, 0.6, 0.45)], ["Mascotas", Color(0.5, 1.0, 0.5)]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.color = entry[1]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		row.add_child(UIStyle.label(entry[0], 15))
		box.add_child(row)
	box.add_child(UIStyle.label("M o Esc: cerrar", 13, UIStyle.TEXT_DIM))


func _on_toggled(is_open: bool) -> void:
	visible = is_open
	if not is_open:
		return
	_view.world = get_tree().get_first_node_in_group("world")
	var terrain: TerrainGenerator = _view.world.terrain
	var me: Node3D = Game.local_player
	var here := me.global_position if me else Vector3.ZERO
	var region_id := terrain.region_at(here.x, here.z)
	if region_id == "":
		region_id = "mainland" if here.x > TerrainGenerator.MAINLAND_CENTER.x * 0.5 and terrain.mainland else "island"
	if region_id != _region or _view.texture == null:
		_region = region_id
		var region := terrain.region_of(region_id)
		_view.region_center = region.center
		_view.region_size = region.size
		_view.texture = _render_terrain(terrain, region)
		_title.text = "MAPA DE VALDORIA" if region_id == "mainland" else "MAPA DE LA ISLA"


## Imagen de la región desde arriba: color del bioma, caminos, relieve y profundidad del agua.
func _render_terrain(terrain: TerrainGenerator, region: TerrainGenerator.Region) -> Texture2D:
	var image := Image.create(MAP_PIXELS, MAP_PIXELS, false, Image.FORMAT_RGB8)
	var half := region.size * 0.5
	var step := region.size / MAP_PIXELS
	var mainland := region.id == "mainland"
	var biome_index := {"meadow": 0, "forest": 1, "desert": 2, "tundra": 3}
	for py in MAP_PIXELS:
		for px in MAP_PIXELS:
			var x := region.center.x - half + (px + 0.5) * step
			var z := region.center.y - half + (py + 0.5) * step
			var h := terrain.get_height(x, z)
			var color: Color
			if h < TerrainGenerator.WATER_LEVEL:
				var depth := clampf((TerrainGenerator.WATER_LEVEL - h) / 14.0, 0.0, 1.0)
				color = Color(0.32, 0.6, 0.72).lerp(Color(0.08, 0.22, 0.4), depth)
			elif h < TerrainGenerator.WATER_LEVEL + 0.8:
				color = TerrainGenerator.SAND
			else:
				var colors: Array = TerrainGenerator.BIOME_COLORS[biome_index[terrain.get_biome(x, z)]]
				color = (colors[0] as Color).lerp(colors[1], clampf(h / TerrainGenerator.SNOW_HEIGHT, 0, 1))
				if mainland:
					var lx := x - region.center.x
					var lz := z - region.center.y
					if TerrainGenerator.in_field(lx, lz):
						color = Color(0.78, 0.66, 0.35)
					color = color.lerp(TerrainGenerator.DIRT, TerrainGenerator.road_factor(lx, lz))
				if h > TerrainGenerator.SNOW_HEIGHT + 4.0:
					color = TerrainGenerator.SNOW
				# Sombreado: las laderas que miran al noroeste se ven más claras.
				var shade := (terrain.get_height(x - step, z - step) - h) * 0.06
				color = color.lightened(clampf(shade, 0, 0.3)) if shade > 0 else color.darkened(clampf(-shade, 0, 0.35))
			image.set_pixel(px, py, color)
	return ImageTexture.create_from_image(image)
