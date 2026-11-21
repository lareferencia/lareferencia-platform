# Changelog

Los cambios relevantes de la plataforma se registran aquí antes de publicarse.
Al preparar una release, mover las entradas incluidas de `Unreleased` a una
sección con su versión y fecha, y conservar `Unreleased` para nuevos cambios.

## Unreleased

### Correcciones

- El widget de estadísticas de uso adopta la tipografía del dashboard. En la copia de pruebas, el widget de Nodo Uruguay y la consulta independiente al proveedor para el mismo período (diciembre de 2025 a junio de 2026) coincidieron en 532.454 vistas y 84.344 descargas (dashboard `258939e`).

- El comparador de cosechas muestra el aviso y mantiene la tabla cerrada si el enlace contiene tres identificadores. Desde ese estado se puede elegir una pareja válida. También se comprobó que recupera una pareja guardada cuando desaparece la página original y hay que reintentar la consulta de una cosecha (dashboard `6dd2b30`).

- El dashboard recupera comparaciones por enlace directo, busca fuentes autorizadas y pagina las frecuencias de cada regla en SQLite. La fuente QAMIX permite verificar registros válidos e inválidos en una misma cosecha con y sin captura de ocurrencias. [Contrato v5](docs/HARVESTER_MANAGEMENT_API_V5.md) · [Casos de prueba](testing/dashboard-validation/README.md)

- El motor, el shell y la API v5 reconocen los nombres históricos de las reglas de validación y transformación, incluso cuando un transformador contiene un validador. Los perfiles instalados cargan directamente con su JSON original. Si se solicita la migración desde el shell, se actualizan las referencias de clase y se conservan los textos de diccionarios, expresiones y descripciones.

- Las expresiones de campo respetan el cuantificador guardado en el perfil. Los transformadores de traducción y alta condicional publican todas las modificaciones realizadas, la limpieza elimina también los elementos XML vacíos y el reemplazo por expresión regular solo cuenta un identificador como transformado cuando cambia su valor.

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

- La guía de configuración del dashboard explica cómo activar y desactivar Cosechas, Validaciones y Estadísticas, aplicar los cambios a los tres idiomas y asignar a cada repositorio su identificador del proveedor de estadísticas (dashboard `a6b6be6`).

- En el dashboard se separaron la búsqueda de repositorios de la navegación y la selección de las dos cosechas de su presentación. La tabla del historial gestiona su paginación y su CSV. Se retiraron funciones de validación sustituidas, se documentaron en inglés las decisiones de compatibilidad y se organizaron las pruebas por funcionalidad.

- El cliente del dashboard comparte la validación de respuestas paginadas y conserva las reglas, los contadores y los campos opcionales de snapshots históricos. La comparación con el cliente anterior dio el mismo resultado en 56 casos, incluidos datos de PA y AREANDINA. Con Node 22.14.0 pasaron las 52 pruebas y se compiló el dashboard en español, inglés y portugués (dashboard `e14bdac`).

