# LA Referencia Platform

LA Referencia is a platform for harvesting, processing, and indexing scholarly metadata from institutional and thematic repositories across Latin America. It provides entity-based metadata management, validation and transformation pipelines, persistent identifier (dARK/ARK) tracking, and publication indexing in Solr and discovery through VuFind.

## 🚀 Current Status

**Version documented here: 5.0.0-rc5.** The workspace lock records the exact
revisions of its 16 modules. See the
[RC5 changelog](CHANGELOG.md#500-rc5) for changes and
[upgrade instructions from RC4](CHANGELOG.md#upgrading-from-500-rc4).

- Full OAI-PMH harvesting and a modernized standalone OAI-PMH data provider
- Entity-based metadata processing with filesystem + SQLite storage
- Incremental validation and indexing (record-level deltas)
- Solr publication indexing
- React-based administration UI with a full management API (`/api/v5`)

### Major Upgrades

- **Spring Boot 3.5** and **Jakarta EE** (javax → jakarta) across all modules
- **Java 17** runtime. Platform CI uses Java 21 and OAI-PMH CI verifies Java 17 and 21.
- All core dependencies updated (XOAI 3.4, SolrJ 9.5, Jena 4.10, langchain4j)

### Deprecated Features

- **Spring Data Solr**: removed (discontinued upstream)
- **`lareferencia-contrib-ibict` and `lareferencia-contrib-rcaap`**: legacy Solr-based entity service modules, no longer compiled (excluded from the default build)

### Highlights of v5

- **Hybrid storage**: original metadata XML on the filesystem (GZIP, hash-partitioned) + SQLite per-snapshot databases for the record catalog, validation results and statistics
- **Incremental processing**: catalogs track record changes (`N`/`U`/`D`), validation state is reused across snapshots via fingerprints and manifests, and indexers consume record-level deltas
- **File-based snapshot logging** under `{basePath}/{NETWORK}/snapshots/snapshot_{id}/snapshot.log` (no database tables)
- **Harvester Management API v5**, with separate React builds for administration and the read-only Repository Dashboard
- **Action configuration model**: per-network action configuration (JSONB), scheduled actions and worker parameterization
- **dARK**: ARK persistent identifier minting, staging/reconciliation workers and legacy ARK CSV import
- **Dynamic validation/transformation forms** generated from Java annotations, localized in English, Spanish and Portuguese
- **Metadata export for enrichment**: immutable LGK reads, XOAI → JSON profiles, traceable packages, and batch outcome codes; see [the export guide](docs/METADATA_EXPORT.md)
- **SQLite enrichment and vectors**: import selected fields into XOAI at validation time, or index precomputed vectors in Solr. [Enrichment configuration](docs/VALIDACION_COMPATIBILIDAD.md#enriquecimientos-sqlite) · [Semantic indexing](docs/SEMANTIC_INDEXING_CHUNKING.md#precomputed-sqlite-vectors)
- **Backup/restore wizard** and an isolated developer Docker workflow

## 📋 System Requirements

- **Java**: OpenJDK 17 (Docker images use `eclipse-temurin:17-jre`)
- **Maven**: 3.9.x
- **Workspace tooling**: Git and Python 3.9+
- **PostgreSQL**: Compose defaults to `postgres:17-alpine3.23`; configurable with `LR_POSTGRES_IMAGE`. Existing PostgreSQL 14 data needs the [documented migration](Docker/README.md#-postgresql-14--17).
- **Solr**: Compose builds from `solr:9.11.0`; SolrJ client 9.5. OAI integration tests use Solr 9.8.
- **Memory**: 4GB minimum (8GB+ recommended)

## 🏗️ Architecture

The platform is a multi-repo workspace managed by `githelper` (each component is its own Git repository) with a root Maven reactor for building.

> Full component map, data flows and ports: [ARCHITECTURE.md](docs/ARCHITECTURE.md)

### Components

| Module | Type | Purpose |
|---|---|---|
| `lareferencia-core-lib` | Library | Domain models, OAI-PMH harvesting, validation/transformation engine, workers, SQLite catalog/validation stores |
| `lareferencia-entity-lib` | Library | Entity model (generic entities, relations, semantic identifiers) |
| `lareferencia-dark-lib` | Library | dARK ARK persistent identifiers: minting, staging, reconciliation, legacy import |
| `lareferencia-oclc-harvester` | Library | Low-level OAI-PMH protocol (OCLC Harvester2 fork) |
| `lareferencia-indexing-filters-lib` | Library | Field occurrence filters for indexing pipelines |
| `lareferencia-solr-cores` | Config | Solr configsets (`biblio`, `entity`, `historic`, `networks`, `oai`, `projects`, `vstats`) |
| `lareferencia-lrharvester-app` | Web app | Main harvester: networks, harvesting, validation and publication; serves separate Admin/Dashboard SPAs and `/api/v5` |
| `lareferencia-lrharvester-admin-web` | Web app (React 19/Vite) | Administration UI consuming the v5 API; built into `admin-static/` |
| `lareferencia-repository-dashboard` | Web app (React + Vite) | Read-only repository dashboard consuming dashboard endpoints in v5; built into `dashboard-static/` |
| `lareferencia-entity-rest` | Web app | REST API for entity data (`/api/v2`) |
| `lareferencia-oai-pmh` | Web app | Standalone OAI-PMH 2.0 provider over the Solr publication index (XOAI 3.4, Spring Boot 3.5) |
| `lareferencia-shell` | CLI | Spring Shell console for administration and LGK export with JSON profiles |
| `lareferencia-metadata-tools` | Python CLI | Rights inventories, SQLite enrichment, bibliographic preparation, batch embeddings and vector packaging |
| `lareferencia-shell-entity-plugin` | CLI plugin | Entity loading and maintenance commands for the shell |
| `lareferencia-contrib-ibict` / `-rcaap` | Library (legacy) | Deprecated, not compiled |

### Services and Ports

| Service | Standalone default | Standard Docker Compose |
|---|---|---|
| Harvester | Admin `http://localhost:8090/admin/` · Dashboard `http://localhost:8090/dashboard/` | Admin `http://localhost:8090/admin/` · Dashboard `http://localhost:8090/dashboard/` |
| OAI-PMH provider | `http://localhost:8092/request` | `http://localhost:8096/request` |

Harvester redirects `/dashboard/` to `/dashboard/es/` by default. English and
Portuguese are available at `/dashboard/en/` and `/dashboard/pt/`.

Standard Compose binds Harvester to loopback by default and maps host port 8096 to
the OAI-PMH container's port 8092. See the [Docker guide](Docker/README.md) for
deployment configuration.

### Storage Architecture (v5.0)

Hybrid **filesystem + database** storage:

| Component | Storage | Format | Purpose |
|-----------|---------|--------|---------|
| **Metadata XML** | Filesystem | GZIP compressed | Original harvested XML records |
| **OAI Records Catalog** | SQLite | `catalog.db` | Harvested record index with MD5 hashes and change tracking |
| **Validation Records** | SQLite | `validation.db` | Validation results and rule violations |
| **Validation Manifest** | JSON (FS) | `validation-manifest.json` | Validator fingerprint for incremental reuse |
| **Validation Statistics** | JSON (FS) | Text aggregates | Pre-computed validation metrics |
| **Snapshot Logs** | Text (FS) | Plain text | Audit trail (`snapshot.log`) |
| **Snapshot / Network / Entity data** | PostgreSQL | Relational | Structural snapshot, network and entity data |

Per-snapshot directory structure:

```text
{basePath}/{NETWORK}/snapshots/snapshot_{ID}/
├── metadata.json
├── catalog/
│   └── catalog.db
├── validation/
│   ├── validation.db
│   └── validation-manifest.json / validation-stats.json
└── snapshot.log

{basePath}/{NETWORK}/metadata/
├── A/B/C/ABCDEF123456789.xml.gz     ← partitioned by content hash (4,096 partitions)
└── ...
```

Key properties: WAL-mode SQLite for concurrent read/write, dynamic validation rule columns, content-addressed XML deduplication, per-network filesystem isolation.

Reference: [ALMACENAMIENTO_REFERENCIA_RAPIDA.md](docs/ALMACENAMIENTO_REFERENCIA_RAPIDA.md)

### Incremental Validation & Indexing

Since 5.0.0 the catalog and validation databases track record-level state:

- `oai_record.change_type` (`N` new / `U` updated / `D` deleted) in `catalog.db`, `record_validation.change_type` in `validation.db`
- Harvested records are only processed downstream when they changed; indexers consume the delta (per-record `solrRecordIDField`/`solrRecordIDValue` updates)
- Validation reuse is controlled by a validator fingerprint + validation manifest: records are re-validated only when input or rule configuration changed

Full manual: [ISSUE_INCREMENTAL_RECORD_PROCESSING.md](docs/ISSUE_INCREMENTAL_RECORD_PROCESSING.md). Test harness: [testing/oai-incremental](testing/oai-incremental/README.md).

### Actions & Workflow Engines

- Actions (harvesting, validation, indexing, publishing, dARK stage/reconcile, metadata cleanup, …) are configured per network: manual and scheduled execution with JSONB configuration
- Application-level actions and worker parameters are managed via the v5 API and the Admin UI
- Workflow engines: `workflow.engine=legacy` (TaskManager, default) or `flowable` (BPMN processes in `config/processes/`)

Reference: [WORKFLOW_ACTIONS.md](docs/WORKFLOW_ACTIONS.md) (new) · analysis: [WORKERS_TASKS_ACTIONS_ANALYSIS.md](docs/WORKERS_TASKS_ACTIONS_ANALYSIS.md)

### Harvester Management API v5 & Admin Web

- `org.lareferencia.backend.api.v5`: typed DTO REST API under `/api/v5` (networks, snapshots, actions, workers, validators/transformers, diagnostics, users, dARK, network transfers, attribute profiles) with Problem Details errors and OpenAPI at `/api/v5/openapi`
- Authentication uses local PostgreSQL identities, JDBC web sessions and revocable scoped bearer tokens. `ADMIN` has global access, `READER` has read-only access to assigned repositories through the native v5 API, and `DASHBOARD` can use the Dashboard for assigned repositories.
- The first administrator is created interactively from `lareferencia-shell` after Flyway migration (`security-create-admin <username>`). No default user or Keycloak migration exists.
- Admin Web: React + Vite, built into the Harvester `admin-static/` and served at `/admin/`. The read-only React Dashboard is built into `dashboard-static/` and served at `/dashboard/`. `/legacy`, `/rest`, `/public` and `/private` are not exposed as legacy application APIs.
- Full setup, cookie/CSRF behavior, token lifecycle and authorization matrix: [Authentication and authorization](docs/AUTHENTICATION.md).

Reference: [HARVESTER_MANAGEMENT_API_V5.md](docs/HARVESTER_MANAGEMENT_API_V5.md) · auth: [AUTHENTICATION.md](docs/AUTHENTICATION.md) (new) · backlog: [HARVESTER_ADMIN_WEB_V5_BACKLOG.md](docs/HARVESTER_ADMIN_WEB_V5_BACKLOG.md) (new)

### DARK / ARK Persistent Identifiers

- ARK minting and per-network settings, staging (`DarkStageWorker`) and reconciliation (`DarkReconcileWorker`) workers
- dARK dashboard in the Admin UI; v5 API under `/api/v5/dark/naans/{arkNaan}/…`
- Legacy import: `import-dark-legacy-csv` runbook: [DARK_LEGACY_ARK_IMPORT.md](docs/DARK_LEGACY_ARK_IMPORT.md)

### Core Library Package Structure

`lareferencia-core-lib` uses `org.lareferencia.core.*` (11 top-level packages):

```text
org.lareferencia.core.*
├── domain/       Domain models
├── repository/   Data access (JPA + SQLite: repository.catalog, repository.validation)
├── service/      Business logic (harvesting, validation, indexing, management)
├── metadata/     Metadata storage abstraction
├── worker/       Asynchronous processors
├── task/         Task scheduling and coordination
├── export/       LGK metadata export, mapping, provenance and package indexes
├── embedding/    Semantic chunking/embedding
├── flowable/     Flowable workflow delegates (optional engine)
├── oabroker/     OpenAIRE broker integration
└── util/         Shared utilities (incl. ConfigPathResolver)
```

Note: dependent projects migrate `org.lareferencia.backend.*` → `org.lareferencia.core.*` for the core libraries; the harvester application itself still uses the `org.lareferencia.backend.*` namespace. Convention: [REFACTORING_PACKAGE_STRUCTURE.md](docs/REFACTORING_PACKAGE_STRUCTURE.md).

## 🚀 Quick Start

> Step-by-step developer setup (prerequisites, profiles, run modes, testing): [ONBOARDING.md](docs/ONBOARDING.md)

### Building the Platform

Use the tag once it is listed on [GitHub Releases](https://github.com/lareferencia/lareferencia-platform/releases). To test the candidate before the tag exists, follow the [candidate checkout instructions](docs/ONBOARDING.md#test-the-rc5-candidate).

```bash
git clone --branch 5.0.0-rc5 https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform

# Prepare the exact module commits frozen in workspace.lock
./githelper init

./build.sh lareferencia
```

For a full build, `./build.sh lareferencia` runs Maven on the host with the JDK
and builds the Java modules, Admin Web and Repository Dashboard. Maven downloads
the pinned Node 22 and npm versions for both frontends. This build works without
Docker or a global Node installation.

Use the individual scripts when rebuilding just one part of the platform:

| Command | What it builds | Build tools |
|---|---|---|
| `./build-java.sh lareferencia` | Java modules only | Host JDK and Maven |
| `./build-admin-web.sh` | Admin Web only. Copies the output to `lareferencia-lrharvester-app/admin-static/`. | Docker with Node 22 |
| `./build-dashboard.sh` | Dashboard only. Copies the output to `lareferencia-lrharvester-app/dashboard-static/`. | Docker with Node 22 |

The frontend scripts run npm in a temporary Docker container and publish the
static files without recompiling Java. The build scripts skip tests. Run the
test commands in the Testing section separately.

Other platform build profiles are `lite`, `rcaap` and `ibict`. To package just the
OAI-PMH provider through Maven, run `mvn -pl lareferencia-oai-pmh package`.

### Running with Docker

```bash
# Interactive wizard (deploy, backup/restore, maintenance, developer environment)
./Docker/docker.sh wizard

# Production-like stack
./Docker/docker.sh up

# Isolated developer environment (port offset +100, Vite dev server)
./Docker/docker-dev.sh wizard
```

See [DOCKER_DEV.md](docs/DOCKER_DEV.md) for the developer workflow and [BACKUP_RESTORE.md](docs/BACKUP_RESTORE.md) (new) for backup/restore.

## 📦 Multi-Repo Workspace

VuFind is an external application and is managed separately. Its local checkout is excluded from the platform workspace manifest, module lock and release archives.

Each module is an independent Git repository cloned in the workspace root and declared in `workspace.ini`; `./githelper` coordinates them.

```bash
./githelper status                          # Parent + module status
./githelper init                            # Prepare frozen modules, or registered feature branches
./githelper pull                            # Pull parent branch and modules
./githelper switch <parent-branch>          # Switch parent branch (applies matching branch-set if present)
./githelper branch-set capture <name>       # Snapshot current module branches (reproducible with: ./githelper sync --set <name>)
./githelper branch create --modules lareferencia-core-lib,lareferencia-shell
./githelper url rewrite --to https
```

For coordinated development and releases:

```bash
./githelper feature start mejora-cosecha --modules lareferencia-core-lib,lareferencia-lrharvester-app
./githelper feature add lareferencia-oai-pmh
# Commit functional changes in each affected repository, then:
./githelper pr
# Prepare common versions and PRs; repeat after merging module PRs:
./githelper release prepare --bump rc
./githelper pr
```

Active modules inherit the parent version; internal dependency versions are
centralized and npm metadata follows the same version. The Python distribution
uses `5.0.0rc5` for platform version `5.0.0-rc5`. Preparation commits these
versions before publication. Legacy contributions retain their independent versions.
Apply exactly one matching `release:*` label once all module PRs are merged and the
coordinator lock is refreshed. Its merge publishes the prepared version after CI.
See [githelper.md](githelper.md) for the complete workflow and recovery.

### Develop Features with Codex

The repository includes the [lareferencia-features skill](.agents/skills/lareferencia-features/SKILL.md)
in `.agents/skills`, so it travels with the platform checkout. Open Codex in the
platform directory and invoke it with your feature request:

```text
$lareferencia-features Implementa [descripción de la funcionalidad]
```

The skill covers module discovery, branches from main, implementation, tests,
commits and coordinated PRs with an updated lock. Release preparation and
publication apply when requested. Its supporting references and UI metadata
are included in the same directory; no personal filesystem paths are required.

### Download a Published Version

Once the `5.0.0-rc5` tag is published:

```bash
git clone --branch 5.0.0-rc5 https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform
./githelper init
./build.sh lareferencia
# Or compile directly with Maven; no version-stamping command is needed:
# mvn clean install -Plareferencia
```

To align an existing clean workspace with another release:

```bash
./githelper switch 5.0.0-rc5
```

Historical versions without workspace.lock retain their original installation
instructions. GitHub's automatic source ZIP contains only the parent repository;
use a Git clone or the complete platform ZIP attached to the release.

## 🔧 Configuration

Each Java application module has a `config/` directory following this model (not all modules use every entry; `application.properties.d/` is used by the harvester and shell):

```
config/
├── application.properties          # Local/private (gitignored)
├── application.properties.model    # Template/reference (versioned)
├── application.properties.d/       # Modular fragments loaded at startup (versioned — the working config on a fresh clone)
│   ├── 00-server.properties
│   ├── 01-dbconnection.properties
│   └── ...
├── beans/                          # Bean definitions (mdformats.xml, fingerprint.xml, actions.xml, …)
├── processes/                      # Flowable BPMN definitions
├── i18n/                           # messages.properties, messages_en, messages_pt
└── ...                             # No users.properties: Harvester identities live in PostgreSQL
```

**The golden rule**: `application.properties` = local override (gitignored); `application.properties.model` = versioned template with documentation for every property. When adding a property, update the `.model` file.

**How the fragments load** (verified in code): `PropertiesDirectoryListener` (`lareferencia-core-lib`, registered in each `MainApp`) reads every `*.properties` file inside `application.properties.d/` in alphabetical order during `ApplicationEnvironmentPreparedEvent` — before any bean exists — and appends each as its own property source; each load is visible in the startup log as `[PropertiesLoader] Loaded: <filename>`. The two-digit prefixes group files by concern (`00-server`, `01-dbconnection`, `02-catalog`/`02-metadata`, `04-security`, `05-harvester`, `06-logging`, `07-dark`/`07-semantic`, `08-workflow`, `09-flowable`, `10-api-v5` in the harvester; `00-app`, `01-dbconnection`, `05-harvester`, `06-logging` in the shell). Today no key is defined twice with different values across the base file and the fragments, so the mechanism works without precedence conflicts; when adding properties, define each key in one place only.

The config base directory is resolved by `ConfigPathResolver` via the `app.config.dir` system property:

```bash
java -jar lareferencia-shell.jar                                   # default: ./config
java -Dapp.config.dir=/etc/lrharvester/config -jar harvester.jar   # custom path
```

Reference: [CONFIG_DIRECTORY.md](docs/CONFIG_DIRECTORY.md) · per-file, per-property reference for the harvester and shell, including which class reads each property and legacy keys no longer read: [CONFIGURATION_PROPERTIES.md](docs/CONFIGURATION_PROPERTIES.md) · pending config-cleanup proposal: [CONFIG_CLEANUP_PROPOSAL.md](docs/CONFIG_CLEANUP_PROPOSAL.md)

## 🧪 Testing

```bash
mvn clean verify -Plareferencia             # full Maven suite, including OAI integration tests; Docker required
mvn test -Plareferencia                     # tests bound to the test phase
mvn -pl lareferencia-oai-pmh verify         # provider unit + Solr 9.8 integration tests
python3 -m unittest discover -p 'test_*.py' # workspace/release tooling
```

- OAI-PMH regression suite: protocol verbs over HTTP validated against the official XSD ([oai-compatibility-contract](lareferencia-oai-pmh/docs/testing/oai-compatibility-contract.md))
- Incremental OAI harness with deterministic fixtures: [testing/oai-incremental](testing/oai-incremental/README.md) (provider at `localhost:8096`, or `8196` in dev)

## 📚 Documentation Map

| I want to… | Start here |
|---|---|
| Install, build or test the platform | [Developer onboarding](docs/ONBOARDING.md) |
| Deploy or run it locally | [Docker guide](Docker/README.md) · [Docker Dev](docs/DOCKER_DEV.md) |
| Configure the Harvester and manage access | [Configuration reference](docs/CONFIGURATION_PROPERTIES.md) · [Authentication and permissions](docs/AUTHENTICATION.md) |
| Understand the components or integrate with the API | [Architecture](docs/ARCHITECTURE.md) · [Harvester Management API v5](docs/HARVESTER_MANAGEMENT_API_V5.md) |
| Export and enrich metadata | [Metadata export guide](docs/METADATA_EXPORT.md) |

See the [full documentation index](docs/DOCUMENTATION_INDEX.md) for specialized
guides, component manuals and historical records.

## 📝 Upgrading to 5.0.0-rc5

From RC4, check pending Flyway migrations with `database_info` and plan for one
full validation per network. Review any scripts that call the former Python
tools by path. See the [RC5 upgrade notes](CHANGELOG.md#upgrading-from-500-rc4)
for configuration, compatibility and rollback details.

Keep the existing configuration and data directories when changing the checkout.
If the source repositories have local edits, review them before switching or
prepare a separate release checkout and point it at your configuration.

### Upgrading from v4.x

#### Required Actions

1. **Java 17+** and **Spring Boot 3.5** (javax → jakarta imports)
2. **Storage**: configure `store.basepath` for filesystem + SQLite (catalog, validation, stats, logs)
3. **Configuration**: review property names for Spring Boot 3.x; keep `application.properties.model` in sync

#### Breaking Changes

- `contrib-ibict`/`contrib-rcaap` no longer compiled
- Core/entity library packages renamed to `org.lareferencia.core.*` (see note above)

## 🤝 Contributing

1. Fork and create a feature branch
2. Follow Java/Spring conventions; add tests for new functionality
3. Update documentation (`.model` config files, module READMEs) as part of the change
4. Open a PR against `main` with a clear description and test results

Contributions must be compatible with **AGPL-3.0**.

## 📄 License

Licensed under the **GNU Affero General Public License v3.0** — see [LICENSE.txt](LICENSE.txt). If you deploy this software as a network service, you must make the complete source code (including your modifications) available to your users.

## 📧 Support and Contact

**Email**: [soporte@lareferencia.redclara.net](mailto:soporte@lareferencia.redclara.net)

When requesting support, include the platform version (e.g. `5.0.0-rc5`), affected module, relevant log excerpts, configuration snippets (without sensitive data) and steps to reproduce.

- **Website**: [lareferencia.info](https://www.lareferencia.info)
- **Issues**: [GitHub Issues](https://github.com/lareferencia/lareferencia-platform/issues)
- **Organization**: [LA Referencia](https://github.com/lareferencia)

---

**Note**: this checkout is a release candidate. Production deployments should use a tagged release validated by the maintainers.
