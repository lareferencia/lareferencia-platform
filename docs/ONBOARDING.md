# Developer Onboarding Guide

**Status:** current · **Last verified:** 2026-09-23

How to get from an empty machine to a running development environment, verified against
the scripts on 2026-09-23. Start with [`ARCHITECTURE.md`](ARCHITECTURE.md) for the big
picture and [`GLOSSARY.md`](GLOSSARY.md) for the vocabulary.

## The workspace shape

This repository is a **workspace of nested independent git repositories**:

- The outer repo holds the root `pom.xml` (aggregator), the documentation (`docs/`),
  Docker orchestration, `testing/` and the helper scripts.
- Each `lareferencia-*` directory is an **independent git repository** with its own
  history, cloned by [`githelper`](../githelper) according to `workspace.ini` (module →
  URL/branch manifest) and listed in `modules.txt` (14 modules).
- The root `pom.xml` aggregates 11 Java modules (plus `lareferencia-lrharvester-admin-web`);
  `contrib-ibict`/`contrib-rcaap` are not part of the default reactor.
- Platform version: `5.0.0-rc2` (Java 17, Spring Boot 3.5.0; CI also builds Java 21).

```bash
git clone <this-repo>
cd lareferencia-platform
./githelper init     # clones the nested modules from workspace.ini (branch main)
./githelper --help   # other workspace commands
```

## Prerequisites

- JDK 17+ and Maven (the reactor builds with Java 17; CI also runs 21)
- Docker (required to build the Admin Web and to run the wizards)
- Node.js is only needed inside the build container (Node 22) — no local install needed
- Python 3 is used by `githelper` (already in the scripts' shebang) and by some Docker
  tooling

## Building

```bash
./build-java.sh            # all Java modules: mvn clean package install -am -DskipTests
./build-java.sh ibict      # optional Maven profile: lareferencia | ibict | rcaap
./build-admin-web.sh       # React Admin Web (Node 22 in Docker) → harvester static/
mvn test                   # run tests (all reactor modules)
mvn -pl lareferencia-oai-pmh test   # provider protocol tests (Testcontainers, Solr 9.8)
```

Notes:

- `build-java.sh` explicitly excludes the admin web — always build it with
  `build-admin-web.sh` (it needs `package-lock.json` and Docker).
- The Maven **profiles** `lareferencia` (default), `ibict` and `rcaap` select the
  country-specific contrib dependencies and branding in the harvester pom.
- Version bumps: `./change-version.sh <version>` (`mvn versions:set` across the reactor).

## Running

| Mode | Command | Use |
|---|---|---|
| Production-like Docker | `./Docker/docker.sh` | Full stack: VuFind, harvester, dashboard, entity-rest, oai-pmh (profile `oai`), Solr, PostgreSQL, Elasticsearch. See [../Docker/README.md](../Docker/README.md) |
| Isolated dev Docker | `./Docker/docker-dev.sh` | Same stack, `81xx` ports and separate volumes; safe next to a production install. See [DOCKER_DEV.md](DOCKER_DEV.md) |
| Local JVM | `java -Dapp.config.dir=... -jar <module>.jar` | Debugging a single module; the `config/` directory must be populated from the `application.properties.model` templates |

Admin Web development has a Vite dev server with its own ports — see
[lareferencia-lrharvester-admin-web/README.md](../lareferencia-lrharvester-admin-web/README.md)
(`generate:api` pulls the OpenAPI spec from the harvester, default
`http://localhost:8080/api/v5/openapi`; export `API_OPENAPI_URL=http://localhost:8090/api/v5/openapi`
for the standard Docker deployment).

## Configuration in one minute

- Each module's `config/application.properties` is **gitignored** (local values);
  `application.properties.model` is the versioned template — keep it in sync when you
  add a property (the golden rule).
- Most modules load additional `config/application.properties.d/*.properties` fragments
  alphabetically at startup; which key is read by which class is documented per file in
  [CONFIGURATION_PROPERTIES.md](CONFIGURATION_PROPERTIES.md). The base directory is
  relocated with `-Dapp.config.dir=…` ([CONFIG_DIRECTORY.md](CONFIG_DIRECTORY.md)).
- Docker deployments override values via `Docker/.env` (`LR_PORT_*`, build profile,
  memory limits) and per-service config overrides under `Docker/config-overrides/`.

## Testing

- Full suite: `mvn test` (the core-lib suite alone is ~1.1k tests — snapshot report in
  [lareferencia-core-lib/src/test/README.md](../lareferencia-core-lib/src/test/README.md)).
- OAI provider regression: protocol verbs validated against the official XSD
  ([oai-compatibility-contract](../lareferencia-oai-pmh/docs/testing/oai-compatibility-contract.md)).
- Incremental OAI harness with deterministic fixtures:
  [testing/oai-incremental](../testing/oai-incremental/README.md) (provider on 8096 /
  8196 in dev).

## Where to edit what

| You want to… | Go to |
|---|---|
| Change harvester behavior (workers, actions, API) | `lareferencia-lrharvester-app` + `lareferencia-core-lib` |
| Change entity/indexing logic | `lareferencia-entity-lib` (+ `lareferencia-indexing-filters-lib`) |
| Work on the Admin Web UI | `lareferencia-lrharvester-admin-web` |
| Add/adjust dARK integration | `lareferencia-dark-lib` |
| Add shell commands | `lareferencia-shell` (+ `lareferencia-shell-entity-plugin` for entities) |
| Change OAI provider behavior | `lareferencia-oai-pmh` |
| Change Solr schemas | `lareferencia-solr-cores` (services run Solr 9.8 copies) |
| Update docs | `docs/` with a `**Status:** current · **Last verified:** <date>` header |

## Conventions

- Java packages follow `org.lareferencia.core.*` (10 packages —
  [REFACTORING_PACKAGE_STRUCTURE.md](REFACTORING_PACKAGE_STRUCTURE.md)).
- Configuration keys are documented in the `.model` file and, for the fragments, in
  [CONFIGURATION_PROPERTIES.md](CONFIGURATION_PROPERTIES.md) — avoid defining the same
  key in both the base file and a fragment.
- Documentation lives in `docs/`; every document carries a status line
  ([DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md) explains the lifecycle).

Support: [soporte@lareferencia.redclara.net](mailto:soporte@lareferencia.redclara.net)

Related: [`ARCHITECTURE.md`](ARCHITECTURE.md) · [`GLOSSARY.md`](GLOSSARY.md) ·
[`DOCUMENTATION_INDEX.md`](DOCUMENTATION_INDEX.md)