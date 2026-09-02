# Issue: procesamiento incremental dirigido por el estado de cada registro

## Resumen

El pipeline actual crea snapshots incrementales correctos a nivel de catálogo: copia el catálogo del último snapshot válido y aplica los cambios recibidos desde OAI-PMH. Sin embargo, el carácter incremental no llega a las etapas posteriores. La validación vuelve a procesar todos los registros activos y cada indexador elimina y reconstruye todos los documentos de una fuente.

Este issue propone que el catálogo SQLite de cada snapshot mantenga explícitamente **qué cambió en cada registro** y que las etapas posteriores consuman ese delta de forma fiable, reintentable e idempotente.

El resultado esperado es:

```text
harvesting incremental
  -> determina altas / cambios / bajas / restauraciones
  -> validation procesa solo los registros cuyo resultado ya no es reutilizable
  -> cada indexador hace UPSERT o DELETE solo de los documentos afectados
```

La propuesta conserva la semántica actual de snapshots inmutables: cada snapshot sigue teniendo su propio `catalog.db` y `validation.db`. No convierte el catálogo en una base mutable global.

## Problema actual

### Estado actual del pipeline

1. `HarvestingWorker` crea un snapshot y, en modo incremental, copia el `catalog.db` del último snapshot válido.
2. Recibe desde OAI-PMH registros nuevos/modificados y cabeceras de borrado. El catálogo aplica `INSERT OR REPLACE` por `identifier`.
3. `ValidationWorker` abre el catálogo resultante y recorre `streamNotDeleted()`: por tanto vuelve a validar todos los registros activos, incluidos los heredados sin cambios.
4. `ValidationStatisticsSQLiteService` crea un `validation.db` vacío para el nuevo snapshot; no hereda resultados validados del snapshot anterior.
5. `IndexerWorker` obtiene el último snapshot válido, borra todos los documentos de la fuente en Solr y vuelve a indexar todos los registros válidos.

En consecuencia, una ejecución con una sola modificación puede volver a transformar, validar e indexar millones de registros.

### Limitaciones concretas

| Área | Comportamiento actual | Consecuencia |
|---|---|---|
| Catálogo | Solo tiene `deleted` y el hash de metadata original | No distingue registro heredado, nuevo, cambiado o restaurado |
| Upsert | `INSERT OR REPLACE` no preserva ni calcula una transición | No se puede decidir qué debe procesarse después |
| Prevalidación | Si un registro modificado no pasa el prevalidador, no se escribe | Puede sobrevivir en el catálogo la versión heredada anterior |
| Validación | Recorre todos los activos y recrea `validation.db` | El flag incremental no reduce trabajo |
| Índices | Borrado completo de fuente y reindexación completa | Alta carga en Solr, ventanas de inconsistencia y coste innecesario |
| Bajas | Se excluyen de la validación | Correcto para validar, pero no existe un delta explícito para que los indexadores borren solo esos documentos |
| Sin cambios | `EMPTY_INCREMENTAL` existe como enum pero no se persiste | No hay una forma fiable de omitir las etapas posteriores |
| Reintentos | El progreso no está representado por registro y destino | Es difícil reanudar sin repetir toda una etapa |

### Archivos relevantes

- `lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/harvesting/HarvestingWorker.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/catalog/CatalogDatabaseManager.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/catalog/OAIRecordCatalogRepository.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/validation/ValidationWorker.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatisticsSQLiteService.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/indexing/IndexerWorker.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/validation/ValidationRecordPaginator.java`

## Objetivos

1. Detectar y persistir el tipo de cambio de cada registro durante la cosecha.
2. Reutilizar resultados anteriores cuando el contenido y la configuración que los produjo sigan siendo válidos.
3. Validar y transformar únicamente registros pendientes de reproceso.
4. Aplicar a cada destino de indexación solo las operaciones necesarias: `UPSERT` y `DELETE`.
5. Hacer las etapas reintentables e idempotentes ante fallos parciales.
6. Poder explicar en diagnóstico y API cuántos registros fueron heredados, procesados, eliminados y omitidos.
7. Mantener una ruta explícita para forzar reproceso completo por cambios de configuración o por operación administrativa.

## No objetivos

