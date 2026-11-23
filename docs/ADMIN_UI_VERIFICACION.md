# Verificación funcional del admin-ui

**19 de noviembre de 2026 · Rama coordinada `codex/rc5-pre` · Cambios locales de admin-web, harvester y core-lib.** El diagnóstico histórico, la sesión, la navegación y los recorridos de la tabla se comprobaron con Chrome y el harvester del workspace. La publicación de una versión requiere integrar los cambios de los módulos y actualizar el lock. El plan mantiene en pausa el estudio del dashboard anterior. [Plan de consolidación](DASHBOARD_PLAN_CONSOLIDACION.md)

## Fallos y evidencia posterior

| Hallazgo | Qué podía observar el operador | Comprobación tras la corrección |
|---|---|---|
| F1–F4 y F10 | Filtros ignorados en compatibilidad, frecuencias fuera de la selección, igualdad parcial, reglas históricas dependientes del validador actual y fecha de lectura presentada como fecha de validación. | Se repitieron las regresiones Java sobre SQLite. En Chrome, AREANDINA #6 mostró 4.000 registros y el filtro «falla la regla 5» devolvió 2.129 tanto en la tabla como en el resumen. La edición histórica del validador por HTTP está registrada en la [etapa 2](DASHBOARD_ETAPA_2_EVIDENCIAS.md). |
| F6 · Detalle de valores | La pantalla confundía una lista vacía con captura omitida, y la obligatoriedad desconocida aparecía como opcional. | Regresiones con captura activada, desactivada y desconocida. El diálogo conserva las frecuencias si hay evidencia histórica y explica los vacíos. El detalle de registro identifica el marcador de campo ausente. Una obligatoriedad sin definición se muestra como desconocida. |
| F7 · Error parcial | Un fallo de la tabla se mostraba como cero coincidencias aunque el resumen sí hubiera cargado. | Chrome recibió un 503 inducido únicamente en la consulta de registros. Mostró el error y el botón de reintento. Al retirar el fallo, la misma página y los mismos filtros devolvieron registros reales. Vitest cubre también una respuesta correcta vacía. |
| F8 · Snapshot y fuente | La selección automática buscaba en los primeros 100. La cabecera podía identificar una red y las filas corresponder a otra. | La entrada automática consulta el último válido de la red. El enlace explícito verifica la red y la marca de borrado antes de montar el informe. Prueba de componente con 100 históricos recientes y el válido en la segunda página. Chrome comprobó enlace correcto, cruce de dos redes accesibles al administrador y fuente nueva sin snapshots. El selector, el historial de cosechas y el panel de resultados de indexación admiten páginas sucesivas. |
| F9 · Peticiones desde la interfaz | Cada tecla disparaba consultas y la apertura de la ficha solicitaba el XML aunque se estuviera leyendo la validación. | Se adoptó búsqueda explícita con **Buscar** o **Enter**. En Chrome, teclear `oai:` produjo cero peticiones de diagnóstico. Enviar produjo un resumen y una página de registros. Abrir la ficha produjo cero peticiones de XML. Al abrir **XML publicado** llegó un 200 con 5.816 bytes en el registro probado. La API usa el hash publicado que conserva el registro. |
| Sesión y enlaces directos | Una recarga llevaba al login mientras `GET /me` aún estaba pendiente, incluso con cookie válida y posterior respuesta 200. | Se espera a resolver la sesión antes de montar el router. Regresión con respuesta diferida y navegación real por URL directa, recarga y Atrás. Después de cerrar sesión volvieron el 401 y el login. |
| Vista de lector | La lista pedía `/capabilities`, reservado a ADMIN. Spring denegaba el acceso a nivel de método y el manejador genérico lo convertía en un 500. | Con READER, la lista de fuentes carga sin pedir el catálogo. Una petición directa de comprobación devuelve 403 con código `FORBIDDEN`. Se añadieron regresiones en el listado React y en el manejo HTTP de la excepción de Spring. |

