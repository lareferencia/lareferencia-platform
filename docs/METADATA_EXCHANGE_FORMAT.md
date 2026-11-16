# Formato de intercambio de metadata y enriquecimientos

**Status:** current · **Last verified:** 2026-11-16

Este documento especifica el paquete que produce el exportador de metadata y el
formato recomendado para devolver resultados externos. Describe el contrato
implementado en `lareferencia-core-lib` y utilizado por los comandos de
`lareferencia-shell`. La importación de enriquecimientos y su aplicación por
transformadores todavía no forman parte de este flujo.

Para instalar perfiles y ejecutar comandos, consulta la [guía de exportación](METADATA_EXPORT.md).
Los esquemas JSON normativos están en
[`lareferencia-core-lib/src/main/resources/export/`](../lareferencia-core-lib/src/main/resources/export/).

## 1. Principios del intercambio

- Cada exportación es un paquete inmutable identificado por `exportId`.
- La identidad de catálogo se expresa con el acrónimo público de la red y el
  `catalogId` almacenado por esa red. El `identifier` OAI se conserva como
  identidad contrastable, pero no reemplaza al ID del catálogo.
- El `metadataHash` identifica la metadata exacta proyectada. La variante y el
  snapshot se describen en el manifiesto y en el índice SQLite.
- El perfil solamente transforma el XML XOAI en `data`; no modifica la
  identidad ni ejecuta transformaciones del harvester.
- Los resultados externos deben devolver las claves de entrada y el hash para
  poder detectar resultados asociados a otra metadata.
- Los nombres y valores de rutas se deben tratar como sensibles a la versión del
  perfil. No se deben inferir campos que el perfil no haya exportado.

## 2. Estructura del paquete

Cada ejecución crea un directorio nuevo `exp-<UUID>` debajo de `--output`:

```text
exp-<UUID>/
  manifest.json
  mapping.json                 # solo JSON y JSONL
  records.sqlite
  errors.jsonl
  UY/                          # cuando partitionBy=network
    part-000001.jsonl.gz
  data/                        # cuando partitionBy=none
    part-000001.jsonl.gz
```

Los nombres de directorio de red se sanitizan para el sistema de archivos; el
acrómino dentro de los datos permanece exacto. El exportador rechaza colisiones
entre nombres de directorio sanitizados. En partición `none`, los acrónimos de
cada registro permiten distinguir las fuentes.

`mapping.json` es una copia de la especificación usada. El manifiesto incluye el
hash canónico de esa especificación. XML no lleva `mapping.json` porque no usa
perfil. `records.sqlite` contiene un índice para cada registro intentado,
incluidos los filtrados y los que dieron error. `errors.jsonl` contiene una
línea por error de registro; cuando no hay errores es un archivo vacío.

Cada archivo entregado, salvo `manifest.json`, aparece en `manifest.json` con su
ruta relativa, tamaño en bytes y SHA-256 de los bytes finales en disco. Para
GZIP, el tamaño y el hash corresponden al archivo comprimido. El manifiesto no
se incluye a sí mismo en `files`, ya que eso requeriría un hash recursivo.
Los archivos se escriben temporalmente y se renombran al cerrarse; ante una
interrupción puede quedar un paquete `FAILED` con diagnósticos parciales.

## 3. Registro JSON

JSON y JSONL usan el mismo objeto por registro. El formato actual compacta la
envoltura así:

```json
{
  "network": "UY",
  "catalogId": "0002f315df52dbcb76631ad201c8d2a5",
  "identifier": "oai:portal.ucr.ac.cr:article/6018",
  "metadataHash": "BB8CCCE2D72C1F0B",
  "data": {
    "licenses": [
      "http://creativecommons.org/licenses/by/4.0",
      "info:eu-repo/semantics/openAccess"
    ]
  }
}
```

