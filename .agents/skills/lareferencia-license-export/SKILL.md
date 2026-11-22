---
name: lareferencia-license-export
description: Extraer y normalizar declaraciones de licencia de dc.rights en LA Referencia. Usar para inventarios de valores, cobertura por ítem o desgloses por familia y país.
---

# Exportación y normalización de licencias

Para ejecutar el pipeline completo en el servidor, publicar SQLite o implementar otros productores de campos, usar [lareferencia-metadata-enrichment](../lareferencia-metadata-enrichment/SKILL.md). El contador y el normalizador viven en `lareferencia-metadata-tools`. El perfil de extracción vive en el shell.

## Exportar y contar valores

La entrega por registro contiene `data.licenses`. Si ya hay un export, comprobar su manifiesto y su `mapping.json` antes de reutilizarlo. Para extraerlo del LGK usar el perfil del shell `config/exports/licenses-v1.json`. Ejemplo para todos los activos de UY con metadata original:

```text
export-metadata --network UY --variant original --format jsonl --mapping config/exports/licenses-v1.json --compression gzip --output /srv/metadata-exports
```

Respetar la variante y el alcance solicitados. Para un inventario por país, contar un paquete completo de una sola red por vez. Desde la raíz de la plataforma, instalá `./lareferencia-metadata-tools`
con `python -m pip install ./lareferencia-metadata-tools` en un entorno
virtual de Python 3.12 o posterior. Con el entorno activo, pasá el directorio
`exp-…` completo como `EXPORT_DIR`.

```sh
count-export-licenses "$EXPORT_DIR" --max-text-length 120 > "$LICENSES_JSONL"
```

El inventario contiene una línea por valor con `value` y `recordCount`. Una repetición del mismo valor dentro del ítem cuenta una vez. El contador omite vacíos, COAR e `info:eu-repo`. Las URL HTTP(S) con host y sin espacios quedan exentas del límite de 120 caracteres del contador. Verificar también el límite del perfil del paquete. En la campaña, el perfil omitió todos los valores de más de 300 puntos de código, incluidas las URL. Consultar `lareferencia-metadata-tools/docs/LICENSE_METADATA_EXTRACTION.md` para el proceso de extracción.

## Normalizar el inventario

Para varias redes, consolidar por igualdad exacta de `value` y conservar `recordCountByCountry` y su suma en `recordCount`. Reutilizar el diccionario versionado del corte cuando se pida reproducir un resultado. La taxonomía vigente es v7. Para el paquete de Externo usar `derechos-normalizados-v7.jsonl` y verificar `taxonomyVersion: 7` en las filas. Para generar un diccionario a partir del inventario, instalar la revisión de metadata tools que contiene las reglas correspondientes.

```sh
normalize-rights "$INVENTORY_JSONL" > "$NORMALIZED_JSONL"
```

Conservar el valor original y la evidencia disponible. Para Creative Commons, priorizar la URL aplicable, luego el código válido y finalmente el nombre textual. Mantener familia, versión, jurisdicción y alcance según la evidencia. Dejar los conflictos sin resolver en revisión. Las nueve familias son CC, SOFTWARE, DATA, INSTITUTIONAL, EDITORIAL, PUBLIC-DOMAIN, RE, Copyright y OTHER-LICENSE. Informar el instrumento dentro de su familia. RE conserva el código canónico. CC0, CC-PDM y PDDL pertenecen a PUBLIC-DOMAIN.

## Contar ítems y calcular cobertura

Volver a las partes de datos de un paquete `COMPLETE` y comprobar su variante, snapshot y total de filas contra el manifiesto. Para cada ítem `(network, catalogId)`, limpiar los espacios exteriores de `data.licenses`, cruzar los valores exactos con el diccionario y reunir las familias en un conjunto. Contar el ítem una vez en el numerador de derechos identificados si tiene al menos una familia. Para una consulta específica de licencias declaradas seleccionar entradas con `kind = license`. En cada fila de familia, contar el ítem una vez. Deduplicar también los subtotales de CC y no CC, porque un ítem puede aparecer en varias familias. `recordCount` sirve para frecuencias por valor y puede contar al mismo ítem en distintos valores.

- **Denominador completo.** Todos los ítems exportados de la red.
- **Denominador ajustado.** Ítems con al menos un valor del paquete después de retirar vacíos y los prefijos COAR e `info:eu-repo` que reconoce `EXCLUDED_VOCABULARIES` en el contador. Conservar los textos largos presentes en el paquete y las demás declaraciones de derechos. El límite de 120 caracteres corresponde al inventario.

Dividir el mismo numerador por cada denominador. Si un denominador es cero, informar el porcentaje como no calculable. Para un total de varias redes, sumar los conteos antes de dividir.

## Copyright y controles

En la salida de enriquecimientos de esquema 4, los avisos de Copyright van en `dc.rights.copyright`. Para medir cobertura de L1/L2, contar esas facetas por separado y calcular explícitamente su intersección con Copyright. Los conteos históricos siguientes corresponden al conjunto de derechos identificados de v7.

Contar Copyright en todos los ítems que contengan la declaración, incluso cuando coexista con CC u otra familia. Para «solo Copyright», exigir que el conjunto de familias sea exactamente `{Copyright}`. En Externo v7, Brasil tiene 576.890 ítems con Copyright y 434.834 exclusivamente con Copyright. El total regional deduplicado de derechos identificados es 4.780.113 sobre 10.025.056 exportados y 5.674.627 ajustados.

Consultar los antecedentes metodológicos de la campaña v5 en el [documento de trabajo de normalización de licencias](https://github.com/LA-Referencia-IOI/lareferencia-license-normalization/blob/main/docs/LICENSE_NORMALIZATION_WORKING_PAPER.md).
