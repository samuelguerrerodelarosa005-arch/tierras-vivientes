# Tierras Vivas - instala la IA local (gratis, todo en tu PC, sin APIs de pago).
# Descarga unos 3,5 GB: cerebro (llama.cpp + Qwen3 4B), oido (whisper.cpp) y voces (Piper).
# Se puede volver a ejecutar: lo que ya esta descargado no se baja otra vez.

$ErrorActionPreference = "Continue"   # los errores se miran a mano (codigos de salida)
$ProgressPreference = "SilentlyContinue"
$IA = $PSScriptRoot
$TMP = Join-Path $IA "_descargas"
New-Item -ItemType Directory -Force -Path $TMP, (Join-Path $IA "modelos"), (Join-Path $IA "voces") | Out-Null

function Paso($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Bajar($urls, $dest) {
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 100000)) { Write-Host "   ya estaba: $(Split-Path $dest -Leaf)"; return $true }
    foreach ($u in @($urls)) {
        Write-Host "   bajando $(Split-Path $u -Leaf) ..."
        & curl.exe -L --fail --retry 3 -C - -o "$dest.part" $u
        if ($LASTEXITCODE -eq 0) { Move-Item -Force "$dest.part" $dest; return $true }
        Remove-Item -Force -ErrorAction SilentlyContinue "$dest.part"
    }
    Write-Host "   NO SE PUDO BAJAR: $(Split-Path $dest -Leaf)" -ForegroundColor Red
    return $false
}
function Descomprimir($zip, $dest, $sub) {
    $x = Join-Path $TMP ("x_" + [IO.Path]::GetFileNameWithoutExtension($zip))
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $x
    Expand-Archive -Force $zip $x
    $from = if ($sub) { Join-Path $x $sub } else { $x }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Recurse -Force (Join-Path $from "*") $dest
    Remove-Item -Recurse -Force $x
}

$LLAMA = "https://github.com/ggml-org/llama.cpp/releases/download/b11912/llama-b11912-bin-win-vulkan-x64.zip"
$WH_GPU = "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.4/whisper-cublas-12.4.0-bin-x64.zip"
$WH_CPU = "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.4/whisper-bin-x64.zip"
$PIPER = "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip"
$HF = "https://huggingface.co"
$LLM_URLS = @(
    "$HF/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
    "$HF/bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
    "$HF/lmstudio-community/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
    "$HF/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")
$VOCES = @(
    "es/es_ES/davefx/medium/es_ES-davefx-medium",
    "es/es_ES/sharvard/medium/es_ES-sharvard-medium",
    "es/es_MX/ald/medium/es_MX-ald-medium",
    "es/es_AR/daniela/high/es_AR-daniela-high")

Write-Host "Tierras Vivas - IA local" -ForegroundColor Green
Write-Host "Se instala en: $IA"

Paso "1/5 Cerebro (llama.cpp, tarjeta grafica por Vulkan)"
if (-not (Test-Path (Join-Path $IA "llama\llama-server.exe"))) {
    $z = Join-Path $TMP "llama.zip"
    if (Bajar $LLAMA $z) { Descomprimir $z (Join-Path $IA "llama") $null }
} else { Write-Host "   ya estaba" }

Paso "2/5 Oido (whisper.cpp: con tarjeta NVIDIA y version de procesador)"
if (-not (Test-Path (Join-Path $IA "whisper\whisper-server.exe"))) {
    $z = Join-Path $TMP "whisper-gpu.zip"
    if (Bajar $WH_GPU $z) { Descomprimir $z (Join-Path $IA "whisper") "Release" }
} else { Write-Host "   ya estaba (GPU)" }
if (-not (Test-Path (Join-Path $IA "whisper-cpu\whisper-server.exe"))) {
    $z = Join-Path $TMP "whisper-cpu.zip"
    if (Bajar $WH_CPU $z) { Descomprimir $z (Join-Path $IA "whisper-cpu") "Release" }
} else { Write-Host "   ya estaba (procesador)" }

Paso "3/5 Voces (Piper)"
if (-not (Test-Path (Join-Path $IA "piper\piper.exe"))) {
    $z = Join-Path $TMP "piper.zip"
    if (Bajar $PIPER $z) { Descomprimir $z $IA $null }
} else { Write-Host "   ya estaba" }
foreach ($v in $VOCES) {
    $n = Split-Path $v -Leaf
    [void](Bajar "$HF/rhasspy/piper-voices/resolve/main/$v.onnx" (Join-Path $IA "voces\$n.onnx"))
    [void](Bajar "$HF/rhasspy/piper-voices/resolve/main/$v.onnx.json" (Join-Path $IA "voces\$n.onnx.json"))
}

Paso "4/5 Modelos (unos 3 GB, puede tardar)"
$llm = Join-Path $IA "modelos\cerebro-qwen3-4b.gguf"
$okLLM = Bajar $LLM_URLS $llm
$okW = Bajar "$HF/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin" (Join-Path $IA "modelos\ggml-large-v3-turbo-q5_0.bin")
$okWs = Bajar "$HF/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin" (Join-Path $IA "modelos\ggml-small-q5_1.bin")

Paso "5/5 Prueba (la primera vez la tarjeta grafica prepara sus programas: 1 a 5 minutos)"
$env:CUDA_CACHE_MAXSIZE = "4294967296"
$wav = Join-Path $TMP "prueba.wav"
$sttCpu = $false
$voz = Get-ChildItem (Join-Path $IA "voces") -Filter *.onnx | Select-Object -First 1
if ($voz -and (Test-Path (Join-Path $IA "piper\piper.exe"))) {
    "Hola, Bruno. Tienes trabajo para mi." | & (Join-Path $IA "piper\piper.exe") -m $voz.FullName -f $wav -q
}
$cli = Join-Path $IA "whisper\whisper-cli.exe"
if ((Test-Path $wav) -and (Test-Path $cli) -and $okW) {
    $out = & $cli -m (Join-Path $IA "modelos\ggml-large-v3-turbo-q5_0.bin") -f $wav -l es -nt 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   La tarjeta grafica no pudo con el oido: se usara el procesador (algo mas lento)." -ForegroundColor Yellow
        $sttCpu = $true
    } else { Write-Host "   El oido entendio: $out" -ForegroundColor Green }
} elseif (-not (Test-Path $cli)) { $sttCpu = $true }

$cfg = [ordered]@{
    modo = "local"
    llm_modelo = "modelos/cerebro-qwen3-4b.gguf"
    stt_modelo = "modelos/ggml-large-v3-turbo-q5_0.bin"
    stt_modelo_cpu = "modelos/ggml-small-q5_1.bin"
    stt_cpu = $sttCpu
    contexto = 4096
    capas_gpu = 99
    hilos_voz = 4
}
$cfg | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $IA "config.json")
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TMP

Write-Host ""
if ($okLLM -and ($okW -or $okWs)) {
    Write-Host "Listo. Abre TierrasVivas.exe, acercate a un habitante, mirale y hablale." -ForegroundColor Green
} else {
    Write-Host "Faltan piezas (mira los mensajes en rojo). Vuelve a ejecutar instalar_ia.bat: sigue donde se quedo." -ForegroundColor Yellow
}
Write-Host "Si el micro no funciona: Configuracion de Windows > Privacidad > Microfono > permitir a las aplicaciones de escritorio."
