# Plan de autenticación del minter y gestión de claves dARK

Fecha: 11 de octubre de 2026. Estado: primera implementación disponible; integración remota y recuperación durable pendientes. El avance y las limitaciones se detallan en la sección 14.

## 1. Objetivo y alcance

Permitir que el administrador del cosechador configure la autenticación DARK2 y genere sus credenciales desde la configuración del minter en el módulo dARK. El servidor conserva la clave privada en almacenamiento persistente; la interfaz entrega la clave pública y explica cómo registrarla en el minter.

El alcance inicial comprende generación de pares Ed25519, almacenamiento, consulta de información pública, reemplazo coordinado, firma de reservas y stage, clasificación de errores y recuperación de resultados inciertos. El registro de la pública en Admin/Dashboard del minter sigue siendo un paso externo: generar una clave en el cosechador no la registra ni concede permisos.

Las secciones 1–13 conservan el diseño propuesto. La sección 14 describe lo implementado; el README de `lareferencia-dark-lib` documenta el uso actual.

## 2. Base técnica y situación actual

Referencia funcional: guía aportada «dARK Minter API: Ed25519 authentication technical guide», versión 1.0, del 11 de octubre de 2026. Describe la implementación revisada por sus autores; hay que confirmar la configuración efectiva de cada instalación.

Componentes actuales relevantes:

| Componente | Situación y cambio previsto |
| --- | --- |
| `DarkMinterClient` | Usa Java HttpClient, Jackson y un encabezado de autoridad configurable. Incorporará firma sobre los bytes enviados. |
| `DarkProperties` | Expone parámetros del cliente y aplica configuración en ejecución. Incorporará el modo y las referencias al almacenamiento. |
| `DarkRuntimeConfigurationService` | Persiste JSON y lo aplica a las propiedades. Mantendrá rutas y parámetros públicos; no material privado. |
| `ApiV5DarkController` | Expone configuración y operaciones dARK. Añadirá gestión administrativa de credenciales. |
| `DarkStageWorker` | Reserva lotes y envía metadatos. Necesita recuperación explícita cuando se pierde una respuesta. |
| `DarkReconcileWorker` | Consulta estados remotos. Sus lecturas seguirán disponibles sin firma cuando el router del minter lo permita. |

El cliente construye una petición una vez y la reutiliza en sus reintentos. Ese mecanismo no puede mantenerse para operaciones firmadas: repetir la petición reutiliza el nonce. Generar otro nonce tampoco resuelve por sí solo la incertidumbre sobre la ejecución anterior.

El parent declara Java 17; el POM de dark-lib declara source/target 11. La implementación debe alinear esta configuración con el runtime soportado antes de utilizar Ed25519 nativo.

## 3. Decisiones propuestas

1. Gestionar las claves desde el backend del cosechador mediante una sección propia de dARK.
2. Generar Ed25519 en el servidor. Guardar la privada como PKCS#8 y exportar la pública como `ssh-ed25519` y raw base64. Son representaciones del mismo par, no claves distintas.
3. Para la primera versión, guardar la privada sin passphrase en un volumen protegido por permisos del sistema. Cifrado mediante un gestor de secretos puede añadirse con un proveedor específico; guardar la passphrase junto al archivo no aporta la protección buscada.
4. Conservar las rutas y parámetros en la configuración persistida. Nunca incluir privada o seed en JSON, respuestas, navegador o logs.
5. Mantener un único par de claves vigente. Regenerarlo reemplaza las credenciales del cosechador y pausa las modificaciones hasta recibir confirmación del administrador del minter.
6. Usar una identidad global de cliente por configuración dARK, consistente con el modelo actual. Varias autoridades con claves distintas requerirían ampliar este diseño.
7. Activar credenciales en ejecución usando una instantánea coherente de autoridad, destino y clave. Una petición no debe mezclar valores anteriores y nuevos.

## 4. Almacenamiento y consistencia

