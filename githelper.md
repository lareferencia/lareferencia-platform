# githelper: instalación, desarrollo y releases

La plataforma reúne repositorios independientes. `workspace.ini` declara cuáles
son y sus ramas de desarrollo; `workspace.lock` fija los commits exactos que se
compilan juntos. VuFind es externo. Los dos módulos contrib legacy conservan su
versión independiente y no reciben cambios de numeración.

## Descargar una versión y compilar

Para descargar una versión publicada:

```bash
git clone --branch 5.0.0-rc4 https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform
./githelper init
./build.sh lareferencia
```

`init` descarga exactamente los commits del lock de esa versión. Los POM y los
archivos npm ya tienen la versión correcta en Git: no hay que ejecutar un stamp,
ni editar versiones ni usar obligatoriamente nuestros scripts de build.

```bash
mvn clean install -Plareferencia       # alternativa directa; ejecuta tests
./build-java.sh lareferencia           # solo Java, omite tests
mvn clean verify -Plareferencia        # suite completa; requiere Docker
```

Requisitos: Python 3.9+, Git, JDK 17+ y Maven 3.9. Maven descarga las versiones de
Node necesarias para los frontends. Las integraciones usan Docker; la prueba
opcional contra PostgreSQL se activa con `-Dindexing.test.jdbc-url=...`. El script
`build.sh` usa Maven y omite tests. Los ZIP de release incluyen fuentes preparadas,
JAR y frontends compilados; se pueden compilar sin ejecutar githelper porque los
módulos ya están incluidos. El ZIP automático de GitHub «Source code» contiene
solo el repositorio padre: para preparar módulos hay que usar un clon Git.

Para cambiar un workspace existente a otra versión:

```bash
./githelper switch 5.0.0-rc5
```

Se comprueban los cambios locales antes de cambiar el padre. Un tag deja los
repositorios en detached HEAD; es normal para una instalación congelada. Si una
descarga falla, corrige la conexión y repite `init`; no se borran cambios locales.
Las versiones históricas sin lock conservan su mecanismo de instalación anterior.

## Desarrollar una feature

Prepara primero el workspace con `init`, luego crea ramas desde los main remotos:

```bash
./githelper feature start mejora-cosecha \
  --modules lareferencia-core-lib,lareferencia-lrharvester-app
```

El nombre se normaliza a `codex/mejora-cosecha`. Se crean las ramas del padre y
los módulos seleccionados desde `origin/main`, después de hacer fetch y comprobar
limpieza y ausencia de ramas con ese nombre. La relación se guarda como branch-set
en `workspace.ini`. Los módulos no seleccionados conservan su checkout congelado;
empieza desde un workspace alineado con `init`.

Para incorporar otro módulo:

```bash
./githelper feature add lareferencia-oai-pmh
```

Crea la misma rama desde su main remoto y actualiza el branch-set. Los cambios
funcionales se commitean normalmente en cada repositorio. No hay commits automáticos
de código funcional.

Para recuperar el desarrollo en otra máquina:

```bash
./githelper switch codex/mejora-cosecha
```

En una rama con branch-set, `init` prepara las ramas registradas y congela los demás
módulos según el lock. `init --dev` permite la inicialización tradicional por ramas
del manifest si no hay branch-set. `init --modules nombre,...` limita los módulos.
`sync` y `pull` son operaciones explícitas de desarrollo por ramas, no operaciones
para reproducir una release. `pull` puede avanzar las ramas; usa `init` para volver
a una combinación congelada limpia.

## Crear o actualizar los PR

Requiere GitHub CLI (`gh`) autenticado con `gh auth login`. La instalación y la
compilación no requieren gh.

```bash
./githelper pr
```

Antes de publicar nada comprueba que los módulos estén limpios y que las ramas
sean las registradas. Rechaza modificaciones en módulos fuera de la feature.
Compara las ramas registradas con main y solo abre PR para las que tienen cambios.
Hace push sin force y reutiliza los PR abiertos. Actualiza el lock y commitea
únicamente `workspace.ini` y `workspace.lock` si cambiaron; las demás modificaciones
del padre deben estar commiteadas previamente. Crea o actualiza un PR coordinador
en borrador con enlaces a los módulos. No mergea los PR.

Si un push o GitHub falla a mitad, los PR ya creados se conservan; se puede repetir
el comando para completar la operación.

## Preparar y publicar una release

Desde la rama coordinadora, con los repositorios limpios:

```bash
./githelper release prepare --bump rc
./githelper pr
```

`prepare` consulta las tags remotas sin sobrescribir tags locales, calcula la
siguiente versión y prepara cambios mecánicos en los módulos activos: versión
del padre, referencias al padre y metadatos npm. Crea ramas para los módulos que
necesiten esos cambios y no estén en la feature. Commitea solo los archivos de
versión generados y el lock/manifest del coordinador. Requiere gh para consultar
el estado de los PR existentes.

Todos los módulos activos acompañan la versión de la plataforma. Esto puede
producir PR de numeración incluso en módulos sin cambios funcionales.

Después de mergear los PR de módulos, repite los mismos comandos:

```bash
./githelper release prepare --bump rc
./githelper pr
```

