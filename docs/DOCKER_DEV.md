# Developer Docker Mode

**Status:** current · **Last verified:** 2026-09-30

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

Entity REST, Shell, Elasticsearch, and the VuFind SCSS watcher are disabled by default. Select modules from the wizard's **Manage Modules (on/off)** action. The selection is persisted in `Docker/.env.dev`. With Harvester selected, both Harvester and the local Nginx gateway are available on loopback: Harvester directly serves compiled Admin and Dashboard at `/admin/` and `/dashboard/`; the gateway offers host-separated access, routing `admin.localhost` to Vite and the full v5 API, and `dashboard.localhost` only to the compiled Dashboard and allowlisted auth/read APIs. Vite itself has no host port. Add the gateway names to `/etc/hosts` if `.localhost` does not resolve automatically. See [DASHBOARD_V5_MIGRATION.md](DASHBOARD_V5_MIGRATION.md).

When Harvester is enabled, it is published on loopback port `8190` in isolated
mode (or `LR_PORT_HARVESTER` in normal mode). The compiled UIs are available
directly at `http://localhost:8190/admin/` and
`http://localhost:8190/dashboard/es/`. The gateway also runs on
`http://admin.localhost:8188/admin/` and
`http://dashboard.localhost:8188/dashboard/es/` (isolated mode; normal mode
defaults to 8088). The gateway's Admin host routes to `admin-web-dev`, which
provides Vite hot-module replacement; Vite itself is not published to the host.
Dashboard Angular is served as a compiled SPA from Harvester; after changing it, run
`./Docker/docker-dev.sh rebuild dashboard` to rebuild its assets and restart
Harvester. Direct loopback access skips the gateway's host allowlist, but all API
authentication and authorization are still enforced by Harvester.

Dependencies are added automatically: Harvester, Shell, and VuFind require Solr; Java services requiring PostgreSQL also bring Core.

Starting without service arguments starts only the selected modules:

```bash
./Docker/docker-dev.sh up
```

## Java build and runtime flow

Java applications are compiled inside `maven-builder`, but the source tree is the local repository. The resulting JAR remains in each module's local `target` directory. Developer runtime containers mount the repository read-only and execute that JAR directly.

Build Java applications and both frontend artifacts:

```bash
./Docker/docker-dev.sh build all
```

Rebuild one application and restart only its container:

```bash
./Docker/docker-dev.sh rebuild harvester
./Docker/docker-dev.sh rebuild entity-rest
./Docker/docker-dev.sh rebuild oai-pmh
```

## Harvester admin web

The React Admin Web and Angular Dashboard are published independently into `admin-static/` and `dashboard-static/`. A frontend-only change does not recompile Harvester Java:

```bash
./Docker/docker-dev.sh rebuild frontend
./Docker/docker-dev.sh rebuild dashboard
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

`watch harvester` distinguishes these paths automatically. React or Angular changes rebuild only that SPA and restart Harvester; Harvester Java or Maven changes rebuild the JAR and recreate the container.

## Developer Harvester account

The former ephemeral `admin/admin` user-file bootstrap is retired. Harvester now
uses PostgreSQL-backed local identities and does not create default credentials.
The developer entrypoint no longer writes `users.properties` or advertises a
default account.

The developer wizard's **Open Interactive Spring Shell** action (or the
`lrshell` command) starts a one-off, TTY-attached shell container connected to
the isolated developer PostgreSQL database. It does not rebuild the platform
automatically. Rebuild just the shell when its sources changed, then run it:

```bash
./Docker/docker-dev.sh rebuild shell
./Docker/docker-dev.sh lrshell
```

At the Spring Shell prompt, apply migrations and create the initial admin:

```text
database_migrate
security-create-admin admin
```

The password is prompted twice without echo. You can also pass a command directly
to the interactive container, preserving its TTY:

```bash
./Docker/docker-dev.sh lrshell database_migrate
./Docker/docker-dev.sh lrshell security-create-admin admin
```

`lrshell` starts PostgreSQL and Solr if needed. It uses the shell JAR already in
`lareferencia-shell/target`; it does not compile it. `rebuild shell` compiles the
shell and its Maven dependencies, then restarts the background shell service.
When starting Harvester or Entity REST, the wizard also builds
the shell with the active profile because those services run the `db-init`
dependency during startup. The optional `SHELL` module can remain disabled; its
JAR is still needed for migrations.
`build all` compiles all Java modules; the full-platform build also compiles the
React web. See the [authentication runbook](AUTHENTICATION.md) for password,
session and permission details. Do not assume a developer admin already exists.

## VuFind and Solr

VuFind uses the existing local `./vufind` mount. Use these actions when needed:

```bash
./Docker/docker-dev.sh restart vufind-web
./Docker/docker-dev.sh reload solr
```

Solr cores are mounted from `Docker/solr/cores`; its persistent data is redirected to the isolated developer data root.

## Command reference

```text
wizard                       Interactive developer wizard
instance [isolated|normal]   Switch instance mode (default: isolated)
up [service...]              Start selected modules or explicit services
down                         Stop and remove developer containers
ps                           Show developer service status
logs [service]               Follow logs
shell [service]              Open a shell (default: harvester)
init-db                      Run database migrations
build <service|all|frontend|dashboard> Compile Java JARs or a frontend
rebuild <service>            Compile/rebuild and recreate one service
restart <service>            Recreate one service without dependencies
watch <service>              Watch Java sources and rebuild on change
reload solr                  Restart Solr after local core changes
frontend-dev                 Start or restart Vite behind the admin gateway (HMR)
clean [--yes]                Remove all isolated developer artifacts
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
