<p align="center"><img src="logo/nexora_logo_horizontal.png" alt="NEXORA" width="560"></p>

# NEXORA

RPG cooperativo de mundo abierto en 3D (2 a 6 jugadores) hecho con **Godot 4.3+** y **GDScript**.
Estilo low-poly: liviano para cualquier PC, pero con iluminación, sombras, niebla y brillo.

![Menú principal](docs/21_menu.png)

![Cinemática del naufragio](docs/28_intro_tormenta.png)

![Mapa de la isla](docs/33_mapa.png)

![Construcción y animales](docs/17_construccion_animales.png)

![Noche con sombras](docs/18_noche_sombras.png)

## Cómo abrirlo

1. Descargá Godot 4.3 o superior (versión estándar, **no** la .NET): https://godotengine.org/download
2. Abrí Godot → **Importar** → elegí el archivo `project.godot` de esta carpeta.
3. Apretá **F5**. En el menú elegí **Continuar** (último mundo), **Jugar solo** o **Multijugador** (crear partida o unirse por IP).

## Guardado de partida

- Cada partida es un **mundo** con nombre. Al elegir *Jugar solo* o *Crear partida* aparece la lista de mundos guardados: cargás uno o creás uno nuevo.
- **Se guarda solo** cada 3 minutos, al salir al menú y al cerrar el juego. También hay un botón **Guardar partida** en la pausa (Esc).
- Se guarda: la isla, el día y la hora, las construcciones, las bolsas en el suelo, los planos aprendidos, las misiones, las **mascotas** y, por cada jugador (según su **nombre**), su inventario, vida, hambre y posición.
- **En cooperativo guarda el host.** Si tus amigos vuelven a entrar con el mismo nombre, recuperan sus cosas y sus mascotas.
- Los archivos están en `%APPDATA%\Godot\app_userdata\NEXORA\saves` (Windows). Copiá esa carpeta si querés hacer una copia de seguridad.

## Cómo actualizar a una versión nueva (sin borrar ni volver a importar)

**Opción A: reemplazar archivos (la más simple)**
1. Descomprimí el zip nuevo.
2. Copiá el **contenido** de la carpeta `nexora` nueva y pegalo **encima** de tu carpeta `nexora`. Cuando Windows pregunte, elegí **Reemplazar los archivos en el destino**.
3. Volvé a Godot: detecta los cambios solo. Si pregunta "¿Recargar desde el disco?", tocá **Recargar**.

No borres la carpeta oculta `.godot` (es la caché del editor) ni tus opciones guardadas: se conservan.

**Opción B: GitHub + GitHub Desktop (la mejor a largo plazo)**
1. Creá una cuenta en github.com e instalá **GitHub Desktop**.
2. Subí el proyecto a un repositorio (o clonalo si ya está subido).
3. Cada vez que haya una versión nueva: en GitHub Desktop tocá **Fetch origin** y después **Pull origin**. Los archivos se actualizan solos y Godot los recarga.

Además tenés el historial de cada versión: si algo se rompe, podés volver atrás.

## Opciones (menú principal o Esc → Opciones)

- **Pantalla:** modo (ventana, maximizada o pantalla completa), resolución, tamaño de la interfaz, VSync y contador de FPS.
- **Cámara:** distancia, altura, hombro (izquierda/centro/derecha), campo de visión, sensibilidad del mouse e invertir eje Y.
- **Gráficos:** calidad baja, media o alta. Baja es ideal para notebooks.

Las opciones se guardan solas y se mantienen la próxima vez que abras el juego.
Por defecto el juego arranca en **ventana maximizada**, así entra en cualquier pantalla.

## Cómo probar el cooperativo

### Opción 1: todo en tu PC (para probar rápido)
1. En Godot, menú **Depurar → Personalizar instancias de ejecución…** (*Debug → Customize Run Instances*).
2. Activá **Habilitar múltiples instancias** y poné **2** (o 3).
3. Apretá **F5**: se abren 2 ventanas del juego.
4. En la primera tocá **Crear partida**. En la segunda escribí otro nombre y tocá **Unirse** con IP `127.0.0.1`.
5. Acomodá las ventanas una al lado de la otra (o usá Alt+Tab) y probá: si talás un árbol en una, desaparece en la otra.