- No cambiar el protocolo OAI-PMH ni eliminar el solapamiento temporal de consultas incrementales.
- No eliminar snapshots históricos ni sustituir el aislamiento por snapshot.
- No convertir la primera implementación en un sistema de eventos distribuido.
- No garantizar indexación atómica entre múltiples núcleos Solr; la idempotencia y el reintento son suficientes.
- No migrar en este issue al motor Flowable. La solución debe funcionar con el motor `legacy` actual.

## Principios de diseño

### 1. Separar el hecho de cambio del progreso de procesamiento

`change_type` describe un hecho inmutable del snapshot: cómo quedó el registro con relación al snapshot base. No debe cambiar a `DONE` cuando una etapa termina.

El avance de validation e indexing se guarda separadamente. Esto permite reintentar una etapa sin perder la explicación de por qué el registro fue seleccionado.

### 2. Separar estado de origen de elegibilidad de pipeline

Un registro puede existir en el origen pero no ser publicable por reglas de prevalidación. Por ello un booleano `deleted` no expresa todos los casos. Deben distinguirse:

- el estado comunicado por OAI-PMH (`ACTIVE` o `DELETED`);
- la aceptación de la prevalidación (`ACCEPTED` o `REJECTED`);
- el resultado de validación (`VALID` o `INVALID`).

Esto evita retener una versión vieja si la versión nueva es rechazada por el prevalidador.

### 3. El contenido y la configuración determinan reutilización

Un hash de metadata igual no basta cuando cambian validador, transformadores, XSLT o atributos de red. La reutilización debe estar ligada a una firma de entrada (`processing signature`) que incluya contenido y configuración relevante.

### 4. Los índices son destinos independientes

Un único `indexed=true` no es correcto: frontend, XOAI, semántico u otros índices pueden tener configuraciones, errores y ritmos distintos. El estado de indexación debe existir por destino.

### 5. Las operaciones deben ser idempotentes

Repetir un `UPSERT` con el mismo documento y un `DELETE` por identificador debe ser seguro. El worker debe marcar trabajo completado solo después de que el destino confirme la operación o el lote correspondiente.

## Modelo de datos propuesto

### Cambios en `catalog.db`

Ampliar `oai_record` sin retirar las columnas actuales:

```sql
ALTER TABLE oai_record ADD COLUMN source_state TEXT NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE oai_record ADD COLUMN harvest_acceptance TEXT NOT NULL DEFAULT 'ACCEPTED';
ALTER TABLE oai_record ADD COLUMN change_type TEXT NOT NULL DEFAULT 'INHERITED';
ALTER TABLE oai_record ADD COLUMN previous_metadata_hash TEXT;
ALTER TABLE oai_record ADD COLUMN change_detected_at TEXT;
ALTER TABLE oai_record ADD COLUMN validation_signature TEXT;
ALTER TABLE oai_record ADD COLUMN validation_state TEXT NOT NULL DEFAULT 'PENDING';
ALTER TABLE oai_record ADD COLUMN validation_error TEXT;

CREATE INDEX IF NOT EXISTS idx_oai_record_change_type
    ON oai_record(change_type);
CREATE INDEX IF NOT EXISTS idx_oai_record_validation_pending
    ON oai_record(source_state, harvest_acceptance, validation_state);
```

Las columnas `deleted` y `source_state` convivirán durante la migración. La aplicación deberá tratarlas como equivalentes mientras exista compatibilidad: `deleted=1` equivale a `source_state='DELETED'`. Una vez terminada la migración, se evaluará eliminar o deprecar `deleted`; no es requisito de este issue.

### Enumeraciones

#### `source_state`

| Valor | Significado |
|---|---|
| `ACTIVE` | El origen provee una versión actual del registro |
| `DELETED` | El origen informó una cabecera OAI-PMH con estado deleted |

#### `harvest_acceptance`

| Valor | Significado |
|---|---|
| `ACCEPTED` | El registro supera la prevalidación o no hay prevalidador |
| `REJECTED` | El registro fue recibido, pero no cumple prevalidación; no debe conservarse la versión anterior como vigente |

#### `change_type`

| Valor | Significado |
|---|---|
| `INHERITED` | Copiado del snapshot anterior y no modificado en esta cosecha |
| `NEW` | No existía en el snapshot anterior |
| `UPDATED` | Existía y cambió la metadata, datestamp, estado OAI o aceptación |
| `DELETED` | El origen lo marcó como eliminado |
| `RESTORED` | Existía como eliminado o rechazado y vuelve a estar aceptado/activo |
| `UNCHANGED_SEEN` | Opcional: fue devuelto por la ventana solapada, pero su contenido y estado no cambiaron. Puede normalizarse a `INHERITED` antes de finalizar harvesting. |

