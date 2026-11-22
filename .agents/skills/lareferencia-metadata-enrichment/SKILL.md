---
name: lareferencia-metadata-enrichment
description: Explain and operate LA Referencia metadata enrichment pipelines and implement producers that feed the shared SQLite package. Use for per-item fields, incremental ingestion, publication, provenance and lookup.
---

# LA Referencia metadata enrichment

## Locate the maintained implementation

Use the current shell checkout. The known local checkout is `/Users/lmatas/source/lareferencia-platform/lareferencia-shell`. All commands below run from its root. Read `docs/METADATA_ENRICHMENT_PACKAGE.md` for the installed contract, and `tools/metadata-enrichment/README.md` for the component map.

The shell owns the pipeline, rights normalizer, SQLite writer, tests and documentation. The platform owns its coordinated lock and general metadata exchange contract. For coordinated code changes use `lareferencia-features`. For SSH operations on production use `lareferencia-harvester-ops`; resolve the actual deployed script path before invoking it.

## Explain or operate the pipeline

The rights workflow is original LGK XML → Java export → distinct eligible literals → v7 dictionary → fields per exported item → working SQLite → published edition. The normalizer interprets each eligible literal once. The producer rejoins that dictionary to each item. Source selection, filters, input hashes and denominators come from the actual export and manifest.

```sh
python3 tools/metadata-enrichment/run_rights_pipeline.py --network PY
python3 tools/metadata-enrichment/run_rights_pipeline.py --network PY --export-dir /srv/metadata-exports/exp-UUID
```

The pipeline selects one network per run and defaults to `/srv/metadata-enrichments/<network>/run-<uuid>/`. It resolves the JAR and licenses 1.1 profile from the shell checkout; `--shell-dir` targets another configured installation. Use the run's reported edition and export paths.

A successful edition contains `enrichments.sqlite` and `manifest.json`. The run also retains `dictionary-v7.jsonl`, the working database and logs. The manifest records snapshot, variant, producer, source references, code and input hashes. Use it to distinguish taxonomy v7, rights facet schema 4 and package format 1.

For rights, L1 is a deduplicated overview, L2 adds known instrument details, and Copyright has its own `dc.rights.copyright` field. Institutional terms share `INSTITUTIONAL` in L1 and identify the institution in L2. For inventory analysis and the two item denominators, use `lareferencia-license-export`.

## Implement another producer

Read [the producer integration guide](references/producers.md). Reuse the generic writer through Python or v2 JSONL ingestion. Keep domain decisions in the producer. Define target fields, occurrence semantics and a stable producer ID; the ID owns the complete set of fields contributed to an item. Preserve item identity and the actual input metadata hash.

The current rights producer demonstrates this interface. ODS is a possible new producer. The existing `tools/embedding-metadata/` workflow produces bibliographic packages and JSONL; integrating it with this SQLite writer requires an adapter.

## Query and verify results

```sh
python3 tools/metadata-enrichment/enrichments.py lookup /path/to/edition/enrichments.sqlite --catalog-id ITEM_ID
python3 tools/metadata-enrichment/enrichments.py lookup /path/to/edition/enrichments.sqlite --identifier OAI_IDENTIFIER
python3 -m unittest discover -s tools/metadata-enrichment -p 'test_*.py'
```

Lookup returns identity, input hash and results grouped by producer, with execution and source references. Use `(network, catalogId)` for catalog remapping. Ambiguous OAI identifiers fail. The source reference identifies the exported line; full model/configuration provenance is resolved through the execution in the manifest.

For a new producer, verify duplicate input, correction, empty result, interrupted batch, conflicting input hash, coexistence with another producer and lookup of a published edition. The writer compares complete occurrence content; producers that require unique facet values must deduplicate by normalized value before writing.

The current delivery ends at the queryable edition. Applying fields to XOAI through a Java transformer remains a subsequent integration.
