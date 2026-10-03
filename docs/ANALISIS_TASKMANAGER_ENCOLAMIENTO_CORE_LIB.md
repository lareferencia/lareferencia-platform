# Análisis del TaskManager del Harvester

> Actualización: la implementación posterior y su estado de comprobación están en [TaskManager implementado](../lareferencia-core-lib/docs/TASKMANAGER_IMPLEMENTACION.md). Este documento conserva el análisis previo.


**Propósito:** dejar evidencia del comportamiento actual de encolamiento y ejecución en `lareferencia-core-lib` para que otro agente evalúe cambios. Es un análisis del código existente; no propone ni implementa cambios.

**Revisión ampliada (2026-10-02):** [propuesta y evidencia en core-lib](../lareferencia-core-lib/docs/TASKMANAGER_PROPUESTA_MEJORA.md). Precisa tres aspectos de este inventario: el drenaje no garantiza FIFO porque un worker bloqueado vuelve al final; la cancelación del future no confirma salida del cuerpo del worker; y la exclusión es por ID de contexto, que en comandos manuales dARK no es el ID de red. También documenta la configuración de lanes en BD, las carreras de creación de colas y las diferencias de admisión entre APIs.

## Alcance y selección del motor

El objeto principal es `org.lareferencia.core.task.TaskManager`, usado por el executor legacy. `TaskManagerConfig` crea ese bean sólo si `workflow.engine=legacy` o la propiedad no está definida (`matchIfMissing=true`). `NetworkActionExecutorConfig` conecta `LegacyNetworkActionExecutor` con `TaskManager`; si el motor seleccionado es Flowable, se usa `FlowableNetworkActionExecutor` y las conclusiones sobre las colas internas legacy no aplican.

Referencias: `lareferencia-core-lib/src/main/java/org/lareferencia/core/task/TaskManager.java:46-55`, `TaskManagerConfig.java:31-43,52-70`, `NetworkActionExecutorConfig.java:60-99`.

## Modelo de ejecución legacy

`TaskManager` mantiene mapas concurrentes de colas por ID:

- `runningWorkers`: workers que ya fueron enviados al scheduler, indexados por `runningContext.getId()`.
- `queuedWorkers`: workers pendientes, también agrupados por contexto.
- `serialLane`: workers corriendo agrupados por `serialLaneId`.
- `scheduledTasks`: lanzadores de ejecuciones cron, aparte de workers activos/pendientes.

Las colas usan `ConcurrentLinkedQueue` sin capacidad fija. `QueueMap.totalSize()` agrega las longitudes de todos los grupos. El tope de pendientes es por tanto un control explícito global, no capacidad de la estructura ni tope independiente por red.

En la ejecución habitual el contexto es `NetworkRunningContext`; su ID es `NETWORK::<networkId>`, así que el guard de “un proceso activo por contexto” serializa acciones de la misma red.

Referencias: `TaskManager.java:59-102,108-118,125-132`; `NetworkRunningContext.java:35-50,88-91`.

## Admisión de workers: `launchWorkerWithResult`

El método sincronizado toma el ID de contexto y el lane del worker. Inicia inmediatamente si se cumplen a la vez estas condiciones:

1. El total de workers activos es menor que `maxConcurrentWorkers`.
2. No hay worker activo para el mismo contexto.
3. El worker no tiene lane serial (lane negativo), o no hay un worker activo registrado en ese lane.

Para iniciar, llama a `scheduler.schedule(worker, new Date())`, asigna el `ScheduledFuture`, añade el worker a `runningWorkers` y, si el lane es no negativo, lo añade al mapa de lane. Devuelve `RUNNING`.

Si alguna condición falla, añade el worker al final de la cola del contexto si el total global encolado aún es menor que el tope; devuelve `QUEUED`. Si el tope fue alcanzado, no lo agrega y devuelve `REJECTED`.

El método y las comprobaciones son sincronizados, por lo que una admisión individual no compite con otra llamada al mismo `TaskManager` entre comprobar y encolar. La clase además guarda sus propios registros de activos/pendientes; el pool del scheduler es otro límite de capacidad.

Referencias: `TaskManager.java:292-307,327-391`.

## Límites y dónde se configuran

