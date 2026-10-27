# GDD — *Tierras Vivas* (título de trabajo)

**Género:** VRMMORPG de mundo vivo · **Plataformas:** Meta Quest 3/3S (standalone) + PC VR
**Motor recomendado:** Unity 6 LTS (URP) + OpenXR / Meta XR SDK
**Inspiraciones:** *Log Horizon* (subclases, cocina real, gobierno de jugadores, habitantes que despiertan) · *Overgeared / Satisfy* (forja con calidad real, títulos, piezas ocultas, NPCs con memoria)
**Versión del documento:** 0.2 — 25/10/2026 (trabajos libres, primera persona, hand tracking)

---

## 0. Advertencia de alcance (leer primero)

Este documento separa **la visión** (MMO completo) de **lo que se puede construir por fases**. La visión completa es de escala AAA y no es alcanzable por una persona ni en meses. El orden de construcción es:

| Fase | Qué es | Jugadores | Objetivo |
|---|---|---|---|
| **F0 — Prototipo WebXR** | Pueblo 3D en navegador del Quest (entregado junto a este GDD) | 1 | Validar sensaciones: voz + gesto, comer, NPCs con personalidad, forja, horarios |
| **F1 — Vertical slice Unity** | 1 pueblo, 1 zona exterior, 1 mazmorra, 5 NPCs con LLM, 7 trabajos combinables | 1 | Calidad final de una porción pequeña; APK instalable en el 3S |
| **F2 — Co-op** | Lo mismo con servidor dedicado | 4–8 | Party, chat de voz espacial, mazmorra en grupo, tiendas de jugador |
| **F3 — MMO acotado** | Una región, gremios, economía, compra de zonas | 100–500 por shard | Probar economía y costos reales de IA |
| **F4 — Visión completa** | Múltiples regiones, full-body tracking externo, PC "ultra" | miles | Solo si F3 demuestra retención y costos sostenibles |

**Regla:** no se avanza de fase sin que la anterior sea divertida *y* tenga un costo por jugador/hora medido.

---

## 1. Visión y pilares

> "Un mundo donde los habitantes recuerdan lo que hiciste, y tus manos y tu voz son la interfaz."

1. **Mundo vivo:** NPCs con personalidad, memoria y relaciones entre ellos; el mundo cambia por lo que hacen jugadores *y* NPCs.
2. **Cuerpo como control:** voz + gestos para habilidades, acciones cotidianas físicas (comer, forjar, escribir, montar).
3. **Identidad por combinación:** dos trabajos libres (principal + secundario) de una sola lista → builds únicos. Un Herrero puede ser Herrero de principal.
4. **Sociedad de jugadores:** tiendas, gremios, gobierno de zonas, jerarquía económica real.
5. **Confort primero:** todo jugable sentado; cada mecánica física tiene alternativa.

### Contradicciones de la premisa y cómo se resuelven
| Conflicto | Resolución |
|---|---|
| Modo sentado vs "levantar rodilla para saltar" | Dos perfiles de control: **Activo** (rodilla/cuerpo) y **Sentado** (botón o gesto de muñeca). El servidor no distingue: ambos producen la misma acción. |
| Realismo tipo Blade & Sorcery vs standalone | Dirección de arte **"realismo pintado"**: materiales y proporciones realistas, texturas estilizadas. Standalone usa iluminación horneada; PC añade tiempo real. |
| IA por NPC vs costo MMO | IA en capas con "nivel de detalle cognitivo" (sección 3.3). El LLM solo se usa cuando un jugador está conversando. |
| Misiones generadas vs balance | El LLM **narra**; el servidor **decide** recompensas con tablas (sección 3.4). |
| Full-body tracking | Fase F4. Antes: estimación de cuerpo del propio visor (Movement SDK) + IK. |

---

## 2. Mundo y premisa narrativa

Los jugadores despiertan como **Viajeros** en un continente donde los **Habitantes** (NPCs) viven sus vidas. Al inicio los Habitantes ven a los Viajeros como seres inmortales y extraños. A medida que interactúan, los Habitantes **despiertan**: forman opiniones, recuerdan, se organizan, compiten económicamente con los jugadores y piden ayuda. El arco del mundo depende de si los Viajeros los tratan como recursos o como personas (eco directo de los "People of the Land" de *Log Horizon*).

