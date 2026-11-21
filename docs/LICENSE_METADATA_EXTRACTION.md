# Extracción de derechos para construir un inventario de licencias

**Status:** current · **Campaña:** 19–20 de noviembre de 2026

Se exportaron los derechos de **17 fuentes nacionales** de LA Referencia y se construyó un inventario de cadenas candidatas a licencia. La unidad del export es un registro de catálogo. En los JSONL derivados, la unidad es un valor de derechos y su conteo. El consolidado tiene **390.673 valores distintos**.

Este informe documenta la campaña, los filtros y cómo reproducir los resultados. Para el contrato general del exportador, consulta el [formato de intercambio](METADATA_EXCHANGE_FORMAT.md) y la [guía de exportación](METADATA_EXPORT.md).

## 1. Fuente y selección de registros

La campaña se ejecutó en el harvester de producción `lrhar`, con el almacén en `/volumes/tmp/data/` y los paquetes en `/srv/metadata-exports/`. Se ejecutó una exportación por acrónimo y se fijó el snapshot LGK disponible para la fuente al inicio de cada export. Los IDs de snapshot de la tabla identifican esa selección histórica. Una nueva ejecución puede resolver un LGK más reciente.

- **Variante `original`**. Se lee el XML almacenado bajo el hash original del catálogo, anterior a las transformaciones de validación.
- **Todos los registros activos**. El catálogo se recorre por ID con `deleted=0`. Se omitió `--valid-only`, por lo que la selección no depende de que el registro haya pasado la validación. Un registro activo sin derechos exportables se conserva con un array vacío.
- Se exportó desde el almacén de snapshots. Los paquetes conservan referencias y hashes para identificar el XML original. Recuperar ese XML requiere disponer del almacén correspondiente.

## 2. Proyección XOAI

Se usó [`licenses-v1.json`](../lareferencia-shell/config/exports/licenses-v1.json), perfil `licenses` versión `1.0`, con `specVersion: 1` e `inputSchema: xoai`. Los 17 manifiestos finales registran el mismo hash canónico del perfil:

```text
sha256:9da2a24cb6ccfa99a9498f63fd78545c99ef65b6dc7796a83df89a6ad9c95229
```

```json
{
  "licenses": {
    "select": "dc.rights.*",
    "type": "string",
    "many": true,
    "normalize": ["trim"],
    "unique": true,
    "maxLength": 300
  }
}
```

1. `dc.rights.*` recorre los elementos descendientes de `dc.rights` a cualquier profundidad. El comodín excluye al propio elemento `dc.rights` y por tanto a sus campos directos.
2. El selector implícito de valor toma sus `<field name="value">` directos. El evaluador usado en la campaña también acepta `<field>` sin atributo `name` como valor.
3. La regla aplica `trim`, omite la ocurrencia si supera **300 puntos de código Unicode** y deduplica valores iguales conservando la primera aparición. El límite del perfil alcanza también a las URLs.
4. La salida es `data.licenses`, un array de cadenas. Esta proyección usa los calificadores para localizar los valores, pero no los incluye en el array junto con el idioma o la ruta XOAI.

Este ejemplo es un registro de la previsualización de Argentina:

```json
{
  "network": "AR",
  "catalogId": "000053498a5e8f543d1fdf18572ca4ce",
  "identifier": "oai:ucacris:123456789/13399",
  "metadataHash": "99E10C03DDD57B93",
  "data": {
    "licenses": [
      "info:eu-repo/semantics/openAccess",
      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
    ]
  }
}
```

En esta etapa se conservan tanto las condiciones de acceso breves como las licencias. La separación de vocabularios se aplica al generar el inventario, de modo que el paquete de origen sigue siendo útil para auditar el recuento.

## 3. Exportación y artefactos

Comando equivalente, ejecutado desde el directorio configurado del shell, con una copia del JAR por ejecución para aislarla de recompilaciones:

```bash
java -jar /ruta/ejecucion/lareferencia-shell.jar export-metadata \
  --network CL --variant original --format jsonl \
  --mapping /ruta/ejecucion/licenses-v1.json \
  --partition-by network --max-records 10000 --max-bytes 128MiB \
  --compression gzip --output /ruta/salida
```

Cada paquete `exp-<UUID>` contiene:

| Archivo | Uso |
|---|---|
| `<PAÍS>/part-*.jsonl.gz` | Un objeto por registro en UTF-8. Hasta 10.000 registros o 128 MiB sin comprimir por lote, con la excepción general para registros sobredimensionados. |
| `manifest.json` | Configuración efectiva, snapshot, estado, conteos, inventario, tamaños y SHA-256 de los archivos. |
| `mapping.json` | Especificación aplicada. |
| `records.sqlite` | Índice de identidad, procedencia y posición del registro. La clave de cruce con el catálogo es `(network, catalogId)`. |
| `errors.jsonl` | Diagnósticos por registro. Los 17 paquetes finales quedaron `COMPLETE` y con cero errores. |