| Límite | Propiedad / default efectivo | Alcance y evidencia |
|---|---|---|
| Workers activos | `taskmanager.concurrent.tasks`, default `4` | Tope global contando `runningWorkers.totalSize()`, comprobado antes de despachar. `TaskManager.java:114-118,296-298,350-359`. |
| Workers en cola | `taskmanager.max_queuded.tasks`, default `32` | Tope global contando todas las colas de contexto; propiedad escrita con typo `queuded`. `TaskManager.java:117-118,301-307,379-386`. |
| Pool del scheduler | `scheduler.pool.size`, default `10` | Tamaño del `ThreadPoolTaskScheduler` del legacy. `TaskManagerConfig.java:52-59`. No sustituye el límite lógico de activos de TaskManager. |
| Trabajos pendientes por contexto | Sin propiedad propia | Estructuras ilimitadas; el límite se comparte globalmente entre contextos. |
| Trabajos pendientes por lane | Sin límite independiente en legacy | Lane sólo impide iniciar mientras haya un activo en ese lane; espera en `queuedWorkers`, sujeta al límite global. |
| Cron almacenado | Sin límite explícito en `scheduledTasks` | No forma parte de `queuedWorkers.totalSize()`. El pool cron y workers usa el mismo `TaskScheduler`. |

Configuración de harvester versionada: `lareferencia-lrharvester-app/config/application.properties.d/05-harvester.properties:6-13` fija pool `10`, activos `4`, pendientes `32`. El loader del core lee los `.properties` del directorio `application.properties.d`, ordenados alfabéticamente, y los añade al Environment; el arranque del app registra ese listener. Referencias: `PropertiesDirectoryListener.java:36-43,63-89`; `MainApp.java:74-80`.

`taskmanager.clean.interval=60000` aparece en ese archivo, pero no controla la limpieza: el método está anotado con `@Scheduled(fixedRate = 2000)`. `taskexecutor.pool.size` también aparece pero no lo lee el código principal según la evidencia de configuración. Referencias: `TaskManager.java:414-415`; `05-harvester.properties:8-13`; `docs/CONFIGURATION_PROPERTIES.md:88-100`.

### Configuración que puede confundirse

`workflow.max-queued-processes=32` aparece en `08-workflow.properties` y en `application.properties.model`, pero **no es el tope leído por `TaskManager`**. El core la vincula a `WorkflowProperties` (`@ConfigurationProperties(prefix="workflow")`) y Flowable usa `maxQueuedProcesses` y `maxQueuedPerLane`; por ello estos límites pertenecen al motor alternativo. En Flowable hay comprobaciones global y por lane y el submit puede lanzar `QueueFullException`.

Referencias: app `config/application.properties.d/08-workflow.properties:8-16`; core `flowable/config/WorkflowProperties.java:42-55`; `flowable/WorkflowService.java:291-319`. El comentario de `08-workflow.properties` declara “Default: flowable”, pero el archivo asigna `legacy`; `TaskManagerConfig` también documenta legacy como default cuando falta la propiedad. No inferir el motor activo del comentario.

## Reglas de serialización

- El contexto evita más de un worker activo para la misma red/contexto incluso con lane negativo.
- `BaseWorker` inicia con `serialLaneId=-1`; los lanes negativos no aplican serialización global por lane.
- Un lane `>=0` se registra cuando inicia el worker y se limpia cuando el `ScheduledFuture` aparece terminado o cancelado. Otro worker del mismo lane no puede iniciar mientras esa entrada permanezca.
- Los IDs de lane son valores compartidos por todos los beans que usan el mismo número; no están calificados por red.
- Los XML de acciones configuran numerosos workers con lanes `1`–`5`, `100`; por ejemplo `config/beans/index.elastic.actions.xml`, `dark.actions.xml`, `network.actions.xml`, `xoai.actions.xml`. El glosario del repo también registra que la serialización legacy se declara por bean con `serialLaneId`.

Referencias: `BaseWorker.java:57-82`; `TaskManager.java:347-365,426-429`; `lareferencia-lrharvester-app/config/beans/*.xml` (búsqueda `serialLaneId`).

## Drenaje de cola, limpieza y cancelación

Cada 2 segundos `cleanFinishedTasksAndRunQueued()` elimina workers terminados/cancelados de los registros de lanes y activos; luego recorre los contextos con pendientes. Para cada contexto sólo intenta sacar un worker si no queda ninguno activo para ese contexto. Saca el primero FIFO y vuelve a pasarlo por `launchWorker()`, que reevalúa los límites globales y lanes. Por tanto, un worker puede salir de la cabeza de su cola y ser encolado otra vez si todavía no puede iniciar; no se drena la cola entera en una sola pasada.

`clearQueueByRunningContextID` vacía pendientes del contexto. `killAllTaskByRunningContextID` llama `stop()` sobre activos; en `BaseWorker.stop()` se cancela el future con interrupción solicitada. La limpieza posterior quita entradas canceladas. El executor legacy para parar acciones llama primero a clear queue y luego a kill. Las tareas cron se guardan aparte; limpiar la cola de workers no elimina su programación.

