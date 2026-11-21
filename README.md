# NEXORA

RPG cooperativo de mundo abierto en 3D (2 a 6 jugadores) hecho con **Godot 4.3+** y **GDScript**.
Estilo low-poly: liviano para cualquier PC, pero con iluminación, sombras, niebla y brillo.

![Menú principal](docs/21_menu.png)

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

### Mundo
- **Isla de 512 × 512 m** (4 veces más grande) con **4 biomas**: Pradera, Bosque, Desierto y Tundra nevada. Cada uno tiene sus colores, árboles, recursos y animales. Arriba de la pantalla se ve en qué bioma estás.
- **Pasto denso que se mueve con el viento**, agua con olas, niebla y cielo dinámico.
- **Ciclo de día y noche** de 12 minutos (unos 8 de día y 4 de noche), sincronizado para todos los jugadores.

### Supervivencia
- **Vida, hambre y energía.** El hambre baja con el tiempo y, si llega a 0, perdés vida. La energía se gasta al correr, saltar y pelear.
- **Comida:** bayas, carne cruda (hace mal) y carne cocida (cocinala con E sobre una fogata).
- **Muerte:** dejás todo en el suelo y reaparecés en el campamento.

### Combate y animales
- **Armas:** garrote de madera, lanza de piedra (mucho alcance) y espada de metal (en la mesa de trabajo).
- **Animales:** conejo, ciervo, jabalí, lobo, oso y lagarto. Huyen, se defienden o te atacan según la especie. Al cazarlos sueltan carne y cuero.
- **Sombras nocturnas:** de noche aparecen sombras (y desde el día 2, brutos) que te buscan. Se queman al amanecer y pueden soltar **planos**.
- **Domesticación:** ver **[TABLA_DOMESTICACION.md](TABLA_DOMESTICACION.md)**.

### Construcción
- **Planos:** se encuentran en **30 cofres** repartidos por la isla (se rellenan cada 8 minutos) o derrotando sombras. Click con el plano en la mano lo aprende **todo el grupo**.
- **Martillo:** con el martillo en la mano ves una vista previa (verde si se puede construir, rojo si no). R cambia de pieza, click construye y click derecho desarma.
- **Piezas:** cimiento, pared, puerta que se abre con E, techo (que sirve de segundo piso) y fogata, en versiones de madera y de piedra. Encajan solas en una cuadrícula de 3 m.

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
    settings.gd        Opciones del jugador (se guardan en user://settings.cfg)
    game.gd            Estado local: inventario, barra rápida, peso, controles, pausa
    network.gd         Host / unirse, registro de jugadores (ENet)
    quest_manager.gd   Misiones cooperativas (datos + lógica del servidor)
    cinematics.gd      Reproductor de cinemáticas
  world/
    world.gd           Genera el mundo + lógica del servidor (recolección, inventarios)
    terrain_generator.gd  Terreno low-poly procedural
    prop_factory.gd    Modelos low-poly por código (árboles, rocas, monolito, fogata)
    resource_node.gd   Recurso recolectable
  characters/humanoid.gd  Cuerpo articulado + animaciones procedurales (jugadores y NPCs)
  data/
    item_db.gd         Todos los ítems (nombre, peso, pila, herramienta)
    recipe_db.gd       Recetas de fabricación
    quest_db.gd        Misiones (textos, objetivos, recompensas)
    npc_db.gd          NPCs (nombre, apariencia, saludos)
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
shaders/               Pasto y agua
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

## Hoja de ruta

1. ~~Prototipo base: mundo, jugador, cooperativo~~ ✅
2. ~~Recolección de madera y piedra~~ ✅
3. ~~Misiones y cinemáticas básicas~~ ✅
4. ~~Inventario por casilleros, peso y herramientas~~ ✅
5. ~~Fabricación, NPCs con misiones y personajes animados~~ ✅
6. ~~Biomas, día/noche, supervivencia, combate, animales, domesticación y construcción~~ ✅
7. ~~Menú con fondo animado, modo solo y guardado de partidas~~ ✅
8. Mapa (tecla M) y brújula
9. Cofres de almacenamiento, camas para reaparecer en tu base
10. Sonido y música
11. Modelos con esqueleto (Blender / Mixamo)
