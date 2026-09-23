# LA Referencia Platform

LA Referencia is a platform for harvesting, processing, and indexing scholarly metadata from institutional and thematic repositories across Latin America. It provides entity-based metadata management, validation and transformation pipelines, persistent identifier (dARK/ARK) tracking, and search through Solr, Elasticsearch/OpenSearch and VuFind.

## 🚀 Current Status

**Current development version: 5.0.0-rc2** (branch `main`).

- Full OAI-PMH harvesting and a modernized standalone OAI-PMH data provider
- Entity-based metadata processing with filesystem + SQLite storage
- Incremental validation and indexing (record-level deltas)
- Elasticsearch/OpenSearch entity indexing and Solr publication indexing
- React-based administration UI with a full management API (`/api/v5`)

### Major Upgrades

- **Spring Boot 3.5** and **Jakarta EE** (javax → jakarta) across all modules
- **Java 17** runtime (CI matrix also builds with Java 21)
- All core dependencies updated (XOAI 3.4, SolrJ 9.5, Jena 4.10, langchain4j)

### Deprecated Features

- **Spring Data Solr**: removed (discontinued upstream)
- **Solr entity indexing**: disabled in code (`EntityIndexerSolrImpl` kept as `.java.disabled`); Elasticsearch is the entity indexing engine. Solr remains in use for the publication index (VuFind discovery, OAI-PMH provider)
- **`lareferencia-contrib-ibict` and `lareferencia-contrib-rcaap`**: legacy Solr-based entity service modules, no longer compiled (excluded from the default build)

### Highlights of v5

- **Hybrid storage**: original metadata XML on the filesystem (GZIP, hash-partitioned) + SQLite per-snapshot databases for the record catalog, validation results and statistics
- **Incremental processing**: catalogs track record changes (`N`/`U`/`D`), validation state is reused across snapshots via fingerprints and manifests, and indexers consume record-level deltas
- **File-based snapshot logging** under `{basePath}/{NETWORK}/snapshots/snapshot_{id}/snapshot.log` (no database tables)
- **Harvester Management API v5** and the new **React Admin Web** (AngularJS UI kept as legacy under `/legacy/`)
- **Action configuration model**: per-network action configuration (JSONB), scheduled actions and worker parameterization
- **Entity `deleted` flag workflow**: soft-delete entities and remove them (and their relations) from indexes
- **dARK**: ARK persistent identifier minting, staging/reconciliation workers and legacy ARK CSV import
- **Dynamic validation/transformation forms** generated from Java annotations, localized in English, Spanish and Portuguese
- **Backup/restore wizard** and an isolated developer Docker workflow

## 📋 System Requirements

- **Java**: OpenJDK 17 (Docker images use `eclipse-temurin:17-jre`)
- **Maven**: 3.9.x
- **PostgreSQL**: 14 (bundled in `docker-compose.yml`; 12+ supported)
- **Elasticsearch**: 7.x (compose bundles 7.12.0; accessed through an OpenSearch-compatible REST client)
- **Solr**: 9.x (compose bundles 9.8.0; SolrJ client 9.5)
- **Memory**: 4GB minimum (8GB+ recommended)

## 🏗️ Architecture

The platform is a multi-repo workspace managed by `githelper` (each component is its own Git repository) with a root Maven reactor for building.

> Full component map, data flows and ports: [ARCHITECTURE.md](docs/ARCHITECTURE.md)

### Components

