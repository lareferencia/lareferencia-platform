# Plan de implementación para operaciones manuales dARK

## Propósito y alcance

Este documento define la implementación acordada para las issues:

- [#74 — Reenvío y actualización explícita de ARKs](https://github.com/lareferencia/lareferencia-platform/issues/74)
- [#75 — Construcción de L1/L2 y selección de URL](https://github.com/lareferencia/lareferencia-platform/issues/75)
- [#76 — Logging y estado visible de workers](https://github.com/lareferencia/lareferencia-platform/issues/76)
- [#77 — Clasificación y recuperación de errores](https://github.com/lareferencia/lareferencia-platform/issues/77)
- [#78 — API dARK operacional en Harvester API v5](https://github.com/lareferencia/lareferencia-platform/issues/78)

La primera versión incluye selección explícita de hasta 100 registros, preview
síncrono opcional, envío/actualización inteligente, reconciliación manual y progreso
efímero sobre el runtime legacy.

Quedan fuera de alcance:

- operaciones por filtro;
- reserva manual de ARKs nuevos;
- tablas o historial de operaciones;
- edición manual de L1/L2 u omisión de L2 como fallback;

## Baseline comprobado

### API, UI y tracking

`ApiV5DarkController` expone consultas y los cuatro endpoints operacionales bajo
`/api/v5/dark`. La selección se recibe como OAI IDs, se valida contra el NAAN y,
para preview y stage, usa la red y el snapshot exactos registrados como
procedencia de cada payload.

El frontend está implementado en `lareferencia-lrharvester-admin-web`. Su
`DarkPage.tsx` navega por NAAN, muestra red/snapshot de procedencia y permite las
operaciones manuales a usuarios `ADMIN`.

`DarkTrackingRecord` es la persistencia vigente. No se añaden tablas de operaciones
ni historial durable. Se amplía la tabla existente con procedencia del payload:

- `source_network_id`, nullable;
- `source_snapshot_id`, nullable.

`source_metadata_hash` ya identifica la metadata concreta. Los tres valores
describen la procedencia vigente del payload, no un historial de envíos.

```text
RESERVED (R)
DRAFT (D)
UPDATE (U)
PUBLISHED (P)
TOMBSTONE (T)
ERROR (E)
```

`lastError` continuará almacenando el último diagnóstico del registro.

### Workers y minter

`DarkStageWorker` reserva cuando no existe un ARK, reutiliza uno existente y omite
payloads sin cambios. Su flujo automático no fuerza actualmente un nuevo `PUT` para
`PUBLISHED`.

`DarkReconcileWorker` consulta el minter para ARKs en `RESERVED`, `DRAFT`, `UPDATE`
o `ERROR` y actualiza el tracking local.

El contrato del minter admite:

```text
RESERVED -> DRAFT     mediante PUT /api/v1/arks/{ark}
DRAFT -> PUBLISHED    mediante workers del minter
PUBLISHED -> UPDATE   mediante PUT /api/v1/arks/{ark}
UPDATE -> PUBLISHED   mediante workers del minter
```

Un ARK en `DRAFT` o `UPDATE` ya tiene trabajo pendiente y no debe recibir otro
envío manual hasta reconciliarse.

`TaskManager` mantiene workers, colas y serial lanes en memoria. Los procesos
terminados se eliminan del runtime; por tanto, el seguimiento manual no será
durable y se implementará solo para el motor legacy.

### Metadata

La preparación actual carga el XML original, transforma L2, selecciona una URL,
construye L1 y calcula el hash del payload.

L1 requiere actualmente título, autor y año. El autor se obtiene de `dc.creator`,
con fallback a `dc.contributor.author`.

La prioridad acordada es `DOI > primera URL normal > Handle`. La implementación
actual sigue ese orden para `https://doi.org/`, pero todavía no reconoce todas las
variantes HTTP(S) de DOI; el detalle queda registrado en el estado de la issue #75.

## Diseño de implementación

### Ámbito NAAN y procedencia de red

El NAAN es el ámbito operativo y agrupa los ARKs. Una red tiene un solo NAAN,
pero varias redes pueden compartirlo. La red no define el grupo operativo: indica
de dónde cargar la metadata de un registro.

Cada fila de tracking conserva `sourceNetworkId` y `sourceSnapshotId`. Los workers
automáticos actualizan esta procedencia al reservar o preparar correctamente el
registro. Reconcile no cambia la procedencia.

Para registros históricos sin procedencia:

- reconcile permanece habilitado porque sólo requiere ARK y minter;
- preview y stage devuelven `SOURCE_NETWORK_MISSING`;
- preview y stage se rechazan explícitamente; no infieren una red ni sustituyen
  el snapshot de procedencia por el último snapshot disponible.

### Envío/actualización inteligente

La UI presenta una única acción `Enviar/actualizar`; la transición se decide a
partir del estado remoto.

El worker manual requiere un ARK existente, consulta su estado remoto justo antes
del efecto y aplica esta tabla:

| Estado remoto | Comportamiento |
|---|---|
| `RESERVED` | Ejecutar `PUT`; debe pasar a `DRAFT`. |
| `PUBLISHED` | Ejecutar `PUT`; debe pasar a `UPDATE`. |
| `DRAFT` | Omitir con `PENDING_RECONCILIATION`. |
| `UPDATE` | Omitir con `PENDING_RECONCILIATION`. |
| `TOMBSTONE` | Fallar con `ARK_TOMBSTONED`. |
| Inexistente | Fallar con `ARK_NOT_FOUND`. |

Para tracking local `ERROR`, el estado remoto determina el comportamiento. La
acción manual nunca reserva otro ARK.

La UI habilita el envío únicamente para estados locales `RESERVED`, `PUBLISHED` y
`ERROR`. Lo deshabilita para `DRAFT` y `UPDATE`, indicando que debe reconciliarse
primero, y para `TOMBSTONE` o registros sin ARK.

No se añade un bloqueo por NAAN o registro. El minter mantiene la autoridad final
sobre identidad, autorización del NAAN y transiciones concurrentes.

### Reconciliación manual

`Reconciliar` acepta entre 1 y 100 registros con ARK. Agrupa la consulta por página
y usa `POST /api/v1/arks/status/batch` (máximo 100 ARKs), conserva el orden de
respuesta, actualiza cada fila y aísla errores permanentes por ARK. Un error
transitorio o una respuesta batch inválida detiene la página para permitir el
reintento. Al finalizar, la UI refresca registros y resumen y vuelve a evaluar las
acciones habilitadas.

### Política de metadata y URL

El envío requiere:

- `dc.title` no vacío;
- autor desde `dc.creator` o `dc.contributor.author`;
- año parseable desde `dc.date.issued`, `dc.date.created` o `dc.date`;
- URL target válida;
- L2 transformable y serializable.

La ausencia o invalidez falla solo ese registro. No se inventan valores, no se
aplican placeholders y no se envía L1 parcial.

La selección de URL es determinista:

1. primera URL HTTP(S) DOI;
2. primera URL HTTP(S) que no sea DOI ni Handle, respetando el orden en
   `dc.identifier` y sus variantes;
3. primera URL HTTP(S) Handle.

Si no existe candidata, usar `TARGET_URL_MISSING`. Ante `413`, guardar tamaños y
`PAYLOAD_TOO_LARGE`: no omitir L2, truncar metadata ni reintentar degradando el
payload.

### Errores en `lastError`

Los errores nuevos se guardan como JSON compacto y versionado dentro de la columna
existente, respetando su límite:

```json
{
  "version": 1,
  "category": "VALIDATION",
  "code": "L1_TITLE_MISSING",
  "phase": "BUILD_L1",
  "httpStatus": null,
  "retryable": false,
  "message": "Missing dc.title",
  "details": {
    "l1Bytes": null,
    "l2Bytes": null,
    "payloadBytes": null
  }
}
```

Categorías:

| Categoría | Casos | Tratamiento |
|---|---|---|
| `VALIDATION` | metadata o URL inválida | Error individual no reintentable. |
| `CONFLICT` | `409` o estado pendiente | No reintentar a ciegas. |
| `PAYLOAD_TOO_LARGE` | `413` | Error individual con tamaños. |
| `AUTHORIZATION` | `401` o `403` | Error sistémico; detener lote. |
| `RATE_LIMIT` | `429` | Retry/backoff del cliente. |
| `REMOTE_TRANSIENT` | `5xx`, timeout o I/O | Retry limitado; luego error individual. |
| `REMOTE_PERMANENT` | otros `4xx` | Error individual no reintentable. |
| `INTERNAL` | configuración, persistencia o invariantes | Error sistémico. |

El DTO actual conserva `lastError`. La persistencia ya usa JSON versionado para los
errores nuevos, pero aún falta exponer un campo `error` estructurado y normalizar
explícitamente el texto histórico en la respuesta API. Si el contenido histórico
no es JSON válido, devolver:

```json
{
  "version": 0,
  "category": "LEGACY",
  "code": "LEGACY_ERROR",
  "retryable": false,
  "message": "<texto existente>"
}
```

Stage o reconcile exitoso limpia `lastError`. El preview no escribe ni limpia el
tracking.

### Runtime manual legacy

Los workers prototype de stage y reconcile manual ya están creados. Su contexto contiene:

- `commandId` UUID;
- red y NAAN;
- acción y usuario autenticado;
- OAI IDs seleccionados;
- total inicial.

Usar las serial lanes dARK existentes. La admisión debe devolver explícitamente
`RUNNING`, `QUEUED` o `REJECTED`; una cola llena no puede aceptarse en silencio.

Mantener durante una hora, configurable mediante
`dark.manual.command-retention-hours`, un registro exclusivamente en memoria con:

- estado `QUEUED`, `RUNNING`, `SUCCEEDED`, `PARTIAL` o `FAILED`;
- fase actual y OAI ID actual;
- `processed`, `total`, `succeeded`, `skipped` y `failed`;
- timestamps y error sistémico final.

Después de reiniciar o expirar, el comando desaparece. Los resultados ya terminados
permanecen en tracking; el operador refresca y relanza la selección necesaria.

Procesar elementos válidos aunque otros fallen. Solo autorización, configuración,
persistencia o invariantes detienen el lote. El estado final es:

- `SUCCEEDED`: sin errores, aunque existan omisiones esperadas;
- `PARTIAL`: mezcla de éxitos/omisiones y errores individuales;
- `FAILED`: error sistémico o todos los elementos fallidos.

Registrar en `INFO` solo inicio y resumen final con `commandId`, usuario, red, NAAN,
acción y conteos. Página y registro quedan en `DEBUG`; nunca registrar payloads o
credenciales.

## Migración de base de datos

La modificación del tracking debe incluir una migración Flyway en
`lareferencia-shell/src/main/resources/db/migration`:

```text
V5.0.0.10__Dark_Tracking_Provenance.sql
```

La migración añade de forma nullable `source_network_id` y `source_snapshot_id` a
`public.dark_tracking_record`. Debe ser compatible con instalaciones existentes:
no borra ni reconstruye la tabla, no modifica la clave primaria y deja los
registros históricos con procedencia nula. La entidad JPA y los DTO deben usar los
mismos nombres y nulabilidad.

## Contrato API v5

Preview, stage y reconcile requieren `ADMIN`. El minter valida además el
`authorityId` configurado y su autorización sobre el NAAN.

```text
POST /api/v5/dark/naans/{arkNaan}/preview
POST /api/v5/dark/naans/{arkNaan}/stage
POST /api/v5/dark/naans/{arkNaan}/reconcile
GET  /api/v5/dark/commands/{commandId}
```

Los tres `POST` reciben:

```json
{
  "oaiIds": ["oai:repository:1", "oai:repository:2"]
}
```

Reglas comunes:

- entre 1 y 100 valores no vacíos y únicos;
- todos los registros deben pertenecer al NAAN indicado;
- preview y stage requieren procedencia de red resoluble;
- reconcile requiere ARK y no depende de snapshot o red.

`preview` responde `200`, no consulta el minter y no escribe tracking. Valida
existencia en el snapshot de la red, ARK, metadata, URL, L1, L2 y tamaños y
devuelve por registro:

```text
oaiId, ark, eligible, localState, targetUrl,
l1Bytes, l2Bytes, payloadBytes, warnings, error
```

`stage` y `reconcile` responden `202`. La admisión valida que todos los OAI
pertenezcan al NAAN. Preview y stage resuelven para cada registro su propia red y
snapshot de procedencia, por lo que un lote puede contener registros de distintas
redes que compartan el mismo NAAN:

```json
{
  "commandId": "uuid",
  "status": "QUEUED",
  "action": "STAGE",
  "total": 2,
  "statusUrl": "/api/v5/dark/commands/uuid"
}
```

`GET /commands/{commandId}` puede ser consultado por `VIEWER` o `ADMIN`. Devuelve
el progreso efímero. Si el comando expiró o Harvester reinició, responde
`404 DARK_COMMAND_NOT_FOUND`.

## Interfaz administrativa

La pantalla dARK implementa:

- usar el NAAN como ámbito de navegación y selección;
- mostrar la red de procedencia por registro;
- seleccionar mediante checkboxes y limitar la selección a 100;
- mostrar cantidad seleccionada;
- ofrecer a `ADMIN` `Previsualizar`, `Enviar/actualizar` y `Reconciliar`;
- conservar para `VIEWER` una interfaz de consulta sin escrituras;
- explicar acciones deshabilitadas;
- confirmar stage mostrando NAAN y cantidad; la tabla hace visible la red y el
  snapshot de procedencia de cada fila;
- impedir dobles clics mientras se acepta la petición;
- mostrar fase y conteos del comando;
- refrescar summary y records al terminar o perderse el comando;
- mostrar errores estructurados y texto legacy.

El preview es opcional. El worker repite validaciones y consulta el estado remoto
antes del `PUT`. Si se pierde el comando por reinicio, la UI lo informa, refresca el
tracking y permite relanzar la selección.

## Implementación realizada

- `V5.0.0.10__Dark_Tracking_Provenance.sql` añade los campos nullable de
  procedencia sin alterar registros históricos.
- Los workers automáticos persisten red/snapshot cuando crean o actualizan un
  payload. Stage y preview manuales consumen ese snapshot exacto.
- Las acciones se reciben por NAAN y se dividen internamente por la pareja
  `(sourceNetworkId, sourceSnapshotId)`. Si la selección viene de una sola red
  y snapshot, se ejecuta un solo worker con paginación filtrada a esos OAI IDs.
- La UI limita a 100 y a un NAAN, muestra preview, confirmación, progreso por
  polling y refresco final. `VIEWER` conserva la vista de consulta.
- La reconciliación automática y manual consulta el endpoint batch del minter en
  páginas de hasta 100 ARKs.
- El estado del runtime legacy combina nombre del worker y `getStatus()`. Los
  workers paginados reportan página y porcentaje; reconcile dARK añade procesados,
  total inicial y contadores de resultado.

Antes de desplegar queda ejecutar la migración y una prueba integrada contra un
minter de prueba.

## Estado de las issues

Estado revisado el 2026-09-24 contra el código de `main` y los commits publicados
en `core-lib`, `dark-lib`, `lrharvester-app` y `lrharvester-admin-web`. “Hecho”
describe comportamiento encontrado en código; “pendiente” son brechas respecto
del contrato acordado y deben cerrarse antes de considerar completa la issue.

### #74 — Reenvío y actualización explícita de ARKs

**Hecho**

- La UI ofrece una acción `Enviar / actualizar` para registros seleccionados con
  estado local `RESERVED`, `PUBLISHED` o `ERROR` y ARK existente.
- Stage manual consulta el estado remoto justo antes del `PUT`: continúa para
  `RESERVED` y `PUBLISHED`, omite `DRAFT` y `UPDATE` para reconciliación, y registra
  error para `TOMBSTONE`. No reserva un ARK desde la acción manual.
- La respuesta remota actualiza tracking y la UI refresca el resumen y los
  registros al terminar.

**Pendiente**

- Completar pruebas de contrato del worker para cada transición y para ARK
  inexistente, incluida la conservación del ARK existente ante todos los errores.
- Ejecutar una prueba integrada contra un minter de prueba para validar las
  transiciones reales `RESERVED -> DRAFT` y `PUBLISHED -> UPDATE`.

### #75 — Construcción de L1/L2 y selección de URL

**Hecho**

- L1 exige título, autor (`dc.creator` con fallback a
  `dc.contributor.author`) y año parseable. L2 se transforma antes del envío.
- Preview muestra URL y tamaños de L1/L2/payload. Los errores de validación se
  aíslan por registro.
- Un `413` queda clasificado como `PAYLOAD_TOO_LARGE`; no hay fallback que quite
  L2 ni que trunque el payload.

**Pendiente**

- Ampliar la detección DOI para reconocer URL HTTP(S) DOI válidas además de
  `https://doi.org/`; por ejemplo `http://doi.org/` y `https://dx.doi.org/`.
- Guardar en `lastError.details` los tamaños de L1, L2 y payload cuando el minter
  responde `413`. Hoy el codec recibe el error sin esos detalles.
- Emitir el código acordado `TARGET_URL_MISSING` cuando no hay URL candidata; hoy
  el worker registra una `IllegalStateException` genérica.
- Añadir pruebas para variantes DOI y comprobar tamaños persistidos en el caso
  `413`.

### #76 — Logging y estado visible de workers

**Hecho**

- El tooltip legacy combina `worker.getName()` con `worker.getStatus()` y evita la
  representación `Clase@hash` de `Object.toString()`.
- Los workers batch y Solr reportan página actual/total y porcentaje. Los workers
  iteradores reportan registros procesados/total cuando conocen el total.
- Stage y reconcile dARK exponen fase y contadores; reconcile añade porcentaje
  respecto del total pendiente inicial. Harvesting informa registros cosechados,
  sin porcentaje cuando el protocolo no proporciona un total fiable.
- El progreso de comandos manuales sigue siendo efímero: al expirar o reiniciar
  Harvester se reconstruye la situación desde tracking.

**Pendiente**

- Añadir pruebas específicas de formato/valores para los estados base de batch,
  iterador y Solr, y para la descripción `nombre + status` del runtime.
- Verificar visualmente la pantalla de red con workers de distintas clases tras
  reconstruir y reiniciar el Harvester que incorpora `core-lib`.

### #77 — Clasificación y recuperación de errores

**Hecho**

- Los errores nuevos se guardan en `lastError` como JSON versionado con categoría,
  código, fase, estado HTTP, retryable, mensaje y `details`.
- El cliente minter reintenta errores marcados como reintentables. Stage y
  reconcile aíslan errores permanentes por registro y detienen el lote ante
  fallos sistémicos o transitorios que requieren reintento.
- La UI intenta interpretar el JSON nuevo y conserva texto que no es JSON para
  mostrar errores históricos.

**Pendiente**

- Añadir un campo `error` estructurado a la respuesta de records sin retirar
  `lastError` durante la transición.
- Normalizar errores históricos no JSON al contrato `version: 0`,
  `category: LEGACY`, `code: LEGACY_ERROR`, `retryable: false`, `message`.
- Incorporar tamaños al error `413` como se especifica en #75 y probar la
  clasificación/recuperación en API y UI, además de la persistencia en workers.

### #78 — API dARK operacional en Harvester API v5

**Hecho**

- Están implementados los endpoints `preview`, `stage`, `reconcile` y consulta de
  comando, con permisos `ADMIN` para operaciones y lectura de progreso para
  `VIEWER`/`ADMIN`.
- Stage y preview resuelven la red y snapshot de procedencia por registro; el
  NAAN es el ámbito de selección. La UI limita selección a 100 registros de un
  NAAN y presenta procedencia, preview, confirmación y progreso.
- Preview es síncrono, no consulta el minter ni modifica tracking. Stage/reconcile
  responden `202`; el progreso vive en memoria y puede expirar o perderse al
  reiniciar.

**Pendiente**

- Rechazar IDs OAI duplicados en API. Actualmente se deduplican silenciosamente,
  aunque el contrato requiere una selección única.
- Ampliar pruebas API para `reconcile`, permisos `VIEWER`/`ADMIN`, selección
  duplicada y límites de 1–100 elementos; actualmente las pruebas de contrato
  cubren `stage` y `preview`.
- Completar la prueba integrada de flujo contra minter y base de datos con la
  migración de procedencia aplicada.

## Plan de pruebas

### Unidad

- creator y fallback contributor.author;
- título, autor o año faltante y fecha inválida;
- L2 inválido y tamaños;
- prioridad DOI, URL normal y Handle;
- ausencia de URL;
- JSON de error y fallback legacy;
- conteos y estado final del comando.

### Worker y minter

- `RESERVED -> DRAFT` y `PUBLISHED -> UPDATE`;
- omisión de `DRAFT` y `UPDATE`;
- `TOMBSTONE`, ARK inexistente y tracking local `ERROR`;
- `409`, `413`, `429`, otros `4xx`, `5xx`, timeout e I/O;
- autoridad sin permiso sobre NAAN;
- lote parcial, error sistémico y cola llena;
- limpieza de `lastError` tras éxito.

### API y UI

- permisos `ADMIN` y `VIEWER`;
- selección vacía, duplicada o superior a 100;
- red inexistente, sin NAAN u OAI ajeno al NAAN;
- preview `200` sin escritura ni llamada remota;
- stage/reconcile `202` y progreso completo;
- comando expirado o perdido tras reinicio;
- selección, estados habilitados, confirmación y refresco;
- errores estructurados y legacy.

Cobertura existente relevante:

- `lareferencia-dark-lib` tiene pruebas para extracción de URL, metadatos L1,
  serialización de errores, cliente minter, stage y reconcile, entre otras áreas.
- `ApiV5DarkControllerTest` verifica actualmente los contratos básicos de `stage`
  y `preview`; no cubre todavía reconcile ni todas las reglas de selección.
- La compilación Maven de los módulos backend modificados se verificó después de
  los cambios de workers y reconciliación batch. Las brechas de pruebas quedan
  detalladas por issue arriba.

## Mapa técnico para el siguiente agente

Backend implementado en estos módulos y archivos principales:

- `lareferencia-dark-lib`: `DarkStageWorker`, `DarkReconcileWorker`,
  `DarkPreviewService`, `DarkErrorCodec`, `DarkManualRunningContext`,
  `DarkManualProgress`, `CatalogRecordPaginator` y
  `SelectedDarkTrackingPaginator`.
- `lareferencia-core-lib`: `TaskManager.launchWorkerWithResult`, que devuelve
  `RUNNING`, `QUEUED` o `REJECTED` y conserva compatibilidad con
  `launchWorker`.
- `lareferencia-lrharvester-app`: `ApiV5DarkController`,
  `ApiV5DarkService`, `ApiV5DarkDtos`, `DarkManualCommandLauncher` y
  `DarkManualCommandRegistry`.
- `lareferencia-shell`: contiene
  `V5.0.0.10__Dark_Tracking_Provenance.sql`, que debe ejecutarse antes de
  desplegar la entidad ampliada.
- Pruebas de contrato: `ApiV5DarkControllerTest`.

La UI usa `oaiIds`, envía el `arkNaan`, trata `202` como aceptación efímera y
consulta el comando hasta estado final. No persiste operaciones localmente.

## Criterios de aceptación

- Un `ADMIN` selecciona hasta 100 registros y puede previsualizar, reconciliar o
  enviar sin modificar directamente estados de tracking.
- La acción reutiliza el ARK existente y nunca reserva otro.
- El estado remoto decide si el `PUT` crea `DRAFT` o `UPDATE`.
- `DRAFT` y `UPDATE` requieren reconciliación antes de otro envío.
- Un error individual no impide procesar los demás registros.
- L1 exige título, autor y año; la URL sigue `DOI > primera URL normal > Handle`.
- Un `413` nunca omite automáticamente L2.
- La UI interpreta errores JSON nuevos y errores históricos de texto.
- El progreso muestra fase y conteos sin prometer historial durable.
- Tras reiniciar, el operador reconstruye la situación desde tracking y relanza.
- Los logs `INFO` contienen solo inicio y final; el detalle queda en `DEBUG`.
- El worker automático conserva su comportamiento funcional.
