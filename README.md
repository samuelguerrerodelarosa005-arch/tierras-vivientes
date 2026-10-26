# Tierras Vivas — prototipo WebXR

Prototipo 3D jugable de un VRMMORPG inspirado en Log Horizon y Overgeared.
Funciona en navegador de PC y en el Meta Quest 3/3S (botón «Entrar en VR»), con mandos o hand tracking.

- `index.html`: el juego completo en un solo archivo (Three.js r149 desde jsDelivr).
- `GDD_Tierras_Vivas.md`: documento de diseño.

## Publicar en Vercel
Importa este repositorio en Vercel como sitio estático: Framework «Other», sin comando de build, carpeta de salida la raíz.

## Versión Godot (PC VR) — la principal

La carpeta `godot/` es el juego en desarrollo: **Godot 4.8 para PC VR** (Meta Link / Air Link y SteamVR), un jugador.
Ábrela con Godot (Importar → `godot/project.godot`) y sigue `godot/README.md`. La versión web de esta carpeta raíz
queda como prototipo antiguo.
