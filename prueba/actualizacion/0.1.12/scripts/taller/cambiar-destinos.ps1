# Cambiar las carpetas de las copias del taller (Fase 8, Paso 7). Las carpetas se montan en el contenedor de la app,
# por eso no se cambian desde la web: este script pregunta una o dos carpetas (con ventanas), las guarda en el .env
# y vuelve a crear el contenedor de la app con ellas. Las copias que ya estaban en la carpeta anterior se quedan allá.
# Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File cambiar-destinos.ps1 [-Seco [-ConVentanas]] [-Carpeta <instalación>]
param(
    [string]$Carpeta = '',
    [switch]$Seco,
    [switch]$ConVentanas
)
. (Join-Path $PSScriptRoot 'comun.ps1')
Preparar-Comun -Seco:$Seco -ConVentanas:$ConVentanas
if (-not $Carpeta) { $Carpeta = $CarpetaPorDefecto }
$archivoEnv = Join-Path $Carpeta '.env'

if (-not (Test-Path $archivoEnv)) {
    if (-not $Seco) { Mostrar-Mensaje "El taller no está instalado en este equipo (no está $archivoEnv)." 'Error'; exit 1 }
    Decir "No hay instalación en ${Carpeta}: en seco se parte de ninguna carpeta."
}
Iniciar-Registro $Carpeta 'cambiar-destinos'
$valores = Leer-Env $archivoEnv
$antes = @{ Local = [string]$valores['COPIAS_CARPETA_LOCAL']; Nube = [string]$valores['COPIAS_CARPETA_NUBE'] }
Decir "Ahora las copias van a: $(if ($antes.Local) { $antes.Local } else { '(ninguna)' })$(if ($antes.Nube) { " y $($antes.Nube)" })"

$nuevos = Elegir-Destinos $antes.Local $antes.Nube
if (-not $nuevos) { Mostrar-Mensaje 'No se cambió nada.' 'Info'; exit 0 }
if ($nuevos.Local -eq $antes.Local -and $nuevos.Nube -eq $antes.Nube) { Mostrar-Mensaje 'Las carpetas son las mismas: no se cambió nada.' 'Info'; exit 0 }

$texto = "Las copias van a ir a:`n`n    $($nuevos.Local)$(if ($nuevos.Nube) { "`n    $($nuevos.Nube)" })`n`nPara eso se apaga y se vuelve a encender el taller (menos de un minuto). ¿Seguir?"
if (-not (Preguntar-SiNo $texto)) { Mostrar-Mensaje 'No se cambió nada.' 'Info'; exit 0 }

Crear-Carpetas $nuevos
$dc = Argumentos-Compose $Carpeta
if ($Seco) {
    Decir "Cambiaría en el .env: COPIAS_CARPETA_LOCAL=$($nuevos.Local) y COPIAS_CARPETA_NUBE=$($nuevos.Nube)"
    Decir "Volvería a crear la app: docker $($dc -join ' ') up -d app, y esperaría /api/salud."
    exit 0
}

Cambiar-Env $archivoEnv 'COPIAS_CARPETA_LOCAL' $nuevos.Local
Cambiar-Env $archivoEnv 'COPIAS_CARPETA_NUBE' $nuevos.Nube
Abrir-Progreso 'Cambiando las carpetas de las copias…'
if (-not (Encender-Docker 240)) { Cerrar-Progreso; Mostrar-Mensaje "Se guardaron las carpetas, pero Docker no está encendido: se usan al abrir el taller.`n`n$(Explicar-Docker-Apagado)" 'Aviso'; exit 1 }
$r = Correr-Docker ($dc + @('up', '-d', 'app')) 300
$sana = ($r.Codigo -eq 0) -and (Esperar-Salud (Puerto-Equipo $valores) 240)
Cerrar-Progreso
if (-not $sana) {
    Anotar-Estado $Carpeta
    Mostrar-Mensaje "Se guardaron las carpetas, pero el taller no respondió al encender.`n`nEl detalle quedó en $($script:Registro). Avise al técnico." 'Error'
    exit 1
}
Mostrar-Mensaje "Listo: las copias van ahora a las carpetas nuevas. Las copias que ya estaban en la carpeta anterior se quedan allá.`n`nRevise en «Copias» que las carpetas salgan disponibles." 'Info'
exit 0