Una raíz de almacenamiento persistente contiene un directorio por credencial, identificado con un UUID generado por el backend. Cada directorio incluye la privada PKCS#8, la pública y un manifiesto con versión de formato, key ID y fecha de creación.

Ejemplo orientativo:

```text
/srv/lareferencia/data/keys/
  <credential-id>/
    private.pk8.pem
    public.pub
    manifest.json
```

La configuración persistida guarda la referencia a la credencial vigente y su estado de registro, sus asociaciones y los parámetros operativos. El backend deriva los archivos desde la raíz y el identificador; la interfaz no proporciona nombres de archivo arbitrarios para generar o sobrescribir claves.

La raíz se deriva automáticamente de `store.basepath`, la propiedad de almacenamiento del harvester, añadiendo el subdirectorio `keys`. La interfaz muestra una nota indicando el directorio `keys` del almacenamiento de la aplicación, sin exponer la ruta absoluta ni permitir elegirla y la API rechaza cambios. Validar rutas reales, enlaces simbólicos y permisos antes de escribir.

En sistemas POSIX: directorios con permisos 0700 y privada 0600, propiedad del usuario del servicio. Los archivos se crean sin sobrescribir existentes y mediante escritura temporal y publicación atómica. La privada no entra en repositorios, imágenes de contenedor ni almacenamiento servido por HTTP.

La escritura del filesystem y la transacción de base de datos no son atómicas entre sí. Primero publicar los archivos completos, validarlos y después guardar la referencia. Si falla la persistencia, queda un directorio huérfano recuperable; nunca una referencia activa a una clave incompleta. Al arrancar, detectar referencias rotas e impedir modificaciones firmadas con un diagnóstico claro.

Copias de seguridad: incluir base de datos y volumen de claves de forma coordinada, con acceso restringido. Restaurar solo la base de datos no permite firmar. La primera versión no borra automáticamente credenciales anteriores; definir después una política de retención y eliminación explícita.

## 5. Modelo de configuración

Esquema orientativo que amplía `client` y conserva `stage` y `reconcile`:

```json
{
  "client": {
    "baseUrl": "https://minter.example.org",
    "authorityId": "11111111-1111-4111-8111-111111111111",
    "authHeaderName": "X-Authority-Id",
    "authentication": {
      "mode": "dark2",
      "storageRoot": "/srv/lareferencia/data/keys",
      "credentialId": null,
      "registrationStatus": "not_configured"
    },
    "maxRetries": 3,
    "backoffSeconds": [1, 5, 15]
  },
  "stage": {
    "metadataSchema": "xoai",
    "metadataMediaType": "application/xml",
    "pageSize": 100,
    "maxPagesPerRun": 0,
    "reserveBatchSize": 100
  },
  "reconcile": { "pageSize": 100 }
}
```

Los valores ilustran la estructura; no sustituyen los valores y validaciones existentes. `maxRetries` y `backoffSeconds` gobiernan lecturas. La recuperación de modificaciones se define por operación, fuera del bucle genérico.

Modos propuestos: `legacy` para instalaciones actuales sin DARK2 y `dark2` para firmas. En `dark2`, la ausencia de credencial válida bloquea las modificaciones; no hay fallback silencioso a legacy.

La referencia a la credencial y el estado de registro son administrados por el servicio de claves. El PUT genérico de configuración no debe permitir alterarlos saltándose las validaciones de generación y reanudación. Persistir también la asociación de la credencial con la autoridad y el destino para detectar cambios posteriores.

Cambiar autoridad o destino invalida la comprobación registrada de autenticación y exige revisar la asociación. El `authHeaderName` existente se conserva para legacy; DARK2 usa sus nombres de encabezado fijos.

## 6. Ciclo de vida e interfaz

Separar el estado del material local del estado de comprobación remota:

