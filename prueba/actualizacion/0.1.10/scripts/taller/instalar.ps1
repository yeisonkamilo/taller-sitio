# Instalador del taller en el portátil (Fase 8, Paso 7). Se abre con doble clic en instalar.cmd, en la carpeta del
# paquete «instalador» (compose, scripts y las imágenes de docker save). Todo va con ventanas: el dueño no usa la
# consola. Pasos: requisitos -> Docker -> preguntas (carpetas de copias y hora) -> imágenes -> archivos y .env ->
# hoja de la frase -> firewall -> íconos -> encender y abrir el navegador.
# Correrlo otra vez no pisa el .env ni la frase: revisa lo demás. Si ya hay otra versión instalada, ofrece actualizar.
# Uso:  instalar.cmd [-Seco [-ConVentanas]] [-Carpeta <carpeta>] [-LicenciaUrl <https://...>] [-ActualizacionUrl <https://.../ultima.json>]
# -Seco no cambia nada (sin -ConVentanas tampoco muestra ventanas: toma las respuestas propuestas). La instalación
# queda en %LOCALAPPDATA%\Taller salvo -Carpeta. ACTUALIZACION_URL (Fase 10) sale de -ActualizacionUrl o, si no, de
# la que trae paquete.json (empaquetar.ps1 -ActualizacionUrl); vacía = el portátil no busca versiones nuevas.
param(
    [string]$Carpeta = '',
    [string]$LicenciaUrl = '',
    [string]$ActualizacionUrl = '',
    [switch]$Seco,
    [switch]$ConVentanas
)
. (Join-Path $PSScriptRoot 'comun.ps1')
Preparar-Comun -Seco:$Seco -ConVentanas:$ConVentanas
if (-not $Carpeta) { $Carpeta = $CarpetaPorDefecto }
$origen = Raiz-Del-Paquete
$archivoEnv = Join-Path $Carpeta '.env'
$imagenApp = $null

function Fallar([string]$texto) {
    Cerrar-Progreso
    Anotar-Estado $Carpeta
    $detalle = if ($script:Registro) { "`n`nEl detalle quedó en $($script:Registro)." } else { '' }
    Mostrar-Mensaje "$texto$detalle" 'Error'
    exit 1
}

function Memoria-GB {
    $instalada = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    if (-not $instalada) { $instalada = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory }
    return [math]::Round($instalada / 1GB, 1)
}

function Revisar-Requisitos {
    $faltas = @()
    $v = [Environment]::OSVersion.Version
    if (-not [Environment]::Is64BitOperatingSystem -or $v.Major -lt 10 -or $v.Build -lt 19045) {
        $faltas += "Windows 10 versión 22H2 o Windows 11, de 64 bits (este equipo tiene la compilación $($v.Build))."
    }
    $gb = Memoria-GB
    if ($gb -lt 7.5) { $faltas += "8 GB de memoria RAM (este equipo tiene $gb GB)." }
    if (-not (Virtualizacion-Activa)) { $faltas += 'La virtualización encendida: hay que activarla en la BIOS (Intel VT-x o AMD-V).' }
    if (-not (Buscar-DockerDesktop) -or -not $script:Docker) { $faltas += 'Docker Desktop instalado (el técnico trae el instalador).' }
    $libre = Libre-GB "$env:SystemDrive\"
    if ($libre -lt 5) { $faltas += "5 GB libres en el disco $env:SystemDrive (quedan $libre GB)." }
    Anotar "Requisitos: Windows $($v.Build), $gb GB, $libre GB libres en $env:SystemDrive"
    return $faltas
}

function Puerto-Libre([int]$p) { -not (Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) }

function Elegir-Puerto {
    if (-not (Puerto-Libre 3101)) { Fallar 'El puerto 3101 de este equipo está ocupado por otro programa y el taller lo necesita.' }
    if (Puerto-Libre 80) { return 80 }
    if (Puerto-Libre 3100) {
        Mostrar-Mensaje "El puerto 80 está ocupado por otro programa: los celulares entrarán con :3100 al final de la dirección." 'Aviso'
        return 3100
    }
    Fallar 'Los puertos 80 y 3100 de este equipo están ocupados por otros programas.'
}

