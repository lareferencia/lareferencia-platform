# Plan técnico de la nueva aplicación administrativa del Harvester

## 1. Objetivo

Construir una aplicación web administrativa moderna que consuma exclusivamente la API `/api/v5`, reemplace funcionalmente a `lareferencia-lrharvester-app/static` y pueda evolucionar sin depender de AngularJS, Spring Data REST, HAL ni entidades JPA.

La nueva aplicación debe conservar las capacidades útiles del producto actual, mejorar su seguridad y experiencia de uso y evitar copiar decisiones accidentales de la implementación legacy.

Este documento se basa en el análisis de:

- los 4.035 renglones de JavaScript y HTML propios de `static`;
- los módulos `app`, `network`, `validators`, `transformers`, `rules` y `diagnose`;
- los servicios que adaptan HAL y Spring Data REST;
- los esquemas locales de redes, atributos y reglas;
- los controladores, DTOs, servicios y seguridad presentes en la rama `codex/add-harvester-management-api-v5`.

## 2. Conclusión ejecutiva

La sustitución es viable y no requiere replicar las 287 piezas distribuidas con la aplicación actual: buena parte son librerías, CSS y plantillas de AngularJS. Sin embargo, la complejidad real no está en el número de archivos sino en cinco flujos con reglas implícitas:

1. dashboard operativo con polling, selección y acciones masivas;
2. edición compuesta de redes y asociaciones;
3. edición dinámica de reglas mediante JSON Schema;
4. historial y observación de procesos asíncronos;
5. diagnóstico facetado de snapshots, registros y ocurrencias.

La API v5 es una base adecuada, pero no está lista todavía para implementar una interfaz completa y eficiente. Antes del desarrollo intensivo del frontend se recomienda una fase corta de estabilización de contrato. Las brechas más importantes son:

- el listado de redes no contiene el resumen operativo que muestra el dashboard actual;
- no acepta filtros ni ordenamiento;
- los diagnósticos se publican como `JsonNode` y los filtros como strings internos;
- no hay catálogo de perfiles de atributos;
- no existe un endpoint de identidad y roles del usuario;
- no hay cancelación explícita por snapshot o proceso;
- las fechas usan `LocalDateTime`, sin zona UTC explícita;
- OpenAPI todavía describe tipos técnicos, pero no documenta exhaustivamente ejemplos y errores.

La estimación para un reemplazo productivo completo es de **80 a 110 días-persona**, incluyendo endurecimiento de API, frontend, pruebas y puesta en producción. Con dos desarrolladores y apoyo de QA, el calendario razonable es de **10 a 14 semanas**. Un MVP operativo puede estar disponible en **35 a 50 días-persona**.

### Estado de la primera iteración P0

La rama `codex/harden-harvester-management-api-v5` implementa el primer corte de estabilización:

- proyección paginada `network-summaries`, con búsqueda, filtros y ordenamiento;
- DTOs públicos para resumen, registros y ocurrencias de diagnóstico;
- filtros públicos tipados y traducción interna segura;
- endpoint `/me` para identidad y roles;
- catálogo configurable de perfiles de atributos;
- fechas v5 como ISO-8601 UTC;
- OpenAPI restringido a v5, con Basic y Bearer/JWT;
- pruebas unitarias y MockMvc iniciales.

Continúan pendientes dentro del endurecimiento: validación completa de atributos contra JSON Schema, DTOs/filtros para origen, set y metadata prefix si el backend estadístico los soporta, pruebas PostgreSQL/Testcontainers, autenticación OIDC end-to-end, concurrencia con ETag y cancelación granular por proceso/snapshot.

## 3. Aplicación actual

### 3.1 Arquitectura

La aplicación actual es una SPA AngularJS cargada directamente desde `static/index.html`.

```mermaid
flowchart LR
    UI[AngularJS + UI Bootstrap] --> DataSrv[DataSrv]
    DataSrv --> HAL[Angular Spring Data REST adapter]
    HAL --> SDR[/rest/**]
    UI --> Legacy[/public/** y /private/**]
    SDR --> JPA[Entidades y asociaciones JPA]
    Legacy --> Engine[TaskManager / Flowable]
```

