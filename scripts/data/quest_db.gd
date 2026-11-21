class_name QuestDB
extends RefCounted
## Misiones de la isla. El progreso es del grupo entero (cooperativo).
##
##   giver: NPC que la da (si no tiene, se activa sola cuando se cumplen los requisitos)
##   requires: misiones que hay que terminar antes
##   auto_complete: se termina sola al cumplir los objetivos (si no, hay que volver con el NPC)
##   offer / progress / complete: lo que dice el NPC al ofrecerla, mientras tanto y al terminarla
##   rewards: ítems que recibe CADA jugador conectado
##   on_accept_cinematic / on_complete_cinematic: cinemáticas (ver world.build_cinematic)
##
## Tipos de objetivo:
##   collect: juntar recursos (cuenta lo que junta todo el grupo)
##   craft:   fabricar un ítem (cuenta lo que fabrica todo el grupo)
##   deliver: entregarle ítems al NPC (los pone el jugador que entrega)
##   talk:    hablar con un NPC
##   reach:   que cualquier jugador llegue a un lugar

const QUESTS := {
	"intro": {
		"title": "Un nuevo comienzo",
		"description": "Despertaron junto a una fogata. Hay alguien en el campamento: hablen con Tomás (tecla E).",
		"auto_complete": true,
		"objectives": [{"type": "talk", "npc": "tomas", "amount": 1, "text": "Hablar con Tomás"}],
	},
	# --- Tomás, el leñador -------------------------------------------------------------
	"t_wood": {
		"giver": "tomas", "requires": ["intro"],
		"title": "Leña para el campamento",
		"description": "Tomás necesita madera para mantener el fuego encendido.",
		"offer": "Si vamos a sobrevivir, el fuego no se puede apagar. Junten 60 de madera entre todos. Con el hacha en la mano (tecla 1) rinde el triple.",
		"progress": "¿Cómo va esa madera? Los árboles grandes dan más.",
		"complete": "¡Excelente trabajo! Tomen una antorcha cada uno. De noche la van a agradecer.",
		"objectives": [{"type": "collect", "item": "wood", "amount": 60, "text": "Juntar madera"}],
		"rewards": {"torch": 1},
	},
	"t_pickaxe": {
		"giver": "tomas", "requires": ["t_wood"],
		"title": "Un pico propio",
		"description": "Fabricá un pico de piedra desde el inventario (Tab → Fabricación).",
		"offer": "Con las manos no van a picar mucha roca. Abran la mochila (Tab) y fabriquen un pico de piedra: madera y piedra, nada más.",
		"progress": "El pico se fabrica desde el inventario, a la izquierda. ¿Ya tienen la piedra?",
		"complete": "¡Eso es un pico! Tomen esta fibra, les va a servir para lo que viene.",
		"objectives": [{"type": "craft", "item": "stone_pickaxe", "amount": 1, "text": "Fabricar un pico de piedra"}],
		"rewards": {"fiber": 20},
	},
	"t_backpack": {
		"giver": "tomas", "requires": ["t_pickaxe"],
		"title": "Más espacio",
		"description": "Tomás puede coser una mochila más grande si le llevan materiales.",
		"offer": "Los veo cargando como mulas. Tráiganme 40 de fibra y 30 de madera y les coso una mochila grande. La fibra sale de las plantas altas y amarillentas.",
		"progress": "Todavía necesito la fibra y la madera para la mochila.",
		"complete": "Aquí tienen. Con esto pueden cargar bastante más sin arrastrar los pies.",
		"objectives": [
			{"type": "deliver", "item": "fiber", "amount": 40, "text": "Entregar fibra"},
			{"type": "deliver", "item": "wood", "amount": 30, "text": "Entregar madera"},
		],
		"rewards": {"large_backpack": 1},
	},
	# --- Ilse, la herrera --------------------------------------------------------------
	"i_ore": {
		"giver": "ilse", "requires": ["t_wood"],
		"title": "Rocas con vetas",
		"description": "Ilse busca mineral de metal: las rocas oscuras con vetas naranjas.",
		"offer": "¿Vieron las rocas oscuras con vetas naranjas? Eso es metal. Tráiganme 20 de mineral y les enseño a fundirlo.",
		"progress": "Las rocas con metal suelen estar en las laderas. Usen el pico.",
		"complete": "¡Buen mineral! Tomen estos fragmentos. El horno es todo suyo: fundan lo que quieran.",
		"objectives": [{"type": "collect", "item": "metal_ore", "amount": 20, "text": "Juntar mineral de metal"}],
		"rewards": {"metal_fragments": 10},
	},
	"i_smelt": {
		"giver": "ilse", "requires": ["i_ore"],
		"title": "Fuego de la forja",
		"description": "Fundí mineral en el horno de la forja (Tab → Fabricación → Fundir metal).",
		"offer": "Ahora ustedes. Párense al lado del horno, abran la mochila y fundan 30 fragmentos de metal. Cada tanda lleva mineral y un poco de madera.",
		"progress": "Tienen que estar cerca del horno para fundir.",
		"complete": "Eso ya parece trabajo de herreros. Tomen, unas antorchas para el camino.",
		"objectives": [{"type": "craft", "item": "metal_fragments", "amount": 30, "text": "Fundir fragmentos de metal"}],
		"rewards": {"torch": 2},
	},
	"i_tools": {
		"giver": "ilse", "requires": ["i_smelt"],
		"title": "Herramientas de verdad",
		"description": "Fabricá un pico de metal en la mesa de trabajo del campamento.",
		"offer": "Con los fragmentos, en la mesa de trabajo del campamento pueden hacer un pico de metal. Rinde mucho más que el de piedra.",
		"progress": "La mesa de trabajo está en el campamento, al lado de Tomás.",
		"complete": "¡Precioso! Tomen más fragmentos: ya saben qué hacer con ellos.",
		"objectives": [{"type": "craft", "item": "metal_pickaxe", "amount": 1, "text": "Fabricar un pico de metal"}],
		"rewards": {"metal_fragments": 20},
	},
	# --- Eco, el ermitaño --------------------------------------------------------------
	"e_monolith": {
		"giver": "eco", "requires": ["intro"], "auto_complete": true,
		"title": "El monolito de la cima",
		"description": "Eco dice que el monolito de la cima los está esperando.",
		"offer": "Arriba de todo hay una piedra que brilla. Dicen que despierta cuando llega gente unida. ¿Se animan a subir?",
		"progress": "La cima está ahí arriba. Sigan la luz.",
		"complete": "Lo sentí desde acá. La isla los aceptó.",
		"objectives": [{"type": "reach", "target": "monolith", "radius": 7.0, "amount": 1, "text": "Llegar al monolito"}],
		"rewards": {"metal_fragments": 15},
		"on_accept_cinematic": "reveal_monolith",
		"on_complete_cinematic": "monolith_awakens",
	},
	# --- Nilo, el pescador -------------------------------------------------------------
	"n_supplies": {
		"giver": "nilo", "requires": ["intro"],
		"title": "Provisiones para el muelle",
		"description": "Nilo necesita materiales para arreglar el muelle.",
		"offer": "El muelle se cae a pedazos. Si me traen 30 de madera y 20 de piedra, les regalo algo útil.",
		"progress": "Madera y piedra, amigos. El muelle no se arregla solo.",
		"complete": "¡Gracias! Tomen antorchas y fibra, me sobra.",
		"objectives": [
			{"type": "deliver", "item": "wood", "amount": 30, "text": "Entregar madera"},
			{"type": "deliver", "item": "stone", "amount": 20, "text": "Entregar piedra"},
		],
		"rewards": {"torch": 2, "fiber": 20},
	},
	"n_lookout": {
		"giver": "nilo", "requires": ["n_supplies"],
		"title": "El mirador olvidado",
		"description": "Hay una pila de piedras con una bandera en una colina lejana. Lleguen hasta ahí y vuelvan con Nilo.",
		"offer": "Desde el bote vi una bandera en una colina, lejos del monolito. ¿Pueden ir a ver qué hay y contarme?",
		"progress": "La bandera está en una colina alta. Fíjense desde algún lugar alto.",
		"complete": "¿Un mirador de piedra? Entonces no fuimos los primeros en esta isla... Tomen, encontré este mineral.",
		"objectives": [{"type": "reach", "target": "lookout", "radius": 6.0, "amount": 1, "text": "Llegar al mirador"}],
		"rewards": {"metal_ore": 20},
	},
}


static func get_quest(id: String) -> Dictionary:
	return QUESTS.get(id, {})
