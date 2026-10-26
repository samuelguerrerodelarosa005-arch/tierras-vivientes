# Tierras Vivas — Godot 4 (PC VR)

RPG de realidad virtual para PC inspirado en Log Horizon y Overgeared. Plataforma actual: **solo PC VR**
(Meta Link / Air Link y SteamVR), un jugador. El diseño completo está en el documento de diseño (GDD).

Pueblo de Valdeluz, 4 habitantes con agenda, memoria, afinidad y rumores; trabajos libres (principal + secundario);
forja, comida, hechizos con gestos, limos, tienda, portal nocturno, Ruinas Lunares, títulos y fragmento de recuerdo.

Los habitantes, edificios, árboles y objetos usan modelos **KayKit** (Kay Lousberg, licencia **CC0**). Los habitantes
vienen con sus animaciones. Lo que no tiene modelo (fuente, Santuario, portal, ruinas, limos) sigue con primitivas.

## 1. Jugar desde Godot (para desarrollar)

1. Descarga el repositorio (Code → Download ZIP) y descomprímelo.
2. Abre `Godot_v4.8-beta1_win64.exe` → **Importar** → elige `godot/project.godot` → **Importar y editar**.
3. Elige cómo conectas el visor (abajo) y pulsa **F5**. Sin visor arranca en modo PC (teclado y ratón).

## 2. Conectar el visor

El juego usa **OpenXR**, así que funciona con el sistema de VR que tengas marcado como «activo» en Windows.

**Meta Quest (3, 3S, 2, Pro) con Meta Link** — recomendado para el Quest, porque las **manos** funcionan:
1. Instala la app **Meta Horizon Link** en el PC.
2. Conecta el visor con cable USB-C (**Link**) o por wifi de 5/6 GHz (**Air Link**, router cerca).
3. En la app: Ajustes → General → **OpenXR Runtime → establecer Meta Horizon Link como activo**.
4. Pulsa F5 en Godot (o abre el `.exe`): el juego entra en VR solo.

**SteamVR** (Index, Vive, Pico, PS VR2 con adaptador, o Quest con Steam Link):
1. Abre SteamVR → Ajustes → OpenXR → **establecer SteamVR como runtime de OpenXR**.
2. Pulsa F5 o abre el `.exe`.

Mandos soportados: Quest Touch, Valve Index, HTC Vive, Windows Mixed Reality, Pico y el perfil genérico.
Si el visor no da ni mandos ni manos, el juego pasa a **apuntar con la mirada**: mira un botón 1,4 s para pulsarlo.

## 3. Jugar sin abrir Godot

Descomprime `TierrasVivas-PCVR-win64.zip` y abre `TierrasVivas.exe` con el visor conectado como en el paso 2.
Para generarlo tú: en Godot, **Proyecto → Exportar → «Windows PC VR» → Exportar proyecto** (la primera vez Godot pide
descargar las plantillas de exportación).

## Calidad gráfica

Menú → Ajustes → **Gráficos**: Baja · Media · Alta · Ultra. Cada nivel cambia sombras, antialiasing (MSAA), oclusión
ambiental, brillo, distancia de dibujado y resolución. En VR un tirón marea: si lo notas, baja un nivel.

## Standalone (Quest sin PC): más adelante

La versión para el visor sin PC está en pausa. El proyecto conserva lo necesario para volver: la simulación vive aparte de
los gráficos y en Android se usa el renderizador Compatibility (`rendering_method.mobile`). Para exportar un APK
habrá que usar el plugin **Godot OpenXR Vendors** con *Gradle Build*.

## Controles en el visor

- **Mandos**: stick izquierdo moverte · stick derecho girar · gatillo derecho apuntar y usar · gatillo izquierdo
  canalizar hechizo y soltar lanzando la mano · X cambiar hechizo · A saltar (o salta de verdad de pie) · B cerrar diálogo.
- **Manos**: pellizco derecho apuntando = usar · pellizca el suelo y suelta = moverte · pellizco izquierdo = hechizo ·
  puño = trazar un gesto propio · baja la mano izquierda = panel de muñeca (girar, saltar, comer, sentado, menú).
- **Gestos propios**: Menú → **Gestos** → elige qué quieres que haga (un hechizo, comer, saltar, descansar, abrir el menú,
  girar…) y traza el gesto 3 veces. Después, mantén el **agarre** (puño o botón lateral del mando) y dibújalo en el aire:
  se ejecuta. En PC funciona igual manteniendo el **clic derecho** y dibujando con el ratón. Hazlo siempre en el mismo
  sentido y con la misma forma; el tamaño y hacia dónde mires no importan.
