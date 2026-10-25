# Tierras Vivas — prototipo WebXR

Prototipo 3D jugable de un VRMMORPG inspirado en Log Horizon y Overgeared.
Funciona en navegador de PC y en el Meta Quest 3/3S (botón «Entrar en VR»), con mandos o hand tracking.

- `index.html`: el juego completo en un solo archivo (Three.js r149 desde jsDelivr).
- `GDD_Tierras_Vivas.md`: documento de diseño.

## Publicar en Vercel
Importa este repositorio en Vercel como sitio estático: Framework «Other», sin comando de build, carpeta de salida la raíz.

## Versión Godot (PC y app para Quest 3S)

La carpeta `godot/` tiene el mismo juego portado a **Godot 4.8** con OpenXR: primera persona, mandos y hand tracking,
física real y paneles VR clicables. Ábrela con Godot (Importar → `godot/project.godot`) y sigue `godot/README.md`
para probarla en PC, por Quest Link o exportarla como APK al visor.
