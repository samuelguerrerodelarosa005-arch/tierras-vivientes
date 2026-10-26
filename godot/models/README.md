# Modelos 3D incluidos — Tierras Vivientes

Los siguientes recursos ya vienen dentro del proyecto. No hace falta descargar paquetes ni ejecutar instaladores adicionales.

| Recurso | Archivo | Uso |
|---|---|---|
| Habitante humanoide | `characters/villager.glb` | Modelo riggeado estilizado basado en Quaternius Universal Base Characters |
| Enemigo limo | `characters/enemy_slime.tscn` | Malla 3D con cuerpo gelatinoso y ojos |
| Brazos del jugador | `characters/player_arm.tscn` | Mangas y manos para vista en primera persona |
| Árbol | `environment/tree_oak.tscn` | Tronco y copas low-poly |
| Casa medieval | `environment/medieval_house.tscn` | Paredes, tejado, puerta y ventanas |

## Importar y ejecutar

1. Descarga el ZIP de la rama `visual-realista-quest3s` y descomprímelo.
2. Abre `godot/project.godot` en Godot 4.
3. Espera a que Godot importe los recursos y pulsa F5.

Las escenas `.tscn` usan mallas y materiales nativos de Godot, por lo que no necesitan archivos de textura o dependencias externas. Son modelos low-poly estilizados, no fotorrealistas, y están pensados como una base ligera para VR. Las animaciones del juego siguen siendo procedurales donde el modelo no aporta clips.

## Licencia del humanoide

El humanoide proviene de Quaternius Universal Base Characters, distribuido en el repositorio público programasweights/avatar. La fuente declara licencia CC0 1.0. Consulta [LICENCIA-MODELO.txt](characters/LICENCIA-MODELO.txt) y la [licencia CC0](https://creativecommons.org/publicdomain/zero/1.0/).

## Verificación de Quest 3S

Los recursos están incluidos en el repositorio, pero aún hay que abrir el proyecto en Godot, revisar errores de importación y ejecutar la prueba automática. La compatibilidad final, la escala en VR, las colisiones, la exportación Android/OpenXR y el rendimiento deben comprobarse en un Meta Quest 3S real antes de darlo por terminado.