> Consejo: en Opciones elegí **modo Ventana** y resolución **1280×720** para que entren las dos ventanas en la pantalla.

### Opción 2: dos PCs en la misma casa (misma red Wi-Fi)
1. Las dos PCs tienen que tener **la misma versión** del proyecto.
2. En la PC del host: **Crear partida**. Si Windows pregunta por el **Firewall**, tocá **Permitir** (redes privadas).
3. Averiguá la IP local del host: abrí `cmd` y escribí `ipconfig` → buscá **Dirección IPv4** (ej. `192.168.0.15`).
4. En la otra PC: **Unirse** con esa IP.

### Opción 3: con amigos por internet
La forma más fácil es una "LAN virtual":
1. Todos instalan **Tailscale** (gratis) o **Radmin VPN** e inician sesión en la misma red.
2. El host crea la partida y comparte **la IP que le muestra Tailscale/Radmin** (ej. `100.x.x.x` o `26.x.x.x`).
3. Los demás se unen con esa IP.

Alternativa sin VPN: el host abre el puerto **UDP 7777** en su router (*port forwarding*) y comparte su IP pública.

### Para que tus amigos no necesiten Godot
En Godot: **Proyecto → Exportar… → Agregar… → Windows Desktop** (la primera vez te pide descargar las *plantillas de exportación*, aceptá). Exportá a un `.exe` y pasales esa carpeta.

### Si no se conecta
- Revisá que la IP esté bien escrita y que el host ya haya creado la partida.
- Permití el juego en el firewall de Windows (o desactivalo un momento para probar).
- Máximo 6 jugadores por partida.

## Jugar en el celular (Android)

El juego tiene **controles táctiles** que se activan solos en Android (en la PC se pueden probar con Opciones → Cámara → Controles táctiles: Siempre):
- **Mitad izquierda de la pantalla:** joystick para moverse (aparece donde apoyás el dedo).
- **Deslizar el dedo en el resto de la pantalla:** girar la cámara.
- **Botones a la derecha:** Golpear (mantenelo apretado), Usar, Saltar y Correr (se prende y se apaga). Con el martillo aparecen Pieza y Desarmar.
- **Botones a la izquierda:** menú (≡), Mochila, Mapa, Personaje y Cámara.
- **Barra rápida:** tocá un casillero para elegirlo. En la mochila, los objetos se arrastran con el dedo.
- En el celular el juego arranca en calidad **Baja** y usa el renderizador liviano (Compatibilidad). La sensibilidad de la cámara se ajusta en Opciones → Cámara.
- El cooperativo funciona igual si el celular y la PC están en la misma red Wi-Fi.

### Cómo generar el APK (una sola vez se prepara la PC)
1. Instalá **Android Studio** (trae el SDK de Android) y un **JDK 17** (por ejemplo, Eclipse Temurin 17).
2. En Godot: **Editor → Administrar plantillas de exportación → Descargar e instalar**.
3. En Godot: **Editor → Configuración del editor → Exportar → Android**: completá la ruta del **SDK de Android** (en Windows suele ser `C:\Users\TU_USUARIO\AppData\Local\Android\Sdk`) y la del **JDK**.
4. **Proyecto → Exportar…**: el proyecto ya trae el preset **Android**. Tocá **Exportar proyecto**, elegí la carpeta y desmarcá "Exportar en modo depuración" si querés la versión final.
5. Pasá el archivo `NEXORA.apk` al celular (cable, Drive o WhatsApp), abrilo y permití **instalar apps de origen desconocido**.

Atajo: con el celular conectado por USB y la **depuración USB** activada (Opciones de desarrollador), el ícono de Android arriba a la derecha de Godot instala y abre el juego directo en el celular.

## Controles