## Recorridos sobre una copia de Docker

El PostgreSQL 14 de la prueba arrancó con una copia del clúster detenido en `Docker/volume/dev/lareferencia-dev/lareferencia/postgres/data/pgdata`. También se copiaron `lrharvester-app/config` y `lrharvester-app/data`, incluidos SQLite, WAL y almacén de metadatos. Se desactivó el cron de las redes copiadas. El harvester sirvió el bundle de producción de admin-web, con motor de tareas local y sesión real, por HTTP en loopback. Se creó un administrador temporal y, desde la interfaz, un lector limitado a AREANDINA. La entrada fue el puerto de Spring. Estas pruebas acreditan el flujo del admin y la API nativa. La prueba de Nginx queda diferida.

| Área | Recorrido observado en Chrome | Resultado |
|---|---|---|
| Fuentes | Abrir listado, alta y editor. Crear una fuente sin cron con URL de prueba, editar su nombre y recargar. Exportar XLSX, conservar la fila de la fuente temporal, validar e importar en modo UPSERT. | Alta 201, edición 200 y nombre persistido. Validación 200 con una fila válida y cero inválidas. Aplicación 200 con una actualización. |
| Historial y diagnóstico | Desde la fila AREANDINA abrir historial y bitácora, volver a la fila y pulsar diagnóstico. Consultar resumen, página, regla, ficha y XML. Recargar y volver atrás tras una búsqueda. | Bitácora 200 con 100 entradas en la página devuelta. Snapshot 6, 4.000 registros. Frecuencias 200. La búsqueda sobrevivió a la recarga y Atrás restituyó el filtro anterior. |
| Pertenencia y vacíos | Como ADMIN, abrir `/admin/networks/33/diagnostics?snapshot=1`. Abrir también el informe de la fuente nueva. | Enlace cruzado señalado como no disponible antes de pedir resumen o registros. La fuente nueva recibió 404 del último válido y mostró el estado sin snapshot. |
| Validadores y transformadores | Abrir ambos listados, cargar sus respectivos editores del ID 1, crear una configuración de cada clase, renombrarla y recargar el editor. | Dos altas 201 y dos ediciones 200. En ambos casos se verificó el nombre persistido. La prueba anterior de reglas incluye alta, edición y retirada por API. |
| Runtime y acciones | Abrir resumen, ejecuciones y configuración. Cambiar la capacidad de cola de la copia, guardar y recargar. Abrir catálogo de acciones y workers y refrescar el catálogo. | Lecturas 200. Cambio de configuración 200 y valor persistido. Refresco del catálogo 200. |
| Usuarios y cuentas técnicas | Crear un lector y asignar AREANDINA. Crear cuenta técnica de prueba, emitir token y revocarlo desde la interfaz. Iniciar sesión como lector. | Altas, emisión y revocación 200. El lector abrió su informe. La red 1 y su snapshot 1 devolvieron 403. Abrir la ruta de usuarios mostró «Acceso denegado». Tras el logout, una recarga protegida pidió login. |
| dARK | Abrir pantalla, configuración, estado de autenticación, resumen e inventario. | Respuestas 200. El inventario mostró 4.000 registros en la copia. |

## Cómo repetir las pruebas

En el módulo admin-web, con las dependencias de su lock instaladas y el Node preparado por Maven, ejecutar:

```sh
./node/node node_modules/typescript/bin/tsc -b --pretty false
./node/node node_modules/vite/bin/vite.js build
./node/node node_modules/vitest/vitest.mjs run
```

Pasaron **85 pruebas en 12 archivos**. El build produjo el bundle y Vite avisó de chunks minificados de más de 500 kB. Las regresiones específicas se encuentran en [diagnóstico](../lareferencia-lrharvester-admin-web/src/features/diagnostics/DiagnosticsPage.test.tsx), [sesión](../lareferencia-lrharvester-admin-web/src/auth/session-expiration.test.tsx) y [listado de redes](../lareferencia-lrharvester-admin-web/src/features/networks/NetworkListPage.test.tsx).

