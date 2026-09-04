# Incremental Processing Developer Manual

## Purpose and implemented scope

This manual replaces the original issue proposal. It documents the behavior implemented in the current source tree for full and incremental harvesting, validation, and Solr indexing. Each snapshot remains isolated and owns its catalog.db, validation.db, metadata files, and validation manifest.

The catalog delta is immutable snapshot evidence, not a consumable work queue. Multiple indexers and retries can therefore read the same delta independently without changing it.

Pipeline:

    Harvesting
      catalog.db: change_type N / U / D / NULL
            |
            v
    Validation
      validation.db: result + change_type
      validation-manifest.json: validator fingerprint + scope
            |
            +--> IndexerWorker
            +--> SemanticIndexerWorker
                  FULL: delete network and rebuild
                  INCREMENTAL: process change_type IS NOT NULL

The parent is the snapshot recorded as previousSnapshotId, not the most recently indexed snapshot.

## Component map

| Component | Implemented responsibility |
|---|---|
| HarvestingWorker | Full/incremental OAI-PMH window, parent selection and snapshot lifecycle. |
| CatalogDatabaseManager | Catalog copy, schema migration and change_type reset. |
| OAIRecordCatalogRepository | N/U/D/NULL classification, upserts, tombstones and delta queries. |
| IOAIRecord / ValidationRecord | Backward-compatible transport of change_type. |
| ValidationDatabaseManager | Validation schema migration, parent copy and inherited-marker reset. |
| RecordValidationRepository | Validation UPSERT and tombstone creation. |
| ValidationRecordPaginator | Full pagination or change-only pagination. |
| ValidationWorker | Parent reuse, changed-record validation and manifest scope. |
| ValidatorFingerprint / ValidationManifestStore | Validator fingerprint and FULL/INCREMENTAL manifest. |
| IRecordFingerprintHelper / PrefixedRecordFingerprintHelper | Solr identity resolution and stable numeric ID. |
| IndexerWorker | Full/delta selection and incremental UPSERT/DELETE. |
| SemanticIndexerWorker | Same contract plus embedding enrichment for valid UPSERTs. |
| Spring XML worker definitions | Explicit solrRecordIDValue per transformation. |

## 1. Harvesting

### On-disk layout

For a network and snapshot, PathUtils derives a snapshot directory below store.basepath. The relevant files are catalog/catalog.db, validation/validation.db, validation/validation-manifest.json, and metadata-store files addressed by their metadata hash. This flow uses SQLite and filesystem storage; it does not use a Parquet backend.

HarvestingWorker creates the snapshot and records metadata through ISnapshotStore. It starts in full mode by default. The action option FORCE_FULL_HARVESTING overrides an incremental request.

For an incremental action it calls findLastGoodKnownSnapshot. If no parent exists, it logs the reason and falls back to full. With a parent it reads the parent start datestamp, rounds it to the configured OAI-PMH granularity, and passes the resulting from value to IHarvester. The new snapshot stores previousSnapshotId, lastIncrementalDatestamp, and inherited size.

Full harvesting initializes an empty SQLite catalog and requests the complete source. Incremental harvesting copies the parent catalog, clears inherited change_type values, and applies only records and deleted headers returned by the OAI-PMH window. An empty incremental harvest is still successful: the copied catalog remains the complete snapshot and all rows have change_type=NULL.

For every event the worker stores XML in IMetadataStore, upserts OAIRecord through OAIRecordCatalogRepository, and updates the snapshot count. It always closes the catalog and marks the snapshot finished or failed. stop() signals both harvester and worker; cleanup is performed by the main run lifecycle.

### Action orchestration

The action layer passes the incremental boolean to workers. LegacyNetworkActionExecutor resolves the configured worker bean, applies effective action configuration, calls setIncremental, assigns NetworkRunningContext, and submits it to the task manager. FlowableNetworkActionExecutor passes the same value as a BPMN process variable; BaseWorkerDelegate applies it before invoking the worker. The worker logic is therefore independent of the orchestration engine, while legacy remains the default deployment choice.

## 2. Catalog delta

