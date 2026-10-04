# Autenticación y autorización local de Harvester API v5

**Status:** current · **Last verified:** 2026-09-30

Esta guía describe el modelo local desplegado para las interfaces de Harvester y `/api/v5`. Sustituye por completo la autenticación v5 basada en fichero, HTTP Basic y OIDC/Keycloak. No hay importación de cuentas, grupos o contraseñas: las instalaciones deben crear explícitamente su primer administrador.

## Resumen del modelo

| Identidad | Autenticación | Alcance |
|---|---|---|
| Usuario `ADMIN` | Usuario y contraseña en una sesión web | Acceso global; administra identidades y configuración |
| Usuario `READER` | Usuario y contraseña en una sesión web | Solo lectura sobre las redes asignadas |
| Usuario `DASHBOARD` | Usuario y contraseña en una sesión web | Dashboard y lectura de las redes asignadas; sin acceso al Admin |
| Cuenta técnica | Token Bearer revocable | Solo lectura sobre las redes asignadas; no inicia sesión en la web |

Las asignaciones se guardan por ID estable de red. La interfaz muestra el acrónimo para reconocerlas. No hay permisos de escritura por red: las acciones, configuración, workers, administración y dARK son globales y requieren `ADMIN`.

## Puesta en marcha

### Requisitos y configuración

Se necesita PostgreSQL accesible tanto por el shell como por Harvester, con la misma base de datos y credenciales. Configure sus URL/usuario/contraseña en los `application.properties` de ambos módulos. La base de datos es la fuente de usuarios, grants, cuentas técnicas, hashes de tokens y sesiones; no se crea ningún usuario ni contraseña automáticamente al arrancar.

El build de plataforma produce el shell y Harvester, incluyendo los recursos de migración:

```bash
./build.sh lareferencia
```

El fragmento `lareferencia-lrharvester-app/config/application.properties.d/10-api-v5.properties` fija actualmente:

```properties
security.api-v5.allowed-origins=
security.api-v5.page-size-max=200
security.api-v5.cookies-secure=false
server.servlet.session.cookie.http-only=true
server.servlet.session.cookie.secure=false
server.servlet.session.cookie.same-site=lax
server.servlet.session.timeout=30m
spring.session.store-type=jdbc
spring.session.jdbc.initialize-schema=never
```

Los valores distribuidos permiten desarrollo por HTTP, incluidas direcciones IP remotas. Para desplegar con HTTPS, configure tanto `security.api-v5.cookies-secure=true` como `server.servlet.session.cookie.secure=true` y reinicie Harvester. Mantenga `server.servlet.session.cookie.http-only=true` en ambos casos.

La interfaz de producción y la API deben servirse bajo el mismo origen. Si durante desarrollo o despliegue se separan, configure en `security.api-v5.allowed-origins` los orígenes exactos permitidos, separados por comas; CORS admite credenciales y no debe abrirse con `*`. La cookie `Secure` requiere HTTPS en el navegador (incluido el TLS terminado en el proxy público). Si el login detecta que está en HTTP y no recibió la cookie CSRF, mostrará un aviso: use HTTPS o configure cookies no seguras solo en un entorno local de desarrollo. No cambie `initialize-schema=never`: Flyway administra el esquema.

### Migrar el esquema y crear el primer administrador

Desde `lareferencia-shell`, use la configuración conectada a la misma base de Harvester. Abra el shell en una terminal interactiva real:

```bash
cd lareferencia-shell
./lareferencia-shell.jar
```

Ejecute primero la migración Flyway y después cree la cuenta inicial:

```text
database_info
database_migrate
security-create-admin admin
```

`security-create-admin` solicita y confirma la contraseña sin mostrarla en pantalla. No acepta la contraseña como argumento ni funciona sin consola interactiva. El nombre se normaliza a minúsculas; admite letras ASCII, números y `._@+-`, con longitud de 3 a 100. La contraseña debe tener entre 12 y 200 caracteres. El comando guarda BCrypt y se niega a crear la cuenta si ya existe un administrador habilitado. No cree el primer administrador insertando a mano una contraseña.

Para recuperar el acceso o cambiar una contraseña desde el shell, ejecute `security-reset-password <usuario>`. El comando solo modifica usuarios existentes, solicita y confirma la nueva contraseña sin mostrarla y revoca las sesiones activas de esa cuenta. También requiere una consola interactiva y acepta la misma longitud y formato de usuario.

`database_migrate` aplica las migraciones pendientes con Flyway. Use las opciones `--out-of-order` o `--baseline-on-migrate` solo cuando el estado de esa base lo requiera; consulte `help database_migrate` y el runbook de base de datos antes de cambiar los valores por defecto. Mantenga una copia de seguridad según el procedimiento normal antes de migrar una base existente.

