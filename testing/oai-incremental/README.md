# OAI-PMH incremental fixture harness

This directory provides a deterministic five-record repository for testing the platform's full and incremental harvesting, validation, and indexing paths. It targets the existing `lareferencia-oai-pmh` provider indirectly through its Solr `oai` core; no provider source changes are required.

## Prerequisites

Start Solr and the provider with the Docker development environment. The normal host defaults are Solr `8983` and provider `8092`. An isolated `docker-dev` instance commonly offsets these ports (for example Solr `9083` and provider `8192`). Check `Docker/.env.dev` for the active values.

The loader uses only Python 3 standard-library modules and Solr HTTP JSON APIs.

## Commands

The canonical executable is `bin/oai-fixtures`; shell wrappers are provided in `scripts/`.

```bash
testing/oai-incremental/bin/oai-fixtures reset
testing/oai-incremental/bin/oai-fixtures baseline
testing/oai-incremental/bin/oai-fixtures status
testing/oai-incremental/bin/oai-fixtures verify-oai
testing/oai-incremental/bin/oai-fixtures scenario metadata-update
```

Common options are `--solr-url`, `--provider-url`, `--core`, `--output human|json`, and `--verbose`. The default Solr URL is `http://localhost:${LR_PORT_SOLR:-8983}/solr/oai`; the default provider URL is `http://localhost:${LR_PORT_OAI:-8092}/request`.

Example for an isolated development instance:

```bash
testing/oai-incremental/bin/oai-fixtures baseline \
  --solr-url http://localhost:9083/solr/oai \
  --provider-url http://localhost:8192/request
```

## Solr contract

The provider core uses `item.handle` as its unique key. Fixtures set `item.id` (integer), `item.public`, `item.deleted`, and `item.lastmodified`. OAI-DC values are stored below dynamic `metadata.*` fields. Deleted records retain their handle and are represented by `item.deleted=true`.

`reset` deletes only handles matching `fixture-*`. `baseline` loads exactly five active records and commits. Both operations are safe to repeat.

## Scenarios

Run `scenario <name>` after `baseline`. Provider mutations are intentionally separate from platform actions: after applying a scenario, run the normal harvesting, validation, and indexing actions to observe catalog `N/U/D/NULL`, validation reuse, and Solr UPSERT/DELETE behavior.

Supported scenarios:

| Scenario | Provider mutation | Expected platform result |
|---|---|---|
| `no-change` | No mutation | Empty delta; inherited rows remain `NULL`. |
| `metadata-update` | Change title and datestamp of fixture-002 | `U`, revalidate and UPSERT one. |
| `new-record` | Add active fixture-006 | `N`, validate and UPSERT one. |
| `delete-active` | Mark fixture-003 deleted | `D`, create tombstone and DELETE one. |
| `delete-new` | Add unknown deleted fixture-007 | New `D` tombstone and DELETE one. |
| `restore` | Reactivate fixture-003 with metadata | `U`, revalidate and UPSERT one. |
| `same-metadata-new-datestamp` | Change only fixture-004 datestamp | OAI-visible change but catalog `NULL`; no downstream delta. |
| `invalid-result` | Set fixture-005 title to `INVALID_TEST_RECORD` | `U`; validation failure and DELETE one. |
| `validator-change` | No provider mutation | Change validator configuration; validation/indexing must be full. |
| `full-rebuild` | No provider mutation | Explicit full actions rebuild the target scope. |
| `legacy-manifest` | No provider mutation | Remove/alter manifest; safety fallback is full. |
| `retry` | No provider mutation | Repeat the same incremental action; operations remain idempotent. |

The `expected/` JSON files are stable acceptance expectations for the scenario matrix. The harness reports actual Solr/OAI state in JSON with `--output json`; catalog and validation assertions are made by the platform integration tests and should be compared with the corresponding expected file.

## OAI verification

`verify-oai` calls `Identify`, `ListMetadataFormats`, `ListIdentifiers` and `ListRecords` for `oai_dc`, then calls `GetRecord` for each baseline handle. It checks OAI-PMH response roots and errors. Date-window and resumption-token checks should be run when the provider is configured with a reduced page size; these requests are deliberately left to the provider integration suite because page size is a provider configuration concern.

## CI usage

