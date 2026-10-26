# Modelos 3D — Tierras Vivas

## Incluidos (licencia CC0, verificada)

| Carpeta | Pack | Autor | Licencia |
|---|---|---|---|
| `characters/` | KayKit Adventurers 1.0 (Knight, Barbarian, Mage, Rogue; 76 animaciones cada uno) | Kay Lousberg | CC0 — `characters/LICENSE_KayKit_Adventurers.txt` |
| `village/` | KayKit Medieval Hexagon 1.0 (casas, forja, taberna, pozo, molino, árboles, rocas, objetos) | Kay Lousberg | CC0 — `village/LICENSE_KayKit_Medieval.txt` |

Fuente: repositorios públicos `KayKit-Game-Assets` en GitHub. El crédito no es obligatorio, pero se agradece (www.kaylousberg.com).

## Casas y objetos

`scripts/world.gd` carga cada edificio con `_building(archivo, x, z, puerta, escala)` y los objetos con `_place(...)`;
los coloca con la base en el suelo, centrados, y les crea la colisión de su tamaño. Los modelos KayKit vienen en
miniatura, por eso se escalan (`S_BUILD`, `S_PROP`). Si un archivo no existe, se dibuja la versión con primitivas.
Para probar la escala de un modelo nuevo: `godot --path . -s tools/preview_models.gd -- salida.png village <filtro> <escala>`.

## Árboles y vegetación

Para Quest 3S, prioriza modelos de 1.000–5.000 triángulos por árbol, materiales simples y texturas de 1K o menos. Usa pocas transparencias y evita hojas con muchos materiales. Mantén el bosque lejano con instancias repetidas y reserva los modelos detallados para el primer plano.

## Personajes

`scripts/humanoid.gd` usa el modelo indicado en `"model"` (tabla `MODELS`) y reproduce sus animaciones: quieto,
caminar, correr y los gestos de `GEST_ANIM` (saludar, hablar, martillar…). Gira la cabeza hacia el jugador y asiente al
hablar. Un personaje nuevo debe traer rig **y** animaciones en el GLB; un modelo estático saldrá en pose T.
Si cambias de pack, ajusta los nombres de `GEST_ANIM` y `LOOPED` a los de sus animaciones.

## Licencias y procedencia

Antes de incluir cualquier pack en el repositorio, verifica la licencia del archivo concreto y conserva el crédito o la licencia exigidos por su autor. No añadas recursos de tiendas o packs con licencia desconocida a un repositorio público.

## Validación de rendimiento

- Objetivo inicial: 72 FPS en Quest 3S.
- Evita luces dinámicas por cada casa/árbol y materiales únicos innecesarios.
- Comprueba las sombras, el número de materiales y las colisiones en el visor.
- Prueba la escena en Godot antes de exportar el APK.