`INHERITED` es el valor que quedará como estado final de registros sin cambio. `UNCHANGED_SEEN` es opcional y solo sirve si se desea auditar cuántos registros regresaron en el solapamiento OAI-PMH.

#### `validation_state`

| Valor | Significado |
|---|---|
| `INHERITED` | Resultado copiado del snapshot anterior y compatible con la firma actual |
| `PENDING` | Debe validarse/transformarse |
| `PROCESSING` | Reservado por el worker; recuperable si el proceso muere |
| `VALID` | Procesado correctamente; el resultado puede ser válido o inválido, que vive en `validation.db` |
| `SKIPPED` | No corresponde validar: `DELETED` o `REJECTED` |
| `FAILED` | Falló de manera terminal o agotó reintentos |

El nombre `VALID` aquí significa “validación ejecutada correctamente”, no “el documento pasó las reglas”. La validez editorial se conserva en `record_validation.is_valid`.

### Tabla por destino de procesamiento

Crear `record_processing` dentro de `catalog.db`, porque representa la decisión de pipeline del snapshot y no un resultado específico de reglas:

```sql
CREATE TABLE IF NOT EXISTS record_processing (
    record_id TEXT NOT NULL,
    stage TEXT NOT NULL,
    target TEXT NOT NULL,
    operation TEXT NOT NULL,
    state TEXT NOT NULL,
    input_signature TEXT NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    claimed_at TEXT,
    completed_at TEXT,
    PRIMARY KEY (record_id, stage, target),
    FOREIGN KEY (record_id) REFERENCES oai_record(id)
);

CREATE INDEX IF NOT EXISTS idx_record_processing_ready
    ON record_processing(stage, target, state, operation);
```

Valores:

| Columna | Valores |
|---|---|
| `stage` | `VALIDATION`, `INDEX` |
| `target` | `validator`, `frontend`, `xoai`, `semantic`, u otro nombre de indexador estable |
| `operation` | `VALIDATE`, `UPSERT`, `DELETE`, `NONE` |
| `state` | `PENDING`, `PROCESSING`, `DONE`, `FAILED`, `SKIPPED` |

Para la primera iteración se puede omitir la fila `VALIDATION` y utilizar solo `oai_record.validation_state`; la tabla se vuelve imprescindible para `INDEX` por tener múltiples destinos.

### Firma de procesamiento

Usar SHA-256, no MD5, para firmas nuevas. Los hashes actuales de metadata pueden mantenerse porque identifican blobs ya almacenados; las firmas no son identidad pública y deben codificar inequívocamente sus componentes, por ejemplo JSON canónico.

#### Firma de validación

```text
SHA-256(canonical-json({
  originalMetadataHash,
  prevalidatorDefinitionHash,
  validatorDefinitionHash,
  primaryTransformerDefinitionHash,
  secondaryTransformerDefinitionHash,
  processingEngineVersion
}))
```

#### Firma de un destino de índice

```text
SHA-256(canonical-json({
  publishedMetadataHash,
  validationResult: VALID | INVALID | ABSENT,
  sourceState,
  targetName,
  targetSchemaName,
  indexTransformerDefinitionHash,
  contentFiltersByFieldName,
  indexedNetworkAttributes,
  indexerImplementationVersion
}))
```

El hash de configuración debe calcularse desde definiciones efectivas y ordenadas, nunca desde `toString()` de objetos Java ni desde valores no deterministas.

## Transiciones de harvesting

Al crear un snapshot incremental, se copia el catálogo completo. Inmediatamente después de copiarlo:

```sql
UPDATE oai_record
SET change_type = 'INHERITED',
    previous_metadata_hash = NULL,
    change_detected_at = NULL,
    validation_state = 'INHERITED';
```

Las filas de `record_processing` se copian como histórico de estado `DONE`; el nuevo snapshot debe crear solo las filas `PENDING` que correspondan a nuevos cambios o a firmas incompatibles.

### Matriz de decisión por evento OAI-PMH

