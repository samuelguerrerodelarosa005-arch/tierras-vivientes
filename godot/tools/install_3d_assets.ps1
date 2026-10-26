# Descarga un personaje humanoide CC0 y lo instala como modelo base de habitantes.
# Ejecutar desde PowerShell: .\godot\tools\install_3d_assets.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$characters = Join-Path $root "models\characters"
New-Item -ItemType Directory -Force -Path $characters | Out-Null

# Modelo Superhero Male de Quaternius Universal Base Characters (CC0 1.0).
# Fuente del archivo y licencia documentadas en ASSETS.md del repositorio original.
$modelUrl = "https://raw.githubusercontent.com/programasweights/avatar/main/public/assets/character.glb"
$licenseUrl = "https://raw.githubusercontent.com/programasweights/avatar/main/public/assets/QUATERNIUS-LICENSE.txt"
$modelPath = Join-Path $characters "villager.glb"
$licensePath = Join-Path $characters "QUATERNIUS-LICENSE.txt"

Write-Host "Descargando personaje humanoide CC0..."
Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath
if ((Get-Item $modelPath).Length -lt 10000) {
    Remove-Item $modelPath -Force
    throw "El archivo GLB descargado parece incompleto."
}
try {
    Invoke-WebRequest -Uri $licenseUrl -OutFile $licensePath
} catch {
    Write-Warning "No se pudo copiar el texto de licencia. Consúltalo en https://github.com/programasweights/avatar/blob/main/ASSETS.md"
}
Write-Host "Modelo instalado en: $modelPath"
Write-Host "Nota: este personaje base no incluye animaciones. El juego conservará las animaciones procedurales cuando no haya clips importados."
Write-Host "Para casas, árboles y enemigos, consulta godot/models/README.md; los packs completos deben descargarse de sus fuentes oficiales."
