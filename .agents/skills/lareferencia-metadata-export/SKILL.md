---
name: lareferencia-metadata-export
description: Exportar y anotar metadata bibliográfica de LA Referencia, preparar datasets de clasificación FORD y calcular embeddings en JSONL o SQLite. Usar para revisar idiomas, roles, etiquetas y trazabilidad por registro.
---

# Metadata bibliográfica para embeddings y clasificación

Identificar el punto de partida por su manifiesto. Un `exp-…` contiene la proyección del snapshot. Un `ann-…` de tipo `annotated-metadata` contiene los títulos y resúmenes anotados. Un `cls-…` de tipo `classification-dataset` contiene un texto por registro y sus etiquetas de referencia. Reutilizar el paquete correspondiente al pedido y resolver su ruta por el ID del manifiesto.

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

## Preparar clasificación FORD

Para reunir casos con FORD, exportá con `subjects-ford-v1.json`. Ese perfil filtra registros por URI en los subjects. Para predecir sobre todo el catálogo, partí de un perfil bibliográfico que incluya los registros sin FORD. Para conservar las etiquetas de referencia, asegurate de que la extracción incluya las URI FORD en `subjects` o `keywords` y anotá con `--annotation-profile ford-level2`.

El preparador resuelve `--annotation-profile auto` a `ford-level2` para `subjects-ford` 1.0 y a `bibliographic` para los perfiles bibliográficos anteriores. La vista FORD conserva las ocurrencias originales en `subjects` y agrega `subjectTerms` con códigos BECyT de segundo nivel, deduplicados por registro. Agregá `--include-provenance` para verificar qué ocurrencias alimentaron cada código.

```sh
prepare-classification-dataset --input "$ANNOTATED_DIR" --output "$OUTPUT_DIR" \
  --mode train --text-format gemma-classification

prepare-classification-dataset --input "$OTHER_ANNOTATED_DIR" --output "$OUTPUT_DIR" \
  --mode predict --recipe-from "$TRAIN_PACKAGE"
```

Usá el `ann-…` completo de contrato v2. El comando agrupa títulos y resúmenes por idioma en un único texto por registro. Por defecto usa los resúmenes clasificados, con `--include-fallback` para sumar los de respaldo. `plain` guarda el contenido bibliográfico y `gemma-classification` incluye el prefijo literal `task: classification | query: `, con el espacio final.

`train` requiere al menos una etiqueta. `predict` conserva las etiquetas conocidas para evaluar resultados y escribe `labels: null` cuando falta la referencia. Usá `--recipe-from` para reproducir el formato y la selección de texto del entrenamiento. Las métricas se calculan sobre los registros con referencia. El manifiesto distingue registros emitidos, omitidos por falta de etiqueta y omitidos por falta de texto.

## Calcular y empaquetar vectores

Para búsqueda, `--combine` en el preparador bibliográfico produce `embedding-inputs`. Para clasificación usá directamente el `classification-dataset` completo como `PREPARED_DIR`. Instalá el extra `inference` de la revisión correspondiente en el host de cálculo y fijá el commit exacto del modelo.

```sh
compute-metadata-embeddings "$PREPARED_DIR" "$SQLITE_EDITION_DIR" \
  --revision "$MODEL_REVISION" --format sqlite
```

Para clasificación usá **768 dimensiones**, el valor predeterminado al omitir `--dimensions`, salvo que se solicite otra dimensión o haya que reproducir la configuración de un clasificador ya entrenado. El calculador codifica el texto preparado con prompt adicional vacío. Usá la misma revisión, receta, dimensión y política de tokens al entrenar y predecir.

El destino debe ser una carpeta nueva. `--format jsonl` genera JSONL GZIP. `--format sqlite` entrega `embeddings.sqlite` y `manifest.json`. Para obtener ambos de una sola corrida, generá JSONL y convertí con `enrichments pack-vectors`. Ambos formatos conservan las etiquetas FORD junto a los vectores. En SQLite, `enrichments lookup-vector` devuelve el vector y las etiquetas por red e ID de catálogo.

Verificá el estado, los conteos, la revisión, las dimensiones y los truncamientos en el manifiesto. Para clasificación, compará `labels` con la entrada por `(network, catalogId)`. En SQLite, comprobá que el BLOB de cada vector ocupe cuatro bytes por dimensión y que las etiquetas JSON o SQL NULL correspondan al registro. Consultá el esquema en `docs/EMBEDDING_METADATA.md`.

## Alcance de la comprobación

Al informar una prueba, indicar si se verificó el paquete, se generaron textos o se ejecutó el modelo real. Si el pedido usa un servicio remoto en lugar del calculador local, consultar su contrato de inferencia e importación. Informar el snapshot, los conteos y la configuración con el manifiesto de la corrida actual.

El preparador, sus pruebas y su contrato viven en `lareferencia-metadata-tools`. El perfil de extracción vive en el shell. La plataforma conserva la documentación transversal y el lock. Para cambios coordinados usar `lareferencia-features`; para operar el harvester de producción usar `lareferencia-harvester-ops`.
