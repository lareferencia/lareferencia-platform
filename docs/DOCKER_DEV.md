# Developer Docker Mode

`Docker/docker-dev.sh` provides an isolated development workflow for the LA Referencia platform. It is intentionally independent from `Docker/docker.sh`: the normal Docker wizard, the original Compose file, existing Dockerfiles, and existing entrypoints remain unchanged.

## Components

The developer workflow adds four files:

- `Docker/docker-dev.sh`: developer wizard and command-line interface.
- `docker-compose.dev.yml`: Compose overlay loaded together with `docker-compose.yml`.
- `Docker/apps/Dockerfile.dev`: Java 17 runtime image; it does not copy source code or JARs.
- `Docker/apps/entrypoint-dev.sh`: starts the locally mounted JAR and prepares runtime configuration.

The overlay also defines a `maven-builder` service. It mounts the repository at `/workspace` and keeps Maven dependencies in the named `lr-maven-cache-dev` volume.

## Instance modes

The default mode is `isolated`. It uses its own project name, ports, and persistent data:

```text
Project: lareferencia-dev
Port offset: 100
Data: Docker/volume/dev/lareferencia-dev
```

The optional `normal` mode reuses the normal platform's project, ports, and data. Use it only when deliberately testing against the existing installation. The destructive `clean` command is blocked in this mode.

Switch modes with:

```bash
./Docker/docker-dev.sh instance isolated
./Docker/docker-dev.sh instance normal
```

Local settings are stored in `Docker/.env.dev`. This file is local-only and is excluded through Git's local exclude configuration.

## Module selection

The developer wizard follows the normal wizard's defaults. By default it enables:

- Core (PostgreSQL)
- Solr
- Harvester
- VuFind
- OAI-PMH

Dashboard, Entity REST, Shell, Elasticsearch, and the VuFind SCSS watcher are disabled by default. Select modules from the wizard's **Manage Modules (on/off)** action. The selection is persisted in `Docker/.env.dev`.

When Harvester is enabled, `admin-web-dev` is started by default as well. It
runs Vite with hot-module replacement on port `5273` in an isolated instance
(`5173 + SERVICES_PORT_OFFSET`) and proxies `/api/v5` to the developer
Harvester. Open `http://localhost:5273` to work on React code; source changes
are reflected without a Maven build.

Dependencies are added automatically: Harvester, Shell, and VuFind require Solr; Java services requiring PostgreSQL also bring Core.

Starting without service arguments starts only the selected modules:

```bash
./Docker/docker-dev.sh up
```

## Java build and runtime flow

Java applications are compiled inside `maven-builder`, but the source tree is the local repository. The resulting JAR remains in each module's local `target` directory. Developer runtime containers mount the repository read-only and execute that JAR directly.

Build all Java applications:

```bash
./Docker/docker-dev.sh build all
```

Rebuild one application and restart only its container:

```bash
./Docker/docker-dev.sh rebuild harvester
./Docker/docker-dev.sh rebuild entity-rest
./Docker/docker-dev.sh rebuild dashboard-rest
./Docker/docker-dev.sh rebuild oai-pmh
```

## Harvester admin web

The React admin application is a separate cycle. Its Maven module builds the frontend and copies the generated `dist` output into the Harvester application's `static` directory. A frontend-only change therefore does not recompile the Harvester Java code:

```bash
./Docker/docker-dev.sh rebuild frontend
```

This rebuilds the frontend and restarts only `harvester`. `rebuild admin-web` is an alias. The existing container is restarted in place; it is only created with `up` when it does not exist yet.

Start or restart the live Vite server independently with:

```bash
./Docker/docker-dev.sh frontend-dev
```

Harvester Java changes use the normal Java cycle:

```bash
./Docker/docker-dev.sh rebuild harvester
```

`watch harvester` distinguishes these paths automatically. Frontend changes rebuild the React application and restart Harvester; Harvester Java or Maven changes rebuild the JAR and recreate the Harvester container.

## Developer Harvester account

The developer entrypoint creates an ephemeral administrator account on every Harvester start:

```text
Username: admin
Password: admin
Role: ROLE_ADMIN
```

The generated user file is inside the container's temporary runtime configuration. The repository's `users.properties` and the normal platform configuration are not modified.

## VuFind and Solr

VuFind uses the existing local `./vufind` mount. Use these actions when needed:

```bash
./Docker/docker-dev.sh restart vufind-web
./Docker/docker-dev.sh reload solr
```

Solr cores are mounted from `Docker/solr/cores`; its persistent data is redirected to the isolated developer data root.

## Command reference

```text
wizard                 Open the interactive developer wizard
up [service...]         Start selected modules or explicit services
down                   Stop and remove developer containers
ps                     Show developer service status
logs [service]          Follow logs
shell [service]        Open a shell (default: harvester)
init-db                Run database migrations
build <service|all>    Compile Java applications or frontend
rebuild <service>      Compile/rebuild and recreate one service
restart <service>      Recreate one service without dependencies
watch <service>        Watch Java sources and rebuild on change
reload solr            Restart Solr after local core changes
frontend-dev            Start or restart the Vite admin web server
clean [--yes]          Remove all isolated developer artifacts
```

## Complete cleanup

`clean` is limited to the isolated developer instance and removes its containers, Compose volumes and network, persistent data, Maven cache, and developer runtime image. It never deletes source code or local Maven targets. A normal rebuild restarts the existing container so the entrypoint loads the updated locally mounted JAR instead of recreating it.

```bash
./Docker/docker-dev.sh clean
./Docker/docker-dev.sh clean --yes
```

The command refuses to run while `DEV_INSTANCE_MODE=normal`, protecting the normal platform's data.

## Typical workflow

```bash
./Docker/docker-dev.sh instance isolated
./Docker/docker-dev.sh build harvester
./Docker/docker-dev.sh up
./Docker/docker-dev.sh rebuild frontend       # React-only change
./Docker/docker-dev.sh rebuild harvester       # Java Harvester change
./Docker/docker-dev.sh watch harvester        # continuous development
```

Validate the scripts without starting containers:

```bash
bash -n Docker/docker-dev.sh
bash -n Docker/apps/entrypoint-dev.sh
```
