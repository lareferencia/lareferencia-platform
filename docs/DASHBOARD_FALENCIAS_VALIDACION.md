# Falencias de los informes y registro de evidencias

Evaluación del 19 de noviembre de 2026. Alcance, versiones, arquitectura y contratos en el [contexto técnico](DASHBOARD_CONTEXTO_TECNICO.md). Las prioridades propuestas reflejan el efecto sobre la interpretación del informe. «Reproducido» significa que se ejecutó la ruta Java indicada con SQLite local. «Por código» identifica un comportamiento leído en fuentes. «Pendiente» señala el experimento que falta. Las prioridades y criterios de aceptación se proponen para el relevo.

El [plan de consolidación](DASHBOARD_PLAN_CONSOLIDACION.md) registra la corrección local de F1–F3. La [verificación de etapa 2](DASHBOARD_ETAPA_2_EVIDENCIAS.md) actualiza F4, F6 y F10 con resultados sobre copias de Docker. E1 conserva la medición inicial para comparación.

## F1 · Alta · Cuatro filtros compatibles devuelven registros de más

**Reproducido.** El método `records` del adaptador transforma los parámetros públicos en `isValid`, `isTransformed`, `validRulesID` e `invalidRulesID`. El repositorio interpreta `is_valid`, `is_transformed`, `valid_rules` e `invalid_rules` y omite campos desconocidos. El identificador sí se traduce a un campo reconocido. Un usuario que selecciona «falla esta regla» puede recibir una página y un total que incluyen registros aprobados. El hallazgo afecta al endpoint compatible `/records`. El endpoint hermano de observaciones recibe las expresiones por otra vía. [Controlador, método records](../lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/api/v5/ApiV5DashboardCompatibilityController.java) · [Repositorio, método applyFilters](../lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/validation/RecordValidationRepository.java)

**Cierre verificable.** Con el juego de datos E1, cada uno de los cuatro filtros debe seleccionar solo la fila correspondiente, con `totalElements=1`. Para `is_valid=true` combinado con `invalid_rules=7`, la colección y el total deben estar vacíos. Comprobarlo por HTTP con el nombre público preservado y una consulta sin filtros como control. En la revisión del legacy, registrar si cada pantalla usa `records` u observaciones antes de estimar usuarios afectados.

## F2 · Alta · Frecuencias de valores fuera del conjunto filtrado

**Reproducido.** La pantalla pasa sus filtros al diálogo por regla. El servicio nativo traduce y entrega esa lista al servicio de estadísticas. El método `queryValidRuleOccurrencesCountBySnapshotID` consulta el repositorio solo con snapshot y regla. La consulta cuenta ocurrencias de registros activos de todo el snapshot. En E1, el resumen y la tabla seleccionaron solo A, pero el diálogo también contaría el valor rechazado de B. La compatibilidad ofrece listas globales por regla sin parámetro de filtro. [Diálogo OccurrencesDialog](../lareferencia-lrharvester-admin-web/src/features/diagnostics/DiagnosticsPage.tsx) · [Servicio SQLite, método queryValidRuleOccurrencesCountBySnapshotID](../lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatisticsSQLiteService.java) · [Agregación de valores](../lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/validation/RuleOccurrenceRepository.java)

**Cierre verificable.** El producto debe especificar el alcance que muestra al abrir la regla. Para frecuencias filtradas, E1 con `VALID=true` debe devolver únicamente `es × 1`. La consulta global debe conservar ambas listas. Añadir un registro con dos valores diferentes y otro con valor repetido para comprobar que se cuentan ocurrencias. No deducir frecuencias a partir de una página de registros.

## F3 · Media · La igualdad de identificador admite coincidencias parciales

**Reproducido.** `EQ` y `CONTAINS` llegan a la misma condición de búsqueda parcial en SQLite. En E1 ambos devuelven A y B para `oai:1`. El buscador del admin pide explícitamente `CONTAINS`, por lo que allí el resultado es coherente. El problema afecta al consumidor que elige igualdad, por ejemplo, para localizar un registro inequívoco. El endpoint XML hace una búsqueda propia por identificador. [Traducción de operadores](../lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/api/v5/ApiV5DiagnosticsService.java) · [Búsqueda y lectura por identificador](../lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/validation/RecordValidationRepository.java)

