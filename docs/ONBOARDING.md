# Developer Onboarding Guide

**Status:** current · **Last verified:** 2026-11-16

Prepare a consistent workspace before building with Maven, the helper scripts or
an IDE. Start with [ARCHITECTURE.md](ARCHITECTURE.md) for the component map and
[githelper.md](../githelper.md) for branch, lock and release operations.

## Workspace and version

The outer repository holds the parent Maven POM, documentation and orchestration.
Each component is a nested independent Git repository. `workspace.ini` identifies
15 platform repositories; `workspace.lock` freezes their exact commits:

- 10 active Java modules and two frontend modules inherit `lareferencia-parent`.
- `lareferencia-solr-cores` supplies configuration and has no Maven artifact.
- `lareferencia-contrib-ibict` and `lareferencia-contrib-rcaap` are legacy modules,
  excluded from the reactor and retained at 4.2.6.
- VuFind is external and excluded from the manifest, lock and platform release.
  Docker can prepare its checkout separately for the discovery/Solr integration.

The current source version is **5.0.0-rc4**, Java 17 and Spring Boot 3.5.0.
Including the parent, the full Maven reactor has 13 projects. Internal dependency
versions are managed by the parent, and frontend npm metadata follows that version.
The consolidated metadata-export changes and verification scope are described in
[the rc4 release notes](RELEASE_5.0.0_RC4.md).

## Prerequisites

- Git, Python 3.9+, JDK 17+ and Maven 3.9.x. Platform CI uses Java 21; OAI CI also
  verifies Java 17.
- Maven downloads pinned Node/npm versions for frontend builds (Node 22 for both Admin and Dashboard); a separate global Node installation is not required.
- Docker is needed for Testcontainers integration tests, Compose, and the optional
  `build-admin-web.sh` / `build-dashboard.sh` container builds.
- Local `run-dev.sh` for Admin requires Node 22/npm on the host. Docker Dev offers
  a Vite container instead.
- GitHub CLI (`gh auth login`) is required only for `githelper pr` and
  `githelper release prepare`, not for installing or compiling a release.

## Download a published release

```bash
git clone --branch 5.0.0-rc4 https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform
./githelper init
./build.sh lareferencia
```

`init` prepares the commits in the selected release's lock. No manual version
stamp is needed. To select another published release in a clean workspace, use
`./githelper switch VERSION`. GitHub's automatic source ZIP contains only the
parent; use a Git clone or the complete platform ZIP attached to the release.

## Building

Run platform commands from the workspace root:

```bash
./build.sh lareferencia      # Java + both SPAs; skips tests and Javadoc
./build-java.sh lareferencia # Java only; skips tests and Javadoc
mvn clean install -Plareferencia  # direct Maven build, with tests
./build-admin-web.sh         # Admin only, Node 22 in Docker → admin-static/
./build-dashboard.sh         # Dashboard only, Node 22 in Docker → dashboard-static/
```

The script `build.sh` defaults to `lite`; explicitly select `lareferencia` for the
standard full implementation. The Harvester POM also defaults to `lite`.
Country profiles select dependencies/contexts; they do not add the legacy contrib
projects back to the reactor. The `rcaap` profile references its independent legacy
artifact and is not the standard rc4 verification target.

Both frontend Maven projects are enabled unless `-Dno-frontends` is supplied.
The full build writes separate `admin-static/` and `dashboard-static/` trees.
The individual Docker frontend scripts avoid depending on host Node/glibc.

## Testing

```bash
python3 -m unittest discover -p 'test_*.py'
mvn clean verify -Plareferencia
# Provider only: verify includes Solr integration tests; test runs unit tests.
mvn -pl lareferencia-oai-pmh verify
# After the Maven frontend build:
(cd lareferencia-lrharvester-admin-web && ./node/node node_modules/vitest/vitest.mjs run)
```

Docker must be available for integration tests. `mvn test` does not execute OAI's
Failsafe integration phase; use `verify` for the complete Maven suite.
CI also supplies a disposable PostgreSQL 15 database and passes
`-Dindexing.test.jdbc-url=jdbc:postgresql://HOST:PORT/indexing_test` to enable the
optional database tests (user `postgres`, password `indexing-test` in the test
fixtures). Use a disposable database, separate from runtime data.

## Coordinated development and releases

```bash
./githelper feature start mejora-cosecha --modules lareferencia-core-lib,lareferencia-lrharvester-app
./githelper feature add lareferencia-oai-pmh
# Commit functional changes in each repository, then create/update PRs:
./githelper pr
./githelper release prepare --bump rc
./githelper pr
```

Feature branches start from fetched `origin/main`. Repeat release preparation
and `pr` after module merges to refresh the final lock. Label the coordinator only
when the module commits are integrated; its merge publishes the prepared version.
See [githelper.md](../githelper.md) for checks, numbering and recovery. `init` on a
registered feature branch prepares its module branches and freezes the others.
`init --dev` provides the traditional manifest-branch initialization where no
branch-set exists. `sync`/`pull` are explicit development operations.

## Running

| Mode | Command | Access |
|---|---|---|
| Standard Compose | `./Docker/docker.sh wizard` | Harvester loopback `8090/admin/` and `8090/dashboard/es/`; optional external VuFind integration |
| Isolated Docker Dev | `./Docker/docker-dev.sh wizard` | Harvester `8190/admin/` and `8190/dashboard/es/`; gateway `admin.localhost:8188/admin/` and `dashboard.localhost:8188/dashboard/es/`; Vite is internal |
| Local JVM | `java -Dapp.config.dir=/path/to/config -jar harvester.jar` | Use the configured server port and provision the runtime services |

Compose defaults to PostgreSQL 17 and Solr 9.11. PostgreSQL 14 data requires the
[documented migration or image pin](../Docker/README.md#-postgresql-14--17).
Build success does not validate production TLS or complete the pending Dashboard
browser/gateway acceptance checks in [DASHBOARD_V5_MIGRATION.md](DASHBOARD_V5_MIGRATION.md).

## Configuration and identity

Application-specific `config/application.properties` is a local override; the
versioned `.model` file documents available settings. Harvester and Shell also
load ordered `application.properties.d/*.properties` fragments. Configure their
base with `-Dapp.config.dir=...`; do not define conflicting values in multiple
fragments. See [CONFIG_DIRECTORY.md](CONFIG_DIRECTORY.md) and
[CONFIGURATION_PROPERTIES.md](CONFIGURATION_PROPERTIES.md).

Harvester users, tokens and sessions live in PostgreSQL. Apply migrations, then
create the first administrator with `security-create-admin <username>` in the
interactive shell. There are no default accounts. See [AUTHENTICATION.md](AUTHENTICATION.md).

Metadata export commands, mapping installation, WAL requirements and batch exit
codes are documented in [METADATA_EXPORT.md](METADATA_EXPORT.md); the record and
package contracts are in [METADATA_EXCHANGE_FORMAT.md](METADATA_EXCHANGE_FORMAT.md).

## Where to edit what

| Change | Repository |
|---|---|
| Harvesting, validation, export or workers | core-lib and the relevant application |
| Entity model/indexing | entity-lib; indexing-filters-lib |
| Administration UI | lrharvester-admin-web |
| Read-only Dashboard | repository-dashboard |
| Shell commands | shell; shell-entity-plugin |
| OAI provider | oai-pmh |
| ARK support | dark-lib |
| Solr configsets | owning module; Docker stages copies |

Core libraries use `org.lareferencia.core.*`; the Harvester application retains
`org.lareferencia.backend.*`. Repository docs carry status/review dates; historical
records remain historical. See [DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md).