| Tecla | Acción |
|---|---|
| WASD / flechas | Moverse |
| Mouse | Cámara |
| Shift | Correr (gasta energía) |
| Espacio | Saltar (gasta energía) |
| **Click izquierdo** | Depende de lo que apuntes y tengas en la mano: recolectar, **atacar**, **comer**, **aprender un plano** o **construir** (con el martillo) |
| Click derecho | Con el martillo: desarmar una pieza (devuelve la mitad) |
| **E** | Hablar con NPCs, recoger bolsas, **usar estaciones** (mesa, horno, fogata), **abrir cofres y puertas**, **domesticar** o dar órdenes a tu mascota |
| R | Con el martillo: cambiar de pieza |
| 1-6 / rueda del mouse | Elegir objeto de la barra rápida |
| Tab / I | Abrir inventario |
| M | Mapa de la isla |
| **C** | **Personaje: nivel, experiencia y habilidades** |
| V | Cámara cerca / normal / lejos |
| Esc | Cerrar inventario · menú de pausa · saltear cinemática |

### Inventario

| Acción | Resultado |
|---|---|
| Arrastrar a otro casillero | Mover, juntar pilas o intercambiar |
| Shift + Click | Mover rápido entre barra rápida y mochila |
| Click derecho | Dividir la pila a la mitad |
| Soltar fuera del inventario | Tirar al suelo en una bolsa (cualquier compañero la puede recoger) |

## Qué incluye este prototipo

### Historia
- **Cinemática de inicio (1 minuto):** el barco *Albatros* queda atrapado en una tormenta, choca contra los arrecifes de una isla que no figura en los mapas y los sobrevivientes despiertan en la playa. Hay lluvia, rayos, olas y sacudones de cámara. Los **restos del naufragio** quedan en la costa para explorarlos, con dos cofres. Se puede saltear con Esc.

### Misión principal: el regreso del Albatros
El objetivo del juego es **reparar el barco y salir de la isla**. La historia se sigue con la estrella ★ en el panel de misiones:
1. **Nilo, el pescador del muelle**, cree que el Albatros se puede reparar: vayan a ver los restos en la playa del naufragio.
2. **Reparen el barco en 4 etapas** con E sobre el Albatros. Cada jugador aporta lo que tenga en la mochila y el barco se ve cada vez más armado:

   | Etapa | Hace falta |
   |---|---|
   | Casco | 40 tablones + 30 clavos |
   | Mástiles | 20 tablones + 12 sogas |
   | Velas | 6 lonas + 10 sogas |
   | Timón y provisiones | 10 tablones + 15 clavos + 10 carnes cocidas |

   - **Tablón** (x2): 5 de madera, en la mesa de trabajo.
   - **Clavos** (x5): 2 fragmentos de metal, en el horno de la forja.
   - **Soga**: 4 de fibra, desde el inventario.
   - **Lona**: 12 de fibra + 2 de cuero, en la mesa de trabajo.
3. **Zarpen hacia Valdoria.** Viaja todo el grupo junto, con una cinemática de la travesía. Desde el muelle de Puerto Albor el Albatros los puede llevar de vuelta a la isla cuando quieran.

