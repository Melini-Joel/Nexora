class_name RecipeDB
extends RefCounted
## Recetas de fabricación. Para agregar una, sumá una entrada acá.
##
##   result / amount: qué se obtiene y cuántos por fabricación
##   ingredients: materiales que se gastan
##   time: segundos por fabricación
##   station: (opcional) hay que estar cerca de esa estación: "workbench" o "furnace"
##   name: (opcional) nombre a mostrar si no es el del ítem

const STATION_RANGE := 7.0
const STATIONS := {"workbench": "Mesa de trabajo (campamento)", "furnace": "Horno de la forja"}

const RECIPES := {
	"torch": {
		"result": "torch", "amount": 1, "time": 2.0,
		"ingredients": {"wood": 10, "fiber": 5},
	},
	"stone_hatchet": {
		"result": "stone_hatchet", "amount": 1, "time": 4.0,
		"ingredients": {"wood": 40, "stone": 20},
	},
	"stone_pickaxe": {
		"result": "stone_pickaxe", "amount": 1, "time": 4.0,
		"ingredients": {"wood": 40, "stone": 30},
	},
	"large_backpack": {
		"result": "large_backpack", "amount": 1, "time": 8.0,
		"ingredients": {"fiber": 60, "wood": 30}, "station": "workbench",
	},
	"metal_fragments": {
		"result": "metal_fragments", "amount": 5, "time": 4.0, "name": "Fundir metal (x5)",
		"ingredients": {"metal_ore": 5, "wood": 5}, "station": "furnace",
	},
	"metal_hatchet": {
		"result": "metal_hatchet", "amount": 1, "time": 8.0,
		"ingredients": {"wood": 30, "metal_fragments": 25}, "station": "workbench",
	},
	"metal_pickaxe": {
		"result": "metal_pickaxe", "amount": 1, "time": 8.0,
		"ingredients": {"wood": 30, "metal_fragments": 35}, "station": "workbench",
	},
}


static func get_recipe(id: String) -> Dictionary:
	return RECIPES.get(id, {})


static func display_name(id: String) -> String:
	var recipe := get_recipe(id)
	return recipe.get("name", ItemDB.item_name(recipe.get("result", id)))


## Cuántas veces se puede fabricar con estos casilleros.
static func max_craftable(id: String, slots: Array) -> int:
	var recipe := get_recipe(id)
	if recipe.is_empty():
		return 0
	var result := 9999
	var ingredients: Dictionary = recipe["ingredients"]
	for item: String in ingredients:
		result = mini(result, Inventory.count_in(slots, item) / int(ingredients[item]))
	return result