| Clave | Significado |
|---|---|
| `network` | Acrónimo exacto de la red. |
| `catalogId` | ID de la fila del catálogo original; se conserva como string, aunque parezca numérico. |
| `identifier` | Identificador OAI del registro, tomado del catálogo, no recalculado desde XML. |
| `metadataHash` | Hash de metadata seleccionado según `variant`. No es el hash del JSON `data`. |
| `data` | Proyección construida por `mapping.json`; sus campos son los nombres definidos por el perfil. |

El objeto de salida por sí solo no incluye `exportId`, `recordKey`,
`snapshotRef`, `originalMetadataHash`, ni `variant`. Esos valores se resuelven
combinando el paquete: `exportId` está en el manifiesto; `recordKey`, variante,
snapshot y hash original están en `records.sqlite`. Dentro del paquete, la clave
`record_key` se forma como `<network>_<catalogId>`. La identidad recomendada
para el intercambio de resultados es `(exportId, network, catalogId)` y se
debe comparar también `metadataHash` antes de aplicar un enriquecimiento.

`network` y `catalogId` deben mantenerse en campos separados; no dividir
`record_key` suponiendo reglas particulares sobre acrónimos o IDs. `identifier`
ayuda a detectar inconsistencias y a inspeccionar resultados, pero el remapeo al
catálogo se realiza con `network` y `catalogId`.

### 3.1 JSON y JSONL

- `jsonl`: un objeto JSON compacto por línea UTF-8, sin envoltorio de array.
  Las posiciones de `records.sqlite` comienzan en 1.
- `json`: un array JSON por archivo. Las posiciones comienzan en 0.
- `gzip`: comprime cada parte independientemente; cada archivo `.gz` se puede
  descomprimir sin depender de las otras partes.
- `none`: escribe los mismos bytes sin compresión.

No se divide un registro entre partes. JSONL suele ser más sencillo para
procesamiento por streaming; JSON facilita consumir lotes pequeños como un
array. La ordenación de claves del objeto no es una garantía semántica del
contrato.

### 3.2 XML

XML no acepta `--mapping`; conserva la metadata XOAI guardada. El layout
`collection` crea documentos XML bien formados con raíz `<records>`. Cada
registro incluye `exportId` y `recordKey` como atributos y nodos vacíos `<source>`
y `<input>` con atributos de procedencia, seguidos por `<metadata>` con el
fragmento XOAI. Los atributos de `source` incluyen red, `catalogId`,
`identifier`, `snapshotRef` y hash original; los de `input`, variante y hash
seleccionado. La raíz de metadata mantiene sus namespaces.

El layout `per-record` escribe un archivo XML por catálogo, con nombre
`<network>_<catalogId>.xml` (más `.gz` si corresponde). El archivo contiene el
XML almacenado sin una envoltura de procedencia; se vincula con el paquete por
su nombre y por `records.sqlite`. No se permiten límites de lotes en este layout.
Para colecciones XML, las posiciones SQLite empiezan en 0; para XML individual
se usa la ruta relativa y `position` queda nula.

## 4. Selección de metadata y alcance de registros

### 4.1 Variantes

- `original`: el hash y el XML son los almacenados al cosechar el registro.
- `processed` (predeterminado): usa `published_metadata_hash` del resultado de
  validación. Puede ser igual al original si el contenido no cambió. Si falta el
  resultado o su hash, el exportador registra error; no sustituye silenciosamente
  la metadata original.

El catálogo aporta `catalogId`, `identifier`, `datestamp` y el hash original.
La validación se enlaza por `identifier_hash` y se comprueba que el identifier
coincida. Se recorren filas activas (`deleted=0`) en orden de ID del catálogo.
No se ejecuta una validación ni transformación nueva durante la exportación.

### 4.2 Estados de validación y filtros

Por defecto se exportan registros activos válidos e inválidos. `--valid-only`
requiere datos de validación y excluye registros que no tengan `is_valid=true`.
Los registros excluidos quedan en `records.sqlite` con estado `FILTERED`; no se
agregan a `errors.jsonl`.

