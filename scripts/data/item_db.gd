class_name ItemDB
extends RefCounted
## Base de datos de ítems. Para agregar un objeto nuevo, sumá una entrada acá.
##
##   name / description: texto que ve el jugador
##   stack: cantidad máxima por casillero
##   weight: kilos por unidad (afecta la velocidad del jugador)
##   icon: dibujo del ícono (ver item_icon.gd)
##   tool: tipo de herramienta ("hatchet" = hacha, "pickaxe" = pico)

const ITEMS := {
	"wood": {
		"name": "Madera",
		"description": "Material básico para construir y hacer fuego.",
		"stack": 250, "weight": 0.25, "icon": "wood", "color": Color(0.62, 0.42, 0.24),
	},
	"stone": {
		"name": "Piedra",
		"description": "Resistente. Sirve para herramientas y construcciones sólidas.",
		"stack": 150, "weight": 0.6, "icon": "stone", "color": Color(0.62, 0.62, 0.64),
	},
	"metal_ore": {
		"name": "Mineral de metal",
		"description": "Roca con vetas de metal. Se funde en un horno (próximamente).",
		"stack": 100, "weight": 1.2, "icon": "ore", "color": Color(0.85, 0.5, 0.22),
	},
	"stone_hatchet": {
		"name": "Hacha de piedra",
		"description": "Triplica la madera que obtenés por golpe.",
		"stack": 1, "weight": 2.0, "icon": "hatchet", "tool": "hatchet", "color": Color(0.7, 0.7, 0.72),
	},
	"stone_pickaxe": {
		"name": "Pico de piedra",
		"description": "Triplica la piedra y el mineral que obtenés por golpe.",
		"stack": 1, "weight": 2.5, "icon": "pickaxe", "tool": "pickaxe", "color": Color(0.7, 0.7, 0.72),
	},
}

const TOOL_NAMES := {"hatchet": "hacha", "pickaxe": "pico"}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func item_name(id: String) -> String:
	return get_item(id).get("name", id)


static func description(id: String) -> String:
	return get_item(id).get("description", "")


static func stack_size(id: String) -> int:
	return get_item(id).get("stack", 1)


static func weight(id: String) -> float:
	return get_item(id).get("weight", 0.0)


static func color(id: String) -> Color:
	return get_item(id).get("color", Color.WHITE)


static func icon(id: String) -> String:
	return get_item(id).get("icon", "")


static func tool_type(id: String) -> String:
	return get_item(id).get("tool", "")
