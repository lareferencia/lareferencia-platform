# Propuesta de actualización de documentación — lareferencia-platform

**Status:** historical · **Last verified:** 2026-09-23

**Fecha:** 2026-09-23 · **Autor:** análisis asistido (Claude) · **Alcance:** toda la documentación del workspace
**Método:** verificación de cada documento contra el código actual (solo lectura), + análisis de los commits de los últimos 2 meses (2026-07-23 → 2026-09-23) en el repo externo y en los 15 componentes anidados.

> **EJECUTADO el 2026-09-23:** el plan se aplicó (fases 1-6) y el borrador `README.proposed.md` se fusionó en `README.md` (el fichero ya no existe). Este documento se conserva como registro de decisión; el índice vigente está en [`DOCUMENTATION_INDEX.md`](DOCUMENTATION_INDEX.md).

---

## 1. Resumen ejecutivo

Se auditaron **~55 documentos** (26 en `docs/`, 19 en componentes y subproyectos, 10 auxiliares del raíz y de infra). Resultado global:

| Grupo | Documentos | VIGENTE (KEEP) | PARCIAL (UPDATE) | OBSOLETO (ARCHIVE) |
|---|---|---|---|---|
| `docs/` del workspace | 26 | 12 | 9 | 5 |
| Raíz (README, changelog, etc.) | 5 | 2 | 2 | 1 |
| READMEs de componentes | 18 | 10 | 6 | 2 |
| Docs de subproyectos (oai-pmh, shell, testing) | 9 | 5 | 3 | 1 |
| Infra (Docker, aws, .agent) | ~10 | 7 | 3 | 0 |

**Diagnóstico general:** la documentación no está "podrida" — la mayoría describe decisiones y arquitectura que **sí** están en el código. El problema es de **tres tipos**:

1. **Docs obsoletos por evolución del código** (5 en `docs/` + changelog): describen un estado previo a la implementación incremental del 2026-09-04 (`7cf2a01`, core-lib) o planes ya ejecutados (plan técnico v5 del admin web, implementado el 2026-08-27→09-03).
2. **Errores concretos que inducen a error operativo** (los más graves, corregibles con UPDATE): rutas de API erróneas en el handoff de dark (`DARK_ISSUES_PLAN_CONTEXT.md`), puertos erróneos del harness de pruebas (`testing/oai-incremental`), nombres de migraciones Flyway erróneos (`IMPLEMENTACION_CONFIGURACION_ACCIONES`), CLI y afirmaciones de seguridad desactualizadas (`AUTENTICACION_FILE_BASED.md`), enlaces absolutos rotos (`ENTITY_DELETED_INDEXING.md`), configuración de indexación que nunca existió (DLQ, buffers — `INDEXING-CONFIGURATION.md`).
3. **README raíz desactualizado en lo operativo** (~20-25% del contenido): **las 3 URLs de acceso declaradas son falsas**, la versión es `5.0.0-rc` (real: `5.0.0-rc2`), faltan 2 de los 15 módulos (`lareferencia-solr-cores`, `lareferencia-lrharvester-admin-web`) y presenta el admin web React como "roadmap" cuando ya está implementado.

**Entregable adicional:** `README.proposed.md` (raíz) — borrador completo del nuevo README en inglés, listo para revisar y reemplazar a `README.md`.

---

## 2. Qué cambió en los últimos 2 meses (base del porqué)

Cronología de los cambios de código que dejaron obsoleta la documentación:

