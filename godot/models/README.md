# Modelos 3D y Meta Quest 3S

## Modelo incluido en el proyecto

El archivo `models/characters/villager.glb` ya está incluido en este repositorio. Es el modelo humanoide **Superhero Male** de Quaternius Universal Base Characters, con licencia CC0 1.0. No necesitas ejecutar un instalador ni descargar ese modelo por separado.

1. Descarga el ZIP de esta rama o clona el repositorio.
2. Abre `godot/project.godot` con Godot 4.
3. Espera a que Godot importe los recursos y ejecuta el proyecto.

La licencia y procedencia del modelo están en [LICENCIA-MODELO.txt](characters/LICENCIA-MODELO.txt). El modelo es estilizado/low-poly, no fotorrealista, y no incluye animaciones; si el modelo no contiene clips compatibles, el juego conserva sus animaciones procedurales.

## Otros modelos opcionales

Los cargadores admiten estos recursos opcionales si se colocan exactamente en estas rutas:

- `models/characters/player_arm.glb`
- `models/characters/enemy_slime.glb`
- `models/environment/tree_oak.glb`
- `models/environment/medieval_house.glb`

Fuentes de recursos gratuitos:
- [Universal Base Characters — CC0](https://quaternius.com/packs/universalbasecharacters.html)
- [Medieval Village MegaKit — CC0](https://quaternius.com/packs/medievalvillagemegakit.html)
- [Universal Animation Library](https://quaternius.itch.io/universal-animation-library)

## Meta Quest 3S: antes de publicar

El modelo incluido es un primer recurso real; el resto del elenco y del entorno aún puede usar las mallas procedurales existentes. Abre el proyecto en Godot 4, comprueba errores de importación y exportación Android/OpenXR, y prueba escala, colisiones, animaciones, controles y rendimiento en el visor real. No se ha certificado el proyecto en hardware Quest 3S.
