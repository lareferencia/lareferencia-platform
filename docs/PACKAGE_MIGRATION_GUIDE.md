# Guía de paquetes

El namespace vigente es `org.lareferencia.core`. Las referencias antiguas `org.lareferencia.backend` no deben aparecer en código nuevo ni en documentación.

Convenciones: dominio en `core.domain`, metadata en `core.metadata`, catálogo en `core.repository.catalog`, validación en `core.repository.validation`, servicios en `core.service`, workers en `core.worker` y workflow en `core.task`/`core.flowable`.

No se mantienen scripts automáticos de sustitución de imports. Los cambios de paquete deben validarse con el compilador, configuración Spring y pruebas del módulo afectado.
