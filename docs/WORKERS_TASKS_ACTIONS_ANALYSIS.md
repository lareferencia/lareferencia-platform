# Workers, tasks y actions

`BaseWorker` gestiona ciclo de vida y contexto; `BaseBatchWorker` procesa lotes; `BaseIteratorWorker` procesa un `Iterator` con hooks `preRun`, `prePage`, `processItem`, `postPage` y `postRun`.

Flujo actual: harvesting obtiene OAI y escribe SQLite; validation lee registros no borrados, aplica reglas y transformaciones y escribe `validation.db`; indexing publica resultados en Solr/OpenSearch/Elasticsearch; las acciones de cierre actualizan snapshot, estadísticas y logs.

`workflow.engine=legacy` es el default y ejecuta acciones XML mediante `TaskManager`. `workflow.engine=flowable` usa BPMN y delegates. Una instalación debe documentar el valor activo.

El flujo actual no tiene una máquina de estados completa por registro. La selección de nuevos/cambiados/reprocesados y la actualización parcial del índice son evolución futura en `ISSUE_INCREMENTAL_RECORD_PROCESSING.md`.

Los workers deben ser idempotentes, respetar cancelación y registrar errores por registro/snapshot. Cualquier cambio incremental debe probar reinicios, reintentos, bajas y cambios de reglas.
