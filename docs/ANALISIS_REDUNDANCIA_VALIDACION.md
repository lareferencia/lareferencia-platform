# Redundancia entre catálogo y validación

El catálogo (`oai_record`) y la validación (`record_validation`) son persistencias SQLite separadas. El catálogo conserva identidad OAI, fecha, hash original y `deleted`; la validación conserva reglas, transformación, hash publicado y ocurrencias.

La separación evita mezclar procedencia con resultados de reglas. Actualmente no existe una máquina de estados incremental completa: `deleted` se conserva en catálogo y `streamNotDeleted` excluye bajas de validation.

La evolución propuesta debe comparar identidad, fecha y hash durante harvesting; clasificar nuevos/cambiados/sin cambios/borrados; validar sólo los afectados; actualizar o eliminar documentos afectados; y registrar éxito/error por etapa. Esa evolución está en `ISSUE_INCREMENTAL_RECORD_PROCESSING.md` y no debe describirse como capacidad disponible.

Un resultado de validación sólo puede reutilizarse si coinciden snapshot, hash de entrada y versión de reglas. Los cambios de esquema requieren migración SQLite y pruebas de reinicio/reconciliación.