**Cierre verificable.** Definir el contrato de igualdad, mayúsculas y caracteres literales para identificadores OAI. Sobre E1 exigir una coincidencia exacta con EQ y dos parciales con CONTAINS en registros y resumen. Mantener la búsqueda parcial del admin.

## F4 · Alta · Consultas históricas dependen del validador vigente

**Reproducida la discrepancia de esquema.** El resumen sin filtros lee el JSON generado al finalizar. Para la consulta filtrada se reconstruye `SnapshotMetadata` a partir de la red asociada al snapshot y de sus reglas actuales. El servicio registra esos IDs para leer SQLite y el agregado construye columnas a partir de ellos. En E1, después de añadir la regla 8 a los metadatos que devuelve el almacén, la misma consulta filtrada pasó de un registro a una excepción 422. La base histórica solo contenía la columna de la regla 7. La edición desde el admin y la persistencia JPA quedan pendientes de comprobar en conjunto. [Construcción de metadatos](../lareferencia-core-lib/src/main/java/org/lareferencia/core/metadata/SnapshotMetadata.java) · [getSnapshotMetadata](../lareferencia-core-lib/src/main/java/org/lareferencia/core/metadata/SnapshotStoreSQLImpl.java) · [Construcción del agregado](../lareferencia-core-lib/src/main/java/org/lareferencia/core/repository/validation/RecordValidationRepository.java)

**Cierre verificable.** Crear y finalizar S1 con regla 7. Añadir la 8, renombrar la 7 y luego retirar o reemplazar el validador. Volver a S1 después de cada cambio. Comparar resumen global y filtrado, reglas y valores del detalle, nombres, obligatoriedad y cuantificador. Deben conservar la semántica con que se validó S1. Repetir con un snapshot anterior a los manifiestos y un hijo incremental. Revisar si las definiciones guardadas en el resumen histórico bastan para leer informes antiguos.

## F5 · Decisión previa de arquitectura · Acceso del usuario DASHBOARD

**Por código y con prueba unitaria de roles.** El diagnóstico nativo exige un rol admitido por la cadena v5. DASHBOARD tiene acceso al adaptador y a su sesión. READER y las cuentas técnicas quedan fuera del adaptador. El gateway de desarrollo para el host dashboard admite los recursos de sesión y lecturas del adaptador, y responde 404 al resto de v5. Por ello copiar el cliente de `DiagnosticsPage` al nuevo dashboard impediría sus consultas incluso si la interfaz carga. El adaptador carece además de un equivalente directo para XML y logs. La prueba de roles ejecutada usa el servicio de autorización. La verificación HTTP vía gateway sigue pendiente en el plan existente. [Seguridad Spring](../lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/app/WebSecurityConfig.java) · [Autorización](../lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/security/LocalAuthorizationService.java) · [Gateway](../Docker/nginx/dev-dashboard-gateway.conf) · [Plan de integración](DASHBOARD_V5_MIGRATION.md)

**Decisión de producto.** Acordar qué operaciones de lectura requiere el perfil DASHBOARD, incluido XML, y qué contrato las atenderá. Preservar la asignación por red. Verificar con una sesión por rol ADMIN, DASHBOARD y READER y una identidad técnica, a través de cada host. Para cada recurso acordado comprobar red asignada, ajena, acrónimo incoherente, sesión vencida y rechazo de operaciones de administración. Registrar ruta, método, rol, estado y alcance devuelto. El test directo al servicio no verifica proxies, cookies ni filtros HTTP.

## Riesgos adicionales antes de reutilizar la pantalla

