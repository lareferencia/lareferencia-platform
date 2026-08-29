# Implementación de configuración de acciones por red

Fecha: 27 de agosto de 2026  
Rama: `harvester-v5-api-and-ui`

## Objetivo

Separar en la API v5 dos conceptos que antes estaban mezclados en `Network.properties`:

1. La política de ejecución de una acción (manual y programada).
2. Los modificadores propios de la acción (por ejemplo, cosecha full o diagnóstico detallado).

La solución agrega una tabla nueva y una capa v5 independiente. Las tablas y contratos legacy no se modifican estructuralmente.

## Funcionalidades nuevas

### Catálogo global de acciones (v5)

Como base de esta iteración ya estaba implementado el catálogo global `application_action` (migración `V5.0.0.8`), con descubrimiento Legacy/Flowable, estados `ENABLED`, `DISABLED` y `UNAVAILABLE`, refresh manual y endpoints `/api/v5/application-actions`. La pantalla React `/actions` permite consultar, habilitar/deshabilitar y editar defaults globales. La configuración por red documentada aquí se superpone a ese catálogo y no lo reemplaza.

### Persistencia

Se agregó la entidad `NetworkActionConfiguration`, persistida en `network_action`, con:

- red y acción global asociadas;
- `enabled` para permitir ejecución manual;
- `scheduleEnabled` para participación en ejecuciones programadas;
- `configuration` JSONB para modificadores por red;
- auditoría de creación, actualización y usuario.

La migración está en `V5.0.0.9__Network_action_configuration.sql`. La tabla tiene unicidad por red y acción.

### Descubrimiento de opciones

Los `NetworkAction` legacy ahora pueden distinguir sus propiedades de configuración mediante `getConfigurationProperties()`:

- en acciones siempre programadas, todas sus propiedades son modificadores;
- en acciones no siempre programadas, la primera propiedad conserva su función histórica de habilitar el schedule y las siguientes son modificadores.

Cuando no se proporciona un schema explícito, el catálogo genera automáticamente un JSON Schema booleano para esos modificadores.

### Migración compatible

Al iniciar el gestor de acciones:

- se crean filas para las acciones descubiertas;
- las acciones existentes quedan habilitadas inicialmente;
- `scheduleEnabled` conserva el resultado de la lógica anterior;
- los valores actuales de `Network.properties` se copian a `network_action.configuration` cuando corresponde;
- las propiedades de `Network` se mantienen intactas como fallback.

Esto permite activar la nueva configuración sin perder instalaciones existentes.

### Contexto de ejecución

`NetworkRunningContext` ahora contiene:

- `actionKey`;
- `actionConfiguration`;
- lectura de opciones booleanas con fallback a la propiedad legacy.

El executor legacy crea contextos específicos para cada acción. Los workers actualmente migrados son:

- `HarvestingWorker`: `FORCE_FULL_HARVESTING`;
- `ValidationWorker`: `DETAILED_DIAGNOSE`.

Flowable recibe `actionName` y `actionConfiguration` como variables del proceso. Los schedules refrescan la política y la configuración antes de cada disparo.

### API v5 por red

Se incorporaron endpoints bajo `/api/v5/networks/{networkId}/actions`:

- `GET` listado de acciones configuradas para la red;
- `GET /{actionKey}` detalle;
- `PUT /{actionKey}` reemplazo de política y configuración.

Las respuestas incluyen estado global, habilitación manual, habilitación programada, configuración local, configuración efectiva y JSON Schema/UI Schema.

### Interfaz React

La edición de red incorpora la pestaña **Acciones y programación**:

- checkbox de ejecución manual;
- checkbox de ejecución programada;
- formulario RJSF para modificadores cuando existe schema;
- guardado explícito de opciones;
- bloqueo visual si la red tiene procesos activos;
- indicación del estado global de cada acción.

El bloque anterior de propiedades programables se retiró de la pestaña separada para evitar duplicar controles.

## Cambios internos relevantes

