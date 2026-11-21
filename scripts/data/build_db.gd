class_name BuildDB
extends RefCounted
## Piezas de construcción. Se desbloquean aprendiendo planos (ítems "bp_...").
##
##   kind: foundation (cimiento), wall (pared), doorway (pared con puerta), roof (techo/piso),
##         campfire (fogata, funciona como estación de cocina), storage (caja de almacenamiento),
##         bed (cama: reaparecés ahí al morir)
##   cost: materiales que gasta
##   requires: planos que tiene que conocer el grupo ([] = disponible desde el principio)
##   material: "wood" o "stone" (define el aspecto)

const GRID := 3.0  ## Tamaño de cada casillero de construcción (m).
const WALL_HEIGHT := 3.0
const BUILD_RANGE := 9.0

const STORAGE_SLOTS := 18  ## Casilleros de una caja de almacenamiento.

const PIECES := {
	"storage_box": {"name": "Caja de almacenamiento", "kind": "storage", "material": "wood",
		"cost": {"wood": 80}, "requires": []},
	"bed": {"name": "Cama", "kind": "bed", "material": "wood",
		"cost": {"wood": 40, "fiber": 40}, "requires": []},
	"wood_foundation": {"name": "Cimiento de madera", "kind": "foundation", "material": "wood",
		"cost": {"wood": 60}, "requires": ["bp_foundation"]},
	"wood_wall": {"name": "Pared de madera", "kind": "wall", "material": "wood",
		"cost": {"wood": 40}, "requires": ["bp_wall"]},
	"wood_doorway": {"name": "Puerta de madera", "kind": "doorway", "material": "wood",
		"cost": {"wood": 55}, "requires": ["bp_doorway"]},
	"wood_roof": {"name": "Techo de madera", "kind": "roof", "material": "wood",
		"cost": {"wood": 50}, "requires": ["bp_roof"]},
	"campfire": {"name": "Fogata", "kind": "campfire", "material": "wood",
		"cost": {"wood": 30, "stone": 10}, "requires": ["bp_campfire"]},
	"stone_foundation": {"name": "Cimiento de piedra", "kind": "foundation", "material": "stone",
		"cost": {"stone": 80}, "requires": ["bp_foundation", "bp_stone"]},
	"stone_wall": {"name": "Pared de piedra", "kind": "wall", "material": "stone",
		"cost": {"stone": 60}, "requires": ["bp_wall", "bp_stone"]},
	"stone_doorway": {"name": "Puerta de piedra", "kind": "doorway", "material": "stone",
		"cost": {"stone": 70, "wood": 15}, "requires": ["bp_doorway", "bp_stone"]},
	"stone_roof": {"name": "Techo de piedra", "kind": "roof", "material": "stone",
		"cost": {"stone": 70}, "requires": ["bp_roof", "bp_stone"]},
}


static func get_piece(id: String) -> Dictionary:
	return PIECES.get(id, {})


static func is_unlocked(id: String, known: Array) -> bool:
	for blueprint: String in get_piece(id).get("requires", ["?"]):
		if not blueprint in known:
			return false
	return true


static func unlocked_pieces(known: Array) -> Array:
	var result: Array = []
	for id: String in PIECES:
		if is_unlocked(id, known):
			result.append(id)
	return result
