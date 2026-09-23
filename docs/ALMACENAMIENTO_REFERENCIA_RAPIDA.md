# Referencia rápida: almacenamiento

**Status:** current · **Last verified:** 2026-09-23

`store.basepath` es la raíz de los datos locales. Cada red mantiene sus datos bajo un directorio sanitizado y los snapshots bajo `snapshots/snapshot_<id>/`.

| Dato | Persistencia | Responsable |
|---|---|---|
| Metadata de redes/snapshots | SQL | `ISnapshotStore` |
| Catálogo OAI | SQLite | `CatalogDatabaseManager` y `OAIRecordCatalogRepository` |
| Registros | SQLite | tabla `oai_record`: `id`, `identifier`, `datestamp`, `original_metadata_hash`, `deleted` |
| Validación y reglas | SQLite | `validation.db`, `record_validation`, `rule_occurrences` |
| Metadata XML | FS, H2 o SQLite | opción `metadata.store.type` (`FS\|H2\|SQLITE`) |
| Logs | ficheros de texto | `SnapshotLogService` |

`deleted=1` indica una baja en el origen. Desde el 2026-09-04 el catálogo y la base de validación son **incrementales**: `oai_record.change_type` (`N`/`U`/`D`) e `idx_change_type`, `streamChanged()`, y reutilización de validación vía fingerprint + manifiesto. Ver `ISSUE_INCREMENTAL_RECORD_PROCESSING.md`.

*Actualizado 2026-09-23 (antes: `metadata.store.option` y nota "no incremental", corregidas).*

Los backups deben incluir las bases SQLite, metadata filesystem y logs. La eliminación de un snapshot debe retirar todos esos datos mediante `ISnapshotStore`.