| Estado anterior | Evento recibido | Hash nuevo | Resultado |
|---|---|---|---|
| inexistente | metadata | cualquiera | `NEW`, `ACTIVE`, `ACCEPTED`, validación pendiente |
| `ACTIVE` + aceptado | metadata | igual | conservar `INHERITED`; no reprocesar |
| `ACTIVE` + aceptado | metadata | distinto | `UPDATED`, guardar hash anterior, validación pendiente |
| `DELETED` | metadata | cualquiera | `RESTORED`, `ACTIVE`, validación pendiente |
| `REJECTED` | metadata que pasa prevalidación | cualquiera | `RESTORED`, `ACTIVE`, validación pendiente |
| activo | cabecera `deleted` | n/a | `DELETED`, `DELETED`, validación omitida, `DELETE` pendiente en índices |
| activo | metadata que no pasa prevalidación | n/a | `UPDATED`, `ACTIVE`, `REJECTED`, validación omitida, `DELETE` pendiente en índices |
| eliminado | cabecera `deleted` | n/a | sin operación adicional; se conserva `DELETED` |

### Tratamiento del prevalidador

El prevalidador debe ejecutarse antes de decidir si se guarda la metadata como actual. Pero un rechazo no puede equivaler a “no hacer nada”: si el registro existía en el snapshot copiado, la versión heredada debe dejar de ser publicable.

Regla propuesta:

```text
metadata recibida + prevalidación fallida
  => source_state=ACTIVE
  => harvest_acceptance=REJECTED
  => change_type=UPDATED (o NEW si no existía)
  => validation_state=SKIPPED
  => operaciones INDEX/DELETE pendientes para todos los destinos donde pudo existir
```

La metadata cruda puede almacenarse para trazabilidad, pero no debe ser consumida por validation ni por indexación. El producto debe decidir si conserva el hash crudo en `original_metadata_hash`; se recomienda conservarlo para depuración y utilizar `harvest_acceptance` como filtro.

### Reemplazar `INSERT OR REPLACE`

`INSERT OR REPLACE` no permite calcular transiciones de forma segura, porque puede borrar/recrear la fila y porque no devuelve el estado previo. Reemplazarlo por una de estas alternativas:

1. Leer las filas existentes del lote por `id` antes de escribir, decidir en Java y ejecutar `INSERT ... ON CONFLICT(id) DO UPDATE`.
2. Usar `INSERT ... ON CONFLICT(id) DO UPDATE` con una cláusula `CASE` que calcule el cambio usando los valores antiguos y `excluded.*`.

Se recomienda la opción 1 para la primera implementación: es más fácil de probar, permite aplicar la misma decisión a metadata, `record_processing` y contadores, y el número de consultas sigue siendo acotado por lote.

Pseudocódigo:

```java
Map<String, CatalogRow> existing = repository.findByIds(snapshotId, incomingIds);
for (IncomingRecord incoming : batch) {
    CatalogRow previous = existing.get(incoming.id());
    Transition transition = transitionResolver.resolve(previous, incoming);
    repository.upsert(snapshotId, transition.toCatalogRow());
    transitionPlanner.planValidationAndIndex(snapshotId, transition);
}
```

Todos los cambios de catálogo y planificación del lote deben confirmarse en la misma transacción SQLite.

## Herencia de resultados de validación

### Estrategia recomendada

En un snapshot incremental, copiar `validation/validation.db` del snapshot anterior después de copiar el catálogo. La copia se acepta solo si la estructura y las firmas de validación son compatibles.

Después de copiar:

1. Eliminar de `record_validation` y `rule_occurrences` las filas de registros `DELETED` o `REJECTED`.
2. Eliminar las filas de `NEW`, `UPDATED` y `RESTORED` que tengan `validation_state='PENDING'`.
3. Conservar las filas de registros `INHERITED` cuya `validation_signature` coincida con la firma actual.
4. Si cambia la firma de validación global, invalidar todos los activos: marcar `validation_state='PENDING'`, recrear `validation.db` y procesar el snapshot completo.

Esta estrategia conserva las columnas dinámicas de reglas solo si sus definiciones siguen siendo compatibles. Si cambian las reglas, columnas o la política de diagnósticos, el fallback seguro es reconstruir `validation.db` completo.

### Firma incompatible

Una modificación de cualquiera de los siguientes elementos obliga a revalidación completa, salvo que en el futuro se implemente invalidación granular de reglas:

- prevalidador;
- validador y sus reglas;
- transformador primario;
- transformador secundario;
- versión de la lógica de validación/transformación;
- configuración que afecte a contenido transformado.

La opción administrativa “revalidar completo” debe producir exactamente el mismo efecto, sin necesidad de modificar metadata.