### Valdoria, el reino medieval
Un continente de 640 × 640 m al este de la isla, con montañas nevadas en los bordes y caminos de tierra entre los pueblos:
- **Puerto Albor:** muelle, plaza con mercado y pozo, la taberna El Ancla Rota y una herrería con mesa de trabajo, horno y fogata. Ahí están **Maese Odón** (capitán del puerto), **Berta** (mercader), **Marta** (pescadera) y **Bruno** (tabernero).
- **Robledal:** pueblo de granjeros con casas de paja, un molino de viento y **campos de trigo** para cosechar. Ahí están **Fermín** (molinero) e **Inés** (granjera). Con 3 de trigo se hornea **pan** en una fogata.
- **Castillo de Valdoria:** murallas con almenas, torres, portón, la torre del homenaje y el trono. Ahí están **Sir Galván** (capitán de la guardia), la **reina Isolda** y los guardias.
- **Campamento bandido:** una empalizada en el bosque del sur con **bandidos** que atacan a quien se acerque, de día y de noche, y su jefe, **Rurik el Rojo**. Sueltan monedas.
- **Comercio:** Berta compra cuero, carne, metal, madera, piedra, trigo y bayas, y vende pan, antorchas, soga, lona, la mochila grande, la espada de metal y planos. La moneda son las **monedas de oro**.
- **Misiones de Valdoria:** llegar al puerto, conocer el mercado, ir a Robledal, arreglar el molino, la cosecha, derrotar a los bandidos y a Rurik, y la **audiencia con la reina**, que entrega la **Espada real de Valdoria** y cierra la historia de esta versión.
- El mapa (M) muestra la región donde estás. Arriba de la pantalla se ve el nombre del lugar (Puerto Albor, Robledal...).

### Mundo
- **Isla de 512 × 512 m** (4 veces más grande) con **4 biomas**: Pradera, Bosque, Desierto y Tundra nevada. Cada uno tiene sus colores, árboles, recursos y animales. Arriba de la pantalla se ve en qué bioma estás.
- **Vegetación abundante:** 5 tipos de árbol (pino, pino nevado, roble grande, abedul, árbol redondo y árbol seco), helechos, flores de 4 colores, hongos, piedritas, troncos caídos, juncos en la orilla, arbustos y matorrales secos. Las hojas y el pasto se mueven con el viento.
- **Gráficos más realistas:** terreno suave con roca en las pendientes y nieve en las cumbres, cielo con nubes que se mueven, sol y estrellas, agua con reflejos y ondas, tonos de cine (ACES) y sombras suaves. En calidad **Alta** y **Ultra** (Opciones → Gráficos) se suman oclusión ambiental (SSAO), luz rebotada (SSIL), iluminación global (SDFGI) y niebla volumétrica.
- **Ciclo de día y noche** de 30 minutos (unos 20 de día y 10 de noche), sincronizado para todos los jugadores.

### Supervivencia
- **Vida, hambre y energía.** El hambre baja con el tiempo y, si llega a 0, perdés vida. La energía se gasta al correr, saltar y pelear.
- **Comida:** bayas, carne cruda (hace mal) y carne cocida (cocinala con E sobre una fogata).
- **Muerte:** dejás todo en el suelo y reaparecés en el campamento.

### Personaje y habilidades (tecla C)
- Ganás **experiencia** con todo lo que hacés: recolectar (2), fabricar (5), construir (8), abrir cofres (12), cazar (15), matar sombras (25) y brutos (70), domesticar (60) y completar misiones (120, para todo el grupo).
- Cada nivel da **1 punto** (2 puntos cada 5 niveles). Los gastás en 6 habilidades de hasta 10 niveles:
  - **Vitalidad:** +15 de vida máxima.
  - **Resistencia:** +15 de energía máxima y recuperación un 8% más rápida.
  - **Fuerza:** +10% de daño.
  - **Recolección:** +15% de recursos.
  - **Carga:** +6 kg de capacidad.
  - **Agilidad:** +4% de velocidad.
- El progreso se guarda con la partida y cada jugador tiene el suyo.

### Combate y animales
- **Armas:** garrote de madera, lanza de piedra (mucho alcance) y espada de metal (en la mesa de trabajo).
- **Animales:** conejo, ciervo, jabalí, lobo, oso y lagarto. Huyen, se defienden o te atacan según la especie. Al cazarlos sueltan carne y cuero.
- **Sombras nocturnas:** de noche aparecen sombras (y desde el día 2, brutos) que te buscan. Son más lentas que vos corriendo, así que siempre podés escapar. Se queman al amanecer y pueden soltar **planos**.
- **Domesticación:** ver **[TABLA_DOMESTICACION.md](TABLA_DOMESTICACION.md)**.

