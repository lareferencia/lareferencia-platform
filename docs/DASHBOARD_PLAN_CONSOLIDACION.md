# Plan de consolidación del admin-ui y las APIs del harvester

Relevo del 19 de noviembre de 2026 · Rama coordinada `codex/rc5-pre`. Las etapas 1 y 2 están implementadas y probadas en el workspace. La etapa 2 actualiza también el tipo del resumen en admin-web. La etapa 1 abarca tres repositorios Git independientes: plataforma (plan, documentación y changelog), core-lib (consultas SQLite) y lrharvester-app (adaptador, operadores y regresiones). El lock de plataforma fija las versiones previas. Al preparar la integración, incluir los cambios de ambos módulos y actualizar el lock mediante el flujo coordinado.

El [contexto técnico](DASHBOARD_CONTEXTO_TECNICO.md) explica los contratos y el significado de cada métrica. El [registro de evidencias](DASHBOARD_FALENCIAS_VALIDACION.md) conserva el comportamiento anterior, las fuentes y los experimentos F1–F10. El estudio funcional del dashboard Angular sigue siendo una entrada pendiente para decidir qué pantallas y permisos conservar.

## Etapa 1 · Exactitud de consultas · Verificada localmente

| Hallazgo | Comportamiento implementado | Evidencia |
|---|---|---|
| F1 · Filtros de registros compatibles | El adaptador traduce los cuatro parámetros públicos al vocabulario SQLite. Los filtros se combinan con AND antes de contar y paginar. | MockMvc comprueba las filas, los totales, una página posterior a la primera y una combinación sin coincidencias. |
| F2 · Frecuencias por regla | La consulta de frecuencias aplica los mismos predicados sobre el registro activo que el resumen y la tabla. Sigue contando cada valor registrado, con su propia validez, incluidos los repetidos. Sin filtros devuelve las frecuencias globales de la regla. | Una fila válida aporta dos ocurrencias aprobadas y una rechazada. Otro registro y una baja comprueban la exclusión. |
| F3 · Identificador OAI | En v5 nativa, EQ y el operador omitido buscan el identificador completo con comparación sensible a mayúsculas. CONTAINS busca una subcadena literal, manteniendo el comportamiento de LIKE de SQLite respecto de mayúsculas ASCII. Los símbolos de patrón SQL se tratan como parte del valor. El parámetro compatible conserva su búsqueda histórica. | Casos prefijo/completo, mayúsculas, comillas, separador interno y símbolos de LIKE. El resumen y la página devuelven los mismos totales. |

### Repetir la verificación

Desde la raíz de plataforma con los módulos del workspace y sus cambios locales:

```sh
mvn -Plareferencia -pl lareferencia-lrharvester-app -am -Dno-frontends \
  -Dtest=ValidationStatisticsSQLiteReadTest,IncrementalValidationLifecycleTest,ApiV5DiagnosticsSQLiteTest,ApiV5DiagnosticsServiceTest,ApiV5DashboardCompatibilityControllerTest \
  -Dsurefire.failIfNoSpecifiedTests=false test
```

Resultado local: **31 casos aprobados** en esas cinco clases, incluidos 13 de la [nueva regresión MockMvc + SQLite](../lareferencia-lrharvester-app/src/test/java/org/lareferencia/backend/api/v5/ApiV5DiagnosticsSQLiteTest.java). La prueba ejerce binding HTTP, controladores, servicios, SQL y serialización JSON, con resolución de snapshots y autorización simuladas. La validación a través del gateway y con sesiones reales corresponde a la etapa 3.

También se comprobó una copia temporal de la base y su WAL de `AREANDINA/snapshots/snapshot_6/validation`, en el volumen de desarrollo de Docker. SQLite informó integridad correcta. Había **4.000 registros activos**. Aplicando el filtro «aprueba la regla 5», tanto la página compatible como el resumen y la página nativos devolvieron **1.871** como total. Para la regla 10, la suma de las frecuencias en esa selección fue **7.623** de **9.971** ocurrencias globales. La búsqueda EQ de un identificador recuperado de esa página devolvió un registro. Los valores dependen de esa copia local. La suite automatizada usa una base temporal independiente.

Consultas de control para comparar contra las respuestas de la aplicación:

```sql
SELECT COUNT(*) FROM record_validation WHERE deleted = 0 AND rule_5 = 1;
SELECT COUNT(*) FROM rule_occurrences o
JOIN record_validation v ON v.identifier_hash = o.identifier_hash
WHERE v.deleted = 0 AND v.rule_5 = 1 AND o.rule_id = 10;
```

## Etapa 2 · Integridad histórica y significado del detalle · Verificada localmente

La [reproducción y los resultados de F4, F6 y F10](DASHBOARD_ETAPA_2_EVIDENCIAS.md) incluyen el antes/después por HTTP, la copia de Docker utilizada y los casos de históricos incompletos. Los criterios siguientes definen el alcance verificado.