| Module | Type | Purpose |
|---|---|---|
| `lareferencia-core-lib` | Library | Domain models, OAI-PMH harvesting, validation/transformation engine, workers, SQLite catalog/validation stores |
| `lareferencia-entity-lib` | Library | Entity model (generic entities, relations, semantic identifiers), Elasticsearch indexing, VIVO/RDF triple store indexing |
| `lareferencia-dark-lib` | Library | dARK ARK persistent identifiers: minting, staging, reconciliation, legacy import |
| `lareferencia-oclc-harvester` | Library | Low-level OAI-PMH protocol (OCLC Harvester2 fork) |
| `lareferencia-indexing-filters-lib` | Library | Field occurrence filters for indexing pipelines |
| `lareferencia-solr-cores` | Config | Solr configsets (`biblio`, `entity`, `historic`, `networks`, `oai`, `projects`, `vstats`) |
| `lareferencia-lrharvester-app` | Web app | Main harvester: networks, harvesting, validation, publication; serves the Admin UI and the `/api/v5` management API |
| `lareferencia-lrharvester-admin-web` | Web app (React 19/Vite) | Administration UI consuming the v5 API; built into the harvester |
| `lareferencia-entity-rest` | Web app | REST API for entity data (`/api/v2`, in transition after Solr indexing removal) |
| `lareferencia-dashboard-rest` | Web app | REST API for monitoring/statistics (`/api/v2`) |
| `lareferencia-oai-pmh` | Web app | Standalone OAI-PMH 2.0 provider over the Solr publication index (XOAI 3.4, Spring Boot 3.5) |
| `lareferencia-shell` | CLI | Spring Shell console: harvesting, database, maintenance, entity and dark commands |
| `lareferencia-shell-entity-plugin` | CLI plugin | Entity loading/indexing/cleanup commands for the shell |
| `lareferencia-contrib-ibict` / `-rcaap` | Library (legacy) | Deprecated, not compiled |
| `vufind/` | Upstream checkout | VuFind® 11.0.1 discovery layer (PHP) |

### Services and Ports (default `docker-compose.yml`)

| Service | URL | Notes |
|---|---|---|
| Harvester + Admin Web (React) | `http://localhost:8090/` | React SPA at `/`, legacy AngularJS UI at `/legacy/` |
| Harvester Management API v5 | `http://localhost:8090/api/v5` | OpenAPI `/api/v5/openapi`, Swagger UI `/api/v5/docs` |
| Dashboard REST | `http://localhost:8092/api/v2/…` | Swagger UI `http://localhost:8092/swagger-ui.html` |
| Entity REST | `http://localhost:8094/api/v2/…` | Swagger UI `http://localhost:8094/swagger` |
| OAI-PMH provider | `http://localhost:8096/` | OAI endpoint at `/request`; container port 8092 |
| VuFind | `http://localhost:8080` | Discovery front-end |
| Solr | `http://localhost:8983` | `biblio`, `oai` and other cores |
| Elasticsearch | `http://localhost:9200` | Entity indexing |

In the **isolated developer workflow** (`docker-compose.dev.yml`) all service ports are offset by +100 (harvester 8190, dashboard 8192, entity-rest 8194, OAI 8196) and the admin web dev server runs Vite at `http://localhost:5273`.

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

### Entity Lifecycle: deleted Flag

Entities can be soft-deleted (`entity.deleted`) and later removed from indexes together with their relations:

- Shell commands: `mark_entities_deleted`, `set_entities_deleted`, `remove_deleted_entities_from_index` (with `--relationFields`, `--pageSize`, `--timeoutSeconds`)
- Requires migration `V5.0.0.7` (`entity.deleted` column)

Guide: [ENTITY_DELETED_INDEXING.md](docs/ENTITY_DELETED_INDEXING.md)

### Actions & Workflow Engines

- Actions (harvesting, validation, indexing, publishing, dARK stage/reconcile, metadata cleanup, …) are configured per network: manual and scheduled execution with JSONB configuration
- Application-level actions and worker parameters are managed via the v5 API and the Admin UI
- Workflow engines: `workflow.engine=legacy` (TaskManager, default) or `flowable` (BPMN processes in `config/processes/`)

Reference: [WORKFLOW_ACTIONS.md](docs/WORKFLOW_ACTIONS.md) (new) · analysis: [WORKERS_TASKS_ACTIONS_ANALYSIS.md](docs/WORKERS_TASKS_ACTIONS_ANALYSIS.md)

### Elasticsearch / OpenSearch Indexing

- Multi-threaded direct indexer: fixed pool + semaphore backpressure + `Phaser`, per-document transactions with read-only semantics (`REQUIRES_NEW`)
- Circuit breaker and retry controls:

```properties
elastic.host=localhost
elastic.port=9200
elastic.indexer.max.concurrent.tasks=16
elastic.indexer.circuit.breaker.max.failures=10
```