### Construcción
- **Planos:** se encuentran en **30 cofres** repartidos por la isla (se rellenan cada 8 minutos) o derrotando sombras. Click con el plano en la mano lo aprende **todo el grupo**.
- **Martillo:** con el martillo en la mano ves una vista previa (verde si se puede construir, rojo si no). R cambia de pieza, click construye y click derecho desarma.
- **Piezas:** cimiento, pared, puerta que se abre con E, techo (que sirve de segundo piso) y fogata, en versiones de madera y de piedra. Encajan solas en una cuadrícula de 3 m.

### Mapa, brújula, cajas y camas
- **Mapa (M):** relieve y biomas desde arriba, con vos y tus compañeros, los habitantes, los lugares importantes, el objetivo de la misión, tus camas y construcciones, tus mascotas y el lugar donde moriste.
- **Brújula** arriba de la pantalla: muestra hacia dónde mirás y la dirección del campamento, de tu cama y del objetivo de la misión.
- **Caja de almacenamiento** (18 casilleros) y **cama**: se construyen con el martillo desde el principio, sin plano. Arrastrá objetos entre tu mochila y la caja, o usá Shift+Click. Si morís, reaparecés en tu cama (E sobre una cama la hace tuya). Todo se guarda con la partida.

### Sonido y música
- Efectos para los pasos, la tala, la piedra, los golpes, las criaturas, las puertas, los cofres, la comida, la construcción y las misiones, más los truenos de la cinemática.
- Ambientes en loop: viento, olas cerca del mar, grillos de noche, lluvia y fuego crepitando en fogatas y hornos.
- Música ambiental que cambia entre el menú, el día y la noche.
- **Todo se genera por síntesis** con `tools/gen_audio.py` (Python + numpy + scipy): no se usan sonidos de terceros. El volumen se ajusta en Opciones → Sonido.

### Estaciones
- **Mesa de trabajo, horno y fogatas:** apretá E y se abre el inventario solo con las recetas de esa estación.

- **Personajes articulados** (cabeza, torso, brazos y piernas con codos y rodillas) con animaciones de quieto, caminar, correr, saltar, caer, aterrizar, golpear, fabricar y caminar encorvado por el peso. Cada jugador tiene su propia apariencia.
- **NPCs con diálogos:** Tomás el leñador (campamento), Ilse la herrera (forja), Eco el ermitaño (cerca de la cima) y Nilo el pescador (muelle). Muestran **!** cuando tienen una misión y **?** cuando podés entregarla.
- **10 misiones** con objetivos de juntar, fabricar, entregar, hablar y explorar. El progreso es compartido y **las recompensas las recibe cada jugador**.
- **Fabricación** desde el inventario (Tab): antorcha, hachas y picos de piedra y de metal, mochila grande y fundición de metal. Algunas recetas piden estar cerca de la **mesa de trabajo** (campamento) o del **horno** (forja). Tiene cola de fabricación con barra de progreso y se puede cancelar (devuelve los materiales).
- **Recursos nuevos:** plantas de fibra (a mano) y fragmentos de metal (se funden en el horno).

- **Isla procedural** de 256 × 256 m generada con una semilla compartida: todos los jugadores ven el mismo mundo sin enviar el terreno por red.
- **Recursos:** árboles (madera), rocas (piedra) y rocas con vetas naranjas (mineral de metal). Reaparecen a los 90 segundos.
- **Inventario por casilleros:** 6 de barra rápida + 24 de mochila, con pilas, arrastrar y soltar, dividir y tirar al suelo.
- **Peso:** cada objeto pesa. Hasta el 40% de la capacidad (40 kg) te movés normal. Después vas cada vez más lento, y si te pasás de la capacidad quedás sobrecargado: sin correr y con saltos cortos. La mochila del personaje crece a la vista.
- **Herramientas:** con el hacha o el pico en la mano sacás el triple de recursos. Arrancás con las dos.
- **Bolsas en el suelo:** si se te llena el inventario, lo que no entra cae al piso. Cualquiera puede recogerlo y desaparece a los 5 minutos.
- **Volver a entrar:** si salís y volvés a la misma partida con el mismo nombre, recuperás tu inventario.
- **Multiplayer cooperativo** de 2 a 6 jugadores con ENet. El host es la autoridad: valida la distancia y el ritmo de recolección y lleva los inventarios.
- **Misiones compartidas:** el progreso es del grupo entero. Hay 3 misiones de ejemplo: recolectar, recolectar y llegar a un lugar.
- **Cinemáticas:** planos de cámara con barras negras, subtítulos y fundidos. Hay una intro, la revelación del monolito y el final de la demo.
- **HUD:** mochila, misión actual, jugadores conectados, avisos y menú de pausa.
- **Gente que entra tarde:** recibe las misiones y los recursos agotados al conectarse.