| Fechas | Componentes | Cambio | Impacto documental |
|---|---|---|---|
| 2026-08-02→03 | `oai-pmh` (35 commits) | Modernización completa del provider: Spring Boot 3.5, XOAI 3.4, imagen Docker Java 17 no-root, core Solr 9.8, desacoplamiento DSpace, suite de tests de protocolo. Integrado al reactor Maven el 08-03. | El ADR `0001-platform-alignment` quedó con su sección "Implementation status" desactualizada ("Platform has not been modified" — falso). |
| 2026-08-12→09-11 | `entity-lib`, `shell-entity-plugin`, `shell` | **Flag `deleted` en entidades** + comandos `mark_entities_deleted`, `set_entities_deleted`, `remove_deleted_entities_from_index` (con `--relationFields`, `--timeout`, filtro por entidad). Migración `V5.0.0.7`. | Nuevo comportamiento documentado en `ENTITY_DELETED_INDEXING.md` (enlaces rotos) y guías del shell. |
| 2026-08-24→09-03 | `lrharvester-app` (28) + `lrharvester-admin-web` (repo nuevo, 18 commits) | **API v5** (gestión, diagnósticos, acciones, users, XLSX transfers, dark) + **Admin Web React 19/Vite 7** reemplazando AngularJS (que queda en `static-legacy/` servido en `/legacy/`). | `HARVESTER_ADMIN_WEB_V5_TECHNICAL_PLAN.md` quedó ejecutado (obsoleto como plan); `HARVESTER_MANAGEMENT_API_V5.md` le faltan ~8 grupos de endpoints; READMEs de app/admin desactualizados. |
| 2026-08-24→09-01 | `dark-lib` (12), `shell`, app, admin-web | dARK: import CSV legacy de ARKs, runtime configuration persistente, dashboard dARK en admin UI. | `DARK_LEGACY_ARK_IMPORT.md` vigente; `DARK_ISSUES_PLAN_CONTEXT.md` (handoff) con rutas de POST erróneas. |
| 2026-08-29→09-01 | `core-lib`, `shell`, app | **Modelo de configuración de acciones**: `application_action`, `network_action` (JSONB), configuración de workers, guard de programación. Tablas en `V5.0.0.8`. | `IMPLEMENTACION_CONFIGURACION_ACCIONES` cita migraciones `V5.0.0.9/V5.0.0.10` inexistentes. |
| 2026-08-20→09-16 | Docker (repo externo) | **Wizard de backup/restore** (`#66`), timers systemd, workflow Docker aislado para desarrollo, live admin-web dev server, scripts `build-java.sh`/`build-admin-web.sh`. | `DOCKER_DEV.md` vigente; `README-forbackup.md` en realidad es la guía de backup (nombre engañoso); scripts de build nuevos sin documentar en README. |
| 2026-09-04 | `core-lib` | **Implementación de validación e indexación incremental** (delta N/U/D, manifiesto de validación, fingerprints). | Dejó obsoletos 3 docs de `docs/` (catálogo SQLite, redundancia de validación, almacenamiento rápido) que declaraban esa capacidad "no disponible". |
| 2026-09-15→17 | todos | Bump a **5.0.0-rc2** en todos los módulos; branch-set v5 eliminado de `workspace.ini`; scripts de build separados. | README y READMEs de componentes siguen citando `5.0.0-rc` y el ejemplo de branch-set `v5-semantic-indexing`. |

**Nota importante:** el commit `605d0a3` (2026-09-17, "Remove obsolete v5 branch set") **no significa que se abandonara la línea v5** — el trabajo v5 ya está mergeado en `main` de todos los componentes; el branch-set se retiró precisamente porque ya no hacía falta. Los docs de v5 no son "trabajo abandonado", sino trabajo completado.

---

## 3. Hallazgos más importantes (prioridad operativa)

