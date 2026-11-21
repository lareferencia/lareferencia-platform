# Validación y transformación de perfiles existentes

El motor abre las filas de reglas con los nombres actuales y los de los paquetes históricos `org.lareferencia.backend.validation.validator` y `org.lareferencia.backend.validation.transformer`. Resuelve el tipo al cargar la regla, también para el validador embebido de normalización. Los textos de diccionarios, expresiones y descripciones conservan su valor. La actualización de binarios no requiere una migración de perfiles.

## Efectos al actualizar

| Configuración existente | Efecto en la siguiente validación |
|---|---|
| Traducción de contenido | Un valor presente en otro campo ya no impide escribir el destino. Los calificadores de un mismo campo siguen compartiendo el control de duplicados. |
| Traducción prioritaria y alta condicional | El XML publicado incluye las modificaciones anteriores a la última coincidencia y las eliminaciones de duplicados cuando la condición es falsa. |
| Regex sobre identificadores | Las sustituciones sin efecto conservan la fecha y dejan de incrementar por sí solas el contador de transformados. |
| Expresiones de campo | Se aplica el cuantificador guardado en el modelo. Revisar especialmente perfiles con `ONE_ONLY`, `ZERO_ONLY`, `ZERO_OR_MORE` o `ALL`. |
| Limpieza de vacíos | También se eliminan los elementos de campo vacíos del XML, por ejemplo `<field name="title"/>`. |
| Todas las redes | El cambio de versión del motor invalida la huella anterior. La siguiente validación procesa todo el catálogo activo y genera una nueva base reutilizable. Los snapshots históricos conservan sus informes. |
| Reglas de año | La ejecución usa el año local de inicio. El primer proceso tras el cambio de año recalcula las redes con esa regla, incluso si está embebida en la normalización. |
| Verificación de URLs | Los registros heredados conservan el resultado hasta una validación completa. Se sigue usando HEAD y HTTP 200. Los límites por conexión y lectura son 5000 y 10000 ms. Pueden configurarse con las propiedades JVM positivas `lareferencia.validation.url.connectTimeoutMillis` y `lareferencia.validation.url.readTimeoutMillis`. |

## Cambios voluntarios

### Añadir la regla de presencia de título desde el admin

El perfil distribuido de Nodo Central ya incluye **Title — Presence**. En un perfil instalado, cada administrador decide si quiere rechazar registros que lleguen a la validación sin título. La edición se aplica a todas las fuentes que usen ese validador en su próxima validación.

1. En **Validadores**, abrir el perfil existente y revisar sus **Reglas**. Si ya hay una regla obligatoria que exige al menos un título en el mismo campo, el perfil ya cubre la presencia. Conservar la regla **Title** con **Todos** (`ALL`) para que siga comprobando la longitud de cada título presente.
2. Pulsar **Añadir regla** y completar los campos con los valores del perfil de Nodo Central.

   | Campo del admin | Valor |
   |---|---|
   | Tipo | Validación por longitud de contenido |
   | Nombre | Title — Presence |
   | Descripción | Exige al menos un título con contenido |
   | Obligatoria | Sí |
   | Cuantificador | Uno o más (`ONE_OR_MORE`) |
   | Campo | `dc.title.*` |
   | Longitud mínima | `1` |
   | Longitud máxima | `2147483647` |

3. Pulsar **Guardar esta regla** y comprobar que aparecen **Title** y **Title — Presence** en el perfil. Si se omitió el título o todas sus ocurrencias tienen longitud cero, el registro fallará la nueva regla. Un título de al menos un carácter la satisface.

### Opciones de transformación y reversión

- **ReduceHeavyRecords** conserva su eliminación incondicional de los campos configurados. Para usar un límite, elegir **ReduceRecordsBySizeRule** e indicar `maxRecordSizeBytes` positivo y `fieldsToRemove`. Mide la serialización UTF-8 del DOM en ese punto de la cadena. Elimina los campos cuando el tamaño supera el límite.
- **FieldNameTranslateRule** y **FieldNameConditionalTranslateRule** mantienen el límite histórico de 101 ocurrencias. La opción `processAllOccurrences: true` recorre toda la selección original.
- Para volver al binario anterior, restaurar primero los perfiles que hayan adoptado el tipo por tamaño y retirar la propiedad nueva de renombre si se guardó. **Title — Presence** usa una clase y un cuantificador del motor anterior. Para restaurar el comportamiento previo de ese perfil basta retirar la regla añadida. Validar de nuevo al cambiar de motor.

