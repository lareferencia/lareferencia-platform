# Docker Development Environment / Entorno Docker / Ambiente Docker

Choose your language: [English](#english) | [Español](#español) | [Português](#português)

---

## English

This environment sets up the platform from the repository root using `docker-compose.yml` and `Docker/docker.sh`.

### 🚀 Key Features (v5.0)

**1. Maven Build Profiles**
Choose business logic by editing `Docker/.env`:
- `LR_BUILD_PROFILE=lareferencia` (Default)
- `LR_BUILD_PROFILE=ibict` (Includes DARK/PID worker)
- `LR_BUILD_PROFILE=rcaap` (Includes RCAAP specific logic)

**2. Flexible Config Overrides**
Use `Docker/config-overrides/` to inject beans/properties without modifying source code:
- **Properties**: `Docker/config-overrides/{module}/99-docker.properties` overrides defaults.
- **Custom Beans**: Place XMLs in `Docker/config-overrides/{module}/beans/` and reference them in properties.
- **Recursive Sync**: Folders are merged into `/tmp/lr-config/` at runtime.

**3. Running Multiple Instances**
You can run multiple isolated instances on the same server by configuring:
- `SERVICE_PREFIX`: Sets a prefix for container, network, and volume names (e.g., `inst1_`).
- `SERVICES_PORT_OFFSET`: Adds an offset to all external ports (e.g., `100` moves Harvester to `8190`) to avoid conflicts.

### ⚡ Quick Start

```bash
# 1) Initialize Java submodules
./githelper pull

# 2) Build and start
./Docker/docker.sh up --build
```

---

## Español

Este entorno levanta la plataforma desde la raíz del repositorio usando `docker-compose.yml` y `Docker/docker.sh`.

### 🚀 Características Clave (v5.0)

**1. Perfiles de Build Maven**
Seleccione la lógica de negocio editando `Docker/.env`:
- `LR_BUILD_PROFILE=lareferencia` (Por defecto)
- `LR_BUILD_PROFILE=ibict` (Incluye worker DARK/PID)
- `LR_BUILD_PROFILE=rcaap` (Incluye lógica específica de RCAAP)

**2. Sobrescritura Flexible de Configuración**
Use `Docker/config-overrides/` para inyectar beans o propiedades sin modificar el código fuente:
- **Propiedades**: `Docker/config-overrides/{module}/99-docker.properties` tiene prioridad.
- **Beans Personalizados**: Coloque sus XML en `Docker/config-overrides/{module}/beans/` y nómbrelos en sus propiedades.
- **Sincronización Recursiva**: Las carpetas se mezclan en `/tmp/lr-config/` durante la ejecución.

**3. Ejecución de Múltiples Instancias**
Puede ejecutar múltiples instancias aisladas en el mismo servidor configurando:
- `SERVICE_PREFIX`: Establece un prefijo para los nombres de contenedores, redes y volúmenes (ej: `inst1_`).
- `SERVICES_PORT_OFFSET`: Agrega un desplazamiento a todos los puertos externos (ej: `100` mueve Harvester a `8190`) para evitar conflictos.

### ⚡ Inicio Rápido

```bash
# 1) Inicializar submódulos Java
./githelper pull

# 2) Construir y arrancar
./Docker/docker.sh up --build
```

---

## Português

Este ambiente levanta a plataforma a partir da raiz do repositório usando `docker-compose.yml` e `Docker/docker.sh`.

### 🚀 Novidades e Recursos (v5.0)

**1. Perfis de Build Maven**
Escolha a lógica de negócio editando o arquivo `Docker/.env`:
- `LR_BUILD_PROFILE=lareferencia` (Padrão)
- `LR_BUILD_PROFILE=ibict` (Inclui o worker DARK/PID)
- `LR_BUILD_PROFILE=rcaap` (Inclui lógica específica da RCAAP)

**2. Sobrescritas de Configuração Flexíveis**
Use o diretório `Docker/config-overrides/` para injetar beans ou propriedades sem modificar o código-fonte:
- **Propriedades**: O arquivo `Docker/config-overrides/{module}/99-docker.properties` sobrescreve os padrões.
- **Beans Customizados**: Coloque seus arquivos XML em `Docker/config-overrides/{module}/beans/` e referencie-os nas suas propriedades.
- **Sincronização Recursiva**: As pastas são mescladas em `/tmp/lr-config/` durante a execução.

**3. Execução de Múltiplas Instâncias**
Você pode rodar múltiplas instâncias isoladas no mesmo servidor configurando:
- `SERVICE_PREFIX`: Define um prefixo para os nomes de containers, redes e volumes (ex: `inst1_`).
- `SERVICES_PORT_OFFSET`: Adiciona um deslocamento a todas as portas externas (ex: `100` move o Harvester para `8190`) para evitar conflitos.

### ⚡ Início Rápido

```bash
# 1) Inicializar submódulos Java
./githelper pull

# 2) Construir e subir o ambiente
./Docker/docker.sh up --build
```

---

## 🛠️ Main Commands / Comandos

```bash
./Docker/docker.sh modules status      # Show active modules
./Docker/docker.sh up                  # Start services
./Docker/docker.sh down                # Stop and remove containers
./Docker/docker.sh logs [svc]          # View logs
./Docker/docker.sh reset-data          # Clean Docker/data (preserving .gitkeep)
./Docker/docker.sh init-db             # Run database migrations
```

## 🌐 Endpoints

- VuFind: `http://localhost:8080`
- Harvester: `http://localhost:8090`
- Dashboard REST: `http://localhost:8092`
- Solr Admin: `http://localhost:8983/solr`
