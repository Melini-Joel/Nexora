class_name NpcDB
extends RefCounted
## Personajes de la isla. "place" es el lugar del mundo donde aparecen (ver world.gd).
## "look" define su apariencia (ver Humanoid.build) y "greetings" lo que dicen al saludar.

const NPCS := {
	"tomas": {
		"name": "Tomás", "title": "Leñador", "place": "camp_npc",
		"look": {
			"skin": Color(0.86, 0.68, 0.52), "hair": Color(0.32, 0.2, 0.12),
			"shirt": Color(0.66, 0.2, 0.17), "pants": Color(0.24, 0.3, 0.42),
			"boots": Color(0.3, 0.2, 0.13), "accessories": ["beard", "cap"],
		},
		"greetings": [
			"¡Ah, por fin despertaron! Esta isla no perdona a los que trabajan solos.",
			"El fuego no se mantiene solo. ¿En qué los puedo ayudar?",
			"Si algo aprendí acá es que de a varios se trabaja el doble de rápido.",
		],
		"idle": "Por ahora no tengo más trabajo. Vayan a ver a los demás de la isla.",
	},
	"ilse": {
		"name": "Ilse", "title": "Herrera", "place": "forge_npc",
		"look": {
			"skin": Color(0.95, 0.8, 0.68), "hair": Color(0.65, 0.25, 0.1),
			"shirt": Color(0.38, 0.33, 0.3), "pants": Color(0.22, 0.2, 0.2),
			"boots": Color(0.2, 0.15, 0.12), "accessories": ["apron", "bun"],
		},
		"greetings": [
			"Cuidado con el horno, que muerde. ¿Traen metal?",
			"La piedra sirve, pero el metal es otra cosa. Ya van a ver.",
		],
		"idle": "El horno está siempre encendido. Úsenlo cuando quieran.",
	},
	"eco": {
		"name": "Eco", "title": "Ermitaño", "place": "hermit_npc",
		"look": {
			"skin": Color(0.82, 0.66, 0.55), "hair": Color(0.88, 0.88, 0.85),
			"shirt": Color(0.42, 0.4, 0.33), "pants": Color(0.35, 0.33, 0.27),
			"boots": Color(0.25, 0.2, 0.15), "accessories": ["long_beard", "hood"],
		},
		"greetings": [
			"El viento me contó que llegaban. El viento nunca miente.",
			"Hace años que nadie sube hasta acá...",
		],
		"idle": "La montaña ya les habló. Escuchen al resto de la isla.",
	},
	"nilo": {
		"name": "Nilo", "title": "Pescador", "place": "dock_npc",
		"look": {
			"skin": Color(0.62, 0.45, 0.32), "hair": Color(0.1, 0.08, 0.07),
			"shirt": Color(0.2, 0.45, 0.55), "pants": Color(0.45, 0.4, 0.3),
			"boots": Color(0.15, 0.13, 0.12), "accessories": ["straw_hat"],
		},
		"greetings": [
			"¡Buenas! Hoy los peces no pican... ¿y ustedes qué andan buscando?",
			"Desde el muelle se ve toda la costa. Linda isla, ¿no?",
		],
		"idle": "Si necesitan algo del mar, ya saben dónde encontrarme.",
	},
}


static func get_npc(id: String) -> Dictionary:
	return NPCS.get(id, {})


static func display_name(id: String) -> String:
	return get_npc(id).get("name", id)
