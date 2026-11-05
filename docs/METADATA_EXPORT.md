# Exportación de metadata para enriquecimientos

**Status:** current · **Last verified:** 2026-11-05

El shell exporta metadata original o procesada desde los snapshots LGK, con los
identificadores del catálogo y referencias suficientes para vincular resultados
de clasificación o enriquecimiento con el registro de origen. La implementación
está en `lareferencia-core-lib`; los comandos y perfiles de uso están en
[`lareferencia-shell`](../lareferencia-shell/README.md).

## Perfiles

Los perfiles de ejemplo mantenidos están en
[`lareferencia-shell/config/exports/`](../lareferencia-shell/config/exports/README.md):

- `publications-v1.json`: perfil introductorio para identificadores, títulos y
  algunos campos frecuentes.
- `common-full-metadata-v1.json`: metadata completa de UY y AREANDINA con las
  mismas familias JSON, calificadores en las ocurrencias y rutas de extensión.
- `classification-embeddings-v1.json`: títulos, posibles resúmenes y keywords
  para clasificación y embeddings.

El perfil de clasificación incluye descripciones sin calificar para aprovechar
la metadata de UY. UY no distingue los abstracts de notas, afiliaciones u otras
descripciones en esos campos. Por eso `abstracts` puede contener otros textos;
AREANDINA también puede aportar descripciones no calificadas. Los calificadores
se conservan cuando la fuente los proporciona, y no se infiere un idioma.

La exportación de prueba del perfil de clasificación produjo 26.700 registros
(22.700 UY, 4.000 AREANDINA), sin errores. La exportación completa de cada fuente
se verificó contra los XML utilizados, incluidas repeticiones, textos y campos
vacíos. Esta cobertura corresponde a los snapshots estudiados; una fuente puede
añadir rutas XOAI que requieran actualizar su perfil.

El perfil `licenses-v1.json` proyecta `dc.rights.*` a `data.licenses`. Aplica
`maxLength: 300` después de `trim`: conserva la ocurrencia completa si tiene como
máximo 300 puntos de código Unicode y omite la ocurrencia si supera el límite.
No trunca valores, para no alterar identificadores ni textos de licencia. La
deduplicación conserva la primera ocurrencia.

## Comandos

Desde el shell interactivo o ejecutando el comando como argumento del JAR:

```text
export-mapping-validate --mapping /config/exports/classification-embeddings-v1.json
export-mapping-validate --mapping /config/exports/licenses-v1.json
export-metadata-preview --network UY --variant processed --mapping /config/exports/licenses-v1.json --limit 3
export-metadata-preview --network AREANDINA --variant processed --mapping /config/exports/classification-embeddings-v1.json --limit 3
export-metadata --networks UY,AREANDINA --variant processed --format jsonl --mapping /config/exports/classification-embeddings-v1.json --partition-by network --max-records 10000 --max-bytes 128MiB --compression gzip --output /exports
```

`--mapping` señala un perfil JSON. Copia los perfiles del repositorio shell a
`exports/` dentro del directorio de configuración de la instalación. Consulta el
[README de perfiles](../lareferencia-shell/config/exports/README.md) para los
comandos del ejemplo local.

Selecciona exactamente una fuente con `--network <acronym>`, `--networks <lista>`
o `--all-networks`. Se resuelven acrónimos exactos. El perfil común se probó con
`UY,AREANDINA`. El comando exporta registros activos y usa metadata procesada por
defecto. `--valid-only` filtra los registros que no pasaron validación.

Los formatos disponibles son XML, JSON y JSONL. JSON y JSONL requieren mapeo XOAI;
XML conserva el XML almacenado. La partición predeterminada es por fuente. Los
lotes cierran al alcanzar `--max-records` o `--max-bytes`; esos límites se aplican
por archivo y no al total de registros. La compresión predeterminada es GZIP.
Cada ejecución crea un directorio nuevo `exp-<uuid>` bajo `--output`.

## Identidad y trazabilidad

Los objetos JSON conservan la identidad del catálogo en campos separados. El perfil
solo construye `data`; su contrato común se ve en este ejemplo:

```json
{
  "network": "AREANDINA",
  "catalogId": "001224fc794bd93a04242afcc7dfbf66",
  "identifier": "oai:digitk.areandina.edu.co:areandina/3985",
  "metadataHash": "78ABA91B5E3BBFE6",
  "data": {
    "titles": [{"value": "Título de ejemplo", "language": "spa"}],
    "abstracts": [{"value": "Resumen de ejemplo", "qualifier": "abstract"}],
    "keywords": [{"value": "Educación", "qualifier": "unesco"}]
  }
}
```

`network` y `catalogId` forman la clave para buscar el registro en el catálogo
original. `identifier` permite contrastar la identidad OAI, y `metadataHash`
identifica el XML que se proyectó. El perfil usado se guarda como `mapping.json`;
`manifest.json` guarda el `exportId`, variante, configuración y referencias a los
snapshots. `records.sqlite` permite encontrar la fila del catálogo, el estado de la
exportación y la ubicación exacta del registro en el archivo JSON/JSONL. Los
resultados externos pueden vincularse mediante `(exportId, network, catalogId)`.

No se emite `payloadHash`: para el perfil común el JSON mantiene solo los campos de
identidad y `data`. La ubicación del XML original depende de conservar el almacén
de metadata del snapshot.

## Paquete, garantías y límites

```text
exp-<uuid>/
  manifest.json
  mapping.json
  records.sqlite
  errors.jsonl
  UY/part-000001.jsonl.gz
  AREANDINA/part-000001.jsonl.gz
```

El lector abre las bases SQLite de catálogo y validación en modo de solo lectura,
no ejecuta migraciones ni nuevas transformaciones y procesa un registro a la vez.
Fija los snapshots LGK al iniciar y detecta cambios de manifiestos o estado.
Problemas de mapeo de un registro quedan en `errors.jsonl` y producen paquete
`PARTIAL`; fallos de infraestructura producen `FAILED`. Solo consume paquetes
`COMPLETE` si el proceso posterior requiere la colección completa.

En Docker, `store.basepath` debe apuntar al almacén montado que contiene metadata
y snapshots. Los perfiles también deben estar disponibles bajo el directorio de
configuración montado, por ejemplo `/config/exports/`. La exportación no requiere
migraciones de PostgreSQL.

Los esquemas de los mapeos y del contrato de retorno están en
[`lareferencia-core-lib/src/main/resources/export/`](../lareferencia-core-lib/src/main/resources/export/).
La importación de enriquecimientos y su aplicación mediante transformadores son
trabajo posterior; no forman parte de esta exportación.
