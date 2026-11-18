# Actualizar el taller con un paquete «instalador» nuevo (Fase 8, Paso 7). Lo abre instalar.cmd cuando ya hay otra
# versión instalada (o se corre este script desde la carpeta del paquete nuevo). Pasos:
#   1. Revisa el paquete (huellas de las imágenes y de cada archivo) y que el taller instalado esté sano; carga las
#      imágenes nuevas (o, si se bajaron por internet, comprueba que estén por su digest firmado).
#   2. Copia antes: detiene la app, que hace su copia al cerrar (cifrada y probada), y comprueba en la base que salió
#      bien. Sin copia buena no sigue y vuelve a encender lo de antes.
#   3. Guarda el compose y los scripts instalados en anterior\, pone los nuevos y la versión en el .env.
#   4. PostgreSQL: con la misma versión mayor (18.x -> 18.y) se recrea la base con el mismo volumen. Con otra mayor
#      (18 -> 19) los datos no sirven tal cual: se levanta la base nueva en su propio volumen (datos-pg<mayor>) y se
#      pasan con pg_dump | pg_restore en una sola transacción; el volumen de la versión anterior no se toca.
#   5. Enciende y espera la salud. Si falla, vuelve a la versión anterior (compose, scripts, versión y, con otra
#      mayor, su volumen intacto) y lo dice. Si sale bien, borra las imágenes taller-motos viejas (menos la anterior).
# También lo corre abrir.ps1 desde descargas\<versión>\ (versión bajada por internet), con -YaConfirmado porque ya
# preguntó. Código de salida: 0 actualizado (o nada que hacer), 1 no se cambió nada, 3 se probó y volvió atrás
# (abrir.ps1 no vuelve a ofrecer esa versión).
# Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File actualizar.ps1 [-Seco [-ConVentanas]] [-Carpeta <instalación>] [-YaConfirmado]
param(
    [string]$Carpeta = '',
    [switch]$Seco,
    [switch]$ConVentanas,
    [switch]$YaConfirmado
)
. (Join-Path $PSScriptRoot 'comun.ps1')
Preparar-Comun -Seco:$Seco -ConVentanas:$ConVentanas
if (-not $Carpeta) { $Carpeta = $CarpetaPorDefecto }
$origen = Raiz-Del-Paquete
$archivoEnv = Join-Path $Carpeta '.env'
$composeInstalado = Join-Path $Carpeta 'docker-compose.taller.yml'
$composePaquete = Join-Path $origen 'docker-compose.taller.yml'
$anterior = Join-Path $Carpeta 'anterior'

function Fallar([string]$texto, [int]$codigo = 1) {
    Cerrar-Progreso
    Anotar-Estado $Carpeta
    $detalle = if ($script:Registro) { "`n`nEl detalle quedó en $($script:Registro)." } else { '' }
    Mostrar-Mensaje "$texto$detalle" 'Error'
    exit $codigo
}

# --- Qué hay y qué trae el paquete ---
$paquete = Leer-Paquete $origen
if ($paquete) { $versionNueva = $paquete.version }
elseif ($Seco) {
    $versionNueva = (Get-Content (Join-Path $origen 'servidor\package.json') -Raw | ConvertFrom-Json).version
    Decir "Sin paquete.json (se corre desde el repositorio): en seco se saltan las imágenes; versión $versionNueva."
}
else { Mostrar-Mensaje "Falta paquete.json en $origen. Use la carpeta «instalador» completa." 'Error'; exit 1 }

