# Plataforma de cosecha, procesamiento y publicación de metadatos

La plataforma LA Referencia es una solución modular para recolectar registros de repositorios, mejorar su interoperabilidad y calidad, y publicarlos para búsqueda y reutilización. Integra servicios de cosecha, procesamiento, administración, indexación y exposición de metadatos. Puede desplegarse para operar una red de repositorios o para agregar y publicar colecciones.

Su arquitectura sigue el ciclo de vida del registro: conecta con fuentes que implementan OAI-PMH, conserva los metadatos recolectados, ejecuta validaciones y transformaciones, actualiza índices y ofrece interfaces y protocolos para consultar o volver a cosechar la información.

## Componentes de la plataforma

### Cosechador

El **Cosechador** es el núcleo de gestión y procesamiento de la plataforma. Se conecta con repositorios OAI-PMH y permite organizar las fuentes en redes, definir formatos y parámetros de cosecha, y ejecutar procesos manuales o programados.

Además de recuperar registros, coordina las etapas posteriores:

- **Validación:** aplica reglas configurables a los metadatos y conserva resultados y diagnósticos para revisar su calidad.
- **Transformación:** ejecuta mapeos entre formatos y prepara los registros para su publicación e indexación.
- **Procesamiento incremental:** detecta registros nuevos, modificados y eliminados. Cuando la configuración y los datos lo permiten, reutiliza resultados previos y procesa solo los cambios; también admite ejecuciones completas.
- **Acciones y tareas:** coordina cosecha, validación, indexación y tareas relacionadas, con seguimiento de estado y resultados.
- **Gestión de redes:** agrupa fuentes y configura para cada red sus formatos, reglas, transformaciones y opciones de publicación.

El Cosechador dispone de una API de gestión versionada y una interfaz web de administración. Los accesos se controlan mediante usuarios, roles y asignaciones a redes; las integraciones automatizadas pueden utilizar cuentas técnicas y tokens.

### Almacenamiento y trazabilidad

La plataforma separa los metadatos originales de los resultados de procesamiento. Los registros originales se conservan en almacenamiento de metadatos; catálogos y resultados de validación mantienen información estructurada por ejecución. Esta organización permite identificar cambios, consultar diagnósticos y reutilizar resultados entre cosechas sin perder la posibilidad de reprocesar una colección completa.

### Indexación, entidades y búsqueda

Los registros transformados pueden publicarse en índices para habilitar su consulta. Solr proporciona índices bibliográficos utilizados por la búsqueda y la publicación OAI-PMH. Elasticsearch u OpenSearch se utiliza para indexar entidades y relaciones extraídas de los metadatos. La plataforma también contempla indexación semántica con vectores cuando se configura un servicio de generación de embeddings.

VuFind puede funcionar como interfaz de descubrimiento sobre el índice bibliográfico. La disponibilidad de cada interfaz e índice depende del despliegue.

### Proveedor OAI-PMH

Un servicio independiente expone los registros publicados mediante OAI-PMH 2.0. Así, otras plataformas y agregadores pueden cosechar los metadatos de una instalación. El servicio lee el índice de publicación y ofrece un punto de interoperabilidad de salida, complementario a la cosecha que realiza el Cosechador desde las fuentes.

### Interfaces web

- **Administración:** permite configurar redes y procesos, ejecutar acciones y consultar su progreso, resultados y diagnósticos.
- **Dashboard de repositorios:** interfaz de consulta de solo lectura para supervisar información y resultados disponibles, con acceso limitado según las redes asignadas.
- **Búsqueda:** VuFind puede presentar los registros indexados como una interfaz de descubrimiento para usuarios finales.

### Identificadores persistentes

La integración con dARK permite coordinar operaciones relacionadas con identificadores ARK, incluidas reserva, preparación y conciliación. Requiere que la instalación tenga acceso al servicio minter y configure los parámetros correspondientes.

## Flujo funcional

```text
Repositorios y fuentes OAI-PMH
              ↓
          Cosechador
              ↓
     Validación y transformación
              ↓
      Indexación y publicación
        ↙          ↓          ↘
   Búsqueda    Entidades    Proveedor OAI-PMH
```

La API y las interfaces de administración permiten configurar y seguir este flujo. Las acciones pueden programarse y ejecutarse de forma coordinada; las actualizaciones incrementales reducen el reprocesamiento cuando solo cambió una parte de la colección.

## Repositorios de código

La plataforma se desarrolla como un conjunto de repositorios Git. El [repositorio principal de la plataforma](https://github.com/lareferencia/lareferencia-platform) reúne la configuración del workspace y el despliegue. Los componentes principales tienen repositorios propios:

- [Cosechador (aplicación)](https://github.com/lareferencia/lareferencia-lrharvester-app) y [biblioteca de procesamiento](https://github.com/lareferencia/lareferencia-core-lib)
- [Interfaz de administración](https://github.com/lareferencia/lareferencia-lrharvester-admin-web) y [Dashboard de repositorios](https://github.com/lareferencia/lareferencia-repository-dashboard)
- [Proveedor OAI-PMH](https://github.com/lareferencia/lareferencia-oai-pmh)
- [Modelo e indexación de entidades](https://github.com/lareferencia/lareferencia-entity-lib) y [API de entidades](https://github.com/lareferencia/lareferencia-entity-rest)
- [Configuración de índices Solr](https://github.com/lareferencia/lareferencia-solr-cores)
- [Integración dARK/ARK](https://github.com/lareferencia/lareferencia-dark-lib)
- [Cliente de cosecha OAI-PMH](https://github.com/lareferencia/lareferencia-oclc-harvester)
- [Herramientas de administración por línea de comandos](https://github.com/lareferencia/lareferencia-shell)

La distribución principal está bajo GNU AGPL v3; al reutilizar componentes, consulta también la licencia declarada en cada repositorio.

---

**Nota editorial:** las interfaces VuFind y Dashboard, la indexación semántica, el proveedor OAI-PMH y la integración dARK pueden requerir servicios, credenciales o configuración adicionales en cada despliegue.