- **Ciclo día/noche:** 1 día de juego = 2 horas reales (configurable por servidor).
- **Fase lunar:** ciclo de 8 días de juego; afecta portales, monstruos y ciertas recetas.
- **Ciudades santuario:** sin PvP; contienen el **Santuario** de resurrección.

---

## 3. IA de NPCs — implementación técnica

### 3.1 Arquitectura en capas

```
┌─────────────────────────────────────────────────────────────┐
│ CAPA 4 · VOZ        STT (jugador) → texto | texto → TTS     │
│                     voz única por NPC (id de voz + tono)    │
├─────────────────────────────────────────────────────────────┤
│ CAPA 3 · LENGUAJE   LLM (Claude vía API) — solo en diálogo   │
│                     Salida: texto + INTENCIONES en JSON      │
├─────────────────────────────────────────────────────────────┤
│ CAPA 2 · MEMORIA    Episódica (vector DB) + Relaciones      │
│                     (grafo de afinidad) + Reputación         │
├─────────────────────────────────────────────────────────────┤
│ CAPA 1 · SIMULACIÓN Utility AI / GOAP en servidor            │
│                     necesidades, agenda, oficio, economía    │
└─────────────────────────────────────────────────────────────┘
```

**Capa 1 — Simulación (determinista, barata, siempre activa)**
- Cada NPC tiene: `necesidades` (hambre, dinero, seguridad, social), `agenda` por hora, `oficio` (herrero, granjero…), `inventario`, `rasgos` (Big Five simplificado: 0–1).
- Decide con **Utility AI**: cada acción candidata puntúa según necesidades × rasgos. Ej.: un herrero codicioso sube precios si la demanda de espadas sube.
- Corre en el servidor a 1 tick/seg (cerca de jugadores) o 1 tick/min (lejos).

**Capa 2 — Memoria**
- **Episódica:** eventos resumidos ("El Viajero Xavier me pagó de más por pan", fecha, importancia 1–10). Se guardan como embeddings en Postgres + `pgvector` (Supabase sirve).
- **Relaciones:** grafo `npc ↔ npc` y `npc ↔ jugador` con `afinidad (-100..100)`, `confianza`, `deuda`.
- **Olvido:** los recuerdos de baja importancia decaen; cada noche de juego un trabajo los **resume** (reflexión) para no crecer sin límite.

**Capa 3 — Lenguaje**
- Se invoca solo cuando hay conversación. El *prompt* se arma con: ficha del NPC (personalidad, voz, conocimientos), estado actual (Capa 1), top-k recuerdos relevantes (Capa 2), contexto del mundo (hora, eventos cercanos), y lo que dijo el jugador.
- El LLM responde con **texto** y una lista de **intenciones estructuradas** (tool calls), por ejemplo:

```json
{ "decir": "Si me traes 3 pieles de lobo, te hago un descuento.",
  "intenciones": [
    {"tipo": "proponer_mision", "plantilla": "recolectar", "objeto": "piel_lobo", "cantidad": 3},
    {"tipo": "ajustar_afinidad", "delta": 2},
    {"tipo": "emote", "anim": "rascarse_cabeza"} ] }
```

- El servidor **valida** cada intención contra reglas (¿tiene ese NPC autoridad para dar esa misión? ¿existe ese objeto?). Lo inválido se descarta en silencio. El LLM nunca toca el inventario ni el oro directamente.

**Capa 4 — Voz**
- **Entrada:** STT en streaming (Meta Voice SDK o Whisper en servidor). Palabras de activación del juego (nombres de hechizos) se reconocen **en el dispositivo** para baja latencia; la conversación libre va al servidor.
- **Salida:** TTS con streaming; cada NPC tiene `voice_id`, velocidad y tono. Lip-sync por visemas (OVR LipSync o equivalente).
- **Ocultar latencia (1–3 s):** el NPC hace animación de "pensar", dice una muletilla corta pregrabada de su personalidad ("Hmm…", "¡Ja! Mira…") mientras llega la respuesta.