| Estado local | Significado |
| --- | --- |
| Sin credenciales | Todavía no existe un par utilizable. |
| Pendiente de registro | Existe un par vigente; las modificaciones están pausadas hasta la confirmación externa. |
| Habilitada | El administrador del cosechador confirmó el registro externo y reanudó las modificaciones. No prueba aceptación remota. |
| No disponible | Falta el archivo, no se puede leer o la pareja es inválida. |

Mostrar además «sin comprobar», «última operación firmada aceptada» o «último error de autenticación», con fecha, autoridad, destino y key ID asociados. Una consulta pública exitosa no comprueba la firma. No interpretar cualquier respuesta HTTP como autenticación válida.

### Responsabilidades

El administrador del cosechador genera las claves, comparte únicamente la pública y reanuda las operaciones. El administrador del minter es otra persona: registra esa pública para la autoridad y confirma el registro por el canal acordado. El cosechador no realiza ese registro ni presupone acceso administrativo al minter.

### Primera instalación

1. El administrador del cosechador configura URL HTTP o HTTPS (preferiblemente HTTPS) y modo DARK2. Puede dejar el ID de autoridad vacío para generar y compartir la clave.
2. Pulsa «Generar claves»; se crea el único par vigente y se persiste «Pendiente de registro».
3. Descarga o copia la pública y su huella y las envía al administrador del minter.
4. El administrador del minter registra la instalación con esa pública, proporciona el ID de autoridad, comprueba los NAAN autorizados y confirma el registro y la huella.
5. El administrador del cosechador guarda el ID de autoridad recibido y pulsa «Confirmar registro y reanudar» para la credencial vigente. Guardar el ID conserva el par generado.
6. La siguiente operación firmada aceptada actualiza la información de comprobación remota.

### Regeneración

1. El administrador del cosechador pulsa «Regenerar claves» y confirma la advertencia de interrupción.
2. El backend pausa nuevas modificaciones y espera a que terminen las peticiones en curso antes de reemplazar las credenciales. Si no puede completar esa espera, mantiene la pausa e informa el bloqueo.
3. Genera y valida el nuevo par, publica sus archivos y actualiza la referencia vigente en almacenamiento persistido. No hay selección entre dos pares ni activación de una candidata.
4. Mantiene «Pendiente de registro» y muestra la nueva pública y su huella para enviarlas al administrador del minter.
5. El administrador del minter reemplaza la pública manteniendo la misma autoridad y confirma el registro.
6. El administrador del cosechador confirma ese registro para la credencial vigente y reanuda las modificaciones.

La interrupción dura hasta completar la coordinación con la otra persona. La pausa afecta reservas y envíos de metadatos, tanto manuales como automáticos; las lecturas y consultas de estado continúan. Persistir la pausa para conservarla tras reinicios y aplicarla en el cliente antes de cualquier modificación.

Si la generación o persistencia falla, conservar la referencia anterior y mantener la pausa con un error recuperable. Los archivos anteriores que permanezcan por recuperación técnica o copias de seguridad no constituyen una segunda credencial seleccionable. No eliminar el archivo vigente antes de publicar y persistir correctamente su reemplazo.

Texto propuesto en la interfaz:

> La clave privada se guarda en este servidor y no se muestra. Regenerar reemplaza las credenciales actuales y pausa las reservas y los envíos de metadatos. Envía la nueva clave pública al administrador del minter. Reanuda las operaciones cuando esa persona confirme su registro para esta autoridad. Las consultas de estado continúan disponibles.

La interfaz incluye autoridad, destino, estado de archivos, pública, huella DARK2, fechas y acciones. Gestionar claves requiere el permiso administrativo aplicable al módulo; consultar información operativa no concede permiso para reanudar operaciones o generar credenciales. Registrar quién generó cada credencial y quién confirmó el registro y reanudó las operaciones, sin registrar secretos.

El minter descrito en la guía usa cachés por proceso: el reemplazo remoto no garantiza revocación inmediata de la clave anterior. La interfaz no promete un plazo fijo de revocación.

## 7. Servicios y API propuestos

