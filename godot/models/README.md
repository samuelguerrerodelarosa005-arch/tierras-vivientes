# Modelos 3D para Tierras Vivas (Godot 4.8 / Quest 3S)

## Estado actual

Esta carpeta **no incluye todavía modelos GLB**. El juego conserva sus modelos procedurales si no encuentra los archivos opcionales indicados abajo. No descargues ni redistribuyas assets de licencia desconocida.

## Paquete recomendado (gratuito, CC0)

El pack **Medieval Village MegaKit** de Quaternius contiene más de 300 piezas modulares de pueblo medieval, con formatos glTF y una licencia CC0:
- Página oficial: https://quaternius.com/packs/medievalvillagemegakit.html
- Descarga Standard: https://quaternius.itch.io/medieval-village-megakit

Es arte 3D estilizado, no fotorrealismo. Para Quest 3S es una base razonable porque los materiales y polígonos pueden mantenerse relativamente ligeros. Descarga el paquete desde la página oficial y conserva el archivo de licencia incluido.

## Rutas opcionales reconocidas por el código

Copia/exporta modelos glTF/GLB a estas rutas dentro de `godot/`:

- `models/environment/medieval_house.glb` — modelo de casa usado por el constructor de casas.
- `models/environment/tree_oak.glb` — árbol para los puntos cercanos; el bosque lejano sigue usando MultiMesh.
- `models/characters/villager.glb` — personaje humanoide con rig y animaciones opcionales, usado por habitantes.
- `models/characters/player_arm.glb` — brazo/antebrazo con mano, orientado para primera persona; se usa en PC si existe.
- `models/characters/enemy_slime.glb` — enemigo con escala aproximada de 1 m; puede incluir clips `Idle`, `Walk`, `Run` o `Jump`.

Los directorios `environment/` y `characters/` se pueden crear al importar los modelos. No basta con copiar el ZIP del pack: hay que localizar el modelo, exportarlo a GLB si viene en otro formato y copiarlo a la ruta esperada.

## Modelos de personajes y enemigos sugeridos

- **Habitantes/jugador humanoide:** [Modular Character Outfits — Fantasy](https://quaternius.itch.io/modular-character-outfits-fantasy) y los Universal Base Characters de Quaternius. Exporta una figura completa riggeada a `villager.glb`. Para el brazo de primera persona exporta solo brazo y mano, con el origen en la muñeca, a `player_arm.glb`. La ropa modular y los personajes usan licencia CC0 según la ficha del paquete.
- **Enemigos:** [Bestiary — Dungeon Monsters Kit](https://quaternius.itch.io/bestiary-dungeon-monsters-kit) contiene 7 monstruos riggeados con variantes de color, pero no incluye animaciones. Puedes usar un monstruo como enemigo en vez del limo, exportándolo como `enemy_slime.glb`; si no tiene clips, el código conserva el salto procedural del enemigo mientras usa el modelo.
- **Casas/entorno:** [Medieval Village MegaKit](https://quaternius.com/packs/medievalvillagemegakit.html) y [Stylized Nature MegaKit](https://quaternius.com/). Son assets estilizados de bajo poligonaje, no fotorrealismo.

Los enlaces son fuentes oficiales; descarga el paquete tú mismo y conserva su licencia. Los archivos binarios no se han incluido en este repositorio todavía.

## Importación recomendada

1. Abre `godot/project.godot` en Godot 4.8 y espera a que termine la importación.
2. Arrastra un archivo `.glb` a la carpeta correspondiente dentro del proyecto.
3. Selecciona el modelo y comprueba escala, orientación, materiales y colisiones en una escena de prueba.
4. Para personajes, usa un GLB riggeado con animaciones compatibles. El script busca clips con nombres como `Idle`, `Walk`, `Talk`, `Wave` y `Think`; los nombres distintos deben mapearse en `scripts/humanoid.gd`.
5. Prueba con el renderizador Mobile, sin sombras costosas ni materiales transparentes innecesarios. En Quest 3S, limita texturas grandes, materiales únicos y polígonos; mantén el bosque lejano instanciado con MultiMesh.

## Validación pendiente

La integración opcional del código no significa que los modelos estén incluidos ni que el proyecto ya se haya probado en un Quest 3S. Tras añadir modelos, ejecuta la prueba headless indicada en `README.md` y verifica en el visor FPS, colisiones, escala y animaciones.