| ID y evidencia | Consecuencia observable o posible | Cómo resolver la incertidumbre |
|---|---|---|
| F6 · Por código. El detalle de valores depende de dos opciones durante la captura. El DTO de frecuencias ofrece listas y la UI muestra un estado vacío. El test de lectura conserva el resultado de regla aun sin valores. | La persona que revisa una regla fallida no puede distinguir detalle omitido de ausencia de valores almacenados. El marcador sintético de campo ausente también puede mostrarse como un valor. | Comparar la misma regla con captura completa, captura desactivada globalmente, regla sin captura y campo ausente. Identificar qué estados puede conocer el backend para snapshots históricos y qué texto admite cada uno. [Captura](../lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatisticsSQLiteService.java) · [Test de lectura](../lareferencia-core-lib/src/test/java/org/lareferencia/core/service/validation/ValidationStatisticsSQLiteReadTest.java) |
| F7 · Por código. Si falla la consulta de registros, la página usa una lista vacía por defecto y solo pasa el indicador de carga a la tabla. Resumen y XML sí tratan errores explícitamente. | Un error de lectura puede aparecer como «sin registros» y ocultar el motivo. | Simular un fallo solo en registros y comparar con una consulta válida de cero filas. La interfaz debe diferenciar ambos resultados y permitir reintentar conservando los filtros. [DiagnosticsPage, Records](../lareferencia-lrharvester-admin-web/src/features/diagnostics/DiagnosticsPage.tsx) |
| F8 · Por código. El cliente pide la primera página de 100 snapshots. La selección automática busca allí un VALID activo. Un ID explícito en la URL tiene precedencia aunque no figure en la lista. | Puede faltar un histórico consultable. Un enlace con red A y snapshot de B podría rotular datos de B con el nombre de A si el usuario tiene permiso para ambas. El servicio nativo comprueba permisos sobre B. | Probar 101 snapshots, uno válido fuera de la primera página, enlace a uno borrado y enlace cruzado entre dos redes autorizadas. El encabezado, resumen y detalle deben referirse al mismo snapshot verificado. [Cliente](../lareferencia-lrharvester-admin-web/src/api/client.ts) · [Selección](../lareferencia-lrharvester-admin-web/src/features/diagnostics/DiagnosticsPage.tsx) |
| F9 · Por código, coste pendiente de medición. La búsqueda actualiza las consultas al teclear. Cada página convierte registros cargando sus ocurrencias individualmente. El diálogo abre la consulta de XML al seleccionar el registro. El agregado filtrado recorre en Java los conteos por regla después de obtenerlos en SQL. | El trabajo crece con el número de consultas, resultados y reglas. Falta evidencia de latencia en tamaños representativos. | Medir con snapshots pequeños y grandes, caché fría/caliente, mismos filtros. Registrar tamaño, reglas, filas, sentencias SQL por página y p50/p95 para resumen, página, frecuencias y XML antes de priorizar optimizaciones. [Servicio SQLite](../lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatisticsSQLiteService.java) · [Pantalla](../lareferencia-lrharvester-admin-web/src/features/diagnostics/DiagnosticsPage.tsx) |
| F10 · Por código. Al reconstruir la observación desde SQLite se pasan valores nulos para set, institución y nombre de repositorio. Su constructor fija la fecha de validación al momento de crear la observación. El DTO nativo de registro omite esa fecha. | Un cliente de observaciones compatible podría mostrar una fecha de lectura como fecha de validación. En listados históricos pueden faltar campos que el contrato admite. | Leer dos veces la misma observación histórica y capturar el JSON real de cada superficie. Verificar cada campo contra una fuente y snapshot conocidos. Para gráficas temporales acordar si se usa fin del snapshot u otra fecha persistida. [Proyección SQLite](../lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatisticsSQLiteService.java) · [Observación](../lareferencia-core-lib/src/main/java/org/lareferencia/core/service/validation/ValidationStatObservation.java) |

## E1 · Experimento repetible con SQLite

La [sonda Java](evidencias/dashboard/ConsultaValidacion.java) invoca los controladores compatible y nativo, el servicio de diagnóstico y las implementaciones de estadísticas y repositorios SQLite del checkout. Usa una base temporal real. Simula la resolución de snapshots y la autorización con Mockito. La sonda imprime las respuestas para comparar versiones. Su salida correcta como proceso significa que completó las consultas, incluso cuando observa una discrepancia. El alcance se limita a llamadas Java. El binding HTTP, la serialización, JPA, el navegador y Nginx quedan fuera del experimento.

| Registro del snapshot 4145 | Validez global | Transformado | Regla 7 | Ocurrencia |
|---|---|---|---|---|
| A · `oai:1` | Sí | No | Aprueba | `es` válida |
| B · `oai:10` | No | Sí | Falla | `?` inválida |