Desde plataforma, usar un **PostgreSQL de pruebas vacío y desechable** para la suite Java. Las pruebas de tags crean y eliminan esquema. El runner espera la cuenta `postgres` y la contraseña de fixture `indexing-test`. La base de la suite es independiente de la copia de datos del navegador.

```sh
mvn -Plareferencia -pl lareferencia-lrharvester-app -am -Dno-frontends \
  '-Dtest=ApiV5*,HistoricalValidationReportTest,IncrementalValidationLifecycleTest,ValidationStatisticsSQLiteReadTest,LocalAuthorizationServiceRoleTest,WebSecurityConfigTest' \
  -Dsurefire.failIfNoSpecifiedTests=false \
  "-Dindexing.test.jdbc-url=jdbc:postgresql://127.0.0.1:${PUERTO_PG_TEST}/indexing_test" test
```

La selección final pasó **72 de 72** (17 en core y 55 en harvester). Comprende consultas sobre SQLite real, controladores MockMvc, autorización y los filtros de tags sobre PostgreSQL. Para repetir la prueba funcional del informe, servir el bundle compilado junto con la API v5 de la copia descrita, con su configuración de idioma español, Chrome y Playwright para Python:

```sh
python3 testing/admin-ui/verificar_diagnostico.py "http://127.0.0.1:${PUERTO_ADMIN}" "${USUARIO_ADMIN_PRUEBA}"
```

La prueba solicita la contraseña por terminal o lee `ADMIN_TEST_PASSWORD`. Verifica peticiones, respuestas, datos renderizados, recarga y recuperación de un 503 simulado en el navegador. Usa los IDs y cifras de esta copia. [Prueba de navegador](../testing/admin-ui/verificar_diagnostico.py)

## Qué queda abierto para cerrar el admin

1. **Suite Java ampliada.** Al ejecutar `mvn test` para harvester y sus dependencias con el PostgreSQL de pruebas, antes de la última corrección de permisos, Surefire registró 1.425 casos, 1.423 aprobados, uno omitido y un error. `SemanticIndexerPipelineIntegrationTest` agotó el tiempo al crear la colección `biblio` al arrancar Solr 9.5 con Testcontainers. Se repitió aislado y con loopback IPv4 y persistió. Posteriormente se corrigió el arranque de Solr y pasó esa regresión aislada. [Diagnóstico y corrección](ADMIN_UI_INDEXACION.md#qué-se-corrigió) `EntityServiceIntegrationTest.testDeleteEntity` está deshabilitado por referencias transitorias a `FieldOccurrence`. La selección final de 72 pruebas cubre el cambio de permisos.
2. **Operaciones con efecto externo.** Se verificaron desde Chrome la cosecha OAI completa, la cancelación con trabajo en cola y los lotes con aceptación total y parcial, incluidos los estados terminales y los catálogos persistidos. También se comprobó la indexación del buscador con el snapshot PA #4 y Solr real. Queda la publicación dARK. [Indexación](ADMIN_UI_INDEXACION.md) [Resultados y reproducción](ADMIN_UI_OPERACIONES.md)
3. **Resto de variantes de operación.** Quedan la edición y reordenación de cada tipo de regla desde el formulario, importación con datos inválidos y los distintos modos de conflicto, y operaciones destructivas de limpieza y borrado. Las pruebas de componentes y API existentes ofrecen cobertura parcial. Este informe indica cuáles se ejercieron con navegador y persistencia real.
4. **Rendimiento e integración de release.** F9 conserva pendiente la medición de p50/p95 y SQL por página con varios tamaños y cachés. Falta integrar los módulos, fijar sus commits en el lock y repetir sobre esa combinación. F5 y las decisiones de XML y logs para otros consumidores quedan en la etapa del dashboard. El acceso del admin al XML publicado y a la bitácora se verificó aquí.
