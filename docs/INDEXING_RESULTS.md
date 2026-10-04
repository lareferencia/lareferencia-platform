# Resultados de indexación por worker

Cada snapshot conserva el último resultado terminado de cada bean indexador en
una columna JSONB `networksnapshot.indexing_results`. La clave es el nombre del
bean Spring, no la clase del worker ni el esquema de destino. El nombre de la
acción queda como contexto del resultado.

El resultado tiene `status` (`INDEXED` o `FAILED`), `actionName`, `finishedAt` UTC
y un motivo breve `error` cuando falla. Un reintento reemplaza solamente la entrada
del mismo bean. No se guardan pendientes ni un historial de intentos en esta columna.

`indexstatus` se conserva como resumen legacy de los resultados registrados:
si alguno falló, `FAILED`; si todos fueron correctos, `INDEXED`; sin resultados,
`UNKNOWN`. No intervienen los indexadores habilitados que todavía no corrieron.
Los snapshots históricos conservan su valor legacy hasta registrar resultados
nuevos; no se infieren éxitos por worker desde el resumen antiguo.

`SnapshotIndexingService` es el único escritor de ambas columnas. Bloquea la fila
durante una transacción corta para incorporar un resultado y actualizar el resumen
sin perder escrituras concurrentes. La finalización se persiste en una transacción
independiente de las páginas del worker. Las columnas no son actualizables mediante
un guardado JPA general de `NetworkSnapshot`, para impedir que una entidad vieja
sobrescriba los resultados nuevos. `ISnapshotStore.markAsIndexed` permanece como
adaptador legacy; no puede esconder fallos ya registrados.

`BaseIndexerWorker` cubre el cierre normal, errores de preparación o procesamiento,
excepciones, cancelaciones y errores parciales manejados dentro del worker.
Solo confirma éxito después del commit y sin errores registrados. Una cancelación
anterior a entrar al worker no genera resultado. Las exclusiones por filtros,
registros no válidos y textos vacíos o por debajo de los umbrales semánticos siguen
sin considerarse errores; fallos al obtener metadatos, transformar, enviar a Solr
o generar embeddings sí se registran como fallo.

Al reiniciar la validación, `resetSnapshotValidationCounts` limpia el mapa y el
resumen, dentro de la misma transacción de validación. Un contador interno
`generation` en el JSON evita que una indexación anterior terminada tarde vuelva a
publicar su resultado después de esa limpieza. Este contador no se expone en la API v5.

La API v5 devuelve un mapa `indexingResults` en las respuestas de snapshots y
resúmenes de fuentes. La administración muestra un indicador compacto `OK`,
`Fallo` o `—` en el listado, el historial y el detalle de la fuente. Al pulsarlo,
un modal del snapshot muestra cada indexador, resultado, fecha y motivo del fallo.
La acción y el nombre técnico del bean se despliegan por indexador. Los mensajes
están disponibles en español, inglés y portugués.

## Migración

La migración está incorporada en `lareferencia-shell` como
`src/main/resources/db/migration/V5.0.0.17__Snapshot_indexing_results.sql`.
Antes de arrancar esta versión sobre una base existente, reconstruir el shell
con los nuevos recursos y ejecutar su comando habitual `database_migrate`
(también utilizado por `init-db`). Flyway registra la versión aplicada.

La migración añade una sola columna, mantiene los estados legacy históricos y
es compatible con bases que ya ejecutaron el SQL separado
`lareferencia-lrharvester-app/config/sql/snapshot-indexing-results.sql`.
Ese script permanece disponible como alternativa manual. No se requieren tablas
nuevas ni índices adicionales.

## Verificación

Pruebas de cierre del worker y errores manejados:

```sh
mvn -pl lareferencia-core-lib -am \
  -Dtest=BaseIndexerWorkerTest,IndexingWorkerErrorTest \
  -Dsurefire.failIfNoSpecifiedTests=false test
```

Las pruebas PostgreSQL son optativas y usan `create-drop`. Requieren una base
descartable exclusiva, con usuario `postgres` y contraseña de prueba
`indexing-test`; nunca se debe pasar la base del harvester:

```sh
mvn -pl lareferencia-core-lib -am \
  -Dtest=SnapshotIndexingServiceIntegrationTest \
  -Dsurefire.failIfNoSpecifiedTests=false \
  -Dindexing.test.jdbc-url=jdbc:postgresql://127.0.0.1:PUERTO/indexing_test test
```

Pruebas de contrato de API y UI:

```sh
mvn -pl lareferencia-lrharvester-app -am \
  -Dtest=ApiV5IndexingResultsTest -Dsurefire.failIfNoSpecifiedTests=false test
cd lareferencia-lrharvester-admin-web
npm test -- src/features/networks/IndexingResults.test.tsx
npm run typecheck
```