- `LegacyNetworkActionExecutor` consulta la política por red antes de lanzar workers.
- `executeAllActions` omite acciones deshabilitadas global o localmente.
- `FlowableNetworkActionExecutor` valida `networkProcessing` y acciones individuales.
- `WorkflowService` permite actualizar las variables de ejecución desde el guard del schedule.
- `NetworkRunningContextFactory` reconstruye el contexto Flowable con acción y configuración.
- Los repositorios nuevos no se exponen mediante Spring Data REST.
- La lógica de `Network.properties` no se elimina ni se reescribe automáticamente.

## Compatibilidad e impactos potenciales

### Legacy y static

La estructura de `Network`, sus propiedades, XML de beans, workers y DTOs legacy permanece igual. Static puede seguir leyendo y editando `Network.properties`.

Sin embargo, una acción que se deshabilite desde v5 dejará de aceptar nuevas ejecuciones manuales y programadas, incluso si static todavía muestra el control antiguo. Los procesos ya ejecutándose o encolados no se cancelan.

Al modificar una opción desde v5, el worker prioriza el valor de `network_action.configuration`; si no existe, utiliza el valor legacy. La reactivación restaura la ejecución sin reiniciar.

### Spring Data REST

No se cambiaron los endpoints generados existentes. Los repositorios `ApplicationActionRepository` y `NetworkActionConfigurationRepository` están excluidos de exposición automática.

### Flowable

La firma pública interna de `WorkflowService.setScheduledProcessGuard` pasó de recibir sólo la clave del proceso a recibir también sus variables. Cualquier integración externa que invoque directamente ese setter debe recompilarse.

### Configuración de schedules

Cambiar `scheduleEnabled` ya no exige modificar `Network.properties`. El cron de la red sigue viviendo en `Network.scheduleCronExpression`; la política de cada acción vive en `network_action`.

### Casos no migrados automáticamente

Las propiedades que son la única propiedad de una acción no siempre programada continúan tratándose como selector legacy de schedule. Para convertirlas en modificadores explícitos será necesario añadir un schema/configuración declarativa en una iteración posterior.

## Verificación realizada

- Compilación de `lareferencia-core-lib`: correcta.
- Pruebas del catálogo: 4 correctas.
- Pruebas focalizadas de la API v5 y servicios: 11 correctas.
- Typecheck y build de la aplicación React: correctos.
- Harvester iniciado localmente con el perfil `lareferencia` y PostgreSQL existente.
- La suite completa queda condicionada a disponer del socket Docker para Testcontainers; el fallo observado fue de infraestructura, no de aserciones funcionales.

## Archivos principales

- `lareferencia-core-lib/src/main/java/org/lareferencia/core/domain/NetworkActionConfiguration.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/task/NetworkActionConfigurationService.java`
- `lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/NetworkRunningContext.java`
- `lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/api/v5/ApiV5NetworkActionController.java`
- `lareferencia-shell/src/main/resources/db/migration/V5.0.0.9__Network_action_configuration.sql`
- `lareferencia-lrharvester-admin-web/src/features/networks/NetworkEditPage.tsx`

## Próximos pasos recomendados

1. Añadir schemas declarativos para modificadores que no puedan inferirse de los XML.
2. Incorporar pruebas MockMvc específicas para listado, PUT, permisos y validación de schemas.
3. Probar en una instalación con static activa que el rechazo de una acción deshabilitada se presenta correctamente.
4. Documentar la migración de propiedades restantes y decidir si alguna debe retirarse de `Network.properties` en una fase futura.

## Actualización: configuración global de workers

Fecha de actualización: 28 de agosto de 2026

Se separaron los parámetros técnicos de los workers de la configuración por fuente. La configuración de un worker ya no se guarda ni se edita dentro de `network_action`; queda centralizada por instalación y motor en la nueva tabla `application_worker_configuration` (migración `V5.0.0.10__Application_worker_configuration.sql`).

### Catálogo de acciones y relación con workers

Cada acción continúa declarando sus workers en los beans `NetworkAction` mediante `workers`. El catálogo persistente publica esa relación en `definition.workers`, y la UI la muestra con una fila por worker. Esto permite saber qué componentes ejecuta cada acción sin inspeccionar XML.