$instalado = Test-Path $archivoEnv
if (-not $instalado) {
    if (-not $Seco) { Mostrar-Mensaje "No hay un taller instalado en $Carpeta. Use instalar.cmd." 'Error'; exit 1 }
    Decir "No hay instalación en ${Carpeta}: en seco se compara el paquete consigo mismo (versión 0.0.0 instalada)."
    $composeInstalado = $composePaquete
}
Iniciar-Registro $Carpeta 'actualizar'
$valores = Leer-Env $archivoEnv
$versionVieja = if ($instalado) { [string]$valores['TALLER_VERSION'] } else { '0.0.0' }
$pgViejo = Etiqueta-Postgres $composeInstalado
$pgNuevo = Etiqueta-Postgres $composePaquete
$claveVieja = Clave-Volumen-Base $composeInstalado
$claveNueva = Clave-Volumen-Base $composePaquete
$proyecto = Nombre-Proyecto $valores $composeInstalado
$volViejo = "${proyecto}_$claveVieja"
$volNuevo = "${proyecto}_$claveNueva"
$mayor = (Mayor-Postgres $pgNuevo) -ne (Mayor-Postgres $pgViejo)
$equipo = Puerto-Equipo $valores
Anotar "Instalada $versionVieja (postgres $pgViejo, $volViejo); paquete $versionNueva (postgres $pgNuevo, $volNuevo)"

if ((Mayor-Postgres $pgNuevo) -lt (Mayor-Postgres $pgViejo)) {
    Fallar "El paquete trae PostgreSQL $pgNuevo, más viejo que el instalado ($pgViejo). No se cambió nada."
}
if ($mayor -and $claveNueva -eq $claveVieja) {
    Fallar "El paquete cambia PostgreSQL de $pgViejo a $pgNuevo pero usa el mismo volumen ($claveVieja). Para el técnico: el compose nuevo tiene que usar datos-pg$(Mayor-Postgres $pgNuevo). No se cambió nada."
}
if (-not $mayor -and $claveNueva -ne $claveVieja) {
    Fallar "El paquete cambia el volumen de la base ($claveVieja -> $claveNueva) sin cambiar la versión mayor de PostgreSQL: los datos quedarían atrás. No se cambió nada."
}
if ($instalado -and $versionNueva -eq $versionVieja -and $pgNuevo -eq $pgViejo) {
    Mostrar-Mensaje "El taller ya está en la versión $versionNueva. No hay nada que actualizar." 'Info'
    exit 0
}

$cambioBase = if ($pgNuevo -eq $pgViejo) { '' } elseif ($mayor) { " y la base de PostgreSQL de $pgViejo a $pgNuevo (versión mayor: los datos se pasan a una base nueva)" } else { " y la base de PostgreSQL de $pgViejo a $pgNuevo" }
$texto = "Se va a actualizar el taller de la versión $versionVieja a la $versionNueva$cambioBase.`n`nAntes se hace una copia de la base. Mientras tanto el taller no se puede usar (unos minutos). ¿Seguir?"
if ($YaConfirmado) { Anotar "Ya confirmado (abrir.ps1): $($texto -replace "`r?`n", ' ')" }
elseif (-not (Preguntar-SiNo $texto)) { Mostrar-Mensaje 'No se cambió nada.' 'Info'; exit 0 }
# La URL de la actualización por internet: la trae el paquete de la USB si el .env todavía no la tiene.
$urlNueva = if ($paquete -and $paquete.actualizacionUrl -and -not $valores.ContainsKey('ACTUALIZACION_URL')) { [string]$paquete.actualizacionUrl } else { '' }
if ($urlNueva -and -not (Url-Actualizacion-Valida $urlNueva)) { Anotar "actualizacionUrl del paquete no sirve: $urlNueva"; $urlNueva = '' }
$conservar = @(@($versionNueva, $versionVieja) + @(Descargas-Listas $Carpeta) | Select-Object -Unique)

