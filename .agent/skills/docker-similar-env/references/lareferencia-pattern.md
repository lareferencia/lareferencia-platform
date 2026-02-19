# Lareferencia Docker Pattern (Source Blueprint)

Este documento resume el patron real extraido de este repositorio para reutilizarlo en otros proyectos.

## Topologia De Servicios

- `vufind-web`: PHP + Apache, monta `./vufind`, configura VuFind y depende de MariaDB + Solr.
- `vufind-db`: MariaDB dedicada para VuFind.
- `solr`: imagen custom con cores `biblio` y `oai`.
- `postgres`: Postgres para servicios Java.
- `harvester`: app Java empaquetada por modulo.
- `dashboard-rest`: app Java empaquetada por modulo.
- `shell`: app Java en perfil `tools` para tareas operativas.
- `elasticsearch`: opcional en perfil `elastic`.
- `vufind-scss-watch`: opcional en perfil `watch`.

## Puertos Locales Del Stack Base

- `8080`: VuFind
- `8090`: Harvester
- `8092`: Dashboard REST
- `8983`: Solr
- `3307`: MariaDB (mapeo local)
- `5432`: Postgres
- `9200/9300`: Elasticsearch (perfil opcional)

## Estructura Docker/

- `Docker/dev.sh`: interfaz operacional principal.
- `Docker/apps/`: Dockerfile base Maven + entrypoint generico para apps Java.
- `Docker/vufind/`: Dockerfile/entrypoint para inicializar VuFind.
- `Docker/solr/`: Dockerfile/entrypoint para inicializar cores y assets.
- `Docker/config-overrides/`: overrides por modulo en `99-docker.properties`.
- `Docker/data/`: persistencia y caches locales.

## Patron De EntryPoint Java (Docker/apps/entrypoint.sh)

- Recibir `APP_MODULE`, `APP_JAR`, `APP_CONFIG_DIR`.
- Construir artefacto solo cuando falta el jar y `BUILD_ON_START=true`.
- Clonar config runtime a ruta temporal.
- Inyectar `99-docker.properties` como JVM props `-Dkey=value`.
- Arrancar con `-Dapp.config.dir=<runtime-config>`.

## Patron De EntryPoint VuFind (Docker/vufind/entrypoint.sh)

- Crear directorio local docker de VuFind si no existe.
- Instalar dependencias Composer cuando falta `vendor/autoload.php`.
- Ejecutar instalador de VuFind una sola vez (`.installed`).
- Forzar valores de `config.ini` y `NoILS.ini` desde variables de entorno.
- Esperar DB + Solr antes de terminar bootstrap.
- Inicializar esquema DB de VuFind si no existe.

## Patron De EntryPoint Solr (Docker/solr/entrypoint.sh)

- Inicializar cores `biblio` y `oai` solo la primera vez (`.lr_initialized`).
- Copiar jars e import assets a rutas esperadas por indexacion.
- Configurar modulos Solr y hardening minimo (`disable.configEdit=true`).

## Capacidades Del Wrapper Docker/dev.sh

- Ciclo de vida: `up`, `down`, `start`, `stop`, `restart`, `build`, `pull`, `ps`, `logs`.
- Salud: `health` revisa estado compose + HTTP endpoints.
- Plataforma: `init-db`, `shell-interactive`, `shell`, `exec`, `compose`.
- VuFind: `debug on/off/show`, `theme set/show`, `db`, `cli`, `shell`.
- Solr: `sync-from-vufind`, `status`.
- Opcionales: `elastic on/off/logs/status`, `watch start/stop/logs/status`.
- Seguridad: `reset-data` con confirmacion y borrado restringido a `Docker/data`.

## Bootstrap Externo Reutilizable

Si falta una dependencia externa versionada (en este caso `./vufind`), el wrapper:

1. Leer defaults desde `.env`.
2. Preguntar repo/ref en modo interactivo.
3. Clonar repo en ruta local.
4. Sincronizar assets derivados que otras imagenes necesitan.

Este patron evita pasos manuales post-clone en equipos nuevos.

## Lecciones Reutilizables

- Usar un solo comando `dev.sh` reduce friccion de onboarding.
- Separar perfiles opcionales evita consumir recursos por defecto.
- Mantener caches (Maven/Composer/npm) en bind mounts acelera ciclos locales.
- Inyectar overrides como JVM properties evita tocar config fuente.