The oai_record table has nullable change_type with a check constraint allowing only N, U, D, or NULL. Index idx_change_type supports changed-only queries.

| Value | Meaning |
|---|---|
| N | New record in this catalog. |
| U | Active record whose metadata changed, or deleted record restored to active. |
| D | OAI-PMH deletion/tombstone. |
| NULL | Inherited or repeated with the same metadata hash. |

No validation status, index status, retry state, or destination-specific state is stored in the catalog.

CatalogDatabaseManager copies the parent database before harvesting. It checks PRAGMA table_info(oai_record), adds the column when absent, creates the index if needed, and clears inherited markers in the new copy. The parent is never modified and migration is idempotent. Legacy catalogs generate a warning; only the new copy is migrated.

OAIRecordCatalogRepository compares original_metadata_hash and deleted during each upsert:

| Incoming event | Previous row | Stored result |
|---|---|---|
| Metadata | Identifier absent | Active row with N. |
| Metadata | Active, hash differs | Update with U. |
| Metadata | Active, same hash | Update datestamp; keep NULL. |
| Metadata | Previously deleted | Restore deleted=0; set U. |
| Deleted header | Active | Set deleted=1; set D. |
| Deleted header | Already deleted in parent | Keep NULL. |
| Deleted header | Identifier absent | Insert tombstone with D. |

If a row was marked N or U earlier in the same harvest and is repeated with identical metadata, its existing mark is retained. The implementation uses identifier-based upsert rather than INSERT OR REPLACE so that the previous row can be compared.

## 3. Validation database

record_validation contains nullable change_type with the same N/U/D constraint and index idx_rv_change_type. ValidationRecord carries the field. IOAIRecord.getChangeType() is a default method returning NULL, preserving behavior for non-catalog implementations.

The fixed columns are identifier_hash (primary key), identifier, datestamp, is_valid, is_transformed, published_metadata_hash, deleted, and change_type. Rule results are represented by dynamic rule_<ruleId> BOOLEAN columns; detailed rule occurrences remain in the separate occurrence table when the validator requests them.

ValidationWorker attempts to copy the parent validation.db. ValidationDatabaseManager migrates an old copy when needed and clears inherited markers; the parent remains immutable.

When reuse is not possible, the worker opens the snapshot catalog and streams every non-deleted OAIRecord. It loads original metadata from the filesystem store, runs the configured transformer and validator, and persists the complete result set. This is the full-validation path and is independent of catalog change markers.

- N and U are revalidated and written through an UPSERT; their marker is preserved.
- D creates or updates a tombstone with deleted=1, is_valid=0, is_transformed=0, and change_type=D. markDeletedRecord creates the row when no parent validation row exists.
- NULL retains the inherited validation result and is not revalidated.

RecordValidationRepository upserts by identifier_hash, updates dynamic rule_* columns, binds change_type from the source record, and inserts a minimal tombstone when required.

ValidationRecordPaginator has changedOnly mode. Count and page SQL use WHERE change_type IS NOT NULL in that mode; full mode reads every validation row. Indexers enable this mode only after the manifest confirms incremental scope.

Validation counters query active rows with deleted=0. Tombstones remain invalid for indexing, but are excluded from active, valid, transformed, and per-rule totals. Revalidated active observations use deleted=false and retain their source change_type.

## 4. Validator manifest and fingerprint

ValidatorFingerprint preserves the existing validator fingerprint and adds optional root-level scope. A current manifest has formatVersion, algorithm SHA-256, canonicalizer validator-v1, hash, and scope. Scope is FULL or INCREMENTAL.

ValidationWorker writes the manifest after deciding whether the parent database is reusable. INCREMENTAL is written only when a parent exists, its manifest is readable, fingerprints match, and the validation copy succeeds. A requested full run, changed fingerprint, missing parent or manifest, copy failure, or unverifiable condition produces FULL.

Historical manifests containing only the fingerprint still deserialize because scope is optional, but missing scope is unsafe and forces full validation. A warning tells operators to regenerate validation with an explicit scope.

## 5. Solr identity contract and configuration

solrRecordIDField remains the Solr field used in DELETE queries. solrRecordIDValue was added to both indexer workers because the value depends on the XSLT and core; it is never inferred from the field name.