AR y BR se ejecutaron por separado. Para los otros 15 países se usó `extract_countries.py`, un proceso desacoplado de SSH que los recorrió en serie y guardó estado por país, un log por export y un log general. Cada país con export completo pasó al recuento. Un fallo quedó registrado en el estado individual y el lote continuó con el siguiente país.

El primer intento de CL exportó 310.260 filas sin errores de registro, pero acabó `FAILED` por la comprobación de consistencia del snapshot. El WAL de validación, presente y vacío al inicio, ya no estaba al revisar el fallo. La corrección `2beb753a1cfd03931ee5af41e2932578489f38c9` trata un WAL de cero bytes igual que uno ausente. La protección frente a un WAL con datos pendientes se mantiene. Se repitió CL con el JAR actualizado y se usó únicamente ese segundo paquete en el inventario.

## 4. Recuento por país

El script [`count_export_licenses.py`](../scripts/count_export_licenses.py) usa la biblioteca estándar de Python. Comprueba que el paquete esté `COMPLETE`, sea JSONL y que el mapeo declare `licenses`. Lee las partes listadas en el manifiesto y comprueba que el número de registros leídos coincida con `counts.exported`. Cada `data.licenses` se valida como array de cadenas. Este recuento comprueba forma y cobertura de filas. La comprobación criptográfica de las partes puede hacerse por separado con el inventario del manifiesto.

```bash
python3 scripts/count_export_licenses.py /ruta/exp-UUID \
  --max-text-length 120 > CL-licencias-valores-unicos.jsonl
```

Para cada registro, el script quita espacios exteriores con `str.strip()`, forma un conjunto de valores y aplica estos filtros:

| Criterio | Regla aplicada |
|---|---|
| Vacíos | Se descarta la cadena vacía tras quitar espacios exteriores. |
| `info:eu-repo` | Se descarta el prefijo inicial `info:eu-repo` cuando va seguido de `/` o del fin del valor, sin distinguir mayúsculas. |
| COAR | Se descartan valores que empiezan por `purl.org/coar` o `vocabularies.coar-repositories.org` seguido del fin, `/`, `?` o `#`. Se aceptan como variantes del prefijo `http://`, `https://` y `www.`, sin distinguir mayúsculas. |
| Texto largo | Se descartan cadenas de más de 120 puntos de código. Para esta regla, una URL web necesita esquema HTTP(S), hostname y ausencia de espacios o saltos de línea. Las URLs que cumplen esa condición quedan exentas del límite de 120. |

Un valor cuenta **una vez por registro** dentro de un país. Si un registro trae valores distintos, cada uno recibe su propio conteo. La salida se ordena por `recordCount` descendente y luego por `value` ascendente para desempatar.

```jsonl
{"value":"https://creativecommons.org/licenses/by-nc-sa/2.5/ar/","recordCount":118212}
{"value":"http://creativecommons.org/licenses/by-nc-sa/4.0/","recordCount":37580}
```

En AR se observaron 1.055 cadenas distintas antes del filtro de inventario. El resultado final fue de 890. Tres cadenas que comenzaban con una URL y seguían con texto largo se descartaron al aplicar la comprobación de URL completa. Los vocabularios se detectan por prefijo. Un vocabulario incrustado en medio de un texto queda fuera de esa regla.

## 5. Consolidación entre países

Se reunieron los 17 archivos por país en `~/Downloads/licencias-17-paises/`. Para AR se reutilizó el JSONL ya guardado en Downloads tras ejecutar el recuento en el harvester. Los otros 16 se copiaron por SFTP desde el harvester. Se verificaron los conteos esperados, el esquema de cada línea y la ausencia de duplicados dentro de cada país.

Se agruparon las filas por igualdad exacta de `value`, sin plegar mayúsculas, unificar protocolos, ajustar barras finales ni traducir nombres. Cada grupo conserva:

| Clave | Significado |
|---|---|
| `value` | Cadena resultante de la fase de recuento. |
| `recordCountByCountry` | Conteo del mismo valor en cada país donde apareció. |
| `recordCount` | Suma de los conteos nacionales del valor. |

El consolidado se llama `licencias-valores-unicos-consolidadas.jsonl` y se ordena por conteo total descendente y por valor ascendente. La verificación comprobó el desglose por país, la correspondencia de cada conteo total con la suma nacional y que ninguna entrada nacional se perdiera al agrupar.

- **392.210** líneas de entrada sumadas entre países.
- **390.673** líneas consolidadas.
- **1.537** líneas fusionadas por coincidencia exacta.
- **858** valores presentes en dos o más países.
- **35.037.623 bytes** en los 17 JSONL nacionales y **46.281.692 bytes** en el consolidado. El consolidado añade el desglose por país a cada línea.

## 6. Resultados y procedencia por país