### 3.2 Animación de NPCs
- Locomoción con *blend trees* (Mixamo/Asset Store) + IK de mirada (cabeza y ojos siguen al interlocutor) + gestos disparados por intenciones `emote`.
- Animaciones de oficio en bucle (martillar, barrer, vender) según la agenda.

### 3.3 Nivel de detalle cognitivo (LOD-C) — clave del costo

| Nivel | Cuándo | Qué corre | Costo |
|---|---|---|---|
| C0 | Ningún jugador en la región | Simulación estadística agregada (precios, población) | ≈0 |
| C1 | Jugador a < 200 m | Utility AI completa, agenda, rutas | CPU servidor |
| C2 | Jugador a < 10 m | + gestos reactivos, frases cortas pregrabadas/caché | CPU |
| C3 | Conversación activa | + LLM + TTS | API por token/carácter |
| C4 (nocturno) | 1 vez por día de juego | Reflexión: resumir memoria, generar rumores y planes | API por lotes |

**Fórmula de costo a vigilar:** `costo/hora = jugadores_concurrentes × conversaciones/hora × (tokens_por_turno × precio_token + caracteres_TTS × precio_TTS)`. Se limita con: respuestas cortas (≤ 60 palabras), caché de saludos, límite de turnos por conversación, y NPCs "menores" con diálogo de plantilla.

### 3.4 Misiones emergentes (jugador↔NPC y NPC↔NPC)

**Gramática de misiones** (el servidor la controla):
`NECESIDAD → OBSTÁCULO → ACCIÓN → RECOMPENSA`

- **NECESIDAD** viene de la simulación: el herrero no tiene hierro; la granjera perdió ovejas; dos NPCs tienen afinidad < -50.
- **Plantillas de ACCIÓN:** recolectar, entregar, escoltar, cazar, investigar, mediar, fabricar, defender.
- **RECOMPENSA** calculada por tabla: `nivel_zona × dificultad × rareza`, nunca por el LLM.
- El LLM recibe la misión ya armada y escribe el diálogo, el contexto y los rumores.

**NPC↔NPC:** durante la reflexión nocturna (C4), los NPCs con relación fuerte "conversan" en un lote barato. Salen **rumores** (texto corto) y **eventos** (ej.: el tabernero le debe dinero al herrero → conflicto). Los rumores se reparten a otros NPCs según su red social; un jugador puede escucharlos y desbloquear misiones de mediación. Ejemplo real de la cadena:

1. La granjera Lía vende menos trigo (sequía simulada).
2. El panadero Bruno sube el pan; la afinidad Lía↔Bruno baja.
3. Rumor: "Bruno acapara harina". Llega al guardia.
4. Misión emergente para el jugador: **investigar** (¿es cierto?) → recompensa y consecuencia en el pueblo (precio del pan, reputación de Bruno).

### 3.5 Seguridad y calidad
- Moderación de entrada/salida; los NPCs no salen de su personaje ni hablan del mundo real.
- Las claves de API **nunca** viajan en el APK: todo pasa por un backend propio (ej.: funciones en Supabase/Vercel) con límite de uso por cuenta.
- Respuesta de emergencia: si el LLM falla o tarda > 4 s, el NPC usa diálogo de plantilla.

---

## 4. Sistema de trabajos (dos ranuras libres)

### 4.1 Regla central
No hay "clases" y "subclases" separadas. Hay **una sola lista de trabajos** y dos ranuras:

- **Trabajo principal:** da el efecto **completo** de ese trabajo y fija la **vida y el maná base**.
- **Trabajo secundario:** da la **mitad** del efecto. Cualquier trabajo puede ir en cualquier ranura; solo no se puede repetir el mismo en las dos.
- Ejemplos válidos: Herrero + Elementalista, Cocinero + Comerciante, Guardián + Herrero, Rastreador + Sanador.
- Todos los Viajeros pueden lanzar los hechizos básicos; los trabajos los potencian. Así un artesano de principal no queda indefenso, solo menos eficaz en combate que un combatiente de principal.
- Cambiar el principal cuesta una misión en la ciudad; el secundario se cambia libremente en un gremio.