CI can start the provider and Solr, call `reset` and `baseline` against the service URL, run `verify-oai`, then execute each scenario in an isolated job or reset between scenarios. Keep the Solr URL explicit in CI; do not rely on host-port defaults. The loader returns non-zero for unavailable Solr, missing cores, malformed fixtures, or failed OAI checks.

## Complete end-to-end runbook

The following sequence is the reference procedure for a developer testing the platform implementation. Replace `HARVESTER_URL`, `NETWORK_ID`, and the port values with the local environment values.

### 1. Start the platform

For a normal Docker instance:

```bash
./Docker/docker.sh up
```

For an isolated development instance, use the `docker-dev` wizard, enable `core`, `solr`, `harvester`, and `oai`, then start the selected modules:

```bash
./Docker/docker-dev.sh wizard
```

The normal host ports are Solr `8983`, harvester `8090`, and OAI provider `8092`. The development wizard adds `SERVICES_PORT_OFFSET`; read `Docker/.env.dev` and use the resulting `LR_PORT_*` values.

Check service health before loading data:

```bash
curl --fail "http://localhost:${LR_PORT_OAI:-8092}/actuator/health"
curl --fail "http://localhost:${LR_PORT_SOLR:-8983}/solr/admin/info/system?wt=json"
```

### 2. Reset and load the provider repository

Always start a scenario sequence from a clean provider core:

```bash
testing/oai-incremental/bin/oai-fixtures reset \
  --solr-url "http://localhost:${LR_PORT_SOLR:-8983}/solr/oai"

testing/oai-incremental/bin/oai-fixtures baseline \
  --solr-url "http://localhost:${LR_PORT_SOLR:-8983}/solr/oai"

testing/oai-incremental/bin/oai-fixtures status --output json
testing/oai-incremental/bin/oai-fixtures verify-oai \
  --provider-url "http://localhost:${LR_PORT_OAI:-8092}/request"
```

The status command must report five active records. `verify-oai` must pass before running a platform harvest; otherwise failures belong to the fixture/provider setup rather than incremental processing.

### 3. Run the baseline full harvest

Create or select a test network whose OAI base URL points to:

```text
http://host.docker.internal:${LR_PORT_OAI:-8092}/request
```

Use `host.docker.internal` when the harvester runs inside Docker and the provider is published on the host. If both containers share the Compose network, use the provider service name and port instead.

Run the configured full harvesting action. The legacy application exposes the operational endpoint:

```bash
curl -u USER:PASSWORD \
  "${HARVESTER_URL}/private/networkAction/HARVESTING_ACTION/false/${NETWORK_ID}"
```

The equivalent API v5 command is the network command endpoint documented by the harvester application. The request must select `HARVESTING_ACTION` with `incremental=false`.

Wait for the snapshot to finish, then inspect the network snapshot and logs through the dashboard/API. Confirm that the resulting catalog contains five active records and that the full validation/index actions complete.

### 4. Run the baseline validation and indexing actions

If the deployment does not chain actions automatically, execute the configured validation and index actions separately, both with `incremental=false`. The validation action is `VALIDATION_ACTION` and is defined by `validation.actions.xml` (or its English variant); it runs the prototype bean `validationWorker` and supports the `DETAILED_DIAGNOSE` action option. The exact index action names are visible in the enabled Spring action configuration (`index.frontend.actions*.xml`, `xoai.actions*.xml`, or another profile).

For the OAI provider index, select the XOAI/Provider indexing action. Its `solrRecordIDValue` must be `record_id`; the provider core itself still uses `item.handle` as its unique key.

After completion verify:

```bash
testing/oai-incremental/bin/oai-fixtures status --output json
curl --fail "${HARVESTER_URL}/api/v5/networks/${NETWORK_ID}/snapshots"
```

The baseline is the reference state for all subsequent scenarios.

### Validation checkpoint

After every harvest and before indexing, execute `VALIDATION_ACTION` and wait for the snapshot to reach validation-complete. Full validation reads every non-deleted catalog record, loads its original metadata from the filesystem store, applies the configured primary and secondary transformers, invokes the network validator, and writes `validation/validation.db`. If no validator is configured, the record is treated as valid. If a transformer changes metadata, the transformed representation is stored and its hash becomes `published_metadata_hash`.

