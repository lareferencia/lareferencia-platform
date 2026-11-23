# Implement a producer for the SQLite package

Read the metadata tools guide `docs/METADATA_ENRICHMENT_PACKAGE.md` alongside `enrichment_package/store.py`, `lareferencia_metadata_tools/enrichments.py` and `enrichment_package/schema.sql` under the module’s `src/`. These files define the installed behavior.

## Define the producer contract

Choose a stable producer ID, a schema version and target fields. An item result is a mapping of target paths to ordered occurrence arrays. Each occurrence has a textual `value` and optional JSON attributes. Keep attributes describing one occurrence together. A field such as `dc.subject.ods` can contain multiple occurrences.

One working database is scoped to a network, snapshot and input variant. Each item supplies its stored catalog ID, exact OAI identifier and input metadata hash. Obtain these from the export; retain any unknown or unresolved outcome as an evaluated result when appropriate.

## Python integration

Install the metadata tools package in the producer's environment and import `upsert_batch` from `enrichment_package`.

```python
from pathlib import Path

from enrichment_package import upsert_batch

run = {
    "network": "PY",
    "snapshot": "4195",
    "variant": "original",
    "exportId": "exp-example",
    "producer": "ods",
    "runId": "ods-example-001",
    "type": "classification",
    "schemaVersion": "1",
    "model": "example-model",
}

# Replace the example identity and hash with values from the actual export.
item = {
    "catalogId": "item-001",
    "identifier": "oai:example:1",
    "metadataHash": "ABC123",
    "generatedAt": "2026-11-22T12:00:00Z",
    "sourceRef": "PY/part-000001.jsonl.gz:1",
    "fields": {
        "dc.subject.ods": [
            {"value": "ODS-03"},
            {"value": "ODS-10"},
        ]
    },
}
upsert_batch(Path("work.sqlite"), run, [item])
```

Input items may be streamed. Every call is atomic; the iterator must reach its end for the batch to commit. For large producers, select practical batches and publish after the intended set has completed.

## JSONL integration

Use the existing v2 return envelope. The run descriptor above can be saved as `run.json`. A matching line is:

```json
{"exportId":"exp-example","network":"PY","catalogId":"item-001","identifier":"oai:example:1","metadataHash":"ABC123","enrichment":{"id":"ods","type":"classification","schemaVersion":"1","runId":"ods-example-001","generatedAt":"2026-11-22T12:00:00Z","values":{"fields":{"dc.subject.ods":[{"value":"ODS-03"},{"value":"ODS-10"}]}}}}
```

```sh
enrichments ingest work.sqlite ods.jsonl --run run.json
enrichments publish work.sqlite edition-001
enrichments lookup edition-001/enrichments.sqlite --catalog-id item-001
```

The ingestion command checks the network, export ID, producer ID, run ID, type and schema version against the descriptor. Use timestamps with a timezone. JSONL.GZ is supported. Record input files and hashes in the descriptor so the basename-and-line source references remain resolvable.

## Updates and ownership

A producer replaces its entire result for an item in one update. Send every field that producer wants to retain. An empty `fields` object records a completed empty evaluation and clears its previous fields. An omitted item retains its prior result. Other producers retain their contributions.

Run metadata is immutable for a `(producer, runId)` pair. Allocate a new run ID when model, configuration or provenance changes. A hash or identity mismatch rolls back the batch; generate results for the matching source cut. The latest committed result is current; run descriptors preserve provenance, while the working store retains current item results.

Generic deduplication compares target plus canonical full JSON occurrence, preserving the first order. Two occurrences with the same `value` and different attributes can therefore coexist. Facet producers must apply their own semantic deduplication, merging supporting details where needed, as the rights producer does.

## Publication and consumption

Publish to a new directory using the shared writer. Consumers open the delivered SQLite read-only and verify its manifest checksum, item identity, variant and input hash. A published edition remains fixed while the working database receives further results.

For item statistics, count distinct items for each target and value. Deduplicate unions across fields or producers explicitly. Distinguish an item with no producer result from a completed empty evaluation.