### Estadísticas

Las estadísticas agregadas actuales se acumulan al escribir `validation.db`. Tras heredar resultados hay dos alternativas:

1. Recalcular `SnapshotValidationStats` desde el `validation.db` final en `postRun()`.
2. Copiar y ajustar estadísticas previas restando registros invalidados y sumando registros reprocesados.

Se recomienda **recalcular desde el `validation.db` final** en la primera versión. Es más simple, evita errores con facetas y ocurrencias, y no obliga a conservar deltas de todas las métricas. La optimización posterior puede evaluarse con métricas reales.

## Planificación de indexación incremental

Cada indexador debe leer únicamente sus filas `record_processing` pendientes para `stage='INDEX'` y su `target`.

### Operaciones por transición

| Resultado final | Operación de índice |
|---|---|
| `NEW`/`UPDATED`/`RESTORED` y validación válida | `UPSERT` |
| `NEW`/`UPDATED`/`RESTORED` y validación inválida | `DELETE` si pudo haber existido un documento previo; en otro caso `NONE` |
| `DELETED` | `DELETE` |
| `REJECTED` | `DELETE` |
| `INHERITED` con firma de índice compatible | ninguna |
| `INHERITED` con firma de índice incompatible | `UPSERT` si es válido; `DELETE` si no lo es |

Para que `DELETE` sea idempotente, se debe usar el identificador estable que ya se utiliza para el fingerprint: `networkAcronym + '_' + identifierHash` o el campo de identidad definido por el indexador. No debe depender del `record_id` numérico generado por snapshot, porque este cambia en cada snapshot.

### Borrado y actualización en el mismo lote

El worker debe ejecutar en orden:

1. enviar `DELETE` de tombstones, rechazados y registros que pasaron de válidos a inválidos;
2. enviar `UPSERT` de registros válidos;
3. hacer commit en Solr;
4. marcar las filas correspondientes como `DONE` en SQLite.

Si falla antes del commit, las filas permanecen `PENDING` o vuelven desde `PROCESSING` a `PENDING`. Repetir el lote debe ser seguro.

### Índices que publican borrados

`indexDeletedRecords=true` es una excepción funcional: en lugar de eliminar un registro `DELETED`, el plan para ese destino puede ser `UPSERT` de un tombstone con `deleted=true`. Esta decisión pertenece al planificador por destino, no al harvesting.

## Estados de snapshot

Agregar o normalizar estados explícitos para observar el pipeline. Posible secuencia:

```text
INITIALIZED
  -> HARVESTING
  -> HARVESTING_FINISHED_VALID
  -> VALIDATING
  -> VALID
  -> INDEXING (por destino, si se desea mantener un estado agregado)
  -> INDEXED
```

Para el caso sin delta material:

```text
EMPTY_INCREMENTAL
```

Un snapshot debe poder declararse `EMPTY_INCREMENTAL` solo cuando:

- no existen `NEW`, `UPDATED`, `DELETED` ni `RESTORED`;
- las firmas de validación son compatibles;
- todos los destinos de indexación tienen firma compatible;
- no se solicitó una ejecución full/reprocesamiento administrativo.

Si no hay cambios OAI pero cambió la configuración de validación o indexación, **no** es `EMPTY_INCREMENTAL`: debe generar el trabajo correspondiente.

## API, operación y observabilidad

### Resumen de snapshot

Exponer, al menos en API v5 y logs, los siguientes contadores:

```json
{
  "inherited": 104230,
  "new": 14,
  "updated": 27,
  "deleted": 3,
  "restored": 1,
  "rejectedByPrevalidation": 2,
  "validationPending": 42,
  "validated": 42,
  "indexOperations": {
    "frontend": { "upsert": 39, "delete": 5, "failed": 0 },
    "xoai": { "upsert": 41, "delete": 3, "failed": 0 }
  }
}
```

### Diagnóstico por registro

Las consultas de diagnóstico deben poder devolver:

- estado y cambio del catálogo;
- hash actual y hash previo, cuando exista;
- firma de validación e índice aplicable;
- último error y número de intentos por etapa/destino;
- operación de índice planificada y completada.

No es necesario exponer hashes completos en la UI general; puede bastar con prefijos, pero la API de soporte debe poder acceder al valor completo.

### Operaciones administrativas

Agregar o preservar comandos claros:

