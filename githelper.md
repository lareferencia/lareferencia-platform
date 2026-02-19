# githelper

CLI unificado para gestionar ramas y `pull` del repositorio padre y sus submodules.

## Ejecucion

Desde la raiz del repo:

```bash
./githelper --help
```

Opcionalmente puedes agregarlo al `PATH`.

## Comandos

### 1) Estado general

```bash
./githelper status
./githelper status --modules module-a,module-b
```

Muestra: `parent|branch|sha` y para cada submodule: `module|branch|sha`.

### 2) Cambiar branch en el padre y sincronizar submodules

```bash
./githelper switch <branch>
./githelper switch <branch> --modules module-a,module-b
```

Regla en submodules:
- Si el submodule tiene esa branch (local o `origin/<branch>`), cambia a esa branch.
- Si no la tiene, se queda donde esta.

### 3) Sincronizar submodules con una branch objetivo

```bash
./githelper sync
./githelper sync --branch <branch>
./githelper sync --modules module-a,module-b
```

- Sin `--branch`, usa la branch actual del padre.
- Aplica la misma regla: cambiar solo si existe la branch en ese submodule.

### 4) Pull integrado (padre + submodules)

```bash
./githelper pull
./githelper pull --modules module-a,module-b
```

Flujo:
1. Hace `pull` del repositorio padre en su branch actual.
2. Para cada submodule:
- Si existe la branch del padre, cambia a esa branch y hace `pull`.
- Si no existe la branch del padre, hace `pull` de la branch actual del submodule.
- Si esta en `detached HEAD` y no hay branch del padre, hace `fetch` y reporta `SKIP`.

### 5) Crear branch en modulos especificos

```bash
./githelper branch create --modules module-a,module-b
./githelper branch create --modules module-a --branch feature/x
```

- Sin `--branch`, usa el nombre de la branch actual del padre.
- Opera modulo por modulo.

### 6) Convertir URLs de submodules (SSH/HTTPS)

```bash
# Vista previa de conversion SSH -> HTTPS en todos los submodules
./githelper url rewrite --to https --dry-run

# Aplicar conversion SSH -> HTTPS en todos los submodules
./githelper url rewrite --to https

# Aplicar solo en algunos modulos
./githelper url rewrite --to https --modules module-a,module-b
```

Este comando:
- actualiza `origin` del repo padre
- actualiza `submodule.<name>.url` en `.gitmodules`
- actualiza `submodule.<name>.url` en `.git/config` del repo padre
- actualiza `origin` en submodules existentes en disco
- ejecuta `git submodule sync --recursive` al final (cuando no es `--dry-run`)

## Manejo de cambios locales al crear branch

Cuando ejecutas `branch create`, si un modulo tiene cambios sin commit, `githelper` pregunta **para ese modulo**:

- `[l]` llevar cambios a la nueva branch.
- `[d]` dejar cambios en la branch actual.

Si eliges `[d]`:
- Se crea la branch objetivo (si no existe) pero **no** se cambia de branch en ese modulo.
- Los cambios quedan en la branch actual del modulo.

Si eliges `[l]`:
- Se cambia/crea la branch objetivo normalmente.
- Los cambios pasan a esa branch.

## Seleccion de modulos

`--modules` acepta lista separada por comas:

```bash
--modules module-a,module-b,module-c
```

Si no se indica `--modules` en comandos que lo permiten, se usan todos los submodules de `.gitmodules`.

## Errores y salida

- El comando devuelve codigo `0` si no hay errores.
- Devuelve codigo distinto de `0` si hay fallos en algun modulo o en el padre.
- Mensajes:
  - `OK` operacion exitosa
  - `SKIP` modulo omitido por regla de branch
  - `WARN` problema no bloqueante por modulo
  - `ERROR` fallo bloqueante

## Recomendaciones de uso diario

1. Cambiar branch de trabajo:

```bash
./githelper switch feature/x
```

2. Traer cambios de todo el workspace:

```bash
./githelper pull
```

3. Crear la misma branch del padre en modulos puntuales:

```bash
./githelper branch create --modules module-a,module-b
```