### 4.2 Trabajos del prototipo (7) y de la visión (25+)

| Trabajo | Tipo | Vida/Maná base | Como principal | Como secundario |
|---|---|---|---|---|
| Elementalista | Combate · Magia | 90 / 130 | Fuego +40 % | Fuego +20 % |
| Guardián | Combate · Defensa | 150 / 80 | Escudo ×2 de duración | +20 vida; escudo +50 % |
| Sanador | Combate · Soporte | 105 / 115 | Curar ×2 | Curar +50 % |
| Herrero | Oficio · Forja | 120 / 85 | Zona de golpe +80 %; +1 grado si la precisión supera 70 % | Zona de golpe +40 % |
| Cocinero | Oficio · Cocina | 110 / 95 | Comida ×2,5 y efecto ×2 de duración | Comida ×1,75 |
| Comerciante | Oficio · Comercio | 105 / 95 | Compras −25 %; clientes aceptan +35 % | Compras −12 %; +17 % |
| Rastreador | Oficio · Caza | 115 / 90 | Ve limos a 45 m a través de todo; +15 % de daño | Ve limos a 25 m |

Visión completa: los 9 de combate (Guardián, Centinela, Custodio, Espadachín, Arquero, Elementalista, Monje, Bardo de guerra, Sanador) y los 16 de oficio (Herrero, Cocinero, Escriba, Alquimista, Sastre, Carpintero, Encantador, Comerciante, Domador, Cartógrafo, Jardinero, Minero, Rastreador, Músico, Pescador, Médico de campo) en la **misma lista**.

### 4.3 Sinergias por pareja (sin importar el orden)

| Pareja | Sinergia |
|---|---|
| Guardián + Herrero | Escudo templado: con espada propia, el escudo absorbe 80 % en vez de 70 % |
| Elementalista + Cocinero | Cocina elemental: comer da +25 % de fuego por 60 s |
| Elementalista + Rastreador | Fuego guiado: la bola de fuego se curva hacia limos |
| Sanador + Cocinero | Caldo curativo: Curar también restaura energía |
| Sanador + Comerciante | Boticario: cada venta devuelve maná |
| Guardián + Rastreador | Centinela: −20 % de daño recibido de limos |
| Elementalista + Herrero | Fragua viva: forjar con efecto de fuego sube un grado |
| Cocinero + Herrero | Fogón de forja: bien alimentado, zona de golpe +15 % |
| Comerciante + Herrero | Marca de taller: tus espadas se venden hasta 30 % más caras |
| Cocinero + Comerciante | Pan de la casa: el pan te cuesta la mitad |
| Guardián + Sanador | Muralla viva: Curar da 3 s de escudo |
| Herrero + Rastreador | Ojo de minero: cada roca da 2 minerales |

### 4.4 Balance con dos ranuras libres

El riesgo nuevo de permitir cualquier trabajo en cualquier ranura es que dos trabajos de combate juntos dominen (ej. Elementalista + Guardián). Contramedidas:

1. **Regla 100/50:** el secundario siempre aporta la mitad. Dos combates suman como máximo 1,5 "trabajos de combate", nunca 2.
2. **Presupuesto de poder por pareja:** cada pareja se mide contra la media; si una supera el 115 % en el simulador, se recorta su sinergia, no los trabajos (así no se rompen las demás parejas).
3. **Rendimientos decrecientes:** bonos del mismo tipo (ej. dos bonos de daño) se suman con −30 %.
4. **Valor horizontal de los oficios:** los oficios dan cosas que el combate no da (calidad de forja, economía, información). Un grupo con un Herrero principal tiene mejor equipo aunque ese jugador pegue menos.
5. **Simulación antes de lanzar:** con 25 trabajos hay 25 × 24 = 600 parejas ordenadas. Simulador automático de combate y de economía; telemetría por pareja en vivo.

## 5. Mecánicas inmersivas VR

