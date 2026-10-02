# Documentation Index

**Status:** current · **Last verified:** 2026-09-29

Built during the 2026-09-23 documentation overhaul (see
[`PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md`](PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md)).
Every document carries a status line: `current` = verified against the code on that date;
`historical` = decision record / analysis snapshot kept for context (its notes state what changed);
`archived` = moved to [`archive/`](archive/README.md) with a banner.

`docs/DARK_ISSUES_PLAN_CONTEXT.md` is excluded from this index until its content is committed.

## Reference — current

| Document | Topic |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Component map, data flows, module table, ports (mermaid diagram) |
| [`ONBOARDING.md`](ONBOARDING.md) | Developer setup: githelper, build scripts, profiles, run modes, testing |
| [`GLOSSARY.md`](GLOSSARY.md) | Platform vocabulary with links to the detailed docs |
| [`AUTHENTICATION.md`](AUTHENTICATION.md) | Local PostgreSQL identities, bootstrap, sessions/CSRF, tokens and network authorization |
| [`DASHBOARD_V5_MIGRATION.md`](DASHBOARD_V5_MIGRATION.md) | Checklist to migrate the Angular repository dashboard to local auth and read-only v5 APIs |
| [`BACKUP_RESTORE.md`](BACKUP_RESTORE.md) | Automated backup via `docker.sh wizard` + restore script |
| [`CONFIG_DIRECTORY.md`](CONFIG_DIRECTORY.md) | `app.config.dir` and `ConfigPathResolver` |
| [`CONFIGURATION_PROPERTIES.md`](CONFIGURATION_PROPERTIES.md) | `application.properties.d` per-file/per-property reference (harvester and shell) |
| [`CONFIG_CLEANUP_PROPOSAL.md`](CONFIG_CLEANUP_PROPOSAL.md) | Proposed removal of dead config keys + template fixes (on hold — configs untouched) |
| [`DOCKER_DEV.md`](DOCKER_DEV.md) | Isolated developer Docker workflow (`docker-dev.sh`) |
| [`../Docker/README.md`](../Docker/README.md) | Normal Docker wizard, endpoints, destructive commands |
| [`ENTITY_DELETED_INDEXING.md`](ENTITY_DELETED_INDEXING.md) | Entity `deleted` flag workflow + shell commands |
| [`ENTITY_INDEXING_ARCHITECTURE.md`](ENTITY_INDEXING_ARCHITECTURE.md) | Current Elasticsearch/OpenSearch indexer model + real properties |
| [`FLOWABLE_REFACTORING_STRATEGY.md`](FLOWABLE_REFACTORING_STRATEGY.md) | Workflow engines state (`legacy` / `flowable`) |
| [`HARVESTER_ADMIN_WEB_V5_BACKLOG.md`](HARVESTER_ADMIN_WEB_V5_BACKLOG.md) | Admin Web + API v5 backlog (what is not done yet) |
| [`HARVESTER_MANAGEMENT_API_V5.md`](HARVESTER_MANAGEMENT_API_V5.md) | `/api/v5` resources, contract, security, new endpoints |
| [`INDEXING-CONFIGURATION.md`](INDEXING-CONFIGURATION.md) | Real indexer configuration properties (buffer/DLQ props removed) |
| [`ISSUE_INCREMENTAL_RECORD_PROCESSING.md`](ISSUE_INCREMENTAL_RECORD_PROCESSING.md) | Incremental record processing (implemented 2026-09-04) |
| [`WORKFLOW_ACTIONS.md`](WORKFLOW_ACTIONS.md) | Actions, scheduling, engines, `V5.0.0.8` configuration tables |
| [`SEMANTIC_INDEXING_CHUNKING.md`](SEMANTIC_INDEXING_CHUNKING.md) | Chunking for semantic embeddings |
| [`DARK_LEGACY_ARK_IMPORT.md`](DARK_LEGACY_ARK_IMPORT.md) | Importing legacy ARK mappings into dARK |
| [`ALMACENAMIENTO_REFERENCIA_RAPIDA.md`](ALMACENAMIENTO_REFERENCIA_RAPIDA.md) | Storage quick reference (es) |
| [`REFACTORING_PACKAGE_STRUCTURE.md`](REFACTORING_PACKAGE_STRUCTURE.md) | Package conventions (`org.lareferencia.core`, 10 packages) |

## Decision records — historical

