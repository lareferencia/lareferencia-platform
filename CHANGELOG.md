# Changelog

## Unreleased

The following changes are on the `codex/rc5-pre` development branch.

### Funcionalidades

- El harvester puede agregar al XML XOAI campos seleccionados de una edición SQLite por red. [Configuración](docs/VALIDACION_COMPATIBILIDAD.md#enriquecimientos-sqlite)

### Upgrading from 5.0.0-rc4

- **Plan for one full validation per network.** The first validation after the upgrade processes the network's entire active catalog. Historical reports remain available. Networks with rules that depend on the current year also revalidate their catalogs after the year changes. [Upgrade details](docs/VALIDACION_COMPATIBILIDAD.md#efectos-al-actualizar)
- **Existing validation and transformation profiles load without migration.** The engine, shell and v5 API recognize historical rule names, including validators embedded in transformers. An optional shell migration updates class references while preserving dictionary entries, expressions and descriptions. [Profile compatibility](docs/VALIDACION_COMPATIBILIDAD.md)
- **Check rules that depend on how many field values match.** Field expressions now apply the quantifier saved in the profile. For example, with `ALL`, a content rule accepts an absent field, while an XPath rule requires at least one selected occurrence. The bundled Nodo Central profile now requires at least one nonempty title. Administrators can add the **Title — Presence** rule to an installed profile alongside its existing title-length check. [Quantifier behavior and title rule setup](docs/VALIDACION_COMPATIBILIDAD.md)
- **Downgrading after adopting new rule options requires a profile change.** Before switching back to the previous engine, restore any profile that uses `ReduceRecordsBySizeRule` to its earlier configuration and remove the new `processAllOccurrences` property wherever it was saved. Run validation again after switching engines. [Rollback instructions](docs/VALIDACION_COMPATIBILIDAD.md#opciones-de-transformación-y-reversión)

### Repository dashboard

- Maven and the platform and Docker build scripts now build the React dashboard by default and serve it at `/dashboard/`. The optional `dashboard-react` Maven profile also produces a standalone ZIP. The Angular source remains in `angular/`. The platform lock pins the dashboard revision alongside the harvester modules.
- Users can search the repositories they have access to by name or acronym. Administrators can enable harvest history, validation reports and usage statistics across the English, Spanish and Portuguese interfaces, and assign a statistics provider ID to each repository. The usage widget follows the dashboard's typography. [Dashboard configuration](https://github.com/lareferencia/lareferencia-repository-dashboard/blob/6c385975ed41b008ec59190ead9d4bfc19c6558a/docs/CONFIGURATION.md)
- Harvest history opens with a trend chart. The paginated history and its CSV list the newest harvests first. Users can compare two harvests by date and time, share the comparison by link and open either harvest's diagnostics. A saved pair can be recovered when the original results page is unavailable. A link with three harvests prompts the user to select two.
- Validation reports identify valid and invalid records. Filters apply to the summary, rule pass rates and counts of individual field values across all pages. Users can inspect values by rule and export visible rules, the current records page or rule frequencies as CSV. [Report API](docs/HARVESTER_MANAGEMENT_API_V5.md)
- Historical reports retain their rules and record counts when a validator is edited or replaced. New reports record whether each rule captured field values. For older reports, the dashboard checks for stored values before offering **View occurrences**. **No count** identifies an unavailable occurrence count, and passed and failed record totals remain available. [Historical report behavior](docs/HARVESTER_MANAGEMENT_API_V5.md)

### Validation and transformation

- Field translation and conditional addition now write all applicable changes to the published XML. A value in another field no longer blocks a translation into its destination. Cleanup also removes empty XML field elements. A regular-expression replacement counts an identifier as transformed only when its value changes. [Rule behavior](docs/VALIDACION_COMPATIBILIDAD.md#efectos-al-actualizar)
- Administrators can configure `FieldAddRule` to skip a fixed value already present in the field. Existing profiles continue adding it on each pass. Field-renaming rules can process every occurrence with `processAllOccurrences`. The default limit is 101. The new `ReduceRecordsBySizeRule` removes selected fields only when the XML exceeds a configured size in UTF-8 bytes. Existing `ReduceHeavyRecords` rules keep their original behavior. [Rule options](docs/VALIDACION_COMPATIBILIDAD.md)
- The engine reuses large vocabulary lookups within a validation run and reduces repeated XML searches and writes during normalization, cleanup, renaming, translation and the addition of repository and provenance fields. Existing profiles retain their configured term matching, value order and translation priorities. In benchmarks, removing duplicate values was faster, while removing only invalid values was slower. [Compatibility tests and measurements](docs/VALIDACION_COMPATIBILIDAD.md)
- URL validation has configurable connection and read timeouts. The defaults are 5 seconds to connect and 10 seconds to read. [Timeout settings](docs/VALIDACION_COMPATIBILIDAD.md#efectos-al-actualizar)

### Harvester administration and API

- Batch actions return a result for every source, including the reason a source could not run the action. The cancellation confirmation has an accessible name.
- Reloading an admin link with a valid session preserves the destination. Administrators can browse snapshot history, retry loading a report table and view the published XML for a record in its original network. Identifier searches run when the user selects Search or presses Enter.
- The v5 diagnostics API supports both exact OAI identifier matching and substring searches. Historical XML access is scoped to the network that owns the snapshot. The API returns HTTP 403 when a user's role does not permit an administrative operation. The read-only listing fetches only the data it displays. [API behavior and permissions](docs/HARVESTER_MANAGEMENT_API_V5.md)
- Orphaned metadata cleanup records the hashes it scanned, identified as deletion candidates and deleted in the history of the protected snapshots.
- A Solr timeout in the harvester test environment was fixed. An indexing check from the admin interface matched all 3,444 active, valid identifiers in a historical snapshot to the documents in Solr. [Indexing verification](docs/ADMIN_UI_INDEXACION.md)

### OAI-PMH provider

- The protocol and repository integration tests now start reliably when reverse DNS is slow in Docker. The tests still wait for the OAI Solr core to answer a query before indexing sample records.

### Metadata exports and processing tools

- The batch embedding calculator accepts `--format sqlite` to publish a vector database directly. GZIP JSONL remains the default.

- The shell ships the Java LGK export commands and JSON profiles. Install the coordinated metadata tools package with Python 3.12 or later to run the processing workflows.

- Metadata tools now follow the coordinated platform branch and release version. The Python package uses the equivalent PEP 440 version.

- The Python workflows for rights, metadata enrichment and batch embeddings now ship in the `lareferencia-metadata-tools` workspace module. Batch Gemma supports 768, 512 and 256 dimensions with float32 L2 normalization.

- Metadata tools convert calculated embeddings to compact SQLite editions and retrieve vectors by network and catalog ID. [Package guide](lareferencia-metadata-tools/docs/METADATA_ENRICHMENT_PACKAGE.md#pack-calculated-embeddings-in-sqlite)

- Rights normalization recognizes Spanish `Derechos de autor` notices as `NOTICE` in the copyright facet.

- Run the complete rights pipeline on the harvester server with a single Python command, from LGK or a verified export to a published enrichment edition. [Server workflow](lareferencia-metadata-tools/docs/METADATA_ENRICHMENT_PACKAGE.md)

- Build incremental SQLite enrichment packages and look up fields by catalog or OAI identifier. The rights v7 producer generates two license facets and a separate copyright notice facet. [Package guide](lareferencia-metadata-tools/docs/METADATA_ENRICHMENT_PACKAGE.md)

- SQLite snapshot exports now tolerate an empty write-ahead log (WAL), including one SQLite removes during the check. This fixes a false “snapshot modified” error. A WAL that still contains data continues to block export until the snapshot is finalized. [Export fix](https://github.com/lareferencia/lareferencia-core-lib/commit/2beb753a1cfd03931ee5af41e2932578489f38c9)
- XOAI exports preserve the text of unnamed value fields. The classification profile includes all configured Dublin Core field variants and writes descriptions under the `descriptions` key.
- XOAI export profiles can exclude values by prefix. Version 1.1 of the license profile uses this option to filter COAR and `info:eu-repo` values from JSON and JSONL exports. Metadata tools include Python commands for counting exported rights statements and normalizing license values. [License inventory workflow](lareferencia-metadata-tools/docs/LICENSE_METADATA_EXTRACTION.md)
- The Python command `prepare-embedding-metadata --combine` produces one input per titled record for the batch embedding calculator. It puts English titles and abstracts first, appends keywords in source order and preserves uncertain description fallbacks. Add `--include-provenance` for export and occurrence references.
- The batch embedding calculator reads packages prepared with `--combine` and produces one vector per record, preserving the network and catalog ID. [Calculator guide](lareferencia-metadata-tools/docs/EMBEDDING_METADATA.md)

## 5.0.0-rc4 — 2026-11-18

### Fixes

- Orphaned metadata cleanup stops before scanning or deleting data if it cannot read a protected catalog or if it loads zero protected references. [Core library PR #23](https://github.com/lareferencia/lareferencia-core-lib/pull/23) · [Platform PR #114](https://github.com/lareferencia/lareferencia-platform/pull/114)
- The OAI-PMH provider's Docker build now copies static assets from the correct directory, `static/`. [Platform PR #112](https://github.com/lareferencia/lareferencia-platform/pull/112)