- `FORCE_FULL_HARVESTING`: no hereda catálogo y planifica validación/indexación completa.
- `FORCE_REVALIDATION`: mantiene catálogo, pero invalida resultados de validación y trabajos de índice derivados.
- `FORCE_REINDEX[target]`: mantiene harvesting/validación y recalcula solo el plan del destino solicitado.
- `RETRY_FAILED_PROCESSING[target]`: libera filas `FAILED` para el destino, sin volver a cosechar.

Cada operación debe quedar registrada en el log de snapshot y en el contexto de ejecución.

## Cambios de implementación propuestos

### Fase 0: pruebas de caracterización

Antes de modificar comportamiento, agregar pruebas que documenten el presente y los casos objetivo:

- copia de catálogo incremental;
- alta, cambio, borrado y restauración;
- registro modificado que no pasa prevalidación;
- snapshot sin cambios;
- fallo a mitad de validación;
- fallo a mitad de índice y reintento;
- cambio de configuración de validador;
- cambio de configuración de un solo indexador.

### Fase 1: catálogo consciente de cambios

1. Crear enums Java: `SourceState`, `HarvestAcceptance`, `RecordChangeType`, `ValidationProcessingState`, `ProcessingStage`, `ProcessingOperation`, `ProcessingState`.
2. Ampliar `CatalogDatabaseManager.CREATE_SCHEMA_SQL` para nuevas instalaciones.
3. Añadir migración de esquema SQLite para catálogos existentes. La migración debe ser idempotente y ejecutarse al abrir/copiar una base con versión anterior.
4. Añadir `CatalogSchemaVersion` o `PRAGMA user_version` para versionar `catalog.db`.
5. Reemplazar `INSERT OR REPLACE` por upsert consciente del estado previo.
6. Incorporar un `RecordTransitionResolver` puro y cubierto por pruebas unitarias.
7. Registrar contadores del delta en `NetworkSnapshot` o en una tabla de resumen específica; no calcularlos solo desde logs.

### Fase 2: herencia e invalidación de validación

1. Añadir firma de validación al snapshot y a los registros del catálogo.
2. Versionar también `validation.db` con `PRAGMA user_version`.
3. Copiar el `validation.db` del snapshot anterior solo cuando sea compatible.
4. Añadir operaciones de eliminación selectiva y upsert a `RecordValidationRepository`.
5. Reemplazar el iterador de `ValidationWorker` por un paginator/stream de registros `PENDING`.
6. Asegurar que un `stop()` o una excepción no ejecuten `postRun()` como éxito ni marquen el snapshot como válido.
7. Recalcular estadísticas finales desde el `validation.db` resultante.

### Fase 3: plan de índice por destino

1. Crear `record_processing` y `IndexOperationPlanner`.
2. Derivar operaciones tras cada resultado de validación y para tombstones/rechazos.
3. Añadir a `IndexerWorker` un modo incremental que consume operaciones de su destino.
4. Conservar temporalmente el modo de reindexación completa detrás de una opción de acción para rollback operativo.
5. Marcar `DONE` solo tras commit exitoso de Solr.
6. Añadir recuperación de filas abandonadas en `PROCESSING` según timeout configurable.

### Fase 4: API y transición operativa

1. Publicar contadores y estados en API v5.
2. Añadir visualización de delta por snapshot en la administración.
3. Documentar los nuevos comandos administrativos.
4. Ejecutar un periodo de comparación: para un conjunto de fuentes, contrastar conteos y contenido de índices incremental vs full.
5. Activar incremental de índice gradualmente por destino/fuente mediante configuración.

## Compatibilidad y migración

### Bases SQLite existentes

Los catálogos y bases de validación viven en filesystem por snapshot y no están gestionados por Flyway. Por eso requieren versionado interno y migración al abrirlas.

Reglas:

1. Nunca alterar una base histórica en modo lectura sin una copia de seguridad o estrategia explícita.
2. Para el último snapshot válido que vaya a servir como base incremental, aplicar una migración SQLite transaccional antes de copiarlo.
3. Si no se puede migrar el catálogo o `validation.db`, hacer fallback seguro a full harvesting/validation/indexing y registrar el motivo.
4. No borrar los archivos `.db`, `-wal` ni `-shm` del snapshot anterior durante migración.

### PostgreSQL

Solo se requiere una migración Flyway si se agregan contadores de delta, firmas de snapshot o estados agregados a `networksnapshot`. Los datos por registro y por destino deben permanecer en SQLite para mantener aislamiento y evitar inflar PostgreSQL.

