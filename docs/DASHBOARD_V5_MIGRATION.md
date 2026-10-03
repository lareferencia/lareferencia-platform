# Migración del Repository Dashboard a la autenticación y API v5

**Status:** integration in progress · **Last updated:** 2026-09-30 · **Angular refactor and separate builds:** implemented and compiled · **runtime/gateway verification:** pending

Este documento es el plan de trabajo para migrar `lareferencia-repository-dashboard`
(Angular) al esquema local de autenticación y consultas del Harvester v5. Actualizar
las casillas al completar cada fase y corregir este documento si cambia el contrato.

## Objetivo y límites

El dashboard será una interfaz de consulta de redes, cosechas y validaciones. Las
identidades, cuentas técnicas, tokens y asignaciones de redes se administran desde el
Admin Web React del Harvester. La autorización efectiva de datos permanece en el
backend v5.

Esta migración incluye cambios Angular, correcciones puntuales al adaptador de lectura
`/api/v5/dashboard`, artefactos estáticos separados y rutas distintas. No cambia los
contratos nativos de `/api/v5`. Se añade un gateway local para simular hosts separados;
la configuración de TLS y hostnames de producción debe aplicarse al proxy de despliegue.
No exponer públicamente el puerto del Harvester.

El proyecto padre está en `5.0.0-rc3`. El dashboard se alineó a esa versión y el tag
existente `2.2.0` conserva la versión anterior.

## Estado actual

- [x] Clonar y registrar `lareferencia-repository-dashboard` como módulo Git del platform.
- [x] Alinear `angular/package.json` y el lockfile raíz a `5.0.0-rc3`.
- [x] Migrar autenticación, rutas y servicios Angular (compila; validación en navegador pendiente).
- [x] Corregir y documentar brechas del adaptador `/api/v5/dashboard` (adapter y normalización del frontend en su lugar; validación runtime pendiente).
- [ ] Validar los flujos Angular con `ADMIN` y `DASHBOARD`, y el rechazo de `READER`.
- [x] Integrar ambos builds frontend al reactor Maven con directorios estáticos separados.
- [x] Servir `/admin/**` y `/dashboard/**` desde directorios distintos en Harvester.
- [x] Añadir gateway Nginx local con hosts separados y allowlist de API para Dashboard.
- [x] Compilar las SPAs y publicar sus artefactos localizados en directorios separados.
- [x] Validar sintaxis de Nginx y configuración Compose del gateway.
- [ ] Validar end-to-end bloqueo de rutas directas y autenticación/lecturas vía gateway.
- [ ] Aplicar TLS y hostnames de producción al proxy de despliegue.

La SPA Angular ya usa la sesión local v5, retiró Keycloak, la administración de usuarios,
grupos y cosechas, además del broker, y dirige las consultas al adaptador
`/api/v5/dashboard`. El reactor Maven publica Admin Web en
`lareferencia-lrharvester-app/admin-static` y Angular en `dashboard-static/{en,es,pt}`.
El Harvester sirve cada aplicación solo bajo `/admin/` o `/dashboard/`. `docker-dev`
inicia un gateway Nginx local en el puerto 8188 en modo aislado (8088 en modo normal): `admin.localhost` permite el UI admin
y API v5 completa; `dashboard.localhost` permite los assets, CSRF/login/logout/`/me` y
solo GET a `/api/v5/dashboard/**`. Operaciones admin y cosechas por el host Dashboard
se deniegan. Docker Dev publica Harvester directamente solo en loopback (`8190`
aislado) además del gateway (`8188`); este acceso directo es útil para desarrollo y
omite únicamente la allowlist de hosts del proxy, no la autorización de la API. Vite
no tiene puerto publicado. Las cookies Secure se desactivan únicamente en ese perfil
local HTTP; el valor predeterminado de producción permanece seguro. El gateway local
no sustituye TLS ni la configuración de dominios de producción. El estado de los
contratos está documentado en
[`HARVESTER_MANAGEMENT_API_V5.md`](HARVESTER_MANAGEMENT_API_V5.md).

## Fases de implementación

### 1. Sustituir Keycloak por la sesión v5

- [x] Retirar `keycloak-angular`, `keycloak-js`, el inicializador y el guard de Keycloak,
      la configuración `key_cloack_config`, el endpoint de autenticación OIDC y los
      recursos SSO que queden sin uso.
- [x] Implementar cliente de autenticación Angular para
      `GET /api/v5/auth/csrf`, `POST /api/v5/auth/login`, `GET /api/v5/me` y
      `POST /api/v5/auth/logout`.
- [x] Al iniciar la SPA, restaurar la sesión con `/me`; sin sesión, presentar el login
      Angular y conservar la ruta de retorno. Manejar `401` como sesión ausente o
      vencida y `403` como acceso denegado.
- [x] Enviar cookie de sesión y encabezado CSRF en operaciones mutables. No guardar
      contraseñas ni bearer tokens en el navegador. Los bearer tokens son para
      integraciones técnicas; una cuenta técnica no inicia sesión web.
- [x] Confirmar que la configuración y el cliente admiten cookie `Secure`, `SameSite=Lax`
      y credenciales. El despliegue soportado servirá UI y API bajo el mismo origen;
      la configuración CORS exacta se resolverá al integrar el proxy.

### 2. Quitar administración heredada y broker

- [x] Eliminar rutas, pantallas, servicios, modelos y configuración de administración
      antigua de usuarios/grupos, incluida la carga masiva y edición de perfil.
