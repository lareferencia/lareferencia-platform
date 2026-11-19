---
name: lareferencia-features
description: "Desarrollar features en LA Referencia con githelper y repositorios coordinados: identificar módulos, crear ramas desde main, implementar y probar, preparar commits y PR con el lock actualizado. Usar para nuevas funcionalidades o cambios que involucren la plataforma y sus módulos; también para cerrar una feature con una release cuando el usuario lo solicite."
---

# Features de LA Referencia

Implementar la funcionalidad hasta el alcance solicitado, siguiendo el githelper del checkout actual. Las instrucciones del usuario y la autorización existente prevalecen. Invocar este skill no autoriza por sí mismo pushes, PR, merges ni publicación; realizar esas operaciones cuando formen parte del encargo o estén ya autorizadas.

## Descubrir el estado y el alcance

1. Ubicar la raíz de `lareferencia-platform`. Leer instrucciones locales aplicables, `githelper.md`, `workspace.ini`, `workspace.lock` y los POM relevantes. Consultar la ayuda o implementación de githelper antes de usar opciones que no estén documentadas. No asumir versiones, número de módulos o identificadores de PR de sesiones anteriores.
2. Inspeccionar rama, upstream, commits locales y cambios pendientes tanto en plataforma como en los módulos involucrados. Usar el registro del workspace y el reactor Maven para descubrir módulos, no una lista fija.
3. Identificar qué repositorios necesitan cambios y sus dependencias. VuFind es externo a la plataforma; no incluirlo en manifest, lock o releases. Mantener los legacy fuera de la sincronización de versiones del reactor activo.
4. Conservar configuración, datos, archivos ignorados y trabajo previo. No ejecutar resets destructivos ni descartar commits. Si el usuario quiere incorporar cambios existentes, integrarlos expresamente: guardarlos en una rama o stash no equivale a incorporarlos.

## Crear o ampliar la feature

En un workspace limpio, preparar la base congelada antes de crear ramas:

```bash
git switch main
git pull --ff-only
./githelper init
./githelper feature start codex/nombre-feature --modules modulo-a,modulo-b
```

Sustituir los nombres por módulos reales. `init` recupera los commits del lock; puede dejar módulos con HEAD separado. No usar `sync`, `pull` de módulos o `init --dev` como sustituto para alinear una release.

`feature start` crea ramas desde `origin/main` en plataforma y módulos seleccionados, y registra la relación en `workspace.ini`. No incorpora automáticamente commits exclusivos del main local. Resolver esa situación antes de avanzar si esos commits deben formar parte de la feature. No reutilizar a ciegas ramas existentes ni borrarlas para evitar colisiones.

Si la feature ya existe, inspeccionar su registro y continuar en sus ramas. Para ampliar el alcance:

```bash
./githelper feature add modulo-c
```

Los módulos ajenos a la feature permanecen en su base congelada. El cambio de `workspace.ini` producido por githelper es esperado. No cambiar manualmente ramas registradas a main durante el cierre coordinado.

## Implementar y verificar

- Escribir código y pruebas pertinentes en cada repositorio afectado. Respetar convenciones locales y evitar cambios ajenos al pedido.
- Para cada fix o feature relevante, añadir una entrada breve en `CHANGELOG.md` de la raíz de plataforma, bajo `Unreleased`, agrupada en `Correcciones`, `Funcionalidades` o `Cambios` según corresponda. Explicar el efecto para quien instala o usa la plataforma e identificar el módulo cuando ayude. Enlazar el PR real cuando esté disponible, sin inventar números; completar el enlace después de abrirlo. Registrar una vez el cambio coordinado, aunque afecte varios módulos, y conservar las entradas pendientes de otros cambios.
- Mantener herencia de versión del padre, dependencias internas centralizadas y versiones npm consistentes. No incrementar versiones para cada commit de feature; la preparación de release se encarga de ello.
- Ejecutar pruebas focalizadas durante el desarrollo. Para cambios de integración o cuando se solicita la suite completa, ejecutar desde plataforma:

```bash
python3 -m unittest discover -p 'test_*.py'
./githelper version sync --check
mvn --batch-mode --no-transfer-progress clean verify -Plareferencia
```

Consultar el workflow Maven actual para servicios y propiedades de pruebas. Testcontainers requiere Docker; las pruebas de base de datos necesitan una instancia desechable, nunca producción. `mvn test` no ejecuta las pruebas Failsafe de OAI. `build.sh` omite pruebas y no acredita que la suite pase. No presentar `mvn validate` como compilación.

Si cambia el frontend admin, tras preparar sus dependencias con Maven ejecutar también su runner actual; en el checkout documentado:

```bash
(cd lareferencia-lrharvester-admin-web && ./node/node node_modules/vitest/vitest.mjs run)
```

Adaptar los checks a los archivos modificados y las instrucciones actuales. Informar bloqueos y pruebas omitidas con precisión. No exigir que el lock coincida con nuevos commits antes de que el paso de PR lo actualice.

Para compilar, usar los scripts oficiales según el alcance:

| Comando | Alcance | Docker para compilar |
| --- | --- | --- |
| `./build.sh lareferencia` | Java, Admin UI y Dashboard; Maven descarga los Node configurados | No |
| `./build-java.sh lareferencia` | Sólo Java | No |
| `./build-admin-web.sh` / `./build-dashboard.sh` | Un frontend por separado, con Node en contenedor | Sí |

`build.sh` y `build-java.sh` omiten las pruebas. La compilación completa sin Docker no implica que las pruebas de integración con Testcontainers puedan ejecutarse sin Docker. No instalar Node global ni sustituir estos scripts por comandos ad hoc cuando el usuario solicita el build oficial.

## Commits y PR

1. Revisar los diffs de cada repositorio y crear commits separados con archivos explícitos. Incluir el trabajo funcional y documentación de plataforma antes de ejecutar el comando de PR.
2. Cuando crear o actualizar PR esté autorizado, comprobar autenticación GitHub y ejecutar:

```bash
./githelper pr
```

Este comando exige módulos limpios; en plataforma permite los metadatos pendientes `workspace.ini` y `workspace.lock`, no cambios funcionales sin commit. Comprueba las ramas registradas, detecta módulos modificados frente a main, sube sus ramas y crea o actualiza PR. Captura los HEAD en el lock y prepara el PR coordinador como borrador. No mergea PR.
3. Si aparece un módulo fuera del registro, revisar por qué cambió y agregarlo con `feature add` cuando corresponda; no ocultar el problema regenerando el lock indiscriminadamente.
4. Revisar los títulos y cuerpos finales: problema resuelto, comportamiento y validación. Correlacionar los checks con el último commit enviado. Informar los enlaces y cualquier bloqueo real.

Si el encargo incluye preparar versión, mergear o publicar, leer [Cierre y releases](references/finish-and-release.md). No convertir automáticamente toda feature en una release.

Al terminar, comunicar comportamiento implementado, módulos afectados, pruebas realizadas y estado de commits/PR. Distinguir lo terminado de cualquier acción pendiente.
