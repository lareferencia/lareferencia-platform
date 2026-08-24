# Importación de mapeos ARK históricos de dARK

Esta guía permite incorporar al modelo actual los ARKs creados por la
integración anterior, que registraba identificador OAI y URL pero no enviaba
metadata. El objetivo es conservar cada ARK existente y hacer que la primera
ejecución de *stage* cargue su metadata completa en dARK.

## Resultado esperado

Cada fila histórica se importa en `dark_tracking_record` como `UPDATE` (`U`):

| Origen CSV | Registro actual |
|---|---|
| `darkidentifier` | `ark` |
| NAAN extraído de `ark:/<naan>/...` | `ark_naan` |
| `oaiidentifier` | `oai_id` |
| `itemurl` | `target_url` |
| `datestamp` | `created_at` |
| `lastmodified` | `updated_at` |
| — | `state = UPDATE` |
| — | `source_metadata_hash`, `stage_payload_hash` y `last_staged_at` vacíos |

El estado `UPDATE` evita una reserva nueva. Al ejecutar `DARK_STAGE_ACTION`,
el worker usa el ARK importado y hace `PUT` con metadata Level 1 y metadata
original. El estado remoto que responda dARK pasa a ser el estado local.

## Requisitos previos

1. La tabla origen debe contener ARKs que ya existen en dARK.
2. El shell debe usar la configuración de la base de datos destino.
3. Cada red afectada debe tener `network.attributes.ark_naan` configurado.
4. La configuración dARK debe incluir, como mínimo, `dark.minter.base-url`,
   `dark.authority-id` y `dark.metadata.schema`.
5. Debe existir una snapshot válida con metadata para que el worker de stage
   pueda construir el payload.

## Formato de entrada

El archivo es UTF-8, separado por comas y con una única cabecera exacta:

```csv
darkidentifier,oaiidentifier,datestamp,itemurl,lastmodified
ark:/41046/001300001kq89,oai:repositorio.ufrn.br:123456789/46761,2025-07-31 12:28:05.320471,https://repositorio.ufrn.br/handle/123456789/46761,2025-09-27 00:18:26.628545
```

Las fechas se aceptan como `yyyy-MM-dd HH:mm:ss` con fracción de segundos
opcional. `itemurl` puede estar vacío: el worker la vuelve a obtener de la
metadata durante el stage.

## Ejecución

Iniciar el shell con la configuración del entorno y ejecutar primero una
simulación:

```text
import-dark-legacy-csv --path /data/legacy-dark.csv
```

La simulación valida cabeceras, ARKs, fechas, duplicados y conflictos locales,
sin escribir en la base. Si el resultado es correcto, aplicar la importación:

```text
import-dark-legacy-csv --path /data/legacy-dark.csv --apply
```

El comando informa cuántas filas importó y cuántas ya existían. Una fila que ya
tiene el mismo par `(ark_naan, oai_id)` y el mismo ARK se omite, por lo que una
importación terminada puede repetirse sin crear registros nuevos.

## Conflictos y orden operativo

El comando no sobrescribe mapeos distintos. Se detiene si detecta alguno de
estos casos:

- el mismo `(ark_naan, oai_id)` asociado a otro ARK;
- el mismo ARK asociado a otro registro local;
- ARKs, fechas o cabeceras inválidos;
- duplicados dentro del CSV.

Después de importar, ejecutar primero `DARK_STAGE_ACTION` para cada red
afectada. No ejecutar `DARK_RECONCILE_ACTION` antes del primer stage: la
reconciliación está pensada para sincronizar estados remotos de registros que
ya se han enviado y podría cambiar el estado `UPDATE` antes de la carga inicial
de metadata.

Tras el stage, se puede ejecutar o programar `DARK_RECONCILE_ACTION` para
mantener los estados locales sincronizados con dARK. Si el servicio remoto no
reconoce un ARK importado, el worker lo deja en error y conserva el mismo ARK;
no reserva uno nuevo automáticamente.
