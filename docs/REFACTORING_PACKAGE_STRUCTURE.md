# Estructura de paquetes vigente

Este documento describe el `lareferencia-core-lib` actual, no un plan histórico.

- `org.lareferencia.core.domain`: entidades y value objects.
- `org.lareferencia.core.metadata`: stores FS/H2/SQLite y snapshots.
- `org.lareferencia.core.repository.catalog`: catálogo SQLite OAI.
- `org.lareferencia.core.repository.validation`: persistencia SQLite de validación.
- `org.lareferencia.core.service`: servicios de metadata, validación, estadísticas e indexación.
- `org.lareferencia.core.worker`: harvesting, validation, indexing y limpieza.
- `org.lareferencia.core.task`: acciones y motor legacy.
- `org.lareferencia.core.flowable`: integración BPMN opcional.

El dominio no depende de UI/transporte; los workers consumen interfaces de metadata, catálogo y validación; la selección `workflow.engine=legacy|flowable` pertenece a configuración.