| Pieza | Responsabilidad |
| --- | --- |
| `DarkKeyStorage` | Crear y leer archivos, validar permisos y publicar escrituras completas. |
| `DarkCredentialService` | Generar pares, verificar correspondencia, gestionar el par vigente y la pausa por registro pendiente y auditar cambios. |
| `DarkRequestSigner` | Construir DARK2 y devolver encabezados sobre cuerpo y URI definitivos. |
| `DarkMinterClient` | Serializar, clasificar operación, firmar y enviar sin alterar los bytes. |
| API e interfaz dARK | Configuración, acciones administrativas e información pública. |

Endpoints propuestos bajo la ruta dARK existente:

| Método y sufijo | Acción |
| --- | --- |
| `GET /authentication` | Estado local, asociaciones, huellas y última comprobación. |
| `POST /authentication/credentials` | Generar o regenerar el par vigente; pausar modificaciones y devolver ID y datos públicos. |
| `GET /authentication/credentials/{id}/public-key` | Obtener o descargar la pública autorizada. |
| `POST /authentication/credentials/{id}/resume` | Confirmar registro externo y reanudar, validando autoridad, destino y versión de configuración. |

Las operaciones concurrentes de generación y reanudación se serializan y usan control de versión. Reanudar con una credencial inexistente, ya reemplazada o asociada a otra autoridad produce un conflicto explícito. La confirmación se refiere al ID y huella actuales, evitando reanudar por la confirmación de una pública anterior. No existe endpoint para descargar la privada.

Una eventual acción «Comprobar autenticación» deberá usar una operación firmada acordada con el minter. La guía no ofrece un endpoint inocuo de validación de firma: no reservar ARKs de prueba silenciosamente ni afirmar comprobación a partir de lecturas públicas.

## 8. Construcción de DARK2

Para `reserveBatch` y `stageArk`:

1. Tomar una instantánea coherente de configuración y credencial.
2. Construir la URI definitiva y validar autoridad y destino.
3. Serializar el objeto una vez con Jackson a UTF-8 `byte[]`.
4. Calcular SHA-256 del buffer exacto y key ID desde los 32 bytes públicos raw.
5. Generar timestamp Unix en segundos y UUID v4 canónico inmediatamente antes del envío.
6. Construir ocho líneas separadas por LF y sin LF final:

```text
DARK2
{METHOD}
{raw_path_and_query}
{authority_id}
{key_id}
{timestamp}
{nonce}
{body_sha256}
```

7. Firmar directamente los bytes UTF-8 del mensaje con Ed25519, sin prehash externo ni envoltura SSH.
8. Enviar el mismo buffer con `BodyPublishers.ofByteArray` y los seis encabezados `X-DARK-Authority-Id`, `X-DARK-Key-Id`, `X-DARK-Timestamp`, `X-DARK-Nonce`, `X-DARK-Content-SHA256` y `X-DARK-Signature`.

La firma se transporta en base64 estándar. La identidad del encabezado coincide exactamente con `authority_id` del cuerpo. Rechazar espacios externos y CR/LF en los campos de firma.

Usar path y query raw, sin reordenar parámetros ni decodificar escapes. Una query vacía no añade `?`; un fragmento no se firma. Deshabilitar redirecciones. La primera versión presupone que el proxy conserva path/query: si elimina un prefijo, definir y validar un mapeo explícito antes del despliegue.

`getArk` y `getArkStatuses` no requieren DARK2 según la guía. La clasificación depende de la operación, no únicamente del verbo HTTP. Firmar no sustituye permisos de NAAN, propiedad del ARK ni validación de metadatos.

## 9. Errores, reintentos y resultados inciertos

