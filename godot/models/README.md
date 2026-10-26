# Modelos 3D y Meta Quest 3S

## Instalación de un modelo humanoide real

Desde la carpeta raíz del repositorio, abre PowerShell y ejecuta:

```powershell
.\godot\tools\install_3d_assets.ps1
```

El script descarga el modelo humanoide **Superhero Male** del pack Universal Base Characters de Quaternius (licencia CC0 1.0) y lo guarda como `godot/models/characters/villager.glb`. La fuente de descarga y la licencia están documentadas en [el repositorio de origen](https://github.com/programasweights/avatar/blob/main/public/assets/ASSETS.md).

Este modelo es un personaje estilizado riggeado, no fotorrealista. El archivo publicado en la fuente no incluye animaciones; el juego mantiene su animación procedural si no encuentra clips. El script requiere conexión a Internet y PowerShell.

## Otros modelos

Los cargadores del juego aceptan estos archivos opcionales:

- `models/characters/player_arm.glb`
- `models/characters/enemy_slime.glb`
- `models/environment/tree_oak.glb`
- `models/environment/medieval_house.glb`

Para completar esos elementos, descarga los packs desde las fuentes oficiales y conserva las licencias:
- [Universal Base Characters — CC0](https://quaternius.com/packs/universalbasecharacters.html)
- [Medieval Village MegaKit — CC0](https://quaternius.com/packs/medievalvillagemegakit.html)
- [Universal Animation Library](https://quaternius.itch.io/universal-animation-library)

Son modelos estilizados/low-poly, no fotorrealistas. Los packs completos de entorno pueden ser grandes; importa solo los recursos usados y reduce texturas, materiales y polígonos para Quest 3S.

## Validación pendiente

La descarga de un modelo no prueba que todo el juego compile ni que funcione en el visor. Abre `godot/project.godot` en Godot, espera a que importe el GLB, ejecuta la prueba automática descrita en `README.md` y prueba controles, escala, colisiones, animaciones y rendimiento en un Meta Quest 3S real.
