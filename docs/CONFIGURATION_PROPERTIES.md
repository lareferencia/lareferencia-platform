# Configuration: `application.properties.d`

**Status:** current · **Last verified:** 2026-09-29

Reference for the split-configuration mechanism used by `lareferencia-lrharvester-app`
and `lareferencia-shell`, with a per-file, per-property breakdown verified against the
code (class references included).

## How loading works

Registered in each application's main class via `builder.listeners(new PropertiesDirectoryListener())`
— harvester `MainApp` (~:81) and shell `MainApp` (~:49):

- `PropertiesDirectoryListener` (`lareferencia-core-lib`, `org.lareferencia.core.util`) reacts to
  `ApplicationEnvironmentPreparedEvent` — i.e. it runs very early, before any bean exists.
- It resolves `${app.config.dir}/application.properties.d/` through
  [`ConfigPathResolver`](CONFIG_DIRECTORY.md) (`app.config.dir` system property, default `config`).
- Every `*.properties` file in the directory is loaded **sorted alphabetically by filename**,
  each as its own `PropertySource` named `custom-<filename>`, appended to the environment with
  `addLast`. A load failure is logged and startup continues.
- Progress is visible in the startup log as `[PropertiesLoader] Loaded: <filename>`.
  If the directory is missing: `[PropertiesLoader] Directory not found: …` and startup continues.

Conventions:

- The two-digit prefix (`00-`, `01-`, …) groups files by concern; it is a reading-order
  convention, not a precedence contract. Among the `.d` files there are currently no
  duplicated keys.
- `config/application.properties` (the module base file) holds deployment-specific values
  (database credentials, storage paths, Solr URLs). It is a normal Spring Boot config-data
  file (loaded from the default `./config/` location) and the `.model` copies are pristine
  templates of it.
- Avoid defining the same key in both the base file and `.d` fragments; if you must, verify the
  effective value in your runtime (actuator `env`, or a startup log line) instead of assuming
  an override order.
- `app.config.dir` relocates the whole directory (including the `.d` folder). Note:
  `config.dir.path=config` present in the shell's `00-app.properties` is **not read by any
  code** — the real key is `app.config.dir`.

---

## lareferencia-lrharvester-app — `config/application.properties.d/`

### `00-server.properties` — HTTP server

| Property | Value / default | Read by | Notes |
|---|---|---|---|
| `server.port` | `8090` | Spring Boot | Container port; Docker Dev publishes loopback at `8190` in isolated mode |
| `spring.data.rest.basePath` | `/rest` | Spring Data REST | Legacy surface is denied by the v5 security chain; do not use it as an API |
| `spring.jackson.serialization.fail-on-empty-beans` | `false` | Jackson | |
| `server.ssl.*` | commented | Spring Boot | Uncomment to enable HTTPS with `config/localhost.p12` (pkcs12) |

### `01-dbconnection.properties` — JPA / connection pool

| Property | Value | Notes |
|---|---|---|
| `spring.datasource.hikari.minimum-idle` | `10` | HikariCP pool |
| `spring.datasource.hikari.maximum-pool-size` | `50` | |
| `spring.jpa.hibernate.ddl-auto` | `none` | Use `update` only for dev with H2/SQLite |
| `spring.jpa.hibernate.naming.physical-strategy` | `PhysicalNamingStrategyStandardImpl` | |
| `spring.jpa.open-in-view` | `true` | |

Credentials and JDBC URL live in the base `application.properties` (PostgreSQL `lrharvester`
by default; H2/SQLite alternatives are commented there).

### `02-catalog.properties` — SQLite catalog

| Property | Value | Read by | Notes |
|---|---|---|---|
| `catalog.batch.size` | `5000` | `OAIRecordCatalogRepository` (~:67, default 5000) | Insert batch size |
| `catalog.sqlite.wal-mode` | `true` | `CatalogDatabaseManager` (~:77, default true) | WAL for read concurrency |
| `catalog.connection.timeout` | `30` | **not read** | Candidate for removal |

### `02-metadata.properties` — metadata store selection

The file itself is all comments: the effective key is `metadata.store.type`, resolved by SpEL
in `lareferencia-lrharvester-app/src/main/resources/application-context.xml` (~:73-75):
`FS` → `MetadataStoreFSImpl` (default), `H2` → `MetadataStorePerNetworkH2Impl`,
`SQLITE` → `MetadataStorePerNetworkSQLiteImpl`. See [`ALMACENAMIENTO_REFERENCIA_RAPIDA.md`](ALMACENAMIENTO_REFERENCIA_RAPIDA.md).

