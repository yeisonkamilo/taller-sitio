# Ícono «Taller» (Fase 8, Paso 7): abre el sistema del taller sin consola. Si la app ya responde, solo abre el
# navegador; si no, enciende Docker Desktop si hace falta, levanta el compose, espera la salud mostrando
# «Abriendo el taller…» y abre el navegador. Si algo falla, lo dice en palabras del taller y deja el detalle en
# registro\abrir.log de la carpeta de la instalación.
# Actualización por internet (Fase 10): si buscar-actualizacion.ps1 dejó una versión bajada y lista, antes de abrir el
# navegador pregunta «¿Actualizar ahora?»; con «Sí» revisa otra vez lo bajado con la imagen instalada y corre su
# actualizar.ps1 (copia antes y vuelta atrás). Al final lanza la búsqueda en segundo plano, sin esperarla.
# El acceso directo lo corre con: conhost.exe --headless powershell.exe ... -File abrir.ps1 [-Arranque]
# -Arranque (al iniciar sesión): lo mismo, sin ventana de espera, navegador ni pregunta; solo avisa si falla.
#   Aviso de versión nueva (Fase 11): con -Arranque, si ya había una versión bajada y lista, muestra la notificación de
#   Windows; su clic corre este mismo script como el ícono (enlace taller-actualizar:, sin nada del enlace), que pregunta.
# -Seco: dice qué haría, sin encender ni abrir nada.
param(
    [string]$Carpeta = '',
    [switch]$Arranque,
    [switch]$Seco
)
. (Join-Path $PSScriptRoot 'comun.ps1')
Preparar-Comun -Seco:$Seco
if (-not $Carpeta) { $Carpeta = $CarpetaPorDefecto }

function Fallar([string]$texto) {
    Cerrar-Progreso
    Anotar-Estado $Carpeta
    $detalle = if ($script:Registro) { "`n`nEl detalle quedó en $($script:Registro)." } else { '' }
    Mostrar-Mensaje "$texto$detalle`n`nSi sigue pasando, avise al técnico." 'Error'
    exit 1
}

# Lanza buscar-actualizacion.ps1 sin esperarlo y sin ventana: al iniciar sesión siempre; al abrir el ícono, si pasaron
# 6 horas desde la última búsqueda.
function Lanzar-Busqueda {
    if (-not $valores['ACTUALIZACION_URL']) { Decir 'Sin ACTUALIZACION_URL: no se buscan versiones nuevas.'; return }
    $horas = ((Ahora-Segundos) - (Leer-Estado $Carpeta).ultimaBusqueda) / 3600
    if (-not $Arranque -and $horas -lt $HorasEntreBusquedas) {
        Decir ('La última búsqueda de versión nueva fue hace {0:N1} h: no se busca otra vez.' -f $horas)
        return
    }
    $buscar = Join-Path $PSScriptRoot 'buscar-actualizacion.ps1'
    $argumentos = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $(Citar $buscar) -Carpeta $(Citar $Carpeta)"
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    if ($Seco) { Decir "Buscaría una versión nueva en segundo plano: $conhost $argumentos"; return }
    Start-Process -FilePath $conhost -ArgumentList $argumentos -WindowStyle Hidden
    Anotar 'Búsqueda de versión nueva lanzada en segundo plano.'
}

# Con una versión bajada y lista, pregunta. Con «No» abre como siempre y vuelve a preguntar la próxima vez.
function Ofrecer-Actualizacion {
    $instalada = [string]$valores['TALLER_VERSION']
    $lista = Version-Pendiente $Carpeta $instalada
    if (-not $lista) { Decir 'No hay una versión nueva bajada.'; return }
    # Mientras se busca o se baja, no se pregunta (trampa 6); la búsqueda tampoco empieza mientras se instala.
    $mutex = Tomar-Mutex 'Local\TallerActualizar'
    if (-not $mutex) { Decir "Se está bajando algo: no se pregunta por la $lista ahora."; return }
    try {
        $texto = "Hay una versión nueva del taller: la $lista (ahora tiene la $instalada).`n`n" +
        "Antes de actualizar se hace una copia de la base, y el taller se detiene unos minutos. Si algo sale mal, " +
        "vuelve solo a la versión de ahora.`n`n¿Actualizar ahora?"
        if (-not (Preguntar-SiNo $texto)) { Anotar "El dueño no quiso actualizar a la $lista ahora."; return }
        # El código de confianza es el instalado: revisa lo bajado con la imagen instalada antes de correr nada de ahí.
        $pg = Etiqueta-Postgres (Join-Path $Carpeta 'docker-compose.taller.yml')
        $paquete = Join-Path (Carpeta-Descargas $Carpeta) $lista
        try { $m = Revisar-Descarga $Carpeta $lista $instalada $pg }
        catch {
            Decir "La $lista bajada no pasó la revisión: $($_.Exception.Message)"
            Borrar-Descarga $Carpeta $lista
            Mostrar-Mensaje "La versión $lista bajada no pasó la revisión de seguridad, así que no se instaló. Se volverá a bajar más tarde.`n`nEl taller sigue con la versión $instalada." 'Aviso'
            return
        }
        $actualizar = Join-Path $paquete 'scripts\taller\actualizar.ps1'
        if ($Seco) { Decir "Revisión de la $lista bajada: OK. Correría $actualizar -Carpeta $Carpeta -YaConfirmado"; return }
        Escribir-Paquete-Descargado $m $paquete $pg   # desde lo firmado, no desde lo que haya en el disco
        Anotar "Instalando la $lista bajada."
        $global:LASTEXITCODE = 1
        try { & $actualizar -Carpeta $Carpeta -YaConfirmado; $codigo = $global:LASTEXITCODE }
        catch { Anotar "actualizar.ps1 se cortó: $($_.Exception.Message)"; $codigo = 1 }
        Anotar "actualizar.ps1 de la $lista terminó con el código $codigo."
        if ($codigo -eq 0) {
            Remove-Item -LiteralPath (Carpeta-Descargas $Carpeta) -Recurse -Force -ErrorAction SilentlyContinue
        }
        elseif ($codigo -eq 3) {
            # Se probó y volvió atrás: no se vuelve a ofrecer sola (trampa 9).
            $estado = Leer-Estado $Carpeta
            $estado.fallidas = @($estado.fallidas) + $lista
            Guardar-Estado $Carpeta $estado
            Borrar-Descarga $Carpeta $lista
        }
        # Con 1 no se cambió nada: se vuelve a preguntar la próxima vez.
    }
    finally { Soltar-Mutex $mutex }
}

