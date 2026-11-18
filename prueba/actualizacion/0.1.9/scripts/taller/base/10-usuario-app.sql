-- Usuario de la aplicación en la base del taller (Fase 8, Paso 6). Lo corre la imagen de postgres una sola vez, cuando
-- el volumen de datos está vacío (docker-entrypoint-initdb.d). La app no usa el superusuario (POSTGRES_USER): este
-- usuario es dueño de la base del taller (y así de lo que crean las migraciones) y puede crear bases solo para la
-- prueba de cada copia y para restaurar (CREATEDB), sin ser superusuario (ASVS A01/A05).
-- Los valores llegan por variables del contenedor db (docker-compose.taller.yml); la clave no queda en este archivo.
\getenv usuario TALLER_DB_USUARIO
\getenv clave TALLER_DB_CLAVE
\getenv base POSTGRES_DB

CREATE ROLE :"usuario" LOGIN CREATEDB NOSUPERUSER NOCREATEROLE PASSWORD :'clave';
ALTER DATABASE :"base" OWNER TO :"usuario";
