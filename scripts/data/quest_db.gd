class_name QuestDB
extends RefCounted
## Misiones de la isla y de Valdoria. El progreso es del grupo entero (cooperativo).
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
##   kill:    derrotar criaturas (item = especie)
##   tame:    domesticar un animal (item = especie o "any")
##   build:   construir una pieza (item = id de la pieza)
##   ship:    reparar una etapa del Albatros (item = id de la etapa, ver ShipDB)
##   sail:    zarpar en el Albatros (item = "mainland" o "island")
##
##   main: true marca las misiones de la historia principal (se ven en dorado)

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
	"t_hunt": {
		"giver": "tomas", "requires": ["t_wood"],
		"title": "Carne para el fuego",
		"description": "Cacen ciervos para conseguir carne y cuero. Cocinen la carne en la fogata.",
		"offer": "Las bayas no alcanzan. Fabriquen una lanza o un garrote y cacen 2 ciervos. La carne se cocina en la fogata (E sobre el fuego).",
		"progress": "Los ciervos huyen rápido: acérquense despacio y con la lanza llegan más lejos.",
		"complete": "¡Huele bien! Tomen carne cocida para el camino. Comer la tienen que hacer seguido: miren la barra de hambre.",
		"objectives": [{"type": "kill", "item": "deer", "amount": 2, "text": "Cazar ciervos"}],
		"rewards": {"cooked_meat": 4, "leather": 5},
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
	"i_shades": {
		"giver": "ilse", "requires": ["i_ore"],
		"title": "Noche de sombras",
		"description": "De noche salen las sombras. Derroten 5 y busquen los planos que dejan.",
		"offer": "Cuando cae el sol aparecen unas sombras con ojos rojos. Mátenlas: a veces dejan planos de construcción. Derroten 5 y vuelvan.",
		"progress": "Las sombras solo salen de noche. Lleven antorchas y armas.",
		"complete": "Son de otro mundo, esas cosas. Tomen estos planos: les van a servir para refugiarse.",
		"objectives": [{"type": "kill", "item": "shade", "amount": 5, "text": "Derrotar sombras"}],
		"rewards": {"bp_foundation": 1, "bp_wall": 1},
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
	"e_friend": {
		"giver": "eco", "requires": ["intro"],
		"title": "Un amigo fiel",
		"description": "Domesticá cualquier animal dándole su comida favorita (mirá la tabla de domesticación).",
		"offer": "Los animales de esta isla son desconfiados, pero si les das lo que les gusta, te siguen a todos lados. Domestiquen uno.",
		"progress": "Con la comida en la mano, acercate y apretá E. Cada animal quiere algo distinto.",
		"complete": "Se nota que te quiere. Tomá, para que lo cuides bien.",
		"objectives": [{"type": "tame", "item": "any", "amount": 1, "text": "Domesticar un animal"}],
		"rewards": {"leather": 10, "berries": 10},
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
	"n_shelter": {
		"giver": "nilo", "requires": ["n_supplies"],
		"title": "Un techo propio",
		"description": "Construí un cimiento con el martillo (necesitan el plano de cimiento).",
		"offer": "Dormir al aire libre con esas sombras... Fabriquen un martillo y levanten un refugio. Los planos se encuentran en cofres por la isla.",
		"progress": "Con el martillo en la mano, R cambia de pieza y click construye.",
		"complete": "¡Un refugio! Tomen este plano, encontré varios en la playa.",
		"objectives": [{"type": "build", "item": "wood_foundation", "amount": 1, "text": "Construir un cimiento de madera"}],
		"rewards": {"bp_doorway": 1, "bp_roof": 1},
	},
	# --- MISIÓN PRINCIPAL: el regreso del Albatros ----------------------------------------
	"m_albatros": {
		"giver": "nilo", "requires": ["intro"], "main": true,
		"title": "El regreso del Albatros",
		"description": "Nilo cree que el Albatros se puede reparar. Vayan a ver los restos del barco en la playa del naufragio.",
		"offer": "Fui a ver los restos del Albatros. El casco es de roble del bueno, ¿saben? Si lo reparamos, podemos irnos de esta isla. Dicen que hacia el este, más allá del horizonte, hay un reino entero: Valdoria. Vayan a ver el barco y díganme qué les parece.",
		"progress": "Los restos están en la playa del naufragio. Búsquenlos en el mapa (M).",
		"complete": "¿Se puede salvar? ¡Lo sabía! Escuchen: tablones de la mesa de trabajo, clavos del horno de la forja, soga de fibra y lona para las velas. Con E sobre el barco ven qué falta. Tomen, para empezar.",
		"objectives": [{"type": "reach", "target": "wreck", "radius": 16.0, "amount": 1, "text": "Revisar los restos del Albatros"}],
		"rewards": {"rope": 4, "nails": 10},
	},
	"m_hull": {
		"requires": ["m_albatros"], "auto_complete": true, "main": true,
		"title": "Reparar el casco",
		"description": "Apretá E sobre el Albatros y aportá tablones (mesa de trabajo) y clavos (horno de la forja).",
		"objectives": [{"type": "ship", "item": "hull", "amount": 1, "text": "Reparar el casco del Albatros"}],
		"rewards": {"cooked_meat": 3},
	},
	"m_mast": {
		"requires": ["m_hull"], "auto_complete": true, "main": true,
		"title": "Levantar los mástiles",
		"description": "Los mástiles necesitan tablones y soga (la soga se hace con fibra, desde el inventario).",
		"objectives": [{"type": "ship", "item": "mast", "amount": 1, "text": "Levantar los mástiles"}],
		"rewards": {"fiber": 30},
	},
	"m_sails": {
		"requires": ["m_mast"], "auto_complete": true, "main": true,
		"title": "Velas nuevas",
		"description": "Hacen falta lonas (fibra y cuero, en la mesa de trabajo) y más soga.",
		"objectives": [{"type": "ship", "item": "sails", "amount": 1, "text": "Colgar las velas"}],
		"rewards": {"metal_fragments": 10},
	},
	"m_helm": {
		"requires": ["m_sails"], "auto_complete": true, "main": true,
		"title": "Timón y provisiones",
		"description": "Arreglen el timón y carguen carne cocida para la travesía.",
		"objectives": [{"type": "ship", "item": "helm", "amount": 1, "text": "Arreglar el timón y cargar provisiones"}],
	},
	"m_voyage": {
		"requires": ["m_helm"], "auto_complete": true, "main": true,
		"title": "Rumbo a Valdoria",
		"description": "¡El Albatros está listo! Apretá E sobre el barco y zarpen hacia el este.",
		"objectives": [{"type": "sail", "item": "mainland", "amount": 1, "text": "Zarpar hacia Valdoria"}],
	},
	# --- Valdoria -------------------------------------------------------------------------
	"v_arrival": {
		"requires": ["m_voyage"], "auto_complete": true, "main": true,
		"title": "Tierra firme",
		"description": "Llegaron a Puerto Albor. Hablen con Maese Odón, el capitán del puerto.",
		"objectives": [{"type": "talk", "npc": "odon", "amount": 1, "text": "Hablar con Maese Odón"}],
		"rewards": {"coin": 15},
	},
	"o_market": {
		"giver": "odon", "requires": ["v_arrival"], "auto_complete": true,
		"title": "El mercado del puerto",
		"description": "Berta, la mercader, compra y vende de todo. Vayan a conocerla.",
		"offer": "Si van a quedarse, van a necesitar oro. Berta, en el mercado, les compra cuero, carne y metal, y les vende de todo. Díganle que van de mi parte.",
		"progress": "Berta tiene su puesto en la plaza, al lado del pozo.",
		"complete": "Berta me contó que ya se conocieron. Tomen unas monedas para empezar.",
		"objectives": [{"type": "talk", "npc": "berta", "amount": 1, "text": "Hablar con Berta"}],
		"rewards": {"coin": 10},
	},
	"o_robledal": {
		"giver": "odon", "requires": ["v_arrival"], "auto_complete": true, "main": true,
		"title": "Camino a Robledal",
		"description": "Sigan el camino de tierra hasta el pueblo de Robledal, al norte.",
		"offer": "Siguiendo el camino de tierra hacia el norte está Robledal, un pueblo de granjeros. Fermín, el molinero, siempre necesita ayuda. Y paga bien... en pan.",
		"progress": "Sigan el camino. Si se pierden, miren el mapa (M).",
		"complete": "",
		"objectives": [{"type": "reach", "target": "village", "radius": 22.0, "amount": 1, "text": "Llegar a Robledal"}],
		"rewards": {"bread": 3},
	},
	"f_mill": {
		"giver": "fermin", "requires": ["o_robledal"], "main": true,
		"title": "El molino parado",
		"description": "Las aspas del molino están rotas. Fermín necesita tablones y soga.",
		"offer": "¿Ven el molino? Una tormenta le rompió las aspas y desde entonces no muele ni un grano. Si me traen 12 tablones y 6 sogas, lo arreglo. Sin molino no hay harina, y sin harina no hay pan.",
		"progress": "12 tablones y 6 sogas. En el puerto hay una mesa de trabajo, al lado de la herrería.",
		"complete": "¡Escuchen cómo gira! Robledal vuelve a tener pan. Tomen, recién horneado, y unas monedas.",
		"objectives": [
			{"type": "deliver", "item": "plank", "amount": 12, "text": "Entregar tablones"},
			{"type": "deliver", "item": "rope", "amount": 6, "text": "Entregar sogas"},
		],
		"rewards": {"coin": 25, "bread": 4},
	},
	"f_harvest": {
		"giver": "fermin", "requires": ["f_mill"],
		"title": "La cosecha",
		"description": "Cosechen trigo en los campos dorados de Robledal.",
		"offer": "Con el molino andando, hay que cosechar. Junten 30 de trigo en los campos dorados. Y un secreto: con 3 de trigo, en una fogata, se hace pan.",
		"progress": "El trigo está en los campos alrededor del pueblo. Se cosecha con click.",
		"complete": "¡Qué cosecha! El pueblo entero les va a estar agradecido este invierno.",
		"objectives": [{"type": "collect", "item": "wheat", "amount": 30, "text": "Cosechar trigo"}],
		"rewards": {"coin": 20, "bread": 5},
	},
	"g_bandits": {
		"giver": "galvan", "requires": ["v_arrival"], "main": true,
		"title": "Los bandidos del sur",
		"description": "Sir Galván necesita ayuda contra los bandidos que acampan en el bosque del sur.",
		"offer": "¿Náufragos, eh? Entonces saben pelear por su vida. Unos bandidos acampan en el bosque del sur y asaltan las carretas que van al puerto. Mis hombres no alcanzan. Derroten a 5 y vuelvan.",
		"progress": "El campamento está en el bosque, al sur del puerto. Lleven comida y buenas armas.",
		"complete": "Cinco menos. Pero los bandidos tienen un jefe: Rurik. Mientras él siga libre, van a volver.",
		"objectives": [{"type": "kill", "item": "bandit", "amount": 5, "text": "Derrotar bandidos"}],
		"rewards": {"coin": 40},
	},
	"g_chief": {
		"giver": "galvan", "requires": ["g_bandits"], "main": true,
		"title": "Rurik el Rojo",
		"description": "El jefe de los bandidos apareció en el campamento. Derrótenlo.",
		"offer": "Mis espías dicen que Rurik, el jefe, volvió al campamento. Es grande y pega fuerte. Si lo derrotan, la reina en persona va a querer conocerlos.",
		"progress": "Rurik es duro. Vayan en grupo, con pan y la mejor espada que tengan.",
		"complete": "¡Rurik derrotado! Valdoria vuelve a respirar. Vengan: la reina los espera.",
		"objectives": [{"type": "kill", "item": "bandit_chief", "amount": 1, "text": "Derrotar a Rurik"}],
		"rewards": {"coin": 80},
	},
	"r_audience": {
		"requires": ["g_chief"], "auto_complete": true, "main": true,
		"title": "Audiencia real",
		"description": "La reina Isolda quiere conocer a los héroes de Valdoria. Vayan al castillo.",
		"objectives": [{"type": "talk", "npc": "isolda", "amount": 1, "text": "Hablar con la reina Isolda"}],
		"rewards": {"royal_sword": 1, "coin": 100},
		"on_complete_cinematic": "royal_audience",
	},
}


static func get_quest(id: String) -> Dictionary:
	return QUESTS.get(id, {})
