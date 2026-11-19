# Admin-ui · Cosecha completa, cancelación y lotes

**19 de noviembre de 2026, rama coordinada `codex/rc5-pre`.** Desde el listado de fuentes en Chrome se ejecutaron cosechas OAI completas, se canceló una cosecha con trabajo pendiente en la misma red y se enviaron dos lotes consecutivos. El fallo principal estaba en la admisión parcial de un lote. Un rechazo podía ocultar que otra red ya se estaba procesando. La corrección se comprobó con el mismo motor y con una segunda ejecución desde redes nuevas. [Prueba reproducible](../testing/admin-ui/verificar_cosecha.py)

## Evidencia de la ejecución final

Se crearon desde el formulario de alta tres fuentes sin cron. Las filas de abajo corresponden a las redes A (`QA9ACB2AA`, ID 128), B (`QA9ACB2AB`, ID 129) y C (`QA9ACB2AC`, ID 130). El proveedor OAI local sirvió los cinco registros de prueba en tres páginas de 2, 2 y 1, con identificadores distintos para cada red. El operador eligió «Cosechar metadatos» en modo completo.

| Operación desde el admin | Ejecución terminal | Snapshot | Registros activos |
|---|---|---|---:|
| Cosecha individual de A | COMPLETED | 20 · HARVESTING_FINISHED_VALID | 5 |
| Cancelar C con la segunda página OAI en vuelo | CANCELLED | 21 · HARVESTING_STOPPED | 2 |
| Cancelar el segundo trabajo de C, ya admitido y en cola | CANCELLED · `startedAt=null`, `finishedAt` informado | C conservó únicamente el snapshot 21 | — |
| Lote de A y B · A admitida | COMPLETED | 22 · HARVESTING_FINISHED_VALID | 5 |
| Lote de A y B · B admitida | COMPLETED | 23 · HARVESTING_FINISHED_VALID | 5 |
| Segundo lote · A admitida | COMPLETED | 24 · HARVESTING_FINISHED_VALID | 5 |
| Segundo lote · B con la acción deshabilitada | REJECTED en su recibo hijo | B conservó únicamente el snapshot 23 | 5 anteriores |

**Cómo se verificó el estado final.** Las altas devolvieron 201 y los comandos 202. Para cada cosecha admitida, el script relaciona el `requestId` de su recibo con el `groupId` de `GET /api/v5/runtime/executions`, comprueba la red, la hora de finalización y el estado del worker. Para una cancelación se sigue el grupo de la cosecha original. En la red C se observó primero un worker RUNNING y otro QUEUED. Después de pulsar «Cancelar acciones» y confirmar, se liberó la respuesta HTTP que el proveedor retenía. C solicitó dos páginas y conservó solo los dos registros de la primera. El trabajo en cola terminó sin iniciar otra petición OAI.

Por cada snapshot nuevo se verificó la red, el estado y `endTime` mediante la API. La consulta directa a PostgreSQL sobre `networksnapshot` confirmó tamaños 5, 2, 5, 5 y 5 y fechas finales iguales o posteriores al inicio. En cada catálogo SQLite se comprobó `PRAGMA integrity_check`, el conjunto exacto de identificadores activos y la coincidencia con el tamaño de la API. Se abrió y analizó el XML comprimido correspondiente a cada hash de metadatos. El runtime de cada red terminó vacío. Tras recargar el admin, A y B mostraron «Cosecha terminada» y C «Detenida».

Para contrastar los recibos con una traza, el lote aceptado tuvo ID `125ac01d-b64c-4820-9697-bc2a82b9e0b5` y el mixto `1df53d61-97b5-40a0-af50-9169aad00349`. El grupo cancelado en ejecución fue `d2694241-c1a6-4fee-b2a7-7d82bdb40a0a` y el cancelado en cola `7fd1b8cc-672d-4c59-872d-473f62d4dcc8`. Los IDs cambian al repetir la prueba.

## Fallos encontrados y correcciones

