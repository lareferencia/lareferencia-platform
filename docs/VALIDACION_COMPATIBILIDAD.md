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

## Casos de compatibilidad en limpieza y vocabularios

Estas optimizaciones se aplican al cargar el JSON que ya tiene el perfil. El administrador puede conservar la configuración. Los casos siguientes fijan qué valores sobreviven y qué se muestra en el diagnóstico.

| Regla o caso | Comportamiento que conserva el perfil |
|---|---|
| Duplicados exactos | Con `A, a, A` quedan `A, a` en ese orden. Se conserva el primer nodo con cada valor, incluidos sus atributos. |
| Conservar solo la primera ocurrencia | Con `A, B, A` queda el primer `A`. Un campo ausente o con un solo valor conserva su estado y la regla devuelve que el registro sigue igual. |
| Lista de exclusión | Se eliminan todas las ocurrencias con un valor que figure en la lista, por coincidencia exacta. Las demás mantienen su orden y sus repeticiones. |
| Vocabulario con prioridad | Gana el término que aparece antes en la lista configurada. A igual prioridad gana el primer nodo en el XML. Los valores ajenos al vocabulario se conservan, incluso si están repetidos. |
| Vocabulario único aceptado | Dos ocurrencias reconocidas hacen fallar la regla, aunque sean idénticas. Una ocurrencia aceptada de más de 255 puntos de código Unicode cuenta para la validez y su texto se omite del diagnóstico. El diagnóstico conserva el orden, las repeticiones y los avisos históricos. |
| Contenedores XML al eliminar campos | Un elemento hermano mantiene vivo el contenedor. Si solo quedan texto o comentarios, se elimina el contenedor vacío y se aplica el mismo criterio a sus ancestros. Se conserva la raíz del documento. |

## Presencia y cardinalidad por familia de reglas

En reglas de contenido y en cada comparación de una expresión, `n` es el número de valores del campo y `m` es el número que satisface la condición. En una regla XPath, `k` es el número de ocurrencias devueltas por el selector.

| Cuantificador | Contenido de campo | Comparación dentro de una expresión | Ocurrencias XPath |
|---|---|---|---|
| `ALL` | `m = n`, pasa con campo ausente | `m = n`, pasa con campo ausente | `k ≥ 1`, falla con selección vacía |
| `ONE_OR_MORE` | `m ≥ 1` | `m ≥ 1` | `k ≥ 1` |
| `ONE_ONLY` | `m = 1` | `m = 1` | `k = 1` |
| `ZERO_ONLY` | `m = 0` | `m = 0` | `k = 0` |
| `ZERO_OR_MORE` | `n = 0` o `m ≥ 1` | Siempre pasa | Siempre pasa |

Para exigir al menos un título y que todos los títulos cumplan una longitud, combinar una regla obligatoria de presencia con `ONE_OR_MORE` y otra obligatoria de longitud con `ALL`. En expresiones compuestas, los operadores booleanos se aplican después de evaluar cada comparación. La regla de vocabulario único aceptado tiene su propio criterio fijo y exige exactamente una ocurrencia del vocabulario completo cuyo término esté aceptado.

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

### Traducción por prioridad

Se compararon cinco transformadores en core-lib `d15f385` sobre el mismo XML con 2 y 32 ocurrencias de `dc.subject`. Con 32 ocurrencias, `FieldContentPriorityTranslateRule` empleó 1,55 ms por registro al encontrar la coincidencia en la última de 32 entradas. Le siguieron `AddRepoNameRule` (0,48 ms), `FieldAddRule` (0,37 ms), `FieldContentNormalizeRule` (0,07 ms) y `RemoveDuplicatePrefixedOccrs` (0,07 ms). Con dos ocurrencias se mantuvo ese orden entre los tres primeros. La comparación mide el coste de estas configuraciones por registro. El impacto en una instalación depende también de los diccionarios y de la frecuencia de uso.

La regla ahora selecciona los nodos de origen una vez y repite la consulta antes de la siguiente entrada solo si hubo una escritura. Así, una entrada puede tomar el resultado de la anterior, incluso cuando el campo de origen usa un comodín que incluye el destino. El historial de valores pertenece al registro y conserva los valores que ya fueron retirados.

