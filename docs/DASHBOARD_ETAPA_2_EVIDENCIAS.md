# Etapa 2 · Lectura histórica de validación

**Verificación local del 19 de noviembre de 2026 en `codex/rc5-pre`.** El caso F4 se reprodujo editando por HTTP el validador vinculado a AREANDINA. La corrección permite añadir, modificar y borrar reglas, e incluso sustituir el validador de la red, conservando los resultados del snapshot anterior. El [plan de consolidación](DASHBOARD_PLAN_CONSOLIDACION.md) recoge el relevo.

## Entorno y datos

Se copiaron el clúster PostgreSQL detenido de `Docker/volume/dev/lareferencia-dev/lareferencia/postgres/data/pgdata`, la configuración de lrharvester y la carpeta `data/AREANDINA/snapshots/snapshot_6/validation`, incluido el WAL de SQLite. PostgreSQL 14 arrancó con su copia y el harvester del checkout usó ese JDBC y el almacén copiado. Ambos escucharon en loopback. Se desactivó la programación de redes en la copia y se creó un administrador temporal. La edición y las consultas usaron sesión real, CSRF, controladores Spring, JPA y SQLite. La entrada fue el puerto HTTP del harvester. El gateway y el navegador corresponden a otras etapas del plan.

La copia ya contenía la red 33, el snapshot 6 en estado VALID, el validador 1 y sus 14 reglas. Las ediciones se hicieron en el validador de la copia. El informe original tenía 4.000 registros activos, 0 válidos globalmente y 0 transformados. La regla 5 era opcional y tenía cuantificador ONE_OR_MORE. La aprobaron 1.871 registros y la fallaron 2.129.

## Secuencia para repetir en una instalación desechable

1. Iniciar sesión v5, renovar CSRF y guardar como referencia las respuestas del cuadro siguiente. Usar `Accept: application/json` y enviar los POST de consulta como JSON con la cabecera CSRF de la sesión.
2. Obtener la regla con `GET /api/v5/validators/1/rules/5`. Conservar `typeId`, configuración y propiedades de regla, retirar `id` y `className`, asignar un nombre nuevo y enviar a `POST /api/v5/validators/1/rules`. Se obtuvo 201. La base de la copia confirmó la nueva fila con ID 77.
3. Antes de la corrección, repetir las cinco consultas. El resumen global y las frecuencias siguieron respondiendo. El resumen filtrado y ambos listados pasaron a 422. El servicio componía la selección con reglas del validador actual, incluida una columna ausente de la SQLite histórica.
4. Arrancar el harvester corregido sobre las **mismas copias ya editadas**. Repetir las consultas. Cambiar además nombre y descripción de la regla 5, invertir su obligatoriedad y asignarle ZERO_ONLY mediante `PUT /api/v5/validators/1/rules/5` (200). Comparar otra vez. Borrar esa regla con DELETE (204) y volver a comparar.
5. Crear un validador vacío con `POST /api/v5/validators` (201) y asignarlo a la red mediante `PATCH /api/v5/networks/33` con `validatorId` (200). Verificar la asignación con GET y repetir las lecturas. Debe seguir siendo posible filtrar por la regla histórica 5.

Las consultas POST del experimento usaron este cuerpo:

```json
{"filters":[{"field":"RULE_VALID","operator":"EQ","value":5}],"page":0,"size":3}
```

| Consulta relativa a /api/v5 | Antes de editar | Regla añadida, código anterior | Tras corregir y editar el validador |
|---|---|---|---|
| GET `/snapshots/6/diagnostics/summary` | 200 · 4.000 registros y 14 reglas | 200 | 200 · mismas reglas, descripciones, cuantificadores y cifras |
| POST `/snapshots/6/diagnostics/summary/query` | 200 · 1.871 registros y 14 reglas | 422 | 200 · misma selección |
| POST `/snapshots/6/diagnostics/records/query` | 200 · 1.871 en total | 422 | 200 · mismo total y misma primera página de 3 registros con resultados por regla |
| POST `/snapshots/6/diagnostics/rules/10/occurrences/query` | 200 · 1.309 valores válidos y 6.314 inválidos, contando repeticiones | 200 | 200 · iguales listas de valores y frecuencias |
| GET `/dashboard/validation/source/AREANDINA/6/records?valid_rules=5&pageSize=3` | 200 · 1.871 en total | 422 | 200 · misma página y total |