| Fallo | Antes | Después |
|---|---|---|
| Una acción deshabilitada en una red interrumpía la respuesta de todo el lote | Chrome recibió 409 `ACTION_DISABLED` para las redes 122 y 123. La red 122 ya había abierto el snapshot 14. Reenviar el lote entero podía repetir trabajo. La regresión MockMvc dio «expected 202, was 409» con la red rechazada en primera posición. | La API registra el rechazo de política en el hijo afectado y continúa con las demás redes. En Chrome devolvió 202 con un hijo ACCEPTED y otro REJECTED. MockMvc verificó el orden inverso y el ID del grupo admitido. El comando individual conserva su semántica. [Servicio](../lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/api/v5/ApiV5ManagementService.java) · [Regresión](../lareferencia-lrharvester-app/src/test/java/org/lareferencia/backend/api/v5/ApiV5TaskAdmissionTest.java) |
| La interfaz cerraba el resultado antes de mostrar los rechazos | El callback de éxito cerraba el diálogo y borraba la selección al recibir el lote, incluso cuando un hijo era REJECTED. El diálogo seguía montado al abrir otra selección. | Un lote totalmente admitido muestra su confirmación en el listado. Con rechazos, el diálogo conserva las redes seleccionadas al abrirlo y muestra el acrónimo y el motivo hasta que el operador lo cierra. En la prueba, el segundo lote se abrió en la misma página y mostró «Action is disabled for this network» junto a B. [Diálogo](../lareferencia-lrharvester-admin-web/src/features/networks/NetworkBatchCommandDialog.tsx) |
| La confirmación de cancelar carecía de nombre accesible | Playwright pudo pulsar el icono por posición, pero buscar el botón «Cancelar operaciones» agotaba el tiempo. La etiqueta del tooltip pertenecía al elemento envolvente. | El botón declara su nombre en el idioma del admin. La prueba lo activó por rol y nombre y verificó el efecto sobre ambos trabajos. [Listado de redes](../lareferencia-lrharvester-admin-web/src/features/networks/NetworkListPage.tsx) |

## Cómo repetir

1. Con el PostgreSQL de desarrollo detenido, copiar a un directorio temporal el clúster `Docker/volume/dev/lareferencia-dev/lareferencia/postgres/data/pgdata` y las carpetas `config` y `data` de `lrharvester-app` del mismo volumen. Iniciar PostgreSQL 14 con el clúster copiado, en un puerto local. En esa copia poner a nulo `network.schedulecronexpression` y preparar una cuenta ADMIN temporal.
2. Compilar los módulos del workspace y servir el bundle de admin-web desde `frontend.admin-static-directory`. La instalación probada usó la configuración copiada, `workflow.engine=legacy`, `actions.beans.filename=actions.xml`, ambos datasources apuntando al PostgreSQL temporal y `store.basepath` apuntando a la copia de `data`. Spring y Chrome se ejecutaron en el mismo equipo. El puerto de Spring y el proveedor OAI de la prueba escucharon en loopback. Para HTTP local se desactivaron los indicadores de cookie segura en la copia.
3. Con Chrome y Playwright para Python instalados, ejecutar desde plataforma el comando siguiente. La prueba solicita la contraseña del administrador o la lee de `ADMIN_TEST_PASSWORD`. Crea tres redes con prefijo aleatorio, sus snapshots y una excepción a la configuración de acciones en la segunda red. Usar la ruta absoluta al almacén de esta instalación. La prueba deja estos datos en la copia para inspección.

```sh
python3 testing/admin-ui/verificar_cosecha.py \
  "http://127.0.0.1:${PUERTO_ADMIN}" "${USUARIO_ADMIN_PRUEBA}" "${COPIA_DATA}"
```

El script sirve `Identify` y `ListRecords` sobre HTTP, incluyendo los tokens de reanudación. Las altas, confirmaciones, cancelación y envíos por lote se hacen con controles de la interfaz en español. Solo la preparación de la acción deshabilitada usa un PUT directo autenticado. Se usaron Chrome 157 y Playwright 1.60. El ensayo cubre el motor de tareas Java empleado por esta copia. La indexación del buscador se verificó posteriormente sobre PA #4. La publicación dARK y la variante Flowable quedan pendientes. [Indexación del buscador](ADMIN_UI_INDEXACION.md) [Registros OAI de entrada](../testing/oai-incremental/fixtures/oai-dc/baseline) · [Seguimiento general](ADMIN_UI_VERIFICACION.md)

## Regresiones automatizadas

```sh
mvn -Plareferencia -pl lareferencia-lrharvester-app -am -Dno-frontends \
  -Dtest=ApiV5TaskAdmissionTest,TaskManagerTest,HarvestingLifecycleTest \
  -Dsurefire.failIfNoSpecifiedTests=false test

cd lareferencia-lrharvester-admin-web
./node/node node_modules/typescript/bin/tsc -b --pretty false
./node/node node_modules/vite/bin/vite.js build
./node/node node_modules/vitest/vitest.mjs run
```

Pasaron **31 pruebas Java** (4 de admisión HTTP, 16 del gestor de tareas y 11 del ciclo de cosecha) y **85 pruebas Vitest** en 12 archivos. También pasaron la compilación TypeScript y el build de producción. Vite mantuvo el aviso de tamaño de bundle ya registrado en la verificación anterior.
