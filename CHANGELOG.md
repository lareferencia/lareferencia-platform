# Changelog

Los cambios relevantes de la plataforma se registran aquí antes de publicarse.
Al preparar una release, mover las entradas incluidas de `Unreleased` a una
sección con su versión y fecha, y conservar `Unreleased` para nuevos cambios.

## Unreleased

### Correcciones

- El dashboard recupera comparaciones por enlace directo, busca fuentes autorizadas y pagina las frecuencias de cada regla en SQLite. La fuente QAMIX permite verificar registros válidos e inválidos en una misma cosecha con y sin captura de ocurrencias. [Contrato v5](docs/HARVESTER_MANAGEMENT_API_V5.md) · [Casos de prueba](testing/dashboard-validation/README.md)

- El dashboard React consulta el XML histórico por red y aplica la selección de registros al resumen, al cumplimiento y a las frecuencias de cada regla. [Contrato de lectura v5](docs/HARVESTER_MANAGEMENT_API_V5.md)

- Se corrigió el timeout de Solr en el entorno de pruebas del harvester. La indexación desde el admin se verificó contra los 3.444 identificadores de un snapshot histórico. [Evidencias](docs/ADMIN_UI_INDEXACION.md)

- Los lotes del admin devuelven un resultado por fuente aunque una tenga la
  acción deshabilitada. El diálogo muestra la fuente rechazada y el motivo.
  La confirmación de cancelación se puede identificar por su nombre accesible.

- El admin conserva los enlaces al recargar con una sesión válida y verifica la
  red del snapshot. Permite recorrer el historial, reintentar la tabla del
  informe y consultar el XML publicado al abrir su pestaña. La búsqueda por
  identificador se aplica con Buscar o Enter.
- El listado del lector consulta solo los datos que necesita. La API v5 devuelve
  403 cuando Spring deniega una operación administrativa por rol.

- Los informes históricos de validación conservan sus reglas y contadores al
  editar o sustituir el validador. Los nuevos resúmenes indican por regla si
  estaba habilitada la captura de valores (core-lib y API v5).

- Los informes de validación aplican los filtros de registros del dashboard y
  calculan las frecuencias por regla sobre la selección activa. En la API v5,
  la igualdad de identificador OAI distingue el valor completo de una búsqueda parcial.

- La limpieza de metadatos huérfanos registra los hashes escaneados, los
  candidatos y los borrados en el historial de los snapshots protegidos.

- La exportación de metadatos interpreta los campos XOAI sin nombre como valores
  y conserva su contenido (core-lib `3a0cbf3`).

- La exportación de snapshots SQLite ignora los archivos WAL vacíos y tolera que
  SQLite los elimine durante la comprobación, evitando falsos errores de snapshot
  modificado. Los WAL con contenido siguen impidiendo la exportación hasta que se
  finalice el snapshot.
  ([core-lib `2beb753`](https://github.com/lareferencia/lareferencia-core-lib/commit/2beb753a1cfd03931ee5af41e2932578489f38c9))

- En el dashboard, los registros se muestran como válidos o inválidos. El selector de diagnóstico reúne las cosechas en un solo desplegable. El historial y su CSV muestran primero las más recientes, y un icono separado del ID abre el diagnóstico cuando está disponible.

- El dashboard muestra **Sin recuento** cuando el snapshot indica que la regla
  carece de recuento de ocurrencias y ofrece **Ver ocurrencias** cuando está
  disponible. Los conteos de registros aprobados y fallidos siguen disponibles.

- En snapshots históricos sin indicador de captura, el dashboard comprueba si hay ocurrencias guardadas para los registros activos antes de ofrecer el recuento por regla.

### Cambios

- Los perfiles de exportación XOAI admiten exclusiones por prefijo. La versión 1.1 del perfil de licencias las aplica a los vocabularios COAR e `info:eu-repo` al generar JSON y JSONL.

- Maven y los scripts de plataforma y Docker compilan y publican el dashboard React en `/dashboard/` de forma predeterminada. El código Angular se conserva en `angular/` fuera de la compilación.

- La portada del dashboard React permite buscar repositorios por nombre o sigla. El historial abre en Evolución y ofrece una comparación bajo demanda con fecha, hora y acceso al diagnóstico de ambas cosechas. [Portada](https://github.com/lareferencia/lareferencia-repository-dashboard/blob/20eedeb9a6e0a0954fa847e88a6112c563094588/docs/evidencias/portada/README.md) · [Comparación de PA #3 y #4](https://github.com/lareferencia/lareferencia-repository-dashboard/blob/20eedeb9a6e0a0954fa847e88a6112c563094588/docs/evidencias/historial-evolucion/README.md#pa-3-y-4-con-la-comparación-bajo-demanda)

- El perfil optativo `dashboard-react` añade un ZIP separado del dashboard React;
  no es necesario para construir React, que ya es la opción predeterminada.
  El diagnóstico reúne las reglas, los registros y sus detalles con la
  presentación del admin.

- El candidato React del dashboard incorpora el historial de cosechas, el gráfico por intervalo y el widget de estadísticas configurable por instalación y repositorio.

- El candidato React del dashboard permite filtrar registros de validación, consultar sus ocurrencias y exportar CSV de las reglas visibles, de la página actual y de las frecuencias por regla.

- El Repository Dashboard se incorpora al grupo de ramas `codex/rc5-pre`, con su
  plan de migración a React versionado y su commit fijado en el lock.

- El perfil de exportación para clasificación contempla todas las variantes DC
  configuradas (shell `d87a859`).

## 5.0.0-rc4 — 2026-11-18

### Correcciones

- La limpieza de metadatos huérfanos abre los catálogos protegidos y aborta antes
  de escanear o borrar si falla la lectura o si no se carga ninguna referencia
  protegida (core-lib).
  ([core-lib #23](https://github.com/lareferencia/lareferencia-core-lib/pull/23),
  [plataforma #114](https://github.com/lareferencia/lareferencia-platform/pull/114))

- Corrige la copia de recursos estáticos al construir la imagen Docker del
  proveedor OAI-PMH: utiliza el directorio `static/` en lugar de `static_en/`.
  ([#112](https://github.com/lareferencia/lareferencia-platform/pull/112))
