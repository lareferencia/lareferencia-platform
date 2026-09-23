# Estructura de paquetes vigente

**Status:** current · **Last verified:** 2026-09-23

Este documento describe el `lareferencia-core-lib` actual, no un plan histórico.

- `org.lareferencia.core.domain`: entidades y value objects.
- `org.lareferencia.core.metadata`: stores FS/H2/SQLite y snapshots.
- `org.lareferencia.core.repository.catalog`: catálogo SQLite OAI.
- `org.lareferencia.core.repository.validation`: persistencia SQLite de validación.
- `org.lareferencia.core.service`: servicios de metadata, validación, estadísticas e indexación.
- `org.lareferencia.core.worker`: harvesting, validation, indexing y limpieza.
- `org.lareferencia.core.task`: acciones y motor legacy.
- `org.lareferencia.core.flowable`: integración BPMN opcional.
- `org.lareferencia.core.util`: utilidades transversales (`ConfigPathResolver`, etc.).
- `org.lareferencia.core.embedding`: soporte de embeddings.
- `org.lareferencia.core.oabroker`: integración con OAI Broker.

El dominio no depende de UI/transporte; los workers consumen interfaces de metadata, catálogo y validación; la selección `workflow.engine=legacy|flowable` pertenece a configuración.

## Convenciones de paquetes y migración

El namespace vigente es `org.lareferencia.core`. Las referencias antiguas `org.lareferencia.backend` no deben aparecer en código nuevo ni en documentación.

Convenciones: dominio en `core.domain`, metadata en `core.metadata`, catálogo en `core.repository.catalog`, validación en `core.repository.validation`, servicios en `core.service`, workers en `core.worker` y workflow en `core.task`/`core.flowable`.

No se mantienen scripts automáticos de sustitución de imports. Los cambios de paquete deben validarse con el compilador, configuración Spring y pruebas del módulo afectado.

> **Nota 2026-09-23:** el contenido de `PACKAGE_MIGRATION_GUIDE.md` se fusionó en este documento (paquetes verificados contra `lareferencia-core-lib/src/main/java/org/lareferencia/core/`); la guía se archivó en [`docs/archive/`](archive/README.md).