### 5.1 Hechizos: gesto + voz
- **Flujo:** (1) gesto de "canalizar" (mano abierta al frente o sigilo dibujado) abre una ventana de 2 s → (2) el jugador dice el nombre → (3) se lanza en la dirección de la mano.
- El gesto actúa como **pulsar para hablar**: evita activaciones falsas por conversación normal o por el chat de voz.
- **Vocabulario configurable por región/acento** y nombres personalizados (el jugador puede renombrar su hechizo y entrenar su pronunciación 3 veces).
- **Precisión del gesto = potencia:** sigilo bien dibujado → +10 % efecto; mal dibujado → se lanza igual con −10 % (nunca falla por completo, para no frustrar).
- **Alternativas de accesibilidad:** rueda radial en la muñeca; solo-gesto; solo-voz.

### 5.2 Acciones cotidianas
- **Comer/beber:** agarrar el objeto y llevarlo a la boca (zona de 15 cm frente al visor) → mordida con sonido y partículas; la comida se consume en 3 mordidas.
- **Escribir** (Escriba): trazar con una pluma en pergamino.
- **Forjar** (Herrero): martillar con ritmo (ver 7.2).
- **Pescar, tocar instrumentos, plantar.**

### 5.3 Movimiento
- **Perfil Activo:** rodilla arriba = saltar; agacharse real; correr con brazos (arm-swing).
- **Perfil Sentado:** stick para moverse, gesto de muñeca o botón para saltar; altura virtual compensada para que el avatar se vea de pie.
- **Full-body (F4):** trackers/cámaras externas en PC → emotes en tiempo real visibles para otros.

### 5.4 Hand tracking (sin mandos)
El juego funciona igual con mandos o con las manos del visor:
- **Pellizco con la mano derecha** apuntando: hablar, recoger, pulsar botones.
- **Pellizcar el suelo y soltar:** teletransporte (no hay stick).
- **Pellizco con la mano izquierda:** canalizar hechizo; soltar mientras lanzas la mano.
- **Bajar la mano izquierda:** aparece el panel de muñeca (girar, saltar, comer, cambiar hechizo, descansar, modo sentado).
- **Puño:** agarre (reservado para monturas y objetos físicos en F1).
- Comer y forjar usan la posición real de la palma.

### 5.5 Desplazamiento
- **Monturas físicas:** riendas agarrables; tirar = frenar, sacudir = acelerar, inclinar el cuerpo = girar (o stick en modo sentado). Viñeta de confort automática.
- **Portales mágicos:** solo activos en ventanas horarias y según fase lunar (ver 7.3).

### 5.6 Confort (opciones)
Teletransporte / movimiento suave · giro por pasos (15°/30°/45°) o continuo · viñeta (0–3) · altura y "modo sentado" · zurdo/diestro · subtítulos de NPCs · tamaño de texto · reducir partículas · sin cámara agitada.

---

## 6. Economía y sociedad

- **Tiendas de jugador:** puestos físicos alquilados en la plaza o locales comprados. El jugador coloca los objetos a mano en el mostrador y les pone precio. Los **NPCs también compran** según demanda simulada → hay clientes aunque no haya jugadores.
- **Jerarquía económica:** puesto ambulante → local alquilado → taller con aprendices NPC → gremio con sucursales.
- **Sumideros de oro:** alquiler, impuestos de zona, reparación, tarifas de portal, tasas de subasta.
- **Gremios:** sede física, banco compartido, rangos, misiones de gremio.
- **Grupos (party):** hasta 6; bonificación por roles distintos.
- **Chat de voz espacial:** atenuación por distancia, "susurro" (mano junto a la boca), canal de party/gremio por botón; silenciado/bloqueo rápido.
- **Mazmorras:** instanciadas; layout semi-procedural; NPCs pueden entrar con el grupo como mercenarios con personalidad.

---

## 7. Mecánicas adicionales inspiradas en *Log Horizon* y *Overgeared*

### 7.1 Cocina real *(Log Horizon)*
La comida hecha con el **menú** sabe "a nada": cura poco y no da buffs. La comida hecha **a mano** (cortar, mezclar, controlar el fuego, sazonar) por un jugador con subclase Cocinero da buffs reales y su calidad depende de lo bien hecho. Los NPCs notan la diferencia y pueden hacerse clientes fijos. Esto crea demanda social de cocineros.