| Caso | Tratamiento propuesto |
| --- | --- |
| Lectura con error transitorio | Reintento con backoff según configuración. |
| Error de firma, clave o autoridad | Detener la modificación y mostrar diagnóstico; no reintentar a ciegas. |
| Timestamp fuera de ventana | Informar desfase del reloj; corregir antes de otro intento. |
| Replay | No prueba éxito del negocio; consultar contexto y estado remoto. |
| Timeout o respuesta de modificación ilegible | Registrar resultado incierto y recuperar por operación. |
| Error de permisos o validación | Corregir datos o permisos antes de un nuevo envío. |

Reserva batch: persistir contexto y `client_item_id` antes del envío, conservarlos durante la recuperación y procesar éxitos/errores por elemento. La guía describe reutilización de reservas activas por autoridad, NAAN y correlación; no garantiza exactamente una ejecución en todos los estados. Auditar que la correlación actual del worker sea estable entre ejecuciones antes de habilitar recuperación automática.

Stage de ARK conocido: consultar registro, estado y contenido disponible antes de reenviar. El estado D/U/P por sí solo no demuestra que se aplicó exactamente el payload perdido. Comparar los datos recuperables con el contexto local y definir cuándo es seguro repetir el PUT; si no puede establecerse, conservar la incertidumbre para resolución explícita.

Cada nuevo envío permitido recibe nonce, timestamp y firma nuevos. Un error de negocio puede consumir el nonce anterior. Mantener el hash publicado localmente solo después de confirmar el resultado correspondiente; no marcar éxito por el mero envío.

Distinguir errores globales de autenticación de errores propios del registro. Evitar que una clave incorrecta produzca miles de modificaciones fallidas: detener el lote o ejecución afectada y conservar las lecturas para diagnóstico y reconciliación. Revisar cómo representar el resultado incierto sin confundirlo con un fallo confirmado en el tracking existente.

## 10. Despliegue

Antes de activar DARK2, confirmar la URL de transporte (se recomienda HTTPS con certificados válidos), UUID exacto, pública y huella registradas, NAAN autorizados, firmas habilitadas y path/query efectivos. Mantener sincronizado el reloj del servidor.

El volumen debe sobrevivir a reinicios y recreaciones de contenedores. Verificar lectura y escritura con el usuario real del proceso. Nunca generar otra clave automáticamente al detectar la credencial vigente ausente: una restauración incompleta debe diagnosticarse y recuperarse.

Primera versión: gestión de claves desde una única instancia administrativa. Un despliegue con varias réplicas requiere almacenamiento accesible a las firmantes, exclusión entre gestores e invalidación coordinada de credenciales en memoria; un volumen local por réplica y configuración compartida no es suficiente.

## 11. Fases de implementación y aceptación

### Fase 1 — Modelo y almacenamiento

Definir esquema persistido, asociación autoridad/destino, raíz autorizada, validación y estados. Implementar generación, archivos, par vigente y pausa persistida por registro pendiente. Aceptación: generación sin sobrescritura, consistencia tras fallos y ninguna exposición de privada por API o logs.

### Fase 2 — Firma y cliente

Alinear Java, implementar firmador y serialización única, clasificar rutas y retirar el reintento genérico de modificaciones. Aceptación: reproducir exactamente el vector determinista de la guía y verificar las peticiones enviadas.

### Fase 3 — Recuperación en workers

Auditar correlaciones, persistir contexto previo al envío, definir incertidumbre y recuperación para batch y stage. Aceptación: una respuesta perdida no marca éxito local ni desencadena duplicación a ciegas.

### Fase 4 — API e interfaz

Añadir sección de autenticación, generación, pública, reanudación y advertencias. Aceptación: regenerar pausa modificaciones hasta la confirmación del registro externo, los cambios concurrentes se detectan y la interfaz distingue confirmación administrativa de comprobación remota.

### Fase 5 — Integración y operación

Documentar despliegue y reemplazo; comprobar contra un minter de prueba autorizado. Aceptación: reserva, stage y consulta completos con pública registrada, y reemplazo coordinado conservando la identidad de autoridad.

## 12. Validación prevista

