---
name: docker-similar-env
description: Crear o adaptar entornos Docker de desarrollo similares al patron de lareferencia-platform (docker-compose + carpeta Docker + wrapper Docker/dev.sh). Usar cuando Codex necesite portar este patron a otro repositorio, disenar un stack multi-servicio con perfiles opcionales, automatizar bootstrap de dependencias externas, centralizar operaciones en un comando dev.sh o documentar capacidades operativas del entorno.
---

# Docker Similar Env

## Objetivo

Crear un entorno local reproducible, con infraestructura y apps desacopladas, operado desde un solo wrapper `Docker/dev.sh`.
Aplicar este skill para clonar el enfoque de este repo en proyectos nuevos o para refactorizar un compose desordenado a un patron mantenible.

## Flujo De Trabajo

1. Levantar inventario tecnico del proyecto destino.
2. Diseñar topologia de servicios y persistencia.
3. Crear estructura `Docker/` y entrypoints idempotentes.
4. Implementar `Docker/dev.sh` como interfaz unica.
5. Documentar comandos y validar arranque end-to-end.

## Entradas Minimas

- Lista de modulos/apps a correr en local.
- Dependencias de infraestructura (db, search, cache, queues, etc).
- Puertos y endpoints esperados.
- Reglas de persistencia y datos efimeros.
- Variables de entorno necesarias.
- Tareas operativas frecuentes (up, logs, init-db, reset, debug).

## Patron Objetivo

Mantener esta estructura base:

- `docker-compose.yml` en la raiz.
- `Docker/dev.sh` como fachada operacional.
- `Docker/<dominio>/Dockerfile` + `entrypoint.sh` por tipo de servicio.
- `Docker/data/*` para persistencia por bind mounts.
- `Docker/config-overrides/*` para overrides de runtime.
- `Docker/.env.example` con defaults documentados.

## Contrato De Docker/dev.sh

Implementar estos grupos de comando:

- Ciclo de vida: `up`, `down`, `start`, `stop`, `restart`, `ps`, `logs`, `build`, `pull`.
- Salud: `health` con chequeo de endpoints HTTP y estado compose.
- Bootstrap: inicializar dependencias externas faltantes (ej: clonar repo externo si no existe).
- Plataforma: comandos para migraciones/init (`init-db`), shell interactivo y `exec`.
- Modo servicio: subcomandos por dominio (`vufind ...`, `solr ...`, etc).
- Perfiles opcionales: activar/desactivar servicios no obligatorios (`elastic`, `watch`).
- Seguridad operacional: `reset-data` con confirmacion explicita antes de borrar volumenes.

## Capacidades A Replicar

1. Arranque idempotente con inicializacion solo en primer boot.
2. Separacion entre servicios stateful e imagenes de aplicacion.
3. Overrides de configuracion por archivo sin mutar config original del repo.
4. Build lazy o on-demand para apps (ejecutar build solo si falta artefacto).
5. Volumen dedicado para cache de dependencias (ej: Maven, Composer, npm).
6. Profiles de Compose para features opcionales.
7. Operacion diaria simplificada en una CLI humana (`dev.sh`).
8. Ruta clara de debugging para alternar modo dev/prod desde `.env`.

## Pasos De Implementacion

1. Crear `docker-compose.yml` con servicios core y puertos locales explicitos.
2. Definir volumes bind para codigo fuente y data persistente.
3. Crear Dockerfiles por dominio y entrypoints con inicializacion idempotente.
4. Implementar `Docker/dev.sh` con parser de comandos y ayuda integrada.
5. Agregar `Docker/.env.example` con defaults seguros para local.
6. Agregar `Docker/config-overrides/<modulo>/99-docker.properties` para runtime local.
7. Probar secuencia minima:
   - `./Docker/dev.sh up --build`
   - `./Docker/dev.sh health`
   - `./Docker/dev.sh init-db` (o equivalente del proyecto)
8. Probar secuencia de operacion:
   - logs por servicio
   - toggle de perfiles opcionales
   - reset de data con confirmacion
9. Documentar endpoints y comandos frecuentes.

## Reglas De Adaptacion

- No copiar nombres de modulos/puertos de forma literal; parametrizar.
- No hardcodear credenciales fuera del `.env` del proyecto.
- Evitar logica de negocio en compose; dejarla en entrypoints o app config.
- Preservar idempotencia: cada contenedor debe poder reiniciar sin destruir estado.
- Mantener fallback razonable cuando falta entrada interactiva.

## Validacion Final

- `docker compose -f docker-compose.yml config` sin errores.
- `./Docker/dev.sh up` levanta servicios core esperados.
- `./Docker/dev.sh health` responde con codigos HTTP validos o diagnostico util.
- Un restart completo no rompe datos persistidos.
- `reset-data` requiere confirmacion y limpia solo rutas permitidas.

## Referencias De Este Patron

Leer `references/lareferencia-pattern.md` para detalles concretos del stack base (servicios, perfiles y entrypoints) que originan este skill.