### 7.2 Forja con calidad y autoría *(Overgeared)*
Al forjar, el jugador martilla sobre marcas que aparecen en el metal al ritmo del calor de la pieza. La precisión define el **grado**: Común → Raro → Épico → Único → Legendario. Los objetos Únicos+ llevan **el nombre del herrero** y un nombre dado por él. Los NPCs del pueblo recuerdan las obras maestras y la reputación del herrero crece.

### 7.3 Portales de hadas por hora y luna *(Log Horizon — fairy rings)*
Cada portal tiene un destino que **cambia según la hora y la fase lunar**. Hay tablas que los Cartógrafos pueden descubrir y vender como mapas. Viajar sin la tabla correcta te puede dejar en una región peligrosa. Esto cumple el requisito de "portales con horario" y lo convierte en conocimiento valioso.

### 7.4 Títulos con poder *(Overgeared)*
Hazañas otorgan títulos ("Amigo de los Panaderos", "Matador de la Bestia del Pantano") con pequeños bonus de estadísticas y **reacciones de NPCs**. Solo se puede tener 1 título activo + 2 pasivos.

### 7.5 Piezas y misiones ocultas *(Overgeared — hidden pieces)*
Algunas misiones solo aparecen con afinidad alta con un NPC concreto o en condiciones raras (luna llena + llover + estar en la taberna). No están en ninguna lista: se descubren hablando.

### 7.6 Resurrección con costo de memoria *(Log Horizon)*
Al morir, el jugador revive en el Santuario y pierde algo de experiencia en forma de un **"fragmento de recuerdo"** que queda en el lugar de la muerte por 30 min. Si vuelve a tiempo, lo recupera. Penaliza sin destruir progreso y genera momentos de rescate en grupo.

### 7.7 Compra de zonas y Consejo *(Log Horizon — zone purchase, Round Table)*
Los gremios pueden **comprar edificios y zonas** (incluidos portales y mercados) y fijar tasas dentro de un límite. Los dueños de zonas forman un **Consejo** que vota leyes de la ciudad (horario de mercado, impuestos, prohibiciones). Los NPCs reaccionan a esas leyes (protestas, migración). Es la jerarquía económica real que pediste, con contrapesos.

---

## 8. Personalización del jugador
- **Avatar:** altura, complexión, rostro (morph targets), piel, cabello (estilo/color), ojos, cicatrices/tatuajes. Sistema recomendado en Unity: UMA o similar.
- **Voz:** filtro de voz opcional (tono) para el chat de voz.
- **Ropa:** equipable por capas; los Sastres pueden teñir y crear diseños.
- **Emotes:** biblioteca + grabación de emotes propios con el tracking del visor (F2) o full-body (F4).
- **Casa:** muebles colocables a mano.

---

## 9. Apartado técnico

### 9.1 Stack recomendado
| Área | Tecnología |
|---|---|
| Motor | Unity 6 LTS, **URP en ambas plataformas** (no mezclar HDRP: duplicaría el trabajo) |
| XR | OpenXR + Meta XR SDK (manos, Movement SDK para cuerpo, passthrough opcional) |
| Red (F2+) | Servidor dedicado autoritativo (Netcode for GameObjects o Photon Fusion) |
| Backend | Supabase (Auth, Postgres, `pgvector` para memoria de NPCs, funciones edge como proxy del LLM) |
| LLM | Claude API vía backend |
| STT | Meta Voice SDK (palabras de hechizo en dispositivo) + Whisper/servicio en nube para conversación |
| TTS | Proveedor con streaming y múltiples voces en español |
| Animación | Mixamo / Asset Store + Animation Rigging (IK) |

### 9.2 Presupuesto de rendimiento — Quest 3/3S
- 72 Hz mínimo (objetivo 90 Hz), *fixed foveated rendering*, MSAA 4x.
- ≤ 150 draw calls visibles, ≤ 750k triángulos en escena.
- Iluminación **horneada** + sondas de luz; 1 luz dinámica (sol) sin sombras en tiempo real o sombras de baja resolución.
- LOD en todo; NPCs lejanos como impostores; texturas ASTC.