For an incremental validation, the worker first compares the current validator fingerprint with the manifest belonging to `previousSnapshotId`. When the fingerprint and manifest are reusable, it copies the parent `validation.db`, clears inherited change markers, writes tombstones for catalog `D` rows, and validates only catalog `N` and `U` rows. Rows with `change_type=NULL` retain their parent result. If the parent database, manifest, or fingerprint cannot be verified, the worker uses the full path and writes scope `FULL`.

Using the legacy management endpoint, the validation calls are:

```bash
curl -u USER:PASSWORD \
  "${HARVESTER_URL}/private/networkAction/VALIDATION_ACTION/false/${NETWORK_ID}"

# For an incremental validation:
curl -u USER:PASSWORD \
  "${HARVESTER_URL}/private/networkAction/VALIDATION_ACTION/true/${NETWORK_ID}"
```

The API v5 command interface can issue the same action by setting `actionName` to `VALIDATION_ACTION` and `incremental` to `false` or `true` in the command request.

Inspect the validation artifact before indexing:

```bash
SNAPSHOT_DIR=/path/to/store/<network>/snapshots/snapshot_<id>
sqlite3 "$SNAPSHOT_DIR/validation/validation.db" \
  'select change_type, deleted, is_valid, count(*) from record_validation group by change_type, deleted, is_valid order by change_type;'
cat "$SNAPSHOT_DIR/validation/validation-manifest.json"
```

Expected incremental validation checks:

- `N` and `U` rows have a newly calculated validation result.
- `D` rows have `deleted=1`, `is_valid=0`, `is_transformed=0` and no metadata load is required.
- `NULL` rows retain the copied parent result.
- Active statistics use `deleted=0`, so tombstones are not counted as active or invalid-quality records.
- A legacy manifest without `scope` logs a warning and forces full validation.

If validation fails, do not run incremental indexing: inspect the worker log, database schema, manifest, and metadata hashes first. A full validation is the safe recovery operation.

### 5. Apply and execute one incremental scenario

For each scenario:

1. Reset and reload baseline, or continue from the documented predecessor.
2. Apply the provider mutation with `scenario <name>`.
3. Run `status` and `verify-oai`.
4. Run `HARVESTING_ACTION` with `incremental=true`.
5. Wait for harvesting completion.
6. Run validation with `incremental=true`.
7. Run the relevant OAI Provider index action with `incremental=true`.
8. Inspect snapshot catalog, validation manifest, validation counts, and Solr documents.
9. Compare the result with `expected/<scenario>.json`.

Example for a metadata update:

```bash
testing/oai-incremental/bin/oai-fixtures scenario metadata-update

curl -u USER:PASSWORD \
  "${HARVESTER_URL}/private/networkAction/HARVESTING_ACTION/true/${NETWORK_ID}"
```

Expected result: only `fixture-002` is classified `U`, revalidated, and upserted.

### 6. Scenario-specific checks

For `delete-active` and `delete-new`, verify the OAI response contains a deleted header before running validation. The incremental indexer must issue DELETE without trying to load published metadata.

For `same-metadata-new-datestamp`, verify the record appears in the OAI date window but remains `change_type=NULL`; no downstream validation or index operation should be generated.

For `invalid-result`, inspect validation `is_valid=0` and confirm incremental indexing removes the previous Solr document.

For `validator-change`, alter the validator configuration or fingerprint, run incremental actions, and confirm the manifest says `FULL` and the indexer rebuilds the complete scope.

For `legacy-manifest`, remove or replace the manifest with a fingerprint-only document and confirm the warning plus full fallback.

For `retry`, execute the validation and indexing actions twice. The second run must produce the same final Solr state and must not duplicate documents.

### 7. Inspecting low-level artifacts

For every snapshot, inspect:

- `catalog/catalog.db`: `oai_record.change_type`, `deleted`, and metadata hash.
- `validation/validation.db`: `record_validation.change_type`, `deleted`, `is_valid`, and dynamic `rule_*` columns.
- `validation/validation-manifest.json`: validator `hash` and `scope`.
- Solr `oai` core: `item.handle`, `item.id`, `item.deleted`, and `item.lastmodified`.

The platform indexer reads the delta from `validation.db`; it does not open the catalog. A full validation or missing/unsafe manifest must result in full indexing, never in a guessed incremental run.

### 8. Cleanup

After a test sequence, stop the platform normally. Use the fixture `reset` command before the next sequence. Do not use the Docker global data reset merely to switch OAI scenarios; that removes unrelated platform state.