$dc = Argumentos-Compose $Carpeta
$temporal = "$proyecto-pg-anterior"
if ($Seco) {
    Decir 'Pasos que se harían:'
    Decir "  1. Encender Docker si hace falta; revisar las huellas del paquete; ver que el taller responda en http://127.0.0.1:$equipo/api/salud (si no, docker $($dc -join ' ') up -d)."
    if ($mayor) { Decir "     Comprobar que el volumen $volNuevo no exista (sería de un intento anterior)." }
    Decir "  2. Cargar: $(if ($paquete) { ($paquete.imagenes | ForEach-Object { if ($_.digest) { "$($_.etiqueta) (ya bajada: comprobar $($_.origen)@$($_.digest))" } else { $_.etiqueta } }) -join ', ' } else { '(sin paquete)' })"
    Decir "  3. Copia antes: docker $($dc -join ' ') stop app (copia al cerrar) y buscar en la tabla copia una buena desde ese momento."
    Decir "  4. Guardar el compose y los scripts en $anterior; copiar los del paquete; TALLER_VERSION=$versionNueva$(if ($urlNueva) { "; ACTUALIZACION_URL=$urlNueva" })."
    if ($mayor) {
        Decir "  5. PostgreSQL $pgViejo -> ${pgNuevo}: up -d --wait db (volumen nuevo $volNuevo); contenedor $temporal con postgres:$pgViejo y $volViejo;"
        Decir "     pg_dump -Fc -h $temporal | pg_restore --no-owner --no-privileges --exit-on-error --single-transaction -h db (con el usuario de la app); borrar $temporal."
    }
    elseif ($pgNuevo -ne $pgViejo) { Decir "  5. PostgreSQL $pgViejo -> ${pgNuevo}: up -d recrea db con el mismo volumen $volViejo." }
    Decir "  6. docker $($dc -join ' ') up -d y esperar la salud hasta 5 min."
    Decir "  7. Si falla: volver a poner lo de $anterior y TALLER_VERSION=$versionVieja, up -d$(if ($mayor) { ", borrar $volNuevo ($volViejo sigue intacto)" })."
    Decir '  8. Si sale bien: volver a crear los íconos (así llegan los nuevos de esta versión):'
    Crear-Accesos $Carpeta
    Decir "  9. Si sale bien: borrar las imágenes taller-motos que no sean $($conservar -join ', ')."
    if (Docker-Listo) {
        Decir "Docker: encendido. Taller instalado respondiendo: $(if (App-Sana $equipo) { 'sí' } else { 'no' })."
        if ($mayor) { Decir "Volumen nuevo ya existe: $(if ((Correr-Docker @('volume', 'inspect', $volNuevo) 30 -SinRegistro).Codigo -eq 0) { 'SÍ (se detendría)' } else { 'no' })." }
    }
    if ($paquete) {
        try { Verificar-Imagenes-Paquete $paquete $origen; Decir 'Huellas de las imágenes: OK.' }
        catch { Decir "Huellas: $($_.Exception.Message)" }
        try { Verificar-Archivos-Paquete $paquete $origen; Decir "Huellas de los archivos: OK ($(@($paquete.archivos).Count))." }
        catch { Decir "Huellas: $($_.Exception.Message)" }
        if (Docker-Listo) {
            foreach ($i in @($paquete.imagenes | Where-Object { $_.digest })) {
                Decir "Imagen $($i.etiqueta) por su digest: $(if (Imagen-Lista $i) { 'está' } else { 'NO está (se bajaría otra vez)' })."
            }
        }
    }
    exit 0
}

# ==== 1. Revisar ====================================================================================================
Abrir-Progreso 'Preparando la actualización…'
if (-not (Encender-Docker 300)) { Fallar "No se pudo actualizar.`n`n$(Explicar-Docker-Apagado)" }
try {
    Verificar-Archivos-Paquete $paquete $origen
    Verificar-Imagenes-Paquete $paquete $origen
}
catch { Fallar $_.Exception.Message }
if ($mayor -and (Correr-Docker @('volume', 'inspect', $volNuevo) 30 -SinRegistro).Codigo -eq 0) {
    Fallar "Ya existe el volumen $volNuevo, de un intento anterior de actualizar la base. Para el técnico: si el taller funciona con la versión instalada, bórrelo con «docker volume rm $volNuevo» y vuelva a correr la actualización. No se cambió nada."
}
if (-not (App-Sana $equipo)) {
    Cambiar-Progreso 'Encendiendo el taller instalado…'
    [void](Correr-Docker ($dc + @('up', '-d')) 300)
    if (-not (Esperar-Salud $equipo 240)) { Fallar 'El taller instalado no está respondiendo, así que no se puede hacer la copia de antes. No se cambió nada.' }
}
try { Cargar-Imagenes $paquete $origen } catch { Fallar "$($_.Exception.Message) No se cambió nada." }

