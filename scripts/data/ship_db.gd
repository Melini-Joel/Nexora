class_name ShipDB
extends RefCounted
## Etapas para reparar el Albatros (la misión principal). Se reparan en orden, con E sobre
## los restos del barco: cada jugador aporta lo que tenga en la mochila y el progreso es
## del grupo entero. Con las cuatro etapas listas, el barco puede zarpar hacia Valdoria.

const STAGES := [
	{"id": "hull", "name": "Casco", "description": "Tapar el agujero del casco y rehacer la cubierta.",
		"items": {"plank": 40, "nails": 30}},
	{"id": "mast", "name": "Mástiles", "description": "Levantar los dos mástiles y atarlos firmes.",
		"items": {"plank": 20, "rope": 12}},
	{"id": "sails", "name": "Velas", "description": "Coser las velas nuevas y colgarlas de las vergas.",
		"items": {"sailcloth": 6, "rope": 10}},
	{"id": "helm", "name": "Timón y provisiones", "description": "Arreglar el timón y cargar comida para la travesía.",
		"items": {"plank": 10, "nails": 15, "cooked_meat": 10}},
]


static func stage_count() -> int:
	return STAGES.size()


static func get_stage(index: int) -> Dictionary:
	return STAGES[index] if index >= 0 and index < STAGES.size() else {}