Características técnicas:

- AngularJS, `ui-router`, `ngTable` y Bootstrap 3;
- formularios generados con Angular Schema Form y TV4;
- relaciones persistentes manipuladas mediante `text/uri-list`;
- obtención de IDs a partir de `_links.self.href`;
- acciones mutantes ejecutadas mediante `GET`;
- polling fijo de cinco segundos sobre el listado de redes;
- autenticación por formulario y sesión del mismo proceso Spring;
- traducciones y etiquetas mezcladas entre español e inglés;
- sin pipeline de construcción, tipado estático ni pruebas frontend visibles.

### 3.2 Mapa funcional

#### Dashboard de redes

La pantalla principal proporciona:

- tabla paginada de redes;
- filtros por estado, indexación, acrónimo, nombre e institución;
- ordenamiento de columnas;
- selección individual o de toda la página;
- actualización manual o automática cada cinco segundos;
- acciones configuradas, acciones individuales full/incremental, cancelación y reprogramación;
- ejecución de acciones sobre una o varias redes;
- indicadores de procesos activos, en cola y programados;
- estado y fecha del último snapshot;
- último snapshot válido conocido;
- tamaños total, válido y transformado;
- acceso a historial, logs, diagnóstico y edición de red.

#### Edición de red

El formulario está dividido conceptualmente en:

- datos principales: acrónimo, nombre, institución, publicación, cron y URL OAI;
- asociaciones: prevalidador, validador, transformador primario y secundario;
- atributos específicos según un perfil local;
- propiedades booleanas derivadas de las acciones instaladas;
- sets OAI;
- acciones disponibles para una red ya persistida.

La implementación actual persiste primero la entidad y después modifica asociaciones HAL. La API v5 mejora este comportamiento al recibir el agregado completo en una sola operación.

#### Validadores y transformadores

Cada recurso ofrece:

- listado;
- creación;
- edición de nombre y descripción;
- clonado;
- eliminación;
- acceso al editor de reglas.

#### Reglas

El editor soporta:

- selección de un tipo de regla instalado;
- formulario genérico de nombre y descripción;
- formulario específico generado desde JSON Schema;
- campos de validación como `mandatory` y `quantifier`;
- orden de ejecución para transformaciones;
- alta, edición y borrado;
- compatibilidad manual con nombres antiguos de paquetes Java.

La aplicación antigua recibe y modifica `jsonserialization`. V5 elimina correctamente este detalle y expone `configuration` como objeto JSON.

#### Snapshots y logs

El historial muestra:

- identificador;
- estado;
- inicio y final;
- tamaños total, válido y transformado;
- marca de borrado;
- acceso al log cuando el snapshot no está borrado.

#### Diagnóstico

La vista de diagnóstico presenta:

- totales de registros, válidos y transformados;
- facetas seleccionables;
- estadísticas por regla;
- lista paginada de registros;
- reglas válidas e inválidas de cada registro;
- ocurrencias válidas e inválidas por regla;
- metadata XML formateada;
- exportación CSV de ocurrencias.

### 3.3 Problemas que no deben migrarse

- Dependencia de HAL para descubrir IDs y asociaciones.
- Estado remoto mezclado directamente con `$scope`.
- Strings de filtros Solr construidos en el navegador.
- Acciones con efectos mediante `GET`.
- Polling global constante incluso cuando la pestaña no está visible.
- Alertas y confirmaciones nativas sin información contextual.
- Credenciales, roles y expiración de sesión sin modelo explícito de frontend.
- Esquemas de atributos copiados y personalizados dentro del artefacto web.
- Respuestas de diagnóstico sin contrato público estable.
- Ausencia de control de concurrencia al editar configuración.

## 4. Cobertura de la API v5