Después, desde la raíz del workspace ejecute `./build.sh lareferencia` para compilar Java y ambas interfaces, o reconstruya el artefacto Docker correspondiente. Abra `/admin/` para la interfaz React e inicie sesión con el administrador recién creado. El administrador puede crear usuarios, cuentas técnicas y grants desde la sección de administración de la interfaz; el Dashboard está en `/dashboard/`.

### Tablas y persistencia

La migración `lareferencia-shell/src/main/resources/db/migration/V5.0.0.13__Local_Identity_Authorization.sql` crea las tablas de usuarios locales, asignaciones usuario-red, cuentas técnicas, asignaciones cuenta-red y tokens. También declara las tablas JDBC de Spring Session; la inicialización automática de Spring Session está deshabilitada. Todos los nodos web deben compartir PostgreSQL para compartir las sesiones. El estado de habilitación, asignaciones y revocaciones se consulta en el servidor y no depende de almacenamiento en el navegador.

## Sesiones web, login y CSRF

Endpoints públicos/necesarios para iniciar sesión:

```text
GET  /api/v5/auth/csrf
POST /api/v5/auth/login
POST /api/v5/auth/logout
GET  /api/v5/me
```

El frontend solicita primero `/auth/csrf`, conserva la cookie CSRF y envía el token devuelto en `X-XSRF-TOKEN` al iniciar/cerrar sesión y en las operaciones no seguras. El login recibe JSON `{ "username": "…", "password": "…" }`; con credenciales válidas crea una sesión y rota el identificador de sesión. La contraseña solo se envía al endpoint de login; React no la guarda ni la adjunta a cada petición. Al recargar, React consulta `/api/v5/me`; al salir, invalida la sesión mediante logout.

La cookie de sesión `JSESSIONID` es `HttpOnly`, `Secure` y `SameSite=Lax`; el timeout configurado es de 30 minutos. El token CSRF se transporta además en la cookie `XSRF-TOKEN`, legible por el frontend para poder reflejarlo en el encabezado. `HttpOnly` protege la cookie de sesión, no la cookie CSRF. Todas las operaciones con sesión que cambian estado deben incluir `X-XSRF-TOKEN`.

El filtro CSRF se aplica según el método HTTP, también a `POST` que funcionalmente sean consultas de solo lectura (por ejemplo, búsquedas tipadas de diagnósticos). Esas rutas autorizan la lectura por el alcance de red, no por el rol de escritura; aun así, el cliente debe presentar CSRF. No asuma que un Bearer `POST` puede omitir el requisito: los clientes de integración que usen esas rutas deben obtener/reflejar el token CSRF y enviar las cookies según la configuración de origen. Los `GET` de lectura no requieren CSRF.

Spring Session JDBC persiste las sesiones para que puedan compartirse entre instancias con la misma base. Proteja PostgreSQL y el canal de conexión, configure HTTPS extremo a extremo y no registre contraseñas, cookies, encabezados de autorización ni tokens.

## Usuarios, cuentas técnicas y tokens

### Usuarios humanos

El administrador gestiona usuarios mediante endpoints v5 (todos requieren `ADMIN` y CSRF cuando se usa sesión):

```text
GET     /api/v5/users
POST    /api/v5/users
PUT     /api/v5/users/{username}
DELETE  /api/v5/users/{username}
```

Un usuario nuevo tiene nombre, contraseña (12–200 caracteres), rol `ADMIN`, `READER` o `DASHBOARD`, estado habilitado y, para los dos últimos, una o más redes. La contraseña se almacena con BCrypt. El usuario puede deshabilitarse, cambiar de rol/contraseña y recibir nuevas asignaciones. No se puede eliminar la cuenta administradora autenticada; el servicio protege también contra dejar el sistema sin administradores activos.

### Cuentas de servicio

Las cuentas técnicas son identidades independientes, no usuarios humanos ni roles heredados:

```text
GET/POST    /api/v5/service-accounts
PUT/DELETE  /api/v5/service-accounts/{id}
GET/POST    /api/v5/service-accounts/{id}/tokens
DELETE      /api/v5/service-accounts/{id}/tokens/{tokenId}
```

Cada cuenta requiere una o más redes asignadas. Para emitir un token se proporciona `expiresAt` futuro; la vida máxima admitida es de cinco años. La respuesta de emisión contiene el secreto completo una sola vez, con prefijo `lrh_`; cópielo en un gestor de secretos en ese momento. La base guarda el prefijo y el hash SHA-256, no el secreto recuperable. Los listados posteriores muestran metadatos, no el valor del token. Deshabilitar/eliminar la cuenta o revocar un token impide su uso en la siguiente petición.

Una integración envía el valor completo así:

```http
Authorization: Bearer lrh_<secreto>
```

