# Restaurar una copia de la base en el portátil del taller (Fase 8, Paso 5). Desde la Fase 9 se restaura en la pantalla
# «Copias» del portátil; esto queda de respaldo para cuando la app no arranca (base dañada, actualización fallida).
# Detiene la app, corre la herramienta en un contenedor de la misma imagen (lista las copias de las carpetas, pide la
# frase y escribir RESTAURAR, copia la base actual, restaura a una base nueva y cambia los nombres) y vuelve a encender
# la app también si algo falló: entonces arranca con la base de antes, que no se tocó.
# Uso, en la carpeta del taller:
#   powershell -NoProfile -ExecutionPolicy Bypass -File restaurar.ps1 [-Compose <docker-compose.taller.yml>] [-Seco]
# -Seco muestra los pasos sin correr nada. -Pausa (el ícono «Taller - Restaurar una copia») espera Enter antes de
# cerrar, para que se alcance a leer el resultado.
param(
    [string]$Compose = '',
    [switch]$Seco,
    [switch]$Pausa
)
$ErrorActionPreference = 'Stop'

function Terminar([int]$codigo) {
    if ($Pausa) { [void](Read-Host 'Presione Enter para cerrar esta ventana') }
    exit $codigo
}
trap {
    Write-Host "No se pudo restaurar: $($_.Exception.Message)" -ForegroundColor Red
    Terminar 1
}

function Buscar-Compose([string]$dado) {
    if ($dado) { return (Resolve-Path $dado).Path }
    $candidatos = @(
        (Join-Path $PSScriptRoot 'docker-compose.taller.yml'),
        (Join-Path $PSScriptRoot '..\..\docker-compose.taller.yml')
    )
    foreach ($c in $candidatos) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    if ($Seco) { return 'docker-compose.taller.yml' }
    throw 'No se encontró docker-compose.taller.yml junto a este script. Use -Compose con la ruta.'
}

function Mostrar([string[]]$argumentos) {
    Write-Host ('  docker ' + ($argumentos -join ' ')) -ForegroundColor DarkGray
}

$archivo = Buscar-Compose $Compose
# No se llama $compose: PowerShell no distingue mayúsculas y sería el parámetro [string]$Compose.
$dc = @('compose', '-f', $archivo)
$detener = $dc + @('stop', 'app')
# Al detenerse, la app hace su copia «cierre» con los datos de ahora. La herramienta no la ofrece si sabe cuándo se
# detuvo: la hora sale del reloj de Docker (el mismo que pone la hora en el nombre de la copia), no del de Windows.
$reloj = $dc + @('exec', '-T', 'db', 'date', '+%s')
function Restaurar-Con([string]$detenida) {
    $variable = if ($detenida) { @('-e', "RESTAURAR_DETENIDA=$detenida") } else { @() }
    return $dc + @('run', '--rm', '--no-deps', '-it') + $variable + @('app', 'node', 'dist/herramientas/restaurar.js')
}
$restaurar = Restaurar-Con '<hora de Docker>'
$encender = $dc + @('up', '-d', 'app')

if ($Seco) {
    Write-Host 'En seco: estos son los pasos, no se corre nada.'
    Write-Host '1. Leer la hora de Docker y detener la aplicación (la base sigue encendida):'; Mostrar $reloj; Mostrar $detener
    Write-Host '2. Restaurar (pide la copia, la frase y escribir RESTAURAR):'; Mostrar $restaurar
    Write-Host '3. Encender la aplicación, haya salido bien o no:'; Mostrar $encender
    exit 0
}

& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Docker Desktop no está encendido. Ábralo, espere a que diga que está listo y vuelva a correr esto.' -ForegroundColor Red
    Terminar 1
}

$detenida = ''
try { $detenida = ((& docker @reloj) | Out-String).Trim() } catch { $detenida = '' }
if ($LASTEXITCODE -ne 0 -or $detenida -notmatch '^\d+$') {
    Write-Host 'Aviso: no se leyó la hora de Docker; la lista puede mostrar de primera la copia que hace la app al detenerse.' -ForegroundColor Yellow
    $detenida = ''
}
$restaurar = Restaurar-Con $detenida

Write-Host '1. Deteniendo la aplicación (la base sigue encendida)...'
& docker @detener
if ($LASTEXITCODE -ne 0) {
    Write-Host 'No se pudo detener la aplicación. No se tocó nada.' -ForegroundColor Red
    Terminar 1
}

$codigo = 1
try {
    Write-Host '2. Restaurar una copia:'
    & docker @restaurar
    $codigo = $LASTEXITCODE
}
finally {
    Write-Host '3. Encendiendo la aplicación...'
    & docker @encender
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'La aplicación no encendió. Use el ícono «Taller» o avise al técnico.' -ForegroundColor Red
    }
}

if ($codigo -eq 0) {
    Write-Host 'Restauración terminada. Abra el taller y revise que estén los datos de la copia.' -ForegroundColor Green
}
else {
    Write-Host 'No se restauró: la aplicación sigue con la base de antes.' -ForegroundColor Yellow
}
Terminar $codigo
