> **[ARCHIVED 2026-09-23]** Pre-incremental snapshot of the SQLite catalog schema. Superseded by the incremental implementation (commit `7cf2a01`, 2026-09-04: `change_type` N/U/D, `streamChanged`, validation manifest). See [`../ISSUE_INCREMENTAL_RECORD_PROCESSING.md`](../ISSUE_INCREMENTAL_RECORD_PROCESSING.md). Kept for historical reference.

# Arquitectura del catálogo SQLite

`CatalogDatabaseManager` crea la base SQLite y `OAIRecordCatalogRepository` encapsula el catálogo OAI por snapshot.

```sql
CREATE TABLE oai_record (
  id TEXT PRIMARY KEY,
  identifier TEXT NOT NULL UNIQUE,
  datestamp TEXT NOT NULL,
  original_metadata_hash TEXT,
  deleted INTEGER NOT NULL DEFAULT 0
);
```

Existen índices para `deleted` y `datestamp`; las escrituras actuales son idempotentes por identificador y el repositorio ofrece `streamAll`/`streamNotDeleted`.

`HarvestingWorker` escribe el catálogo; `ValidationWorker` lee activos y escribe `validation.db`; `IndexerWorker` consume resultados de validación. El filtrado fino por cambios aún no está implementado.

El esquema no contiene estado de etapa, versión de reglas ni hash indexado. Esa ampliación está especificada en `ISSUE_INCREMENTAL_RECORD_PROCESSING.md` y requiere migración SQLite, pruebas de reinicio y reconciliación.
