# Glossary

**Status:** current · **Last verified:** 2026-09-23

Vocabulary used across the platform and its documentation. Links point to the document
with the details ([DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md) for everything else).

| Term | Meaning |
|---|---|
| **Action** | A schedulable, configurable operation (harvest, validate, index, …) defined in `config/beans/*actions.xml`; since `V5.0.0.8` their configuration is consolidated in database tables. → [WORKFLOW_ACTIONS.md](WORKFLOW_ACTIONS.md) |
| **Admin Web** | The React UI (`lareferencia-lrharvester-admin-web`) built into the harvester's `static/` and served at `/` on port 8090. |
| **ARK** | Persistent identifier of the `ark:/NAAN/name` form minted through dARK. |
| **NAAN** | Name Assigning Authority Number — the registry number inside an ARK; configured **per network** via `network.attributes.ark_naan`. |
| **dARK** | Decentralized ARK service: external minter plus the `lareferencia-dark-lib` client used for reserving/staging/reconciling identifiers. → [HARVESTER_MANAGEMENT_API_V5.md](HARVESTER_MANAGEMENT_API_V5.md) |
| **Minter** | The dARK service that creates ARKs (`dark.minter.base-url`; the v4 `dark.minter.url` key is dead). |
| **Authority ID** | dARK user identifier sent as `X-Authority-Id` (`dark.authority-id`, required). |
| **Catalog** | The SQLite database tracking harvested records, including per-record `change_type` `N`/`U`/`D` (new/updated/deleted) that drives incremental processing. → [ISSUE_INCREMENTAL_RECORD_PROCESSING.md](ISSUE_INCREMENTAL_RECORD_PROCESSING.md) |
| **Crosswalk** | Mapping XML bean that transforms source metadata into the target schema (e.g. `lr-elastic-indexing.xml`). |
| **Entity** | Record-level item derived from transformed metadata, with relations; soft-deleted via the `deleted` flag. → [ENTITY_DELETED_INDEXING.md](ENTITY_DELETED_INDEXING.md) |
| **Fingerprint / manifest** | Validation-reuse mechanism: a fingerprint identifies unchanged inputs so the previous validation result is reused instead of re-running. → [ISSUE_INCREMENTAL_RECORD_PROCESSING.md](ISSUE_INCREMENTAL_RECORD_PROCESSING.md) |
| **Harvesting** | Pulling records from an OAI-PMH repository (client library: `lareferencia-oclc-harvester`). |
| **Incremental processing** | Operating only on records whose `change_type` says they changed, instead of reprocessing whole networks. |
| **Lane (serial lane)** | Queue constraint that serializes certain workers; configured per worker bean with `serialLaneId` in `config/beans/*actions.xml` — **not** via the (dead) `workflow.processes.*.lane` keys. → [WORKFLOW_ACTIONS.md](WORKFLOW_ACTIONS.md) |
| **Legacy engine** | The default in-memory workflow engine (`TaskManager`); Flowable is the persistent alternative (`workflow.engine=flowable`). |
| **Flowable** | BPMN-based workflow engine (optional, separate `lrharvester_flowable` database). → [FLOWABLE_REFACTORING_STRATEGY.md](FLOWABLE_REFACTORING_STRATEGY.md) |
| **Metadata store** | Where transformed metadata records live: filesystem by default (`FS`), with H2/SQLite per-network variants selected by `metadata.store.type`. → [ALMACENAMIENTO_REFERENCIA_RAPIDA.md](ALMACENAMIENTO_REFERENCIA_RAPIDA.md) |
| **Network** | The top-level configuration unit: a set of OAI-PMH sources with format, validation rules, transformations and attributes (including the dARK NAAN). |
| **OAI-PMH** | The harvesting protocol; the platform is both harvester (client) and provider (`lareferencia-oai-pmh`, port 8096). |
| **Profile (build)** | Maven profile selecting country branding/dependencies: `lareferencia` (default), `ibict`, `rcaap`. |
| **Provider** | The `lareferencia-oai-pmh` module serving OAI-PMH from the Solr `oai` core. |
| **Solr core** | A Solr index with its schema; `lareferencia-solr-cores` holds the definitions (canonical `oai` core is `LUCENE_42`; services run Solr 9.8 copies). |
| **Snapshot** | Directory of a validation run's persisted state (catalog + validation DBs), used for reuse/rollback. |
| **TaskManager / Worker** | The legacy engine's executor (`TaskManager`) and the unit that performs an action (`HarvestingWorker`, `SemanticIndexerWorker`, …). |
| **Validation rules** | JSON-defined rules (dynamic schemas + i18n) executed per record. → [DYNAMIC_SCHEMA_REFACTORING.md](DYNAMIC_SCHEMA_REFACTORING.md) |
| **VuFind** | The end-user search UI (PHP, external fork, separate database). |

Related: [`ARCHITECTURE.md`](ARCHITECTURE.md) · [`CONFIGURATION_PROPERTIES.md`](CONFIGURATION_PROPERTIES.md) ·
[`DOCUMENTATION_INDEX.md`](DOCUMENTATION_INDEX.md)