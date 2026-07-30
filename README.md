# LA Referencia Platform 4.2.7

Plataforma de cosecha, transformación, validación y publicación de metadatos de LA Referencia.

## Requisitos

- OpenJDK 11
- Maven 3.8 o posterior
- PostgreSQL 12 o posterior
- Git 2.30 o posterior
- Python 3.8 o posterior, para `githelper`

La configuración Maven incluida redirige la URL obsoleta del repositorio
Restlet, usada por el grafo de dependencias de Solr 8, a su endpoint actual.

## Workspace multi-repositorio

A partir de 4.2.7 el proyecto ya no usa submódulos Git. Cada módulo se descarga como un repositorio independiente según `workspace.ini`.

La release fija cada módulo a la tag `4.2.7` y al SHA exacto publicado en el manifiesto.

```bash
git clone https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform
git checkout 4.2.7

./githelper init
./githelper status
./build.sh lareferencia
```

Para restaurar todos los módulos a las tags y commits declarados:

```bash
./githelper sync
```

Los módulos fijados a tags permanecen en detached HEAD de forma intencionada. `githelper pull` no avanza una release fijada: verifica la tag y el SHA configurados.

Consulta `githelper.md` para la referencia completa del CLI.

## Actualización desde 4.2.6

Después de cambiar el repositorio padre a 4.2.7, ejecuta:

```bash
./githelper migrate from-submodules --in-place
./githelper sync
```

El primer comando convierte worktrees de submódulos ya inicializados en repositorios independientes. En una instalación nueva basta con `./githelper init`.

## Licencia

GNU Affero General Public License v3. Consulta `LICENSE.txt`.