### `04-security.properties` — retired

Harvester v5 no longer reads `security.users.file` or
`security.users.default-file`; there is no file-based authentication fragment.
Local identities and grants live in PostgreSQL. See
[`AUTHENTICATION.md`](AUTHENTICATION.md) for initial administrator setup.

### `05-harvester.properties` — harvesting and task manager

| Property | Value | Read by | Notes |
|---|---|---|---|
| `harvester.max.retries` | `10` | `HarvestingWorker` (~:123, **no default — required**) | |
| `harvester.retry.seconds` | `3` | `OCLCBasedHarvesterImpl` (~:78, **no default**) | Base retry delay |
| `harvester.retry.factor` | `2` | same (~:81, **no default**) | Exponential factor |
| `scheduler.pool.size` | `10` | `TaskManagerConfig` (~:53, default 10) | `TaskScheduler` pool |
| `taskexecutor.pool.size` | `10` | **not read in main code** (only an integration test) | Candidate for removal |
| `taskmanager.clean.interval` | `60000` | **not read** | Candidate for removal |
| `taskmanager.concurrent.tasks` | `4` | `TaskManager` (~:114, default 4) | Max workers running concurrently |
| `taskmanager.max_queuded.tasks` | `32` | `TaskManager` (~:117, default 32) | Note the misspelled key (`queuded`) is the real one |
| `reponame.fieldname` / `reponame.prefix` / `instname.*` | `dc:source`… | **not read** | v4 legacy; today crosswalks/indexing XML carry the `reponame:`/`instname:` logic (e.g. `lr-elastic-indexing.xml`) |

### `06-logging.properties` — log levels

Working keys: `logging.level.org.lareferencia=INFO`,
`logging.level.org.lareferencia.core.dark=INFO`,
`logging.level.org.lareferencia.backend.controllers.BackendController=DEBUG` (controller still exists).

Stale keys (packages no longer exist after the v5 refactor — they log nothing):
`logging.level.org.lareferencia.backend.taskmanager` (now `core.task`) and
`logging.level.org.lareferencia.backend.validation` (now `core.worker.validation`).

### `07-dark.properties` — dARK / ARK

Bound by `DarkProperties` (`@ConfigurationProperties(prefix = "dark")`,
`lareferencia-dark-lib/.../services/DarkProperties.java`):

| Property | Value | Code default |
|---|---|---|
| `dark.minter.base-url` | `http://dark-core-01.dark-pid.net:8001` | `http://localhost:8001` |
| `dark.authority-id` | `<uuid>` | unset (**required** — the stage worker fails without it) |
| `dark.auth-header-name` | `X-Authority-Id` | `X-Authority-Id` |
| `dark.metadata.schema` | `xoai` | `dublin_core`; if it differs from `network.metadataStoreSchema`, metadata is transformed with configured crosswalks |
| `dark.metadata.media-type` | `application/xml` | `application/xml` |
| `dark.stage.page-size` | `100` | `100` |
| `dark.reserve.batch-size` | `100` | `100` |
| `dark.reconcile.page-size` | `100` | `100` |

Additional keys accepted by the same binder (not present in the file):
`dark.minter.retry.max-retries` (default 5), `dark.minter.retry.backoff-seconds`
(default `5,30,60,180,300`), `dark.stage.max-pages-per-run` (default `0` = unlimited).

Notes: the ARK NAAN is configured **per network** via `network.attributes.ark_naan`;
`dark.minter.url=…/load` in the base `application.properties` is a v4 leftover and is **not
read** (the real key is `dark.minter.base-url`). Real dARK API routes: see
[`HARVESTER_MANAGEMENT_API_V5.md`](HARVESTER_MANAGEMENT_API_V5.md).

### `07-semantic.properties` — semantic embeddings

