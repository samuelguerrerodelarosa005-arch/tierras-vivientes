# Modelos 3D opcionales — Tierras Vivas

Esta carpeta está preparada para importar modelos propios en formato GLB. **No se incluyen modelos externos en este commit**: así no se redistribuyen assets sin comprobar su licencia ni se descargan archivos binarios sin que el autor los elija.

## Casas

Ruta opcional que reconoce el código:
- `models/environment/medieval_house.glb`

El modelo se usa como sustituto de las casas procedurales de `scripts/world.gd`. Si el archivo no existe, el juego conserva automáticamente las casas procedurales. El modelo debe estar centrado cerca del origen, con el suelo en Y=0 y una dimensión de referencia cercana a 8 metros. Ajusta la escala y orientación si el pack tiene otro origen.

## Árboles y vegetación

Para Quest 3S, prioriza modelos de 1.000–5.000 triángulos por árbol, materiales simples y texturas de 1K o menos. Usa pocas transparencias y evita hojas con muchos materiales. Mantén el bosque lejano con instancias repetidas y reserva los modelos detallados para el primer plano.

## Personajes

El sistema actual de `scripts/humanoid.gd` crea el esqueleto visual con primitivas y mueve brazos y piernas directamente. Un personaje realista debe incluir un rig humanoide y animaciones exportadas en GLB (por ejemplo `Idle`, `Walk`, `Talk`). No basta con copiar un modelo estático: hay que adaptar `animate()` y las referencias de extremidades para no romper gestos, diálogo ni el creador de personaje.

## Licencias y procedencia

Antes de incluir cualquier pack en el repositorio, verifica la licencia del archivo concreto y conserva el crédito o la licencia exigidos por su autor. No añadas recursos de tiendas o packs con licencia desconocida a un repositorio público.

## Validación de rendimiento

- Objetivo inicial: 72 FPS en Quest 3S.
- Evita luces dinámicas por cada casa/árbol y materiales únicos innecesarios.
- Comprueba las sombras, el número de materiales y las colisiones en el visor.
- Prueba la escena en Godot antes de exportar el APK.