- `FieldAddRule` permite omitir desde el admin un valor fijo que ya esté presente en el campo. Los perfiles existentes siguen agregándolo en cada pasada. La escritura de campos XOAI con rutas simples y únicas requiere menos tiempo. [Configuración y mediciones](docs/VALIDACION_COMPATIBILIDAD.md#alta-de-un-valor-fijo)

- `AddRepoNameRule` necesita menos consultas XPath para crear la ruta de destino o conservar los tres nombres en un campo compartido. Los perfiles existentes mantienen sus prefijos, el orden de escritura y el reemplazo de la última coincidencia. [Mediciones y casos de compatibilidad](docs/VALIDACION_COMPATIBILIDAD.md#nombres-de-repositorio-e-institución)

- La traducción de campos por prioridad evita repetir consultas XPath en las entradas del diccionario que dejan el registro intacto. Los perfiles existentes conservan el orden de prioridad, las traducciones encadenadas y el comportamiento al detenerse en la primera coincidencia. [Mediciones y casos de compatibilidad](docs/VALIDACION_COMPATIBILIDAD.md#traducción-por-prioridad)

- La regla de procedencia (`AddProvenanceMetadataRule`) reduce el tiempo y la memoria necesarios para escribir campos de repositorio en el XML XOAI. Los perfiles instalados se aplican con su JSON original y siguen publicando los campos vacíos en el mismo orden. [Mediciones y casos de compatibilidad](docs/VALIDACION_COMPATIBILIDAD.md#metadatos-de-procedencia)

- El renombre masivo de campos reutiliza el resultado de la búsqueda del campo de destino al añadir cada valor. Los perfiles existentes conservan sus mapeos encadenados, las repeticiones y el orden de las ocurrencias XML. [Mediciones y casos de compatibilidad](docs/VALIDACION_COMPATIBILIDAD.md#renombre-masivo-de-campos)

- Los transformadores de limpieza reducen los recorridos del XML al eliminar campos y resolver duplicados. El validador de vocabulario único reúne las coincidencias y su diagnóstico en el mismo recorrido. Los perfiles instalados conservan la prioridad configurada, el orden de los valores y el tratamiento de las repeticiones. [Ejemplos de compatibilidad](docs/VALIDACION_COMPATIBILIDAD.md#casos-de-compatibilidad-en-limpieza-y-vocabularios)

- El validador de expresiones y el transformador por regex compilan el patrón una sola vez por comparación o por registro, respectivamente. El transformador reutiliza también la selección XPath original. La limpieza de espacios escribe en el XML solo cuando cambia el valor. Estas mejoras se aplican a los perfiles instalados con su configuración actual.

- El motor construye el índice de cada vocabulario grande en su primera consulta y lo reutiliza para todos los registros y páginas de esa ejecución. Cada ejecución simultánea mantiene su propio índice. En Java 21, los índices del perfil de Nodo Central añadieron unos 313 KiB en total (310,1 KiB para idiomas y 3,1 KiB para formatos), con el mismo tamaño tras 20.000 consultas. Los perfiles conservan el CSV original y la coincidencia exacta de términos. [Medición con los vocabularios de Nodo Central](docs/VALIDACION_COMPATIBILIDAD.md#consultas-a-vocabularios-grandes)

- La guía de perfiles detalla cómo se evalúa cada cuantificador ante un campo ausente o con varios valores. Con `ALL`, una regla de contenido admite un campo ausente y una regla XPath requiere al menos una ocurrencia seleccionada. [Presencia y cardinalidad por familia de reglas](docs/VALIDACION_COMPATIBILIDAD.md#presencia-y-cardinalidad-por-familia-de-reglas)

- **Título en Nodo Central.** El perfil distribuido incorpora `Title — Presence` para exigir al menos un título con contenido. Los perfiles ya instalados conservan sus reglas. Cada administrador puede añadir la regla desde **Validadores → Reglas → Añadir regla**, conservando la regla `Title` existente. [Instrucciones y valores de configuración](docs/VALIDACION_COMPATIBILIDAD.md#añadir-la-regla-de-presencia-de-título-desde-el-admin)

- **Primera validación tras actualizar.** Cada red vuelve a procesar su catálogo activo y conserva sus informes históricos. Las redes con reglas de año dinámico también se recalculan al cambiar el año. La comprobación de URL usa tiempos de espera configurables, con valores iniciales de 5 segundos para conectar y 10 para leer. [Efectos por regla](docs/VALIDACION_COMPATIBILIDAD.md#efectos-al-actualizar)

- **Opciones de transformación.** La nueva regla `ReduceRecordsBySizeRule` permite eliminar campos cuando el XML supera un umbral en bytes UTF-8. Las reglas de renombre de campos permiten procesar todas las ocurrencias con `processAllOccurrences`. Los perfiles existentes conservan el límite de 101 ocurrencias y el comportamiento de `ReduceHeavyRecords`. [Configuración y reversión](docs/VALIDACION_COMPATIBILIDAD.md#opciones-de-transformación-y-reversión)

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