| Property | Value | Read by (default) |
|---|---|---|
| `embedding.api.url` | `http://localhost:8989/api/v1/embeddings` | `EmbeddingAPIConfig` (~:57, default `http://localhost:11434/api`), `SemanticIndexerWorker` (~:158) |
| `embedding.model.name` | `bge-m3` | client config |
| `embedding.model.dimension` | `1024` | vector schema |
| `embedding.api.timeout.seconds` | `60` | HTTP client |
| `embedding.max.segment.size.tokens` | `128` | `ChunkingService` |
| `embedding.max.overlap.size.tokens` | `0` | `ChunkingService` (≤ segment size) |
| `embedding.max.chunks.size` | `5` | `ChunkingService` (~:59, default 5) |
| `embedding.api.key` | commented | optional, for external embedding APIs |
| `embedding.title.field` / `embedding.abstract.field` | `dc.title.*` / `dc.description.*` | field selection |
| `embedding.title.standalone.indexing.min.words` | `5` | |
| `embedding.vector.field.name` / `embedding.use.multivalued.vector` | `vector_multivalued` / `true` | Solr vector field |

Chunking algorithm details: [`SEMANTIC_INDEXING_CHUNKING.md`](SEMANTIC_INDEXING_CHUNKING.md).
The worker indexes into `semantic.solr.url` (falls back to `frontend.solr.url`,
`SemanticIndexerWorker` ~:121).

### `08-workflow.properties` — engine selection

| Property | Value | Read by |
|---|---|---|
| `workflow.engine` | `legacy` | `TaskManagerConfig` (legacy when `legacy` **or unset**), `TransactionManagerConfig` (~:44, Flowable only when `flowable`) |
| `workflow.max-queued-processes` | `32` | `WorkflowProperties.maxQueuedProcesses` (`core.flowable.config`, default 32) |

> The in-file comment says "Default: flowable" — **that is wrong**: with the property unset
> the legacy engine runs. `WorkflowProperties` also accepts `workflow.max-queued-per-lane`
> (default 10) and `workflow.scheduler-pool-size` (default 5), not set in the file.

### `09-flowable.properties` — Flowable engine (only when `workflow.engine=flowable`)

| Property | Value | Notes |
|---|---|---|
| `spring.liquibase.enabled` | `false` | Flowable manages its own schema via `flowable.database.schema-update` |
| `flowable.process.definitions.location` | `file:config/processes/**/*.bpmn20.xml` | auto-deployment of the 7 BPMN processes |
| `flowable.datasource.jdbc-url` | `jdbc:postgresql://localhost:5432/lrharvester_flowable` | **separate database**, same server; H2/SQLite variants are commented in-file |
| `flowable.datasource.username` / `password` | `${spring.datasource.*}` | |
| `flowable.datasource.hikari.*` | idle 2 / max 10 / timeout 30s / idle-timeout 10m / max-lifetime 30m | pool independent from the main one |
| `flowable.database.schema-update` | `true` | set `false` in production once created |
| `flowable.async-executor-activate` | `true` | background jobs |
| `flowable.async-executor.number-of-retries` | `0` | no retries (clean shutdown) |
| `flowable.async-executor.core-pool-size` / `max-pool-size` | `2` / `10` | |
| `flowable.id-generator` | `uuid` | |

### `10-api-v5.properties` — management API v5

`security.api-v5.allowed-origins=` (no cross-origin browser access by default),
`security.api-v5.page-size-max=200`,
`api-v5.attribute-profiles-location=file:config/attribute-profiles`, and the
`springdoc.*` block (OpenAPI `/api/v5/openapi`, Swagger `/api/v5/docs`, path/package filters).
Distributed configuration sets `HttpOnly=true`, `SameSite=Lax`, a 30-minute
timeout, and both session and CSRF Secure flags to `false` for HTTP development.
For HTTPS deployments, set both `security.api-v5.cookies-secure=true` and
`server.servlet.session.cookie.secure=true`. The CSRF Secure flag falls back to
`true` in code if its property is omitted. Spring Session JDBC uses the Flyway-created schema. Authentication no longer
has a `file`/`oidc`/`hybrid` mode. Full details: [`AUTHENTICATION.md`](AUTHENTICATION.md).
Reference: [`AUTHENTICATION.md`](AUTHENTICATION.md) · [`HARVESTER_MANAGEMENT_API_V5.md`](HARVESTER_MANAGEMENT_API_V5.md).

---

## lareferencia-shell — `config/application.properties.d/`

### `00-app.properties` — Spring Shell

`spring.shell.interactive.enabled=true`, `spring.shell.command.version.enabled=true`,
`spring.shell.command.help.enabled=true`, `spring.liquibase.enabled=false`
(the shell does not run changelogs; migrations run via the `database_migrate` command).
`config.dir.path=config` is **not read** — the real key is `app.config.dir`.

### `01-dbconnection.properties` — JPA + Flyway