### Rollback

La configuración debe permitir volver temporalmente a:

```properties
incremental.record-processing.enabled=false
```

Con el flag apagado, el sistema mantiene el nuevo catálogo si existe, pero ejecuta validación e indexación completas como hoy. Esto permite revertir el comportamiento sin perder snapshots ni necesitar una migración inversa de SQLite.

## Concurrencia, errores y recuperación

### Exclusión por fuente

El `TaskManager` actualmente serializa workers por `NetworkRunningContext`. La propuesta depende de esa exclusión, pero no debe asumir que un proceso siempre termina limpiamente.

### Claim de trabajo

El claim de una fila pendiente debe ser atómico. Ejemplo conceptual:

```sql
UPDATE record_processing
SET state = 'PROCESSING',
    claimed_at = :now,
    attempt_count = attempt_count + 1
WHERE rowid IN (
    SELECT rowid
    FROM record_processing
    WHERE stage = :stage
      AND target = :target
      AND state = 'PENDING'
    LIMIT :batchSize
)
AND state = 'PENDING';
```

Tras reclamar se releen las filas reclamadas por `claimed_at`/token de ejecución. Para una primera versión, ya que solo hay un worker por fuente, se puede usar una transacción SQLite local y un `run_id`; el esquema debe dejar espacio para extenderlo.

### Trabajo abandonado

Al iniciar un worker, filas `PROCESSING` cuyo `claimed_at` exceda `processing.claim-timeout` se devuelven a `PENDING` y se registra un evento de recuperación. No se deben reintentar automáticamente errores de configuración deterministas; esos se marcan `FAILED` con un mensaje accionable.

### Completitud del snapshot

Un snapshot no debe promocionarse como último snapshot válido para indexación hasta que:

- harvesting haya terminado correctamente;
- validation no tenga filas `PENDING`, `PROCESSING` o `FAILED` requeridas;
- el destino mínimo configurado haya completado sus operaciones, si la política de la instalación así lo requiere.

La política exacta para destinos opcionales debe quedar parametrizada. Por ejemplo, puede permitirse que falle el índice semántico sin bloquear frontend, pero el estado debe hacerlo visible.

## Casos de prueba y aceptación

### Pruebas unitarias

- `RecordTransitionResolver` para todas las filas de la matriz de transiciones.
- Cálculo determinista de firmas, independiente del orden de mapas/reglas.
- Planificador de operaciones de índice para todas las transiciones de validez.
- Rechazo de prevalidador para registro nuevo y para registro heredado.

### Pruebas de integración de catálogo

- Crear snapshot A full con N registros, copiarlo a B incremental y verificar `INHERITED`.
- Aplicar `NEW`, `UPDATED`, `DELETED`, `RESTORED` y comprobar columnas, conteos e índices SQLite.
- Reabrir bases versionadas y verificar que la migración no se repite ni modifica valores ya migrados.
- Simular fallo entre upsert de catálogo y planificación; la transacción no debe dejar estado parcial.

### Pruebas de validación

- Copiar `validation.db`; validar solo un conjunto PENDING y conservar filas heredadas.
- Cambio de firma de validación: todos los activos pasan a PENDING y se reconstruye el resultado.
- Registro actualizado válido -> inválido: se conserva diagnóstico nuevo y se planifica DELETE.
- Registro actualizado inválido -> válido: se planifica UPSERT.
- Stop/error durante el worker: no se llama a finalización exitosa ni se marca el snapshot como válido.

### Pruebas de indexación

- Un delta con 1 `UPSERT` y 1 `DELETE` no borra otros documentos de la fuente.
- Reejecutar un lote ya confirmado no cambia el resultado final.
- Fallar antes de commit: operaciones quedan reintentables.
- `indexDeletedRecords=true` publica tombstone en vez de DELETE.
- Dos targets: completar frontend no marca XOAI como completado.

### Criterios de aceptación funcionales