| Solicitud lógica | Resultado esperado según la selección | Observado el 19-11-2026 |
|---|---|---|
| Compatible, cuatro llamadas independientes: `is_valid=true`, `is_transformed=true`, `valid_rules=7`, `invalid_rules=7` | Un registro por llamada, respectivamente A, B, A y B | Totales 2, 2, 2, 2 |
| Nativa, resumen y registros con `VALID EQ true` | 1 y 1 | 1 y 1 |
| Nativa, frecuencias de regla 7 con ese filtro | Válidas: es × 1. Inválidas: ninguna | Válidas: es × 1. Inválidas: ? × 1 |
| Nativa, identificador `oai:1`, EQ y CONTAINS | 1 y 2 | 2 y 2 |
| Nativa, mismo resumen filtrado tras incorporar a los metadatos la regla 8 ausente en la base | El snapshot histórico conserva su resultado de 1 | Excepción de estado 422, mensaje `Error calculating aggregated stats` |

### Ejecución y cobertura verificada

Desde la raíz de plataforma en los commits indicados, con las dependencias Maven disponibles. El JDK usado fue 21.0.9. El primer comando compila los módulos pertinentes y genera el classpath real en el reporte de Surefire. Se puede omitir `-o` para preparar una caché Maven nueva.

```sh
mvn -o -q -Plareferencia -pl lareferencia-lrharvester-app -am -Dno-frontends \
  -Dtest=ValidationStatisticsSQLiteReadTest,IncrementalValidationLifecycleTest,ApiV5DiagnosticsServiceTest,ApiV5DashboardCompatibilityControllerTest,WebSecurityConfigTest,LocalAuthorizationServiceRoleTest \
  -Dsurefire.failIfNoSpecifiedTests=false test
python3 - <<'PY'
from pathlib import Path
import subprocess, tempfile, xml.etree.ElementTree as ET
reports = Path("lareferencia-lrharvester-app/target/surefire-reports")
report = next(reports.glob("TEST-*ApiV5DiagnosticsServiceTest.xml"))
cp = ET.parse(report).find(".//property[@name='java.class.path']").get("value")
with tempfile.TemporaryDirectory() as directory:
    raise SystemExit(subprocess.run(["java", "-cp", cp, "docs/evidencias/dashboard/ConsultaValidacion.java", directory]).returncode)
PY
```

| Grupo ejecutado | Resultado | Alcance real |
|---|---|---|
| Core · ValidationStatisticsSQLiteReadTest / IncrementalValidationLifecycleTest | 3 + 8 pasaron | Lectura con BD abierta y reabierta, regla con detalle ausente, herencia, bajas, cambio de registro, cancelación y finalización |
| Harvester · ApiV5DiagnosticsServiceTest / ApiV5DashboardCompatibilityControllerTest | 2 + 5 pasaron | Traducción de filtros nativos, listado con permisos, denegación, acrónimo y nombres JSON. Las pruebas del adaptador usan servicio estadístico simulado |
| Seguridad · WebSecurityConfigTest / LocalAuthorizationServiceRoleTest | 3 + 1 pasaron | CSRF y autorización de roles del adaptador a nivel de método |
| Admin · client / problem-detail / session-expiration / config / language-switch | 11 pasaron en 5 archivos | Cliente, errores, sesión, configuración e idioma. El renderizado de DiagnosticsPage y el recorrido HTTP quedan pendientes |

Comando del frontend, desde el módulo admin-web con dependencias instaladas:

```sh
./node/node node_modules/vitest/vitest.mjs run src/api/client.test.ts src/api/problem-detail.test.ts src/auth/session-expiration.test.tsx src/app/config.test.ts src/i18n/language-switch.test.tsx
```

### Relevo para la lectura del dashboard anterior

Al recorrer el legacy, anotar para cada pantalla la ruta de entrada, el rol real, el endpoint y parámetros emitidos, el campo que alimenta cada indicador, su denominador y su comportamiento con error, cero registros y detalle ausente. Registrar si la pantalla consume el adaptador de registros o el de observaciones. Contrastar los recorridos con F1–F10 y anotar qué fallas alcanzan hoy al usuario y cuáles afectarían únicamente a un diseño nuevo. Mantener el historial de cosecha y las estadísticas externas identificados por su fuente. La decisión de reutilizar el diagnóstico nativo queda supeditada al contrato de lectura y al gateway descritos en F5.