# ==== 2. Copia antes ================================================================================================
Cambiar-Progreso 'Haciendo la copia de la base antes de actualizar…'
try {
    $desde = Consultar-Base $Carpeta $valores "SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.MS')"
    $migracionesAntes = [int](Consultar-Base $Carpeta $valores 'SELECT count(*) FROM _prisma_migrations WHERE finished_at IS NOT NULL')
}
catch { Fallar "$($_.Exception.Message) No se cambió nada." }
$r = Correr-Docker ($dc + @('stop', 'app')) 180
$copia = ''
if ($r.Codigo -eq 0) {
    try {
        $copia = Consultar-Base $Carpeta $valores ("SELECT archivo FROM copia WHERE inicio >= '$desde' AND resultado IN ('COMPLETA', 'PARCIAL') " +
            'AND prueba_buena ORDER BY inicio DESC LIMIT 1')
    }
    catch { Anotar $_.Exception.Message }
}
if (-not $copia) {
    [void](Correr-Docker ($dc + @('up', '-d', 'app')) 300)
    Fallar 'No salió bien la copia de la base antes de actualizar, así que no se actualizó: el taller sigue con la versión de antes. Revise «Copias».'
}
Anotar "Copia antes de actualizar: $copia"

# ==== 3. Archivos nuevos (lo de antes queda en anterior\) ===========================================================
Cambiar-Progreso 'Poniendo la versión nueva…'
if (Test-Path $anterior) { Remove-Item -Recurse -Force $anterior }
New-Item -ItemType Directory -Force -Path $anterior | Out-Null
foreach ($a in $ArchivosInstalados) {
    $desdeArchivo = Join-Path $Carpeta $a
    $hastaArchivo = Join-Path $anterior $a
    New-Item -ItemType Directory -Force -Path (Split-Path $hastaArchivo) | Out-Null
    Copy-Item -Recurse -Force $desdeArchivo $hastaArchivo
}

function Volver-Atras([string]$motivo) {
    Anotar "Volviendo a la versión anterior: $motivo"
    Cambiar-Progreso 'Algo salió mal: volviendo a la versión anterior…'
    if ($mayor) { [void](Correr-Docker @('rm', '-f', $temporal) 60) }
    foreach ($a in $ArchivosInstalados) {
        $hastaArchivo = Join-Path $Carpeta $a
        if (Test-Path $hastaArchivo) { Remove-Item -Recurse -Force $hastaArchivo }
        Copy-Item -Recurse -Force (Join-Path $anterior $a) $hastaArchivo
    }
    Cambiar-Env $archivoEnv 'TALLER_VERSION' $versionVieja
    # up recrea db con la imagen y el volumen de antes (con otra mayor, el de antes nunca se tocó).
    $r = Correr-Docker ($dc + @('up', '-d')) 600
    $sana = ($r.Codigo -eq 0) -and (Esperar-Salud $equipo 300)
    if ($mayor) {
        $b = Correr-Docker @('volume', 'rm', $volNuevo) 60
        Anotar "Volumen nuevo borrado: $($b.Codigo -eq 0)"
    }
    $texto = "No se pudo actualizar: $motivo`n`n"
    if ($sana) {
        $texto += "El taller volvió a la versión $versionVieja con sus datos."
        if (-not $mayor) {
            try {
                $migracionesAhora = [int](Consultar-Base $Carpeta $valores 'SELECT count(*) FROM _prisma_migrations WHERE finished_at IS NOT NULL')
                if ($migracionesAhora -gt $migracionesAntes) {
                    $texto += " La versión nueva alcanzó a cambiar la base: si algo no anda bien, el técnico puede restaurar la copia $copia con restaurar.ps1."
                }
            }
            catch { Anotar $_.Exception.Message }
        }
    }
    else { $texto += "El taller tampoco encendió con la versión anterior. La copia de antes es $copia. Avise al técnico." }
    Fallar $texto 3
}