El catálogo general de acciones sigue siendo `application_action`. Sus responsabilidades son descubrir acciones, guardar su definición y controlar si están habilitadas. La configuración técnica de los workers se administra separadamente.

### Descubrimiento automático de parámetros

Al reconciliar el catálogo, Spring inspecciona cada bean worker y descubre automáticamente sus propiedades JavaBean editables de tipo escalar:

- texto y nombres de esquemas/campos;
- enteros y números;
- booleanos;
- valores enum.

Se excluyen propiedades de infraestructura y estado de ejecución, como el contexto de red, estado, tareas programadas, `incremental` y dependencias Spring. Las propiedades declaradas explícitamente en XML siguen siendo compatibles y se utilizan como metadatos adicionales o valores por defecto.

La configuración se valida contra el JSON Schema descubierto y se aplica únicamente al crear una nueva instancia prototype del worker. Los procesos en curso no se modifican.

### API y pantalla

La API v5 dispone de:

- `GET /api/v5/worker-configurations`;
- `GET /api/v5/worker-configurations/{workerKey}`;
- `PUT /api/v5/worker-configurations/{workerKey}`.

En `/actions`, la sección se denomina **Configuraciones de workers**. El botón de edición se muestra como **Parámetros** y utiliza un formulario generado desde el schema, no un campo de texto JSON libre.

### Migración de compatibilidad

Durante la reconciliación inicial, si existían valores de worker anidados en la configuración global de una acción, se copian a la fila global correspondiente y después se eliminan del registro de la acción. Las propiedades por fuente y los modificadores funcionales de `network_action` permanecen separados.

Este cambio no altera las tablas `network`, los XML legacy ni los contratos de static. El único efecto operativo nuevo es que los parámetros técnicos modificados en la aplicación se aplican globalmente a las siguientes ejecuciones de todas las fuentes.

## Actualización: edición independiente de reglas

Fecha de actualización: 29 de agosto de 2026

La edición de validadores y transformadores se ajustó para evitar que una operación sobre las reglas reemplace accidentalmente toda la configuración.

### Separación de responsabilidades

- **Guardar configuración** modifica únicamente el nombre y la descripción del validador o transformador existente.
- **Guardar esta regla** crea o actualiza una regla mediante su subrecurso v5.
- El borrado de una regla persistida se realiza mediante `DELETE` y requiere confirmación en la UI.
- El reordenamiento se realiza exclusivamente con los botones subir/bajar y se persiste como una operación atómica de orden.
- Se eliminó el campo numérico redundante de orden en el formulario de transformadores.

Para configuraciones nuevas se conserva el guardado agregado inicial, ya que todavía no existe un identificador de la configuración al que asociar reglas individuales.

### Nuevos endpoints de metadatos

Se agregaron endpoints administrativos que no tocan las reglas hijas:

- `PUT /api/v5/validators/{id}/metadata`
- `PUT /api/v5/transformers/{id}/metadata`

Los endpoints reciben únicamente `name` y `description`. Los endpoints agregados previamente para reglas continúan siendo:

- `POST .../{id}/rules`;
- `PUT .../{id}/rules/{ruleId}`;
- `DELETE .../{id}/rules/{ruleId}`;
- `PUT .../{id}/rules/order`.

### Compatibilidad

La API agregada `PUT /api/v5/validators/{id}` y su equivalente de transformadores se mantiene para clientes existentes, incluyendo reemplazo completo de reglas. La nueva interfaz React utiliza los endpoints separados para evitar conflictos y no cambia los controladores legacy, Spring Data REST, las entidades existentes ni el formato `jsonserialization` interno.

La UI muestra mensajes de éxito o error para cada operación. En caso de fallo al guardar, borrar o reordenar, la respuesta `ProblemDetail` de la API se presenta al usuario sin ocultar el motivo.

### Verificación adicional

- Build de producción React (`tsc -b` y `vite build`): correcto.
- Compilación Maven de `lareferencia-lrharvester-app` con sus dependencias: correcta.
- No se modificó el comportamiento de los workers ni de los motores Legacy/Flowable.