Same HikariCP/JPA block as the harvester (`minimum-idle 10`, `maximum-pool-size 50`,
`ddl-auto none`, standard physical naming, `open-in-view true`) plus:

| Property | Value | Notes |
|---|---|---|
| `spring.flyway.enabled` | `false` | disabled by default; the `database_migrate` command enables/uses Flyway |
| `spring.flyway.user` / `password` / `url` | `${spring.datasource.*}` | credentials templated from the main datasource |

### `05-harvester.properties` — same block as the harvester's `05`

Identical keys and values (`harvester.*`, `scheduler.pool.size`, `taskmanager.*`,
`reponame.*`/`instname.*`), including the same two dead keys (`taskmanager.clean.interval`,
`taskexecutor.pool.size`) and the unread `reponame.*`/`instname.*`.

### `06-logging.properties`

Only commented examples (`logging.level.root`, `org.lareferencia.core.dark`).

### Base `application.properties` (shell)

PostgreSQL `jdbc:postgresql://localhost:5432/lrharvester`, `store.basepath=/tmp/data/`,
plus two blocks worth flagging:

- `solr.host` — **not read by the shell**; it is read by `lareferencia-entity-rest`
  (`LareferenciaEntityRestApplication` ~:73). Shell indexing workers use
  `semantic.solr.url`/`frontend.solr.url` instead.
- `workflow.max-queued-processes=32`, the `workflow.processes.<name>.lane` block and the
  `workflow.lanes[n]` definitions — **not read by current code**. Serial lanes are configured
  per worker bean with `serialLaneId` in the `config/beans/*actions.xml` (e.g. value `1` in
  `index.elastic.actions.xml`) and enforced by the `TaskManager` queue map
  (`TaskManager` ~:112-345).
- `elastic.*` — indexer connection properties documented in
  [`ENTITY_INDEXING_ARCHITECTURE.md`](ENTITY_INDEXING_ARCHITECTURE.md) /
  [`INDEXING-CONFIGURATION.md`](INDEXING-CONFIGURATION.md).

---

---

## Modules without `application.properties.d`

- `lareferencia-entity-rest`: `config/` contains only `application.properties.model` and
  legacy `*-context.xml` files — no fragments, no live base. The runtime
  `config/application.properties` must be created manually from the model (the app reads
  e.g. `solr.host` from there, `LareferenciaEntityRestApplication` ~:73).
- `lareferencia-oai-pmh`: `config/` has `application.properties.model`, `crosswalks/` and
  log4j files — no fragments; Docker provides the live config at deploy time
  (`APP_CONFIG_DIR` + `EXTERNAL_CONFIG_DIR=/config` volume in `docker-compose.yml`).
- VuFind (PHP), `lareferencia-solr-cores` and the libraries are not Spring Boot config modules.

---

## Maintenance notes (2026-09-23 review)

Pending: the proposed removal of these keys (plus template and local-file hygiene) is
documented in [`CONFIG_CLEANUP_PROPOSAL.md`](CONFIG_CLEANUP_PROPOSAL.md) — the config
files themselves are untouched as of 2026-09-23.

Keys present in config but not read by current code (safe cleanup candidates — confirm per
deployment before removing):

- `catalog.connection.timeout` (harvester `02-catalog`)
- `taskmanager.clean.interval`, `taskexecutor.pool.size`, `reponame.*`, `instname.*`
  (both `05-harvester.properties`)
- `config.dir.path` (shell `00-app.properties` and base files) → use `app.config.dir`
- `dark.minter.url` (harvester base) → superseded by `dark.minter.base-url`
- `workflow.processes.*.lane` / `workflow.lanes[n]` (shell base) → use `serialLaneId` in beans XML
- `solr.host` (shell base) → not consumed by the shell itself
- stale comment in dashboard `00-server.properties` ("Access via http://localhost:8090" —
  the port is 8092)
- stale loggers in harvester `06-logging.properties` (`backend.taskmanager`, `backend.validation`)
- the "Default: flowable" comment in `08-workflow.properties` contradicts the code
  (real default: legacy)

Related: [`CONFIG_DIRECTORY.md`](CONFIG_DIRECTORY.md) (config dir resolution) ·
[`WORKFLOW_ACTIONS.md`](WORKFLOW_ACTIONS.md) (engines and actions) ·
[`AUTHENTICATION.md`](AUTHENTICATION.md) · [`ENTITY_INDEXING_ARCHITECTURE.md`](ENTITY_INDEXING_ARCHITECTURE.md)