1. 🔴 **`DARK_ISSUES_PLAN_CONTEXT.md`** (doc de handoff, sin commitear): las rutas de POST documentadas `POST /api/v5/dark/networks/{networkId}/(preview|stage|reconcile)` **no existen**; las reales son `POST /api/v5/dark/naans/{arkNaan}/(preview|stage|reconcile)` (`ApiV5DarkController`). Además el conteo de tests (22) quedó en 50. Y el archivo **no está commiteado** (`??` en git status) — si se pierde el checkout, se pierde el doc.
2. 🔴 **`testing/oai-incremental/README.md`**: puerto del provider erróneo en todos los ejemplos (dice 8092/8192 — el 8092 del host es `dashboard-rest`; el real es **8096** en normal / **8196** en dev). Además "canonical OAI core" vs la copia real del provider, y manifiesto sin `scope` no emite warning.
3. 🔴 **README.md raíz**: URLs falsas (`/harvester`, `/entity-api`, `/dashboard-api`), versión `5.0.0-rc` ×5, faltan 2 módulos, admin web React presentado como roadmap, ejemplo de branch-set eliminado, "automated scripts" de migración que contradicen el doc de migración.
4. 🟠 **`lareferencia-entity-rest/README.md`**: describe búsqueda full-text, faceting y 4 entidades — el controlador tiene **los endpoints comentados** ("avoid Solr dependency issues") y solo `/search/entity/{type}` está activo. El módulo está en transición y su README no lo dice.
5. 🟠 **`lareferencia-solr-cores/README.md`**: vacío (26 bytes, solo título) pese a contener 7 configsets (`biblio, entity, historic, networks, oai, projects, vstats` + copia `solr.v9/`).
6. 🟠 **`docs/INDEXING-CONFIGURATION.md`**: documenta ~40% de propiedades inexistentes (DLQ completo, `writer.threads`, `buffer.size`, `monitoring.interval`) de un diseño que nunca se implementó.
7. 🟠 **`lareferencia-core-lib/src/test/README.md`**: cifra de tests casi exacta (1162 vs 1163 ✓) pero afirma AssertJ y JaCoCo que no existen en el proyecto; el comando `mvn clean test jacoco:report` fallaría.
8. 🟡 **`changelog.md`**: muerto desde 2024-01 (última entrada 4.2.3); el mecanismo real de changelog son GitHub Releases + tags (workflow `maven.yml`).
9. 🟡 **`README-forbackup.md`**: NO es un backup del README — es una guía válida de backup/restore con nombre engañoso y un comando desactualizado (`./Docker/docker.sh` → `./Docker/docker.sh wizard`).
10. 🟡 **Inconsistencia sistemática de versión**: casi todos los READMEs de componentes cierran con `Platform 5.0.0-rc` cuando el parent y los módulos están en `5.0.0-rc2`.

---

## 4. Matriz de vigencia — `docs/` (26 documentos)

