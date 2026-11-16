# 5.0.0-rc4: alcance de fuentes y estado de integración

**Status:** current · **Last verified:** 2026-11-16

## Estado de publicación

La rc4 publicada en GitHub apunta al coordinador `32b4719` e incluye el flujo de
instalación congelada, la herencia de versión de los módulos, la sincronización npm
y las correcciones de integración ya mergeadas.

El `main` local de esta revisión contiene además los aportes locales que se
integraron después de esa publicación:

| Repositorio | Commit conservado | Aporte |
|---|---|---|
| Plataforma | `0553d5c` | Guía detallada del formato de intercambio y documentación de exportación |
| core-lib | `791b2b3` | Lecturas SQLite inmutables, rechazo de WAL no vacío y progreso de exportación |
| shell | `1ac52a4` | Listado de perfiles y diferenciación de exportaciones parciales en modo batch |

Las correcciones de documentación de esta revisión también son locales.
**La publicación existente no se ha sustituido.** Clonar su tag recupera la
combinación publicada, no estos cambios adicionales. Para reproducir la integración
se necesitan los commits del `workspace.lock` de este checkout; mientras alguno
solo exista localmente, un clon remoto no podrá descargarlo con `githelper init`.
El número de versión compartido por sí solo no sustituye al lock como identidad
de las fuentes.

## Módulos y versiones

El manifest declara 15 repositorios: diez módulos Java y dos frontends activos,
solr-cores y los dos contrib legacy. El reactor completo incluye esos doce módulos
activos más el padre. Todos los activos heredan `5.0.0-rc4` de
`lareferencia-parent`; las dependencias internas están centralizadas y los archivos
npm se sincronizan con esa versión. Los contrib conservan 4.2.6. VuFind es externo
y no está incluido en el manifest, lock ni ZIP de plataforma.

## Instalación y desarrollo

Una versión publicada se prepara con `githelper init` y se compila con Maven o los
scripts existentes, sin un stamp manual. `githelper switch VERSION` alinea otro
checkout publicado. Para desarrollar, `feature start` crea ramas desde main,
`feature add` incorpora módulos y `pr` crea o actualiza los PR con cambios.

`release prepare` deja la versión escrita antes del merge. Después de integrar
los PR de módulos, se repite para capturar sus SHA finales. CI valida lock y
versiones y compila una descarga limpia. El merge del coordinador etiquetado
publica esa versión. Consulte [githelper](../githelper.md).

## Comportamiento documentado en esta revisión

- Admin React en `/admin/` y Dashboard Angular en `/dashboard/{en,es,pt}/`, con
  `admin-static/` y `dashboard-static/` separados.
- PostgreSQL 17 y Solr 9.11 como bases del Compose actual; PostgreSQL 15 para las
  pruebas opcionales y Solr 9.8 para las integraciones del proveedor OAI.
- Exportación LGK de solo lectura: snapshots finalizados, perfiles XOAI → JSON,
  identidad y procedencia conservadas y estados COMPLETE/PARTIAL/FAILED.
- Códigos de salida batch de exportación: 0/2/1 respectivamente. El contrato de
  retorno de enriquecimientos está definido; su importación no está implementada
  por este flujo.

## Verificación y pendientes

La integración de documentación, core y shell pasó la suite completa el
2026-11-16: 1.424 casos Maven sin fallos ni errores (uno deshabilitado), 74 pruebas
de frontend y 43 de herramientas. Los cambios posteriores de esta revisión son
documentación y la corrección de ruta del helper de build de Admin.

La compilación no equivale a una validación de navegador del Dashboard. Sus
pruebas end-to-end, traducciones y despliegue TLS que sigan pendientes se mantienen
marcados en [la guía de migración](DASHBOARD_V5_MIGRATION.md).

Referencias: [instalación](ONBOARDING.md), [arquitectura](ARCHITECTURE.md),
[exportación](METADATA_EXPORT.md), [formato de intercambio](METADATA_EXCHANGE_FORMAT.md).