| Función | Cobertura v5 | Observación |
|---|---|---|
| Listar redes | Parcial | Paginación uniforme, pero sin filtros, orden ni estado operacional agregado. |
| Crear/editar red | Alta | DTO explícito y asociaciones atómicas. PATCH requiere mayor prueba de merge patch. |
| Borrar red | Alta | Confirmación por acrónimo y ejecución asíncrona. |
| Propiedades y acciones instaladas | Alta | Disponibles en `capabilities`. |
| Selección y comandos masivos | Alta | `network-command-batches` soporta resultado parcial. |
| Runtime global y por red | Media | Datos disponibles, pero el dashboard necesita combinarlos eficientemente. |
| Historial de snapshots | Alta | Recurso paginado y último snapshot. |
| Logs | Alta | Paginados con contrato explícito. |
| CRUD de validadores/transformadores | Alta | Incluye clonado y restricción de asociaciones. |
| CRUD y orden de reglas | Alta | Configuración como JSON y catálogo de tipos. |
| Ayuda y presentación de reglas | Parcial | El catálogo no expone ayuda detallada ni UI Schema. |
| Perfiles de atributos | Ausente | Hoy viven en archivos JavaScript específicos de cada instalación. |
| Diagnóstico resumido | Parcial | Se devuelve un `JsonNode` opaco. |
| Registros y ocurrencias | Parcial | Respuestas sin DTO; filtros públicos siguen siendo `List<String>`. |
| XML de registro | Alta | Endpoint XML explícito. |
| Cancelar por red | Alta | `CANCEL_ALL`. |
| Cancelar por snapshot/proceso | Ausente | Debe definirse si se necesita paridad o se elimina de la UX. |
| Identidad y roles | Ausente | Hace falta `/api/v5/me` o equivalente. |
| Basic file-based | Alta para CLI | Poco apropiado para almacenar credenciales en una SPA. |
| OIDC/JWT | Base disponible | Falta completar y probar el flujo Authorization Code + PKCE en la aplicación. |
| OpenAPI consumible | Parcial | Generado, pero necesita ejemplos, descripciones, errores y prueba de estabilidad. |

## 5. Cambios de API recomendados antes del frontend

### 5.1 Prioridad P0: bloqueantes

#### Proyección de dashboard

Añadir una representación de resumen diseñada para la tabla:

```json
{
  "id": 12,
  "acronym": "V5TEST",
  "name": "Repositorio",
  "institutionName": "Institución",
  "published": true,
  "latestSnapshot": {
    "id": 100,
    "status": "VALID",
    "indexStatus": "INDEXED",
    "startTime": "2026-08-25T10:00:00Z",
    "size": 1000,
    "validSize": 980,
    "transformedSize": 970
  },
  "lastValidSnapshotId": 100,
  "runtime": {
    "runningCount": 0,
    "queuedCount": 0,
    "scheduled": true
  }
}
```

Puede publicarse como `GET /api/v5/network-summaries` o como una proyección seleccionable de `/networks`. Debe evitar una secuencia de tres o cuatro llamadas por fila.

El endpoint debe aceptar:

- `page`, `size`;
- `sort=field,direction`;
- `q` para búsqueda general;
- `acronym`, `name`, `institutionName`;
- `snapshotStatus`, `indexStatus`;
- `published`, `active`.

#### Contrato de diagnóstico tipado

Sustituir `DiagnosticResponse(JsonNode data)` por DTOs públicos:

- `DiagnosticSummaryResponse`;
- `DiagnosticFacetResponse`;
- `DiagnosticRuleStatsResponse`;
- `DiagnosticRecordResponse`;
- `RuleOccurrenceResponse`;
- `PageResponse<DiagnosticRecordResponse>`.

El cuerpo de consulta debe aceptar filtros tipados y nunca expresiones Solr:

```json
{
  "filters": [
    { "field": "valid", "operator": "EQ", "value": true },
    { "field": "set", "operator": "IN", "values": ["setA"] }
  ],
  "page": 0,
  "size": 25
}
```

#### Identidad de sesión

Añadir `GET /api/v5/me`:

```json
{
  "username": "admin",
  "displayName": "Administrador",
  "roles": ["ADMIN"],
  "authMode": "oidc"
}
```

Esto permite ocultar operaciones no autorizadas sin inferir roles a partir de errores 403.

#### Perfiles de atributos

Añadir:

- `GET /api/v5/attribute-profiles`;
- `GET /api/v5/attribute-profiles/{typeId}`.

Cada perfil debe publicar `typeId`, nombre, clase técnica, JSON Schema, versión y, opcionalmente, UI Schema. La API debe validar el objeto `attributes` contra el perfil seleccionado.

#### Fechas y zona horaria

Reemplazar `LocalDateTime` por `Instant` u `OffsetDateTime` y asegurar respuestas ISO-8601 en UTC con sufijo `Z`.

### 5.2 Prioridad P1: necesarias para producción

- Añadir cancelación por `processId` cuando Flowable lo soporte y declarar explícitamente el alcance legacy.
- Resolver si `STOP_HARVESTING` por snapshot continúa siendo requisito funcional.
- Incorporar `version` o ETag en redes, validadores y transformadores, usando `If-Match` para detectar edición concurrente.
- Añadir `usedByNetworks` o endpoints de referencias para explicar conflictos 409 antes de borrar.
- Publicar en OpenAPI todos los códigos de error, ejemplos, límites y esquemas.
- Asegurar que `typeId` sea estable ante cambios de nombre de clase; mantener aliases para plugins migrados.
- Añadir pruebas de CORS, Basic, JWT y Swagger UI en contexto real de Spring.
- Confirmar que reprogramación se ejecute después del commit y no dentro de una transacción que pueda revertirse.

### 5.3 Prioridad P2: mejoras posteriores

- SSE para runtime y comandos; comenzar con polling adaptativo.
- Historial persistente o auditable de comandos.
- Vista de eventos de seguridad y cambios administrativos.
- Previsualización y validación de una configuración de reglas sin persistirla.
- Endpoint para probar conectividad OAI-PMH y `Identify` antes de guardar una red.

## 6. Arquitectura propuesta

### 6.1 Decisión tecnológica

Aplicación SPA en repositorio independiente, sugerido:

```text
lareferencia-lrharvester-admin-web
```

Stack:

| Capa | Tecnología | Responsabilidad |
|---|---|---|
| Lenguaje | TypeScript estricto | Tipos, refactors y contratos verificables. |
| UI | React | Componentes y composición de pantallas. |
| Build | Vite | Desarrollo local, bundle y configuración por entorno. |
| Routing | React Router | Rutas, layouts, loaders y páginas de error. |
| Estado servidor | TanStack Query | Caché, polling, mutaciones e invalidación. |
| Formularios normales | React Hook Form + Zod | Redes y datos generales. |
| Formularios dinámicos | RJSF + AJV 8 | Reglas y perfiles definidos mediante JSON Schema. |
| Componentes | Material UI | Tablas, formularios, modales y accesibilidad base. |
| Cliente HTTP | generado desde OpenAPI | DTOs y operaciones sin contratos duplicados. |
| Internacionalización | i18next | Español, portugués e inglés. |
| Unit/component tests | Vitest + Testing Library + MSW | Lógica, componentes y API simulada. |
| E2E | Playwright | Flujos completos con backend real. |

No se recomienda Next.js para esta fase: no hay necesidad de SEO o renderizado del lado servidor y añadiría un runtime adicional sin beneficio suficiente.

### 6.2 Despliegue

Soportar dos modalidades desde el mismo build:

1. **Separada**: archivos estáticos servidos por Nginx/CDN y API en otro origen permitido por CORS.
2. **Empaquetada**: bundle copiado al artefacto Spring Boot bajo una ruta nueva, por ejemplo `/admin-v5`.

La modalidad separada facilita releases independientes. La empaquetada simplifica instalaciones pequeñas y evita CORS. La decisión de hosting no debe cambiar el código funcional.

La configuración del frontend se cargará en runtime mediante `/config.json`, no mediante secretos compilados:

```json
{
  "apiBaseUrl": "/api/v5",
  "authMode": "oidc",
  "oidc": {
    "authority": "https://identity.example.org",
    "clientId": "lr-harvester-admin",
    "redirectUri": "https://harvester.example.org/admin-v5/callback"
  },
  "defaultLocale": "es"
}
```

### 6.3 Organización del código

```text
src/
├── app/
│   ├── App.tsx
│   ├── router.tsx
│   ├── providers.tsx
│   └── config.ts
├── api/
│   ├── generated/
│   ├── client.ts
│   ├── problem-detail.ts
│   └── query-keys.ts
├── auth/
│   ├── AuthProvider.tsx
│   ├── RequireRole.tsx
│   └── token-store.ts
├── features/
│   ├── dashboard/
│   ├── networks/
│   ├── validators/
│   ├── transformers/
│   ├── rules/
│   ├── snapshots/
│   ├── diagnostics/
│   └── runtime/
├── components/
│   ├── data-table/
│   ├── dynamic-form/
│   ├── feedback/
│   └── layout/
├── i18n/
├── test/
└── main.tsx
```

Reglas de arquitectura:

- `api/generated` se regenera y nunca se edita manualmente;
- cada feature posee páginas, componentes, queries y tests;
- ningún componente llama `fetch` directamente;
- TanStack Query contiene exclusivamente estado del servidor;
- filtros de tabla relevantes se reflejan en la URL;
- estado de formulario no se almacena globalmente;
- los DTOs generados no se transforman en modelos HAL;
- `ProblemDetail` se normaliza en un único interceptor;
- los permisos se aplican en UI por ergonomía y en backend por seguridad.

### 6.4 Autenticación

#### Producción

Usar OIDC Authorization Code con PKCE:

1. redirección al proveedor;
2. callback a la SPA;
3. token mantenido en memoria;
4. renovación según las capacidades del proveedor;
5. header `Authorization: Bearer` agregado por el cliente;
6. cierre de sesión local y, cuando corresponda, en el proveedor.

No guardar access tokens o contraseñas en `localStorage`.

#### File/Basic

Mantener Basic para `curl`, pruebas y entornos controlados. Si se requiere una experiencia web file-based de producción, es preferible añadir un login de sesión/BFF específico antes que almacenar la contraseña en la SPA. Esta decisión debe tomarse durante la fase 0.

## 7. Diseño funcional propuesto

### 7.1 Navegación

```text
Resumen
Redes
├── Listado
├── Nueva red
└── Detalle
    ├── Configuración
    ├── Operación
    ├── Snapshots
    └── Diagnóstico
Validadores
Transformadores
Runtime
```

### 7.2 Dashboard

- KPIs: redes publicadas, con error, activas y sin snapshot válido.
- Tabla con filtros persistentes en la URL.
- selección entre páginas solo si el usuario la solicita explícitamente;
- comandos individuales y por lote con confirmación que muestre alcance;
- polling adaptativo: 5 segundos con tareas activas, 30–60 segundos en reposo y detenido cuando la pestaña no está visible;
- recibos de comando visibles hasta que se observe un cambio de runtime;
- estados con texto e icono, nunca solo color;
- acceso directo a red, snapshot y diagnóstico.

### 7.3 Editor de red

Usar una página, no un modal, con secciones:

1. identidad e institución;
2. origen OAI y sets;
3. programación;
4. validación y transformación;
5. perfil y atributos;
6. acciones habilitadas;
7. resumen antes de guardar.

Comportamientos:

- guardar el agregado en una única petición;
- bloquear envío mientras exista una mutación pendiente;
- mostrar errores de campo provenientes de `violations`;
- advertir si la red está activa;
- detectar edición concurrente;
- ofrecer “probar conexión OAI” cuando exista el endpoint;
- para borrar, exigir escribir el acrónimo exacto.

### 7.4 Validadores, transformadores y reglas