| Documento | Fecha | Veredicto | Acción propuesta | Evidencia principal |
|---|---|---|---|---|
| ARQUITECTURA_TRANSACCIONAL.md | 2025-11-07 | VIGENTE | KEEP | Todas las clases/props verificadas; solo marcar config recomendada como "no aplicada" |
| REFACTORING_TRANSACCIONAL.md | 2025-11-09 | VIGENTE | KEEP (nota menor) | `processEntityInTransaction(UUID)` existe; corregir commit→rollback |
| DYNAMIC_SCHEMA_REFACTORING.md | 2025-12-11 | VIGENTE | KEEP (rutas) | Anotaciones, controller `/public/validation/*` y i18n verificados; rutas `static/`→`static-legacy/` |
| CONFIG_DIRECTORY.md | 2026-01-20 | VIGENTE | KEEP | `ConfigPathResolver` idéntico al doc; añadir dashboard-rest a módulos compatibles |
| DOCKER_DEV.md | 2026-09-04 | VIGENTE | KEEP | `docker-dev.sh`, modo isolated, puertos, entrypoints verificados |
| ISSUE_INCREMENTAL_RECORD_PROCESSING.md | 2026-09-04 | VIGENTE | KEEP (renombrar opcional) | **100% verificado** — manual operativo del delta N/U/D, fingerprints, manifiesto |
| WORKERS_TASKS_ACTIONS_ANALYSIS.md | 2026-09-02 | VIGENTE | KEEP (1 línea) | Hooks `preRun…postRun`, `workflow.engine=legacy`; quitar "evolución futura" (ya implementada) |
| SEMANTIC_INDEXING_CHUNKING.md | 2026-08-17 | VIGENTE | KEEP | langchain4j 1.15.0-beta25, fórmula de estimación, propiedades — todo verificado |
| DARK_LEGACY_ARK_IMPORT.md | 2026-08-24 | VIGENTE | KEEP | Comando `import-dark-legacy-csv`, cabeceras, mapeo — verificado línea a línea |
| REFACTORING_PACKAGE_STRUCTURE.md | 2026-09-02 | VIGENTE | KEEP (absorbe guía de migración) | 10 paquetes `core.*` existen; `workflow.engine=legacy\|flowable` |
| HARVESTER_MANAGEMENT_API_V5.md | 2026-08-31 | PARCIAL | UPDATE | Endpoints correctos pero faltan `/application-actions`, `/worker-configurations`, `/dark/**`, `/network-transfers`, `/users`; sección "Límites" obsoleta (AngularJS ya está en `/legacy`) |
| IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md | 2026-08-30 | VIGENTE (sustancia) | UPDATE | Corregir migraciones: no existen `V5.0.0.9/V5.0.0.10`; las 3 tablas están en `V5.0.0.8__Harvester_action_configuration.sql` |
| ENTITY_DELETED_INDEXING.md | 2026-09-11 | VIGENTE (sustancia) | UPDATE | Enlaces absolutos `/Users/jesiel/...` rotos → rutas de repo; desplazamientos de líneas |
| AUTENTICACION_FILE_BASED.md | 2025-12-15 | PARCIAL | UPDATE | CLI real es posicional (no `-u/-p`); `$2b$` sí aceptado; hay rol VIEWER y modos `file/oidc/hybrid` no documentados; login real en `/legacy/login.html` |
| INDEXING-CONFIGURATION.md | 2025-11-09 | PARCIAL (~40% válido) | UPDATE fuerte | DLQ, `writer.threads`, `buffer.size`, `monitoring.interval` **no existen**; válidos: conexión ES, circuit breaker, reintentos, concurrencia |
| ALMACENAMIENTO_REFERENCIA_RAPIDA.md | 2026-09-02 | PARCIAL | UPDATE | Propiedad real es `metadata.store.type` (no `option`); la nota "no es máquina de estados incremental" es falsa desde 09-04 |
| ANALISIS_MERGE_ENTIDADES.md | 2025-11-07 | PARCIAL | UPDATE | Merge ya implementado: `merge_dirty_entities_and_relations()` (doc dice "vacío" y cita `process_dirty_entities`); SQL descrito sí coincide |
| ANALISIS_SYNCHRONIZED.md | 2025-11-07 | PARCIAL | UPDATE | §2/§3 ya resueltas en código; el resto (inventario de `synchronized`) vigente |
| PACKAGE_MIGRATION_GUIDE.md | 2026-09-02 | PARCIAL | UPDATE/consolidar | Migración core-lib ya hecha (0 refs a `backend.*`); la regla "backend no debe aparecer" no se cumple en app/shell/contribs; fusionar con REFACTORING_PACKAGE_STRUCTURE |
| ANALISIS_INDEXACION_MULTITHREAD.md | 2025-11-09 | OBSOLETO | ARCHIVE | Describe el pipeline buffer→distributor→writers **eliminado** en `1b894e7` (2025-11-09); sus config keys no se leen; reemplazar por doc nuevo del modelo actual |
| ARQUITECTURA_CATALOGO_SQLITE.md | 2026-09-02 | OBSOLETO | ARCHIVE | Esquema sin `change_type` (existe desde `7cf2a01`); "filtrado fino no implementado" — falso (`streamChanged`, idx_change_type) |
| ANALISIS_REDUNDANCIA_VALIDACION.md | 2026-09-02 | OBSOLETO | ARCHIVE | Afirmación central ("no existe máquina de estados incremental") superada; `record_validation` ya tiene `change_type` + manifiesto |
| ANALISIS_OPTIMIZACION_TRANSACCIONAL_READONLY.md | 2025-11-09 | PARCIAL (propuesta ya implementada) | ARCHIVE | `setReadOnly(true)` ya implementado en código; plegar como nota en REFACTORING_TRANSACCIONAL |
| HARVESTER_ADMIN_WEB_V5_TECHNICAL_PLAN.md | 2026-08-27 | OBSOLETO (plan ejecutado) | ARCHIVE + extraer backlog | Stack propuesto = stack real (React 19/Vite 7/MUI/TanStack); P0 implementados; extraer pendientes (ETag, SSE, cancelación, Playwright/MSW) a doc nuevo |
| DARK_ISSUES_PLAN_CONTEXT.md | sin commitear | PARCIAL | UPDATE + **commitear** | Rutas POST erróneas (`networks/{networkId}` → `naans/{arkNaan}`); 22→50 tests; doc de trabajo en curso |