# Al iniciar sesión: la notificación de la versión que ya estaba bajada ANTES de lanzar la búsqueda (la que se baje
# ahora la avisa buscar-actualizacion.ps1 al terminar, así no se repite).
function Avisar-Pendiente {
    if (-not $valores['ACTUALIZACION_URL']) { return }
    $v = Version-Pendiente $Carpeta ([string]$valores['TALLER_VERSION'])
    if ($v) { Avisar-VersionNueva $Carpeta $v } else { Decir 'No hay una versión nueva bajada: sin aviso.' }
}

# Lo último: la pregunta de la versión bajada (solo al abrir el ícono a mano) o su aviso (al iniciar sesión), la
# búsqueda y el navegador.
function Terminar {
    if (-not $Arranque) {
        try { Ofrecer-Actualizacion } catch { Anotar "Actualización: $($_.Exception.Message)" }
    }
    else {
        try { Avisar-Pendiente } catch { Anotar "Aviso: $($_.Exception.Message)" }
    }
    try { Lanzar-Busqueda } catch { Anotar "Búsqueda: $($_.Exception.Message)" }
    if ($Seco) { Decir $(if ($Arranque) { 'Sin navegador (-Arranque).' } else { "Abriría $url" }) }
    elseif (-not $Arranque -and (App-Sana $puerto)) { Start-Process $url }
    exit 0
}

# Dos clics seguidos en el ícono: el segundo no levanta nada más.
$unaVez = New-Object System.Threading.Mutex($false, 'Local\TallerAbrir')
if (-not $unaVez.WaitOne(0)) { exit 0 }
try {
    $archivoEnv = Join-Path $Carpeta '.env'
    if (-not (Test-Path $archivoEnv)) {
        if (-not $Seco) { Mostrar-Mensaje "El taller no está instalado en este equipo (no está $archivoEnv).`n`nAvise al técnico." 'Error'; exit 1 }
        Decir "No hay instalación en ${Carpeta}: en seco se usa el puerto del equipo por defecto (3101)."
    }
    Iniciar-Registro $Carpeta 'abrir'
    $valores = Leer-Env $archivoEnv
    $puerto = Puerto-Equipo $valores
    $url = "http://127.0.0.1:$puerto/"

    if (App-Sana $puerto) {
        Anotar 'La app ya responde.'
        if ($Seco) { Decir "La app ya responde en $url." }
        Terminar
    }

    if ($Seco) {
        Decir "La app no responde en $url. Se haría:"
        Decir "  1. Docker: $(if (Docker-Listo) { 'ya está encendido' } elseif (Buscar-DockerDesktop) { 'abrir Docker Desktop y esperar hasta 4 min' } else { 'NO está instalado: se avisaría' })"
        Decir "  2. docker $((Argumentos-Compose $Carpeta) -join ' ') up -d"
        Decir "  3. Esperar /api/salud hasta 4 min (ventana «Abriendo el taller…»$(if ($Arranque) { ', que con -Arranque no sale' }))"
        Decir '  4. Lo de abajo (pregunta o aviso de la versión bajada, búsqueda y navegador):'
        Terminar
    }

    if (-not $Arranque) { Abrir-Progreso 'Abriendo el taller…' }
    $espera = if ($Arranque) { 300 } else { 240 }
    if (-not (Encender-Docker $espera)) { Fallar "No se pudo abrir el taller.`n`n$(Explicar-Docker-Apagado)" }

    Cambiar-Progreso 'Encendiendo el taller…'
    $r = Correr-Docker ((Argumentos-Compose $Carpeta) + @('up', '-d')) 300
    if ($r.Codigo -ne 0) { Fallar 'No se pudo encender el taller.' }

    Cambiar-Progreso 'Esperando a que el taller responda…'
    if (-not (Esperar-Salud $puerto 240)) { Fallar 'El taller encendió pero no responde.' }

    Cerrar-Progreso
    Anotar 'Listo.'
    Terminar
}
finally {
    Cerrar-Progreso
    $unaVez.ReleaseMutex()
}
