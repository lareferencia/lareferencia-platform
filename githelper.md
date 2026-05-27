# githelper

CLI unificado para gestionar el repositorio padre y los clones del workspace declarados en `workspace.ini`.

El proyecto ya no usa Git submodules como forma de trabajo diaria. Cada modulo vive en la raiz como un clone Git independiente, con el mismo nombre de directorio que antes.

## Ejecucion

Desde la raiz del repo:

```bash
./githelper --help
```

Opcionalmente puedes agregarlo al `PATH`.

## Manifest

`workspace.ini` es la fuente de verdad para los repos del workspace:

```ini
[workspace]
default_branch = main

[module.lareferencia-core-lib]
url = https://github.com/lareferencia/lareferencia-core-lib
branch = main

[profile.v5-semantic-indexing]
lareferencia-core-lib = v5-semantic-indexing
lareferencia-entity-lib = v5-semantic-indexing
```

- `default_branch` se usa cuando un modulo no declara `branch`.
- Cada `[module.<name>]` declara `url` y opcionalmente `branch`.
- Cada `[profile.<branch>]` articula ramas por modulo para una rama del repo padre.
- Si no existe un perfil para la rama del padre, los modulos usan su `branch` o `main`.

## Comandos

### 1) Estado general

```bash
./githelper status
./githelper status --modules lareferencia-core-lib,lareferencia-shell
./githelper status --dirty
```

Muestra `parent|branch|sha|state` y para cada modulo `module|branch|sha|state`.

Estados de cambios:
- `clean`: sin cambios locales.
- `dirty:N`: hay `N` entradas en `git status --porcelain`.
- `status?`: no se pudo leer el estado.

Estados posibles:
- `MISSING`: no existe el path del modulo en disco.
- `UNINITIALIZED`: existe el path pero no es repo Git inicializado.
- `DETACHED`: repo inicializado en detached HEAD.

Con `--dirty`, muestra solo el padre y/o modulos con cambios locales.

### 2) Inicializar clones faltantes

```bash
./githelper init
./githelper init --modules lareferencia-core-lib,lareferencia-shell
./githelper init --branch v5-semantic-indexing
```

Clona los repos declarados en `workspace.ini` que no existan localmente. Por defecto usa la rama del modulo; con `--branch` usa el perfil correspondiente si existe.

### 3) Cambiar branch en el padre y aplicar perfil

```bash
./githelper switch <branch>
./githelper switch <branch> --modules lareferencia-core-lib,lareferencia-shell
```

Flujo:
1. Cambia el repo padre a `<branch>`.
2. Busca `[profile.<branch>]` en `workspace.ini`.
3. Cada modulo listado en el perfil cambia a la rama indicada.
4. Los modulos no listados usan su branch por defecto, normalmente `main`.

Si una rama requerida por el manifest/perfil no existe localmente ni en `origin`, el comando reporta error.

### 4) Sincronizar modulos

```bash
./githelper sync
./githelper sync --branch <profile>
./githelper sync --modules lareferencia-core-lib,lareferencia-shell
```

Sin `--branch`, usa la branch actual del padre como nombre de perfil. Si no existe perfil, aplica defaults.

### 5) Pull integrado

```bash
./githelper pull
./githelper pull --branch <branch>
./githelper pull --modules lareferencia-core-lib,lareferencia-shell
```

Hace `pull` del padre y luego de cada modulo en su rama objetivo segun `workspace.ini`.

### 6) Crear branch en modulos especificos

```bash
./githelper branch create --modules lareferencia-core-lib,lareferencia-shell
./githelper branch create --modules lareferencia-core-lib --branch feature/x
```

Sin `--branch`, usa el nombre de la branch actual del padre. Este comando no modifica `workspace.ini`; los perfiles se mantienen manualmente.

### 7) Convertir URLs SSH/HTTPS

```bash
./githelper url rewrite --to https --dry-run
./githelper url rewrite --to https
./githelper url rewrite --to ssh --modules lareferencia-core-lib,lareferencia-shell
```

Este comando actualiza:
- `origin` del repo padre.
- URLs de modulos en `workspace.ini`.
- `origin` en clones existentes en disco.

### 8) Migrar desde submodules

```bash
./githelper migrate from-submodules --in-place --dry-run
./githelper migrate from-submodules --in-place
```

Preflight:
- el repo padre debe estar limpio;
- `.gitmodules` debe existir;
- cada modulo debe tener `.git` como archivo `gitdir: ../.git/modules/<modulo>`;
- cada gitdir referenciado debe existir.

La migracion mueve cada gitdir a `<modulo>/.git`, quita `core.worktree`, elimina los gitlinks del indice del padre, borra `.gitmodules` y limpia las entradas `submodule.*` de `.git/config`.

## Manejo de cambios locales al crear branch

Cuando ejecutas `branch create`, si un modulo tiene cambios sin commit, `githelper` pregunta para ese modulo:

- `[l]` llevar cambios a la nueva branch.
- `[d]` dejar cambios en la branch actual.

Si eliges `[d]`, se crea la branch objetivo si hace falta, pero no se cambia de branch en ese modulo.

## Seleccion de modulos

`--modules` acepta lista separada por comas:

```bash
--modules lareferencia-core-lib,lareferencia-shell,lareferencia-entity-lib
```

Si no se indica `--modules`, se usan todos los modulos de `workspace.ini`.

## Recomendaciones de uso diario

1. Inicializar workspace:

```bash
./githelper init
```

2. Cambiar branch de trabajo y aplicar perfil:

```bash
./githelper switch feature/x
```

3. Traer cambios de todo el workspace:

```bash
./githelper pull
```

4. Crear la misma branch del padre en modulos puntuales:

```bash
./githelper branch create --modules lareferencia-core-lib,lareferencia-shell
```
