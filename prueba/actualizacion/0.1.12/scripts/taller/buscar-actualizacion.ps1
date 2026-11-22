# Busca y baja una versión nueva del taller por internet (Fase 10, Paso 4), en segundo plano y sin ventanas. Lo lanza
# abrir.ps1 sin esperarlo: al iniciar sesión y al abrir el ícono si pasaron 6 horas. Pasos:
#   1. Baja ultima.json de ACTUALIZACION_URL (.env): solo https, hasta 64 KB y 60 s, con TLS 1.2.
#   2. Verifica la firma con el verificador y la clave de la imagen INSTALADA (docker run --network none): solo sigue
#      con una versión más nueva que la instalada, firmada con la clave de actualizaciones.
#   3. Revisa el disco libre y baja la imagen de la app (y la de postgres si cambia) por su digest firmado
#      (docker pull --platform linux/amd64 origen@sha256:…), con la etiqueta del compose.
#   4. Baja cada archivo (el compose y scripts\taller\) y comprueba su tamaño y su huella.
#   5. Arma el paquete en descargas\<versión>\ (con paquete.json, como el de la USB) y al final deja la marca LISTA.
# Al dueño no se le muestra nada: sin internet, sin URL o con algo raro solo queda una línea en registro\actualizar.log.
# Solo cuando acaba de dejar LISTA muestra una vez la notificación de Windows (Fase 11); la pregunta «¿Actualizar
# ahora?» la hace abrir.ps1 al abrir el ícono o al hacer clic en la notificación.
# Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File buscar-actualizacion.ps1 [-Carpeta <instalación>]
#       [-Url https://…/ultima.json] [-Seco]
# -Seco: baja y verifica ultima.json (en memoria, no escribe nada) y dice qué bajaría.
param(
    [string]$Carpeta = '',
    [string]$Url = '',
    [switch]$Seco
)
. (Join-Path $PSScriptRoot 'comun.ps1')
Preparar-Comun -Seco:$Seco
$script:SinVentanas = $true   # en segundo plano: nunca una ventana
if (-not $Carpeta) { $Carpeta = $CarpetaPorDefecto }
$archivoEnv = Join-Path $Carpeta '.env'

function Salir([string]$texto) {
    Decir $texto
    exit 0
}

