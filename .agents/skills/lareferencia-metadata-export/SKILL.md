---
name: lareferencia-metadata-export
description: Exportar títulos, descripciones y keywords de LA Referencia y preparar paquetes bibliográficos y textos para embeddings. Usar para revisar idiomas, roles y entradas por registro.
---

# Textos bibliográficos para embeddings

Identificar el punto de partida por su manifiesto. Un `exp-…` contiene la proyección del snapshot con el perfil elegido. Un `ann-…` de tipo `annotated-metadata` ya contiene los textos clasificados. Si el pedido es revisar ejemplos, medir cobertura o cambiar la composición del texto, usar el paquete existente que corresponde a esa etapa. Resolver rutas por el ID entregado por el comando y el manifiesto, incluso si hay varias corridas del mismo país.

## Exportar o elegir perfil

Desde el checkout de plataforma consultar `docs/METADATA_EXPORT.md` y `docs/METADATA_EXCHANGE_FORMAT.md`. En el repositorio del shell, los perfiles mantenidos están en `config/exports/`. La consola Java ofrece `export-mapping-list`, `export-mapping-validate`, `export-metadata-preview` y `export-metadata`. Resolver las redes por acrónimo. Especificar la variante solicitada: el valor por defecto del exportador es `processed`. Para originales de todos los activos, usar `--variant original` y omitir `--valid-only`.

Para preparar títulos, resúmenes, keywords, afiliaciones, financiadores y tipos usar `bibliographic-roles-v1.json`. Ejemplo desde el shell, con la ruta del perfil ajustada a la instalación:

```text
export-metadata --network UY --variant original --format jsonl --mapping config/exports/bibliographic-roles-v1.json --compression gzip --output /srv/metadata-exports
```

## Preparar y consumir el paquete

Usar la guía de `lareferencia-metadata-tools` `docs/EMBEDDING_METADATA.md` como contrato de la versión instalada. Ejecutar desde el sistema operativo con el entorno virtual activo. Para instalar, usar un entorno virtual de Python 3.12 y `python -m pip install "./lareferencia-metadata-tools[bibliographic]"` desde la plataforma dentro de ese entorno. Localizar los modelos `lid.176.ftz` y `role.bin` de la ejecución deseada. Con las rutas de entrada, salida y modelos resueltas:

```sh
prepare-embedding-metadata --input "$EXPORT_DIR" --output "$OUTPUT_DIR" --models-dir "$MODELS_DIR"
```

El preparador verifica el padre JSONL `COMPLETE`. El código 0 entrega `COMPLETE`, 2 señala `PARTIAL` y 1 señala fallo. Para una entrega completa, comprobar estado, conteos, redes, snapshot, variante y hash del manifiesto padre. Si hay errores de registro, revisar `errors.jsonl` y el índice. Un reintento genera un nuevo ID.

Para obtener textos desde una carpeta anotada ya entregada, usar solo esa carpeta como datos de entrada:

```sh
build-embedding-inputs "$PACKAGE_DIR" > "$TEXTS_JSONL"
```

`--classified-only` excluye los resúmenes de respaldo. Los candidatos de idioma `und` permanecen en el paquete. El consumidor mantiene separados los títulos y resúmenes indeterminados. Lee las asignaciones de keywords de los paquetes históricos v1. Los paquetes anotados actuales conservan las keywords en la metadata. El manifiesto cuenta **ocurrencias** de keywords; para preguntas por valores únicos o por registros, calcular el denominador solicitado. Para mostrar un ejemplo literal, cruzar las entradas emitidas y la fila anotada por `packageId` del manifiesto, `network` y `catalogId`; comprobar `fields` contra los arrays de la fila. Para remontar al export, consultar `records.sqlite`, las líneas desde 1 y los índices de ocurrencia desde 0.

## Calcular y empaquetar vectores

Para un vector por ítem con título, agregá `--combine` al preparador.
Usá el directorio `embedding-inputs` completo en el host de inferencia, con
la misma revisión de metadata tools instalada mediante el extra `inference`.

```sh
compute-metadata-embeddings "$PREPARED_DIR" "$VECTOR_DIR" --revision "$MODEL_REVISION"
enrichments pack-vectors "$VECTOR_DIR" "$SQLITE_EDITION_DIR"
```

## Alcance de la comprobación

Distinguir la prueba del paquete portátil, la generación de textos y una llamada efectiva al calculador. Para esta última, revisar el contrato del servicio elegido: la llamada de vectores consume los textos en `input`, con modelo/store, dimensiones y límites configurados. La importación de colecciones v2 tiene su propio formato. La referencia de UY en la guía permite contrastar el mismo export y la misma versión; usar el manifiesto de la corrida actual al informar resultados de otro snapshot.

El preparador, sus pruebas y su contrato viven en `lareferencia-metadata-tools`. El perfil de extracción vive en el shell. La plataforma conserva la documentación transversal y el lock. Para cambios coordinados usar `lareferencia-features`; para operar el harvester de producción usar `lareferencia-harvester-ops`.
