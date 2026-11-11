# Exportación de metadata para enriquecimientos

**Status:** current · **Last verified:** 2026-11-11

El shell exporta metadata original o procesada desde snapshots LGK para
clasificación y enriquecimiento externo. Usa el acrónimo de red, el ID del
catálogo original y el identifier OAI para preservar la relación con los
registros de origen.

Esta guía cubre perfiles disponibles y comandos. El contrato minucioso de los
archivos, JSON/XML, trazabilidad, manifiesto, índice SQLite y retorno de
enriquecimientos está en [Formato de intercambio](METADATA_EXCHANGE_FORMAT.md).

## Perfiles instalados

Los perfiles mantenidos están en
[`lareferencia-shell/config/exports/`](../lareferencia-shell/config/exports/README.md):

- `publications-v1.json`: ejemplo inicial de identificadores, dARK, títulos y
  abstracts.
- `common-full-metadata-v1.json`: metadata completa común a UY y AREANDINA, con
  calificadores y extensiones identificadas por ruta.
- `classification-embeddings-v1.json`: títulos, posibles resúmenes y keywords.
  Incluye descripciones sin calificar; en UY pueden ser notas, afiliaciones u
  otros textos además de resúmenes.
- `licenses-v1.json`: valores de `dc.rights.*` de hasta 300 puntos de código
  Unicode; recorta espacios exteriores, deduplica y omite valores largos sin
  truncarlos.

Para listar los JSON disponibles en el directorio de configuración:

```text
export-mapping-list
```

Por defecto lee `<config>/exports`; admite `--directory <path>`. Para validar o
inspeccionar una muestra:

```text
export-mapping-validate --mapping /config/exports/licenses-v1.json
export-metadata-preview --network UY --variant processed --mapping /config/exports/licenses-v1.json --limit 3
```

## Exportar

Selecciona exactamente una fuente con `--network <acronym>`, `--networks <lista>`
o `--all-networks`. Los acrónimos se resuelven exactamente. Ejemplo de
exportación conjunta de UY y AREANDINA para clasificación y embeddings:

```text
export-metadata --networks UY,AREANDINA --variant processed --format jsonl --mapping /config/exports/classification-embeddings-v1.json --partition-by network --max-records 10000 --max-bytes 128MiB --compression gzip --output /exports
```

Ejemplo de licencias de UY:

```text
export-metadata --network UY --variant processed --format jsonl --mapping /config/exports/licenses-v1.json --compression gzip --output /exports
```

Los formatos disponibles son XML, JSON y JSONL. JSON/JSONL requieren `--mapping`;
XML conserva la metadata XOAI y permite `--layout collection|per-record`.
La variante predeterminada es `processed`; el filtro `--valid-only` excluye
registros no válidos y requiere resultados de validación. Sin él se exportan
registros activos válidos e inválidos. La partición predeterminada es por red.

Cada ejecución crea un directorio `exp-<UUID>` nuevo. Los lotes predeterminados
son 10.000 registros o 128 MiB UTF-8 sin comprimir por archivo. GZIP es la
compresión predeterminada. Los límites y opciones completos se muestran con:

```text
help export-metadata
```

En modo no interactivo (script o `--network ...` por línea de comandos) los
exit codes distinguen resultados: `COMPLETE` termina con 0, `PARTIAL` con 2
(por registros con error; el paquete y su `errors.jsonl` son consumibles
parcialmente) y `FAILED` con 1. El progreso se registra en el log cada 10.000
registros y por fuente, con su `exportId` para correlacionar.

## Lectura del paquete y garantías

Un paquete contiene `manifest.json`, `records.sqlite`, `errors.jsonl` y archivos
de datos. Para JSON se incluye la especificación usada como `mapping.json`.
Los registros JSON se mantienen compactos con `network`, `catalogId`,
`identifier`, `metadataHash` y `data`. El manifiesto describe variante,
snapshot, opciones y hashes de archivos; `records.sqlite` vincula cada intento
con estado, hash original y ubicación exacta. `errors.jsonl` contiene problemas
por registro; estos dejan el paquete en estado `PARTIAL`. Un fallo de
infraestructura deja `FAILED`. Para colecciones completas, consume solo paquetes
`COMPLETE`.

El lector abre SQLite en modo de solo lectura y no ejecuta nuevas validaciones ni
transformaciones. Fija los snapshots LGK al inicio y detecta cambios mientras
exporta. JSON no incluye los XML originales: recuperarlos requiere conservar el
almacén de metadata del snapshot. No se requieren migraciones PostgreSQL.

En Docker, configura `store.basepath` al almacén montado que contiene catálogos,
validaciones y metadata, y asegúrate de que los perfiles estén disponibles bajo
`<config>/exports`.
