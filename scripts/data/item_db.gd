class_name ItemDB
extends RefCounted
## Base de datos de ítems. Para agregar un objeto nuevo, sumá una entrada acá.
##
##   name / description: texto que ve el jugador
##   stack / weight: cantidad máxima por casillero y kilos por unidad
##   icon / color: dibujo del ícono (ver item_icon.gd) y color principal
##   tool / power: tipo de herramienta ("hatchet", "pickaxe", "hammer") y multiplicador de recolección
##   damage / range / cooldown: daño, alcance (m) y segundos entre golpes al pelear
##   food / heal: hambre que calma y vida que da (o quita) al comerlo
##   blueprint: true si es un plano de construcción (click con el plano en la mano = aprenderlo)
##   capacity_bonus: kilos extra que podés cargar si lo llevás en el inventario

const ITEMS := {
	# --- Recursos ---
	"wood": {"name": "Madera", "description": "Material básico para construir, fabricar y hacer fuego.",
		"stack": 500, "weight": 0.25, "icon": "wood", "color": Color(0.62, 0.42, 0.24)},
	"stone": {"name": "Piedra", "description": "Resistente. Sirve para herramientas y construcciones sólidas.",
		"stack": 300, "weight": 0.5, "icon": "stone", "color": Color(0.62, 0.62, 0.64)},
	"fiber": {"name": "Fibra vegetal", "description": "Se arranca de las plantas altas y amarillentas y de los cactus.",
		"stack": 300, "weight": 0.1, "icon": "fiber", "color": Color(0.78, 0.8, 0.38)},
	"metal_ore": {"name": "Mineral de metal", "description": "Roca con vetas de metal. Se funde en el horno de la forja.",
		"stack": 200, "weight": 1.0, "icon": "ore", "color": Color(0.85, 0.5, 0.22)},
	"metal_fragments": {"name": "Fragmentos de metal", "description": "Metal fundido. Base de las herramientas y armas avanzadas.",
		"stack": 500, "weight": 0.4, "icon": "fragments", "color": Color(0.7, 0.74, 0.8)},
	"leather": {"name": "Cuero", "description": "Se obtiene cazando animales. Sirve para mochilas y equipo.",
		"stack": 200, "weight": 0.2, "icon": "leather", "color": Color(0.62, 0.43, 0.28)},
	# --- Materiales para reparar el barco ---
	"plank": {"name": "Tablón", "description": "Madera cepillada en la mesa de trabajo. Para el casco y la cubierta del Albatros.",
		"stack": 200, "weight": 0.8, "icon": "plank", "color": Color(0.72, 0.52, 0.3)},
	"rope": {"name": "Soga", "description": "Fibra trenzada. Sostiene mástiles y velas.",
		"stack": 100, "weight": 0.3, "icon": "rope", "color": Color(0.8, 0.7, 0.45)},
	"nails": {"name": "Clavos", "description": "Se forjan en el horno con fragmentos de metal.",
		"stack": 500, "weight": 0.05, "icon": "nails", "color": Color(0.62, 0.64, 0.7)},
	"sailcloth": {"name": "Lona", "description": "Tela fuerte de fibra y cuero. Con varias se hace una vela.",
		"stack": 50, "weight": 1.0, "icon": "cloth", "color": Color(0.92, 0.88, 0.76)},
	# --- Valdoria ---
	"coin": {"name": "Monedas de oro", "description": "La moneda de Valdoria. Se usan para comerciar con Berta, en Puerto Albor.",
		"stack": 9999, "weight": 0.0, "icon": "coin", "color": Color(1.0, 0.8, 0.25)},
	"wheat": {"name": "Trigo", "description": "Se cosecha en los campos de Robledal. Con trigo se hace pan en la fogata.",
		"stack": 200, "weight": 0.1, "icon": "wheat", "color": Color(0.9, 0.76, 0.38)},
	# --- Comida ---
	"berries": {"name": "Bayas", "description": "De los arbustos con frutos rojos. Calman un poco el hambre. A varios animales les encantan.",
		"stack": 100, "weight": 0.05, "icon": "berries", "color": Color(0.82, 0.16, 0.25), "food": 8, "heal": 1},
	"raw_meat": {"name": "Carne cruda", "description": "Mejor cocinarla en una fogata: cruda llena poco y hace mal.",
		"stack": 50, "weight": 0.3, "icon": "meat", "color": Color(0.85, 0.35, 0.35), "food": 6, "heal": -4},
	"cooked_meat": {"name": "Carne cocida", "description": "Llena mucho y recupera vida.",
		"stack": 50, "weight": 0.3, "icon": "meat", "color": Color(0.55, 0.3, 0.15), "food": 30, "heal": 10},
	"bread": {"name": "Pan", "description": "Pan casero de Robledal. Llena muchísimo y recupera vida.",
		"stack": 30, "weight": 0.3, "icon": "bread", "color": Color(0.82, 0.58, 0.3), "food": 40, "heal": 15},
	# --- Herramientas ---
	"torch": {"name": "Antorcha", "description": "Ilumina alrededor tuyo mientras la tenés en la mano. Ideal para la noche.",
		"stack": 5, "weight": 0.5, "icon": "torch", "color": Color(1.0, 0.6, 0.2), "damage": 8},
	"stone_hatchet": {"name": "Hacha de piedra", "description": "Triplica la madera que obtenés por golpe.",
		"stack": 1, "weight": 2.0, "icon": "hatchet", "tool": "hatchet", "power": 3, "damage": 12,
		"color": Color(0.7, 0.7, 0.72)},
	"stone_pickaxe": {"name": "Pico de piedra", "description": "Triplica la piedra y el mineral que obtenés por golpe.",
		"stack": 1, "weight": 2.5, "icon": "pickaxe", "tool": "pickaxe", "power": 3, "damage": 10,
		"color": Color(0.7, 0.7, 0.72)},
	"metal_hatchet": {"name": "Hacha de metal", "description": "Quintuplica la madera que obtenés por golpe.",
		"stack": 1, "weight": 2.5, "icon": "hatchet", "tool": "hatchet", "power": 5, "damage": 18,
		"color": Color(0.55, 0.68, 0.85)},
	"metal_pickaxe": {"name": "Pico de metal", "description": "Quintuplica la piedra y el mineral que obtenés por golpe.",
		"stack": 1, "weight": 3.0, "icon": "pickaxe", "tool": "pickaxe", "power": 5, "damage": 15,
		"color": Color(0.55, 0.68, 0.85)},
	"hammer": {"name": "Martillo de construcción", "description": "En la mano: R cambia de pieza, click construye, click derecho desarma.",
		"stack": 1, "weight": 1.5, "icon": "hammer", "tool": "hammer", "damage": 8, "color": Color(0.6, 0.6, 0.62)},
	# --- Armas ---
	"wooden_club": {"name": "Garrote de madera", "description": "Arma simple pero efectiva.",
		"stack": 1, "weight": 1.5, "icon": "club", "damage": 20, "range": 2.6, "cooldown": 0.7,
		"color": Color(0.55, 0.38, 0.22)},
	"stone_spear": {"name": "Lanza de piedra", "description": "Mucho alcance. Ideal para cazar.",
		"stack": 1, "weight": 2.0, "icon": "spear", "damage": 30, "range": 3.4, "cooldown": 0.85,
		"color": Color(0.65, 0.65, 0.67)},
	"metal_sword": {"name": "Espada de metal", "description": "La mejor arma contra las sombras.",
		"stack": 1, "weight": 2.5, "icon": "sword", "damage": 48, "range": 2.8, "cooldown": 0.6,
		"color": Color(0.6, 0.72, 0.88)},
	"royal_sword": {"name": "Espada real de Valdoria", "description": "Regalo de la reina Isolda. Forjada para los héroes del reino.",
		"stack": 1, "weight": 2.5, "icon": "sword", "damage": 70, "range": 3.0, "cooldown": 0.55,
		"color": Color(1.0, 0.82, 0.35)},
	# --- Equipo ---
	"large_backpack": {"name": "Mochila grande", "description": "Mientras la lleves en el inventario podés cargar 30 kg más.",
		"stack": 1, "weight": 1.0, "icon": "backpack", "capacity_bonus": 30.0, "color": Color(0.55, 0.4, 0.26)},
	# --- Planos (se encuentran en cofres o derrotando sombras) ---
	"bp_foundation": {"name": "Plano: Cimiento", "description": "Click con el plano en la mano para aprenderlo (para todo el grupo).",
		"stack": 5, "weight": 0.05, "icon": "blueprint", "blueprint": true, "color": Color(0.35, 0.55, 0.9)},
	"bp_wall": {"name": "Plano: Pared", "description": "Click con el plano en la mano para aprenderlo (para todo el grupo).",
		"stack": 5, "weight": 0.05, "icon": "blueprint", "blueprint": true, "color": Color(0.35, 0.55, 0.9)},
	"bp_doorway": {"name": "Plano: Puerta", "description": "Click con el plano en la mano para aprenderlo (para todo el grupo).",
		"stack": 5, "weight": 0.05, "icon": "blueprint", "blueprint": true, "color": Color(0.35, 0.55, 0.9)},
	"bp_roof": {"name": "Plano: Techo", "description": "Click con el plano en la mano para aprenderlo (para todo el grupo).",
		"stack": 5, "weight": 0.05, "icon": "blueprint", "blueprint": true, "color": Color(0.35, 0.55, 0.9)},
	"bp_campfire": {"name": "Plano: Fogata", "description": "Click con el plano en la mano para aprenderlo (para todo el grupo).",
		"stack": 5, "weight": 0.05, "icon": "blueprint", "blueprint": true, "color": Color(0.9, 0.55, 0.25)},
	"bp_stone": {"name": "Plano: Construcción de piedra", "description": "Desbloquea las versiones de piedra de las piezas que conozcan.",
		"stack": 5, "weight": 0.05, "icon": "blueprint", "blueprint": true, "color": Color(0.6, 0.6, 0.65)},
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


static func is_food(id: String) -> bool:
	return get_item(id).has("food")


static func is_blueprint(id: String) -> bool:
	return get_item(id).get("blueprint", false)


## Daño al pelear con este ítem en la mano ("" = puño).
static func damage(id: String) -> float:
	return get_item(id).get("damage", 6.0)


static func attack_range(id: String) -> float:
	return get_item(id).get("range", 2.4)


static func attack_cooldown(id: String) -> float:
	return get_item(id).get("cooldown", 0.55)


## Texto tipo "Madera x10, Piedra x5".
static func list_text(items: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in items:
		parts.append("%s x%d" % [item_name(id), items[id]])
	return ", ".join(parts)