Referencias: `TaskManager.java:414-469,477-528`; `BaseWorker.java:94-100`; `LegacyNetworkActionExecutor.java:196-200`.

## Qué sucede con un rechazo

El core expone `WorkerLaunchResult { RUNNING, QUEUED, REJECTED }` y también un batch `launchWorkersWithResult`. El batch primero hace una comprobación conservadora `queued + workers.size() > maxQueuedWorkers`; si falla, devuelve `REJECTED` para todos. Si pasa, procesa secuencialmente cada worker; los resultados pueden diferir según disponibilidad/contexto/lane.

Sin embargo, las rutas normales del executor legacy (`executeAction` y `executeAllActions`) llaman `taskManager.launchWorker(worker)`. Este método envuelve `launchWorkerWithResult` pero descarta el resultado. Si la cola está llena, el worker no se encola y el caller no recibe resultado estructurado; queda el log de “Waiting queue reached max allowed size”. Por ello no debe asumirse que el disparador/API pueda informar rechazo al usuario. La ruta normal además hace una llamada individual por worker, no usa admisión batch.

Referencias: `TaskManager.java:334-412`; `LegacyNetworkActionExecutor.java:131-189`.

## Scheduler frente al límite lógico

`TaskManagerConfig` instancia `ThreadPoolTaskScheduler` con `scheduler.pool.size` (10 en config) y `TaskManager` admite por defecto hasta 4 activos. En el flujo manejado por TaskManager la admisión de workers está limitada por 4 antes del scheduler, mientras que el pool comparte hilos con programación de cron y por sí solo no expresa el mismo límite. Si `scheduler.pool.size` se configura por debajo del límite lógico, los registros `runningWorkers` pueden incluir tareas ya enviadas que están esperando turno interno del scheduler; el contador lógico no demuestra que el cuerpo del worker ya esté ejecutándose.

Referencias: `TaskManagerConfig.java:52-59`; `TaskManager.java:350-359`; `05-harvester.properties:6-13`.

## Observabilidad disponible

TaskManager publica por JMX `getRunningCount()` y `getQueuedCount()` como agregados, y listas por contexto para activos, pendientes y schedulers cron. El conteo de activos corresponde a lo registrado en `runningWorkers`, sujeto al ciclo de limpieza de 2 segundos; no es una medición directa de threads en ejecución. Referencia: `TaskManager.java:54,138-240`.

## Puntos concretos para que el siguiente agente evalúe

1. Confirmar si el límite deseado es worker, acción completa o proceso de red: legacy encola cada worker por separado, mientras Flowable somete procesos.
2. Alinear el nombre/documentación de la propiedad de cola (`taskmanager.max_queuded.tasks`) con la propiedad `workflow.max-queued-processes` ya usada por Flowable, evitando cambiar sólo una ruta de ejecución.
3. Decidir la semántica esperada al llenar la cola: rechazo visible al caller, log/estado consultable, o estrategia distinta. Hoy el executor legacy ignora `WorkerLaunchResult`.
4. Determinar si los topes necesitan scopes global, por red, por lane y/o por tipo de worker. El actual legacy sólo tiene global activo/pendiente, contexto para exclusión y lane para serialización.
5. Revisar drenaje FIFO por contexto y el hecho de que los contextos se recorren vía `ConcurrentHashMap`; no hay orden global justo entre redes/contextos.
6. Tratar `scheduler.pool.size`, limpieza fija de 2 s, cron y workers como recursos relacionados pero distintos; no tomar `taskmanager.clean.interval` ni `taskexecutor.pool.size` como controles efectivos.
7. Comparar explícitamente con Flowable sólo si el cambio debe cubrir ambos motores: usa `workflow.max-queued-processes`, `workflow.max-queued-per-lane` y colas por lane.

## Archivos fuente principales

- `lareferencia-core-lib/src/main/java/org/lareferencia/core/task/TaskManager.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/task/TaskManagerConfig.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/task/LegacyNetworkActionExecutor.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/task/NetworkActionExecutorConfig.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/BaseWorker.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/NetworkRunningContext.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/flowable/WorkflowService.java` (comparación)
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/flowable/config/WorkflowProperties.java` (comparación)
- `lareferencia-lrharvester-app/config/application.properties.d/05-harvester.properties`
- `lareferencia-lrharvester-app/config/application.properties.d/08-workflow.properties`
- `lareferencia-lrharvester-app/config/beans/*.xml` (`serialLaneId`)
