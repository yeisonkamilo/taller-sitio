# Funciones comunes de los scripts del taller (Fase 8, Paso 7): ventanas en español, registro, .env, Docker y salud
# de la app. Cada script la carga con:  . (Join-Path $PSScriptRoot 'comun.ps1')
# Nada de aquí muestra ni escribe en el registro las claves ni la frase: las salidas de Docker que podrían llevarlas
# se corren con -SinRegistro.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

$script:CarpetaPorDefecto = Join-Path $env:LOCALAPPDATA 'Taller'
$script:Titulo = 'Taller'
$script:EnSeco = $false
$script:SinVentanas = $false
$script:Registro = $null
$script:Progreso = $null
$script:Dueno = $null
$script:Docker = $null
# Lo que se copia del paquete a la carpeta de la instalación (empaquetar.ps1 se queda en el equipo del desarrollador).
$script:ArchivosInstalados = @('docker-compose.taller.yml', 'scripts\taller')

# -Seco: no cambia nada. Sin -ConVentanas, en seco las preguntas toman la respuesta propuesta y se escriben aquí.
function Preparar-Comun([switch]$Seco, [switch]$ConVentanas) {
    $script:EnSeco = [bool]$Seco
    $script:SinVentanas = [bool]$Seco -and -not $ConVentanas
    $script:Docker = Buscar-Docker
    if ($Seco) { Write-Host 'EN SECO: no se cambia nada; se muestra lo que se haría.' -ForegroundColor Cyan }
}

