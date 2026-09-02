# Referencia rápida: almacenamiento

`store.basepath` es la raíz de los datos locales. Cada red mantiene sus datos bajo un directorio sanitizado y los snapshots bajo `snapshots/snapshot_<id>/`.

| Dato | Persistencia | Responsable |
|---|---|---|
| Metadata de redes/snapshots | SQL | `ISnapshotStore` |
| Catálogo OAI | SQLite | `CatalogDatabaseManager` y `OAIRecordCatalogRepository` |
| Registros | SQLite | tabla `oai_record`: `id`, `identifier`, `datestamp`, `original_metadata_hash`, `deleted` |
| Validación y reglas | SQLite | `validation.db`, `record_validation`, `rule_occurrences` |
| Metadata XML | FS, H2 o SQLite | opción `metadata.store.option` |
| Logs | ficheros de texto | `SnapshotLogService` |

`deleted=1` indica una baja en el origen; no es todavía una máquina de estados incremental. Los estados de reprocesamiento son una propuesta documentada en `ISSUE_INCREMENTAL_RECORD_PROCESSING.md`.

Los backups deben incluir las bases SQLite, metadata filesystem y logs. La eliminación de un snapshot debe retirar todos esos datos mediante `ISnapshotStore`.
