class_name CreatureDB
extends RefCounted
## Animales y criaturas.
##
##   behavior: flee (huye), neutral (se defiende si lo atacan), wolf (neutral de día,
##             agresivo de noche), mob (criatura nocturna: busca y ataca jugadores),
##             hostile (bandidos: atacan a quien se acerque, pero no se alejan de su campamento)
##   camp / aggro: lugar del continente donde viven y distancia a la que te ven
##   biomes: dónde aparecen (meadow, forest, desert, tundra)
##   count: cuántos hay en la isla a la vez
##   drops: lo que recibe quien lo mata
##   tame: {"food", "amount", "combat"}: comida para domesticarlo, cuántas veces darle
##         y si pelea a tu lado una vez domesticado
##   look: apariencia (ver Quadruped.build)

const SPECIES := {
	"rabbit": {
		"name": "Conejo", "body": "quadruped", "behavior": "flee", "health": 20.0, "speed": 6.5,
		"damage": 0.0, "biomes": ["meadow"], "count": 10,
		"drops": {"raw_meat": 1, "leather": 1},
		"tame": {"food": "berries", "amount": 3, "combat": false},
		"look": {"size": 0.32, "color": Color(0.7, 0.6, 0.48), "ears": "long", "tail": "puff", "snout": 0.4},
	},
	"deer": {
		"name": "Ciervo", "body": "quadruped", "behavior": "flee", "health": 60.0, "speed": 7.5,
		"damage": 0.0, "biomes": ["meadow", "forest"], "count": 12,
		"drops": {"raw_meat": 4, "leather": 3},
		"tame": {"food": "berries", "amount": 8, "combat": false},
		"look": {"size": 1.0, "color": Color(0.6, 0.42, 0.26), "ears": "small", "tail": "short",
			"antlers": true, "legs": 1.25, "snout": 0.8},
	},
	"boar": {
		"name": "Jabalí", "body": "quadruped", "behavior": "neutral", "health": 90.0, "speed": 4.6,
		"damage": 12.0, "biomes": ["forest", "meadow"], "count": 8,
		"drops": {"raw_meat": 5, "leather": 4},
		"tame": {"food": "raw_meat", "amount": 5, "combat": true},
		"look": {"size": 0.75, "color": Color(0.32, 0.25, 0.2), "ears": "small", "tail": "thin",
			"tusks": true, "legs": 0.7, "snout": 0.9},
	},
	"wolf": {
		"name": "Lobo", "body": "quadruped", "behavior": "wolf", "health": 80.0, "speed": 5.6,
		"damage": 14.0, "biomes": ["forest", "tundra"], "count": 8,
		"drops": {"raw_meat": 3, "leather": 4},
		"tame": {"food": "cooked_meat", "amount": 6, "combat": true},
		"look": {"size": 0.75, "color": Color(0.5, 0.5, 0.52), "ears": "pointy", "tail": "long", "snout": 1.0},
	},
	"bear": {
		"name": "Oso", "body": "quadruped", "behavior": "neutral", "health": 260.0, "speed": 4.8,
		"damage": 26.0, "biomes": ["tundra", "forest"], "count": 4,
		"drops": {"raw_meat": 10, "leather": 12},
		"tame": {"food": "cooked_meat", "amount": 12, "combat": true},
		"look": {"size": 1.45, "color": Color(0.36, 0.24, 0.16), "ears": "round", "tail": "short",
			"legs": 0.85, "snout": 0.7},
	},
	"lizard": {
		"name": "Lagarto de arena", "body": "quadruped", "behavior": "flee", "health": 35.0, "speed": 7.0,
		"damage": 0.0, "biomes": ["desert"], "count": 8,
		"drops": {"raw_meat": 2, "leather": 3},
		"look": {"size": 0.5, "color": Color(0.78, 0.66, 0.4), "ears": "none", "tail": "lizard",
			"legs": 0.45, "snout": 1.0},
	},
	# --- Criaturas nocturnas ---
	"shade": {
		"name": "Sombra", "body": "humanoid", "behavior": "mob", "health": 60.0, "speed": 3.4,
		"damage": 7.0, "drops": {"metal_fragments": 3}, "blueprint_chance": 0.3, "scale": 1.5,
		"look": {"model": "shade"},
	},
	"brute": {
		"name": "Bruto sombrío", "body": "humanoid", "behavior": "mob", "health": 170.0, "speed": 2.8,
		"damage": 16.0, "drops": {"metal_fragments": 10, "leather": 4}, "blueprint_chance": 0.6, "scale": 1.6,
		"look": {"model": "brute"},
	},
	# --- Bandidos de Valdoria (viven en su campamento, de día y de noche) ---
	"bandit": {
		"name": "Bandido", "body": "humanoid", "behavior": "hostile", "health": 90.0, "speed": 3.9,
		"damage": 8.0, "drops": {"coin": 6, "leather": 2}, "scale": 1.0, "camp": "bandits", "aggro": 15.0,
		"look": {
			"skin": Color(0.78, 0.6, 0.45), "hair": Color(0.15, 0.1, 0.08),
			"shirt": Color(0.35, 0.28, 0.2), "pants": Color(0.25, 0.22, 0.18),
			"boots": Color(0.18, 0.13, 0.1), "accessories": ["hood", "bandana", "sword"],
		},
	},
	"bandit_chief": {
		"name": "Rurik, jefe bandido", "body": "humanoid", "behavior": "hostile", "health": 420.0, "speed": 3.6,
		"damage": 18.0, "drops": {"coin": 60, "metal_fragments": 20}, "scale": 1.2, "camp": "bandits", "aggro": 18.0,
		"look": {
			"skin": Color(0.72, 0.52, 0.38), "hair": Color(0.5, 0.15, 0.08),
			"shirt": Color(0.4, 0.08, 0.08), "pants": Color(0.2, 0.18, 0.16),
			"boots": Color(0.15, 0.1, 0.08), "accessories": ["chainmail", "long_beard", "cape_red", "sword"],
		},
	},
}

const PET_BENEFITS := {
	"rabbit": "Mascota: te sigue a todos lados.",
	"deer": "Mascota: te sigue y no huye de vos.",
	"boar": "Pelea a tu lado contra las sombras (daño 12).",
	"wolf": "Pelea a tu lado, es rápido y te defiende de noche (daño 14).",
	"bear": "Guardián: pelea a tu lado con mucha vida y daño (daño 26).",
}


static func get_species(id: String) -> Dictionary:
	return SPECIES.get(id, {})


static func display_name(id: String) -> String:
	return get_species(id).get("name", id)


static func is_mob(id: String) -> bool:
	return get_species(id).get("behavior", "") == "mob"