## Comprobar el impacto por red

Ejecutar el motor anterior y el actualizado sobre dos copias de la misma cosecha con los mismos perfiles, atributos de red, reloj y respuestas HTTP. Usar una validación completa. Guardar los perfiles con sus IDs de regla y el original de cada registro. Repetir sobre una tercera copia para medir por separado la adopción de las opciones voluntarias.

La utilidad trabaja sobre copias cerradas de los snapshots con los WAL consolidados. Compara registros activos por clave de catálogo y comprueba identificador, hash original y fecha cosechada antes de comparar resultados. Devuelve una línea JSON por registro con diferencias y una última línea de totales. Un código de salida distinto de cero invalida la comparación.

```sh
python3 testing/validation/compare_snapshots.py /copias/anterior/snapshot_42 /copias/actual/snapshot_42 > red-42.jsonl
```

Las claves `rule_<id>` identifican las reglas del perfil. El resumen cuenta aceptaciones, rechazos y cambios en el hash publicado, en el identificador y en los transformados. Un cambio exclusivamente de XML puede proceder de un transformador aunque coincidan todas las decisiones de validación. Para atribuirlo, reproducir el original con los dos motores y contrastar el contenido después de cada regla en orden.

## Evidencia en el checkout de desarrollo

Se ejecutaron el motor de referencia del core (`fff4293`) y el actualizado sobre los mismos 150 originales locales. Se seleccionaron los primeros 50 registros activos por ID de los snapshots PA/4, UY/2 y AREANDINA/6. Cada conjunto se procesó con el perfil distribuido de Nodo Central, tanto con 16 como con 17 reglas, y con el par validador/transformador Standard. Esta comparación usa los perfiles distribuidos sobre las tres muestras. Las configuraciones particulares de cada instalación requieren su propio ensayo.

| Muestra | Válidos con Nodo Central anterior / actualizado | Válidos con Standard anterior / actualizado |
|---|---:|---:|
| PA | 50 / 50 | 0 / 0 |
| UY | 48 / 48 | 0 / 0 |
| AREANDINA | 0 / 0 | 0 / 0 |

En estas muestras coincidieron los identificadores, los hashes publicados y los indicadores de transformación entre motores. Los 150 originales pasaron la regla adicional de presencia. El perfil Standard consulta campos directos como `dc:title` y Nodo Central consulta rutas como `dc.title.*`. Las pruebas sintéticas cubren registros sin título, colisiones entre campos y transformaciones que antes se omitían. El perfil actualizado también se pudo ejecutar con el motor anterior.

### Perfiles guardados en la base local

El 21 de noviembre de 2026 se recuperó el JSON de cada regla desde una copia del PostgreSQL de desarrollo y se procesaron los 4.000 originales activos del snapshot 6 de AREANDINA con el motor anterior y el actualizado. La red tenía asignado el validador 1, de 14 reglas, sin prevalidación ni transformadores. También se ensayó el validador 5, de 16 reglas, guardado en esa base y sin redes asignadas.

En cada perfil coincidieron las decisiones de todas las reglas para los 4.000 registros. La regla obligatoria `Creator` falló en todos los originales con ambos motores. La regla histórica `Title` pasó en todos. Ambos perfiles se ejecutaron tal como estaban almacenados, sin añadir la regla de presencia. El ensayo cubre estos perfiles y este snapshot de desarrollo.

Las regresiones de compatibilidad se ejecutan desde la raíz de plataforma.

```sh
mvn -pl :lareferencia-core-lib,:lareferencia-shell,:lareferencia-lrharvester-app -am \
  '-Dtest=PersistedRuleCompatibilityTest,PipelineRegressionTest,IncrementalValidationLifecycleTest,HarvesterProfileImportTest,ApiV5ProfileCompatibilityTest,URLExistFieldValidatorRuleTest' \
  -Dsurefire.failIfNoSpecifiedTests=false test
python3 -m unittest discover -s testing/validation
```

La prueba JPA guarda las definiciones de las 29 clases del catálogo anterior, cierra la transacción, ejecuta ambas cadenas sobre XML y vuelve a leer las filas para comparar el JSON literal. La prueba del worker comprueba el hash recuperando el XML del almacén de archivos y repitiendo la validación contra el resultado persistido en SQLite.