function Pedir-Hora {
    $texto = "¿A qué hora se hace la copia diaria de la base?`n`nEscriba la hora como HH:MM de 24 horas (13:00 es la 1 de la tarde). Elija una hora en que el portátil suela estar encendido; si está apagado, la copia se hace al encenderlo. Se cambia después en «Copias»."
    for ($i = 0; $i -lt 3; $i++) {
        $hora = (Pedir-Texto $texto '13:00').Trim()
        if (-not $hora) { return '13:00' }
        if ($hora -match '^([01]?[0-9]|2[0-3]):[0-5][0-9]$') { return ('{0:D2}:{1}' -f [int]($hora -split ':')[0], ($hora -split ':')[1]) }
        Mostrar-Mensaje "«$hora» no es una hora válida. Escríbala así: 13:00" 'Aviso'
    }
    return '13:00'
}

# La frase la genera el mismo código del servidor (dominio/copias/frase), dentro de la imagen y sin red.
function Generar-Frase([string]$imagen) {
    $codigo = "process.stdout.write(require('./dist/dominio/copias/frase.js').generarFrase())"
    $r = Correr-Docker @('run', '--rm', '--network', 'none', '--entrypoint', 'node', $imagen, '-e', $codigo) 120 -SinRegistro
    $frase = $r.Salida.Trim()
    if ($r.Codigo -ne 0 -or $frase -notmatch '^([2-9A-HJKMNP-Z]{5}-){5}[2-9A-HJKMNP-Z]{5}$') {
        Fallar 'No se pudo generar la frase de recuperación.'
    }
    return $frase
}

function Html([string]$t) { [System.Net.WebUtility]::HtmlEncode($t) }