- listados separados con búsqueda local o servidor según volumen;
- cantidad de reglas y redes asociadas visibles;
- clonado con nombre nuevo editable antes de confirmar;
- editor agregado con drag-and-drop accesible para orden;
- catálogo de tipos con búsqueda y ayuda;
- RJSF renderiza `configuration` desde el esquema de v5;
- vista JSON avanzada opcional para administradores expertos;
- validación cliente con AJV y validación definitiva en servidor;
- preservación de cambios no guardados al navegar accidentalmente.

### 7.5 Snapshots, logs y runtime

- historial paginado, con filtros de estado;
- fechas localizadas, conservando UTC en el contrato;
- logs con paginación incremental, búsqueda local y copia;
- runtime global y por red;
- polling solo cuando haya actividad;
- explicación del alcance de cancelación según motor;
- no presentar un recibo HTTP como ejecución finalizada.

### 7.6 Diagnóstico

- encabezado con resumen del snapshot;
- facetas multi-selección reflejadas en la URL;
- tabla paginada de registros;
- panel lateral o ruta hija para detalle del registro;
- agrupación clara de reglas válidas e inválidas;
- ocurrencias por regla con exportación CSV construida desde datos tipados;
- XML cargado bajo demanda, formateado y escapado, nunca inyectado como HTML;
- consultas cancelables al cambiar rápidamente de filtros.

## 8. Plan de implementación

### Fase 0 — Contrato y decisiones bloqueantes (10–15 días-persona)

Entregables:

- matriz de paridad aprobada;
- contratos P0 implementados y probados;
- OpenAPI versionado como artefacto CI;
- `network summary`, filtros y ordenamiento;
- DTOs tipados de diagnóstico;
- `/me` y perfiles de atributos;
- decisión OIDC frente a sesión file-based;
- entorno PostgreSQL de integración con datos de prueba;
- pruebas API del issue #70 ejecutadas.

Gate de salida: generar un cliente TypeScript sin tipos `any` para todos los flujos del MVP.

### Fase 1 — Fundaciones frontend (8–12 días-persona)

- crear repositorio y proyecto Vite/TypeScript;
- lint, format, typecheck, test y build en CI;
- layout responsive y sistema visual;
- configuración runtime;
- router y páginas de error;
- cliente generado de OpenAPI;
- normalizador de Problem Details;
- autenticación y autorización;
- i18n inicial ES/PT/EN;
- MSW con contratos representativos.

Gate de salida: login, `/me`, navegación por rol, error 401/403 y health smoke test.

### Fase 2 — Dashboard y operación (12–16 días-persona)

- tabla de resúmenes de red;
- filtros, orden, paginación y deep links;
- selección y comandos por lote;
- capacidades dinámicas;
- recibos y errores parciales;
- runtime y polling adaptativo;
- estados de snapshot e indexación;
- confirmaciones seguras.

Gate de salida: un ADMIN puede operar redes de prueba y un VIEWER solo observarlas.

### Fase 3 — Configuración de redes (10–14 días-persona)

- crear, consultar, reemplazar y aplicar merge patch;
- editores de sets, atributos y propiedades;
- asociaciones de validación y transformación;
- cron con validación y ayuda;
- bloqueo por actividad;
- confirmación de borrado exacta;
- conflictos de versión y asociaciones inexistentes.

Gate de salida: ciclo completo de red cubierto por Playwright y PostgreSQL de prueba.

### Fase 4 — Validadores, transformadores y reglas (15–20 días-persona)

- listados y detalle;
- alta, reemplazo, clonado y borrado;
- conflictos por redes asociadas;
- catálogo de reglas localizado;
- renderer JSON Schema;
- CRUD individual de reglas;
- reordenamiento accesible;
- edición de configuración avanzada;
- manejo de schemas/plugin desconocidos.

Gate de salida: crear un agregado completo, vincularlo a una red y ejecutar una cosecha simulada.

### Fase 5 — Snapshots y diagnóstico (12–18 días-persona)