Detecta los PR mergeados, incluidos squash/rebase, reemplaza sus entradas por los
commits finales de main y quita esas ramas del branch-set. Conserva los PR aún
pendientes. Las ejecuciones repetidas no generan nuevos commits si nada cambió.
Ante una rama de numeración antigua que colisione, informa el error para revisarla;
no la resetea. Los fallos de Git no se revierten automáticamente: inspecciona
`githelper status` antes de reintentar si hubo una operación interrumpida.

Cuando todos estén mergeados, añade la etiqueta correspondiente al coordinador,
verifica CI, marca el PR listo y mergea:

| Preparación | Etiqueta | Ejemplo |
|---|---|---|
| `--bump rc` | `release:rc` | 5.0.0-rc3 → 5.0.0-rc4 |
| `--bump stable` | `release:stable` | 5.0.0-rc4 → 5.0.0 |
| `--bump patch` | `release:patch` | 5.0.0 → 5.0.1 |
| `--bump minor` | `release:minor` | 5.0.1 → 5.1.0 |
| `--bump major` | `release:major` | 5.1.0 → 6.0.0 |

Solo una etiqueta `release:*`. Mientras la última versión sea candidata se usa
`rc` o `stable`. Si otra publicación ocupa el número preparado, CI falla y hay
que volver a ejecutar prepare. El merge publica la versión escrita en `VERSION`
y en los POM; el workflow no cambia versiones ni crea commits de numeración.

CI prueba herramientas, lock y versiones, descarga otra copia limpia, ejecuta
`githelper init` y compila con Maven. El job de publicación exige que los commits
del lock estén integrados en main, vuelve a comprobar la versión y publica tag,
ZIP, checksum, lock y `release.json`. El tag identifica el merge del coordinador.
Las dependencias externas y timestamps no están congelados: no se promete un ZIP
idéntico byte a byte.

## Comandos de diagnóstico y mantenimiento

```bash
./githelper status
./githelper status --dirty
./githelper lock verify
./githelper lock verify --merged
./githelper version sync --check
```

El lock debe incluir todos los repos del manifest exactamente una vez. Se comprueban
URLs, rutas, SHA completos y limpieza. Los comandos de bajo nivel siguen disponibles:

```bash
./githelper lock capture             # capturar los HEAD limpios actuales
./githelper lock capture --from-main # actualizar desde main sin cambiar checkouts
./githelper lock checkout            # ignorar branch-set y restaurar el lock exacto
./githelper version set 5.0.0-rc4     # editar metadatos, sin commits automáticos
./change-version.sh 5.0.0-rc4        # equivalente compatible
./githelper url rewrite --to https
```

Las dependencias internas están centralizadas en el padre con `${project.version}`.
Los hijos heredan versión, con referencia explícita al padre por compatibilidad
con Maven 3. Las operaciones de versión validan todo el reactor activo antes de
escribir, incluidos frontends; excluyen legacy y VuFind. `release stamp` queda como
herramienta de bajo nivel compatible, fuera del flujo de instalación/publicación.

`lareferencia-metadata-tools` participa en las ramas coordinadas, en el lock y
en las operaciones de versión. El paquete Python usa la representación PEP 440
de la versión de plataforma. Por ejemplo, `5.0.0-rc4` se publica en el wheel
como `5.0.0rc4`, y `5.0.1-SNAPSHOT` se escribe como `5.0.1.dev0`.
Las versiones estables usan los mismos tres componentes en ambos formatos.

Para compilar OAI por separado, instala antes el POM padre correspondiente. Su
Dockerfile recibe el contexto `platform-parent`. Su CI busca el padre ya commiteado
en el tag de la versión, main o un único PR coordinador compatible; nunca inventa
una versión del padre. Si el coordinador aún no se subió, se reintenta el CI del
módulo después de subirlo.

## Configuración y recuperación de GitHub

Protege main con el check `Locked platform integration`, actualizado con la base.
Los workflows crean las etiquetas de release que falten en PR del mismo repositorio
y en pushes a main. Usan `GITHUB_TOKEN`; los módulos actuales son públicos.

La publicación está serializada. No se sobrescriben tags, releases ni assets.
Para reintentar una publicación fallida, usa Re-run jobs o workflow_dispatch con
el número del coordinador mergeado. Un tag ya creado sobre ese commit conserva
su versión. Una release ya publicada se conserva; una draft parcial exige revisión
manual antes de reintentar.

## Reedición explícita de una candidata

El flujo normal no reemplaza releases ni tags. Una reedición excepcional de una
RC ya publicada requiere autorización expresa y un respaldo completo de sus
assets y metadatos, comprobados con SHA-256.

Después de mergear los PR de módulos y el coordinador con CI en verde, ejecutar
manualmente `Coordinator release` con el número de ese PR y estos campos:

- `replace_version`: candidata numerada exacta, por ejemplo `5.0.0-rc4`.
- `expected_tag_sha`: SHA completo al que apunta actualmente ese tag.

La versión debe coincidir con el padre y `VERSION`. Este modo solo admite
candidatas publicadas y mutables, comprueba el SHA anterior, vuelve a ejecutar
las pruebas y sube los nuevos assets a un borrador. Solo después de comprobar
sus tamaños y hashes vuelve a verificar el tag, sustituye la publicación y mueve
el tag al coordinador nuevo. `release.json` conserva `replaces_tag_commit`.
Una interrupción durante el intercambio conserva el borrador nuevo para
inspección y recuperación manual; no se debe iniciar otro intercambio a ciegas.
Dejar ambos campos vacíos mantiene el comportamiento habitual de publicación.
