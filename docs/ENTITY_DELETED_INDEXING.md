# Change Summary: Entity `deleted` Flag

**Status:** current · **Last verified:** 2026-09-23

This change adds the `deleted` flag to final entities and uses it to skip logically deleted entities during indexing.

## Changed Areas

Links are repository-relative (fixed 2026-09-23; they previously pointed to a local absolute path).

- `Entity` now has `deleted=false` by default: [Entity.java](../lareferencia-entity-lib/src/main/java/org/lareferencia/core/entity/domain/Entity.java) (`deleted` column, ~line 103)
- `index-entities` pagination filters by `dirty=false` and `deleted=false`: [EntityPaginator.java](../lareferencia-entity-lib/src/main/java/org/lareferencia/core/entity/workers/EntityPaginator.java)
- Related/nested entities also skip related entities with `deleted=true`: [EntityRepository.java](../lareferencia-entity-lib/src/main/java/org/lareferencia/core/entity/repositories/jpa/EntityRepository.java)
- Migration created with `deleted boolean NOT NULL DEFAULT FALSE`: [V5.0.0.7__Add_Entity_Deleted_Flag.sql](../lareferencia-shell/src/main/resources/db/migration/V5.0.0.7__Add_Entity_Deleted_Flag.sql)
- Shell command `mark_entities_deleted` (marks entities as deleted from a UUID file, ~line 372): [EntityDataCommands.java](../lareferencia-shell-entity-plugin/src/main/java/org/lareferencia/shell/commands/entity/EntityDataCommands.java)
- Shell command `remove_deleted_entities_from_index` (removes deleted entities and their nested references from a specific Elasticsearch/OpenSearch index, ~line 453): [EntityDataCommands.java](../lareferencia-shell-entity-plugin/src/main/java/org/lareferencia/shell/commands/entity/EntityDataCommands.java)

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

To remove already-indexed deleted root entities from one index:

```bash
remove_deleted_entities_from_index --indexName brc-nov2025-person --entity person
```

For large indexes, use a larger page size and request timeout:

```bash
remove_deleted_entities_from_index --indexName brc-nov2025-person --entity person --pageSize 10000 --timeoutSeconds 900
```

For very large indexes where the deleted entities are known to appear in specific nested relation fields, restrict the cleanup to those fields. For example, to remove deleted journal references stored under `journal.id`:

```bash
remove_deleted_entities_from_index --indexName brc-nov2025-journal-v2 --entity journal --pageSize 10000 --timeoutSeconds 900 --relationFields journal
```

Parameters:

- `--indexName`: target Elasticsearch/OpenSearch index. Required.
- `--entity`: entity type whose `deleted` records will be fetched from the database. Required.
- `--pageSize`: number of deleted entity IDs processed per batch. Default: `1000`.
- `--timeoutSeconds`: REST request timeout for delete/update-by-query operations. Default: `300`.
- `--relationFields`: optional comma-separated relation object field names to clean, such as `journal` or `journal,publisher`. When omitted, the command removes root documents. When provided, it removes deleted IDs only from the listed relation fields.

Operational notes:

- Run the command once per target index that must be cleaned.
- The command fetches only deleted records of the entity type passed with `--entity`.
- Without `--relationFields`, it deletes root documents whose `_id` matches a deleted entity UUID.
- With `--relationFields`, it removes relationship entries with an `id` matching a deleted entity UUID only from the listed fields, using `_update_by_query`.
- If the Elasticsearch/OpenSearch endpoint uses HTTPS, set `elastic.useSSL=true`.
- The command is idempotent and can be safely re-run; already removed documents or relationships become no-ops.

## Expected Behavior

- New entities continue to use `deleted=false`.
- Entities with `deleted=true` are excluded from the main `index-entities` pagination.
- Entities with `deleted=true` are also excluded as related/nested entities in other entity documents.