Se midió el método `transform` en Java 21, en dos JVM por versión, con heap de 384 MiB. Cada lote procesó 16 copias de un DOM con 32 ocurrencias idénticas y un diccionario de 32 entradas. La preparación de las copias quedó fuera de la medición. Los intervalos recogen las medianas de siete lotes por JVM después de cuatro de calentamiento. Los MB son asignaciones del hilo por registro.

| Diccionario | Antes, ms/registro | Después, ms/registro | Antes, MB/registro | Después, MB/registro |
|---|---:|---:|---:|---:|
| Ninguna coincidencia | 2,26–2,49 | 0,20–0,22 | 4,70 | 0,14 |
| Coincide la última entrada | 2,40–2,83 | 0,17–0,18 | 4,80–4,82 | 0,28 |
| Las 32 entradas encadenan escrituras | 2,25–2,69 | 2,33–2,53 | 8,98 | 8,86–8,88 |

Los tiempos se solapan cuando cada entrada modifica el origen y la siguiente necesita volver a leerlo. En los otros dos escenarios, la selección XPath pasó de 33 consultas a una.

Coincidieron el JSON serializado de 32 configuraciones con nombre de clase histórico y el XML completo y el indicador de transformación en 160 casos aplicados dos veces. Se probaron coincidencias exactas y por prefijo, reemplazo y adición, primera coincidencia y todas, destinos compartidos, rutas con comodines y valores duplicados o vacíos. Sobre 150 originales de AREANDINA se aplicó un perfil de prueba con traducciones encadenadas en `dc.type.*`. Ambos motores modificaron los mismos 60 registros y produjeron el mismo XML en los 150.

### Metadatos de procedencia

`AddProvenanceMetadataRule` escribe varios campos en el mismo contenedor XOAI. Cuando falta el campo, el motor puede añadirlo al primer contenedor coincidente en una sola consulta al padre. Cuando el campo ya existe, las nuevas ocurrencias se añaden en su propia rama. La mejora se aplica en cada registro y no requiere una caché.

Se comparó core-lib `4734679` con la versión optimizada en Java 21, con dos JVM por versión y un heap de 384 MiB. Cada JVM ejecutó cuatro lotes de calentamiento y siete de medición por caso. Cada lote aplicó el perfil por defecto a 32 copias de un registro XOAI sin contenedor de repositorio. La copia del DOM quedó fuera de la medición. Los intervalos muestran las dos medianas por versión. La memoria corresponde a los bytes asignados por el hilo durante la transformación.

| Atributos de red | Antes, ms/registro | Después, ms/registro | Antes, MB/registro | Después, MB/registro |
|---|---:|---:|---:|---:|
| Todos informados | 1,75–1,82 | 1,17–1,34 | 7,86 | 5,02–5,07 |
| Ausentes | 1,43–1,45 | 1,14–1,15 | 7,84 | 5,01 |
| Presentes con valor nulo | 1,18–1,38 | 0,90–0,91 | 7,75–7,76 | 5,01 |

La regla conserva los elementos XML vacíos para atributos ausentes y nulos, y sigue publicando `opendoar:` cuando falta el identificador del repositorio. En la segunda aplicación reemplaza los campos configurados para nombre del repositorio, correo e identificador OAI. Los demás se vuelven a añadir en el orden histórico.

Se cargaron tres configuraciones con el nombre histórico de la clase. Se compararon su JSON serializado y, en 72 casos de dos pasadas, el XML completo y el indicador de transformación. Los casos combinan atributos completos, ausentes, nulos y mixtos con rutas anidadas, comodines, destinos compartidos, ramas repetidas y documentos con y sin espacio de nombres. Todos coincidieron. También coincidieron los 150 primeros originales activos del snapshot 6 de AREANDINA al aplicarles el perfil de prueba con atributos mixtos.

### Renombre masivo de campos

Se compararon seis transformadores pendientes con XML XOAI. Con 32 ocurrencias, el mayor coste por registro correspondió a `FieldNameBulkTranslateRule`. Con dos ocurrencias, `AddProvenanceMetadataRule` costó más que el renombre. La prioridad por instalación depende de las reglas asignadas y del número de valores por campo.

Para el renombre se movieron todas las ocurrencias de `dc.subject` a `dc.type.none`, inicialmente ausente. Se alternaron dos JVM por versión (Java 21), con cinco lotes de 12 registros después de tres de calentamiento. Las copias del XML se prepararon antes de medir. Los intervalos recogen las medianas por JVM.