try {
    Copiar-Archivos $origen $Carpeta
    Cambiar-Env $archivoEnv 'TALLER_VERSION' $versionNueva
    # La versión anterior no la usa: puede quedar aunque se vuelva atrás.
    if ($urlNueva) { Cambiar-Env $archivoEnv 'ACTUALIZACION_URL' $urlNueva }
}
catch { Volver-Atras "no se pudieron copiar los archivos nuevos ($($_.Exception.Message))." }

# ==== 4. PostgreSQL de otra versión mayor: pasar los datos a su volumen nuevo =======================================
if ($mayor) {
    Cambiar-Progreso "Pasando los datos a PostgreSQL $pgNuevo (puede tardar)…"
    $r = Correr-Docker ($dc + @('up', '-d', '--wait', '--wait-timeout', '180', 'db')) 240
    if ($r.Codigo -ne 0) { Volver-Atras "la base PostgreSQL $pgNuevo no encendió." }
    [void](Correr-Docker @('rm', '-f', $temporal) 60)
    $r = Correr-Docker @('run', '-d', '--name', $temporal, '--network', "${proyecto}_default", '-v', "${volViejo}:/var/lib/postgresql", "postgres:$pgViejo") 120
    if ($r.Codigo -ne 0) { Volver-Atras "no se pudo abrir la base anterior ($pgViejo)." }
    $lista = $false
    for ($i = 0; $i -lt 30 -and -not $lista; $i++) {
        Esperar 2
        $lista = (Correr-Docker @('exec', $temporal, 'pg_isready', '-U', $valores['POSTGRES_USER'], '-d', $valores['POSTGRES_DB']) 15 -SinRegistro).Codigo -eq 0
    }
    if (-not $lista) { Volver-Atras "la base anterior ($pgViejo) no respondió." }
    # Con el usuario de la app (dueño de todo en las dos bases); la clave va por variable, no en los argumentos.
    $pasar = "set -o pipefail; pg_dump -Fc -h $temporal | pg_restore --no-owner --no-privileges --exit-on-error --single-transaction -h db -d `"`$PGDATABASE`""
    $r = Correr-Docker ($dc + @('run', '--rm', '--no-deps', '-T', '-e', 'PGUSER', '-e', 'PGPASSWORD', '-e', 'PGDATABASE', 'app', 'sh', '-c', $pasar)) 3600 -Entorno @{
        PGUSER = $valores['TALLER_DB_USUARIO']; PGPASSWORD = $valores['TALLER_DB_CLAVE']; PGDATABASE = $valores['POSTGRES_DB']
    }
    [void](Correr-Docker @('rm', '-f', $temporal) 60)
    if ($r.Codigo -ne 0) { Volver-Atras "no se pudieron pasar los datos a PostgreSQL $pgNuevo ($(Ultima-Linea $r.Error))." }
}

# ==== 5. Encender ===================================================================================================
Cambiar-Progreso 'Encendiendo la versión nueva…'
$r = Correr-Docker ($dc + @('up', '-d')) 600
if ($r.Codigo -ne 0) { Volver-Atras 'la versión nueva no encendió.' }
Cambiar-Progreso 'Esperando a que el taller responda…'
if (-not (Esperar-Salud $equipo 300)) { Volver-Atras 'la versión nueva no respondió.' }
# Los íconos de la versión nueva (por ejemplo, «Cambiar carpetas de copias» desde 0.1.3).
Crear-Accesos $Carpeta
Cambiar-Progreso 'Borrando las versiones viejas que ya no hacen falta…'
try { Borrar-Imagenes-Viejas $conservar } catch { Anotar "No se borraron las imágenes viejas: $($_.Exception.Message)" }

Cerrar-Progreso
$final = "Listo: el taller quedó en la versión $versionNueva.`n`nLa copia de antes de actualizar es $copia."
if ($mayor) { $final += "`n`nLa base anterior (PostgreSQL $pgViejo) quedó guardada en el volumen $volViejo por si hace falta; el técnico la puede borrar cuando todo ande bien." }
Mostrar-Mensaje $final 'Info'
exit 0