# Dos búsquedas a la vez, o una búsqueda mientras abrir.ps1 instala: la segunda sale.
$mutex = Tomar-Mutex 'Local\TallerActualizar'
if (-not $mutex) { Write-Host 'Hay otra búsqueda o una actualización en curso: esta sale.'; exit 0 }
try {
    $instalado = Test-Path -LiteralPath $archivoEnv
    if (-not $instalado -and -not $Seco) { exit 0 }
    Iniciar-Registro $Carpeta 'actualizar'
    Anotar 'Buscar una versión nueva por internet'
    $valores = Leer-Env $archivoEnv
    if (-not $Url) { $Url = [string]$valores['ACTUALIZACION_URL'] }
    if ($instalado) {
        $instalada = [string]$valores['TALLER_VERSION']
        $compose = Join-Path $Carpeta 'docker-compose.taller.yml'
    }
    else {
        $raiz = Raiz-Del-Paquete
        $instalada = (Get-Content (Join-Path $raiz 'servidor\package.json') -Raw | ConvertFrom-Json).version
        $compose = Join-Path $raiz 'docker-compose.taller.yml'
        Decir "No hay instalación en ${Carpeta}: en seco se toma la versión del repositorio ($instalada)."
    }
    $pgInstalado = Etiqueta-Postgres $compose
    if (-not $Url) { Salir 'Sin ACTUALIZACION_URL: no se buscan versiones nuevas.' }
    if (-not (Url-Actualizacion-Valida $Url)) { Salir 'ACTUALIZACION_URL no sirve (solo https://…/algo.json, sin usuario, ? ni #): no se busca.' }
    $estado = Leer-Estado $Carpeta
    $estado.ultimaBusqueda = Ahora-Segundos
    Guardar-Estado $Carpeta $estado
    if (-not (Docker-Listo)) { Salir 'Docker no está encendido: no se busca.' }

    # ==== 1. Bajar lo publicado ===================================================================================
    Decir "1. Bajar $Url (instalada $instalada, postgres $pgInstalado)."
    Preparar-Tls
    try { $publicado = Bajar-Bytes $Url $MaximoManifiesto 60 }
    catch { Salir "Sin versión nueva: no se pudo bajar ultima.json ($($_.Exception.Message))." }

    # ==== 2. Verificar la firma con la imagen instalada ===========================================================
    Decir '2. Verificar la firma con la imagen instalada.'
    $v = Verificar-Manifiesto $publicado $instalada $pgInstalado
    if (-not $v.Valido) { Salir "Sin versión nueva para instalar: $($v.Motivo)." }
    $m = $v.Manifiesto
    $version = [string]$m.version
    Decir "   Firmada y más nueva: $version (postgres $($m.postgres), $(@($m.archivos).Count) archivos)."
    if ($estado.fallidas -contains $version) {
        Salir "La $version ya falló al instalarse: no se vuelve a ofrecer sola (se espera una más nueva o la USB)."
    }
    if ((Descargas-Listas $Carpeta) -contains $version) {
        $falla = ''
        try { [void](Revisar-Descarga $Carpeta $version $instalada $pgInstalado) } catch { $falla = $_.Exception.Message }
        if (-not $falla) { Salir "La $version ya está bajada y lista para instalar." }
        Decir "La $version bajada no pasó la revisión ($falla): se baja de nuevo."
        Borrar-Descarga $Carpeta $version
    }

    $imagenes = @(Imagenes-A-Bajar $m $pgInstalado)   # @(): en PowerShell 5.1 un objeto suelto no tiene .Count
    $libre = Libre-GB $env:LOCALAPPDATA
    $base = $Url.Substring(0, $Url.LastIndexOf('/'))
    $destino = Join-Path (Carpeta-Descargas $Carpeta) $version
    if ($Seco) {
        Decir "3. Disco libre: $libre GB (hacen falta $EspacioMinimoGB). Bajaría por digest:"
        foreach ($i in $imagenes) { Decir "     docker pull --platform linux/amd64 $($i.origen)@$($i.digest)  ->  $($i.etiqueta)" }
        if (-not $imagenes.Count) { Decir '     (ninguna)' }
        Decir "4. Bajaría $(@($m.archivos).Count) archivos de $base/$version/ y comprobaría tamaño y huella:"
        foreach ($a in $m.archivos) { Decir "     $($a.ruta) ($($a.bytes) bytes)" }
        Decir "5. Armaría $destino con paquete.json y la marca LISTA, y borraría las otras descargas."
        exit 0
    }
    if ($libre -lt $EspacioMinimoGB) { Salir "Poco disco ($libre GB libres; hacen falta $EspacioMinimoGB): no se baja la $version." }

    # Un corte a mitad deja la carpeta sin LISTA: se empieza de nuevo (Docker retoma las capas que ya tenía).
    Borrar-Descarga $Carpeta $version
    try {
        New-Item -ItemType Directory -Force -Path $destino | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $destino 'manifiesto.json'), $publicado)

        # ==== 3. Imágenes por digest ==============================================================================
        Decir "3. Bajar por digest: $(if ($imagenes.Count) { ($imagenes | ForEach-Object { $_.etiqueta }) -join ', ' } else { 'ninguna' })."
        foreach ($i in $imagenes) { Bajar-Imagen $i }

        # ==== 4. Archivos por huella ==============================================================================
        Decir "4. Bajar $(@($m.archivos).Count) archivos de $base/$version/."
        foreach ($a in $m.archivos) {
            $bytes = Bajar-Bytes "$base/$version/$($a.ruta)" ([long]$a.bytes) 120
            if ($bytes.Length -ne [long]$a.bytes -or (Huella-Bytes $bytes) -ne [string]$a.sha256) {
                throw "el archivo $($a.ruta) bajado no es el firmado (tamaño o huella)"
            }
            $ruta = Join-Path $destino ([string]$a.ruta).Replace('/', '\')
            New-Item -ItemType Directory -Force -Path (Split-Path $ruta) | Out-Null
            [System.IO.File]::WriteAllBytes($ruta, $bytes)
        }

        # ==== 5. Paquete y marca LISTA (lo último) ================================================================
        Escribir-Paquete-Descargado $m $destino $pgInstalado
        [void](Revisar-Descarga $Carpeta $version $instalada $pgInstalado)
        [System.IO.File]::WriteAllText((Join-Path $destino 'LISTA'), $version)
    }
    catch {
        Decir "No se pudo bajar la ${version}: $($_.Exception.Message)"
        Borrar-Descarga $Carpeta $version
        # Con un digest distinto la etiqueta podría quedar en otra imagen: se quita (nunca es la instalada).
        if (Id-Imagen "taller-motos:$version") { [void](Correr-Docker @('image', 'rm', "taller-motos:$version") 120) }
        exit 0
    }
    foreach ($otra in @(Get-ChildItem -LiteralPath (Carpeta-Descargas $Carpeta) -Directory | Where-Object { $_.Name -ne $version })) {
        Remove-Item -LiteralPath $otra.FullName -Recurse -Force
        Anotar "Descarga vieja borrada: $($otra.Name)"
    }
    Decir "5. La $version quedó lista en ${destino}: se preguntará al abrir el ícono «Taller»."
    # Se suelta antes del aviso: un clic inmediato en la notificación no debe encontrar la búsqueda en curso.
    Soltar-Mutex $mutex
    $mutex = $null
    # El aviso dentro de la app (Fase 12) lo escribe Version-Pendiente, que decide qué se ofrece.
    try { [void](Version-Pendiente $Carpeta $instalada) } catch { Anotar "Aviso en la app: $($_.Exception.Message)" }
    Avisar-VersionNueva $Carpeta $version   # nunca falla: no cambia el código de salida
    exit 0
}
finally {
    Soltar-Mutex $mutex
}