## Estructura

```
scenes/
  main.tscn            Escena principal (mundo + spawner de jugadores)
  player.tscn          Jugador + MultiplayerSynchronizer
scripts/
  main.gd              Menú → mundo, argumentos de línea de comandos
  autoload/
    save_manager.gd    Guardado y carga de mundos (user://saves)
    sound.gd           Efectos, ambientes y música
    settings.gd        Opciones del jugador (se guardan en user://settings.cfg)
    game.gd            Estado local: inventario, barra rápida, peso, controles, pausa
    network.gd         Host / unirse, registro de jugadores (ENet)
    quest_manager.gd   Misiones cooperativas (datos + lógica del servidor)
    cinematics.gd      Reproductor de cinemáticas
  world/
    world.gd           Genera el mundo + lógica del servidor (recolección, inventarios, barco, comercio)
    terrain_generator.gd  Terreno procedural en dos regiones: la isla y Valdoria
    mainland_builder.gd   Puerto, pueblo, castillo y campamento bandido de Valdoria
    medieval_props.gd     Casas, taberna, mercado, molino, murallas, torres, carpas, trigo
    voyage_stage.gd       Escenario de la cinemática del viaje en barco
    interactable.gd       Objetos que se usan con E (el Albatros)
    prop_factory.gd    Modelos low-poly por código (árboles, rocas, monolito, fogata)
    resource_node.gd   Recurso recolectable
  characters/humanoid.gd  Personajes con modelo 3D (models/*.glb) + animaciones procedurales
  data/
    item_db.gd         Todos los ítems (nombre, peso, pila, herramienta)
    recipe_db.gd       Recetas de fabricación
    quest_db.gd        Misiones (textos, objetivos, recompensas)
    npc_db.gd          NPCs (nombre, apariencia, saludos) y comercio de Berta
    ship_db.gd         Etapas de reparación del Albatros
    creature_db.gd     Animales y sombras (vida, daño, comida para domesticar)
    build_db.gd        Piezas de construcción (costo, planos necesarios)
    inventory.gd       Lógica del inventario (agregar, mover, dividir, peso)
  world/item_drop.gd   Bolsa en el suelo
  world/npc.gd         NPC (mira al jugador, marcador ! / ?)
  world/creature.gd    Animales y sombras (IA en el servidor, domesticación)
  world/build_piece.gd Piezas de construcción
  world/day_night.gd   Ciclo de día y noche
  world/grass.gd       Pasto por parcelas con viento
  world/station.gd     Estaciones interactuables
  world/loot_chest.gd  Cofres con botín
  characters/quadruped.gd  Cuerpo y animaciones de los animales
  world/intro_stage.gd Escenario de la cinemática del naufragio (barco, tormenta)
  ui/map_ui.gd         Mapa de la isla (tecla M)
shaders/               Pasto y agua
audio/                 Sonidos y música (generados por tools/gen_audio.py)
tools/gen_audio.py     Generador de audio por síntesis
tools/gen_characters.py  Generador de los modelos 3D de los personajes (Blender)
models/                Modelos 3D de los personajes (humano, sombra y bruto)
  player/player.gd     Movimiento, peso, cámara 3ª persona, herramientas, interacción
  ui/
    inventory_ui.gd    Barra rápida, ventana de inventario, indicador de carga
    item_slot.gd       Casillero con arrastrar y soltar
    item_icon.gd       Íconos dibujados por código
    settings_menu.gd   Menú de opciones
    crafting_panel.gd  Panel de fabricación
    dialog_ui.gd       Diálogos con NPCs
```

