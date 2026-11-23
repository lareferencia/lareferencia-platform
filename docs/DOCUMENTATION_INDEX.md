# Documentation Index

**Status:** current · **Last verified:** 2026-11-23

Built during the 2026-09-23 documentation overhaul (see
[`PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md`](PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md)).
Status labels distinguish operating guides from earlier records. `current` = reviewed on the stated date;
`historical` = decision record / analysis snapshot kept for context (its notes state what changed);
`archived` = moved to [`archive/`](archive/README.md) with a banner.

Start with the [RC5 changelog](../CHANGELOG.md#500-rc5) and
[upgrade notes from RC4](../CHANGELOG.md#upgrading-from-500-rc4).
Relative links to module files resolve in the complete release ZIP or after
`./githelper init` in a source checkout.

## Reference — current

| Document | Topic |
|---|---|
| [`CHANGELOG.md`](../CHANGELOG.md) | Release history, upgrade steps and compatibility |
| [`../githelper.md`](../githelper.md) | Frozen installation, feature branches, PRs and prepared releases |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Component map, data flows, module table, ports (mermaid diagram) |
| [`ONBOARDING.md`](ONBOARDING.md) | Developer setup: githelper, build scripts, profiles, run modes, testing |
| [`GLOSSARY.md`](GLOSSARY.md) | Platform vocabulary with links to the detailed docs |
| [`AUTHENTICATION.md`](AUTHENTICATION.md) | Local PostgreSQL identities, bootstrap, sessions/CSRF, tokens and network authorization |
| [Dashboard configuration](../lareferencia-repository-dashboard/docs/CONFIGURATION.md) | React Dashboard modules, usage statistics and repository access |
| [`BACKUP_RESTORE.md`](BACKUP_RESTORE.md) | Automated backup via `docker.sh wizard` + restore script |
| [`CONFIG_DIRECTORY.md`](CONFIG_DIRECTORY.md) | `app.config.dir` and `ConfigPathResolver` |
| [`CONFIGURATION_PROPERTIES.md`](CONFIGURATION_PROPERTIES.md) | `application.properties.d` per-file/per-property reference (harvester and shell) |
| [`DOCKER_DEV.md`](DOCKER_DEV.md) | Isolated developer Docker workflow (`docker-dev.sh`) |
| [`../Docker/README.md`](../Docker/README.md) | Normal Docker wizard, endpoints, destructive commands |
| [`ENTITY_DELETED_INDEXING.md`](ENTITY_DELETED_INDEXING.md) | Entity `deleted` flag workflow + shell commands |
| [`METADATA_EXPORT.md`](METADATA_EXPORT.md) | Java export commands, profiles and installation of the Python processing workflows |
| [`EMBEDDING_METADATA.md`](../lareferencia-metadata-tools/docs/EMBEDDING_METADATA.md) | Prepare standalone annotated packages and embedding input texts; UY acceptance results |
| [`METADATA_EXCHANGE_FORMAT.md`](METADATA_EXCHANGE_FORMAT.md) | Detailed package, record, mapping, provenance, SQLite index and enrichment return contracts |
| [`LICENSE_METADATA_EXTRACTION.md`](../lareferencia-metadata-tools/docs/LICENSE_METADATA_EXTRACTION.md) | Rights extraction, license value counts and consolidation across 17 countries |
| [`METADATA_ENRICHMENT_PACKAGE.md`](../lareferencia-metadata-tools/docs/METADATA_ENRICHMENT_PACKAGE.md) | Rights pipeline, SQLite editions and vector lookup |
| [`VALIDACION_COMPATIBILIDAD.md`](VALIDACION_COMPATIBILIDAD.md) | Rule compatibility, full revalidation, upgrade and rollback, optional SQLite enrichment import |
| [`ENTITY_INDEXING_ARCHITECTURE.md`](ENTITY_INDEXING_ARCHITECTURE.md) | Current Elasticsearch/OpenSearch indexer model + real properties |
| [`FLOWABLE_REFACTORING_STRATEGY.md`](FLOWABLE_REFACTORING_STRATEGY.md) | Workflow engines state (`legacy` / `flowable`) |
| [`HARVESTER_ADMIN_WEB_V5_BACKLOG.md`](HARVESTER_ADMIN_WEB_V5_BACKLOG.md) | Admin Web + API v5 backlog (what is not done yet) |
| [`HARVESTER_MANAGEMENT_API_V5.md`](HARVESTER_MANAGEMENT_API_V5.md) | `/api/v5` resources, contract, security, new endpoints |
| [`INDEXING-CONFIGURATION.md`](INDEXING-CONFIGURATION.md) | Real indexer configuration properties (buffer/DLQ props removed) |
| [`ISSUE_INCREMENTAL_RECORD_PROCESSING.md`](ISSUE_INCREMENTAL_RECORD_PROCESSING.md) | Incremental record processing (implemented 2026-09-04) |
| [`INDEXING_RESULTS.md`](INDEXING_RESULTS.md) | Per-worker snapshot indexing status and filter behavior |
| [`WORKFLOW_ACTIONS.md`](WORKFLOW_ACTIONS.md) | Actions, scheduling, engines, `V5.0.0.8` configuration tables |
| [`TASKMANAGER_OPERATIONS_GUIDE.md`](TASKMANAGER_OPERATIONS_GUIDE.md) | TaskManager configuration, queue monitoring and deployment |
| [`SEMANTIC_INDEXING_CHUNKING.md`](SEMANTIC_INDEXING_CHUNKING.md) | Online embedding chunking and the precomputed SQLite vector indexing and removal actions |
| [`DARK_ISSUES_PLAN_CONTEXT.md`](DARK_ISSUES_PLAN_CONTEXT.md) | Committed implementation plan for manual dARK operations; describes scope rather than a blanket runtime verification |
| [`DARK_LEGACY_ARK_IMPORT.md`](DARK_LEGACY_ARK_IMPORT.md) | Importing legacy ARK mappings into dARK |
| [`ALMACENAMIENTO_REFERENCIA_RAPIDA.md`](ALMACENAMIENTO_REFERENCIA_RAPIDA.md) | Storage quick reference (es) |
| [`REFACTORING_PACKAGE_STRUCTURE.md`](REFACTORING_PACKAGE_STRUCTURE.md) | Package conventions (`org.lareferencia.core`, including metadata export) |
| [`SINGLE_ACCEPTED_VOCABULARY_VALIDATOR.md`](SINGLE_ACCEPTED_VOCABULARY_VALIDATOR.md) | Single accepted vocabulary term rules and diagnostics |
| [`DESCRIPCION_PLATAFORMA_WEB.md`](DESCRIPCION_PLATAFORMA_WEB.md) | Platform capabilities for a general audience (es) |

## Decision records — historical

| Document | Note |
|---|---|
| [`RELEASE_5.0.0_RC4.md`](RELEASE_5.0.0_RC4.md) | RC4 integration report |
| [`DASHBOARD_V5_MIGRATION.md`](DASHBOARD_V5_MIGRATION.md) | Earlier Angular integration checklist for local authentication and API v5 |
| [`DASHBOARD_PLAN_MIGRACION_REACT.md`](DASHBOARD_PLAN_MIGRACION_REACT.md) | React migration plan and implementation record |
| [`DASHBOARD_PLAN_CONSOLIDACION.md`](DASHBOARD_PLAN_CONSOLIDACION.md) | Dashboard integration handoff |
| [`CONFIG_CLEANUP_PROPOSAL.md`](CONFIG_CLEANUP_PROPOSAL.md) | Configuration cleanup proposal on hold |
| [`DASHBOARD_ANALISIS_ANGULAR.md`](DASHBOARD_ANALISIS_ANGULAR.md) | Angular feature baseline for the React migration |
| [`DASHBOARD_CONTEXTO_TECNICO.md`](DASHBOARD_CONTEXTO_TECNICO.md) | Technical baseline by module revision |
| [`DASHBOARD_FALENCIAS_VALIDACION.md`](DASHBOARD_FALENCIAS_VALIDACION.md) | Findings from the earlier validation interface |
| [`ANALISIS_TASKMANAGER_ENCOLAMIENTO_CORE_LIB.md`](ANALISIS_TASKMANAGER_ENCOLAMIENTO_CORE_LIB.md) | TaskManager queue analysis |
| [`DARK_MINTER_AUTHENTICATION_PLAN.md`](DARK_MINTER_AUTHENTICATION_PLAN.md) | dARK authentication design and implementation record |
| [`FUTURE_VALIDATOR_TRANSFORMER_PARALLELIZATION.md`](FUTURE_VALIDATOR_TRANSFORMER_PARALLELIZATION.md) | Proposal for parallel validation |
| [`ANALISIS_MERGE_ENTIDADES.md`](ANALISIS_MERGE_ENTIDADES.md) | Merge design record; function is now `merge_dirty_entities_and_relations()` (implemented) |
| [`ANALISIS_SYNCHRONIZED.md`](ANALISIS_SYNCHRONIZED.md) | §2/§3 resolved in code; inventory kept as reference |
| [`ARQUITECTURA_TRANSACCIONAL.md`](ARQUITECTURA_TRANSACCIONAL.md) | Transaction architecture; "recommended configuration" is not applied anywhere |
| [`REFACTORING_TRANSACCIONAL.md`](REFACTORING_TRANSACCIONAL.md) | Implemented; read-only transactions close with `rollback()` |
| [`DYNAMIC_SCHEMA_REFACTORING.md`](DYNAMIC_SCHEMA_REFACTORING.md) | Historical implementation record; its frontend path references predate React-only static |
| [`WORKERS_TASKS_ACTIONS_ANALYSIS.md`](WORKERS_TASKS_ACTIONS_ANALYSIS.md) | Incremental processing already implemented |
| [`IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md`](IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md) | Migrations consolidated in `V5.0.0.8` |
| [`AUTENTICACION_FILE_BASED.md`](AUTENTICACION_FILE_BASED.md) | Historical file-based auth mechanism (removed; superseded by `AUTHENTICATION.md`) |
| [`PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md`](PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md) | Historical documentation plan snapshot — its authentication and legacy-UI findings were superseded on 2026-09-29 |

## Verification records

| Document | Scope |
|---|---|
| [`ADMIN_UI_OPERACIONES.md`](ADMIN_UI_OPERACIONES.md) | Harvesting, cancellation and batch actions |
| [`ADMIN_UI_VERIFICACION.md`](ADMIN_UI_VERIFICACION.md) | Browser checks of navigation, reports and historical metadata |
| [`ADMIN_UI_INDEXACION.md`](ADMIN_UI_INDEXACION.md) | Solr indexing of a historical snapshot |
| [`DASHBOARD_ETAPA_2_EVIDENCIAS.md`](DASHBOARD_ETAPA_2_EVIDENCIAS.md) | Historical and filtered validation reports |
| [`METADATA_CLEANUP_REVIEW_2026-11-18.md`](METADATA_CLEANUP_REVIEW_2026-11-18.md) | RC4 investigation of orphaned metadata cleanup |

## Archived

Moved to [`archive/`](archive/README.md) on 2026-09-23 (7 documents, each with a banner):
pipeline multithread removed, pre-incremental catalog analyses, readonly-transaction proposal,
Admin Web v5 technical plan (executed), package migration guide (merged) and the unmaintained `changelog.md`.

## Component READMEs

| README | Highlight |
|---|---|
| [`lareferencia-core-lib`](../lareferencia-core-lib/README.md) | Package table including export, incremental behavior, config/workflow links |
| [`lareferencia-core-lib/src/test`](../lareferencia-core-lib/src/test/README.md) | Test suite report (snapshot disclaimer; no AssertJ/JaCoCo) |
| [`lareferencia-lrharvester-app`](../lareferencia-lrharvester-app/README.md) | Admin at `/admin/`, Dashboard at `/dashboard/`, API v5 and local identity |
| [`lareferencia-lrharvester-admin-web`](../lareferencia-lrharvester-admin-web/README.md) | React SPA build/development, session and CSRF behavior |
| [`lareferencia-entity-lib`](../lareferencia-entity-lib/README.md) | `deleted` flag, dirty-entity merge, indexer model links |
| [`lareferencia-entity-rest`](../lareferencia-entity-rest/README.md) | Transition state: only `GET /search/entity/{type}` active |
| [`lareferencia-repository-dashboard`](../lareferencia-repository-dashboard/README.md) | React Dashboard build, local session and read-only API v5 |
| [`lareferencia-metadata-tools`](../lareferencia-metadata-tools/README.md) | Python 3.12+ installation, rights and enrichment commands, embedding preparation and inference |
| [`lareferencia-shell`](../lareferencia-shell/README.md) | Command reference and initial local administrator bootstrap |
| [`lareferencia-indexing-filters-lib`](../lareferencia-indexing-filters-lib/README.md) | FieldOccurrenceFilter strategies |
| [`lareferencia-oai-pmh`](../lareferencia-oai-pmh/README.md) | Parent inheritance, independent provider builds, runtime and Docker context |
| [`lareferencia-dark-lib`](../lareferencia-dark-lib/README.md) | dARK client and inherited platform version |
| [`lareferencia-oclc-harvester`](../lareferencia-oclc-harvester/README.md) | OAI harvesting library and inherited platform version |
| [`lareferencia-shell-entity-plugin`](../lareferencia-shell-entity-plugin/README.md) | Entity commands contributed to Shell profiles |
| [`lareferencia-solr-cores`](../lareferencia-solr-cores/README.md) | Historical configsets; current runtime sources are documented in Docker/README.md |

The OAI README documents parent inheritance, standalone builds and the named Docker
context. Other active module footers defer to the parent version. Legacy contrib
READMEs retain their independent version context.

## Subproject and infrastructure docs

| Document | Note |
|---|---|
| [`lareferencia-oai-pmh/docs/architecture/0001-platform-alignment.md`](../lareferencia-oai-pmh/docs/architecture/0001-platform-alignment.md) | + addendum 2026-09-23: provider integrated in reactor/compose/workspace |
| [`lareferencia-oai-pmh/docs/testing/oai-compatibility-contract.md`](../lareferencia-oai-pmh/docs/testing/oai-compatibility-contract.md) | Tests use the provider's own Solr 9.8 core copy; layer 5 pending |
| [`testing/oai-incremental/README.md`](../testing/oai-incremental/README.md) | Ports corrected (8096/8196), `--core` unused, manifest scope behavior |
| [CloudFormation infrastructure repository](https://github.com/LA-Referencia-IOI/larefererencia-infra-cloudformation) | EC2 templates, machine configurations, and deployment/monitoring scripts |

## How to keep this healthy

1. New documents start with `**Status:** current · **Last verified:** <date>`.
2. When a document becomes a historical record instead of a live reference, change its status line and add a note describing what changed.
3. Superseded documents move to `archive/` with a banner and a row in [`archive/README.md`](archive/README.md).
4. Re-verify after big merges; bump the `Last verified` date instead of silently editing.
