# Tierras Vivas — Godot 4 (PC y Meta Quest 3/3S)

Port del prototipo WebXR a Godot 4.8 con OpenXR. Mismo juego: pueblo de Valdeluz, 4 habitantes con
agenda, memoria, afinidad y rumores; trabajos libres (principal + secundario); forja, comida, hechizos,
limos, tienda, portal nocturno, Ruinas Lunares, títulos y fragmento de recuerdo al morir.

Todo el 3D está hecho con primitivas desde código. El siguiente paso es cambiar esas primitivas por
modelos `.glb` (ver «Mejorar los gráficos»).

## 1. Abrirlo en tu PC

1. Descarga el repositorio (Code → Download ZIP) y descomprímelo.
2. Abre `Godot_v4.8-beta1_win64.exe` → **Importar** → elige `godot/project.godot` → **Importar y editar**.
3. Pulsa **F5**. Sin visor conectado arranca en modo PC.

Controles de PC: WASD moverte · Mayús correr · clic para fijar el ratón y lanzar hechizos · 1/2/3 hechizos ·
E usar · F comer · clic derecho + dibujar = gesto propio · Espacio saltar · I inventario · R rumores · H controles · Esc cerrar.

## 2. Probarlo en el visor desde el PC (más rápido para iterar)

1. Conecta el Quest 3S con Quest Link (cable) o Air Link.
2. En la app Meta Horizon Link del PC: Ajustes → General → **OpenXR Runtime → Establecer Meta Horizon Link como activo**.
3. Pulsa **F5** en Godot con Link activo: el juego entra en VR solo.

## 3. Exportarlo como app (APK) para el Quest 3S

Solo hay que hacerlo una vez:

1. Instala **JDK 17** y **Android Studio** (para el Android SDK).
2. En Godot: **Editor → Configuración del editor → Exportar → Android**: pon la ruta del Java SDK y del Android SDK.
3. **Proyecto → Instalar plantilla de compilación de Android**.
4. **AssetLib** (arriba en el editor) → busca **«Godot OpenXR Vendors»** → descargar e instalar →
   **Proyecto → Configuración del proyecto → Plugins** → activa el plugin.
5. **Proyecto → Exportar → Añadir… → Android** y configura:
   - *Gradle Build → Use Gradle Build*: activado.
   - *XR Features → XR Mode*: **OpenXR**.
   - Activa la opción del plugin de **Meta** (aparece con el plugin de vendors instalado).
   - *Meta XR Features → Hand Tracking*: **Optional** (o Required si solo quieres manos).
   - *Architectures*: solo **arm64-v8a**.
6. Pon el Quest en **modo desarrollador** (app Meta Horizon del móvil → Dispositivos → Modo de desarrollador) y conéctalo por USB.
7. Pulsa el icono de **Android** (arriba a la derecha) para instalar y ejecutar en el visor, o exporta el APK
   e instálalo con Meta Quest Developer Hub. Aparece en *Biblioteca → Orígenes desconocidos*.

Los nombres exactos de algunas opciones pueden variar un poco en la 4.8-beta.

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

Sin clave, los habitantes usan frases de respaldo. Con una clave de la API de Anthropic, Claude improvisa con
la personalidad, memoria y rumores de cada uno (la misión y la recompensa las decide siempre el juego).

- En PC: **Ajustes → IA de los habitantes** → pega la clave → Guardar. Se guarda solo en ese equipo.
- En el visor: define `tierras_vivas/ai/api_key` en **Proyecto → Configuración del proyecto** antes de exportar.
  Hazlo solo para tu APK personal y **no compartas ese APK**: la clave va dentro y se puede extraer.

## Qué falta respecto a la web

- **Hechizos por voz**: Godot no trae reconocimiento de voz. Hace falta un plugin (por ejemplo el Voice SDK de Meta
  o Whisper). Mientras tanto, los hechizos se lanzan con gesto, gatillo o teclas.
- **Lanzamiento probado solo en simulación**: el umbral del gesto de lanzar (2,2 m/s, `THROW_SPEED` en
  `scripts/player.gd`) no se ha probado en el visor. Si se dispara solo o cuesta lanzarlo, sube o baja ese número.
- **Voces de los habitantes**: usan el texto a voz del sistema (Windows o Android). La calidad depende del dispositivo.

## Mejorar los gráficos

Cada parte del mundo está en una función de `scripts/world.gd` (`_bakery`, `_forge`, `_tavern`…) y los personajes en
`scripts/humanoid.gd`. Para meter arte real:

1. Descarga modelos con licencia libre en `.glb` (por ejemplo los packs CC0 de **Quaternius** o **Kenney**) y
   arrástralos a una carpeta `models/` del proyecto.
2. En la función del edificio, cambia las primitivas por `load("res://models/xxx.glb").instantiate()` en la misma posición.
   Las colisiones (`Util.col_box`) pueden quedarse igual.
3. Para personajes animados, sustituye `humanoid.gd` por un modelo con `AnimationPlayer` (caminar, hablar, gestos)
   y llama a sus animaciones desde `animate()`.

## Prueba automática

```
godot --headless --path godot -- --smoke   # 33 comprobaciones: diálogo, forja, comida, hechizos, rumores, portal, panel VR, gestos, apuntar y lanzar, guardado
godot --headless --path godot -- --soak    # simulación acelerada del pueblo
```

## Estructura

| Archivo | Qué hace |
|---|---|
| `scripts/main.gd` | Bucle del juego, interactuables, hechizos, forja, comida, tienda, rumores, portal, cielo, guardado |
| `scripts/game.gd` | Datos y estado global (autoload `Game`): trabajos, sinergias, misiones, títulos, guardado |
| `scripts/player.gd` | Jugador en primera persona: PC, mandos y hand tracking (OpenXR) |
| `scripts/npc.gd` + `scripts/data.gd` | Habitantes: agenda, rutas, visitas, memoria, afinidad, rumores |
| `scripts/dialogue.gd` | Conversación (IA de Claude o guion de respaldo) |
| `scripts/ui.gd` + `scripts/panel3d.gd` | Interfaz de PC y paneles 3D clicables en VR |
| `scripts/world.gd` | Construcción del pueblo, terreno, portal y ruinas |
| `scripts/slime.gd`, `scripts/humanoid.gd`, `scripts/sfx.gd`, `scripts/util.gd` | Limos, personajes, sonidos, utilidades |
