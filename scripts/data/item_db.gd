class_name ItemDB
extends RefCounted
## Base de datos de ítems. Para agregar un objeto nuevo, sumá una entrada acá.
##
##   name / description: texto que ve el jugador
##   stack: cantidad máxima por casillero
##   weight: kilos por unidad (afecta la velocidad del jugador)
##   icon: dibujo del ícono (ver item_icon.gd)
##   color: color principal (ícono, bolsa en el suelo, cabeza de la herramienta)
##   tool / power: tipo de herramienta ("hatchet" = hacha, "pickaxe" = pico) y multiplicador
##   capacity_bonus: kilos extra que podés cargar si lo llevás en el inventario

const ITEMS := {
	"wood": {
		"name": "Madera",
		"description": "Material básico para construir, fabricar y hacer fuego.",
		"stack": 500, "weight": 0.25, "icon": "wood", "color": Color(0.62, 0.42, 0.24),
	},
	"stone": {
		"name": "Piedra",
		"description": "Resistente. Sirve para herramientas y construcciones sólidas.",
		"stack": 300, "weight": 0.5, "icon": "stone", "color": Color(0.62, 0.62, 0.64),
	},
	"fiber": {
		"name": "Fibra vegetal",
		"description": "Se arranca de las plantas altas y amarillentas. Sirve para tela y cuerdas.",
		"stack": 300, "weight": 0.1, "icon": "fiber", "color": Color(0.78, 0.8, 0.38),
	},
	"metal_ore": {
		"name": "Mineral de metal",
		"description": "Roca con vetas de metal. Se funde en el horno de la forja.",
		"stack": 200, "weight": 1.0, "icon": "ore", "color": Color(0.85, 0.5, 0.22),
	},
	"metal_fragments": {
		"name": "Fragmentos de metal",
		"description": "Metal fundido. Base de las herramientas avanzadas.",
		"stack": 500, "weight": 0.4, "icon": "fragments", "color": Color(0.7, 0.74, 0.8),
	},
	"torch": {
		"name": "Antorcha",
		"description": "Ilumina alrededor tuyo mientras la tenés en la mano.",
		"stack": 5, "weight": 0.5, "icon": "torch", "color": Color(1.0, 0.6, 0.2),
	},
	"stone_hatchet": {
		"name": "Hacha de piedra",
		"description": "Triplica la madera que obtenés por golpe.",
		"stack": 1, "weight": 2.0, "icon": "hatchet", "tool": "hatchet", "power": 3,
		"color": Color(0.7, 0.7, 0.72),
	},
	"stone_pickaxe": {
		"name": "Pico de piedra",
		"description": "Triplica la piedra y el mineral que obtenés por golpe.",
		"stack": 1, "weight": 2.5, "icon": "pickaxe", "tool": "pickaxe", "power": 3,
		"color": Color(0.7, 0.7, 0.72),
	},
	"metal_hatchet": {
		"name": "Hacha de metal",
		"description": "Quintuplica la madera que obtenés por golpe.",
		"stack": 1, "weight": 2.5, "icon": "hatchet", "tool": "hatchet", "power": 5,
		"color": Color(0.55, 0.68, 0.85),
	},
	"metal_pickaxe": {
		"name": "Pico de metal",
		"description": "Quintuplica la piedra y el mineral que obtenés por golpe.",
		"stack": 1, "weight": 3.0, "icon": "pickaxe", "tool": "pickaxe", "power": 5,
		"color": Color(0.55, 0.68, 0.85),
	},
	"large_backpack": {
		"name": "Mochila grande",
		"description": "Mientras la lleves en el inventario podés cargar 30 kg más.",
		"stack": 1, "weight": 1.0, "icon": "backpack", "capacity_bonus": 30.0,
		"color": Color(0.55, 0.4, 0.26),
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


static func tool_power(id: String) -> int:
	return get_item(id).get("power", 1)


## Texto tipo "Madera x10, Piedra x5".
static func list_text(items: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in items:
		parts.append("%s x%d" % [item_name(id), items[id]])
	return ", ".join(parts)