Se comparó el JSON estructurado de las respuestas después de cada operación. La comprobación final de F4 preserva indicadores, reglas, identificadores, resultados y frecuencias. Se verificaron por separado el nuevo indicador de captura y el enriquecimiento de los campos de procedencia. El listado se comparó sobre la página pedida y el total del servidor.

## Reglas de lectura e interpretación

- **F4 · Snapshot con JSON y SQLite.** PostgreSQL identifica la red y localiza los archivos. El resumen global usa los contadores precalculados. En las consultas de registros y agregados filtrados, las columnas físicas de `record_validation` fijan los IDs de regla de ese snapshot. `validation-stats.json` proporciona las definiciones históricas asociadas a esos IDs. La finalización escribe el resumen mediante un temporal y lo publica por renombrado para que una lectura concurrente reciba un documento completo. [Servicio de estadísticas](../lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatisticsSQLiteService.java) · [Esquema de validación](../lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/validation/ValidationDatabaseManager.java)
- **F4 · Evidencia parcial.** Cuando un snapshot VALID conserva solo SQLite, se recuperan IDs, resultados y agregados de sus filas activas. Las reglas sin definición se identifican por su ID y devuelven cuantificador y obligatoriedad nulos. Si solo queda el resumen, los contadores globales siguen disponibles y se preservan los textos que existan. Para listas de registros, selecciones y frecuencias se necesita la base de detalle. [Conversión de reglas y contadores](../lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatsResult.java)
- **F6 · Captura de valores.** Los nuevos resúmenes conservan `occurrenceCaptureEnabled` por regla. Es verdadero cuando el diagnóstico detallado de la acción y la recogida de valores de la regla estaban activados, incluso si se procesaron cero registros. Falso indica captura desactivada. En históricos sin ese dato se devuelve nulo. Una lista vacía con captura desconocida no permite inferir su causa. Una ocurrencia sintética `no_occurrences_found` sigue siendo evidencia de cómo la regla evaluó un campo ausente. La UI podrá distinguir estos estados en la etapa 4. [Worker](../lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/validation/ValidationWorker.java) · [DTO nativo](../lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/api/v5/ApiV5Dtos.java)
- **F10 · Fecha y procedencia.** SQLite guarda el datestamp OAI del registro. Al reconstruir una observación compatible, `validationDate` queda nulo porque no se registró una hora de validación por fila. Se comprobó esta ausencia en `GET /api/v5/dashboard/validation/source/stats/AREANDINA/6/query?pageSize=1`. Para representar un snapshot terminado, la fecha de referencia es su `endTime`, descrita como fin del snapshot. La proyección usa origen, prefijo, acrónimo, nombre de fuente e institución del bloque histórico de red cuando existe. Si falta ese bloque se usa la información disponible de la red para localizar y contextualizar el snapshot. `setSpec` permanece nulo en estas observaciones porque la tabla de validación carece de ese campo. [Estado del snapshot](../lareferencia-core-lib/src/main/java/org/lareferencia/core/metadata/SnapshotStoreSQLImpl.java)

## Pruebas automatizadas

Desde la raíz de plataforma:

```sh
mvn -Plareferencia -pl lareferencia-lrharvester-app -am -Dno-frontends \
  -Dtest=HistoricalValidationReportTest,ValidationStatisticsSQLiteReadTest,IncrementalValidationLifecycleTest,ApiV5DiagnosticsSQLiteTest,ApiV5DiagnosticsServiceTest,ApiV5DashboardCompatibilityControllerTest \
  -Dsurefire.failIfNoSpecifiedTests=false test
```

Pasaron **37 casos Java**. Las cuatro regresiones históricas cubren la proyección de una regla modificada/retirada, el resumen de un hijo incremental con una baja, la recuperación desde SQLite sin JSON y la recuperación desde JSON parcial sin SQLite. La suite de ciclo de vida comprueba además la captura por regla con diagnóstico activado y desactivado aun cuando no quedan registros activos. Las pruebas de etapa 1 siguen cubriendo filtros, paginación, igualdad y frecuencias. En admin-web pasaron la compilación TypeScript y **74 pruebas Vitest**. [Regresión histórica](../lareferencia-core-lib/src/test/java/org/lareferencia/core/service/validation/HistoricalValidationReportTest.java) · [Ciclo de vida](../lareferencia-core-lib/src/test/java/org/lareferencia/core/worker/validation/IncrementalValidationLifecycleTest.java)