# Hoja para imprimir: un archivo temporal que se abre en el navegador y se borra cuando el dueño confirma.
# La frase no sale en la consola, en el registro ni en ningún archivo que quede.
function Imprimir-Hoja([string]$frase, $destinos, [switch]$Ejemplo) {
    $grupos = ($frase -split '-' | ForEach-Object { "<span>$(Html $_)</span>" }) -join ''
    $carpetas = (@($destinos.Local, $destinos.Nube) | Where-Object { $_ } | ForEach-Object { "<li>$(Html $_)</li>" }) -join ''
    $marca = if ($Ejemplo) { '<p class="ejemplo">EJEMPLO DE LA HOJA (instalación en seco): esta frase no sirve para nada.</p>' } else { '' }
    $html = @"
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Frase de recuperación del taller</title>
<style>
body { font-family: "Segoe UI", Arial, sans-serif; max-width: 46em; margin: 2em auto; color: #111; line-height: 1.45; }
h1 { font-size: 1.6em; margin-bottom: .2em; }
.frase { display: flex; flex-wrap: wrap; gap: .6em; margin: 1.2em 0; }
.frase span { font: bold 2em "Consolas", "Courier New", monospace; letter-spacing: .12em; border: 2px solid #111; padding: .25em .45em; }
.aviso { border-left: 6px solid #111; padding: .4em 1em; }
.ejemplo { background: #ffe8a3; padding: .6em; font-weight: bold; }
.boton { font-size: 1.1em; padding: .5em 1.2em; }
@media print { .boton { display: none; } }
</style></head>
<body onload="window.print()">
$marca
<h1>Frase de recuperación de las copias del taller</h1>
<p>Fecha de la instalación: $(Get-Date -Format 'dd/MM/yyyy')</p>
<div class="frase">$grupos</div>
<div class="aviso">
<p><strong>Sin esta frase no se puede leer ninguna copia de la base.</strong> El técnico no la tiene: si se pierde,
las copias no sirven.</p>
<ul>
<li>Guarde esta hoja <strong>fuera del portátil</strong> (en la casa o en un sobre cerrado), no en el cajón del equipo.</li>
<li>No le tome foto ni la mande por WhatsApp o correo: así terminaría en la nube junto a las copias.</li>
<li>Si el portátil se daña o se pierde: se instala el taller en otro equipo y se restaura la última copia con esta frase.</li>
</ul>
</div>
<p>Las copias se guardan en:</p><ul>$carpetas</ul>
<p>Se puede escribir con minúsculas, espacios o guiones; cada grupo trae al final un carácter que avisa si hay un error.</p>
<button class="boton" onclick="window.print()">Imprimir</button>
</body></html>
"@
    $archivo = Join-Path $env:TEMP ("taller-hoja-{0}.html" -f [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($archivo, $html, (New-Object System.Text.UTF8Encoding($true)))
        while ($true) {
            Start-Process $archivo
            $texto = "Se abrió en el navegador la hoja con la frase de recuperación de las copias.`n`nImprímala (si no hay impresora, cópiela a mano en papel, con cuidado) y guárdela fuera del portátil.`n`n¿Ya la tiene en papel?"
            if (Preguntar-SiNo $texto) { break }
            if (-not (Preguntar-SiNo '¿Abrir otra vez la hoja?')) {
                Mostrar-Mensaje "Sin la hoja, si el portátil se daña no se pueden leer las copias.`n`nPara imprimirla después, abra otra vez instalar.cmd: no cambia la frase." 'Aviso'
                break
            }
        }
    }
    finally {
        # El navegador ya la leyó; si no se puede borrar ahora, la borra la próxima instalación.
        Start-Sleep -Seconds 2
        Remove-Item -Force -ErrorAction SilentlyContinue $archivo
    }
}

function Borrar-Hojas-Viejas {
    Get-ChildItem -Path $env:TEMP -Filter 'taller-hoja-*.html' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

# Valores del .env de una instalación nueva (sección «Taller» de .env.example). Claves y secretos al azar.
function Valores-Nuevos([string]$puerto, $destinos, [string]$frase, [string]$version) {
    $v = [ordered]@{}
    $v['TALLER_VERSION'] = $version
    $v['TALLER_PUERTO'] = $puerto
    $v['TALLER_PUERTO_EQUIPO'] = '3101'
    $v['POSTGRES_USER'] = 'taller'
    $v['POSTGRES_PASSWORD'] = Texto-Aleatorio 32
    $v['POSTGRES_DB'] = 'taller'
    $v['TALLER_DB_USUARIO'] = 'taller_app'
    $v['TALLER_DB_CLAVE'] = Texto-Aleatorio 32
    $v['SESION_SECRETO'] = Texto-Aleatorio 64
    $v['COOKIE_SEGURA'] = 'no'
    $v['LICENCIA_URL'] = $LicenciaUrl
    $v['ACTUALIZACION_URL'] = $ActualizacionUrl
    $v['COPIAS_FRASE'] = $frase
    $v['COPIAS_CARPETA_LOCAL'] = $destinos.Local
    $v['COPIAS_CARPETA_NUBE'] = $destinos.Nube
    return $v
}

function Escribir-Env-Nuevo($valores) {
    $lineas = @(
        "# Taller instalado el $(Get-Date -Format 'yyyy-MM-dd HH:mm') por instalar.ps1. Tiene las claves y la frase de las copias:",
        '# no lo copie, no lo mande ni lo suba a la nube. Las carpetas de copias se cambian con cambiar-destinos.ps1.'
    )
    foreach ($k in $valores.Keys) { $lineas += "$k=$(Valor-Env $valores[$k])" }
    New-Item -ItemType File -Force -Path $archivoEnv | Out-Null
    Proteger-Archivo $archivoEnv
    Escribir-Lineas $archivoEnv $lineas
}

# Firewall: entran los celulares solo en redes privadas, y en las públicas el puerto queda bloqueado. Si la red de
# ahora está como pública, pregunta si es la Wi-Fi del taller para marcarla como privada. Necesita permiso de
# administrador (ventana de Windows); lo hace regla-firewall.ps1 aparte para que el resto no corra como administrador.
function Abrir-Firewall([string]$puerto) {
    $regla = Join-Path $Carpeta 'scripts\taller\regla-firewall.ps1'
    $extra = @()
    $publicas = @(Perfiles-Publicos)
    if ($publicas.Count) {
        $texto = "La red «$(($publicas | ForEach-Object { $_.Name }) -join ', ')» está como pública: así los celulares no entran al taller.`n`n¿Es la Wi-Fi del taller? Si dice Sí, Windows la marca como red privada.`n`nSi es la red de un café, un hotel o un aeropuerto, diga No."
        if (Preguntar-SiNo $texto $false) { $extra = @('-Privadas', (($publicas | ForEach-Object { $_.InterfaceIndex }) -join ',')) }
    }
    if ($script:EnSeco) { Decir "Pediría permiso de administrador para: regla-firewall.ps1 -Puerto $puerto $($extra -join ' ') (entrada TCP $puerto en redes privadas, bloqueada en públicas)"; return $true }
    Mostrar-Mensaje "Ahora Windows va a pedir permiso de administrador para dejar entrar a los celulares por la Wi-Fi (puerto $puerto, solo en redes privadas). Responda «Sí»." 'Info'
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList (@(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$regla`"", '-Puerto', $puerto) + $extra)
        Anotar "Firewall: código $($p.ExitCode)"
        return $p.ExitCode -eq 0
    }
    catch {
        Anotar "Firewall: no se dio el permiso ($($_.Exception.Message))"
        return $false
    }
}

function Direccion-Wifi {
    $ip = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { $_ -and $_ -notlike '169.254.*' } | Select-Object -First 1
    return $ip
}

function Perfiles-Publicos {
    Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.NetworkCategory -eq 'Public' -and $_.IPv4Connectivity -ne 'Disconnected' }
}

function Redes-Publicas { Perfiles-Publicos | ForEach-Object { $_.Name } }

# ==== Comienzo ====================================================================================================
Borrar-Hojas-Viejas
$paquete = Leer-Paquete $origen
if ($paquete) {
    $version = $paquete.version
    $imagenApp = ($paquete.imagenes | Where-Object { $_.etiqueta -like 'taller-motos:*' } | Select-Object -First 1).etiqueta
}
elseif ($Seco) {
    $version = (Get-Content (Join-Path $origen 'servidor\package.json') -Raw | ConvertFrom-Json).version
    $imagenApp = "taller-motos:$version"
    Decir "Sin paquete.json (se corre desde el repositorio): en seco se saltan las imágenes; versión $version."
}
else {
    Mostrar-Mensaje "Falta paquete.json en $origen. Use la carpeta «instalador» completa que trajo el técnico." 'Error'
    exit 1
}
if (-not $ActualizacionUrl -and $paquete -and $paquete.actualizacionUrl) { $ActualizacionUrl = [string]$paquete.actualizacionUrl }
if ($ActualizacionUrl -and -not (Url-Actualizacion-Valida $ActualizacionUrl)) {
    Decir "La dirección de actualizaciones «$ActualizacionUrl» no sirve (solo https://…/ultima.json): se deja vacía."
    $ActualizacionUrl = ''
}

$faltas = Revisar-Requisitos
if ($faltas.Count) {
    Mostrar-Mensaje ("Este equipo no cumple lo que necesita el taller:`n`n- " + ($faltas -join "`n- ") + "`n`nNo se instaló nada.") 'Error'
    exit 1
}
Decir 'Requisitos: OK.'

$existe = Test-Path $archivoEnv
$actual = Leer-Env $archivoEnv
if ($existe -and $actual['TALLER_VERSION'] -and $actual['TALLER_VERSION'] -ne $version) {
    if (Preguntar-SiNo "Ya está instalado el taller, versión $($actual['TALLER_VERSION']).`n`n¿Actualizarlo a la versión $version?") {
        & (Join-Path $PSScriptRoot 'actualizar.ps1') -Carpeta $Carpeta -Seco:$Seco -ConVentanas:$ConVentanas
        exit $LASTEXITCODE
    }
    exit 0
}
if (-not $Seco) { New-Item -ItemType Directory -Force -Path $Carpeta | Out-Null }
Iniciar-Registro $Carpeta 'instalar'
if ($existe) { Decir "Ya hay una instalación en ${Carpeta}: se conservan su .env y su frase; se revisa lo demás." }

# --- Preguntas (antes de lo que tarda) ---
if ($existe) {
    $puerto = if ($actual['TALLER_PUERTO']) { $actual['TALLER_PUERTO'] } else { '80' }
    $destinos = @{ Local = $actual['COPIAS_CARPETA_LOCAL']; Nube = $actual['COPIAS_CARPETA_NUBE'] }
    $hora = $null
    $reimprimir = Preguntar-SiNo '¿Quiere imprimir otra vez la hoja con la frase de recuperación?' $false
}
else {
    $puerto = [string](Elegir-Puerto)
    $destinos = Elegir-Destinos
    if (-not $destinos) { Mostrar-Mensaje 'No se eligió carpeta para las copias. No se instaló nada.' 'Aviso'; exit 1 }
    $hora = Pedir-Hora
    $reimprimir = $false
}
Decir "Puerto para los celulares: $puerto. Copias en: $($destinos.Local)$(if ($destinos.Nube) { " y $($destinos.Nube)" })."

# --- Docker e imágenes ---
Abrir-Progreso 'Preparando Docker…'
if (-not (Encender-Docker 300)) {
    if ($Seco) { Decir "En seco: Docker no está listo; se seguiría al encender." }
    else { Fallar "No se pudo seguir con la instalación.`n`n$(Explicar-Docker-Apagado)`n`nSi es la primera vez, abra Docker Desktop y acepte sus condiciones." }
}
if ($paquete) {
    try {
        Verificar-Archivos-Paquete $paquete $origen
        Verificar-Imagenes-Paquete $paquete $origen
        if ($Seco) { Decir "Huellas de los archivos y de las imágenes: OK. Cargaría (si no están ya): $(($paquete.imagenes | ForEach-Object { $_.etiqueta }) -join ', ')" }
        else { Cargar-Imagenes $paquete $origen }
    }
    catch { Fallar $_.Exception.Message }
}

# --- Archivos, .env y frase ---
Cambiar-Progreso 'Copiando los archivos del taller…'
Copiar-Archivos $origen $Carpeta
Crear-Carpetas $destinos
$frase = $null
if (-not $existe) {
    if ($Seco) {
        $frase = 'ABCD8-EFGH2-JKMN5-PQRS7-TUVW3-XYZ24'
        Decir "Escribiría $archivoEnv (solo legible por $env:USERNAME) con claves al azar y la frase generada por $imagenApp."
    }
    else {
        Cambiar-Progreso 'Generando las claves y la frase…'
        $frase = Generar-Frase $imagenApp
        Escribir-Env-Nuevo (Valores-Nuevos $puerto $destinos $frase $version)
        Anotar ".env creado en $archivoEnv"
    }
}
elseif (-not $Seco) {
    # Variables que una versión nueva necesite y este .env no tenga (sin tocar las que están).
    foreach ($k in @('TALLER_PUERTO_EQUIPO', 'COOKIE_SEGURA', 'ACTUALIZACION_URL')) {
        if (-not $actual.ContainsKey($k)) {
            Cambiar-Env $archivoEnv $k (@{ TALLER_PUERTO_EQUIPO = '3101'; COOKIE_SEGURA = 'no'; ACTUALIZACION_URL = $ActualizacionUrl }[$k])
        }
    }
}
Cerrar-Progreso
if (-not $existe -or $reimprimir) {
    $fraseHoja = if ($frase) { $frase } else { $actual['COPIAS_FRASE'] }
    if ($Seco -and -not $ConVentanas) { Decir 'Abriría la hoja para imprimir con la frase (en seco, con -ConVentanas se ve un ejemplo).' }
    else { Imprimir-Hoja $fraseHoja $destinos -Ejemplo:$Seco }
}

# --- Windows: firewall e íconos ---
$firewall = Abrir-Firewall $puerto
Crear-Accesos $Carpeta

# --- Encender ---
$valores = Leer-Env $archivoEnv
$equipo = Puerto-Equipo $valores
$dc = Argumentos-Compose $Carpeta
if ($Seco) {
    Decir "Encendería: docker $($dc -join ' ') up -d, esperaría http://127.0.0.1:$equipo/api/salud y abriría el navegador."
    if ($hora -and $hora -ne '13:00') { Decir "Guardaría la hora de la copia diaria: $hora" }
}
else {
    Abrir-Progreso 'Encendiendo el taller (la primera vez tarda más)…'
    $r = Correr-Docker ($dc + @('up', '-d')) 600
    if ($r.Codigo -ne 0) { Fallar 'No se pudo encender el taller.' }
    Cambiar-Progreso 'Esperando a que el taller responda…'
    if (-not (Esperar-Salud $equipo 300)) { Fallar 'El taller encendió pero no responde.' }
    if ($hora -and $hora -ne '13:00') {
        try { [void](Consultar-Base $Carpeta $valores "UPDATE copia_ajustes SET hora = '$hora' WHERE id = 1") }
        catch { Mostrar-Mensaje "No se pudo guardar la hora de la copia ($hora): cámbiela en «Copias»." 'Aviso' }
    }
    Cerrar-Progreso
}

# --- Final ---
$ip = Direccion-Wifi
$direccion = if ($ip) { "http://$ip$(if ($puerto -ne '80') { ":$puerto" })" } else { '(no se encontró la dirección de la Wi-Fi)' }
$avisos = @()
if (-not $firewall) { $avisos += 'No se dio el permiso del firewall: los celulares no van a entrar hasta correr otra vez instalar.cmd.' }
$publicas = @(Redes-Publicas)
if ($publicas.Count) { $avisos += "La red «$($publicas -join ', ')» está como pública y así los celulares no entran: en Configuración > Red e Internet, elija «Red privada»." }
$final = "Listo: el taller quedó instalado.`n`nEn este portátil: ícono «Taller» del escritorio.`nEn los celulares (misma Wi-Fi): $direccion"
if (-not $existe) { $final += "`n`nEn el navegador que se abre, haga la configuración inicial del taller." }
if ($avisos.Count) { $final += "`n`nOJO:`n- " + ($avisos -join "`n- ") }
if ($Seco) { Decir "Abriría http://127.0.0.1:$equipo/" } else { Start-Process "http://127.0.0.1:$equipo/" }
Mostrar-Mensaje $final $(if ($avisos.Count) { 'Aviso' } else { 'Info' })
exit 0