`--valid-only` no equivale a filtrar por `is_transformed`: un registro puede ser
válido y no haber cambiado con transformaciones. El índice conserva ambos
valores cuando están disponibles. Para `original` sin `--valid-only`, la base de
validación puede no ser necesaria; en ese caso el estado de validación queda
nulo en el índice.

### 4.3 Fuentes y snapshots

Se requiere exactamente una de estas selecciones: `--network <acrónimo>`,
`--networks <lista>` o `--all-networks`. La resolución del acrónimo es exacta;
IDs internos de red no son aceptados como selección. Fuentes sin LGK se añaden a
`skippedSources` con `reason: NO_LGK`. Una selección explícita sin ningún LGK
falla antes de empezar; seleccionar todas puede completar con cero fuentes y
cero registros si ninguna tiene LGK.

Al inicio se fijan las referencias a snapshots completados con estado `VALID`.
El manifiesto les asigna referencias como `source-000001`. Antes y después de
leer cada fuente, y al final, se comprueba que el snapshot y los manifiestos
observados no hayan cambiado. La lectura de SQLite se hace en modo solo lectura
inmutable; el exportador no ejecuta migraciones ni checkpoints sobre el origen.
Una base con WAL no vacío indica un snapshot no finalizado: el export falla en
lugar de leer datos posiblemente desactualizados.

El manifiesto de la implementación actual incluye `internalSnapshotId` como
evidencia de auditoría, además de la referencia pública `snapshotRef`. Tratar el
ID interno como dato opaco y no estable; para correlación entre archivos del
paquete usar `snapshotRef`. Los valores de `databaseVersions` registran tamaño,
fecha de modificación y `fileKey`, no son hashes criptográficos de las bases.

## 5. Perfiles XOAI → JSON

Una especificación v1 tiene la forma:

```json
{
  "specVersion": 1,
  "name": "licenses",
  "version": "1.0",
  "inputSchema": "xoai",
  "fields": {
    "licenses": {
      "select": "dc.rights.*",
      "type": "string",
      "many": true,
      "normalize": ["trim"],
      "unique": true,
      "maxLength": 300
    }
  }
}
```

El schema formal es
[`mapping-v1.schema.json`](../lareferencia-core-lib/src/main/resources/export/mapping-v1.schema.json).
Además del JSON Schema, el runtime comprueba selectores, propiedades
desconocidas, tipos y restricciones entre `occurrenceStart` y selectores
relativos. Validar perfiles con `export-mapping-validate` antes de usarlos.

### 5.1 Campos simples

Una regla simple usa `select` y `type`:

```json
{
  "select": "dc.identifier.dark:value",
  "type": "string",
  "many": false,
  "normalize": ["trim"]
}
```

Los tipos disponibles son `string`, `integer` y `boolean`. Un selector sin
`:field` usa el subcampo XOAI `value`; `:value`, `:language` y otros campos
XOAI explícitos terminan en `:nombre`. `integer` acepta enteros decimales con
signo y precisión arbitraria. `boolean` acepta únicamente las cadenas exactas
`true` y `false`.

- `many` predeterminado `true`: produce un array, incluso si no hay valores
  (`[]`). Con `false`, produce el valor escalar; si no hay coincidencias, omite
  la propiedad. Si quedan múltiples valores para un escalar, el registro falla.
- `normalize` admite `trim`, que quita espacios al principio y al final. No se
  eliminan cadenas vacías automáticamente.
- `unique: true` elimina valores repetidos preservando la primera aparición y el
  orden de origen.
- `maxLength` es un entero no negativo permitido solo con `type: string`. Se
  mide en puntos de código Unicode, después de las normalizaciones. La
  ocurrencia completa que exceda el máximo se omite; no se trunca. Este filtro
  elimina valores del campo y no incrementa el contador de registros `filtered`.

### 5.2 Selectores y comodines