- Vector offline de la guía: pública, key ID, digest, mensaje y firma idénticos.
- Captura HTTP local: digest corresponde al cuerpo enviado; seis encabezados únicos; Unicode, rutas ARK y query preservados.
- Claves: parejas incompatibles, archivos ausentes, permisos, escrituras interrumpidas y generación concurrente.
- Configuración: cambio de autoridad/destino, referencias protegidas y ausencia de fallback en DARK2.
- Recuperación: respuestas perdidas, batch parcial, replay y errores de autenticación sin bucles de modificaciones.
- Interfaz: mensajes y confirmaciones del reemplazo, permisos y ausencia de material privado.
- Integración autorizada: ciclo real y nueva pública registrada; no presentar resultados offline como aceptación de producción.

## 13. Puntos por cerrar antes de implementar

Resolver en el diseño técnico la ubicación del frontend dARK y sus permisos actuales; el contrato para persistir contexto e incertidumbre; la compatibilidad requerida para claves existentes; y si la primera instalación tendrá una o varias instancias firmantes.

No es necesario soportar importación de privadas OpenSSH para automatizar la generación desde el cosechador. Si se requiere migrar claves existentes, añadir un flujo específico que preserve el par y no exponga secretos.

La coordinación automática con Admin del minter queda como ampliación futura y requeriría credenciales administrativas independientes de DARK2.


## 14. Avance de implementación (11 de octubre de 2026)

Implementados el almacenamiento POSIX con creación atómica, el único par vigente, la pausa persistida y la confirmación del registro externo; firma DARK2 en el cliente; endpoints ADMIN; y sección de autenticación en el frontend ES/EN/PT. El modo legacy sigue siendo el valor inicial.

La raíz es `${store.basepath}/keys` y `storageRoot` informa la ruta derivada, sin admitir selección. Las modificaciones y los cambios de credenciales comparten un monitor en la única instancia soportada. La gestión usa transacciones independientes y aplica la configuración en memoria después de confirmar su persistencia.

La recuperación inicial conserva las correlaciones de batch y bloquea el reenvío automático de stages con resultado incierto. Mantiene la advertencia al reconciliar estados y pide una decisión explícita antes de reenviar manualmente. Una ampliación de la fase 3 debe añadir un registro durable del contexto antes del envío para cubrir también la caída del proceso entre la ejecución remota y la persistencia local; el manejo actual cubre errores y respuestas perdidas detectados por el proceso.

La comprobación remota de autenticación sigue siendo una operación firmada autorizada. La pantalla muestra la confirmación administrativa, sin afirmar que el minter aceptó una firma. La integración real, la gestión entre réplicas y la importación de claves existentes quedan fuera de esta primera implementación.

DARK2 permite HTTP sin bloqueo. La interfaz muestra una advertencia sobre la falta de cifrado del transporte y recomienda HTTPS. Se siguen rechazando otros esquemas, credenciales en la URL, query y fragmento en la URL base.

La ubicación de las claves usa el almacenamiento existente del harvester: `${store.basepath}/keys`. La interfaz indica únicamente que se almacenan en el directorio `keys` del almacenamiento de la aplicación. El backend calcula siempre esa ruta y rechaza cualquier ubicación distinta enviada por la API. Para instalaciones con archivos en la ubicación anterior, trasladar el directorio de la credencial conservando su ID y permisos.

La configuración del minter integra URL y modo, clave pública para copiar o descargar, y autoridad con activación. El ID puede estar vacío al guardar DARK2 y generar claves; es obligatorio para confirmar el registro y habilitar modificaciones. La huella y explicación de la privada están en detalles desplegables; reintentos, cabecera y parámetros de lotes se agrupan en configuración avanzada.

Compatibilidad con minters que tienen la verificación de firmas desactivada: las modificaciones DARK2 envían también `X-Authority-Id`, con el mismo valor de `X-DARK-Authority-Id` y del cuerpo. La configuración del servidor determina si verifica la firma; el cliente mantiene todos los encabezados DARK2.