---

## 5. Matriz de vigencia — raíz, componentes y subproyectos

### 5.1 Raíz

| Documento | Veredicto | Acción |
|---|---|---|
| `README.md` | PARCIAL (~20-25% obsoleto) | **REEMPLAZAR por `README.proposed.md`** (adjunto) |
| `README-forbackup.md` | VIGENTE (guía de backup real, mal nombrada) | MOVER a `docs/BACKUP_RESTORE.md` + corregir comando (`./Docker/docker.sh wizard`) |
| `changelog.md` | OBSOLETO (muerto desde 2024-01) | ARCHIVAR; changelog real = GitHub Releases + tags |
| `githelper.md` | VIGENTE | KEEP (comandos verificados contra el binario) |
| `.cursorrules` | PARCIAL | UPDATE: añadir `oai-pmh` y `admin-web`; matizar que `.properties.d/` no existe en todas las apps |

### 5.2 READMEs de componentes (prioridad de corrección)

| Componente | Veredicto | Correcciones principales |
|---|---|---|
| `lareferencia-entity-rest` | **OBSOLETO** | Endpoints comentados; describir estado real (1 endpoint activo, módulo en transición post-Spring-Data-Solr) |
| `lareferencia-solr-cores` | **OBSOLETO (vacío)** | **Escribir**: 7 configsets, copia `solr.v9/`, core `historic` legacy (LUCENE_42), despliegue |
| `lareferencia-core-lib/src/test/README.md` | PARCIAL | Eliminar afirmaciones de AssertJ/JaCoCo (no existen); es snapshot caducable por diseño |
| `lareferencia-core-lib` | PARCIAL | Paquetes `core.harvester`/`core.validation` no existen como top-level; versión rc2 |
| `lareferencia-lrharvester-app` | PARCIAL | `static/` = SPA React; AngularJS en `static-legacy/` (→`/legacy/`); mencionar API v5 |
| `lareferencia-entity-lib` | PARCIAL | Modelo genérico `Entity` (no clases Publication/Person/…); cliente real es **OpenSearch**; circuit breaker |
| `lareferencia-dashboard-rest` | PARCIAL | "quality indicators" no existe en código; 4 controllers `/api/v2/*` verificados |
| `lareferencia-lrharvester-admin-web` | VIGENTE | 1 corrección: default de `generate:api` es puerto 8080 |
| `lareferencia-oai-pmh` | VIGENTE | KEEP (todo verificado) |
| `lareferencia-shell` | VIGENTE | KEEP (matiz: backup es sufijo `.backup.xlsx`) |
| `lareferencia-shell-entity-plugin` | VIGENTE | KEEP (opcional: listar los 13 comandos de entidad) |
| `lareferencia-dark-lib` (+ tools) | VIGENTE | KEEP |
| `lareferencia-oclc-harvester` | VIGENTE | KEEP |
| `lareferencia-indexing-filters-lib` | VIGENTE | KEEP (matiz: filtran por regla, no "top N") |
| `lareferencia-contrib-rcaap` / `-ibict` | VIGENTE | KEEP (deprecated correcto, no compilados) |
| `entity-lib/.../README_SOLR_MIGRATION.md` | VIGENTE | KEEP |

### 5.3 Subproyectos

| Documento | Veredicto | Acción |
|---|---|---|
| `oai-pmh/docs/architecture/0001-platform-alignment.md` (ADR) | PARCIAL | KEEP + UPDATE: addendum — provider ya integrado al reactor/compose; core canónico `lareferencia-solr-cores/oai` **aún sin actualizar** (sigue en LUCENE_42) y tests usan la copia del provider; "layered" → no-layered |
| `oai-pmh/docs/testing/oai-compatibility-contract.md` | PARCIAL | KEEP + UPDATE: core real del testcontainer; capa 5 (tests diferenciales) marcarla como **pendiente** |
| `shell/docs/*.md` (5 guías es/en/pt) | VIGENTE | KEEP (menor: retirar `lite` del listado de perfiles con comandos de entidad) |
| `testing/oai-incremental/README.md` | PARCIAL | UPDATE: **puertos 8096/8196** (no 8092/8192), nota manifiesto sin `scope`, `--core` no usado |
| `.github/java-upgrade/.../progress.md` | OBSOLETO | ELIMINAR (log de intento fallido de Copilot, gitignored, no versionado) |

