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

Run the command once per target index that must be cleaned.

## Expected Behavior

- New entities continue to use `deleted=false`.
- Entities with `deleted=true` are excluded from the main `index-entities` pagination.
- Entities with `deleted=true` are also excluded as related/nested entities in other entity documents.
