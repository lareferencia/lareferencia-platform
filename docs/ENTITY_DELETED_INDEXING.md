# Change Summary: Entity `deleted` Flag

This change adds the `deleted` flag to final entities and uses it to skip logically deleted entities during indexing.

## Changed Areas

- `Entity` now has `deleted=false` by default: [Entity.java (line 103)](/Users/jesiel/dev/ioi/lareferencia-platform/lareferencia-entity-lib/src/main/java/org/lareferencia/core/entity/domain/Entity.java:103)
- `index-entities` pagination filters by `dirty=false` and `deleted=false`: [EntityPaginator.java (line 131)](/Users/jesiel/dev/ioi/lareferencia-platform/lareferencia-entity-lib/src/main/java/org/lareferencia/core/entity/workers/EntityPaginator.java:131)
- Related/nested entities also skip related entities with `deleted=true`: [EntityRepository.java (line 108)](/Users/jesiel/dev/ioi/lareferencia-platform/lareferencia-entity-lib/src/main/java/org/lareferencia/core/entity/repositories/jpa/EntityRepository.java:108)
- Migration created with `deleted boolean NOT NULL DEFAULT FALSE`: [V5.0.0.7__Add_Entity_Deleted_Flag.sql (line 1)](/Users/jesiel/dev/ioi/lareferencia-platform/lareferencia-shell/src/main/resources/db/migration/V5.0.0.7__Add_Entity_Deleted_Flag.sql:1)
- Shell command updated to mark entities as deleted from a UUID file: [EntityDataCommands.java (line 355)](/Users/jesiel/dev/ioi/lareferencia-platform/lareferencia-shell-entity-plugin/src/main/java/org/lareferencia/shell/commands/entity/EntityDataCommands.java:355)
- Shell command added to remove deleted entities and their nested references from a specific Elasticsearch/OpenSearch index: [EntityDataCommands.java (line 435)](/Users/jesiel/dev/ioi/lareferencia-platform/lareferencia-shell-entity-plugin/src/main/java/org/lareferencia/shell/commands/entity/EntityDataCommands.java:435)

## Usage

Before using the command against an existing database, run the database migration so the `entity.deleted` column exists:

```bash
database_migrate
```

To mark entities as deleted and skip them in future indexing runs:

```bash
mark_entities_deleted --path /path/to/uuids.txt
```

The file may contain UUIDs separated by lines, spaces, commas, or semicolons. Comments starting with `#` are ignored.

## Revert

To re-enable entities for indexing:

```bash
set_entities_deleted --path /path/to/uuids.txt --deleted false
```

## Elasticsearch Cleanup

To remove already-indexed deleted entities from one index, and remove nested references to those deleted IDs from documents in that same index:

```bash
remove_deleted_entities_from_index --indexName brc-nov2025-person
```

For large indexes, use a larger page size and request timeout:

```bash
remove_deleted_entities_from_index --indexName brc-nov2025-person --pageSize 10000 --timeoutSeconds 900
```

For very large indexes where the deleted entities are known to appear in specific nested relation fields, restrict the cleanup to those fields. For example, to remove deleted journal references stored under `journal.id`:

```bash
remove_deleted_entities_from_index --indexName brc-nov2025-journal-v2 --pageSize 10000 --timeoutSeconds 900 --relationFields journal
```

Parameters:

- `--indexName`: target Elasticsearch/OpenSearch index. Required.
- `--pageSize`: number of deleted entity IDs processed per batch. Default: `1000`.
- `--timeoutSeconds`: REST request timeout for delete/update-by-query operations. Default: `300`.
- `--relationFields`: optional comma-separated relation object field names to clean, such as `journal` or `journal,publisher`. When provided, the command queries `<field>.id` instead of scanning the whole index.

Operational notes:

- Run the command once per target index that must be cleaned.
- The command deletes root documents whose `_id` matches a deleted entity UUID.
- It also removes nested relationship entries with an `id` matching a deleted entity UUID from documents in the same index.
- Relationship cleanup uses `_update_by_query`; on large indexes, use `--relationFields` when the deleted entity type maps to known relation fields.
- If the Elasticsearch/OpenSearch endpoint uses HTTPS, set `elastic.useSSL=true`.
- The command is idempotent and can be safely re-run; already removed documents or relationships become no-ops.

## Expected Behavior

- New entities continue to use `deleted=false`.
- Entities with `deleted=true` are excluded from the main `index-entities` pagination.
- Entities with `deleted=true` are also excluded as related/nested entities in other entity documents.
