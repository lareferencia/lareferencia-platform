# Changelog

## Unreleased

### Fixes

- Githelper allows local configuration and generated files during workspace checkout when Git can preserve them. Git reports any files that block the change.

### Metadata export

- `prepare-classification-dataset` creates one plain or EmbeddingGemma classification text per annotated record. Prediction retains available FORD labels and can reuse the training text recipe.
- `compute-metadata-embeddings` accepts classification datasets and carries their reference labels into JSONL and SQLite vector packages.
- XOAI mappings support record selection by value prefix. The FORD profile exports all titles, descriptions and subjects of matching records.
- Metadata tools adds selectable annotation profiles. FORD annotations preserve original subjects and extract deduplicated second-level BECyT codes with occurrence provenance; existing bibliographic and combined preparation retain their behavior.

### Repository dashboard

- Opening or closing the harvest comparison preserves dates entered in the history filter until the user applies or resets them.
- The dashboard's TypeScript record type matches historical validation responses. Rule IDs can be strings or numbers, and metadata, outcomes and occurrence fields can be absent or null.
- The production build now type-checks the dashboard tests in CI. The history tests cover applying draft dates, resetting them and retrying a failed read. [Review and verification](https://github.com/lareferencia/lareferencia-repository-dashboard/blob/ea9bcbfca418442f37172709201096411d2c6e41/docs/CODE_REVIEW.md#rc6-follow-up)

## 5.0.0-rc5

### Upgrading from 5.0.0-rc4

- **Check the database before starting the upgraded harvester.** Run `database_info` from the updated `lareferencia-shell` and apply any pending Flyway migrations with `database_migrate`. The harvester applies the action catalogue defaults when it creates the catalogue. Existing catalogues retain their saved settings. [Database migration](docs/AUTHENTICATION.md)

- **Plan for one full validation per network.** The first validation after the upgrade processes the network's entire active catalog. Historical reports remain available. Networks with rules that depend on the current year also revalidate their catalogs after the year changes. [Upgrade details](docs/VALIDACION_COMPATIBILIDAD.md#efectos-al-actualizar)
- **Existing validation and transformation profiles load without migration.** The engine, shell and v5 API recognize historical rule names, including validators embedded in transformers. An optional shell migration updates class references while preserving dictionary entries, expressions and descriptions. [Profile compatibility](docs/VALIDACION_COMPATIBILIDAD.md)
- **Check rules that depend on how many field values match.** Field expressions now apply the quantifier saved in the profile. For example, with `ALL`, a content rule accepts an absent field, while an XPath rule requires at least one selected occurrence. The bundled Nodo Central profile now requires at least one nonempty title. Administrators can add the **Title — Presence** rule to an installed profile alongside its existing title-length check. [Quantifier behavior and title rule setup](docs/VALIDACION_COMPATIBILIDAD.md)
- **Downgrading after adopting new rule options requires a profile change.** Before switching back to RC4, restore any profile that uses `ReduceRecordsBySizeRule` or `ImportEnrichments` to its earlier configuration and remove the new `processAllOccurrences` property wherever it was saved. Run validation again after switching engines. [Rollback instructions](docs/VALIDACION_COMPATIBILIDAD.md#opciones-de-transformación-y-reversión)
- **Update scripts that call the Python tools by file path.** Install `lareferencia-metadata-tools` from the pinned workspace with Python 3.12 or later and use its command-line entry points. This replaces the Python scripts previously run from the platform and shell directories. The Java `export-metadata` command and its JSON profiles remain in the shell. [Installation and command names](lareferencia-metadata-tools/README.md#installation)

### Repository dashboard

- Maven and the platform and Docker build scripts now build the React dashboard by default and serve it at `/dashboard/`. The optional `dashboard-react` Maven profile also produces a standalone ZIP. The Angular source remains in `angular/`. The platform lock pins the dashboard revision alongside the harvester modules.
- Users can search the repositories they have access to by name or acronym. Administrators can enable harvest history, validation reports and usage statistics across the English, Spanish and Portuguese interfaces, and assign a statistics provider ID to each repository. The usage widget follows the dashboard's typography. [Dashboard configuration](https://github.com/lareferencia/lareferencia-repository-dashboard/blob/6c385975ed41b008ec59190ead9d4bfc19c6558a/docs/CONFIGURATION.md)
- Harvest history opens with a trend chart. The paginated history and its CSV list the newest harvests first. Users can compare two harvests by date and time, share the comparison by link and open either harvest's diagnostics. A saved pair can be recovered when the original results page is unavailable. A link with three harvests prompts the user to select two.
- Validation reports identify valid and invalid records. Filters apply to the summary, rule pass rates and counts of individual field values across all pages. Users can inspect values by rule and export visible rules, the current records page or rule frequencies as CSV. [Report API](docs/HARVESTER_MANAGEMENT_API_V5.md)
- Historical reports retain their rules and record counts when a validator is edited or replaced. New reports record whether each rule captured field values. For older reports, the dashboard checks for stored values before offering **View occurrences**. **No count** identifies an unavailable occurrence count, and passed and failed record totals remain available. [Historical report behavior](docs/HARVESTER_MANAGEMENT_API_V5.md)

### Validation and transformation

- `ImportEnrichments` adds selected values from a published SQLite edition to XOAI during validation. In Admin, configure the SQLite filename for each network and map source properties to qualified XOAI fields. A mapping can select a producer. The rule matches the catalog ID and original metadata hash, preserves existing values and skips duplicates. Validation continues when the edition is absent and stops at startup if the edition is invalid. Installing, replacing or removing the edition triggers a full validation on the next run. The form includes help in English, Spanish and Portuguese. [Configuration](docs/VALIDACION_COMPATIBILIDAD.md#enriquecimientos-sqlite)
- Field translation and conditional addition now write all applicable changes to the published XML. A value in another field no longer blocks a translation into its destination. Cleanup also removes empty XML field elements. A regular-expression replacement counts an identifier as transformed only when its value changes. [Rule behavior](docs/VALIDACION_COMPATIBILIDAD.md#efectos-al-actualizar)
- Administrators can configure `FieldAddRule` to skip a fixed value already present in the field. Existing profiles continue adding it on each pass. Field-renaming rules can process every occurrence with `processAllOccurrences`. The default limit is 101. The new `ReduceRecordsBySizeRule` removes selected fields only when the XML exceeds a configured size in UTF-8 bytes. Existing `ReduceHeavyRecords` rules keep their original behavior. [Rule options](docs/VALIDACION_COMPATIBILIDAD.md)
- The engine reuses large vocabulary lookups within a validation run and reduces repeated XML searches and writes during normalization, cleanup, renaming, translation and the addition of repository and provenance fields. Existing profiles retain their configured term matching, value order and translation priorities. In benchmarks, removing duplicate values was faster, while removing only invalid values was slower. [Compatibility tests and measurements](docs/VALIDACION_COMPATIBILIDAD.md)
- URL validation has configurable connection and read timeouts. The defaults are 5 seconds to connect and 10 seconds to read. [Timeout settings](docs/VALIDACION_COMPATIBILIDAD.md#efectos-al-actualizar)

### Harvester administration and API

- The Admin labels the dARK identifier minting step **Minting dARK**, with Spanish and Portuguese translations.

- VuFind indexers now default to the `vufind5` profile, including frontend, thesis and both semantic indexers. OpenAIRE sources use their dedicated DataCite and OpenAIRE mapping with that profile. Run a full reindex to apply the profile across existing documents.

- Batch actions return a result for every source, including the reason a source could not run the action. The cancellation confirmation has an accessible name.
- Reloading an admin link with a valid session preserves the destination. Administrators can browse snapshot history, retry loading a report table and view the published XML for a record in its original network. Identifier searches run when the user selects Search or presses Enter.
- The v5 diagnostics API supports both exact OAI identifier matching and substring searches. Historical XML access is scoped to the network that owns the snapshot. The API returns HTTP 403 when a user's role does not permit an administrative operation. The read-only listing fetches only the data it displays. [API behavior and permissions](docs/HARVESTER_MANAGEMENT_API_V5.md)
- Orphaned metadata cleanup records the hashes it scanned, identified as deletion candidates and deleted in the history of the protected snapshots.
- A Solr timeout in the harvester test environment was fixed. An indexing check from the admin interface matched all 3,444 active, valid identifiers in a historical snapshot to the documents in Solr. [Indexing verification](docs/ADMIN_UI_INDEXACION.md)

### OAI-PMH provider

- The protocol and repository integration tests now start reliably when reverse DNS is slow in Docker. The tests still wait for the OAI Solr core to answer a query before indexing sample records.

### Metadata exports and licenses

- The Java shell exports the latest valid snapshot (LGK) by network acronym, with original or processed metadata and an optional valid-only filter. JSON and JSONL use a named profile. Packages retain the catalog ID, OAI identifier, metadata hash and record location for downstream joins. Use `export-mapping-list` to discover the bundled profiles. [Export commands and package contract](docs/METADATA_EXPORT.md)
- XOAI mappings preserve values in unnamed fields. The classification profile includes all title, description and subject variants and exports descriptions under `descriptions`. The license profile uses prefix exclusions for COAR and `info:eu-repo`. Snapshot exports accept an empty SQLite write-ahead log (WAL), including one removed during the check. A WAL with pending data requires a finalized snapshot before export. [Export profiles and snapshot checks](docs/METADATA_EXPORT.md)
- The workspace and platform release ZIP include `lareferencia-metadata-tools`, installable separately with Python 3.12 or later. The release workflow synchronizes its version with the platform using PEP 440. The shell supplies the Java exporter and JSON profiles. Install the Python package to use the processing commands. [Installation and commands](lareferencia-metadata-tools/README.md)
- Use `count-export-licenses` for inventories of distinct rights statements and `run-rights-pipeline` to publish `enrichments.sqlite` from a fresh export or an existing complete package. The v7 taxonomy produces two license facets and a copyright facet. Spanish `Derechos de autor` declarations map to `NOTICE`. Producers can ingest results in batches and retrieve published values by network and catalog ID or OAI identifier. [License extraction](lareferencia-metadata-tools/docs/LICENSE_METADATA_EXTRACTION.md) · [Enrichment package](lareferencia-metadata-tools/docs/METADATA_ENRICHMENT_PACKAGE.md)

### Preparing and calculating embeddings

- `prepare-embedding-metadata` classifies bibliographic text and annotates titles and abstracts with their detected languages. Its default package includes titles, abstracts, raw keywords, affiliations, funders, document types and other descriptions. Use `--combine` for one input per record with a usable title. It places English titles and abstracts first, appends keywords in source order and can use an uncertain description when no abstract is accepted. `--include-provenance` adds export and occurrence references. [Text preparation](lareferencia-metadata-tools/docs/EMBEDDING_METADATA.md)
- `compute-metadata-embeddings` accepts prepared texts and complete Java JSONL exports. Choose GZIP JSONL (the default) or direct SQLite with `--format sqlite`. The JSONL path from a Java export preserves the historical `metadata-embeddings` v1 contract. EmbeddingGemma defaults to 768 dimensions. At 512 or 256 it truncates to the first components and renormalizes in float32. The manifest records the model revision, recipe and dimensions. [Calculator and output formats](lareferencia-metadata-tools/docs/EMBEDDING_METADATA.md#calculate-vectors)
- `enrichments pack-vectors` converts prepared vector packages to SQLite without recomputing them. The SQLite edition stores one float32 vector per network and catalog ID with links to the source package. `enrichments lookup-vector` retrieves a vector by that key. [SQLite vector editions](lareferencia-metadata-tools/docs/METADATA_ENRICHMENT_PACKAGE.md#pack-calculated-embeddings-in-sqlite)

### Indexing precomputed vectors in Solr

- **Semantic Indexing (precomputed)** publishes complete bibliographic documents with vectors from the network’s SQLite edition. In Harvester Admin, enable `SEMANTIC_DB_INDEXING_ACTION` under **Actions**, then run it from the network’s **Run action** menu. New snapshot indexing results use the worker key `semanticDbIndexerWorker`. [Admin steps for AR](docs/SEMANTIC_INDEXING_CHUNKING.md#run-for-ar-from-harvester-admin)
- Place the manifest and SQLite file in `${store.basepath}/<network>/embeddings/`, alongside `enrichments/`. The worker verifies the package and Solr field dimension before deleting existing documents. It matches vectors by network and catalog ID and retains the bibliographic documents that have no vector. After replacing an edition, run the action again to rebuild the network. [Configuration and reindexing](docs/SEMANTIC_INDEXING_CHUNKING.md#precomputed-sqlite-vectors)
- **Remove Semantic Index (precomputed)** adds the manual `SEMANTIC_DB_DELETE_ACTION`. It deletes the selected network’s documents from the same Solr destination as the precomputed indexer and checks that none remain after commit. [Removal from Harvester Admin](docs/SEMANTIC_INDEXING_CHUNKING.md#remove-a-network-from-the-precomputed-index)
- New legacy catalogues place the precomputed actions after their respective semantic indexing and deletion actions. All four start disabled. Existing catalogues retain their saved order, enablement and configuration. [Action catalogue defaults](docs/WORKFLOW_ACTIONS.md)
- Harvester Admin displays the precomputed indexing and removal labels in English, Spanish and Portuguese.
- A local Docker test launched from the Admin indexed all 24 records in an AR sample into VuFind’s `biblio` core on Solr 9.11. A kNN query recovered the same 24 IDs as the 512-dimensional SQLite edition. A separate check rejected a 1024-dimensional destination field before deleting any documents.

## 5.0.0-rc4 — 2026-11-18

### Fixes

- Orphaned metadata cleanup stops before scanning or deleting data if it cannot read a protected catalog or if it loads zero protected references. [Core library PR #23](https://github.com/lareferencia/lareferencia-core-lib/pull/23) · [Platform PR #114](https://github.com/lareferencia/lareferencia-platform/pull/114)
- The OAI-PMH provider's Docker build now copies static assets from the correct directory, `static/`. [Platform PR #112](https://github.com/lareferencia/lareferencia-platform/pull/112)
