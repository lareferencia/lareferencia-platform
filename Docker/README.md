# Entorno Docker de Desarrollo

Este entorno levanta la plataforma completa desde la raíz del repositorio usando `docker-compose.yml` y el helper `Docker/dev.sh`.

## Componentes

- VuFind Web (`vufind-web`)
- MariaDB para VuFind (`vufind-db`)
- Solr con cores `biblio` y `oai` (`solr`)
- PostgreSQL para servicios Java (`postgres`)
- Harvester (`harvester`)
- Dashboard REST (`dashboard-rest`)
- Shell de administración (`shell`, bajo perfil `tools`)
- Elasticsearch opcional (`elasticsearch`, bajo perfil `elastic`)
- Watcher de SCSS opcional (`vufind-scss-watch`, bajo perfil `watch`)

## Requisitos

- Docker Engine
- Docker Compose plugin (`docker compose`)
- Git (para clonado automático de `vufind/` cuando no exista)

## Estructura relevante

- `docker-compose.yml`
- `Docker/dev.sh`
- `Docker/.env.example`
- `Docker/apps/`
- `Docker/solr/`
- `Docker/vufind/`
- `Docker/config-overrides/`
- `Docker/data/`

## Configuración

El script usa el archivo `./.env` en la raíz del repositorio.

Inicialización sugerida:

```bash
cp Docker/.env.example .env
chmod +x Docker/dev.sh
```

Variables principales:

- `LR_BUILD_PROFILE` (default `lareferencia`)
- `BUILD_ON_START` (default `true`)
- `VUFIND_THEME` (default `bootstrap5`)
- `VUFIND_ENV` (default `production`)
- `VUFIND_SYSTEM_DEBUG` (default `false`)
- `VUFIND_PHP_DISPLAY_ERRORS` (default `0`)
- `VUFIND_REPO_URL` (default `https://github.com/vufind-org/vufind`)
- `VUFIND_REF` (default `v11.0.1`)

## Arranque rápido

```bash
# 1) Levantar stack principal
./Docker/dev.sh up --build

# 2) Inicializar/migrar base PostgreSQL usando lareferencia-shell
./Docker/dev.sh init-db

# 3) Verificar estado
./Docker/dev.sh health
```

Endpoints locales:

- VuFind: `http://localhost:8080`
- Harvester: `http://localhost:8090`
- Dashboard REST: `http://localhost:8092`
- Solr Admin: `http://localhost:8983/solr`

## Clonado automático de VuFind

Si el directorio `vufind/` no existe, `Docker/dev.sh` hace lo siguiente antes de ejecutar el comando solicitado:

- pregunta repositorio GitHub (con default `VUFIND_REPO_URL`)
- pregunta branch/tag (con default `VUFIND_REF`)
- ejecuta `git clone --branch <ref> --single-branch <repo> vufind/`
- sincroniza `vufind/import` -> `Docker/solr/import`
- sincroniza `vufind/solr/vufind/jars` -> `Docker/solr/jars`

## Operación diaria

```bash
# levantar / bajar
./Docker/dev.sh up
./Docker/dev.sh down

# iniciar / detener / reiniciar
./Docker/dev.sh start
./Docker/dev.sh stop
./Docker/dev.sh restart

# build / pull
./Docker/dev.sh build
./Docker/dev.sh pull

# estado y logs
./Docker/dev.sh ps
./Docker/dev.sh logs
./Docker/dev.sh logs solr -f
./Docker/dev.sh health
```

## Comandos de plataforma

```bash
# migración no interactiva (default: database_migrate)
./Docker/dev.sh init-db
./Docker/dev.sh init-db <comando-shell>

# shell interactivo de lareferencia-shell
./Docker/dev.sh shell-interactive
./Docker/dev.sh shell-interactive <comando-shell>

# shell interactivo dentro de un servicio
./Docker/dev.sh shell vufind-web
./Docker/dev.sh shell postgres

# ejecutar comando directo dentro de un servicio
./Docker/dev.sh exec harvester <cmd>

# pasar argumentos crudos a docker compose
./Docker/dev.sh compose <args...>
```

## Solr

```bash
# sincronización manual de import/jars desde vufind
./Docker/dev.sh solr sync-from-vufind

# estado rápido de fuentes/destinos
./Docker/dev.sh solr status
```

## VuFind

```bash
# debug
./Docker/dev.sh vufind debug show
./Docker/dev.sh vufind debug on
./Docker/dev.sh vufind debug off

# theme
./Docker/dev.sh vufind theme show
./Docker/dev.sh vufind theme set bootstrap5

# DB VuFind
./Docker/dev.sh vufind db

# CLI VuFind
./Docker/dev.sh vufind cli <args...>

# shells de servicios VuFind
./Docker/dev.sh vufind shell web
./Docker/dev.sh vufind shell db
./Docker/dev.sh vufind shell solr
```

## Perfiles opcionales

```bash
# elasticsearch
./Docker/dev.sh elastic on
./Docker/dev.sh elastic off
./Docker/dev.sh elastic logs
./Docker/dev.sh elastic status

# watcher SCSS
./Docker/dev.sh watch start
./Docker/dev.sh watch stop
./Docker/dev.sh watch logs
./Docker/dev.sh watch status

# levantar con perfiles al inicio
./Docker/dev.sh up --elastic
./Docker/dev.sh up --watch
```

## Datos persistentes

- Toda la persistencia usa bind mounts en `Docker/data/*`.
- El reset completo se hace con:

```bash
./Docker/dev.sh reset-data
./Docker/dev.sh reset-data --yes
```

## Notas de versionado

- `Docker/data/**` se ignora en git, excepto `*.gitkeep`.
- `Docker/solr/import/**` y `Docker/solr/jars/**` se ignoran en git, excepto `*.gitkeep`.