- [x] Eliminar por completo la página/módulo broker, sus servicios, modelos y
      configuración. Broker queda fuera de esta migración y no tiene contrato v5
      acordado.
- [x] Retirar la ruta y pantalla experimental de administración de redes/cosechas:
      la administración operacional pertenece al Admin Web React.
- [x] Conservar la vista de perfil solo en modo lectura, usando `/api/v5/me` para mostrar
      usuario, roles y redes legibles. No ofrecer cambios de contraseña, roles ni permisos
      desde Angular.
- [ ] Limpiar y revisar catálogos XLF: pantallas y navegación ya se retiraron de Angular,
      pero las traducciones no se han podado ni revalidado.

### 3. Migrar consultas y ajustar contratos

- [x] Migrar listado de redes, detalle, último snapshot e historial a
      `/api/v5/dashboard/harvesting/source/...`.
- [x] Migrar resumen de validación, registros, filtros y ocurrencias a
      `/api/v5/dashboard/validation/...`.
- [x] Comparar los modelos TypeScript con las respuestas reales: `content` y
      `totalElements`, campos de snapshots, `rulesByID`, observaciones y ocurrencias.
      Ajustar tipos y transformaciones de la UI donde difieran.
- [x] Corregir la consulta por rango de fechas: enviar fechas en el formato aceptado por
      el backend y comprobar límites inclusivos, paginación y orden temporal.
- [x] Auditar cada llamada que la UI realmente use, incluidos logs y metadata. Si una
      función no está en el adaptador, usar el endpoint nativo v5 correspondiente solo
      si ya forma parte del alcance de lectura; de lo contrario, documentar y completar
      el adaptador separado. No reutilizar rutas v2 ni cambiar rutas nativas v5.
- [x] Revisar paginación del selector: recorrer todas las páginas y conservar una red
      guardada solo si todavía figura entre las redes autorizadas por el servidor.
- [ ] Validar en runtime estados de consulta vacía, errores, redes sin snapshots y
      pérdida de permiso; no debe recurrirse a datos locales ni solicitudes sin filtrar.

### 4. Conservar estadísticas bajo configuración explícita

- [x] Mantener el módulo estadístico que consume el widget externo como función
      condicionada, no como servicio necesario para autenticarse o consultar cosechas.
- [x] Mostrarlo solo cuando la configuración lo active y la red tenga
      `attributes.stats_source_id`; si falta cualquiera, ocultar la entrada o mostrar un
      estado vacío claro.
- [ ] Verificar la carga del script externo y sus etiquetas de alcance. No asumir que el
      widget acepta la cookie local del Harvester ni enviarle credenciales/tokens.

### 5. Documentar, integrar y cerrar

- [x] Reemplazar el ejemplo `appConfig.json.model` y tipos TypeScript: eliminar URLs v2,
      claves de Keycloak, broker y administración antigua; definir una base API v5 y la
      configuración de estadísticas que siga vigente.
- [x] Actualizar README Angular con instalación, configuración local, login, permisos,
      servicios conservados y funciones retiradas.
- [x] Integrar los frontends en el empaquetado y añadir proxy local por host; no definir
      Domain en la cookie de sesión para que cada host mantenga su propia sesión.
- [ ] Configurar HTTPS y dominios de producción en el proxy de despliegue. Mantener el
      puerto 8090 privado/loopback-only o en una red privada accesible solo al proxy.
- [ ] Actualizar el estado de este checklist y la documentación del platform después
      de completar la integración.

## Contratos y autorización

El navegador usa identidad humana con sesión local y permisos que devuelve `/api/v5/me`.
`ADMIN` puede consultar todas las redes; `DASHBOARD` solo las asignadas. `READER` no accede a esta API. El frontend filtra
la navegación según esa sesión, pero los endpoints verifican siempre el acceso en el
backend. Las consultas directas a redes o snapshots ajenos deben terminar en `403` y no
incluir datos.

El listado compatible del dashboard filtra antes de paginar. Para recursos de un
snapshot se valida que dicho snapshot pertenezca a una red autorizada. Las APIs de
identidades (`/api/v5/users`, `/api/v5/service-accounts` y tokens) pertenecen a la
administración React, no a esta UI.

## Criterios de aceptación

- No quedan referencias ejecutables a Keycloak, a contratos de consulta `/api/v2`, a
  administración vieja de usuarios/grupos ni a broker dentro de Angular.
- Login incorrecto no crea sesión; login correcto restaura `/me` tras recargar; logout
  invalida sesión; CSRF incorrecto bloquea login/logout.
- `ADMIN` consulta todas las redes y `DASHBOARD` solo las suyas; `READER` y los tokens técnicos reciben `403`, incluso al solicitar URLs
  manualmente o usar IDs de snapshots.
- Selector, historial, fechas, resumen de validación, filtros de registros, ocurrencias,
  metadata y exportaciones mantienen resultados correctos con las respuestas v5.
- Estadísticas aparece únicamente con módulo activo y `stats_source_id` presente; si el
  widget externo falla, las demás consultas siguen funcionando.
- El build Angular termina correctamente y los README/documentos describen el mismo
  estado y alcance.
- El gateway local debe devolver 404 para `/admin/**` y API administrativa bajo
  `dashboard.localhost`; repetir esta comprobación después de configurar el proxy real.

## Referencias

- [Autenticación y autorización v5](AUTHENTICATION.md)
- [Contrato de la API v5](HARVESTER_MANAGEMENT_API_V5.md)
- [Arquitectura y estado de integración](ARCHITECTURE.md)
- [README del dashboard Angular](../lareferencia-repository-dashboard/angular/README.md)
