# Changelog

Los cambios relevantes de la plataforma se registran aquí antes de publicarse.
Al preparar una release, mover las entradas incluidas de `Unreleased` a una
sección con su versión y fecha, y conservar `Unreleased` para nuevos cambios.

## Unreleased

### Correcciones

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

- La limpieza de metadatos huérfanos abre los catálogos protegidos y aborta antes
  de escanear o borrar si falla la lectura o si no se carga ninguna referencia
  protegida (core-lib).
  ([core-lib #23](https://github.com/lareferencia/lareferencia-core-lib/pull/23),
  [plataforma #114](https://github.com/lareferencia/lareferencia-platform/pull/114))

- Corrige la copia de recursos estáticos al construir la imagen Docker del
  proveedor OAI-PMH: utiliza el directorio `static/` en lugar de `static_en/`.
  ([#112](https://github.com/lareferencia/lareferencia-platform/pull/112))

### Cambios

- El perfil de exportación para clasificación contempla todas las variantes DC
  configuradas (shell `d87a859`).