| Ocurrencias | Antes, ms/registro | Después, ms/registro | Memoria asignada antes → después |
|---|---:|---:|---:|
| 2 | 1,36–1,61 | 1,01–1,59 | 2,44 → 1,35 MB |
| 32 | 14,84–16,08 | 4,52–5,45 | 38,68 → 5,62 MB |

El cambio está en la escritura compartida de campos. Cuando el destino ya existe, se añade el valor junto al primer campo coincidente, incluso si pertenece a la segunda de varias ramas con el mismo nombre. Se conserva el orden de los mapeos, de modo que un renombre posterior puede tomar como origen el resultado del anterior. Se compararon 80 casos cargados desde JSON histórico en dos pasadas, con destinos existentes y ausentes, comodines, selectores de elementos, campos con nombre, namespaces y rutas inválidas. Coincidieron el XML, el indicador de transformación y las excepciones observadas.

También se aplicó un perfil de prueba con dos renombres encadenados a los primeros 150 originales activos del snapshot 6 de AREANDINA. Se movieron 541 ocurrencias de materia en 147 registros. El hash del XML resultante y el indicador de transformación coincidieron para los 150 registros en ambos motores.

### Limpieza de campos con muchas ocurrencias

Se comparó core-lib `c148c6f` con el motor actualizado sobre lotes de 128 registros XOAI, cada uno con 512 ocurrencias en el mismo campo. Las copias del DOM se prepararon antes de empezar a medir. Se alternaron las versiones en cuatro JVM de Java 21 y se tomó la mediana de siete lotes por JVM después de cuatro de calentamiento. Los intervalos son las dos medianas observadas para cada versión.

| Transformador | Anterior, ms por lote | Actualizado, ms por lote |
|---|---:|---:|
| Duplicados por prioridad del vocabulario | 95–162 | 29–39 |
| Duplicados exactos | 90–121 | 25–29 |
| Conservar solo la primera ocurrencia | 87–108 | 23–25 |
| Lista de exclusión | 75–96 | 22–24 |

En el mismo ensayo el validador de vocabulario único asignó unos 8 KiB menos por registro. Los tiempos de validación de ambas versiones se solaparon. Además, se cargó el JSON con nombres de clase históricos para cada una de las cinco reglas y se compararon 129 casos por regla, con cero a 128 ocurrencias. Coincidieron el XML y el indicador de cambio de los transformadores, incluida una segunda pasada, y el dictamen y los diagnósticos del validador.

### Consultas a vocabularios grandes

La regla `LargeControlledValueFieldContentValidatorRule` genera un índice de pertenencia en memoria en la primera consulta a los términos cargados desde CSV o archivo. Conserva el CSV y la comparación exacta, incluidas mayúsculas, espacios y acentos. El índice requiere memoria adicional proporcional al número de términos distintos.

Se midió la llamada a `validate(String)` en Java 21 con los vocabularios del perfil distribuido de Nodo Central. Cada ronda repitió 20.000 consultas, la mitad con un término del perfil elegido al azar con semilla fija y la mitad con un valor ausente. Los tiempos son la mediana de siete rondas después de cuatro de calentamiento. Miden la búsqueda con la regla ya cargada.

| Vocabulario | Términos | Búsqueda anterior | Búsqueda con índice |
|---|---:|---:|---:|
| Idiomas | 8.129 | 144,8 ms | 1,0 ms |
| Formatos | 83 | 1,84 ms | 0,41 ms |

### Asignaciones de memoria por registro en reglas de texto

Se comparó la versión de core-lib `88f1c2b` con la versión optimizada en Java 21. Cada llamada procesó un XML XOAI con 32 valores de `dc.type`. La expresión regular del validador coincidía con todos. En las pruebas de transformación, ningún valor requería traducción ni limpieza. Se midieron los bytes asignados por el hilo, con siete rondas de 500 llamadas tras cuatro de calentamiento. La tabla muestra la mediana por llamada, redondeada a KiB.

| Operación | Antes | Después |
|---|---:|---:|
| Validar una expresión con regex | 196 KiB | 149 KiB |
| Traducir por regex | 302 KiB | 148 KiB |
| Limpiar espacios | 158 KiB | 144 KiB |

Estas cifras incluyen la consulta XPath y las asignaciones temporales de la regla. El consumo de toda la cosecha depende también de cuántas ocurrencias tenga cada registro y de cuántas cambien.

### Perfiles distribuidos sobre registros locales

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