### 9.3 Menú gráfico profundo — PC
Calidad de texturas · distancia de dibujado · densidad de vegetación · sombras (resolución, cascadas, distancia) · iluminación en tiempo real · SSAO · reflejos (SSR / sondas) · niebla volumétrica · calidad de partículas/VFX · LOD bias · supersampling / resolución de renderizado · upscaling · físicas de tela y cabello · cantidad de NPCs visibles · preajustes (Bajo/Medio/Alto/Ultra) + perfil "Standalone equivalente".

### 9.4 Distribución en Quest 3S
1. Cuenta de desarrollador de Meta → activar modo desarrollador en el visor.
2. Compilar APK (Android, ARM64, OpenXR) desde Unity.
3. Instalar con Meta Quest Developer Hub (o SideQuest). Aparece en *Biblioteca → Orígenes desconocidos*.

---

## 10. Riesgos principales

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Costo de LLM + TTS escala con jugadores | Alto | LOD cognitivo, caché, límites de turnos, NPCs menores con plantilla |
| Latencia de conversación (1–3 s) | Medio | Muletillas, animación de pensar, streaming de TTS |
| Falsos positivos de voz | Medio | Gesto como pulsar-para-hablar |
| Rendimiento en standalone | Alto | Presupuestos fijos desde el día 1; probar en el 3S cada semana |
| Mareo | Alto | Opciones de confort, modo sentado por defecto |
| Economía inflacionaria | Alto | Sumideros, NPCs compradores, telemetría |
| Toxicidad en chat de voz | Medio | Bloqueo rápido, burbuja personal, reportes |
| Alcance | Crítico | Fases estrictas (sección 0) |

---

## 11. Prototipo F0 entregado (WebXR)

Prototipo en navegador que corre en el Quest 3S (Meta Quest Browser → "Entrar en VR") y en PC con teclado/ratón. Valida:

- Juego en **primera persona** (brazos visibles en PC; manos reales en VR). El creador de personaje muestra el avatar en 3D.
- Creador de personaje (altura, complexión, piel, cabello, ropa, capa) + **dos trabajos libres** de la misma lista, con sinergia mostrada.
- **Hand tracking** en el Quest: pellizco para usar, teletransporte al suelo, hechizos con la mano izquierda y panel de muñeca.
- Pueblo 3D con plaza, forja, taberna, puesto de jugador, campo con monstruos y un portal.
- 3 NPCs con personalidad, agenda, mirada, gestos, **voz sintetizada distinta** y diálogo con IA (o guion de respaldo), memoria de afinidad, conversaciones entre ellos que generan **rumores y misiones**.
- Hechizos por **voz** (si el navegador lo permite) y por **gesto/botón**.
- Comer llevando la comida a la boca.
- Forja rítmica con grados de calidad.
- Ciclo día/noche con **portal activo solo de noche**.
- Modo de pie / sentado.

Limitaciones honestas: modelos 3D hechos con primitivas (no arte final), un jugador, sin persistencia en servidor, y el reconocimiento de voz depende de lo que soporte el navegador del visor.

## 12. Estado del proyecto Godot (PC VR)

| Fase | Qué incluye | Estado |
|---|---|---|
| 0 | Paso a PC VR (Link / SteamVR), calidad gráfica, mandos de PC, sin APIs de pago | Hecha |
| 1 | Mundo vivo: economía con oro real, misiones que nacen de problemas, escrow, regateo, plazos, cadenas, hechos y rumores, reputación (miedo, respeto, cariño, confianza), ambiciones | Hecha (prueba `--month`) |
| 2 | Conversación por voz sin menús: micrófono con detección de voz → whisper.cpp → llama.cpp (entiende) → el juego decide → llama.cpp (dice, sin cifras) → Piper (voz 3D por NPC). Instalador `instalar_ia.bat`; servidor propio opcional | Hecha en simulación (prueba `--voicetest`); falta probar en el PC con visor |
| 2b | Voces clonadas con consentimiento; interrumpir al NPC mientras habla; respuestas en streaming | Pendiente |
| 3 | Camino oscuro: verbos de ataque, ciudades seguras, muerte de NPC fuera de la ciudad, misiones de defensa por rumores | Diseñada, sin implementar |