No coloque tokens en URL, logs, repositorios ni configuración versionada. Cree tokens separados por consumidor y con expiración acorde a su política operativa.

## Autorización por red

`ADMIN` tiene acceso global. `READER`, `DASHBOARD` y las cuentas técnicas solo pueden consultar redes explícitamente asignadas. `READER` y las cuentas técnicas usan las lecturas nativas de v5; `DASHBOARD` usa exclusivamente `/api/v5/dashboard/**`; `ADMIN` puede usar ambas superficies. La API filtra las redes y los resúmenes antes de calcular la paginación; los contadores no deben revelar redes ajenas. Para rutas por ID, se vuelve a comprobar que la red o snapshot pertenece a una red autorizada: conocer un ID no concede acceso. Historial, logs, resumen/filas/ocurrencias de diagnóstico y metadata heredan el permiso de lectura de la red propietaria. Los recursos de configuración, operaciones, acciones, workers, administración y dARK son solo de administrador.

| Capacidad | `ADMIN` | `READER` / token técnico | `DASHBOARD` |
|---|---:|---:|---:|
| API v5 administrativa de lectura | Todas | Solo asignadas | No |
| API `/api/v5/dashboard/**` | Todas | No | Solo asignadas |
| Crear/modificar/eliminar redes, ejecutar acciones | Sí | No | No |
| Configurar validadores, transformadores, workers y aplicación | Sí | No | No |
| dARK y administración de identidades/tokens | Sí | No | No |

La interfaz oculta acciones no permitidas por comodidad, pero el control efectivo está en el backend y no depende del cliente React.

## Superficies retiradas y ausencia de compatibilidad

La seguridad de Harvester ya no acepta `security.api-v5.auth-mode`, usuarios en `config/users.properties`, HTTP Basic ni OIDC/Keycloak. `users.properties`, `users.properties.default`, `add-user.py`, los modos `file`/`oidc`/`hybrid` y las antiguas rutas de login no crean identidades v5. No se migran ni importan usuarios o contraseñas. La actualización requiere aplicar Flyway y crear el admin local antes de usar la interfaz.

Las SPAs se sirven en rutas separadas: Admin React en `/admin/` y Dashboard Angular en `/dashboard/`; no existe fallback AngularJS `/legacy`. Las rutas fuera de `/api/v5` que no sean esos recursos estáticos explícitos se deniegan por seguridad; no se debe usar `/rest`, `/public` o `/private` como API de administración. OpenAPI y Swagger están en `/api/v5/openapi` y `/api/v5/docs`.

El dashboard Angular registrado en `lareferencia-repository-dashboard` usa la sesión local v5 y endpoints de lectura `/api/v5/dashboard/**`; no usa Keycloak ni API v2. En Docker Dev, el gateway separa `admin.localhost` (API v5 completa) de `dashboard.localhost` (solo autenticación y lecturas del dashboard). El despliegue real debe reproducir esa allowlist en su proxy y servir ambos hosts bajo HTTPS.

La migración Flyway `V5.0.0.14` habilita `DASHBOARD`; no convierte automáticamente usuarios `READER`. El administrador debe revisar cuáles necesitan Dashboard y cambiarles el rol. Al cambiar rol, estado o contraseña se invalidan las sesiones JDBC de ese usuario.

## Verificación de despliegue

Antes de exponer una instalación, verificar al menos:

1. Flyway crea las tablas de identidad y sesión; crear un admin interactivo y comprobar que un segundo bootstrap falla.
2. Login correcto/incorrecto, `/me` tras recargar, logout, sesión expirada, usuario deshabilitado y rotación de sesión.
3. CSRF ausente/incorrecto bloquea operaciones inseguras; UI usa cookie y encabezado CSRF.
4. `READER` y tokens técnicos ven solo sus redes en la API nativa; `DASHBOARD` ve solo sus redes en la API Dashboard. Las otras superficies devuelven `403`; IDs directos ajenos no devuelven datos.
5. Diagnósticos `POST` funcionan para lectura autorizada cuando se incluye CSRF; mutaciones y administración siguen siendo exclusivas de `ADMIN`.
6. Tokens expirados, revocados o pertenecientes a cuenta deshabilitada fallan en la petición siguiente; el secreto solo se muestra al emitirlo.
7. Dos instancias conectadas a la misma base comparten sesiones; una sesión no aparece al usar otra base.
8. `/` sirve React, `/legacy` no sirve la aplicación antigua y `/rest/**`, `/public/**` y `/private/**` no están expuestos como APIs de Harvester.

Referencias: [API v5](HARVESTER_MANAGEMENT_API_V5.md), [configuración](CONFIGURATION_PROPERTIES.md), [shell](../lareferencia-shell/README.md) y [aplicación Harvester](../lareferencia-lrharvester-app/README.md).