Los selectores utilizan segmentos separados por puntos: por ejemplo,
`dc.identifier.dark`. Se pueden seleccionar campos XOAI con `:field`:
`dc.identifier.dark:value`. Los nombres deben seguir el patrón admitido por el
schema; no son expresiones XPath arbitrarias.

`*` significa descendencia recursiva del helper actual. Por ejemplo,
`dc.identifier.*` selecciona elementos descendientes bajo `dc.identifier` y
excluye al propio elemento padre. Un comodín puede abarcar varios niveles; no
significa solamente “un segmento”. Esto puede capturar calificadores anidados,
por lo que conviene previsualizar el perfil sobre cada fuente.

### 5.3 Ocurrencias agrupadas

`forEach` selecciona elementos y siempre produce un array de objetos. Cada regla
interna se evalúa relativa a cada elemento seleccionado:

```json
{
  "titles": {
    "forEach": "dc.title.*",
    "fields": {
      "value": {"select": ":value", "type": "string", "many": false},
      "language": {"select": ":language", "type": "string", "many": false}
    }
  }
}
```

Así se conserva el idioma junto a su título. No se construyen objetos haciendo
`zip` de listas independientes de values e idiomas.

`forEach` puede ser un array de selectores. Se evalúa la unión sin duplicar
elementos y se conserva el orden del documento XOAI. `occurrenceStart` permite
agrupar campos hermanos que representan secuencias de ocurrencias: cada campo
con ese nombre inicia un grupo nuevo y los siguientes campos hermanos se
adjuntan hasta el próximo inicio. En ese modo, los campos internos deben usar
selectores directos `:field` y cada selector escalar; un campo anterior al primer
inicio es ambiguo y produce error de registro.

`includeContext` puede añadir al objeto `schema`, `qualifier` y/o `path`:

- `schema`: primer segmento, como `dc` o `dcterms`.
- `qualifier`: segmentos bajo el nombre del campo, unidos por puntos; se omite
  para el calificador `none` o si no hay calificador.
- `path`: ruta completa, por ejemplo `dc.title.alternative`.

Los metadatos de contexto se agregan al objeto de la ocurrencia y no se infieren
desde los values. Evitar nombrar un campo interno igual que una propiedad de
contexto configurada.

### 5.4 Registro y errores de mapeo

El documento debe tener raíz XOAI `<metadata>`; se admite namespace ausente o
`http://www.lyncode.com/xoai`. Se deshabilitan DTD y entidades externas. Un
namespace no admitido, XML inválido, conversión de tipo inválida, ambigüedad de
ocurrencias, identidad incompleta o hash ausente es error de registro. El
proceso continúa con los siguientes registros y el paquete acaba `PARTIAL` si
hubo errores. Un perfil inválido o una opción incompatible es error de
configuración y detiene la ejecución.

## 6. Índice `records.sqlite`

El índice está cerrado y autocontenido en el paquete; usa journal DELETE y crea
un índice adicional sobre `(network,catalog_id)`. La tabla `records` tiene estas
columnas:

| Columna | Significado |
|---|---|
| `record_key` | Clave por paquete `<network>_<catalogId>`; clave primaria. |
| `export_id` | `exportId` del manifiesto. |
| `network`, `catalog_id`, `identifier` | Identidad del catálogo. |
| `snapshot_ref` | Referencia que enlaza con una fuente en `manifest.json`. |
| `original_metadata_hash` | Hash almacenado en catálogo al cosechar. |
| `variant`, `metadata_hash` | Variante exportada y hash utilizado. |
| `datestamp` | Datestamp del catálogo original. |
| `is_valid`, `is_transformed` | Booleanos nullable de validación, serializados como 0/1/NULL. |
| `status` | `EXPORTED`, `FILTERED` o `ERROR`. |
| `file`, `position` | Ruta relativa dentro del paquete y localizador del registro; NULL si no se escribió. |
| `error` | Mensaje de error de registro o NULL. |

