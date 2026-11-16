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

[module.lareferencia-entity-lib]
url = https://github.com/lareferencia/lareferencia-entity-lib
tag = 4.2.7
commit = 0123456789abcdef0123456789abcdef01234567

[branch-set.v5-semantic-indexing]
lareferencia-core-lib = v5-semantic-indexing
```

- `default_branch` se usa cuando un modulo no declara `branch`.
- Cada `[module.<name>]` declara `url` y uno de estos destinos:
  - `branch`: rama de desarrollo actualizable.
  - `tag`: tag de release, que se mantiene en detached HEAD.
  - `ref = refs/tags/<tag>`: forma equivalente y explicita de declarar una tag.
- Un modulo fijado por tag puede declarar `commit` con el SHA Git completo de 40 caracteres. `githelper` verifica que la tag resuelva exactamente a ese commit.
- `branch` y `tag`/`ref` son mutuamente excluyentes.
- Cada `[branch-set.<branch>]` articula ramas por modulo para una rama del repo padre.
- Si no existe un branch-set para la rama del padre, los modulos usan su `branch` o `main`.
- Los modulos fijados por tag no son modificados por los branch sets.
- Los profiles Maven (`lareferencia`, `ibict`, `rcaap`) son independientes de los branch sets de `githelper`.

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
./githelper init --modules lareferencia-oai-pmh
./githelper init --set v5-semantic-indexing
```

Clona los repos declarados en `workspace.ini` que no existan localmente. Por defecto usa la rama o tag del modulo; con `--set` usa el branch-set correspondiente para los modulos basados en ramas. Las tags quedan en detached HEAD y se verifica `commit` cuando esta declarado.

### 3) Cambiar branch en el padre y aplicar branch-set

```bash
./githelper switch <branch>
./githelper switch <branch> --modules lareferencia-core-lib,lareferencia-shell
```

Flujo:
1. Cambia el repo padre a `<branch>`.
2. Busca `[branch-set.<branch>]` en `workspace.ini`.
3. Cada modulo listado en el branch-set cambia a la rama indicada.
4. Los modulos no listados usan su branch por defecto, normalmente `main`.

Si una rama requerida por el manifest/branch-set no existe localmente ni en `origin`, el comando reporta error.

### 4) Sincronizar modulos

```bash
./githelper sync
./githelper sync --set <branch-set>
./githelper sync --modules lareferencia-core-lib,lareferencia-shell
```

Sin `--set`, usa la branch actual del padre como nombre de branch-set. Si no existe branch-set, aplica defaults. Los modulos fijados por tag se cambian a esa tag y se verifica su commit. Si todos los modulos seleccionados usan tags, tambien funciona cuando el repositorio padre esta en detached HEAD.

### 5) Guardar un mapa de ramas del workspace

```bash
./githelper branch-set capture semantic-demo
./githelper branch-set capture semantic-demo --modules lareferencia-core-lib,lareferencia-shell
./githelper branch-set capture semantic-demo --force
```

Lee la branch actual de cada modulo seleccionado y escribe un `[branch-set.semantic-demo]` en `workspace.ini`.
Ese branch-set se puede reproducir despues con:

```bash
./githelper sync --set semantic-demo
```

Si el branch-set ya existe, el comando falla salvo que uses `--force`. Los modulos con cambios locales se pueden capturar igual; los modulos `MISSING`, `UNINITIALIZED` o `DETACHED` hacen fallar la captura porque no hay una branch reproducible.

### 6) Pull integrado

```bash
./githelper pull
./githelper pull --branch <branch>
./githelper pull --modules lareferencia-core-lib,lareferencia-shell
```

Hace `pull` del padre y luego de cada modulo en su rama objetivo segun `workspace.ini`. Para modulos fijados por tag no ejecuta `pull`: descarga tags, verifica el commit y restaura el detached HEAD esperado.

### 7) Crear branch en modulos especificos

```bash
./githelper branch create --modules lareferencia-core-lib,lareferencia-shell
./githelper branch create --modules lareferencia-core-lib --branch feature/x
```

Sin `--branch`, usa el nombre de la branch actual del padre. Este comando no modifica `workspace.ini`; los branch sets se pueden editar manualmente o generar con `branch-set capture`.

### 8) Convertir URLs SSH/HTTPS

```bash
./githelper url rewrite --to https --dry-run
./githelper url rewrite --to https
./githelper url rewrite --to ssh --modules lareferencia-core-lib,lareferencia-shell
```

Este comando actualiza:
- `origin` del repo padre.
- URLs de modulos en `workspace.ini`.
- `origin` en clones existentes en disco.

## Crear ramas desde main

