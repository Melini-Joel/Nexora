class_name NpcDB
extends RefCounted
## Personajes de la isla y de Valdoria. "place" es el lugar del mundo donde aparecen (ver world.gd).
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
		"idle": "Por ahora no tengo más trabajo. Nilo, el pescador del muelle, anda diciendo que el Albatros se puede reparar... Vayan a hablar con él.",
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
	# --- El Albatros (no es una persona: abre la ventana de reparación y viaje) ---------
	"albatros": {
		"name": "El Albatros", "title": "Barco", "greetings": ["El viejo Albatros cruje con el viento."],
		"idle": "",
	},
	# --- Valdoria: Puerto Albor -----------------------------------------------------------
	"odon": {
		"name": "Maese Odón", "title": "Capitán del puerto",
		"look": {
			"skin": Color(0.85, 0.66, 0.5), "hair": Color(0.55, 0.55, 0.55),
			"shirt": Color(0.2, 0.28, 0.45), "pants": Color(0.3, 0.25, 0.2),
			"boots": Color(0.2, 0.14, 0.1), "accessories": ["beard", "cape_blue"],
		},
		"greetings": [
			"¡Por todos los mares! Hace años que nadie llega en un barco tan maltrecho. Bienvenidos a Puerto Albor.",
			"Las mareas traen de todo a este puerto. Hoy, por lo visto, trajeron náufragos.",
		],
		"idle": "El puerto es de todos los que trabajan. Paseen, comercien y no se metan en líos.",
	},
	"berta": {
		"name": "Berta", "title": "Mercader",
		"look": {
			"skin": Color(0.92, 0.76, 0.62), "hair": Color(0.45, 0.22, 0.1),
			"shirt": Color(0.55, 0.2, 0.35), "pants": Color(0.3, 0.2, 0.25),
			"boots": Color(0.25, 0.15, 0.1), "accessories": ["bun", "dress", "apron"],
		},
		"greetings": [
			"¡Pasen, pasen! Compro cuero, carne y metal. Vendo pan, herramientas y cosas que no van a encontrar en otro lado.",
			"El oro abre más puertas que cualquier espada, ¿sabían?",
		],
		"idle": "Cuando quieran comerciar, acá estoy.",
		"trader": true,
	},
	"marta": {
		"name": "Marta", "title": "Pescadera",
		"look": {
			"skin": Color(0.7, 0.52, 0.38), "hair": Color(0.15, 0.1, 0.08),
			"shirt": Color(0.35, 0.5, 0.45), "pants": Color(0.35, 0.3, 0.25),
			"boots": Color(0.2, 0.15, 0.1), "accessories": ["dress", "apron"],
		},
		"greetings": [
			"Dicen que más allá del horizonte hay una isla donde brilla una luz azul... cuentos de marineros.",
			"Si buscan trabajo, vayan a Robledal. Fermín siempre necesita manos.",
			"Los caminos ya no son seguros. Los bandidos del bosque del sur asaltan las carretas.",
		],
		"idle": "",
	},
	"bruno": {
		"name": "Bruno", "title": "Tabernero",
		"look": {
			"skin": Color(0.88, 0.68, 0.55), "hair": Color(0.3, 0.18, 0.1),
			"shirt": Color(0.75, 0.7, 0.6), "pants": Color(0.3, 0.22, 0.15),
			"boots": Color(0.22, 0.15, 0.1), "accessories": ["apron", "beard"],
		},
		"greetings": [
			"¡La taberna del Ancla Rota nunca cierra! Bueno, casi nunca.",
			"La reina Isolda no recibe a cualquiera. Primero tienen que ganarse el respeto del capitán Galván.",
			"¿Náufragos? Entonces brindo por ustedes. No cualquiera sale vivo del mar.",
		],
		"idle": "",
	},
	# --- Valdoria: Robledal ---------------------------------------------------------------
	"fermin": {
		"name": "Fermín", "title": "Molinero",
		"look": {
			"skin": Color(0.9, 0.72, 0.58), "hair": Color(0.9, 0.88, 0.85),
			"shirt": Color(0.85, 0.82, 0.72), "pants": Color(0.4, 0.33, 0.22),
			"boots": Color(0.3, 0.2, 0.12), "accessories": ["straw_hat", "beard"],
		},
		"greetings": [
			"Buenas, buenas. Bienvenidos a Robledal: trigo, harina y gente honesta.",
			"El molino es el corazón del pueblo. Si se para, no hay pan para nadie.",
		],
		"idle": "Los campos están llenos de trigo. Cosechen lo que necesiten.",
	},
	"ines": {
		"name": "Inés", "title": "Granjera",
		"look": {
			"skin": Color(0.78, 0.58, 0.42), "hair": Color(0.55, 0.35, 0.15),
			"shirt": Color(0.45, 0.55, 0.3), "pants": Color(0.35, 0.28, 0.2),
			"boots": Color(0.25, 0.18, 0.12), "accessories": ["dress", "bun"],
		},
		"greetings": [
			"Con tres manojos de trigo, en una fogata, se hace un pan riquísimo.",
			"De noche salen unas sombras raras del bosque. Antes no pasaba...",
		],
		"idle": "",
	},
	# --- Valdoria: castillo ---------------------------------------------------------------
	"galvan": {
		"name": "Sir Galván", "title": "Capitán de la guardia",
		"look": {
			"skin": Color(0.8, 0.62, 0.48), "hair": Color(0.2, 0.15, 0.1),
			"shirt": Color(0.6, 0.12, 0.14), "pants": Color(0.25, 0.25, 0.28),
			"boots": Color(0.18, 0.15, 0.12), "accessories": ["chainmail", "cape_red", "beard", "sword"],
		},
		"greetings": [
			"Alto. Nadie entra al castillo sin motivo. ¿Quiénes son ustedes?",
			"La corona protege a Valdoria. Y la guardia protege a la corona.",
		],
		"idle": "El reino está en deuda con ustedes. Mis hombres los saludan al pasar.",
	},
	"isolda": {
		"name": "Reina Isolda", "title": "Reina de Valdoria",
		"look": {
			"skin": Color(0.95, 0.82, 0.72), "hair": Color(0.75, 0.6, 0.3),
			"shirt": Color(0.4, 0.15, 0.45), "pants": Color(0.3, 0.1, 0.3),
			"boots": Color(0.2, 0.1, 0.15), "accessories": ["dress", "crown", "cape_red", "bun"],
		},
		"greetings": [
			"Así que ustedes son los náufragos de los que habla todo el reino.",
			"Valdoria es antigua, viajeros. Y guarda más secretos de los que imaginan.",
		],
		"idle": "Las puertas de mi castillo siempre estarán abiertas para ustedes.",
	},
	"guard_a": {
		"name": "Guardia", "title": "Castillo de Valdoria",
		"look": {
			"skin": Color(0.85, 0.68, 0.55), "hair": Color(0.3, 0.2, 0.1),
			"shirt": Color(0.6, 0.12, 0.14), "pants": Color(0.25, 0.25, 0.28),
			"boots": Color(0.18, 0.15, 0.12), "accessories": ["chainmail", "helmet", "spear"],
		},
		"greetings": ["Circulen. El capitán Galván está adentro, en el patio.", "Por la reina."],
		"idle": "",
	},
	"guard_b": {
		"name": "Guardia", "title": "Castillo de Valdoria",
		"look": {
			"skin": Color(0.7, 0.5, 0.36), "hair": Color(0.1, 0.08, 0.06),
			"shirt": Color(0.6, 0.12, 0.14), "pants": Color(0.25, 0.25, 0.28),
			"boots": Color(0.18, 0.15, 0.12), "accessories": ["chainmail", "helmet", "spear"],
		},
		"greetings": ["Los bandidos del sur nos tienen cansados. Ojalá alguien los ponga en su lugar.", "Por la reina."],
		"idle": "",
	},
}

## Comercio con Berta: [ítem, cantidad, precio en monedas]. "sell" = lo que ella te compra.
const TRADES := {
	"buy": [
		["bread", 3, 4], ["torch", 2, 3], ["rope", 5, 6], ["sailcloth", 2, 10],
		["large_backpack", 1, 25], ["metal_sword", 1, 40], ["bp_stone", 1, 35], ["bp_roof", 1, 15],
	],
	"sell": [
		["leather", 5, 4], ["cooked_meat", 5, 5], ["raw_meat", 5, 2], ["metal_fragments", 10, 6],
		["wood", 50, 3], ["stone", 50, 3], ["wheat", 10, 3], ["berries", 20, 2],
	],
}


static func get_npc(id: String) -> Dictionary:
	return NPCS.get(id, {})


static func display_name(id: String) -> String:
	return get_npc(id).get("name", id)