`position` es línea desde 1 para JSONL, índice desde 0 para arrays JSON o XML
collection, y NULL para XML individual. Para un XML individual, `file` apunta al
archivo. La fila del índice es la fuente de verdad para descubrir snapshot,
variant y localizador de una línea JSON compacta.

Consulta directa para remapear un resultado externo y localizar su registro:

```sql
SELECT record_key, network, catalog_id, identifier, snapshot_ref, variant,
       original_metadata_hash, metadata_hash, status, file, position, error
FROM records
WHERE network = 'UY' AND catalog_id = '0002f315df52dbcb76631ad201c8d2a5';
```

En JSONL, `file` es la parte y `position` la línea desde 1; en JSON es el índice
desde 0 dentro del array de esa parte. En una colección XML, es el índice del
elemento `<record>`. La ruta siempre es relativa al directorio del paquete.

`errors.jsonl` es un diagnóstico legible, no sustituye el índice: cada línea
contiene identidad, hash seleccionado (si existe) y `error`. El estado y la
localización remapeable se consultan en `records.sqlite`.

Ejemplo de error JSONL:

```json
{"network":"UY","catalogId":"0002f315df52dbcb76631ad201c8d2a5","identifier":"oai:portal.ucr.ac.cr:article/6018","metadataHash":"BB8CCCE2D72C1F0B","error":"IllegalArgumentException: Invalid boolean"}
```

## 7. Manifiesto y estados

`manifest.json` es el descriptor del paquete. En la versión actual incluye:

- `contractVersion: 2`, `exportId`, `canonicalizer: export-json-v1`, estado,
  `startedAt` y `finishedAt` en ISO-8601 UTC.
- `options`: variante, formato, layout, partición, límites numérico en bytes,
  compresión, filtro `validOnly`, selección y si se usó `allNetworks`.
- `sources`: procedencia por snapshot: `snapshotRef`, acrónimo, URL de origen,
  prefijo de metadata, schema del almacén, ID interno de snapshot, estado,
  fechas, snapshot previo, evidencia de manifiestos y atributos de archivos de
  base de datos.
- `skippedSources`: redes omitidas y motivo, actualmente `NO_LGK`.
- `mappingHash`: hash canónico del perfil cuando hay mapping.
- `counts`: `attempted`, `exported`, `filtered` y `errors`.
- `warnings.oversizedRecords`: cantidad de registros individuales que excedieron
  el límite de bytes del lote y por eso ocuparon un archivo propio.
- `files`: inventario con ruta relativa, bytes y hash SHA-256.
- `failure`: detalle si un error de infraestructura o finalización dejó el
  paquete `FAILED`.

`canonicalizer: export-json-v1` ordena recursivamente las claves de objetos JSON,
preserva el orden de arrays y serializa UTF-8 sin espacios para producir el
`mappingHash`. No se emite `payloadHash` por registro.

| Estado | Interpretación |
|---|---|
| `RUNNING` | Estado provisional al inicio; un paquete final normal lo reemplaza. |
| `COMPLETE` | Terminó sin errores de registro ni de infraestructura; puede contener cero filas. |
| `PARTIAL` | Terminó el recorrido, pero hubo uno o más errores de registro. |
| `FAILED` | Falló la infraestructura, hubo interrupción o no pudo completarse el paquete. |

La selección sin LGK puede aparecer en `skippedSources`. Los errores de lectura,
identidad, hash o mapping por registro incrementan `errors` y escriben
`errors.jsonl`; errores de disco, consistencia de snapshot o escritura llevan a
`FAILED`. Los contadores se refieren a filas intentadas del catálogo, no a la
cantidad de ocurrencias JSON.

## 8. Contrato para devolver enriquecimientos

El schema vigente es
[`enrichment-return-v2.schema.json`](../lareferencia-core-lib/src/main/resources/export/enrichment-return-v2.schema.json).
Cada resultado externo debe conservar las claves de entrada relevantes y añadir
el enriquecimiento. Ejemplo:

```json
{
  "exportId": "exp-b0e04b15-9450-42ab-9841-0e96ec8293fd",
  "network": "UY",
  "catalogId": "0002f315df52dbcb76631ad201c8d2a5",
  "identifier": "oai:portal.ucr.ac.cr:article/6018",
  "metadataHash": "BB8CCCE2D72C1F0B",
  "enrichment": {
    "id": "license-classification",
    "type": "classification",
    "schemaVersion": "1.0.0",
    "runId": "run-2026-11-11-001",
    "generatedAt": "2026-11-11T12:00:00Z",
    "values": {
      "licenseType": "CC-BY-4.0",
      "confidence": 0.98
    }
  }
}
```

`values` depende del tipo y versión de enriquecimiento; el resto de campos
conforman el vínculo. El schema requiere `exportId`, red, `catalogId`,
`identifier`, `metadataHash` y un bloque `enrichment` con `id`, `type`,
`schemaVersion`, `runId`, `generatedAt` y `values`. `generatedAt` debe ser
fecha-hora ISO-8601. El schema v1 anterior usaba `source` e `input` anidados y
queda como formato histórico de compatibilidad; para nuevas salidas usar v2.

El manifiesto de una ejecución externa debería registrar como mínimo: nombre y
versión del procesador, versión de su configuración, timestamps, el `exportId`
procesado, esquema del resultado, y referencias/versiones de modelo, prompt,
vocabularios o recursos usados. Evitar incluir secretos o credenciales.

### 8.1 Validación antes de incorporar resultados

Un importador futuro o un transformador debe:

1. Verificar que el `exportId` existe y que el paquete no está `PARTIAL` o
   `FAILED` cuando se requiera una colección íntegra.
2. Buscar la fila exacta usando red y `catalogId`; comprobar que
   `identifier` coincide con la fila del índice y con el resultado.
3. Comparar `metadataHash` del resultado con el hash de entrada del índice. Si
   la red se reexportó o cambió la variante, no aplicar el resultado antiguo.
4. Validar la versión de esquema y los valores del enriquecimiento antes de
   transformarlos en metadata.
5. Hacer idempotente la incorporación. Una clave candidata es
   `(exportId, network, catalogId, enrichment.id, enrichment.runId)`; la política
   debe permitir reemplazo explícito cuando cambie el resultado.
6. Auditar quién o qué procesador generó el resultado, y conservar el JSON de
   retorno y el manifiesto de ejecución externa.
7. Incluir el hash de la colección de enriquecimientos consumida en el
   fingerprint del pipeline para que una modificación fuerce la actualización
   de los registros afectados.

## 9. Límites y garantías

- Límites por defecto: 10.000 registros o 128 MiB UTF-8 sin comprimir por
  archivo, el primer límite que se alcance. No se parte un registro. Un registro
  mayor ocupa un archivo solo y cuenta en `warnings.oversizedRecords`.
- XML `per-record` no admite límites de lote. La compresión GZIP se aplica por
  archivo.
- El orden del catálogo es por ID dentro de cada fuente; las fuentes se
  resuelven por acrónimo. No asumir que los números de parte son IDs de snapshot.
- Se parsea XML de forma segura y se procesa un registro por vez. El tamaño total
  final de los paquetes puede superar la memoria disponible porque se escriben
  secuencialmente.
- `metadataHash` permite localizar el XML en el almacén del snapshot, pero el
  paquete no incluye los XML fuente cuando exporta JSON. Recuperarlos requiere
  conservar el almacén correspondiente.
- Las referencias `snapshotRef` solo son únicas dentro del paquete. No reutilizar
  `source-000001` como identidad entre exportaciones.
- `records.sqlite` es parte del contrato de trazabilidad actual. Aunque los
  objetos JSON traen `network` y `catalogId`, se necesita el índice para
  recuperar `snapshotRef`, variant, estado, datestamp y ubicación autoritativa
  de cada registro.