- historial y último válido;
- visor de logs;
- resumen de diagnóstico;
- filtros tipados y facetas;
- registros paginados;
- detalle de registro y reglas;
- ocurrencias y CSV;
- visor XML seguro;
- estados vacíos y snapshots borrados.

Gate de salida: reproducir el recorrido funcional actual de diagnóstico sin utilizar endpoints legacy.

### Fase 6 — Endurecimiento y lanzamiento (13–15 días-persona)

- pruebas E2E completas en Basic y OIDC;
- accesibilidad WCAG 2.1 AA en flujos críticos;
- pruebas Chrome, Firefox y Safari actuales;
- auditoría de dependencias y CSP;
- límites de bundle y rendimiento;
- guía operativa y de despliegue;
- observabilidad y correlación por `traceId`/`requestId`;
- piloto en entorno no productivo;
- correcciones de aceptación;
- rollout paralelo con `static`.

Gate de salida: aceptación del equipo y plan de reversión probado.

## 9. Estrategia de pruebas

### 9.1 Frontend

#### Unitarias

- traducción de estados;
- serialización de filtros a URL;
- validación de cron y URL como ayuda cliente;
- permisos por rol;
- normalización de Problem Details;
- polling adaptativo;
- generación de CSV.

#### Componentes

- tablas con carga, vacío, error y paginación;
- formularios con errores cliente/servidor;
- confirmaciones de comandos y borrado;
- renderizado de JSON Schema;
- reglas desconocidas o schemas inválidos;
- detalle de diagnóstico y XML.

MSW debe simular el contrato HTTP, no funciones internas del cliente.

#### Contrato

- descargar OpenAPI de una build del backend;
- regenerar cliente;
- fallar CI si aparecen cambios no aceptados;
- ejecutar una colección de smoke tests sobre cada despliegue.

#### End-to-end

1. autenticarse como VIEWER y verificar modo lectura;
2. autenticarse como ADMIN;
3. crear validador y transformador con reglas;
4. crear red vinculada;
5. editar cron y verificar reprogramación;
6. ejecutar acción y observar runtime;
7. ejecutar lote parcialmente inválido;
8. consultar snapshot, log y diagnóstico;
9. abrir XML y exportar ocurrencias;
10. verificar conflicto al borrar un recurso vinculado;
11. desvincular y borrar recursos temporales;
12. verificar confirmación exacta de borrado de red.

### 9.2 Backend requerido para la app

- MockMvc para cada ruta y permiso;
- Testcontainers/PostgreSQL para asociaciones y restricciones;
- fixtures de reglas reales para JSON Schema;
- dobles de legacy y Flowable;
- validación del número de consultas del endpoint de dashboard;
- pruebas de fechas UTC;
- prueba de que ninguna respuesta contiene `_links` o `jsonserialization`;
- pruebas de compatibilidad del OpenAPI generado.

### 9.3 No funcionales

- primera carga comprimida objetivo menor a 500 KB, excluyendo mapas fuente;
- navegación utilizable con teclado;
- ningún error crítico de axe en flujos principales;
- tabla fluida con 200 filas;
- diagnóstico cancelable y sin resultados obsoletos;
- secretos y tokens ausentes de logs, almacenamiento persistente y bundles;
- CSP sin `unsafe-eval` en producción.

## 10. CI/CD

Pipeline por pull request:

```text
install locked dependencies
  -> lint
  -> typecheck
  -> unit/component tests
  -> generate/check OpenAPI client
  -> production build
  -> dependency audit
  -> Playwright smoke tests
```

Pipeline de release:

- versión semántica del frontend;
- imagen Nginx y/o archive estático;
- SBOM;
- firma o checksum del artefacto;
- configuración externa por entorno;
- smoke test posterior al despliegue;
- rollback al artefacto anterior.

## 11. Migración y convivencia

1. Mantener `static` disponible sin modificar sus rutas.
2. Publicar la nueva app en `/admin-v5` o un host separado.
3. Ejecutar ambas contra el mismo entorno de prueba.
4. Comparar resultados de lectura y acciones seleccionadas.
5. Realizar piloto con administradores reales.
6. Corregir brechas y documentar diferencias intencionales.
7. Declarar freeze funcional de AngularJS.
8. Cambiar el acceso principal a la nueva app.
9. Mantener rollback durante al menos un ciclo operativo acordado.
10. Retirar `static`, Spring Data REST y controladores legacy en una fase posterior independiente.

