# Admin-ui · Indexación del buscador

El 19 de noviembre de 2026, en la rama coordinada `codex/rc5-pre`, el admin indexó el snapshot histórico **PA #4** sobre una copia del entorno Docker de desarrollo. Los **3.444** identificadores OAI válidos y activos de SQLite coincidieron exactamente con los documentos que devolvió Solr. El ensayo cubre la acción «Indexar en el buscador» del motor Java, con la transformación real y búsqueda bibliográfica en el core VuFind. [Prueba de navegador](../testing/admin-ui/verificar_indexacion.py)

## Evidencia

| Comprobación | Resultado observado |
|---|---|
| Origen | PostgreSQL 14 copiado, red PA (ID 1), snapshot 4 del 4 de octubre de 2026. La API y PostgreSQL registraron 3.444 válidos. El manifiesto de validación declara alcance `FULL`. |
| Índice antes de la acción | Solr 9.11.0, core `biblio` iniciado con la imagen del proyecto y un volumen nuevo. Cero documentos para PA. Revisión VuFind del core según `build-info.properties`: `acde2b922de221d855c1ca1883c9c648b1e427f2`. |
| Acción desde Chrome | Iniciar sesión, abrir la fila PA, pulsar «Ejecutar acción», «Indexar en el buscador» y «Confirmar». El navegador envió `POST /api/v5/networks/1/commands` con `FRONTEND_INDEXING_ACTION`. HTTP 202 y resultado `ACCEPTED`. |
| Ejecución | `requestId` y `groupId` coinciden en `aec9017d-d7fa-471c-9399-a5fbb4bb6789`. Estado `COMPLETED`. Desde 11:54:38.048958 hasta 11:54:46.130439 UTC. El worker procesó 35 páginas con el perfil efectivo `vufind5`. |
| Persistencia y presentación | El snapshot 4 devolvió `indexStatus=INDEXED`. El resultado de `frontendIndexerWorker` registró la acción correcta, `finishedAt=2026-11-19T11:54:46.123949Z` y error nulo. Se verificó el cambio del resultado respecto del histórico. Tras recargar, el detalle de indexación de la fila PA mostró «Indexación del buscador» y «OK». |
| Identidad | `PRAGMA integrity_check` devolvió `ok`. Se compararon todos los `identifier` de `record_validation` con `is_valid=1 AND deleted=0` contra todos los `oai_identifier_str` del índice, con filtro `network_acronym_str:PA`. Resultado: 3.444 documentos, 3.444 identificadores distintos, cero faltantes y cero adicionales. |
| Búsquedas | La consulta exacta por `oai:ridda2.utp.ac.pa:123456789/12794` devolvió el documento `PA_0017a80d1a08b09a0691b876289872c0`. La búsqueda por título «Palabras de la Editora» devolvió ese mismo documento como única coincidencia. Un identificador inexistente devolvió cero. |
| Reinicio de Solr | Tras reiniciar el contenedor de prueba y redescubrir su puerto local, `q=network_acronym_str:PA&rows=0` devolvió otra vez `numFound=3444`. |

## Qué se corrigió

El fallo registrado en la verificación anterior se reprodujo en Testcontainers con Solr 9.5. Jetty anunciaba el puerto abierto y el cliente agotaba el tiempo al crear la colección `biblio`. Cambiar a un core autónomo también agotó el tiempo en la espera HTTP. Un volcado de hilos durante esa espera mostró al hilo de aceptación de Jetty en `SecurityManager.checkAccept → SocketPermission.getCanonName → Inet6AddressImpl.getHostByAddr`. El bloqueo se producía durante la resolución inversa de una conexión.

El contenedor de la prueba usa ahora `SOLR_SECURITY_MANAGER_ENABLED=false`, el valor que ya emplea la imagen del proyecto. Se verificó el ajuste aislado con la imagen 9.5 y la creación de colección originales. Maven terminó con éxito. El cambio de código se limita al contenedor del test. La aplicación y el esquema VuFind existentes completaron la indexación bibliográfica. [Configuración de la prueba](../lareferencia-lrharvester-app/src/test/java/org/lareferencia/backend/integration/BaseIntegrationTest.java) · [Arranque del Solr del proyecto](../Docker/solr/entrypoint.sh)

## Reproducción sobre otra copia

1. Seguir la preparación de PostgreSQL, configuración, almacén, usuario ADMIN temporal y bundle del admin descrita en el ensayo de cosecha. Copiar el clúster con el PostgreSQL de origen detenido e iniciar el backend con ambos datasources y el almacén de la copia. Desactivar los cron en ella. [Preparación](ADMIN_UI_OPERACIONES.md#cómo-repetir)
2. Construir la imagen con el Dockerfile y los cores ya preparados en `Docker/solr`. Iniciar un contenedor nuevo, con puerto publicado en loopback y almacenamiento Solr nuevo. Por ejemplo, desde la raíz del proyecto y con un nombre libre:

   ```sh
   docker build -f Docker/solr/Dockerfile -t lr-solr-prueba:local .
   docker run -d --name lr-solr-prueba -p 127.0.0.1::8983 lr-solr-prueba:local
   docker port lr-solr-prueba 8983
   ```

3. Usar en `frontend.solr.url` la dirección local del core. En la configuración global del worker `frontendIndexer` de la **copia**, ajustar también `solrUrl` a esa misma dirección. Este valor persistido en `application_worker_configuration.configuration` prevalece sobre el valor de Spring. En esta prueba se sustituyó la dirección interna de Docker manteniendo el perfil persistido `vufind5` y la opción de red `INDEX_FULLTEXT=false`. El navegador comprueba el destino efectivo antes de admitir la acción.
4. Con Chrome y Playwright para Python instalados, ejecutar el siguiente comando. Se utilizó Chrome 157 y Playwright 1.60. La contraseña se solicita en la terminal o se lee de `ADMIN_TEST_PASSWORD`.

   ```sh
   python3 testing/admin-ui/verificar_indexacion.py \
     --origen "http://127.0.0.1:${PUERTO_ADMIN}" --usuario "${USUARIO_ADMIN_PRUEBA}" \
     --solr "http://127.0.0.1:${PUERTO_SOLR}/solr/biblio" --almacen "${COPIA_DATA}"
   ```

5. Para repetir desde cero, preparar otro índice desechable vacío y actualizar el destino en la copia. El script rechaza un índice PA que ya contenga documentos. Escribe el comando mediante la interfaz y lee las evidencias a través de la API, SQLite y Solr. Para comprobar persistencia, reiniciar ese contenedor, consultar su puerto con `docker port` y repetir la consulta por red.

La búsqueda se comprobó mediante `/solr/biblio/select`. El ensayo cubre los metadatos indexados del snapshot. La búsqueda vectorial con un servicio de embeddings real queda fuera de esta verificación.