| Código | País | Snapshot | Export ID | Registros exportados | Valores únicos |
|---|---|---:|---|---:|---:|
| AR | Argentina | 3609 | `exp-e799e369-455f-4e14-b248-4bc641fba8e9` | 341.764 | 890 |
| BO | Bolivia | 4188 | `exp-8b291e78-4481-49af-87d7-ba0a5dbb56ee` | 605 | 0 |
| BR | Brasil | 4193 | `exp-f95aa0cd-e579-4144-8f17-f6cc3cefe138` | 4.163.778 | 155.248 |
| CL | Chile | 4167 | `exp-96d4a09b-6fdb-4dd9-b34b-e2782a6ba9ee` | 310.260 | 4.699 |
| CO | Colombia | 4016 | `exp-63d5aac6-233b-4ae4-b103-d432bc20e051` | 262.906 | 7.395 |
| CR | Costa Rica | 3607 | `exp-a99ef81e-c1b9-4acc-9a57-4c9ea6ef26dc` | 87.040 | 5.810 |
| CU | Cuba | 4192 | `exp-451be763-f4c9-48bc-a4a6-2b326a350288` | 2.162 | 65 |
| DO | República Dominicana | 4180 | `exp-aa987de8-5b81-4579-ba83-14de9a6613c8` | 2.260 | 69 |
| EC | Ecuador | 4122 | `exp-04e3d4ef-b546-4ca3-87c6-33fc8ab84315` | 655.493 | 6.232 |
| ES | España | 4190 | `exp-16944706-3e6d-45fd-98aa-edeccf64ce9d` | 4.370.252 | 142.138 |
| MX | México | 4053 | `exp-581e55c2-6179-4e72-97ed-347f4c2aebd0` | 1.317.195 | 41.375 |
| PA | Panamá | 3613 | `exp-9006b7d6-97cc-489d-afde-75bf2287bc5d` | 3.444 | 23 |
| PE | Perú | 4139 | `exp-e2ea1fa2-4fe6-4903-b5d7-9c98e3a42d80` | 975.117 | 25.835 |
| PY | Paraguay | 4195 | `exp-5ffc2c9f-7d1c-4ad1-9765-be8e854c51ff` | 1.935 | 308 |
| SV | El Salvador | 4194 | `exp-09e17a6d-df95-40db-bb98-aa975ce2b5fa` | 2.888 | 745 |
| UY | Uruguay | 4186 | `exp-885b8a99-0704-42a8-8dd8-4c32eb04235c` | 30.752 | 1.369 |
| VE | Venezuela | 4170 | `exp-edb84d74-11b8-4a5e-b40e-4f05a548836b` | 5.739 | 9 |
| | **Total antes de consolidar** | | | **12.533.590** | **392.210** |

SHA-256 del JSONL consolidado local: `f022b6b4422f2c4a8620c17cbcffe9c892e8ef86811a2201f5559be0676540ba`.

## 7. Ubicación y uso de los resultados

| Conjunto | Ubicación |
|---|---|
| AR | Paquete `lrhar:/srv/metadata-exports/exp-e799e369-455f-4e14-b248-4bc641fba8e9/`. |
| BR | `lrhar:/srv/metadata-exports/br-licenses-run-20261119T202807Z/`. |
| Lote de países | `lrhar:/srv/metadata-exports/licenses-countries-20261119T203721Z/`. Incluye los JSONL completados, los paquetes bajo `packages/<PAÍS>/` y el primer intento de CL. |
| CL | `lrhar:/srv/metadata-exports/cl-licenses-retry-6lmtjvh6/`. Incluye el paquete final y el JSONL. |
| Copia de revisión | `~/Downloads/licencias-17-paises/`, con los 17 JSONL y el consolidado. |

Los valores del inventario son **candidatos**. Pueden ser licencias, URLs de repositorio o textos breves sobre derechos. Un valor con dos variantes de escritura ocupa dos filas. El conteo total suma registros dentro de cada país y no deduplica publicaciones repetidas entre catálogos. Bolivia produjo un archivo vacío porque ningún valor pasó los filtros entre los 605 registros exportados.

Para agrupar Creative Commons, la unidad de equivalencia propuesta es **tipo, versión y jurisdicción**. Por ejemplo, las URLs HTTP y HTTPS, con o sin barra final, o con sufijo `deed.es` de CC BY-NC-SA 4.0 Internacional pueden resolverse a una sola clave. CC BY-NC-SA 2.5 Argentina conserva su propia clave. Los nombres textuales se pueden asociar cuando el tipo, la versión y la jurisdicción se puedan resolver con evidencia suficiente.

El conteo de una licencia normalizada se recalcula sobre los registros del paquete, tomando una sola presencia por grupo dentro de cada registro. En AR se comprobó con dos URLs de CC BY-NC-SA 4.0 y su nombre completo: las tres variantes sumaban 89.538 presencias, pero correspondían a 56.443 registros únicos. Los agregados por valor permiten revisar candidatos y frecuencias. Para obtener el conteo por licencia agrupada se necesita volver a los registros fuente.
