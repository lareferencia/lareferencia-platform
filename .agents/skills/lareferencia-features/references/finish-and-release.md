# Cierre coordinado y releases

Aplicar únicamente al alcance solicitado y ya autorizado. Consultar `githelper.md`, los workflows y scripts actuales antes de actuar; sus interfaces pueden evolucionar. No fijar una versión o número de PR histórico.

## Preparar la versión

Con repositorios limpios, en la rama coordinadora:

```bash
./githelper release prepare --bump rc
./githelper pr
```

Elegir el incremento según el pedido y las opciones vigentes. La numeración debe partir de los tags remotos, no de una suposición sobre la siguiente RC. `prepare` actualiza y commitea versiones del reactor activo y metadatos npm, y registra ramas de versión para módulos que lo necesitan. Los legacy conservan su versión independiente; VuFind queda excluido.

Actualizar `CHANGELOG.md` como parte del PR coordinador: mover sólo las entradas incluidas en la release desde `Unreleased` a una sección con la versión preparada y la fecha prevista de publicación; conservar `Unreleased` y las entradas que no se publicarán. Comprobar enlaces a PR y usar esas entradas para las notas de GitHub Release. Si cambia la versión o la fecha antes de publicar, corregir la sección. Este paso es editorial; no asumir que githelper lo realiza automáticamente.

`prepare` no abre PR: ejecutar después `pr`. Puede haber PR de módulos que sólo cambian versión. Revisar el alcance y el diff del lock. Si una rama de versión ya existe, inspeccionar su contenido y registro antes de reintentar; no asumir idempotencia ilimitada ni forzar su eliminación.

## Mergear módulos y cerrar el lock

1. Identificar los PR exactos, sus bases y sus HEAD. Esperar CI correspondiente a los últimos commits, incluidas verificaciones independientes de los módulos afectados.
2. Si mergear está autorizado, mergear primero los PR de módulos. Usar repositorio e identificador explícitos y el SHA esperado cuando la interfaz lo permita.
3. Repetir `release prepare` y `pr` para recoger los commits que realmente quedaron en main después de squash o merge. Dejar que el helper reconozca los módulos mergeados, retire sus registros y alinee sus checkouts. No cambiarlos prematuramente a main a mano.
4. Verificar el estado final:

```bash
./githelper lock verify --merged
./githelper version sync --check
```

El lock debe reflejar los commits finales de main, no los viejos HEAD de PR. Revisar que incluya todos los módulos del manifest y no VuFind.

## Coordinador y publicación

Leer los triggers y labels del workflow actual. En el flujo documentado, asignar exactamente una etiqueta de release compatible con la versión, marcar el coordinador listo y esperar los checks tras la última actualización y etiqueta. Por ejemplo, sustituyendo los identificadores:

```bash
gh pr edit NUMERO --repo lareferencia/lareferencia-platform --add-label release:rc
gh pr ready NUMERO --repo lareferencia/lareferencia-platform
gh pr checks NUMERO --repo lareferencia/lareferencia-platform --watch
```

Mergear el coordinador sólo con CI final satisfactorio y autorización vigente. Githelper no realiza este merge. Después:

- Localizar la ejecución de publicación recién disparada por ese PR y esperar su resultado; no confundirla con un run histórico. Un evento de cierre puede mostrar el SHA del PR aunque publique el merge: correlacionar evento, PR y metadatos.
- Verificar que el tag corresponde al merge coordinador y que la release tiene el estado correcto, incluido prerelease para una RC.
- Comprobar ZIP, `SHA256SUMS`, `release.json` y lock publicado; contrastar sus commits y sumas, no sólo la existencia de archivos.
- Si se solicita instalación reproducible, clonar el tag público en una carpeta nueva, ejecutar `./githelper init`, verificar lock y versiones, y compilar con el comando documentado. Separar evidencia de compilación y evidencia de pruebas.
- Sincronizar el workspace local sólo conservando trabajo previo. No eliminar backups o stashes del usuario como limpieza incidental.

## Reemplazar una RC publicada

Es excepcional: la ruta normal crea la siguiente versión. Reemplazar una RC existente exige que el usuario lo haya pedido explícitamente; no pedir de nuevo si esa autorización ya está presente.

Antes de modificar el tag o la release pública, respaldar el SHA antiguo y sus metadatos/assets y revisar las garantías del script actual. El workflow manual documentado recibe `pr`, `replace_version` y `expected_tag_sha`. Verificar que el PR está mergeado, la versión coincide con los archivos comprometidos y el SHA antiguo coincide exactamente.

Preparar y verificar los assets en una release borrador antes del reemplazo destructivo. Para encontrar borradores utilizar listado/ID: la consulta pública por tag puede devolver 404 si todavía no existe el tag. Ante un fallo, inspeccionar borrador y destino antes de reintentar. Conservar la publicación anterior si el intercambio no comenzó y usar los respaldos verificados para recuperar un intercambio parcial. No sobrescribir tags ni borrar releases ajenas por aproximación.
