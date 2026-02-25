# Entorno Docker de Desarrollo

Este entorno levanta la plataforma desde la raíz del repositorio usando `docker-compose.yml` y `Docker/dev.sh`.

## Módulos (Docker/dev.sh)

- `core` (activo por defecto): `postgres`, `solr`, `harvester`, `dashboard-rest`, `shell`
- `vufind` (opcional, on-demand): `vufind-db`, `vufind-web`
- `elastic` (opcional): `elasticsearch`
- `watch` (opcional): `vufind-scss-watch`

Comando de estado:

```bash
./Docker/dev.sh modules status
```

Activar/desactivar módulos:

```bash
./Docker/dev.sh modules on vufind
./Docker/dev.sh modules off vufind
./Docker/dev.sh modules on elastic
./Docker/dev.sh modules off elastic
```

Los toggles se guardan en `./.env`:
- `DEV_MODULE_VUFIND`
- `DEV_MODULE_ELASTIC`
- `DEV_MODULE_WATCH`

## Requisitos

- Docker Engine
- Docker Compose plugin (`docker compose`)
- Git (para clonado automático de `vufind/` cuando se use ese módulo)

## Configuración

Inicialización sugerida:

```bash
cp Docker/.env.example .env
chmod +x Docker/dev.sh
```

Variables relevantes:

- `LR_BUILD_PROFILE` (default `lareferencia`)
- `BUILD_ON_START` (default `smart`, valores: `smart|always|false`)
- `VUFIND_REPO_URL` (default `https://github.com/vufind-org/vufind`)
- `VUFIND_REF` (default `v11.0.1`)
- `VUFIND_THEME` (default `bootstrap5`)

## Arranque rápido

```bash
# 1) Inicializar submódulos de platform (importante para build Java)
./githelper pull

# 2) Levantar stack activo (por módulos)
./Docker/dev.sh up

# 3) Levantar forzando rebuild de imágenes + recompilación Java + migrate DB
./Docker/dev.sh up --build
```

`up --build` ejecuta:
- `docker compose up -d --build ...`
- `BUILD_ON_START=always` para recompilar Java contra el filesystem actual
- `init-db` (`database_migrate`) al finalizar, para dejar schema actualizado

## VuFind on-demand

`vufind/` se clona solo si realmente se necesita (módulo/servicios VuFind):

- `./Docker/dev.sh modules on vufind`
- `./Docker/dev.sh vufind up`
- `./Docker/dev.sh up --vufind`
- `./Docker/dev.sh vufind ...`
- `./Docker/dev.sh solr sync-from-vufind`

`./Docker/dev.sh up` (y `start/restart/build` sin flags/servicios VuFind explícitos) no dispara clone de `vufind/` si falta el checkout.

Si `vufind/` no existe, el script pide repo/ref (o usa defaults de `.env`) y luego sincroniza:

- `vufind/import` -> `Docker/solr/import`
- `vufind/solr/vufind/jars` -> `Docker/solr/jars`

Al ejecutar `./Docker/dev.sh solr sync-from-vufind`, el servicio `solr` se recrea automáticamente para aplicar esos assets.
Al ejecutar `./Docker/dev.sh vufind up` (o `modules on vufind`), también se sincronizan assets de Solr y se recrea `solr`.

## Comandos principales

```bash
./Docker/dev.sh up
./Docker/dev.sh up --build
./Docker/dev.sh up --module vufind
./Docker/dev.sh down
./Docker/dev.sh start
./Docker/dev.sh stop
./Docker/dev.sh restart
./Docker/dev.sh ps
./Docker/dev.sh logs
./Docker/dev.sh health
```

## Core

```bash
./Docker/dev.sh core status
./Docker/dev.sh core up
./Docker/dev.sh core down
```

## DB y shell

```bash
./Docker/dev.sh init-db
./Docker/dev.sh shell-interactive
./Docker/dev.sh shell-interactive database_migrate
```

`init-db` y `shell-interactive` usan el contenedor `lr-shell` existente (via `docker compose exec`) y no crean contenedores temporales `shell-run-*`.

## VuFind

```bash
./Docker/dev.sh vufind status
./Docker/dev.sh vufind up
./Docker/dev.sh vufind down
./Docker/dev.sh vufind debug show
./Docker/dev.sh vufind debug on
./Docker/dev.sh vufind debug off
./Docker/dev.sh vufind theme show
./Docker/dev.sh vufind theme set bootstrap5
./Docker/dev.sh vufind db
./Docker/dev.sh vufind cli <args...>
./Docker/dev.sh vufind shell web
```

## Elastic y Watch

```bash
./Docker/dev.sh elastic status
./Docker/dev.sh elastic up
./Docker/dev.sh elastic down
./Docker/dev.sh elastic logs

./Docker/dev.sh watch status
./Docker/dev.sh watch up
./Docker/dev.sh watch down
./Docker/dev.sh watch logs
```

## Limpieza de datos

```bash
./Docker/dev.sh reset-data
./Docker/dev.sh reset-data --yes
```

`reset-data` limpia solo data persistida no versionada en `Docker/data`.
Los archivos trackeados por git dentro de esa carpeta se conservan.

## Endpoints locales

- VuFind: `http://localhost:8080`
- Harvester: `http://localhost:8090`
- Dashboard REST: `http://localhost:8092`
- Solr Admin: `http://localhost:8983/solr`