function Raiz-Del-Paquete { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

# --- Registro --------------------------------------------------------------------------------------------------

function Iniciar-Registro([string]$carpeta, [string]$nombre) {
    if ($script:EnSeco) { return }
    $dir = Join-Path $carpeta 'registro'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:Registro = Join-Path $dir "$nombre.log"
    if ((Test-Path $script:Registro) -and (Get-Item $script:Registro).Length -gt 1MB) {
        Move-Item -Force $script:Registro "$($script:Registro).anterior"
    }
    Anotar "==== $nombre $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}

function Anotar([string]$texto) {
    if ($script:Registro) {
        Add-Content -Path $script:Registro -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $texto) -Encoding UTF8
    }
}

function Decir([string]$texto) {
    Write-Host $texto
    Anotar $texto
}

# --- Ventanas --------------------------------------------------------------------------------------------------

# Dueño invisible y siempre encima: sin él, desde un script sin consola las ventanas pueden quedar detrás de otras.
function Ventana-Duena {
    if (-not $script:Dueno) {
        $script:Dueno = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
    }
    return $script:Dueno
}

function Mostrar-Mensaje([string]$texto, [string]$tipo = 'Info') {
    Anotar "MENSAJE ($tipo): $($texto -replace "`r?`n", ' ')"
    if ($script:SinVentanas) {
        $color = @{ Error = 'Red'; Aviso = 'Yellow'; Info = 'Green' }[$tipo]
        Write-Host "[$tipo] $texto" -ForegroundColor $color
        return
    }
    $icono = @{ Error = 'Error'; Aviso = 'Warning'; Info = 'Information' }[$tipo]
    [void][System.Windows.Forms.MessageBox]::Show((Ventana-Duena), $texto, $script:Titulo, 'OK', $icono)
}

function Preguntar-SiNo([string]$texto, [bool]$porDefecto = $true) {
    if ($script:SinVentanas) {
        Write-Host "[Pregunta] $texto" -ForegroundColor Cyan
        Write-Host ('  -> en seco se toma «{0}»' -f $(if ($porDefecto) { 'Sí' } else { 'No' })) -ForegroundColor Cyan
        return $porDefecto
    }
    $boton = if ($porDefecto) { 'Button1' } else { 'Button2' }
    $r = [System.Windows.Forms.MessageBox]::Show((Ventana-Duena), $texto, $script:Titulo, 'YesNo', 'Question', $boton)
    Anotar ("PREGUNTA: {0} -> {1}" -f ($texto -replace "`r?`n", ' '), $r)
    return $r -eq 'Yes'
}

function Pedir-Texto([string]$texto, [string]$propuesta) {
    if ($script:SinVentanas) {
        Write-Host "[Pregunta] $texto -> en seco se toma «$propuesta»" -ForegroundColor Cyan
        return $propuesta
    }
    return [Microsoft.VisualBasic.Interaction]::InputBox($texto, $script:Titulo, $propuesta)
}

# Devuelve la carpeta elegida o '' si el dueño cancela.
function Elegir-Carpeta([string]$descripcion, [string]$propuesta) {
    if ($script:SinVentanas) {
        Write-Host "[Carpeta] $descripcion -> en seco se toma «$propuesta»" -ForegroundColor Cyan
        return $propuesta
    }
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = $descripcion
    $d.ShowNewFolderButton = $true
    if ($propuesta -and (Test-Path $propuesta)) { $d.SelectedPath = $propuesta }
    if ($d.ShowDialog((Ventana-Duena)) -eq 'OK') { return $d.SelectedPath }
    return ''
}

# Ventanita «Abriendo el taller…» con barra en movimiento. Las esperas largas llaman a DoEvents para que no se congele.
function Abrir-Progreso([string]$texto) {
    Anotar $texto
    if ($script:SinVentanas) { Write-Host $texto; return }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $script:Titulo
    $f.FormBorderStyle = 'FixedDialog'
    $f.ControlBox = $false
    $f.StartPosition = 'CenterScreen'
    $f.TopMost = $true
    $f.ClientSize = New-Object System.Drawing.Size(440, 120)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $texto
    $l.Font = New-Object System.Drawing.Font('Segoe UI', 13)
    $l.TextAlign = 'MiddleCenter'
    $l.SetBounds(10, 10, 420, 60)
    $b = New-Object System.Windows.Forms.ProgressBar
    $b.Style = 'Marquee'
    $b.MarqueeAnimationSpeed = 30
    $b.SetBounds(40, 80, 360, 18)
    $f.Controls.AddRange(@($l, $b))
    $f.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $script:Progreso = @{ Ventana = $f; Texto = $l }
}

function Cambiar-Progreso([string]$texto) {
    Anotar $texto
    if ($script:Progreso) {
        $script:Progreso.Texto.Text = $texto
        [System.Windows.Forms.Application]::DoEvents()
    }
    else { Write-Host $texto }
}

function Cerrar-Progreso {
    if ($script:Progreso) {
        $script:Progreso.Ventana.Close()
        $script:Progreso.Ventana.Dispose()
        $script:Progreso = $null
    }
}

function Esperar([int]$segundos) {
    $fin = (Get-Date).AddSeconds($segundos)
    while ((Get-Date) -lt $fin) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
}

# --- Programas -------------------------------------------------------------------------------------------------

# Un argumento con espacios o comillas va entre comillas, con las reglas de Windows para las barras invertidas.
function Citar([string]$a) {
    if ($a -and $a -notmatch '[\s"]') { return $a }
    $b = New-Object System.Text.StringBuilder
    [void]$b.Append('"')
    $barras = 0
    foreach ($c in $a.ToCharArray()) {
        if ($c -eq '\') { $barras++; continue }
        if ($c -eq '"') { [void]$b.Append('\' * ($barras * 2 + 1)) }
        else { [void]$b.Append('\' * $barras) }
        [void]$b.Append($c)
        $barras = 0
    }
    [void]$b.Append('\' * ($barras * 2))
    [void]$b.Append('"')
    return $b.ToString()
}

# Corre un programa sin ventana, con tiempo máximo, sin congelar las ventanas. -Entorno pasa variables solo a ese
# proceso (así una clave no va en los argumentos). -SinRegistro: la salida puede llevar secretos y no se anota.
# -Entrada: bytes que se le escriben por la entrada estándar (en .NET Framework no hay StandardInputEncoding).
function Correr([string]$exe, [string[]]$argumentos, [int]$tiempo = 120, [hashtable]$Entorno = @{}, [switch]$SinRegistro,
    [byte[]]$Entrada = $null) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = (($argumentos | ForEach-Object { Citar $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $null -ne $Entrada
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    foreach ($k in $Entorno.Keys) { $psi.EnvironmentVariables[$k] = [string]$Entorno[$k] }
    # .NET Framework abre la entrada con Console.InputEncoding y, si es UTF-8 con BOM, antepone EF BB BF: por un momento
    # se pone UTF-8 sin BOM (sin consola, el cambio falla y no hace falta).
    $codificacionAntes = $null
    if ($null -ne $Entrada) {
        try {
            if ([Console]::InputEncoding.GetPreamble().Length) {
                $codificacionAntes = [Console]::InputEncoding
                [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
            }
        }
        catch { }
    }
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    finally { if ($codificacionAntes) { try { [Console]::InputEncoding = $codificacionAntes } catch { } } }
    $salida = $p.StandardOutput.ReadToEndAsync()
    $errores = $p.StandardError.ReadToEndAsync()
    if ($null -ne $Entrada) {
        try {
            $p.StandardInput.BaseStream.Write($Entrada, 0, $Entrada.Length)
            $p.StandardInput.BaseStream.Flush()
        }
        catch { Anotar "No se pudo escribir la entrada de $([System.IO.Path]::GetFileName($exe)): $($_.Exception.Message)" }
        finally { try { $p.StandardInput.Close() } catch { } }
    }
    $fin = (Get-Date).AddSeconds($tiempo)
    $agotado = $false
    while (-not $p.HasExited) {
        if ((Get-Date) -gt $fin) {
            $agotado = $true
            try { $p.Kill() } catch { }
            break
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
    }
    $p.WaitForExit()
    $codigo = if ($agotado) { -1 } else { $p.ExitCode }
    $r = [pscustomobject]@{ Codigo = $codigo; Salida = $salida.Result; Error = $errores.Result; Agotado = $agotado }
    $nombre = [System.IO.Path]::GetFileNameWithoutExtension($exe)
    if ($SinRegistro) {
        Anotar "> $nombre $($argumentos[0]) ... => $codigo (salida sin anotar)"
    }
    else {
        Anotar "> $nombre $($argumentos -join ' ') => $codigo$(if ($agotado) { ' (tiempo agotado)' })"
        foreach ($t in @($r.Salida, $r.Error)) {
            if ($t -and $t.Trim()) { ($t.Trim() -split "`r?`n" | Select-Object -Last 40) | ForEach-Object { Anotar "    $_" } }
        }
    }
    return $r
}

function Ultima-Linea([string]$texto) {
    $l = @(($texto -split "`r?`n") | Where-Object { $_.Trim() })
    if ($l.Count) { return $l[-1].Trim() }
    return ''
}

# --- Docker ----------------------------------------------------------------------------------------------------

function Buscar-Docker {
    $c = Get-Command docker.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'
    if (Test-Path $p) { return $p }
    return $null
}

function Buscar-DockerDesktop {
    $p = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $p) { return $p }
    return $null
}

function Correr-Docker([string[]]$argumentos, [int]$tiempo = 120, [hashtable]$Entorno = @{}, [switch]$SinRegistro,
    [byte[]]$Entrada = $null) {
    if (-not $script:Docker) { throw 'No se encontró el programa docker. ¿Está instalado Docker Desktop?' }
    return Correr $script:Docker $argumentos $tiempo -Entorno $Entorno -SinRegistro:$SinRegistro -Entrada $Entrada
}

function Docker-Listo {
    if (-not $script:Docker) { return $false }
    return (Correr-Docker @('info', '--format', '{{.ServerVersion}}') 30 -SinRegistro).Codigo -eq 0
}

# Con un hipervisor ya corriendo (WSL2), Windows dice que la virtualización del procesador está apagada: por eso se
# mira primero si hay hipervisor.
function Virtualizacion-Activa {
    if ((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) { return $true }
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    return [bool]$cpu.VirtualizationFirmwareEnabled
}

# Enciende Docker Desktop si hace falta y espera a que responda. $true si quedó listo.
function Encender-Docker([int]$tiempo = 240) {
    if (Docker-Listo) { return $true }
    $exe = Buscar-DockerDesktop
    if (-not $exe -or -not $script:Docker) { return $false }
    if ($script:EnSeco) {
        Decir "Docker Desktop está apagado: se abriría «$exe» y se esperaría hasta $tiempo s."
        return $false
    }
    Anotar 'Docker Desktop apagado: se abre.'
    if (-not (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)) { Start-Process -FilePath $exe }
    $fin = (Get-Date).AddSeconds($tiempo)
    while ((Get-Date) -lt $fin) {
        Esperar 5
        if (Docker-Listo) { return $true }
    }
    return $false
}

function Explicar-Docker-Apagado {
    if (-not (Buscar-DockerDesktop) -or -not $script:Docker) { return 'Docker Desktop no está instalado en este equipo.' }
    if (-not (Virtualizacion-Activa)) {
        return 'La virtualización del equipo está apagada. Hay que activarla en la BIOS (Intel VT-x o AMD-V); el técnico sabe cómo.'
    }
    return 'Docker Desktop no terminó de encender. Espere un momento y vuelva a intentarlo; si sigue igual, reinicie el portátil.'
}

function Argumentos-Compose([string]$carpeta) { @('compose', '-f', (Join-Path $carpeta 'docker-compose.taller.yml')) }

# Etiqueta de postgres del compose (p. ej. 18.6-alpine) y su versión mayor.
function Etiqueta-Postgres([string]$compose) {
    $m = [regex]::Match((Get-Content $compose -Raw), '(?m)^\s*image:\s*postgres:(\S+)')
    if (-not $m.Success) { throw "No se encontró la imagen de postgres en $compose." }
    return $m.Groups[1].Value
}

function Mayor-Postgres([string]$etiqueta) { [int]($etiqueta -split '[.-]')[0] }

# Volumen de los datos de la base en el compose (datos-pg<mayor>): cada versión mayor usa uno propio.
function Clave-Volumen-Base([string]$compose) {
    $m = [regex]::Match((Get-Content $compose -Raw), '(?m)^\s*-\s*([\w.-]+):/var/lib/postgresql\s*$')
    if (-not $m.Success) { throw "No se encontró el volumen de la base en $compose." }
    return $m.Groups[1].Value
}

# Nombre del proyecto de compose: COMPOSE_PROJECT_NAME del .env (pruebas) o «name:» del compose.
function Nombre-Proyecto([hashtable]$valores, [string]$compose) {
    if ($valores['COMPOSE_PROJECT_NAME']) { return $valores['COMPOSE_PROJECT_NAME'] }
    $m = [regex]::Match((Get-Content $compose -Raw), '(?m)^name:\s*(\S+)')
    if ($m.Success) { return $m.Groups[1].Value }
    throw "El compose $compose no dice su nombre de proyecto."
}

# Consulta en la base del taller como superusuario, por el socket del contenedor db (no necesita clave).
function Consultar-Base([string]$carpeta, [hashtable]$valores, [string]$sql) {
    $a = (Argumentos-Compose $carpeta) + @('exec', '-T', 'db', 'psql', '-U', $valores['POSTGRES_USER'], '-d',
        $valores['POSTGRES_DB'], '-tAX', '-v', 'ON_ERROR_STOP=1', '-c', $sql)
    $r = Correr-Docker $a 60
    if ($r.Codigo -ne 0) { throw "La base no respondió: $(Ultima-Linea $r.Error)" }
    return $r.Salida.Trim()
}

# --- La app ----------------------------------------------------------------------------------------------------

function Puerto-Equipo([hashtable]$valores) {
    if ($valores['TALLER_PUERTO_EQUIPO']) { return [int]$valores['TALLER_PUERTO_EQUIPO'] }
    return 3101
}

# /api/salud por el puerto del equipo (solo 127.0.0.1), sin proxy.
function App-Sana([int]$puerto) {
    try {
        $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$puerto/api/salud")
        $req.Proxy = $null
        $req.Timeout = 3000
        $resp = $req.GetResponse()
        $ok = [int]$resp.StatusCode -eq 200
        $resp.Close()
        return $ok
    }
    catch { return $false }
}

function Esperar-Salud([int]$puerto, [int]$tiempo) {
    $fin = (Get-Date).AddSeconds($tiempo)
    while ((Get-Date) -lt $fin) {
        if (App-Sana $puerto) { return $true }
        Esperar 3
    }
    return $false
}

# Deja en el registro el estado de los contenedores y las últimas líneas de cada uno, para el técnico.
function Anotar-Estado([string]$carpeta) {
    if (-not $script:Registro -or -not $script:Docker) { return }
    $dc = Argumentos-Compose $carpeta
    [void](Correr-Docker ($dc + @('ps', '-a')) 30)
    [void](Correr-Docker ($dc + @('logs', '--no-color', '--tail', '60', 'app', 'db')) 30)
}

# --- .env ------------------------------------------------------------------------------------------------------

function Leer-Env([string]$archivo) {
    $v = @{}
    if (-not (Test-Path $archivo)) { return $v }
    foreach ($linea in [System.IO.File]::ReadAllLines($archivo)) {
        if ($linea -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
            $clave = $Matches[1]
            $valor = $Matches[2].Trim()
            if ($valor -match "^'(.*)'$" -or $valor -match '^"(.*)"$') { $valor = $Matches[1] }
            $v[$clave] = $valor
        }
    }
    return $v
}

# Valor como lo lee docker compose: entre comillas simples si no es solo letras, números y - _ . : (rutas).
function Valor-Env([string]$valor) {
    if ($valor -match '^[A-Za-z0-9_.:-]*$') { return $valor }
    if ($valor.Contains("'")) { throw 'Un valor del .env no puede llevar comillas simples.' }
    return "'$valor'"
}

# UTF-8 sin BOM: con BOM docker compose leería mal la primera variable.
function Escribir-Lineas([string]$archivo, [string[]]$lineas) {
    [System.IO.File]::WriteAllLines($archivo, $lineas, (New-Object System.Text.UTF8Encoding($false)))
}

# Cambia o agrega una variable sin tocar el resto del archivo.
function Cambiar-Env([string]$archivo, [string]$clave, [string]$valor) {
    $lineas = [System.Collections.Generic.List[string]]::new()
    $hecho = $false
    foreach ($l in [System.IO.File]::ReadAllLines($archivo)) {
        if ($l -match "^\s*$clave\s*=") {
            if (-not $hecho) { $lineas.Add("$clave=$(Valor-Env $valor)") }
            $hecho = $true
        }
        else { $lineas.Add($l) }
    }
    if (-not $hecho) { $lineas.Add("$clave=$(Valor-Env $valor)") }
    Escribir-Lineas $archivo $lineas.ToArray()
}

# Solo el usuario de Windows que instaló (y el sistema) pueden leer el archivo: tiene las claves y la frase.
function Proteger-Archivo([string]$ruta) {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $yo = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $sistema = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    foreach ($quien in @($yo, $sistema)) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($quien, 'FullControl', 'Allow')))
    }
    (Get-Item -LiteralPath $ruta).SetAccessControl($acl)
}

# Letras y números al azar (sirven dentro de una dirección postgresql:// sin escapar), sin sesgo.
function Texto-Aleatorio([int]$largo) {
    $alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $byte = New-Object byte[] 1
    $sb = New-Object System.Text.StringBuilder
    while ($sb.Length -lt $largo) {
        $rng.GetBytes($byte)
        if ($byte[0] -lt 248) { [void]$sb.Append($alfabeto[$byte[0] % 62]) }
    }
    $rng.Dispose()
    return $sb.ToString()
}

# --- Archivos del paquete --------------------------------------------------------------------------------------

function Leer-Paquete([string]$origen) {
    $p = Join-Path $origen 'paquete.json'
    if (-not (Test-Path $p)) { return $null }
    return Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Comprueba que cada archivo de imagen llegó entero (huella SHA-256 de paquete.json). Las imágenes bajadas por internet
# no tienen archivo: van por su digest (Cargar-Imagenes).
function Verificar-Imagenes-Paquete($paquete, [string]$origen) {
    foreach ($i in $paquete.imagenes) {
        if (-not $i.archivo) { continue }
        $archivo = Join-Path $origen $i.archivo
        if (-not (Test-Path $archivo)) { throw "Falta $($i.archivo) en el paquete." }
        Cambiar-Progreso "Revisando $(Split-Path $archivo -Leaf)…"
        $huella = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivo).Hash.ToLowerInvariant()
        if ($huella -ne $i.sha256) { throw "El archivo $($i.archivo) llegó dañado (su huella no coincide). Copie otra vez el paquete." }
        Anotar "Huella correcta: $($i.archivo)"
    }
}

function Capas-Imagen([string]$etiqueta) {
    $r = Correr-Docker @('image', 'inspect', '--format', '{{json .RootFS.Layers}}', $etiqueta) 30
    if ($r.Codigo -ne 0) { return $null }
    return ($r.Salida.Trim() | ConvertFrom-Json) -join ','
}

# Carga cada imagen salvo que ya esté igual (mismas capas) y comprueba lo cargado contra paquete.json. Las bajadas
# por internet (con origen y digest) ya están: se comprueba su digest (o se bajan otra vez si se borraron).
function Cargar-Imagenes($paquete, [string]$origen) {
    foreach ($i in $paquete.imagenes) {
        if ($i.digest) { Bajar-Imagen $i; continue }
        $esperadas = $i.capas -join ','
        if ((Capas-Imagen $i.etiqueta) -eq $esperadas) { Anotar "Ya estaba cargada: $($i.etiqueta)"; continue }
        Cambiar-Progreso "Cargando $($i.etiqueta) (puede tardar unos minutos)…"
        $r = Correr-Docker @('load', '-i', (Join-Path $origen $i.archivo)) 1200
        if ($r.Codigo -ne 0) { throw "No se pudo cargar $($i.etiqueta): $(Ultima-Linea $r.Error)" }
        if ((Capas-Imagen $i.etiqueta) -ne $esperadas) { throw "La imagen $($i.etiqueta) cargada no es la del paquete." }
    }
}

# Copia el compose y los scripts del paquete a la carpeta de la instalación y les quita la marca de «descargado».
function Copiar-Archivos([string]$origen, [string]$carpeta) {
    if ((Test-Path $carpeta) -and (Resolve-Path $origen).Path.TrimEnd('\') -ieq (Resolve-Path $carpeta).Path.TrimEnd('\')) {
        Decir 'Se corre desde la carpeta de la instalación: no se copian archivos.'
        return
    }
    foreach ($a in $script:ArchivosInstalados) {
        $desde = Join-Path $origen $a
        $hasta = Join-Path $carpeta $a
        if ($script:EnSeco) { Decir "Copiaría $desde -> $hasta"; continue }
        if ((Get-Item $desde).PSIsContainer) {
            if (Test-Path $hasta) { Remove-Item -Recurse -Force $hasta }
            New-Item -ItemType Directory -Force -Path (Split-Path $hasta) | Out-Null
            Copy-Item -Recurse -Force $desde $hasta
            Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $hasta 'empaquetar.ps1')
        }
        else { Copy-Item -Force $desde $hasta }
    }
    if (-not $script:EnSeco) { Get-ChildItem -Recurse -File $carpeta -Include *.ps1, *.yml, *.sql | Unblock-File }
}

# Rutas (con /) de lo que se instala desde $carpeta: el compose y todo scripts\taller\ (también lo oculto).
function Archivos-Instalables([string]$carpeta) {
    $base = (Resolve-Path -LiteralPath $carpeta).Path.TrimEnd('\')
    $rutas = @()
    if (Test-Path -LiteralPath (Join-Path $base 'docker-compose.taller.yml') -PathType Leaf) { $rutas += 'docker-compose.taller.yml' }
    $scripts = Join-Path $base 'scripts\taller'
    if (Test-Path -LiteralPath $scripts) {
        $rutas += @(Get-ChildItem -LiteralPath $scripts -Recurse -File -Force |
            ForEach-Object { $_.FullName.Substring($base.Length + 1).Replace('\', '/') })
    }
    return $rutas
}

function Huella-Archivo([string]$ruta) { (Get-FileHash -Algorithm SHA256 -LiteralPath $ruta).Hash.ToLowerInvariant() }

function Huella-Bytes([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

# Ruta, huella y tamaño de cada archivo que se instala desde $carpeta (paquete.json de la USB; trampa 2).
function Huellas-De([string]$carpeta) {
    foreach ($r in (Archivos-Instalables $carpeta)) {
        $a = Get-Item -LiteralPath (Join-Path $carpeta $r.Replace('/', '\'))
        [pscustomobject][ordered]@{ ruta = $r; sha256 = Huella-Archivo $a.FullName; bytes = $a.Length }
    }
}

# '' si lo que se instala desde $carpeta es exactamente la lista (cada ruta con su tamaño y su huella, sin archivos de
# más); si no, qué falla.
function Revisar-Huellas($archivos, [string]$carpeta) {
    $lista = @($archivos | Where-Object { $_ })
    if (-not $lista.Count) { return 'no trae la huella de sus archivos' }
    $esperadas = @{}
    foreach ($a in $lista) { $esperadas[([string]$a.ruta).ToLowerInvariant()] = $true }
    foreach ($r in (Archivos-Instalables $carpeta)) {
        if (-not $esperadas.ContainsKey($r.ToLowerInvariant())) { return "sobra el archivo $r" }
    }
    foreach ($a in $lista) {
        $ruta = Join-Path $carpeta ([string]$a.ruta).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { return "falta el archivo $($a.ruta)" }
        if ((Get-Item -LiteralPath $ruta).Length -ne [long]$a.bytes -or (Huella-Archivo $ruta) -ne [string]$a.sha256) {
            return "el archivo $($a.ruta) cambió (su huella no coincide)"
        }
    }
    return ''
}

# Comprueba el compose y cada script del paquete contra su huella de paquete.json (antes solo se miraban las imágenes).
function Verificar-Archivos-Paquete($paquete, [string]$origen) {
    Cambiar-Progreso 'Revisando los archivos del paquete…'
    $falla = Revisar-Huellas $paquete.archivos $origen
    if ($falla) { throw "El paquete no está completo o cambió: $falla. Copie otra vez el paquete." }
    Anotar "Huellas de los archivos: OK ($(@($paquete.archivos).Count))."
}

# --- Actualización por internet (Fase 10) ----------------------------------------------------------------------
# Lo publicado lo firma el desarrollador (scripts/actualizacion/publicar.mjs) y se verifica con la clave de la imagen
# INSTALADA: la raíz de confianza es lo instalado, nunca lo bajado. Orden fijo: bajar ultima.json -> verificar la
# firma -> bajar las imágenes (por digest) y los archivos (por huella) -> recién ahí se corre su actualizar.ps1.
# Todo queda en <instalación>\descargas\<versión>\ (solo ese usuario) y el estado en <instalación>\actualizacion\.

$script:MaximoManifiesto = 64KB          # el mismo máximo del verificador
$script:EspacioMinimoGB = 5
$script:HorasEntreBusquedas = 6

# Mutex de un solo dueño a la vez; $null si lo tiene otro proceso. Si el anterior se cerró sin soltarlo, queda de este.
function Tomar-Mutex([string]$nombre) {
    $m = New-Object System.Threading.Mutex($false, $nombre)
    try { if ($m.WaitOne(0)) { return $m } }
    catch [System.Threading.AbandonedMutexException] { return $m }
    $m.Dispose()
    return $null
}

function Soltar-Mutex($m) {
    if (-not $m) { return }
    try { $m.ReleaseMutex() } catch { }
    $m.Dispose()
}

# Windows PowerShell 5.1 puede intentar TLS 1.0 y GitHub lo rechaza (trampa 5). Con «lo que diga el sistema» (0) se
# deja; si no, se le suma TLS 1.2 (forzar 1.3 en Windows 10 puede romper la conexión).
function Preparar-Tls {
    $p = [Net.ServicePointManager]::SecurityProtocol
    if ([int]$p -ne 0) { [Net.ServicePointManager]::SecurityProtocol = $p -bor [Net.SecurityProtocolType]::Tls12 }
}

# Solo https, sin usuario ni clave, sin ? ni # y terminada en .json (mismas reglas que LICENCIA_URL).
function Url-Actualizacion-Valida([string]$url) {
    return $url -match '^https://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d{1,5})?(/[A-Za-z0-9._~-]+)*/[A-Za-z0-9._~-]+\.json$'
}

# Baja una dirección https a memoria, con tamaño y tiempo máximos. Lanza un error con el motivo.
function Bajar-Bytes([string]$url, [long]$maximo, [int]$segundos = 60) {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Timeout = $segundos * 1000
    $req.ReadWriteTimeout = $segundos * 1000
    $req.UserAgent = 'taller-actualizacion'
    $resp = $req.GetResponse()
    try {
        if ($resp.ResponseUri.Scheme -ne 'https') { throw 'la descarga salió de https' }
        $s = $resp.GetResponseStream()
        $ms = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 65536
        $fin = (Get-Date).AddSeconds($segundos)
        while (($n = $s.Read($buf, 0, $buf.Length)) -gt 0) {
            $ms.Write($buf, 0, $n)
            if ($ms.Length -gt $maximo) { throw "pasa el máximo de $maximo bytes" }
            if ((Get-Date) -gt $fin) { throw "tardó más de $segundos s" }
        }
        return , $ms.ToArray()
    }
    finally { $resp.Close() }
}

# Verifica lo publicado ({"codigo":…}) con el verificador y la clave de la imagen INSTALADA, sin red (trampa 1).
# Devuelve Valido, Motivo y Manifiesto (solo los campos conocidos). Una imagen sin verificador (0.1.6 o antes) no
# puede verificar: no se ofrece nada.
function Verificar-Manifiesto([byte[]]$publicado, [string]$instalada, [string]$postgres) {
    $a = @('run', '--rm', '-i', '--pull', 'never', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges', '--entrypoint', 'node', "taller-motos:$instalada",
        'dist/herramientas/verificar-actualizacion.js', '--instalada', $instalada, '--postgres', $postgres)
    $r = Correr-Docker $a 120 -SinRegistro -Entrada $publicado
    $j = $null
    try { $j = (Ultima-Linea $r.Salida) | ConvertFrom-Json } catch { }
    if (-not $j -or $null -eq $j.valido) {
        Anotar "Verificador: sin respuesta ($(Ultima-Linea $r.Error))"
        return [pscustomobject]@{ Valido = $false; Motivo = 'la versión instalada no puede verificar actualizaciones'; Manifiesto = $null }
    }
    $valido = [bool]$j.valido -and $r.Codigo -eq 0
    Anotar "Verificador: $(if ($valido) { "válido ($($j.manifiesto.version))" } else { "rechazo: $($j.motivo)" })"
    return [pscustomobject]@{ Valido = $valido; Motivo = [string]$j.motivo; Manifiesto = $j.manifiesto }
}

function Id-Imagen([string]$referencia) {
    $r = Correr-Docker @('image', 'inspect', '--format', '{{.Id}}', $referencia) 30
    if ($r.Codigo -ne 0) { return '' }
    return $r.Salida.Trim()
}

# ¿La etiqueta del compose apunta a la imagen bajada por el digest firmado? (trampa 3)
function Imagen-Lista($i) {
    $porDigest = Id-Imagen "$($i.origen)@$($i.digest)"
    return [bool]$porDigest -and $porDigest -eq (Id-Imagen $i.etiqueta)
}

# Baja la imagen por su digest firmado (Docker comprueba que el contenido sea ese) y le pone la etiqueta del compose.
function Bajar-Imagen($i) {
    if (Imagen-Lista $i) { Anotar "Ya está por digest: $($i.etiqueta)"; return }
    $ref = "$($i.origen)@$($i.digest)"
    Cambiar-Progreso "Bajando $($i.etiqueta)…"
    $r = Correr-Docker @('pull', '--platform', 'linux/amd64', $ref) 3600
    if ($r.Codigo -ne 0) { throw "No se pudo bajar ${ref}: $(Ultima-Linea $r.Error)" }
    $r = Correr-Docker @('tag', $ref, $i.etiqueta) 60
    if ($r.Codigo -ne 0 -or -not (Imagen-Lista $i)) { throw "La imagen $($i.etiqueta) bajada no es la firmada." }
}

# Las imágenes que hay que bajar: la de la app siempre; la de postgres solo si cambia (la instalada ya está aquí).
function Imagenes-A-Bajar($manifiesto, [string]$pgInstalado) {
    return @($manifiesto.imagenes | Where-Object { $_.etiqueta -ne "postgres:$pgInstalado" })
}

# paquete.json de una versión bajada, armado desde el manifiesto ya verificado (como el de la USB, sin archivos de
# imagen: van por digest). abrir.ps1 lo vuelve a escribir justo antes de instalar.
function Escribir-Paquete-Descargado($manifiesto, [string]$carpetaVersion, [string]$pgInstalado) {
    $p = [ordered]@{
        version  = [string]$manifiesto.version
        creado   = [string]$manifiesto.creado
        desde    = 'internet'
        imagenes = @(Imagenes-A-Bajar $manifiesto $pgInstalado | ForEach-Object {
                [ordered]@{ etiqueta = $_.etiqueta; origen = $_.origen; digest = $_.digest } })
        archivos = @($manifiesto.archivos | ForEach-Object { [ordered]@{ ruta = $_.ruta; sha256 = $_.sha256; bytes = [long]$_.bytes } })
    }
    [System.IO.File]::WriteAllText((Join-Path $carpetaVersion 'paquete.json'), ($p | ConvertTo-Json -Depth 5),
        (New-Object System.Text.UTF8Encoding($false)))
}

# Estado de la búsqueda, fuera de descargas\ (que se borra): hora de la última y versiones que fallaron al instalarse
# (no se vuelven a ofrecer solas; trampa 9).
function Archivo-Estado([string]$carpeta) { Join-Path $carpeta 'actualizacion\estado.json' }

function Leer-Estado([string]$carpeta) {
    $e = @{ ultimaBusqueda = [long]0; fallidas = @() }
    $a = Archivo-Estado $carpeta
    if (-not (Test-Path -LiteralPath $a)) { return $e }
    try {
        $j = Get-Content -LiteralPath $a -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.ultimaBusqueda) { $e.ultimaBusqueda = [long]$j.ultimaBusqueda }
        $e.fallidas = @($j.fallidas | Where-Object { $_ -match '^\d{1,6}\.\d{1,6}\.\d{1,6}$' })
    }
    catch { Anotar "Estado de la actualización ilegible ($($_.Exception.Message)): se empieza de cero." }
    return $e
}

function Guardar-Estado([string]$carpeta, $estado) {
    if ($script:EnSeco) { return }
    $a = Archivo-Estado $carpeta
    New-Item -ItemType Directory -Force -Path (Split-Path $a) | Out-Null
    $json = [ordered]@{ ultimaBusqueda = [long]$estado.ultimaBusqueda; fallidas = @($estado.fallidas | Select-Object -Unique) } | ConvertTo-Json
    [System.IO.File]::WriteAllText($a, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Ahora-Segundos { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Carpeta-Descargas([string]$carpeta) { Join-Path $carpeta 'descargas' }

# Versiones bajadas con la marca LISTA (la última que se escribe), de la más nueva a la más vieja.
function Descargas-Listas([string]$carpeta) {
    $d = Carpeta-Descargas $carpeta
    if (-not (Test-Path -LiteralPath $d)) { return @() }
    return @(Get-ChildItem -LiteralPath $d -Directory |
        Where-Object { $_.Name -match '^\d{1,6}\.\d{1,6}\.\d{1,6}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'LISTA')) } |
        Sort-Object { [version]$_.Name } -Descending | ForEach-Object { $_.Name })
}

function Borrar-Descarga([string]$carpeta, [string]$version) {
    $c = Join-Path (Carpeta-Descargas $carpeta) $version
    if (-not (Test-Path -LiteralPath $c)) { return }
    if ($script:EnSeco) { Decir "Borraría $c"; return }
    Remove-Item -LiteralPath $c -Recurse -Force
    Anotar "Descarga borrada: $version"
}

# Vuelve a revisar una versión bajada antes de darla por lista o de instalarla: la firma (con la imagen instalada),
# que la carpeta sea esa versión, la huella de cada archivo (sin archivos de más), el postgres del compose bajado
# (el verificador no ve el compose) y las imágenes por digest. Devuelve el manifiesto o lanza el motivo.
function Revisar-Descarga([string]$carpeta, [string]$version, [string]$instalada, [string]$pgInstalado) {
    $c = Join-Path (Carpeta-Descargas $carpeta) $version
    $archivo = Join-Path $c 'manifiesto.json'
    if (-not (Test-Path -LiteralPath $archivo -PathType Leaf)) { throw 'falta manifiesto.json' }
    if ((Get-Item -LiteralPath $archivo).Length -gt $script:MaximoManifiesto) { throw 'manifiesto.json pasa el máximo' }
    $v = Verificar-Manifiesto ([System.IO.File]::ReadAllBytes($archivo)) $instalada $pgInstalado
    if (-not $v.Valido) { throw "la firma no se aceptó: $($v.Motivo)" }
    $m = $v.Manifiesto
    if ($m.version -ne $version) { throw "la carpeta $version tiene el manifiesto de la $($m.version)" }
    $falla = Revisar-Huellas $m.archivos $c
    if ($falla) { throw $falla }
    $pg = Etiqueta-Postgres (Join-Path $c 'docker-compose.taller.yml')
    if ($pg -ne $m.postgres) { throw "el compose bajado trae postgres:$pg y lo firmado dice postgres:$($m.postgres)" }
    foreach ($i in (Imagenes-A-Bajar $m $pgInstalado)) {
        if (-not (Imagen-Lista $i)) { throw "la imagen $($i.etiqueta) no está bajada por su digest" }
    }
    return $m
}

# Borra las imágenes taller-motos que ya no sirven, con sus referencias por digest (ghcr.io/…@sha256:…), menos las
# de $conservar (la instalada, la anterior y las bajadas). Lo que falle solo queda en el registro.
function Borrar-Imagenes-Viejas([string[]]$conservar) {
    $r = Correr-Docker @('image', 'ls', 'taller-motos', '--format', '{{.Tag}}') 60
    if ($r.Codigo -ne 0) { return }
    $viejas = @(($r.Salida -split "`r?`n") | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+\.\d+\.\d+$' -and $conservar -notcontains $_ })
    foreach ($etiqueta in $viejas) {
        if ($script:EnSeco) { Decir "Borraría la imagen taller-motos:$etiqueta"; continue }
        $digests = Correr-Docker @('image', 'inspect', '--format', '{{json .RepoDigests}}', "taller-motos:$etiqueta") 30
        [void](Correr-Docker @('image', 'rm', "taller-motos:$etiqueta") 120)
        if ($digests.Codigo -ne 0) { continue }
        foreach ($ref in @($digests.Salida.Trim() | ConvertFrom-Json)) {
            if ($ref -like '*@sha256:*') { [void](Correr-Docker @('image', 'rm', $ref) 120) }
        }
    }
}

# --- Carpetas de copias ----------------------------------------------------------------------------------------

function Libre-GB([string]$ruta) {
    $raiz = [System.IO.Path]::GetPathRoot($ruta)
    return [math]::Round((New-Object System.IO.DriveInfo($raiz)).AvailableFreeSpace / 1GB, 1)
}

function Disco-Con-Mas-Espacio {
    $d = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object FreeSpace -Descending | Select-Object -First 1
    return "$($d.DeviceID)\"
}

# ¿$ruta es $raiz o una carpeta dentro de ella? Sin distinguir mayúsculas ni la barra del final.
function Dentro-De([string]$ruta, [string]$raiz) {
    if (-not $ruta -or -not $raiz) { return $false }
    $r = $raiz.TrimEnd('\')
    $c = $ruta.TrimEnd('\')
    if ($c.Equals($r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $c.StartsWith("$r\", [System.StringComparison]::OrdinalIgnoreCase)
}

# Carpetas del equipo que respalda Google Drive para escritorio («Carpetas de mi computadora», por ejemplo
# Documentos): su ruta no dice «Google Drive» (simulacro, 2026-11-16). Drive las guarda en root_preference_sqlite.db
# (tabla roots, columna last_seen_absolute_path); se lee con el SQLite que trae Windows (winsqlite3.dll), solo
# lectura. Si algo falla, ninguna: entonces solo se avisa de más.
function Carpetas-GoogleDrive {
    $db = Join-Path $env:LOCALAPPDATA 'Google\DriveFS\root_preference_sqlite.db'
    if (-not (Test-Path -LiteralPath $db)) { return @() }
    try {
        if (-not ('TallerSqlite' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class TallerSqlite {
    [DllImport("winsqlite3.dll")] static extern int sqlite3_open_v2(byte[] archivo, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CharSet = CharSet.Unicode)] static extern int sqlite3_prepare16_v2(IntPtr db, string sql, int largo, out IntPtr st, IntPtr resto);
    [DllImport("winsqlite3.dll")] static extern int sqlite3_step(IntPtr st);
    [DllImport("winsqlite3.dll")] static extern IntPtr sqlite3_column_text16(IntPtr st, int columna);
    [DllImport("winsqlite3.dll")] static extern int sqlite3_finalize(IntPtr st);
    [DllImport("winsqlite3.dll")] static extern int sqlite3_close(IntPtr db);
    public static string[] Columna(string archivo, string sql) {
        var lista = new List<string>();
        IntPtr db, st;
        if (sqlite3_open_v2(Encoding.UTF8.GetBytes(archivo + "\0"), out db, 1, IntPtr.Zero) != 0) { sqlite3_close(db); return lista.ToArray(); }
        try {
            if (sqlite3_prepare16_v2(db, sql, -1, out st, IntPtr.Zero) != 0) return lista.ToArray();
            try { while (sqlite3_step(st) == 100) { var t = Marshal.PtrToStringUni(sqlite3_column_text16(st, 0)); if (t != null) lista.Add(t); } }
            finally { sqlite3_finalize(st); }
        }
        finally { sqlite3_close(db); }
        return lista.ToArray();
    }
}
'@
        }
        return @([TallerSqlite]::Columna($db, 'SELECT last_seen_absolute_path FROM roots') |
            ForEach-Object { $_ -replace '^\\\\\?\\', '' } | Where-Object { $_ -and $_.TrimEnd('\').Length -gt 2 })
    }
    catch {
        Anotar "Google Drive: no se leyeron sus carpetas ($($_.Exception.Message))"
        return @()
    }
}

# Carpetas que sincroniza OneDrive, según su registro del usuario (no solo las variables de entorno): la carpeta de
# cada cuenta y las bibliotecas de SharePoint o Teams, que pueden quedar fuera de ella. Documentos, Escritorio o
# Imágenes respaldados por OneDrive se mudan dentro de la carpeta de la cuenta, así que también cuentan.
function Carpetas-OneDrive {
    $motores = @(Get-ChildItem 'HKCU:\Software\SyncEngines\Providers\OneDrive' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue })
    $cuentas = @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Datos = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                Cache = Get-ItemProperty (Join-Path $_.PSPath 'ScopeIdToMountPointPathCache') -ErrorAction SilentlyContinue
            }
        })
    return @(Rutas-OneDrive $motores $cuentas)
}

# Lo que se lee del registro: MountPoint de cada motor; UserFolder y los valores de ScopeIdToMountPointPathCache de
# cada cuenta. Aparte para probarlo sin tocar el registro.
function Rutas-OneDrive($motores, $cuentas) {
    $rutas = @($motores | Where-Object { $_ } | ForEach-Object { $_.MountPoint })
    foreach ($c in @($cuentas | Where-Object { $_ })) {
        if ($c.Datos) { $rutas += $c.Datos.UserFolder }
        if ($c.Cache) { $rutas += $c.Cache.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $_.Value } }
    }
    return @($rutas | Where-Object { $_ -is [string] -and $_.TrimEnd('\').Length -gt 2 } | Select-Object -Unique)
}

function Parece-Sincronizada([string]$ruta) {
    if (-not $ruta) { return $false }
    $raices = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) + @(Carpetas-OneDrive) + @(Carpetas-GoogleDrive)
    foreach ($raiz in $raices) {
        if (Dentro-De $ruta $raiz) { return $true }
    }
    return $ruta -match '(?i)\\(OneDrive|Google ?Drive|Mi unidad|My Drive|Dropbox|iCloudDrive)([\\ ]|$)'
}

# '' si la carpeta sirve; si no, por qué.
function Revisar-Carpeta([string]$ruta) {
    if (-not $ruta) { return 'No se eligió ninguna carpeta.' }
    if ($ruta -notmatch '^[A-Za-z]:\\') { return "«$ruta» no es una carpeta de un disco de este equipo (por ejemplo D:\TallerCopias)." }
    if ($ruta.Contains("'")) { return "La ruta «$ruta» lleva una comilla ('); elija otra carpeta." }
    return ''
}

# Pregunta una o dos carpetas para las copias. Propone la actual o una en el disco con más espacio libre.
# Devuelve @{ Local; Nube } o $null si el dueño cancela.
function Elegir-Destinos([string]$localActual = '', [string]$nubeActual = '') {
    while ($true) {
        $propuesta = if ($localActual) { $localActual } else { Join-Path (Disco-Con-Mas-Espacio) 'TallerCopias' }
        $local = $propuesta
        $texto = "Las copias de la base se guardarán en:`n`n    $propuesta`n`n(quedan $(Libre-GB $propuesta) GB libres en ese disco)`n`n¿Usar esta carpeta? Con «No» elige otra."
        if (-not (Preguntar-SiNo $texto)) {
            $local = Elegir-Carpeta 'Carpeta para las copias de la base del taller' $propuesta
            if (-not $local) { return $null }
        }
        $falla = Revisar-Carpeta $local
        if ($falla) { Mostrar-Mensaje $falla 'Aviso'; continue }

        $nube = ''
        $texto = "¿Quiere una segunda carpeta para las copias?`n`nSirve la que sincroniza Google Drive u OneDrive: así queda una copia fuera del portátil. Si la primera ya es una de esas, no hace falta."
        if (Preguntar-SiNo $texto ([bool]$nubeActual)) {
            $nube = Elegir-Carpeta 'Segunda carpeta para las copias (por ejemplo, dentro de Google Drive u OneDrive)' $nubeActual
            if ($nube) {
                $falla = Revisar-Carpeta $nube
                if (-not $falla -and $nube.TrimEnd('\') -ieq $local.TrimEnd('\')) { $falla = 'La segunda carpeta es la misma que la primera.' }
                if ($falla) { Mostrar-Mensaje $falla 'Aviso'; continue }
            }
        }
        if (-not (Parece-Sincronizada $local) -and -not (Parece-Sincronizada $nube)) {
            $texto = "Ninguna de las carpetas parece estar sincronizada con la nube (Google Drive, OneDrive o Dropbox).`n`nSi el portátil se daña o se pierde, se pierden también las copias.`n`n¿Seguir así?"
            # En seco sin ventanas la respuesta propuesta («No») volvería a preguntar sin fin: se sigue.
            if (-not (Preguntar-SiNo $texto $false) -and -not $script:SinVentanas) { $localActual = $local; $nubeActual = $nube; continue }
        }
        return @{ Local = $local; Nube = $nube }
    }
}

function Crear-Carpetas($destinos) {
    foreach ($c in @($destinos.Local, $destinos.Nube)) {
        if (-not $c) { continue }
        if ($script:EnSeco) { Decir "Crearía la carpeta $c (si no existe)"; continue }
        New-Item -ItemType Directory -Force -Path $c | Out-Null
    }
}

# --- Accesos directos ------------------------------------------------------------------------------------------

# Cada ícono corre su script con conhost --headless: sin ventana de consola, también con Windows Terminal como
# consola predeterminada (allí -WindowStyle Hidden no la esconde). Los scripts hablan con ventanas. Con -Consola, el
# script corre en una consola que se ve (restaurar.ps1 pregunta allí).
function Crear-Acceso([string]$ruta, [string]$carpeta, [string]$extra = '', [string]$script = 'abrir.ps1',
    [string]$descripcion = 'Abre el sistema del taller en el navegador', [switch]$Consola) {
    $abrir = Join-Path $carpeta "scripts\taller\$script"
    $powershell = "-NoProfile -ExecutionPolicy Bypass -File `"$abrir`" $extra".TrimEnd()
    if ($Consola) {
        $programa = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argumentos = $powershell
    }
    else {
        $programa = Join-Path $env:SystemRoot 'System32\conhost.exe'
        $argumentos = "--headless powershell.exe -WindowStyle Hidden $powershell"
    }
    if ($script:EnSeco) { Decir "Crearía el acceso «$ruta» -> $programa $argumentos"; return }
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($ruta)
    $l.TargetPath = $programa
    $l.Arguments = $argumentos
    $l.WorkingDirectory = $carpeta
    $l.IconLocation = "$(Join-Path $carpeta 'scripts\taller\taller.ico'),0"
    $l.Description = $descripcion
    $l.WindowStyle = $(if ($Consola) { 1 } else { 7 })
    $l.Save()
}

function Crear-Accesos([string]$carpeta) {
    Crear-Acceso (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Taller.lnk') $carpeta
    Crear-Acceso (Join-Path ([Environment]::GetFolderPath('Programs')) 'Taller.lnk') $carpeta
    # Al iniciar sesión: enciende Docker y el taller sin abrir el navegador.
    Crear-Acceso (Join-Path ([Environment]::GetFolderPath('Startup')) 'Taller (al encender).lnk') $carpeta '-Arranque'
    # Las carpetas de las copias se montan en el contenedor: no se cambian desde la web, sino con este ícono.
    Crear-Acceso (Join-Path ([Environment]::GetFolderPath('Programs')) 'Taller - Cambiar carpetas de copias.lnk') $carpeta '' `
        'cambiar-destinos.ps1' 'Cambia las carpetas donde se guardan las copias del taller'
    # Restaurar no está en la web (por ahora): este ícono abre su consola sin escribir ningún comando.
    Crear-Acceso (Join-Path ([Environment]::GetFolderPath('Programs')) 'Taller - Restaurar una copia.lnk') $carpeta '-Pausa' `
        'restaurar.ps1' 'Restaura una copia del taller (pide la frase de la hoja)' -Consola
}