- Semantic vector indexing with chunking (langchain4j): [SEMANTIC_INDEXING_CHUNKING.md](docs/SEMANTIC_INDEXING_CHUNKING.md)
- Architecture reference: [ENTITY_INDEXING_ARCHITECTURE.md](docs/ENTITY_INDEXING_ARCHITECTURE.md) (new)

### Harvester Management API v5 & Admin Web

- `org.lareferencia.backend.api.v5`: typed DTO REST API under `/api/v5` (networks, snapshots, actions, workers, validators/transformers, diagnostics, users, dARK, network transfers, attribute profiles) with Problem Details errors and OpenAPI at `/api/v5/openapi`
- Authentication modes: `file` (HTTP Basic against `config/users.properties`), `oidc`, `hybrid`; roles `VIEWER`/`ADMIN`
- Admin Web: React 19 + Vite + Material UI, built into the harvester (`build-admin-web.sh`); the AngularJS UI remains available at `/legacy/`

Reference: [HARVESTER_MANAGEMENT_API_V5.md](docs/HARVESTER_MANAGEMENT_API_V5.md) · auth: [AUTHENTICATION.md](docs/AUTHENTICATION.md) (new) · backlog: [HARVESTER_ADMIN_WEB_V5_BACKLOG.md](docs/HARVESTER_ADMIN_WEB_V5_BACKLOG.md) (new)

### DARK / ARK Persistent Identifiers

- ARK minting and per-network settings, staging (`DarkStageWorker`) and reconciliation (`DarkReconcileWorker`) workers
- dARK dashboard in the Admin UI; v5 API under `/api/v5/dark/naans/{arkNaan}/…`
- Legacy import: `import-dark-legacy-csv` runbook: [DARK_LEGACY_ARK_IMPORT.md](docs/DARK_LEGACY_ARK_IMPORT.md)

### Core Library Package Structure

`lareferencia-core-lib` uses `org.lareferencia.core.*` (10 packages):

```text
org.lareferencia.core.*
├── domain/       Domain models
├── repository/   Data access (JPA + SQLite: repository.catalog, repository.validation)
├── service/      Business logic (harvesting, validation, indexing, management)
├── metadata/     Metadata storage abstraction
├── worker/       Asynchronous processors
├── task/         Task scheduling and coordination
├── embedding/    Semantic chunking/embedding
├── flowable/     Flowable workflow delegates (optional engine)
├── oabroker/     OpenAIRE broker integration
└── util/         Shared utilities (incl. ConfigPathResolver)
```

Note: dependent projects migrate `org.lareferencia.backend.*` → `org.lareferencia.core.*` for the core libraries; the harvester application itself still uses the `org.lareferencia.backend.*` namespace. Convention: [REFACTORING_PACKAGE_STRUCTURE.md](docs/REFACTORING_PACKAGE_STRUCTURE.md).

## 🚀 Quick Start

> Step-by-step developer setup (prerequisites, profiles, run modes, testing): [ONBOARDING.md](docs/ONBOARDING.md)

### Building the Platform

```bash
git clone https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform

# Clone workspace modules declared in workspace.ini
./githelper init

# Build the standard implementation (Java modules + admin web)
./build.sh lareferencia

# Java modules only
./build-java.sh lareferencia

# Admin web only (Node 22, output copied into the harvester)
./build-admin-web.sh

# Other build profiles: lite | rcaap | ibict
# ./build.sh ibict

# Build/test only the OAI-PMH provider from the reactor
mvn -pl lareferencia-oai-pmh package
mvn -pl lareferencia-oai-pmh test
```

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

Each module is an independent Git repository cloned in the workspace root and declared in `workspace.ini`; `./githelper` coordinates them.

```bash
./githelper status                          # Parent + module status
./githelper init                            # Clone missing modules
./githelper pull                            # Pull parent branch and modules
./githelper switch <parent-branch>          # Switch parent branch (applies matching branch-set if present)
./githelper branch-set capture <name>       # Snapshot current module branches (reproducible with: ./githelper sync --set <name>)
./githelper branch create --modules lareferencia-core-lib,lareferencia-shell
./githelper url rewrite --to https
```