- **F4.** Finalizar S1 con una regla, editar el validador desde la API y recargar el snapshot desde JPA. Repetir con regla añadida, renombrada, retirada y con sustitución del validador. Determinar cómo leer los IDs, nombres, cuantificadores y obligatoriedad vigentes al finalizar S1. Verificar contra el esquema SQLite y el resumen persistido antes de elegir un formato adicional.
- **F6.** Definir los estados que se pueden distinguir al consultar ocurrencias para una regla: detalle guardado, captura desactivada y disponibilidad desconocida en datos históricos. Incluir campo ausente y regla sin almacenamiento de valores.
- **F10.** Trazar el origen de fechas y atributos de la observación compatible. Contrastar dos lecturas del mismo snapshot y establecer qué fecha persistida se mostrará en el informe.
- **Cierre.** El snapshot conserva cifras y definiciones al consultar resumen global, filtrado, registros y valores después de editar su validador. Cubrir un histórico antiguo y un hijo incremental con bajas. La interfaz debe poder comunicar las limitaciones de evidencia de cada uno.

## Etapa 3 · Contrato de lectura y permisos · Diferida por prioridad del admin

Para F5, la propuesta es mantener el adaptador bajo `/api/v5/dashboard` y compartir la implementación de consultas con diagnóstico nativo. Inventariar las necesidades de las pantallas actuales, acordar el acceso al XML publicado y decidir por separado si el perfil dashboard requiere logs. Documentar ruta, método, rol y ámbito por red de cada operación acordada.

**Cierre.** Probar a través de los hosts admin y dashboard con ADMIN, DASHBOARD, READER, cuenta técnica y sesión ausente o vencida. Incluir red asignada y ajena, discrepancia acrónimo/snapshot, CSRF de consultas POST y rechazo de operaciones administrativas en el host dashboard. Registrar las respuestas del gateway y del backend.

## Etapa 4 · Recorridos del admin-ui · Verificación local

Se adelantó esta etapa por prioridad del admin. El [informe de verificación funcional](ADMIN_UI_VERIFICACION.md) registra las correcciones de F6–F9 en la interfaz, dos fallos de sesión y permisos, las pruebas en Chrome contra una copia de Docker y las operaciones pendientes para el cierre transversal. Los criterios del plan se conservan a continuación.

- **F7.** Diferenciar fallo parcial, carga y cero coincidencias. Permitir reintento de la tabla conservando filtros y página.
- **F8.** Seleccionar el último snapshot válido independientemente de la primera página. Paginar todo el historial. Validar pertenencia de los enlaces profundos y coherencia entre cabecera, resumen y registros.
- **F6/F9.** Aplicar las decisiones sobre detalle ausente, solicitar el XML al abrir su pestaña y ajustar la búsqueda según las peticiones medidas.
- **Cierre.** Prueba en navegador del recorrido red → snapshot → filtro → regla → ficha → XML. Verificar vuelta atrás, recarga, enlace directo y error recuperable. Incluir una red con más de 100 snapshots, una sin validaciones y un enlace con red y snapshot incoherentes.

## Etapa 5 · Regresión transversal y rendimiento · En curso

Se comprobó en el admin el estado terminal de las cosechas completas, la cancelación y las acciones por lote sobre datos copiados de Docker. El [registro de operaciones](ADMIN_UI_OPERACIONES.md) conserva la reproducción del rechazo parcial, la corrección y las comprobaciones sobre snapshots, ejecuciones y SQLite.

La acción «Indexar en el buscador» quedó verificada desde Chrome. Los 3.444 identificadores del snapshot PA #4 coincidieron con Solr y el índice persistió tras reiniciar el servicio. [Evidencia y reproducción](ADMIN_UI_INDEXACION.md)

Se puede iniciar el inventario y tomar medidas de referencia mientras avanzan las etapas anteriores. Cruzar controladores, consumidores y OpenAPI. Registrar para cada familia los métodos, contratos de error, paginación, roles y ámbito: sesión/usuarios, redes/snapshots, validadores/transformadores/reglas, acciones/comandos/runtime, transferencias y dARK. En una instalación desechable probar éxito, entrada inválida y permiso denegado. En comandos asíncronos verificar también el estado final de ejecución.

Para F9, medir resumen libre y filtrado, registros, frecuencias y XML en snapshots representativos. Registrar registros y reglas por snapshot, captura de detalle, peticiones y sentencias por página, latencias p50/p95 y estado de caché. Usar esa línea base para decidir si optimizar carga de ocurrencias, agregados o frecuencia de peticiones.

**Cierre del plan.** Para cada F1–F10, vincular caso reproducible, evidencia posterior y commits integrados. Pasar las pruebas de backend, frontend y gateway de la combinación fijada en el lock. Registrar aparte cualquier decisión funcional que permanezca pendiente.
