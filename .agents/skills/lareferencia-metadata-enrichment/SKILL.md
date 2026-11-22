---
name: lareferencia-metadata-enrichment
description: Explain and operate LA Referencia metadata enrichment pipelines and implement producers that feed the shared SQLite package. Use for per-item fields, incremental ingestion, publication, provenance and lookup.
---

# LA Referencia metadata enrichment

## Locate the maintained implementation

From the platform root, install the module pinned in `workspace.lock`
with `python -m pip install ./lareferencia-metadata-tools` in a Python 3.12+
virtual environment. Run its console commands from that environment. Read its
`docs/METADATA_ENRICHMENT_PACKAGE.md` for the installed contract.

The metadata tools module owns the pipeline, rights normalizer, SQLite writer, tests and documentation. The shell owns Java exports and extraction profiles. The platform owns its coordinated lock and general metadata exchange contract. For coordinated code changes use `lareferencia-features`. For SSH operations on production use `lareferencia-harvester-ops`; resolve the configured Java shell directory and the installed Python environment before launching a job.

## Explain or operate the pipeline

The rights workflow is original LGK XML → Java export → distinct eligible literals → v7 dictionary → fields per exported item → working SQLite → published edition. The normalizer interprets each eligible literal once. The producer rejoins that dictionary to each item. Source selection, filters, input hashes and denominators come from the actual export and manifest.

```sh
run-rights-pipeline --network PY --shell-dir "$SHELL_DIR"
run-rights-pipeline --network PY --export-dir /srv/metadata-exports/exp-UUID
```

The pipeline selects one network per run and defaults to `/srv/metadata-enrichments/<network>/run-<uuid>/`. It resolves the JAR and licenses 1.1 profile from the sibling shell checkout when available. Use `--shell-dir` or `LR_SHELL_DIR` to select a configured installation. Use the run's reported edition and export paths. For a detached job, invoke the command by its absolute path in the virtual environment.

A successful edition contains `enrichments.sqlite` and `manifest.json`. The run also retains `dictionary-v7.jsonl`, the working database and logs. The manifest records snapshot, variant, producer, source references, code and input hashes. Use it to distinguish taxonomy v7, rights facet schema 4 and package format 1.

For rights, L1 is a deduplicated overview, L2 adds known instrument details, and Copyright has its own `dc.rights.copyright` field. Institutional terms share `INSTITUTIONAL` in L1 and identify the institution in L2. For inventory analysis and the two item denominators, use `lareferencia-license-export`.

## Implement another producer

Read [the producer integration guide](references/producers.md). Reuse the generic writer through Python or v2 JSONL ingestion. Keep domain decisions in the producer. Define target fields, occurrence semantics and a stable producer ID; the ID owns the complete set of fields contributed to an item. Preserve item identity and the actual input metadata hash.

The current rights producer demonstrates this interface. ODS is a possible new producer. The bibliographic preparation workflow produces bibliographic packages and JSONL; integrating it with this SQLite writer requires an adapter.

## Query and verify results

```sh
enrichments lookup /path/to/edition/enrichments.sqlite --catalog-id ITEM_ID
enrichments lookup /path/to/edition/enrichments.sqlite --identifier OAI_IDENTIFIER
python -m unittest discover -s tests -p 'test_*.py'
```

Lookup returns identity, input hash and results grouped by producer, with execution and source references. Use `(network, catalogId)` for catalog remapping. Ambiguous OAI identifiers fail. The source reference identifies the exported line; full model/configuration provenance is resolved through the execution in the manifest.

For a new producer, verify duplicate input, correction, empty result, interrupted batch, conflicting input hash, coexistence with another producer and lookup of a published edition. The writer compares complete occurrence content; producers that require unique facet values must deduplicate by normalized value before writing.

To apply a published original-variant edition to XOAI, install its SQLite file in the network data directory under `enrichments/` and configure the `ImportEnrichments` rule in the validation profile. See the platform guide `docs/VALIDACION_COMPATIBILIDAD.md#enriquecimientos-sqlite` for field mappings and incremental validation.