`branch create` descarga `origin` y crea las ramas desde `origin/main`, aunque
el módulo esté actualmente en otra rama. `--base` permite otra base explícita.
Rechaza clones sucios y ramas que ya existen; nunca las reutiliza silenciosamente.
Comprueba todos los repos antes de crear la primera rama. Ante un error de Git
durante la creación, informa el fallo; las ramas ya creadas permanecen disponibles.

Para crear también la rama del padre y registrar el branch-set automáticamente:

```bash
./githelper feature start codex/123-descripcion \
  --modules lareferencia-core-lib,lareferencia-lrharvester-app
```

El padre y los módulos seleccionados deben estar limpios. El branch-set generado
se debe commitear en el padre. Los módulos no seleccionados conservan su checkout;
`sync` aplica posteriormente sus defaults si necesitas normalizar todo el workspace.

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

2. Cambiar branch de trabajo y aplicar branch-set:

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

## Versión común de los módulos activos

Los 12 módulos Maven activos heredan su versión de `lareferencia-parent`. Sus POM
no declaran una versión de proyecto propia. El padre centraliza las versiones de
las dependencias internas en `dependencyManagement` mediante `${project.version}`.
La referencia `<parent><version>` sigue siendo explícita, como requiere Maven 3,
y se actualiza junto con la versión del padre.

Los POM de Admin Web y Repository Dashboard heredan también del padre. Antes de
`npm ci`, Maven sincroniza `package.json` y `package-lock.json` con su versión
heredada, sin crear commits ni tags npm. En el código fuente ambas aplicaciones
usan la misma versión que la plataforma.

```bash
./githelper version sync --check  # comprobar herencia, dependencias y versiones npm
./githelper version sync          # alinear referencias al padre y metadatos npm
./githelper version set 5.0.0-rc4 # cambiar la versión común
./change-version.sh 5.0.0-rc4     # misma operación, interfaz compatible
```

Estas operaciones recorren los módulos activos del reactor, incluidos los
frontends. Validan todos los POM antes de escribir. No modifican `contrib-ibict`,
`contrib-rcaap`, otros proyectos fuera del reactor ni VuFind. Los módulos legacy
conservan sus versiones y sus dependencias explícitas. Las referencias internas
a ellos en perfiles legacy conservan también la versión original.

Para compilar OAI-PMH fuera del reactor hay que instalar primero el POM padre de
la plataforma. Su CI realiza ese paso; su Dockerfile recibe el POM como contexto
adicional `platform-parent`. El runtime del proveedor sigue siendo independiente.

## Lock de módulos

`workspace.lock` es JSON versionado con esquema 1 y, para cada módulo del manifest,
nombre, path, URL y SHA completo de los 15 módulos LA Referencia. VuFind es una
aplicación externa: su checkout local se administra por separado y no forma parte
del manifest, el lock, los metadatos ni el ZIP de la release. Los módulos con tag
deben coincidir con esa tag; los demás deben pertenecer a `origin/main` al publicar.

```bash
# Capturar los HEAD actuales: exige todos los módulos limpios.
./githelper lock capture

# Capturar los main remotos y las tags fijadas sin cambiar ningún checkout local.
# Es el comando habitual después de mergear los PR de los módulos.
./githelper lock capture --from-main

# Clonar lo que falte y restaurar exactamente el lock en detached HEAD.
./githelper lock checkout

# Verificar SHA y limpieza; no cambia de rama.
./githelper lock verify

# Además exige que todos los commits estén integrados en main
# (o coincidan con la tag fijada, para módulos upstream).
./githelper lock verify --merged
```

`checkout` rechaza clones sucios, remotos distintos del manifest, paths inseguros,
SHA inválidos y locks incompletos. Comprueba los clones existentes antes de cambiar
el primero. No restaura cambios locales ni hace reset. `sync` y `pull` siguen
orientados al desarrollo por ramas; para reproducir una release usa `lock checkout`.

## PR coordinador y releases

1. Crea la feature con `feature start`; desarrolla y abre un PR a `main` por módulo.
2. Abre el PR del padre con el branch-set y un lock de la combinación a probar.
   Sin etiqueta de release se pueden probar SHA todavía no integrados.
3. Mergea los PR de módulos y actualiza el lock con sus SHA finales. Si usaste
   squash o rebase, captura los SHA resultantes, no los anteriores al merge.
4. Añade exactamente una etiqueta de release al PR coordinador y revisa CI.
5. Mergea ese PR: `Coordinator release` verifica el lock, calcula la versión,
   compila, ejecuta tests y publica el tag, ZIP, checksums, lock y `release.json`.

Etiquetas y ejemplos:

| Etiqueta | Antes | Después |
|---|---|---|
| `release:rc` | `5.0.0-rc3` | `5.0.0-rc4` |
| `release:stable` | `5.0.0-rc4` | `5.0.0` |
| `release:patch` | `5.0.0` | `5.0.1` |
| `release:minor` | `5.0.1` | `5.1.0` |
| `release:major` | `5.1.0` | `6.0.0` |

Mientras la última versión sea candidata se exige `rc` o `stable`. La numeración
parte de la mayor tag reconocida y exige que sea ancestro del coordinador. Los
nombres históricos `5.0.0-alpha`, `5.0.0-beta` y `5.0.0-rc` no numerados se ignoran.

Puedes previsualizar localmente después de descargar las tags:

```bash
git fetch origin --tags
./githelper release plan --bump rc
```

La previsión de un PR puede aumentar si otra release se publica antes de su merge.
La versión definitiva se asigna durante la publicación serializada. La cola de
GitHub conserva hasta 100 ejecuciones pendientes. Si hay una publicación fuera del
orden de commits, falla por ancestry en vez de etiquetar una regresión.

### Versiones de compilación y reproducibilidad

La tag apunta exactamente al commit mergeado del coordinador. Los SHA del lock
identifican las fuentes originales de los módulos. Para no generar commits de
numeración en todos los repos, CI aplica una transformación explícita y determinista:

```bash
./githelper release stamp 5.0.0-rc4
```

Este comando cambia la versión del padre, las referencias al padre de los 12
módulos activos y los metadatos npm, y genera `VERSION`. Las dependencias internas
reciben esa versión por `dependencyManagement`; no se añaden versiones propias
a los hijos. No cambia los módulos legacy ni las dependencias externas. Es una operación de build: úsala en un clon
limpio o temporal. Después del stamp el lock sigue identificando los commits de
origen, pero `lock verify` rechazará los cambios de compilación hasta que vuelvas
a un workspace limpio.

El ZIP incluye estas fuentes con versiones aplicadas, los cuatro JAR desplegables
y los dos frontends compilados, sin caches ni configuraciones locales ignoradas.
`release.json` registra la versión, el PR, el commit coordinador, los SHA de módulos
y el comando de transformación. El checksum corresponde al ZIP.

Para reconstruir desde Git en un directorio nuevo:

```bash
git clone https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform
git checkout 5.0.0-rc4
./githelper lock checkout
./githelper lock verify --merged
./githelper release stamp 5.0.0-rc4
mvn --batch-mode clean verify -Plareferencia
```

Las fuentes quedan fijadas; dependencias de registros externos y timestamps del
build no están congelados, por lo que no se promete un ZIP idéntico byte a byte.

### Configuración inicial en GitHub

El workflow crea automáticamente las cinco etiquetas `release:*` que falten en los
PR abiertos desde este mismo repositorio y al integrar cambios en `main`; conserva
las etiquetas ya existentes. Protege `main` exigiendo el check
`Locked platform integration` actualizado con la base antes de mergear. Protege
las tags numeradas contra cambios y activa releases inmutables si están disponibles.
Los workflows usan `GITHUB_TOKEN`, sin la clave SSH personal que usaba el flujo
anterior. Los módulos declarados actualmente son públicos; para módulos privados
haría falta configurar credenciales de lectura limitadas a esos repositorios.

`Platform CI` nunca publica. `Coordinator release` publica solo PR mergeados con
una etiqueta de release. Las candidatas se marcan como prerelease en GitHub.
No se borran ni reemplazan tags, releases o assets existentes. Se crea una draft,
se adjuntan assets y después se publica. Una draft parcial requiere inspección
manual antes de reintentar; una release ya publicada se conserva intacta.

Para recuperar una ejecución fallida, usa **Re-run jobs** o `workflow_dispatch` del
workflow `Coordinator release` indicando el número del PR ya mergeado. Si una tag
ya fue creada sobre ese commit, se reutiliza su versión, sin asignar otra. Si se
publicaron versiones posteriores sobre commits descendientes, no se numera el
commit antiguo como si fuera una nueva release.

Los jobs de CI y release levantan además un PostgreSQL 15 efímero y pasan
`indexing.test.jdbc-url` a Maven. Esto activa las pruebas optativas de concurrencia
y persistencia de resultados de indexación y las consultas operativas de tags.
La contraseña `indexing-test` pertenece exclusivamente a esa base desechable;
no se conecta a ninguna base de producción. Las demás integraciones usan sus
propios contenedores de Testcontainers. Se requiere Docker disponible; la versión
de Testcontainers está fijada en 1.21.4 para admitir Docker 29.