### Cómo agregar cosas

- **Una misión nueva:** agregala en `scripts/data/quest_db.gd` (con `giver` = el NPC que la da).
- **Una receta:** agregala en `scripts/data/recipe_db.gd`.
- **Un NPC:** agregalo en `scripts/data/npc_db.gd` y ubicalo en `_place_settlements()` de `world.gd`.
- **Una cinemática:** agregá un caso en `build_cinematic()` de `world.gd`. Cada plano tiene posición inicial y final de la cámara, el punto al que mira, la duración y el texto.
- **Un ítem:** agregalo en `ITEMS` de `scripts/data/item_db.gd` (nombre, peso, pila) y su ícono en `item_icon.gd`.
- **Cambiar cuánto se puede cargar:** `CAPACITY_KG` en `scripts/data/inventory.gd`.

## Modelos 3D de los personajes

Los personajes usan modelos 3D con esqueleto, en estilo low-poly inspirado en Albion Online (proporciones robustas, ropa en capas y colores planos). Están en `models/`:
- `humanoid.glb`: jugadores, habitantes, guardias y bandidos. Las partes de piel, pelo, camisa, pantalón, botas y capa se pintan con los colores de cada personaje, y los accesorios (pelo largo, rodete, barba, gorra, sombrero de paja, capucha, delantal, corona, casco, cota de malla, capa, vestido y pañuelo) se muestran según quién sea.
- `shade.glb`: las sombras (manto en jirones, garras y ojos que brillan).
- `brute.glb`: el bruto sombrío (cuernos, hombreras de hueso, puños enormes y grietas que brillan).

Los tres comparten el mismo esqueleto: las animaciones (caminar, correr, saltar, golpear, fabricar, encorvarse con peso) se calculan por código en `scripts/characters/humanoid.gd` y mueven sus huesos.

**Para cambiarlos:** se generan con `tools/gen_characters.py` (Blender como módulo de Python: `pip install bpy`, después `python tools/gen_characters.py`). También se pueden abrir en Blender y retocar a mano: mientras se mantengan los nombres de los huesos (hips, spine, head, shoulder_l, elbow_l, hand_l, hip_l, knee_l, ankle_l y sus pares _r), el juego los anima igual.

## Créditos de tipografías

El logo y el título del menú usan **Cinzel Decorative** (Natanael Gama) y **Marcellus SC** (Astigmatic), las dos con licencia libre [SIL Open Font License 1.1](fonts/OFL_CinzelDecorative.txt). Están en la carpeta `fonts/`.

## Hoja de ruta

1. ~~Prototipo base: mundo, jugador, cooperativo~~ ✅
2. ~~Recolección de madera y piedra~~ ✅
3. ~~Misiones y cinemáticas básicas~~ ✅
4. ~~Inventario por casilleros, peso y herramientas~~ ✅
5. ~~Fabricación, NPCs con misiones y personajes animados~~ ✅
6. ~~Biomas, día/noche, supervivencia, combate, animales, domesticación y construcción~~ ✅
7. ~~Menú con fondo animado, modo solo y guardado de partidas~~ ✅
8. ~~Mapa (tecla M) y brújula~~ ✅
9. ~~Cajas de almacenamiento y camas para reaparecer en tu base~~ ✅
10. ~~Sonido y música~~ ✅
11. ~~Cinemática de inicio: el naufragio del Albatros~~ ✅
12. ~~Misión principal (reparar el Albatros) y el reino medieval de Valdoria~~ ✅
13. ~~Modelos 3D con esqueleto para los personajes, las sombras y el bruto~~ ✅
14. Modelos 3D para los animales (ciervo, lobo, oso...) con el mismo sistema
