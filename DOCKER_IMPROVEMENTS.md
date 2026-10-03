# Docker: backlog de mejoras

Este documento reúne mejoras pendientes para el entorno Docker de LA Referencia Platform. Es una lista de trabajo, no confirma que las mejoras estén implementadas.

## Prioridad alta

### Usar el core OAI-PMH mantenido por el provider

**Situación actual**

- La fuente vigente del core OAI-PMH es `lareferencia-oai-pmh/solr.core/oai`.
- El contenedor Solr se construye copiando `Docker/solr/cores` a `/opt/lr-solr-cores` (`Docker/solr/Dockerfile`).
- Al primer arranque, `Docker/solr/entrypoint.sh` copia esa plantilla a `/var/solr/data`. Por tanto, el servicio Solr de Docker todavía depende de `Docker/solr/cores/oai`, que es una copia independiente.
- El entrypoint inicializa solo cuando no existe `/var/solr/data/.lr_initialized`. Un rebuild o restart normal no actualiza los configsets ya inicializados.

**Trabajo propuesto**

1. Hacer que el contexto de build de Solr obtenga `oai` desde `lareferencia-oai-pmh/solr.core/oai`, y dejar en `Docker/solr/cores` solo los configsets que pertenecen al stack Docker, como `biblio`.
2. Retirar `Docker/solr/cores/oai` cuando la nueva ruta de provisión esté integrada.
3. Definir cómo actualizar `conf/` en instalaciones existentes sin borrar el índice ni los datos persistidos. Distinguir explícitamente entre configset de arranque y configuración activa del core.
4. Mantener una única fuente de verdad para schema, `solrconfig.xml`, `core.properties` y recursos auxiliares.

**Criterios de cierre**

- Una instalación nueva registra el core `oai` con los archivos del provider.
- Una reconstrucción/actualización aplica los archivos nuevos al core existente sin eliminar documentos.
- Solr 9.8 carga el core y el provider puede consultar, paginar e indexar documentos, incluido `item.id` de tipo `long` y `item.handle` como `uniqueKey`.
- La documentación de los flujos normal y Docker Dev explica cómo aplicar una actualización de configuración.

## Otras mejoras identificadas

### Hacer explícita la actualización de cores existentes

El marcador `.lr_initialized` hace que la copia inicial sea de una sola vez. Documentar y ofrecer una operación segura para actualizar configuraciones existentes, con respaldo y sin borrar los datos del índice.

### Validar configuración al iniciar

Agregar una comprobación clara de los cores requeridos por los servicios seleccionados y fallar con un mensaje accionable si falta un configset o una configuración es incompatible.

### Reducir duplicación entre perfiles Docker

Revisar `docker.sh` y `docker-dev.sh` para que build, sincronización de assets, puertos y operaciones de Solr compartan una única implementación o contratos comunes, evitando que los dos flujos diverjan.

### Mejorar trazabilidad de la imagen Solr

Registrar en logs la versión de Solr, las fuentes/identificadores de los configsets usados en el build y si se hizo inicialización o actualización de configuración.

### Revisar recursos externos de build

El Dockerfile de Solr descarga jars desde ramas externas durante el build. Fijar versiones o checksums para mejorar reproducibilidad y detectar cambios inesperados.

## Estado

- [ ] Core `oai` de Docker obtenido desde el provider.
- [ ] Actualización segura de cores existentes definida e implementada.
- [ ] Validación de configsets al iniciar.
- [ ] Menor duplicación entre flujos Docker normal y Dev.
- [ ] Trazabilidad de versiones y fuentes de configsets.
- [ ] Dependencias descargadas fijadas y verificadas.