- [ ] Una cosecha incremental sin cambios OAI ni cambios de configuración no ejecuta validation ni indexación y deja el snapshot en `EMPTY_INCREMENTAL`.
- [ ] Un registro nuevo válido genera una sola validación y un `UPSERT` por destino habilitado.
- [ ] Un registro modificado válido genera una sola validación y un `UPSERT`, sin reindexar registros heredados.
- [ ] Un registro eliminado en OAI-PMH genera un `DELETE` por destino que no indexa borrados.
- [ ] Un registro actualizado que deja de pasar prevalidación elimina la versión anterior de los índices.
- [ ] Un registro que pasa de inválido a válido vuelve a aparecer mediante `UPSERT`.
- [ ] Cambiar el validador o un transformador fuerza revalidación completa de los registros activos.
- [ ] Cambiar solo la configuración de frontend fuerza reproceso solo para frontend, no para XOAI ni validación.
- [ ] Un fallo de validation o indexing no marca el trabajo afectado como completado y se puede reintentar.
- [ ] El resultado de una ejecución incremental es equivalente al de una ejecución full con los mismos datos y configuración.

### Criterios de aceptación no funcionales

- [ ] Las consultas de selección tienen índices SQLite y no cargan el catálogo completo en memoria.
- [ ] Los lotes de operación son configurables.
- [ ] Los logs incluyen `snapshotId`, fuente, tipo de cambio, etapa, target y operación.
- [ ] Las migraciones de SQLite son idempotentes y seguras ante una segunda apertura.
- [ ] Existe métrica de registros procesados/omitidos y duración por etapa.
- [ ] El modo full actual puede activarse como fallback durante el despliegue.

## Decisiones que deben confirmarse antes de implementar

1. **Snapshot vacío:** ¿se debe crear un nuevo snapshot `EMPTY_INCREMENTAL` como hoy, o reutilizar el anterior? Esta propuesta conserva la creación para mantener trazabilidad.
2. **Prevalidación rechazada:** ¿debe conservarse el XML crudo para auditoría? Se recomienda sí, pero no publicarlo ni validarlo.
3. **Promoción de snapshot:** ¿un fallo en un índice opcional bloquea que el snapshot sea último válido para frontend/OAI? Se requiere una política explícita por destino.
4. **Cambio de reglas:** primera versión invalida todo el `validation.db`; la invalidación por regla individual queda fuera de alcance.
5. **Identidad de documento:** confirmar que todos los indexadores soportan borrado por fingerprint estable `network + identifierHash` y no por ID numérico del snapshot.
6. **Tamaño de copia:** validar si copiar `validation.db` aporta ahorro suficiente frente al coste de copiar dos SQLite. Para redes pequeñas puede mantenerse el full como opción preferida.

## Métricas para medir el beneficio

Registrar por fuente y snapshot:

- total activo heredado;
- cantidad de altas, cambios, bajas, restauraciones y rechazos;
- registros validados e indexados realmente;
- deletes/upserts por destino;
- tiempo y tamaño de catálogo/validation DB copiados;
- duración de harvesting, validation e indexing;
- equivalencia de conteos entre incremental y full durante el rollout.

El criterio de éxito inicial no es solo reducir tiempo: es demostrar que el conjunto final por cada destino coincide con una reconstrucción completa de referencia.

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Estado inconsistente entre catálogo, validation.db y Solr | Plan persistente por etapa/destino, operaciones idempotentes y confirmación después de commit |
| Cambio de reglas con resultados heredados obsoletos | Firmas de configuración y fallback a revalidación completa |
| Prevalidación oculta una actualización | Persistir `REJECTED` y planificar DELETE |
| Migrar SQLite histórico es complejo | Versionado interno, migración al abrir y fallback a full |
| Borrado por identificador no uniforme entre índices | Definir y probar identidad estable por target antes de activar incremental |
| Incremental más complejo que full para redes pequeñas | Flag de rollout y modo full disponible |
| Workers se detienen pero finalizan como éxito | Corregir contrato de `BaseIteratorWorker` antes de confiar en estados incrementales |

## Entregables

1. Migración/versionado de `catalog.db` y, cuando corresponda, `validation.db`.
2. Enums, modelos y repositorios para transiciones y procesamiento por destino.
3. `RecordTransitionResolver`, firmas de configuración y planificador de indexación.
4. Workers actualizados con modo incremental y fallback full.
5. API/diagnóstico con contadores de delta y estado por etapa/destino.
6. Suite de pruebas unitarias e integración descrita arriba.
7. Guía de rollout y rollback operativo.

## Definition of Done

El issue se considera terminado cuando los criterios de aceptación se cumplen, el modo incremental está habilitado para al menos un destino de índice controlado, se ha comparado contra ejecuciones full en fuentes representativas y existe un mecanismo operativo probado para volver temporalmente a procesamiento completo.
