# Exportación de metadata para enriquecimientos

**Status:** current · **Last verified:** 2026-11-16

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
- `bibliographic-roles-v1.json`: títulos, descripciones, keywords, tipos, afiliaciones y financiadores.
- `subjects-ford-v1.json`: selecciona registros con URI FORD de Argentina (BECyT) o Perú en sus materias y exporta todas las ocurrencias de títulos, descripciones y subjects.
- `licenses-v1.json`: valores de `dc.rights.*` de hasta 300 puntos de código
  Unicode. La versión 1.1 recorta espacios exteriores, excluye los prefijos de
  `info:eu-repo` y de los vocabularios COAR y deduplica por registro.

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

Ejemplo de licencias de UY para el pipeline de derechos:

```text
export-metadata --network UY --variant original --format jsonl --mapping /config/exports/licenses-v1.json --compression gzip --output /exports
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

En modo no interactivo (comando pasado al ejecutable del shell) los
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

El lector abre SQLite en modo de solo lectura inmutable (`mode=ro&immutable=1`)
y no ejecuta nuevas validaciones ni transformaciones. Si el catálogo o la base de
validación tienen un WAL no vacío, rechaza la exportación: hay que finalizar el
snapshot antes de reintentar, sin borrar manualmente el WAL. Fija los snapshots LGK al inicio y detecta cambios mientras
exporta. JSON no incluye los XML originales: recuperarlos requiere conservar el
almacén de metadata del snapshot. No se requieren migraciones PostgreSQL.

En Docker, configura `store.basepath` al almacén montado que contiene catálogos,
validaciones y metadata, y asegúrate de que los perfiles estén disponibles bajo
`<config>/exports`.

## Procesar un export completo

Tomá el directorio `exp-…` informado por el shell y comprobá que su manifiesto
indique `COMPLETE`. Conservá el paquete íntegro para que el procesador pueda
verificar los archivos y remontar los resultados al catálogo.

Desde la raíz de un checkout preparado con `githelper init` o del ZIP de
plataforma, instalá la versión incluida del módulo en un entorno virtual.
Usá Python 3.12 o posterior.

```sh
python3.12 -m venv .venv-metadata
. .venv-metadata/bin/activate
python -m pip install ./lareferencia-metadata-tools
```

- **Licencias.** Exportá metadata `original` con `licenses-v1.json`. Ejecutá
  `count-export-licenses "$EXPORT_DIR" --max-text-length 120` para obtener el
  inventario, o `run-rights-pipeline --network UY --export-dir "$EXPORT_DIR"`
  para publicar `enrichments.sqlite`. Para exportar y procesar en una sola
  operación, usá `run-rights-pipeline --network UY --shell-dir "$SHELL_DIR"`.
  [Guía de enriquecimientos](https://github.com/LA-Referencia-IOI/lareferencia-metadata-tools/blob/main/docs/METADATA_ENRICHMENT_PACKAGE.md)
- **Embeddings.** Exportá con `bibliographic-roles-v1.json` e instalá el
  extra `./lareferencia-metadata-tools[bibliographic]` para ejecutar
  `prepare-embedding-metadata --combine`. En la máquina de cálculo, instalá el
  extra `inference` de la misma revisión y ejecutá
  `compute-metadata-embeddings --format sqlite` para publicar
  `embeddings.sqlite`, o `--format jsonl` para obtener las partes JSONL
  comprimidas. `enrichments pack-vectors` permite obtener ambos formatos
  a partir de un único cálculo en JSONL sobre textos preparados.
  [Guía de embeddings](https://github.com/LA-Referencia-IOI/lareferencia-metadata-tools/blob/main/docs/EMBEDDING_METADATA.md)
- **Anotaciones FORD.** Con un export `subjects-ford-v1.json`, ejecutá
  `prepare-embedding-metadata --input "$EXPORT_DIR" --output "$OUTPUT_DIR" --models-dir "$MODELS_DIR" --annotation-profile ford-level2 --include-provenance`.
  Conserva títulos e idiomas, resúmenes y otras descripciones, todos los
  `subjects` originales y los códigos BECyT de segundo nivel en `subjectTerms`.
  `auto` elige este perfil para `subjects-ford`; los perfiles anteriores siguen
  usando la vista `bibliographic`. Esta vista FORD no se combina con `--combine`.
  [Contrato de perfiles de anotación](../lareferencia-metadata-tools/docs/EMBEDDING_METADATA.md#annotation-profiles-and-ford-subjects)