- **Lanzar con gesto**: si el gesto es la **Bola de fuego**, no se lanza al momento. Queda **preparada** en esa mano
  con un **láser** de su color que marca dónde caerá (el punto crece si apuntas a un limo). Apunta y **haz el
  movimiento de lanzar** (mano rápida hacia delante) o pulsa el gatillo / pellizca. El maná se gasta al lanzarla;
  si no la lanzas en 8 s se desvanece sin gastar nada. Escudo y Curar se lanzan al instante (no hay que apuntar).
  En PC: el gesto la prepara y el **clic izquierdo** la lanza hacia la mira. El gatillo izquierdo también muestra
  el láser mientras canalizas.
- **Comer**: la comida aparece en tu mano derecha; llévala a la boca (3 mordidas).
- **Forjar**: golpea el yunque con el martillo o pulsa el gatillo cuando la marca esté en la luz.

## IA de los habitantes

Ahora hablan con su **guion**. No hay APIs de pago: la IA local (modelo de lenguaje, voces diseñadas y clonadas,
reconocimiento de voz, todo en el PC del jugador) llega en la **fase 2**. El hueco ya está preparado:
`dialogue.ai_provider` en `scripts/dialogue.gd`.

## Qué falta

- **Hechizos por voz**: Godot no trae reconocimiento de voz. Hace falta un plugin (por ejemplo el Voice SDK de Meta
  o Whisper). Mientras tanto, los hechizos se lanzan con gesto, gatillo o teclas.
- **Lanzamiento probado solo en simulación**: el umbral del gesto de lanzar (2,2 m/s, `THROW_SPEED` en
  `scripts/player.gd`) no se ha probado en el visor. Si se dispara solo o cuesta lanzarlo, sube o baja ese número.
- **Voces de los habitantes**: por ahora usan el texto a voz de Windows. Las voces con IA llegan en la fase 2.

## Gráficos y modelos

- `models/characters/`: Knight, Barbarian, Mage y Rogue (KayKit Adventurers, 76 animaciones cada uno).
  Cada habitante elige modelo en `scripts/data.gd` (`"model"`, y `"hide"`/`"show"` para quitar cascos o poner el bastón).
  El jugador elige el suyo en el creador (**Aspecto**); «Clásico» es el muñeco de primitivas con colores.
- `models/village/`: casas, panadería, forja, taberna, pozo, molino, árboles, rocas, vallas, barriles… (KayKit Medieval Hexagon).
  Vienen en miniatura: `world.gd` los escala (`S_BUILD`, `S_PROP`) y les pone colisión de su tamaño.
- Si borras un modelo, el juego vuelve a dibujar esa pieza con primitivas en el mismo sitio.

**Por qué no se veía bien el modelo «villager.glb»**: era un maniquí base (Universal Base Characters) sin ropa, sin
textura y **sin animaciones**. Godot no puede animar lo que el archivo no trae, por eso salía en pose T. Si quieres otro
personaje, necesita el esqueleto **y** las animaciones (en el mismo `.glb` o en uno compatible).

**Estilo final (fase 6)**: en PC se puede subir a un estilo más realista. La vía práctica para personajes es Mixamo
(personaje + animaciones, cuenta gratuita de Adobe) exportado a `.glb`: se cambia la ruta en `MODELS` de
`scripts/humanoid.gd` y los nombres de animación en `GEST_ANIM`.

Capturas para revisar el aspecto sin visor: `godot --path godot -- --shots` (guarda PNG en `user://shots`).

## Prueba automática

```
godot --headless --path godot -- --smoke   # 35 comprobaciones: diálogo, forja, comida, hechizos, rumores, portal, panel VR, gestos, apuntar y lanzar, modelos animados, sin API de pago, guardado
godot --headless --path godot -- --soak    # simulación acelerada del pueblo
```

## Estructura

| Archivo | Qué hace |
|---|---|
| `scripts/main.gd` | Bucle del juego, interactuables, hechizos, forja, comida, tienda, rumores, portal, cielo, guardado |
| `scripts/game.gd` | Datos y estado global (autoload `Game`): trabajos, sinergias, misiones, títulos, guardado |
| `scripts/player.gd` | Jugador en primera persona: PC, mandos y hand tracking (OpenXR) |
| `scripts/npc.gd` + `scripts/data.gd` | Habitantes: agenda, rutas, visitas, memoria, afinidad, rumores |
| `scripts/dialogue.gd` | Conversación con guion; hueco `ai_provider` para la IA local (fase 2) |
| `scripts/ui.gd` + `scripts/panel3d.gd` | Interfaz de PC y paneles 3D clicables en VR |
| `scripts/world.gd` | Construcción del pueblo, terreno, portal y ruinas |
| `scripts/humanoid.gd` | Personajes: modelo KayKit animado (o primitivas) |
| `scripts/slime.gd`, `scripts/sfx.gd`, `scripts/util.gd` | Limos, sonidos, utilidades |
| `models/` | Modelos KayKit (CC0) con sus licencias |
| `tools/preview_models.gd` | Pone modelos junto a una persona de 1,75 m para comprobar la escala |
| `tools/add_pcvr_profiles.gd` | Añade al mapa de acciones los mandos de PC VR (Index, Vive, WMR) |