Development modules normally use `branch = main`; release modules can pin `tag = <version>` (optionally plus an exact `commit` SHA). Maven build profiles (`lareferencia`, `lite`, `rcaap`, `ibict`) are independent of branch-sets. See [githelper.md](githelper.md).

### Checkout a Tagged Version

```bash
git checkout 4.2.6
./githelper init
```

## 🔧 Configuration

Each application module has a `config/` directory following this model (not all modules use every entry; `application.properties.d/` is used by the harvester, shell and dashboard):

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
└── users.properties                # File-based auth (harvester; gitignored — copied automatically from users.properties.default on first run)
```

**The golden rule**: `application.properties` = local override (gitignored); `application.properties.model` = versioned template with documentation for every property. When adding a property, update the `.model` file.

**How the fragments load** (verified in code): `PropertiesDirectoryListener` (`lareferencia-core-lib`, registered in each `MainApp`) reads every `*.properties` file inside `application.properties.d/` in alphabetical order during `ApplicationEnvironmentPreparedEvent` — before any bean exists — and appends each as its own property source; each load is visible in the startup log as `[PropertiesLoader] Loaded: <filename>`. The two-digit prefixes group files by concern (`00-server`, `01-dbconnection`, `02-catalog`/`02-metadata`, `04-security`, `05-harvester`, `06-logging`, `07-dark`/`07-semantic`, `08-workflow`, `09-flowable`, `10-api-v5` in the harvester; `00-app`, `01-dbconnection`, `05-harvester`, `06-logging` in the shell). Today no key is defined twice with different values across the base file and the fragments, so the mechanism works without precedence conflicts; when adding properties, define each key in one place only.

The config base directory is resolved by `ConfigPathResolver` via the `app.config.dir` system property:

```bash
java -jar lareferencia-shell.jar                                   # default: ./config
java -Dapp.config.dir=/etc/lrharvester/config -jar harvester.jar   # custom path
```

Reference: [CONFIG_DIRECTORY.md](docs/CONFIG_DIRECTORY.md) · per-file, per-property reference for the harvester (12 fragments), the shell (4) and the dashboard (5), including which class reads each property and the legacy keys no longer read: [CONFIGURATION_PROPERTIES.md](docs/CONFIGURATION_PROPERTIES.md) · pending config-cleanup proposal: [CONFIG_CLEANUP_PROPOSAL.md](docs/CONFIG_CLEANUP_PROPOSAL.md)

## 🧪 Testing

```bash
mvn test                                   # all reactor modules
mvn -pl lareferencia-oai-pmh test          # provider protocol tests (Testcontainers, Solr 9.8)
```

- OAI-PMH regression suite: protocol verbs over HTTP validated against the official XSD ([oai-compatibility-contract](lareferencia-oai-pmh/docs/testing/oai-compatibility-contract.md))
- Incremental OAI harness with deterministic fixtures: [testing/oai-incremental](testing/oai-incremental/README.md) (provider at `localhost:8096`, or `8196` in dev)

## 📚 Documentation Map

| Document | Topic |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) * | Component map, data flows, modules, ports |
| [ONBOARDING.md](docs/ONBOARDING.md) * | New developer setup (githelper, build, profiles, run modes) |
| [GLOSSARY.md](docs/GLOSSARY.md) * | Platform vocabulary (network, dARK, crosswalk, lane, …) |
| [DOCKER_DEV.md](docs/DOCKER_DEV.md) | Isolated Docker developer workflow |
| [BACKUP_RESTORE.md](docs/BACKUP_RESTORE.md) * | Backup & restore (wizard, cron/systemd, `restore.sh`) |
| [CONFIG_DIRECTORY.md](docs/CONFIG_DIRECTORY.md) | Configuration directory resolution |
| [CONFIGURATION_PROPERTIES.md](docs/CONFIGURATION_PROPERTIES.md) * | `application.properties.d` fragments per file (harvester, shell and dashboard) |
| [ALMACENAMIENTO_REFERENCIA_RAPIDA.md](docs/ALMACENAMIENTO_REFERENCIA_RAPIDA.md) (ES) | Storage quick reference (FS/H2/SQLite, metadata stores) |
| [AUTHENTICATION.md](docs/AUTHENTICATION.md) * | Users, roles, auth modes (file/OIDC/hybrid) |
| [WORKFLOW_ACTIONS.md](docs/WORKFLOW_ACTIONS.md) * | Action catalog, scheduling, worker configuration, engines |
| [FLOWABLE_REFACTORING_STRATEGY.md](docs/FLOWABLE_REFACTORING_STRATEGY.md) | Workflow engines state (legacy / flowable) |
| [ISSUE_INCREMENTAL_RECORD_PROCESSING.md](docs/ISSUE_INCREMENTAL_RECORD_PROCESSING.md) | Incremental validation & indexing manual |
| [ENTITY_DELETED_INDEXING.md](docs/ENTITY_DELETED_INDEXING.md) | Soft-deleted entities and index cleanup |
| [ENTITY_INDEXING_ARCHITECTURE.md](docs/ENTITY_INDEXING_ARCHITECTURE.md) * | Current Elasticsearch entity indexing model |
| [INDEXING-CONFIGURATION.md](docs/INDEXING-CONFIGURATION.md) (ES) | Real indexer connection properties |
| [SEMANTIC_INDEXING_CHUNKING.md](docs/SEMANTIC_INDEXING_CHUNKING.md) | Semantic indexing & chunking |
| [HARVESTER_MANAGEMENT_API_V5.md](docs/HARVESTER_MANAGEMENT_API_V5.md) | Management API v5 |
| [HARVESTER_ADMIN_WEB_V5_BACKLOG.md](docs/HARVESTER_ADMIN_WEB_V5_BACKLOG.md) * | Admin web pending work |
| [DARK_LEGACY_ARK_IMPORT.md](docs/DARK_LEGACY_ARK_IMPORT.md) | Legacy ARK import runbook |
| [DYNAMIC_SCHEMA_REFACTORING.md](docs/DYNAMIC_SCHEMA_REFACTORING.md) | Dynamic validation schemas & i18n |
| [ARQUITECTURA_TRANSACCIONAL.md](docs/ARQUITECTURA_TRANSACCIONAL.md) (ES) | Entity transactional architecture |
| [REFACTORING_TRANSACCIONAL.md](docs/REFACTORING_TRANSACCIONAL.md) (ES) | Transactional refactoring record |
| [REFACTORING_PACKAGE_STRUCTURE.md](docs/REFACTORING_PACKAGE_STRUCTURE.md) | Package conventions |
| [DOCUMENTATION_INDEX.md](docs/DOCUMENTATION_INDEX.md) * | Full index of `docs/` with status |

\* Created or updated during the 2026-09-23 documentation work (see `docs/PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md`). Historical decision records live in `docs/archive/`.

## 📝 Migration Guide: v4.x → 5.0.0-rc2

### Required Actions

1. **Java 17+** and **Spring Boot 3.5** (javax → jakarta imports)
2. **Entity indexing on Elasticsearch** (Solr entity APIs removed)
3. **Storage**: configure `store.basepath` for filesystem + SQLite (catalog, validation, stats, logs)
4. **Configuration**: review property names for Spring Boot 3.x; keep `application.properties.model` in sync

### Breaking Changes

- Solr entity indexing APIs removed (Elasticsearch/OpenSearch instead)
- `contrib-ibict`/`contrib-rcaap` no longer compiled
- Core/entity library packages renamed to `org.lareferencia.core.*` (see note above)
- Entity indexer completely rewritten (direct threaded model)

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

When requesting support, please include: platform version (e.g. `5.0.0-rc2`), affected module, relevant log excerpts, configuration snippets (without sensitive data) and steps to reproduce.

- **Website**: [https://www.lareferencia.info](https://www.lareferencia.info)
- **Issues**: [GitHub Issues](https://github.com/lareferencia/lareferencia-platform/issues)
- **Organization**: [https://github.com/lareferencia](https://github.com/lareferencia)

---

**Note**: this checkout is a release candidate. Production deployments should use a tagged release validated by the maintainers.