### 5.4 Infra (Docker, aws, .agent)

| Documento | Veredicto | Acción |
|---|---|---|
| `Docker/README.md` | VIGENTE | UPDATE menor: advertir que `reset-data` **elimina contenedores y borra módulos clonados**; typo `/solr`` |
| `aws-cloudformation/README.md` | VIGENTE | KEEP |
| `Docker/solr/import/lib_local/README.md` | VIGENTE | KEEP |
| `.agent/workflows/build.md`, `check-modules.md` | VIGENTE | KEEP |
| `.agent/workflows/configure-vufind.md` | PARCIAL | UPDATE: quitar ruta absoluta personal (`/home/juan-manitta/...`) |
| `.agent/skills/docker-similar-env/` | PARCIAL | UPDATE: `Docker/dev.sh` no existe (es `docker.sh`); añadir `entity-rest`, `oai-pmh`, `db-init` a servicios |
| `.agent/skills/vufind_config/` | VIGENTE | KEEP |

---

## 6. Plan propuesto (6 fases, en orden de ejecución)

### Fase 1 — README raíz (impacto inmediato)

Reemplazar `README.md` por el contenido de `README.proposed.md` (en inglés, corregido y actualizado). Correcciones clave incluidas: versión `5.0.0-rc2`, URLs de acceso reales, 15 módulos completos (incl. `solr-cores` y `admin-web`), admin web React como implementado, branch-set example genérico, paquete structure real (10 paquetes, 3 niveles), tabla de puertos, scripts `build-java.sh`/`build-admin-web.sh`, sección "Documentation map".

### Fase 2 — Archivar obsoletos (`git mv` → `docs/archive/`)

Crear `docs/archive/README.md` (una línea por doc: por qué quedó obsoleto y qué lo reemplaza), y mover:

1. `docs/ANALISIS_INDEXACION_MULTITHREAD.md` — pipeline eliminado en commit `1b894e7`; reemplazado por `ENTITY_INDEXING_ARCHITECTURE.md`
2. `docs/ARQUITECTURA_CATALOGO_SQLITE.md` — superado por la implementación incremental; reemplazado por `ISSUE_INCREMENTAL_RECORD_PROCESSING.md`
3. `docs/ANALISIS_REDUNDANCIA_VALIDACION.md` — idem
4. `docs/ANALISIS_OPTIMIZACION_TRANSACCIONAL_READONLY.md` — propuesta ya implementada en código; plegada como nota en `REFACTORING_TRANSACCIONAL.md`
5. `docs/HARVESTER_ADMIN_WEB_V5_TECHNICAL_PLAN.md` — plan ejecutado; backlog extraído a `HARVESTER_ADMIN_WEB_V5_BACKLOG.md`
6. `changelog.md` (raíz) — muerto; reemplazado por GitHub Releases

Fuera de `docs/`: eliminar `.github/java-upgrade/20251030155000/` (artefacto gitignored de un intento fallido).

### Fase 3 — Actualizar docs vigentes (correcciones concretas)

| Doc | Correcciones |
|---|---|
| `DARK_ISSUES_PLAN_CONTEXT.md` | Rutas POST → `/api/v5/dark/naans/{arkNaan}/…`; tests 22→50; **commitearlo** |
| `testing/oai-incremental/README.md` | Puertos → 8096 (normal) / 8196 (dev); nota 8092=dashboard |
| `HARVESTER_MANAGEMENT_API_V5.md` | Añadir endpoints nuevos (application-actions, worker-configurations, dark, network-transfers, users, metadata-cleanup preview, export/import); corregir sección "Límites actuales" |
| `AUTENTICACION_FILE_BASED.md` | CLI posicional de `add-user.py`; `$2b$` aceptado; rol VIEWER; modos `file/oidc/hybrid`; login en `/legacy/login.html` |
| `IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md` | Migraciones reales: `V5.0.0.8__Harvester_action_configuration.sql` (+ nota V5.0.0.9 es Dark runtime) |
| `ENTITY_DELETED_INDEXING.md` | Enlaces absolutos → rutas relativas de repo; refrescar números de línea |
| `INDEXING-CONFIGURATION.md` | Eliminar DLQ/buffer/monitoring inexistentes; dejar solo props reales (@Value) + circuit breaker |
| `ALMACENAMIENTO_REFERENCIA_RAPIDA.md` | `metadata.store.type` (FS/H2/SQLITE); quitar nota "no incremental" |
| `ANALISIS_MERGE_ENTIDADES.md` | Merge implementado (`merge_dirty_entities_and_relations()`); marcar conclusiones como resueltas |
| `ANALISIS_SYNCHRONIZED.md` | Marcar §2/§3 como resueltas |
| `PACKAGE_MIGRATION_GUIDE.md` | Fusionar contenido en `REFACTORING_PACKAGE_STRUCTURE.md` (convención) y archivar el resto |
| `WORKERS_TASKS_ACTIONS_ANALYSIS.md` | 1 línea: incremental ya implementado |
| `REFACTORING_TRANSACCIONAL.md` | Nota: close con `rollback` (equiv. read-only); añadir nota de optimización readonly |
| `DYNAMIC_SCHEMA_REFACTORING.md` | Rutas `static/` → `static-legacy/`; basename i18n con `ConfigPathResolver` |
| ADR `0001-platform-alignment.md` | Addendum de estado de integración |
| `oai-compatibility-contract.md` | Core real del testcontainer; capa 5 pendiente |
| `Docker/README.md` | Advertencia destructiva de `reset-data`; typo |
| `.cursorrules`, `.agent/*` | Fixes menores (módulos faltantes, rutas) |

### Fase 4 — Crear documentación nueva (inglés)

| Doc nuevo | Contenido mínimo | Reemplaza / se apoya en |
|---|---|---|
| `docs/ENTITY_INDEXING_ARCHITECTURE.md` | Modelo actual: pool fijo + semaphore backpressure + Phaser + transacciones read-only REQUIRES_NEW + circuit breaker + reintentos + props reales (@Value) | Sustituye a `ANALISIS_INDEXACION_MULTITHREAD.md` (archivado) y a la parte muerta de `INDEXING-CONFIGURATION.md` |
| `docs/HARVESTER_ADMIN_WEB_V5_BACKLOG.md` | Backlog extraído del plan archivado: ETag/If-Match, SSE, cancelación de acciones, sonda OAI Identify, validación de atributos contra JSON Schema, Playwright/MSW, cliente de API generado | Extraído de `HARVESTER_ADMIN_WEB_V5_TECHNICAL_PLAN.md` (archivado) |
| `docs/AUTHENTICATION.md` | Estado actual: file-based (users.properties, BCrypt $2a/$2b/$2y), modos `file/oidc/hybrid`, roles VIEWER/ADMIN, API v5 `/users`, `add-user.py` posicional | Consolida `AUTENTICACION_FILE_BASED.md` (que queda como registro histórico en español) |
| `docs/BACKUP_RESTORE.md` | Wizard backup/restore, cron/systemd, restore.sh, retención 7 días | De `README-forbackup.md` (renombrado y corregido) |
| `docs/WORKFLOW_ACTIONS.md` | Catálogo de acciones, configuración por red (JSONB), programación, guard, motores `legacy`/`flowable`, workers config | Nuevo; se apoya en `WORKERS_TASKS_ACTIONS_ANALYSIS.md` e `IMPLEMENTACION_CONFIGURACION_ACCIONES` (registros históricos) |
| `docs/DOCUMENTATION_INDEX.md` | Índice vivo de `docs/` con estado y fecha de última verificación (prevención de doc-rot) | Nuevo |
| `lareferencia-solr-cores/README.md` | Propósito y configsets (biblio/entity/historic/networks/oai/projects/vstats), copia `solr.v9/`, core legacy `historic`, relación con Solr 9.5/9.8 | Nuevo (el actual está vacío) |

### Fase 5 — READMEs de componentes

Aplicar las correcciones de §5.2 en orden de prioridad: `entity-rest` → `solr-cores` (Fase 4) → `core-lib` (+test) → `lrharvester-app` → `entity-lib` → `dashboard-rest` → menores.

### Fase 6 — Gobernanza (prevención)

- **Idioma**: documentación nueva en inglés; los docs históricos en español se conservan como registros de decisión con nota "historical record".
- **Encabezado de vigencia**: cada doc de `docs/` añade un header YAML (`last-verified: 2026-09-23`, `status: current|historical`) — base para el índice.
- **Regla de CI opcional**: un script `check-docs` que valide que las rutas/clases citadas en docs "current" existen (anti-rotura de enlaces).
- **Conención de fechas**: usar fecha absoluta en el nombre solo para docs de decisión/plan; docs operativos sin fecha en el nombre.

---

## 7. Orden y esfuerzo estimado

| Fase | Alcance | Esfuerzo |
|---|---|---|
| 1. README | reemplazo | bajo (borrador ya hecho) |
| 2. Archivar | 6 movimientos + archive README | bajo |
| 3. Actualizar | 18 docs con correcciones puntuales | medio (la mayoría < 30 min c/u; los 4 primeros de la tabla son los importantes) |
| 4. Docs nuevos | 7 docs (6 en `docs/` + 1 README de componente) | medio-alto (escribir de nuevo) |
| 5. READMEs componentes | ~10 correcciones | medio |
| 6. Gobernanza | headers + índice + (opcional) CI | bajo-medio |

**Orden de dependencias**: Fase 4 antes de Fase 1 definitiva, porque el README nuevo enlaza a `BACKUP_RESTORE.md`, `AUTHENTICATION.md`, `ENTITY_INDEXING_ARCHITECTURE.md` y `WORKFLOW_ACTIONS.md` (o ajustar enlaces si se prefiere aplicar el README primero).

---

## 8. Apéndice — evidencia clave (muestra)

- `pom.xml:28` → `<version>5.0.0-rc2</version>` (README dice `5.0.0-rc`).
- `lareferencia-entity-rest/config/application.properties.model:44` → `server.servlet.context-path=/api/v2`; `docker-compose.yml:266` → `LR_PORT_ENTITY_REST:-8094` (README decía 8081/entity-api).
- `docker-compose.yml:307` → `LR_PORT_OAI:-8096:8092` (host 8096); `testing/oai-incremental/README.md` usa `LR_PORT_OAI:-8092`.
- `FrontendController.java:26-31` + `WebMvcConfiguration.java:42` → SPA React en `/`, AngularJS en `/legacy/` (README decía `/harvester`).
- `workspace.ini` → sin sección `[branch-set.*]` desde commit `605d0a3` (README daba ejemplo con `v5-semantic-indexing`).
- `CatalogDatabaseManager.java:89-101` → `oai_record.change_type TEXT CHECK (IN ('N','U','D'))` + `idx_change_type` (docs "pre-incrementales" afirman que no existe).
- `EntityDataCommands.java:372,377,453` → comandos de borrado lógico/limpieza de índice (verificados).
- `ApiV5DarkController.java:71-93` → rutas reales `/api/v5/dark/naans/{arkNaan}/...`.
- `JsonElasticEntityIndexerThreadedImpl` (entity-lib): `newFixedThreadPool(indexingThreads)`, `Semaphore(threads*2)`, `Phaser`, TX read-only `REQUIRES_NEW` — el modelo actual (el pipeline de buffers del doc archivado no existe).
- `V5.0.0.8__Harvester_action_configuration.sql` → consolida las 3 tablas de acciones citadas con nombres inexistentes en `IMPLEMENTACION_CONFIGURACION_ACCIONES`.