| Document | Note |
|---|---|
| [`ANALISIS_MERGE_ENTIDADES.md`](ANALISIS_MERGE_ENTIDADES.md) | Merge design record; function is now `merge_dirty_entities_and_relations()` (implemented) |
| [`ANALISIS_SYNCHRONIZED.md`](ANALISIS_SYNCHRONIZED.md) | §2/§3 resolved in code; inventory kept as reference |
| [`ARQUITECTURA_TRANSACCIONAL.md`](ARQUITECTURA_TRANSACCIONAL.md) | Transaction architecture; "recommended configuration" is not applied anywhere |
| [`REFACTORING_TRANSACCIONAL.md`](REFACTORING_TRANSACCIONAL.md) | Implemented; read-only transactions close with `rollback()` |
| [`DYNAMIC_SCHEMA_REFACTORING.md`](DYNAMIC_SCHEMA_REFACTORING.md) | Historical implementation record; its frontend path references predate React-only static |
| [`WORKERS_TASKS_ACTIONS_ANALYSIS.md`](WORKERS_TASKS_ACTIONS_ANALYSIS.md) | Incremental processing already implemented |
| [`IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md`](IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md) | Migrations consolidated in `V5.0.0.8` |
| [`AUTENTICACION_FILE_BASED.md`](AUTENTICACION_FILE_BASED.md) | Historical file-based auth mechanism (removed; superseded by `AUTHENTICATION.md`) |
| [`PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md`](PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md) | Historical documentation plan snapshot — its authentication and legacy-UI findings were superseded on 2026-09-29 |

## Archived

Moved to [`archive/`](archive/README.md) on 2026-09-23 (7 documents, each with a banner):
pipeline multithread removed, pre-incremental catalog analyses, readonly-transaction proposal,
Admin Web v5 technical plan (executed), package migration guide (merged) and the unmaintained `changelog.md`.

## Component READMEs (updated/verified 2026-09-23)

| README | Highlight |
|---|---|
| [`lareferencia-core-lib`](../lareferencia-core-lib/README.md) | 10 packages table, incremental behavior, config/workflow links |
| [`lareferencia-core-lib/src/test`](../lareferencia-core-lib/src/test/README.md) | Test suite report (snapshot disclaimer; no AssertJ/JaCoCo) |
| [`lareferencia-lrharvester-app`](../lareferencia-lrharvester-app/README.md) | React-only at `/`, API v5 with local users and scoped tokens |
| [`lareferencia-lrharvester-admin-web`](../lareferencia-lrharvester-admin-web/README.md) | React SPA build/development, session and CSRF behavior |
| [`lareferencia-entity-lib`](../lareferencia-entity-lib/README.md) | `deleted` flag, dirty-entity merge, indexer model links |
| [`lareferencia-entity-rest`](../lareferencia-entity-rest/README.md) | Transition state: only `GET /search/entity/{type}` active |
| [`lareferencia-repository-dashboard`](../lareferencia-repository-dashboard/README.md) | Angular repository dashboard; local auth and read-only API v5 migration planned in [DASHBOARD_V5_MIGRATION.md](DASHBOARD_V5_MIGRATION.md) |
| [`lareferencia-shell`](../lareferencia-shell/README.md) | Command reference and initial local administrator bootstrap |
| [`lareferencia-indexing-filters-lib`](../lareferencia-indexing-filters-lib/README.md) | FieldOccurrenceFilter strategies |
| [`lareferencia-solr-cores`](../lareferencia-solr-cores/README.md) | Cores table, Solr 9 copies, canonical `oai` still `LUCENE_42` |

Unchanged (verified as valid in the audit): `lareferencia-dark-lib`, `lareferencia-oai-pmh`,
`lareferencia-oclc-harvester`, `lareferencia-shell-entity-plugin`, `lareferencia-contrib-*`.

## Subproject and infrastructure docs

| Document | Note |
|---|---|
| [`lareferencia-oai-pmh/docs/architecture/0001-platform-alignment.md`](../lareferencia-oai-pmh/docs/architecture/0001-platform-alignment.md) | + addendum 2026-09-23: provider integrated in reactor/compose/workspace |
| [`lareferencia-oai-pmh/docs/testing/oai-compatibility-contract.md`](../lareferencia-oai-pmh/docs/testing/oai-compatibility-contract.md) | Tests use the provider's own Solr 9.8 core copy; layer 5 pending |
| [`testing/oai-incremental/README.md`](../testing/oai-incremental/README.md) | Ports corrected (8096/8196), `--core` unused, manifest scope behavior |
| [`.agent/workflows/configure-vufind.md`](../.agent/workflows/configure-vufind.md) | Personal absolute path removed |
| [CloudFormation infrastructure repository](https://github.com/LA-Referencia-IOI/larefererencia-infra-cloudformation) | EC2 templates, machine configurations, and deployment/monitoring scripts |

## How to keep this healthy

1. New documents start with `**Status:** current · **Last verified:** <date>`.
2. When a document becomes a historical record instead of a live reference, change its status line and add a note describing what changed.
3. Superseded documents move to `archive/` with a banner and a row in [`archive/README.md`](archive/README.md).
4. Re-verify after big merges; bump the `Last verified` date instead of silently editing.