| solrRecordIDValue | Resolved value |
|---|---|
| fingerprint | Existing textual fingerprint, networkAcronym_md5. |
| record_id | Positive Long derived from that fingerprint. |
| identifier | OAI identifier. |

IRecordFingerprintHelper.getRecordIdValue is the common resolver. Current XML configurations use fingerprint for frontend/VuFind, thesis, and semantic transformations; record_id for Provider/Xoai; and identifier for RCAAP.

Example worker properties:

    <property name="solrRecordIDField" value="id"/>
    <property name="solrRecordIDValue" value="fingerprint"/>

An old incremental bean without solrRecordIDValue logs a warning and falls back to full indexing. Changing an XSLT or identity field requires reviewing both properties and performing a full rebuild.

## 6. Stable numeric record_id

The XSLT record_id parameter is no longer generated from snapshotId plus a counter. PrefixedRecordFingerprintHelper computes the existing textual fingerprint, applies XXHash64, and normalizes it with:

    long positive = hash & Long.MAX_VALUE;

The result is deterministic for the same identifier and network, invariant under metadata-only changes, sensitive to identifier/network changes, and always in [0, Long.MAX_VALUE]. The textual fingerprint and catalog OAIRecord.id MD5 are unchanged. No collision table or explicit collision handling was added.

Existing Solr documents made with the old ID do not match the new identity. The first post-deployment indexing must therefore be full.

## 7. IndexerWorker

After opening the snapshot, IndexerWorker sets useIncrementalDelta only when the action is incremental, the manifest says scope=INCREMENTAL, and solrRecordIDValue is non-blank. Otherwise it logs the fallback and uses full mode.

Full mode deletes the entire network and paginates every validation row. Incremental mode does not delete the network and paginates only change_type IS NOT NULL:

1. deleted=1: DELETE.
2. Active but invalid: DELETE, removing a document no longer publishable.
3. Active and valid: UPSERT the transformed XML.

Deletion is attempted before loading published metadata because a tombstone may have no metadata file. The query combines solrRecordIDField with the resolved identity and escapes it with ClientUtils.escapeQueryChars. The legacy deletion-only action (executeDeletion=true, executeIndexing=false) remains available.

Batch submission, commit, and error handling remain in the existing Solr client path. Retrying repeats the same idempotent operations; no validation state is consumed or mutated.

## 8. SemanticIndexerWorker

SemanticIndexerWorker implements the same manifest check, full/delta selection, identity resolution, deletion ordering, and paginator mode. Embedding enrichment is retained only for valid UPSERTs. Tombstones and invalid records are deleted without metadata transformation.

An unterminated Javadoc block was corrected during the refactor; it had caused subsequent methods to be parsed as comments and produced the observed compilation cascade.

## 9. Compatibility, limits, and operational rules

- Legacy catalog and validation databases remain readable; new columns are added only to new copies.
- Missing or legacy manifest scope is unsafe and forces full validation/indexing.
- Full validation scope automatically implies a full index.
- There is no index_pending, per-destination table, or consumable progress flag.
- Indexers never open catalog.db; they consume the classification copied into validation.db.
- Elastic, entity, and other specialized indexers are outside this refactor.
- The record_id parameter name and existing XSLTs are unchanged.
- Prevalidation is not optimized. If the prevalidator changes between harvests, full processing remains the safe operation.

## 10. Verification

The core module was compiled with:

    mvn -pl lareferencia-core-lib -DskipTests compile -q

Stable fingerprint/ID tests were run with:

    mvn -pl lareferencia-core-lib -Dtest=PrefixedRecordFingerprintHelperTest test -q

Those tests cover determinism across snapshots, metadata invariance, identifier/network sensitivity, positive range, and preservation of the textual fingerprint. Before production rollout, retain or add coverage for legacy database migration, N/U/D/NULL propagation, parentless tombstones, readable/legacy/unreadable manifests, full versus changed-only pagination, DELETE/UPSERT behavior in both workers, all three identity sources, and repeated execution by multiple indexers without mutating validation.db.