No se recomienda una migración gradual de componentes dentro de AngularJS: mantener dos frameworks en la misma página prolongaría el acoplamiento y complicaría autenticación, build y pruebas.

## 12. Estimación

| Fase | Días-persona |
|---|---:|
| 0. Contrato y decisiones | 10–15 |
| 1. Fundaciones | 8–12 |
| 2. Dashboard y operación | 12–16 |
| 3. Redes | 10–14 |
| 4. Validadores, transformadores y reglas | 15–20 |
| 5. Snapshots y diagnóstico | 12–18 |
| 6. Endurecimiento y lanzamiento | 13–15 |
| **Total** | **80–110** |

Escenarios:

- un desarrollador full-stack: aproximadamente 4–6 meses, más disponibilidad de revisión funcional;
- dos desarrolladores con QA parcial: 10–14 semanas calendario;
- MVP sin diagnóstico avanzado ni OIDC completo: 35–50 días-persona;
- prototipo visual sin integración real: 10–15 días-persona, pero no reduce el trabajo de producto posterior en la misma proporción.

La incertidumbre principal no es React: son la estabilización de diagnóstico, los perfiles de atributos, la autenticación elegida y las diferencias entre motores de ejecución.

## 13. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Construir sobre un contrato v5 aún inestable | Reprocesamiento frontend | Gate de OpenAPI y fase 0 obligatoria. |
| N+1 en dashboard | Carga lenta sobre muchas redes | Endpoint agregado y prueba de consultas. |
| Diagnóstico opaco | Tipos `any` y bugs de filtros | DTOs y filtros públicos tipados. |
| Basic en SPA | Manejo inseguro de credenciales | OIDC PKCE o BFF/session. |
| Plugins con schemas diversos | Formularios que no renderizan | fixtures reales, AJV y fallback JSON controlado. |
| Concurrencia entre administradores | Pérdida silenciosa de cambios | ETag/If-Match. |
| Diferencias legacy/Flowable | Acciones ambiguas | capacidades y alcance de cancelación visibles. |
| Polling excesivo | Carga backend | intervalos adaptativos y pausa en segundo plano. |
| Paridad entendida como copia visual | UX nueva limitada por AngularJS | matriz de capacidades y criterios de aceptación. |
| Retiro prematuro de legacy | Riesgo operativo | convivencia, piloto y rollback. |

## 14. Definición de terminado

La nueva aplicación se considerará lista cuando:

- no haga ninguna llamada a `/rest`, `/public` o `/private`;
- todos los flujos definidos como paridad estén cubiertos por Playwright;
- VIEWER y ADMIN tengan permisos correctos en UI y backend;
- no procese HAL, proxies JPA o `jsonserialization`;
- gestione errores mediante `ProblemDetail` y muestre `traceId` al operador;
- soporte una instalación file-based acordada y una instalación OIDC probada;
- pase accesibilidad y navegadores objetivo;
- disponga de guía de despliegue, operación y rollback;
- el equipo funcional acepte dashboard, configuración, acciones y diagnóstico;
- el frontend legacy pueda quedar en modo de solo mantenimiento.

## 15. Próxima decisión

Antes de crear el repositorio frontend deben aprobarse cuatro decisiones:

1. OIDC como modo principal o necesidad de una sesión file-based para navegador.
2. Contrato del resumen de dashboard.
3. DTOs públicos de diagnóstico.
4. propiedad y distribución de los perfiles de atributos.

Una vez resueltas, el primer incremento debe ser un vertical slice real: autenticación, listado de redes, detalle, un comando `RESCHEDULE` y observación del runtime. Ese incremento valida arquitectura, seguridad y contrato antes de abordar formularios dinámicos y diagnóstico.
