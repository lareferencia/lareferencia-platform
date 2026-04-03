# Entorno Docker de Desarrollo

Este entorno levanta la plataforma desde la raíz del repositorio usando `docker-compose.yml` y `Docker/docker.sh`.

## Módulos (Docker/docker.sh)

- `core` (activo por defecto): `postgres`, `solr`, `harvester`, `dashboard-rest`, `shell`
- `vufind` (opcional, on-demand): `vufind-db`, `vufind-web`
- `elastic` (opcional): `elasticsearch`
- `watch` (opcional): `vufind-scss-watch`

Comando de estado:

```bash
./Docker/docker.sh modules status
```

Activar/desactivar módulos:

```bash
./Docker/docker.sh modules on vufind
./Docker/docker.sh modules off vufind
./Docker/docker.sh modules on elastic
./Docker/docker.sh modules off elastic
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
chmod +x Docker/docker.sh
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
./Docker/docker.sh up

# 3) Levantar forzando rebuild de imágenes + recompilación Java + migrate DB
./Docker/docker.sh up --build
```

`up --build` ejecuta:
- `docker compose up -d --build ...`
- `BUILD_ON_START=always` para recompilar Java contra el filesystem actual
- `init-db` (`database_migrate`) al finalizar, para dejar schema actualizado

## VuFind on-demand

`vufind/` se clona solo si realmente se necesita (módulo/servicios VuFind):

- `./Docker/docker.sh modules on vufind`
- `./Docker/docker.sh vufind up`
- `./Docker/docker.sh up --vufind`
- `./Docker/docker.sh vufind ...`
- `./Docker/docker.sh solr sync-from-vufind`

`./Docker/docker.sh up` (y `start/restart/build` sin flags/servicios VuFind explícitos) no dispara clone de `vufind/` si falta el checkout.

Si `vufind/` no existe, el script pide repo/ref (o usa defaults de `.env`) y luego sincroniza:

- `vufind/import` -> `Docker/solr/import`
- `vufind/solr/vufind/jars` -> `Docker/solr/jars`

Al ejecutar `./Docker/docker.sh solr sync-from-vufind`, el servicio `solr` se recrea automáticamente para aplicar esos assets.
Al ejecutar `./Docker/docker.sh vufind up` (o `modules on vufind`), también se sincronizan assets de Solr y se recrea `solr`.

## Comandos principales

```bash
./Docker/docker.sh up
./Docker/docker.sh up --build
./Docker/docker.sh up --module vufind
./Docker/docker.sh down
./Docker/docker.sh start
./Docker/docker.sh stop
./Docker/docker.sh restart
./Docker/docker.sh ps
./Docker/docker.sh logs
./Docker/docker.sh health
```

## Core

```bash
./Docker/docker.sh core status
./Docker/docker.sh core up
./Docker/docker.sh core down
```

## DB y shell

```bash
./Docker/docker.sh init-db
./Docker/docker.sh shell-interactive
./Docker/docker.sh shell-interactive database_migrate
```

`init-db` y `shell-interactive` usan el contenedor `lr-shell` existente (via `docker compose exec`) y no crean contenedores temporales `shell-run-*`.

## VuFind

```bash
./Docker/docker.sh vufind status
./Docker/docker.sh vufind up
./Docker/docker.sh vufind down
./Docker/docker.sh vufind debug show
./Docker/docker.sh vufind debug on
./Docker/docker.sh vufind debug off
./Docker/docker.sh vufind theme show
./Docker/docker.sh vufind theme set bootstrap5
./Docker/docker.sh vufind db
./Docker/docker.sh vufind cli <args...>
./Docker/docker.sh vufind shell web
```

## Elastic y Watch

```bash
./Docker/docker.sh elastic status
./Docker/docker.sh elastic up
./Docker/docker.sh elastic down
./Docker/docker.sh elastic logs

./Docker/docker.sh watch status
./Docker/docker.sh watch up
./Docker/docker.sh watch down
./Docker/docker.sh watch logs
```

## Limpieza de datos

```bash
./Docker/docker.sh reset-data
./Docker/docker.sh reset-data --yes
```

`reset-data` limpia solo data persistida no versionada en `Docker/data`.
Los archivos trackeados por git dentro de esa carpeta se conservan.

## Endpoints locales

- VuFind: `http://localhost:8080`
- Harvester: `http://localhost:8090`
- Dashboard REST: `http://localhost:8092`
- Solr Admin: `http://localhost:8983/solr`
