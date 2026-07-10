#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve ROOT_DIR more robustly
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Debug paths if needed
# echo "DEBUG: SCRIPT_DIR=${SCRIPT_DIR}"
# echo "DEBUG: ROOT_DIR=${ROOT_DIR}"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
DATA_DIR="${ROOT_DIR}/Docker/data"
VOLUME_DIR="${ROOT_DIR}/Docker/volume"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

# Ensure vufind directory exists as soon as possible (non-versioned component)
if [ ! -d "${ROOT_DIR}/vufind" ]; then
  mkdir -p "${ROOT_DIR}/vufind"
fi

DEFAULT_VUFIND_REPO_URL="https://github.com/vufind-org/vufind"
DEFAULT_VUFIND_REF="v11.0.1"

ALL_MODULES=(core solr harvester dashboard entity-rest shell vufind elastic watch)
JAVA_PARENT_MODULES=(
  lareferencia-oclc-harvester
  lareferencia-core-lib
  lareferencia-entity-lib
  lareferencia-indexing-filters-lib
  lareferencia-shell-entity-plugin
  lareferencia-shell
  lareferencia-dark-lib
  lareferencia-lrharvester-app
  lareferencia-entity-rest
  lareferencia-dashboard-rest
)

COLLECTED_SERVICES=()
COLLECTED_PROFILES=()
FILTERED_SERVICES=()

# --- Visual Theme (Flat ANSI) ---
C_RESET=$(printf '\033[0m')
C_BOLD=$(printf '\033[1m')
C_BLUE=$(printf '\033[38;5;75m')    # Soft blue
C_CYAN=$(printf '\033[38;5;80m')    # Flat cyan
C_GREEN=$(printf '\033[38;5;114m')  # Soft green
C_YELLOW=$(printf '\033[38;5;222m') # Flat yellow
C_RED=$(printf '\033[38;5;204m')    # Flat red
C_MAGENTA=$(printf '\033[38;5;176m') # Flat magenta
C_GRAY=$(printf '\033[38;5;245m')   # Gray

# --- Gum Wrapper (Like mvnw) ---

ensure_gum_binary() {
  local bin_dir="${SCRIPT_DIR}/.bin"
  local gum_bin="${bin_dir}/gum"
  local version="0.15.0" # Stable version

  if [ -x "${gum_bin}" ]; then
    printf "%s" "${gum_bin}"
    return 0
  fi

  # Detect OS and Arch
  local os
  case "$(uname -s)" in
    Darwin) os="Darwin" ;;
    Linux)  os="Linux" ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac

  local arch
  case "$(uname -m)" in
    x86_64) arch="x86_64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported Arch: $(uname -m)" >&2; exit 1 ;;
  esac

  # Build download URL (Official GitHub Releases)
  local filename="gum_${version}_${os}_${arch}.tar.gz"
  local url="https://github.com/charmbracelet/gum/releases/download/v${version}/${filename}"

  echo -e "${C_CYAN}Downloading gum wrapper v${version} for ${os}-${arch}...${C_RESET}" >&2
  mkdir -p "${bin_dir}"
  
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required to download the gum wrapper." >&2; exit 1
  fi

  if ! curl -sSL "${url}" -o "${bin_dir}/${filename}"; then
    echo "Error: Failed to download gum from ${url}" >&2; exit 1
  fi

  # Extract the binary. Most gum releases have the binary inside a folder.
  # We extract everything and move the binary to the root of .bin/
  (
    cd "${bin_dir}"
    tar -xzf "${filename}"
    # Move binary if it's inside a subfolder (standard GitHub release format)
    find . -name "gum" -type f -exec mv {} . \;
    # Clean up any leftover directories or files from the tar
    find . -maxdepth 1 -type d -name "gum_*" -exec rm -rf {} \;
  )
  
  chmod +x "${gum_bin}"
  rm -f "${bin_dir}/${filename}"
  
  printf "%s" "${gum_bin}"
}

gum() {
  local gum_path
  gum_path="$(ensure_gum_binary)"
  "${gum_path}" "$@"
}

# --- Helpers ---

ensure_env_file() {
  if [ ! -f "${ENV_FILE}" ]; then
    if [ -f "${ENV_EXAMPLE}" ]; then
      cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    else
      touch "${ENV_FILE}"
    fi
  fi
}

get_env_var() {
  local key="$1"
  local default_value="$2"
  local value=""

  if [ -f "${ENV_FILE}" ]; then
    local found
    found="$(awk -F= -v k="${key}" '$1 ~ "^[[:space:]]*"k"[[:space:]]*$" {v=$2} END {gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/^"|"$/, "", v); print v}' "${ENV_FILE}" || true)"
    if [ -n "${found}" ]; then
      value="${found}"
    fi
  fi

  if [ -z "${value}" ]; then
    value="${default_value}"
  fi
  printf "%s\n" "${value}"
}

set_env_var() {
  local key="$1"
  local value="$2"
  local file="${3:-$ENV_FILE}"

  ensure_env_file
  
  local tmp_file="${file}.tmp"
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
    sed -E "s|^([[:space:]]*${key}[[:space:]]*=).*$|\1${value}|g" "${file}" > "${tmp_file}"
    mv "${tmp_file}" "${file}"
  else
    printf "%s=%s\n" "${key}" "${value}" >> "${file}"
  fi
}

export_service_prefix() {
  local prefix
  prefix="$(get_env_var SERVICE_PREFIX "")"
  prefix="${prefix//\"/}"
  prefix="${prefix//\'/}"

  if [ -n "${prefix}" ]; then
    export SERVICE_PREFIX="${prefix}"
    local clean_name="${prefix%[_-]}"
    export COMPOSE_PROJECT_NAME="${clean_name//_/-}"
  else
    export COMPOSE_PROJECT_NAME="lareferencia"
    export SERVICE_PREFIX=""
  fi

  set_env_var "SERVICE_PREFIX" "${SERVICE_PREFIX}"
  set_env_var "COMPOSE_PROJECT_NAME" "${COMPOSE_PROJECT_NAME}"
}

export_salted_ports() {
  unset LR_PORT_VUFIND_WEB LR_PORT_VUFIND_DB LR_PORT_SOLR LR_PORT_POSTGRES LR_PORT_HARVESTER LR_PORT_DASHBOARD LR_PORT_ENTITY_REST LR_PORT_ELASTIC_9200 LR_PORT_ELASTIC_9300

  local salt
  salt="$(get_env_var SERVICES_PORT_OFFSET 0)"
  salt="${salt//[^0-9]/}"

  local base_vufind_web=8080
  local base_vufind_db=3307
  local base_solr=8983
  local base_postgres=5432
  local base_harvester=8090
  local base_dashboard=8092
  local base_entity_rest=8094
  local base_elastic_9200=9200
  local base_elastic_9300=9300

  if [ -z "${salt}" ] || [ "${salt}" -eq 0 ]; then
    salt=0
  fi

  export LR_PORT_VUFIND_WEB=$((base_vufind_web + salt))
  export LR_PORT_VUFIND_DB=$((base_vufind_db + salt))
  export LR_PORT_SOLR=$((base_solr + salt))
  export LR_PORT_POSTGRES=$((base_postgres + salt))
  export LR_PORT_HARVESTER=$((base_harvester + salt))
  export LR_PORT_DASHBOARD=$((base_dashboard + salt))
  export LR_PORT_ENTITY_REST=$((base_entity_rest + salt))
  export LR_PORT_ELASTIC_9200=$((base_elastic_9200 + salt))
  export LR_PORT_ELASTIC_9300=$((base_elastic_9300 + salt))

  set_env_var "LR_PORT_VUFIND_WEB" "${LR_PORT_VUFIND_WEB}"
  set_env_var "LR_PORT_VUFIND_DB" "${LR_PORT_VUFIND_DB}"
  set_env_var "LR_PORT_SOLR" "${LR_PORT_SOLR}"
  set_env_var "LR_PORT_POSTGRES" "${LR_PORT_POSTGRES}"
  set_env_var "LR_PORT_HARVESTER" "${LR_PORT_HARVESTER}"
  set_env_var "LR_PORT_DASHBOARD" "${LR_PORT_DASHBOARD}"
  set_env_var "LR_PORT_ENTITY_REST" "${LR_PORT_ENTITY_REST}"
  set_env_var "LR_PORT_ELASTIC_9200" "${LR_PORT_ELASTIC_9200}"
  set_env_var "LR_PORT_ELASTIC_9300" "${LR_PORT_ELASTIC_9300}"
}

sync_compose_profiles() {
  local profiles=()
  
  for module in "${ALL_MODULES[@]}"; do
    if [ "$(get_module_state "${module}")" = "on" ]; then
      case "${module}" in
        core)         profiles+=(core) ;;
        solr)         ;;
        harvester)    profiles+=(harvester) ;;
        dashboard)    profiles+=(dashboard) ;;
        entity-rest)  profiles+=(entity-rest) ;;
        shell)        profiles+=(tools) ;;
        vufind)       profiles+=(vufind) ;;
        elastic)      profiles+=(elastic) ;;
        watch)        profiles+=(watch) ;;
      esac
    fi
  done
  
  local joined
  joined=$(IFS=,; echo "${profiles[*]}")
  export COMPOSE_PROFILES="${joined}"
  set_env_var "COMPOSE_PROFILES" "${joined}"
}

apply_resource_profile() {
  local profile="$1"
  local config_file="${SCRIPT_DIR}/profiles/${profile}.env"
  
  if [ ! -f "${config_file}" ]; then
    echo -e "${C_RED}Error: Profile file ${config_file} not found.${C_RESET}" >&2
    return 1
  fi

  echo -e "${C_CYAN}Applying resource profile: ${profile}...${C_RESET}"
  
  # Read settings from the individual profile file
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    if [[ "$line" == *"="* ]]; then
      local key="${line%%=*}"
      local value="${line#*=}"
      set_env_var "${key}" "${value}"
    fi
  done < "${config_file}"
  
  set_env_var "LR_RESOURCE_PROFILE" "${profile}"
}

dc() {
  ensure_env_file
  export_salted_ports
  export_service_prefix
  sync_compose_profiles
  
  # Lógica para Solr Externo
  local ext_solr
  ext_solr="$(get_env_var SOLR_EXTERNAL_URL "")"
  if [ -n "${ext_solr}" ]; then
    export SOLR_HOST="${ext_solr}"
  fi

  local env_args=()
  if [ -f "${ENV_FILE}" ]; then
    env_args+=(--env-file "${ENV_FILE}")
  fi
  
  docker compose -f "${COMPOSE_FILE}" "${env_args[@]}" "$@"
}

# --- Core Logic ---

contains_item() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    if [ "${item}" = "${needle}" ]; then
      return 0
    fi
  done
  return 1
}

reset_collections() {
  COLLECTED_SERVICES=()
  COLLECTED_PROFILES=()
}

add_collected_service() {
  local service="$1"
  if ! contains_item "${service}" "${COLLECTED_SERVICES[@]-}"; then
    COLLECTED_SERVICES+=("${service}")
  fi
}

add_collected_profile() {
  local profile="$1"
  if ! contains_item "${profile}" "${COLLECTED_PROFILES[@]-}"; then
    COLLECTED_PROFILES+=("${profile}")
  fi
}

normalize_toggle() {
  local value="$1"
  case "$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')" in
    1|true|on|yes) printf "on\n" ;;
    *) printf "off\n" ;;
  esac
}

module_env_key() {
  local module="$1"
  case "${module}" in
    core) printf "DEV_MODULE_CORE\n" ;;
    solr) printf "DEV_MODULE_SOLR\n" ;;
    harvester) printf "DEV_MODULE_HARVESTER\n" ;;
    dashboard) printf "DEV_MODULE_DASHBOARD\n" ;;
    entity-rest) printf "DEV_MODULE_ENTITY_REST\n" ;;
    shell) printf "DEV_MODULE_SHELL\n" ;;
    vufind) printf "DEV_MODULE_VUFIND\n" ;;
    elastic) printf "DEV_MODULE_ELASTIC\n" ;;
    watch) printf "DEV_MODULE_WATCH\n" ;;
    *) return 1 ;;
  esac
}

module_default_state() {
  local module="$1"
  case "${module}" in
    core|solr|harvester|vufind) printf "on\n" ;;
    *) printf "off\n" ;;
  esac
}

validate_module_name() {
  local module="$1"
  local known
  for known in "${ALL_MODULES[@]}"; do
    if [ "${known}" = "${module}" ]; then
      return 0
    fi
  done
  echo -e "${C_RED}Invalid module: ${module}${C_RESET}" >&2
  return 1
}

get_module_state() {
  local module="$1"
  local key
  local default_state
  local raw

  if [ "${module}" = "core" ]; then
    printf "on\n"
    return 0
  fi

  key="$(module_env_key "${module}")"
  default_state="$(module_default_state "${module}")"
  raw="$(get_env_var "${key}" "${default_state}")"
  normalize_toggle "${raw}"
}

set_module_state() {
  local module="$1"
  local state="$2"
  local key

  if [ "${module}" = "core" ] && [ "${state}" = "off" ]; then
    echo "Core module cannot be deactivated." >&2
    return 1
  fi

  key="$(module_env_key "${module}")"
  set_env_var "${key}" "${state}"
}

module_services() {
  local module="$1"
  case "${module}" in
    core)
      printf "postgres\n"
      ;;
    solr)
      if [ -z "$(get_env_var SOLR_EXTERNAL_URL "")" ]; then
        printf "solr\n"
      fi
      ;;
    harvester)
      printf "harvester\n"
      ;;
    dashboard)
      printf "dashboard-rest\n"
      ;;
    entity-rest)
      printf "entity-rest\n"
      ;;
    shell)
      printf "shell\n"
      ;;
    vufind)
      printf "vufind-db vufind-web\n"
      ;;
    elastic)
      printf "elasticsearch\n"
      ;;
    watch)
      printf "vufind-scss-watch\n"
      ;;
    *)
      return 1
      ;;
  esac
}

module_profiles() {
  local module="$1"
  case "${module}" in
    dashboard)
      printf "dashboard\n"
      ;;
    shell)
      printf "tools\n"
      ;;
    elastic)
      printf "elastic\n"
      ;;
    watch)
      printf "watch\n"
      ;;
    *)
      return 0
      ;;
  esac
}

service_requires_vufind() {
  local service="$1"
  case "${service}" in
    vufind-web|vufind-db|vufind-scss-watch)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

collect_from_modules() {
  local module
  local service
  local profile

  reset_collections

  for module in "$@"; do
    validate_module_name "${module}"

    for service in $(module_services "${module}"); do
      add_collected_service "${service}"
    done

    for profile in $(module_profiles "${module}"); do
      if [ -n "${profile}" ]; then
        add_collected_profile "${profile}"
      fi
    done
  done
}

collect_profiles_for_services() {
  local service
  COLLECTED_PROFILES=()
  for service in "$@"; do
    case "${service}" in
      shell)
        add_collected_profile "tools"
        ;;
      elasticsearch)
        add_collected_profile "elastic"
        ;;
      vufind-scss-watch)
        add_collected_profile "watch"
        ;;
    esac
  done
}

enabled_modules() {
  local module
  for module in "${ALL_MODULES[@]}"; do
    if [ "$(get_module_state "${module}")" = "on" ]; then
      printf "%s\n" "${module}"
    fi
  done
}

are_images_built() {
  local services=("$@")
  if [ "${#services[@]}" -eq 0 ]; then
    return 1
  fi

  local missing_image=false
  local checked_any=false
  local s
  for s in "${services[@]}"; do
    case "${s}" in
      harvester|dashboard-rest|entity-rest|shell|solr|vufind-web|vufind-scss-watch)
        checked_any=true
        local img_id
        img_id=$(dc images -q "${s}" 2>/dev/null || true)
        if [ -z "${img_id}" ]; then
          missing_image=true
          break
        fi
        ;;
    esac
  done
  
  if [ "${checked_any}" = true ] && [ "${missing_image}" = false ]; then
    return 0
  fi
  return 1
}

sync_solr_assets_from_vufind() {
  local src_import="${ROOT_DIR}/vufind/import"
  local src_jars="${ROOT_DIR}/vufind/solr/vufind/jars"
  local src_vendor="${ROOT_DIR}/vufind/solr/vendor/modules/analysis-extras/lib"
  local dst_import="${ROOT_DIR}/Docker/solr/import"
  local dst_jars="${ROOT_DIR}/Docker/solr/jars"
  local dst_vendor="${ROOT_DIR}/Docker/solr/vendor"

  echo "Syncing Docker/solr/assets from vufind/..."
  
  rm -rf "${dst_import}" "${dst_jars}" "${dst_vendor}"
  mkdir -p "${dst_import}" "${dst_jars}" "${dst_vendor}"

  if [ -d "${src_import}" ]; then cp -a "${src_import}/." "${dst_import}/"; fi
  if [ -d "${src_jars}" ]; then cp -a "${src_jars}/." "${dst_jars}/"; fi
  if [ -d "${src_vendor}" ]; then 
    cp "${src_vendor}"/icu4j-*.jar "${dst_vendor}/" 2>/dev/null || true
    cp "${src_vendor}"/lucene-analysis-icu-*.jar "${dst_vendor}/" 2>/dev/null || true
  fi

  echo "Sync Solr assets complete."
}

ensure_vufind_checkout() {
  local cloned_vufind=false
  local repo_url
  local repo_ref

  # Check if it's already populated
  if [ -f "${ROOT_DIR}/vufind/composer.json" ]; then
    return 0
  fi

  repo_url="${VUFIND_REPO_URL:-$(get_env_var VUFIND_REPO_URL "${DEFAULT_VUFIND_REPO_URL}")}"
  repo_ref="${VUFIND_REF:-$(get_env_var VUFIND_REF "${DEFAULT_VUFIND_REF}")}"

  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is not available in PATH; cannot clone VuFind." >&2
    exit 1
  fi

  # Silently clone
  git clone --quiet --branch "${repo_ref}" --single-branch "${repo_url}" "${ROOT_DIR}/vufind" > /dev/null 2>&1
  cloned_vufind=true

  if [ "${cloned_vufind}" = true ]; then
    sync_solr_assets_from_vufind > /dev/null 2>&1
  fi
}

ensure_vufind_for_services() {
  local service
  for service in "$@"; do
    if service_requires_vufind "${service}"; then
      ensure_vufind_checkout
      return 0
    fi
  done
}

filter_vufind_services_if_checkout_missing() {
  local explicit_vufind="$1"
  shift || true

  local services_in=("$@")
  local skipped=()
  local service

  FILTERED_SERVICES=()

  if [ "${explicit_vufind}" = true ] || [ -d "${ROOT_DIR}/vufind" ]; then
    FILTERED_SERVICES=("${services_in[@]}")
    return 0
  fi

  for service in "${services_in[@]}"; do
    if service_requires_vufind "${service}"; then
      skipped+=("${service}")
    else
      FILTERED_SERVICES+=("${service}")
    fi
  done

  if [ "${#skipped[@]}" -gt 0 ]; then
    echo "VuFind is not cloned; skipping services: ${skipped[*]}."
    echo "To include them explicitly: ./Docker/docker.sh vufind up  (or ./Docker/docker.sh up --vufind)"
  fi
}

dir_has_non_gitkeep_content() {
  local dir="$1"
  find "${dir}" -mindepth 1 ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .
}

ensure_solr_build_context() {
  local import_dir="${ROOT_DIR}/Docker/solr/import"
  local jars_dir="${ROOT_DIR}/Docker/solr/jars"

  mkdir -p "${import_dir}" "${jars_dir}"
  touch "${import_dir}/.gitkeep" "${jars_dir}/.gitkeep"

  if ! dir_has_non_gitkeep_content "${import_dir}" || ! dir_has_non_gitkeep_content "${jars_dir}"; then
    if [ -d "${ROOT_DIR}/vufind/import" ] && [ -d "${ROOT_DIR}/vufind/solr/vufind/jars" ]; then
      echo "Missing/incomplete Solr assets; syncing from vufind/..."
      sync_solr_assets_from_vufind
    else
      echo "Warning: Docker/solr/import or Docker/solr/jars is empty. Solr will build with placeholders." >&2
    fi
  fi
}

refresh_solr_for_vufind_assets() {
  ensure_vufind_checkout
  sync_solr_assets_from_vufind
  echo "Recreating solr service to apply jars/import from VuFind..."
  dc up -d --force-recreate solr
}

ensure_java_parent_modules_ready() {
  local pull_existing="${1:-false}"
  local missing=()
  local module

  for module in "${JAVA_PARENT_MODULES[@]}"; do
    if [ ! -f "${ROOT_DIR}/${module}/pom.xml" ]; then
      missing+=("${module}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing initialized Java workspace modules (pom.xml absent):" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Cloning missing modules using githelper..." >&2
    if [ -x "${ROOT_DIR}/githelper" ]; then
      "${ROOT_DIR}/githelper" init
    else
      python3 "${ROOT_DIR}/githelper" init
    fi
  fi

  if [ "${pull_existing}" = "true" ]; then
    echo "Pulling updates for existing modules using githelper..." >&2
    if [ -x "${ROOT_DIR}/githelper" ]; then
      "${ROOT_DIR}/githelper" pull || true
    else
      python3 "${ROOT_DIR}/githelper" pull || true
    fi
  fi

  # Re-verify after run
  missing=()
  for module in "${JAVA_PARENT_MODULES[@]}"; do
    if [ ! -f "${ROOT_DIR}/${module}/pom.xml" ]; then
      missing+=("${module}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Error: Some modules are still missing after initialization." >&2
    return 1
  fi

  return 0
}

ensure_m2_cache_dir() {
  # No-op since we now use the shared named volume lr-maven-cache
  return 0
}

compile_java_modules() {
  echo "--- Compiling Java Modules (using named volume lr-maven-cache) ---"
  
  # Ensure the named volume exists
  docker volume create lr-maven-cache >/dev/null 2>&1 || true
  
  local profile="${LR_BUILD_PROFILE:-lareferencia}"
  
  # Run maven compilation inside a container with the named volume
  local compile_cmd="docker run --rm \
    -v lr-maven-cache:/root/.m2 \
    -v \"${ROOT_DIR}:/workspace\" \
    -w /workspace \
    maven:3.9.11-eclipse-temurin-17 \
    mvn clean package -DskipTests -Dspring-boot.repackage.executable=false -P${profile}"
    
  eval "${compile_cmd}"
}

run_global_build() {
  compile_java_modules

  echo "--- Building images using Multi-stage Dockerfiles ---"
  local profile_args=()
  profile_args+=(--profile tools)
  if [ "$(get_module_state "elastic")" = "on" ]; then
    profile_args+=(--profile elastic)
  fi
  if [ "$(get_module_state "watch")" = "on" ]; then
    profile_args+=(--profile watch)
  fi
  dc "${profile_args[@]}" build --no-cache
  echo "--- Build completed successfully ---"
}

run_init_db() {
  local shell_cmd=("$@")
  if [ "${#shell_cmd[@]}" -eq 0 ]; then
    if [ -f "${ROOT_DIR}/Docker/config-overrides/lareferencia-shell/db_init_script.txt" ]; then
      shell_cmd=(script /tmp/lr-config/lareferencia-shell/db_init_script.txt)
    else
      shell_cmd=(database_migrate)
    fi
  fi

  echo "--- Cleaning up potential remnants from previous runs ---"
  # Garante que containers que possam estar em estado de erro ou travados sejam removidos
  dc --profile tools rm -f -s -v postgres solr shell db-init 2>/dev/null || true
  echo "--- Running Database Initialization ---"
  dc --profile tools up -d postgres solr
  
  # Executa a inicialização em foreground (logs capturados externamente se necessário)
  dc --profile tools run --rm -T --no-deps shell /usr/local/bin/lr-app-entrypoint.sh "${shell_cmd[@]}"
  local exit_code=$?
  
  if [ "${exit_code}" -ne 0 ]; then
    echo -e "\n\033[31m❌ Database initialization failed with exit code ${exit_code}.\033[0m"
    exit "${exit_code}"
  else
    echo -e "\n\033[32m✔ Database initialization completed successfully.\033[0m"
  fi
}

ensure_shell_service_running() {
  dc up -d postgres solr
  return 0
}

exec_shell_command_noninteractive() {
  local cmd=("$@")
  if dc ps --status running --services 2>/dev/null | grep -q "^shell$"; then
    dc exec -T -e SHELL_IDLE=false shell /usr/local/bin/lr-app-entrypoint.sh ${cmd+"${cmd[@]}"}
  else
    dc run --rm -T -e SHELL_IDLE=false shell ${cmd+"${cmd[@]}"}
  fi
}

exec_shell_command_interactive() {
  local cmd=("$@")
  if dc ps --status running --services 2>/dev/null | grep -q "^shell$"; then
    dc exec -e SHELL_IDLE=false shell /usr/local/bin/lr-app-entrypoint.sh ${cmd+"${cmd[@]}"}
  else
    dc run --rm -e SHELL_IDLE=false shell ${cmd+"${cmd[@]}"}
  fi
}

clean_data_preserving_tracked() {
  local rel_data_dir="${DATA_DIR#${ROOT_DIR}/}"
  local rel_volume_dir="${VOLUME_DIR#${ROOT_DIR}/}"
  echo "--- Cleaning data in ${rel_data_dir} and ${rel_volume_dir} ---"

  # On Linux, containers (e.g. postgres) create files as root or internal UIDs (999).
  # We must fix permissions using Docker before the host user can delete them.
  if command -v docker >/dev/null 2>&1; then
    echo "Fixing permissions for data directories using Docker..."
    docker run --rm -v "${ROOT_DIR}:/workspace" alpine sh -c "chmod -R ugo+rwX /workspace/${rel_data_dir} /workspace/${rel_volume_dir} 2>/dev/null" || true
  fi

  if command -v git >/dev/null 2>&1 && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Git clean excluding the m2 directory
    local paths_to_clean=()
    [ -n "${rel_data_dir}" ] && paths_to_clean+=("${rel_data_dir}")
    [ -n "${rel_volume_dir}" ] && paths_to_clean+=("${rel_volume_dir}")
    
    if [ ${#paths_to_clean[@]} -gt 0 ]; then
      git -C "${ROOT_DIR}" clean -fdx -e "m2/" -- "${paths_to_clean[@]}"
    fi
  else
    # Find/delete excluding the m2 path
    for dir in "${DATA_DIR}" "${VOLUME_DIR}"; do
      if [ -d "${dir}" ]; then
        find "${dir}" -mindepth 1 -path "${dir}/m2" -prune -o ! -name '.gitkeep' -type f -delete
        find "${dir}" -mindepth 1 -path "${dir}/m2" -prune -o -type l -delete
        find "${dir}" -mindepth 1 -path "${dir}/m2" -prune -o -type d -empty -delete
      fi
    done
  fi
}

print_module_status() {
  local running_services
  local module
  running_services="$(dc ps --status running --services 2>/dev/null || true)"

  echo -e "${C_CYAN}${C_BOLD}📦 Platform Modules:${C_RESET}"
  for module in "${ALL_MODULES[@]}"; do
    local state="$(get_module_state "${module}")"
    local color=$C_GRAY
    local state_icon="⚪"
    [ "${state}" = "on" ] && { color=$C_GREEN; state_icon="🟢"; }
    
    printf "  %-10s [${color}%-3s${C_RESET}] %s\n" "${module}" "${state}" "${state_icon}"
    
    for service in $(module_services "${module}"); do
      local status="${C_GRAY}off${C_RESET}"
      local status_icon="⭕"
      if printf "%s\n" "${running_services}" | grep -Fxq "${service}"; then
        status="${C_GREEN}running${C_RESET}"
        status_icon="⚡"
      fi
      printf "    └─ %-15s [${status_icon}${status}]\n" "${service}"
    done
  done
}

print_module_status_one() {
  local module="$1"
  validate_module_name "${module}"
  local state="$(get_module_state "${module}")"
  echo -e "${C_BOLD}${module}${C_RESET}: ${state}"
}

is_any_service_running() {
  local running
  running="$(dc ps --status running --services 2>/dev/null || true)"
  [ -n "${running}" ]
}

# --- Wizard Logic ---

clear_screen() {
  printf "\033c"
}

draw_header() {
  echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
  echo -e "${C_CYAN}  🐳 ${C_BOLD}LA REFERENCIA PLATFORM${C_RESET} ${C_CYAN}- Docker Management Wizard${C_RESET}"
  echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}

show_current_config() {
  local prefix="$(get_env_var SERVICE_PREFIX "lareferencia")"
  local offset="$(get_env_var SERVICES_PORT_OFFSET "0")"
  local profile="$(get_env_var LR_BUILD_PROFILE "lareferencia")"
  local res_profile="$(get_env_var LR_RESOURCE_PROFILE "medium")"
  
  echo -e "${C_MAGENTA}${C_BOLD}⚙️  CURRENT CONFIGURATION:${C_RESET}"
  echo -e "  🆔 ${C_GRAY}Project:${C_RESET} ${C_BOLD}${COMPOSE_PROJECT_NAME:-lareferencia}${C_RESET}"
  echo -e "  🏷️  ${C_GRAY}Prefix:${C_RESET}  ${C_BOLD}${prefix}${C_RESET}"
  echo -e "  🔌 ${C_GRAY}Offset:${C_RESET}  ${C_YELLOW}${offset}${C_RESET}"
  echo -e "  🏗️  ${C_GRAY}Profile:${C_RESET} ${C_BLUE}${profile}${C_RESET}"
  echo -e "  ⚡ ${C_GRAY}Resources:${C_RESET} ${C_GREEN}${res_profile}${C_RESET}"
  echo
  print_module_status
  echo
}

execute_with_progress() {
    local cmd="$1"
    local label="$2"
    local log_file="${3:-/tmp/lareferencia-docker.log}"
    
    rm -f "$log_file"
    # Execute command in background and capture PID
    eval "$cmd" > "$log_file" 2>&1 &
    local pid=$!
    
    local width=15
    local i=0
    local cpu_val="0"
    local mem_val="0"
    local ncpu
    if [[ "$OSTYPE" == "darwin"* ]]; then
      ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    else
      ncpu=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    fi

    # Determine terminal width (target exactly 78 to match the wizard header)
    local total_width=78
    local term_cols
    term_cols=$(tput cols 2>/dev/null || echo 80)
    if [ "${term_cols}" -lt 80 ]; then
      total_width=$((term_cols - 2))
    fi
    [ "${total_width}" -lt 40 ] && total_width=40

    local content_width=$((total_width - 4))
    local bottom_len=$((total_width - 2))

    # Hide cursor
    printf "\033[?25l"

    # Disable exit on error temporarily to handle the wait manually
    set +e
    while kill -0 $pid 2>/dev/null; do
        # Move cursor up 7 lines ONLY on subsequent iterations to avoid overlapping prior output on start
        if [ $i -gt 0 ]; then
          printf "\r\033[7A"
        fi
        
        # Spinner character
        local spinner_char="⠋"
        case $((i % 10)) in
            0) spinner_char="⠋" ;;
            1) spinner_char="⠙" ;;
            2) spinner_char="⠹" ;;
            3) spinner_char="⠸" ;;
            4) spinner_char="⠼" ;;
            5) spinner_char="⠴" ;;
            6) spinner_char="⠦" ;;
            7) spinner_char="⠧" ;;
            8) spinner_char="⠇" ;;
            9) spinner_char="⠏" ;;
        esac

        # 1. Top border (clear line first to avoid ghosts)
        local border_len=$((total_width - 9 - ${#label}))
        if [ "${border_len}" -lt 2 ]; then border_len=2; fi
        local border_str
        border_str=$(printf '─%.0s' $(seq 1 ${border_len}))
        printf "\033[K${C_CYAN}┌─ %s [%s] %s┐${C_RESET}\n" "${label}" "${spinner_char}" "${border_str}"

        # 2. Get last 5 lines from log file portably
        local lines=()
        local idx=0
        if [ -f "$log_file" ]; then
          while IFS= read -r line || [ -n "${line}" ]; do
            lines[idx]="${line}"
            idx=$((idx + 1))
          done < <(tail -n 5 "$log_file" 2>/dev/null)
        fi
        
        for k in {0..4}; do
          local line="${lines[$k]:-}"
          line=$(echo "${line}" | tr -d '\r')
          if [ "${#line}" -gt "${content_width}" ]; then
            line="${line:0:$((content_width - 3))}..."
          fi
          printf "\033[K${C_CYAN}│${C_RESET} %-${content_width}s ${C_CYAN}│${C_RESET}\n" "${line}"
        done

        # 3. Bottom border
        local bottom_str
        bottom_str=$(printf '─%.0s' $(seq 1 ${bottom_len}))
        printf "\033[K${C_CYAN}└%s┘${C_RESET}\n" "${bottom_str}"

        # 4. Progress bar, status text, and CPU/MEM stats
        local progress=$(( (i % width) + 1 ))
        local remaining=$(( width - progress ))
        
        # Update system stats every 1.5 seconds to avoid overhead
        if (( i % 15 == 0 )); then
          if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS CPU: ps sum normalized by cores
            local raw_cpu=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%.0f", s}')
            cpu_val=$(( raw_cpu / ncpu ))
            [ $cpu_val -gt 100 ] && cpu_val=100
            # macOS Mem: Approximation via vm_stat
            mem_val=$(memory_pressure | grep "System-wide memory free percentage" | awk '{print 100-$5}' || echo "0")
          else
            # Linux fallback
            cpu_val=$(top -bn1 | grep "Cpu(s)" | awk '{s+=$2+$4} END {print s}' | cut -d. -f1 || echo "0")
            mem_val=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}' || echo "0")
          fi
        fi

        # Helper for mini-bar graph
        draw_mini_graph() {
          local val=$1
          local color=$C_GREEN
          [ $val -gt 60 ] && color=$C_YELLOW
          [ $val -gt 85 ] && color=$C_RED
          
          local blocks=(" " "▂" "▃" "▄" "▅" "▆" "▇" "█")
          local idx=$(( val * 7 / 100 ))
          printf "${color}${blocks[$idx]}${C_RESET}"
        }

        # Extract current status/service from log
        local status_text="Initializing..."
        if [ -f "$log_file" ]; then
          local found
          found=$(grep -E "Container|Building|#|Step|cloned|pulled|Cloning|Pulling" "$log_file" | tail -n 1 | sed -E 's/.*Container ([^ ]+).*/\1/; s/.*Building ([^ ]+).*/\1/; s/.*#[0-9]+ (\[[^]]+\]).*/\1/; s/.*OK[[:space:]]+(lareferencia-[^:]+): (cloned|pulled).*/\2 \1/; s/.*(Cloning|Pulling) (missing|updates)( for existing)? modules.*/\1 modules/; s/lareferencia-//g')
          if [ -n "$found" ]; then
             status_text="$found"
          fi
          status_text=${status_text//"${COMPOSE_PROJECT_NAME:-lr}-"/}
          status_text=$(echo "$status_text" | tr -d '\r\n')
          if [ ${#status_text} -gt 15 ]; then
            status_text="${status_text:0:12}..."
          fi
        fi

        printf "\r\033[K  [${C_GREEN}"
        for ((j=0; j<progress; j++)); do printf "━"; done
        printf "${C_GRAY}"
        for ((j=0; j<remaining; j++)); do printf " "; done
        printf "${C_RESET}] "
        
        # Info display: Status + CPU/MEM Mini Graphs
        printf " ${C_GRAY}➜ ${C_BOLD}%-15s${C_RESET} " "$status_text"
        printf "${C_GRAY}CPU:${C_RESET}$(draw_mini_graph $cpu_val)${C_GRAY}%-3s${C_RESET} " "$cpu_val%"
        printf "${C_GRAY}MEM:${C_RESET}$(draw_mini_graph $mem_val)${C_GRAY}%-3s${C_RESET}" "$mem_val%"
        
        i=$((i + 1))
        sleep 0.1
    done
    
    wait $pid
    local status=$?
    set -e # Re-enable exit on error
    printf "\033[?25h" # Show cursor
    
    # Clear all 8 lines of progress only if we actually drew the box
    if [ $i -gt 0 ]; then
      printf "\r\033[7A"
      for k in {1..8}; do printf "\033[K\n"; done
      printf "\r\033[8A"
    fi

    if [ $status -eq 0 ]; then
        printf "\r  ${C_GREEN}✅ ${label} Completed!${C_RESET}\n"
    else
        local rev="unknown"
        if command -v git >/dev/null 2>&1 && git -C "${ROOT_DIR:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          rev=$(git -C "${ROOT_DIR:-.}" describe --tags --always --dirty 2>/dev/null || echo "unknown")
        fi
        printf "\r  ${C_RED}❌ ${label} Failed! [Rev: %s] (See details below)${C_RESET}\n" "${rev}"
        echo -e "${C_GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_RED}${C_BOLD}ERROR LOG (Last 20 lines):${C_RESET}"
        if [ -f "$log_file" ]; then
          tail -n 20 "$log_file"
        else
          echo "Log file not found."
        fi
        echo -e "${C_GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_YELLOW}Full log available at: $log_file${C_RESET}\n"
    fi
    return $status
}

ensure_docker_installed() {
  local missing=()
  if ! command -v docker >/dev/null 2>&1; then
    missing+=("docker (Engine)")
  fi
  if ! docker compose version >/dev/null 2>&1; then
    missing+=("docker compose (Plugin V2)")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    echo -e "${C_RED}${C_BOLD}❌ FATAL ERROR: Missing required tools:${C_RESET}"
    for tool in "${missing[@]}"; do
      echo -e "  - ${tool}"
    done
    echo -e "\nPlease install Docker and the Docker Compose plugin to use this wizard."
    echo -e "Documentation: https://docs.docker.com/get-docker/"
    exit 1
  fi
}

get_check_status() {
  local docker_ok="${C_GREEN}✓${C_RESET} Docker"
  local compose_ok="${C_GREEN}✓${C_RESET} Compose"
  local daemon_ok="${C_GREEN}✓${C_RESET} Daemon"

  if ! command -v docker >/dev/null 2>&1; then
    docker_ok="${C_RED}✗${C_RESET} Docker"
  fi

  if ! docker compose version >/dev/null 2>&1; then
    compose_ok="${C_RED}✗${C_RESET} Compose"
  fi

  if ! docker info >/dev/null 2>&1; then
    daemon_ok="${C_RED}✗${C_RESET} Daemon"
  fi

  printf "%s|%s|%s" "$docker_ok" "$compose_ok" "$daemon_ok"
}

get_service_port() {
  local service="$1"
  local salt
  salt="$(get_env_var SERVICES_PORT_OFFSET 0)"
  salt="${salt//[^0-9]/}"
  [ -z "${salt}" ] && salt=0

  case "${service}" in
    vufind-web)     printf ":%s" $((8080 + salt)) ;;
    vufind-db)      printf ":%s" $((3307 + salt)) ;;
    solr)           printf ":%s" $((8983 + salt)) ;;
    postgres)       printf ":%s" $((5432 + salt)) ;;
    harvester)      printf ":%s" $((8090 + salt)) ;;
    dashboard-rest) printf ":%s" $((8092 + salt)) ;;
    entity-rest)    printf ":%s" $((8094 + salt)) ;;
    elasticsearch)  printf ":%s" $((9200 + salt)) ;;
    *)              printf "" ;;
  esac
}

print_module_status_columns() {
  local running_services
  running_services="$(dc ps --status running --services 2>/dev/null || true)"
  local blocks=()

  for module in "${ALL_MODULES[@]}"; do
    # Skip Harvester as it will be grouped with Core
    [ "${module}" = "harvester" ] && continue

    local state="$(get_module_state "${module}")"
    local color="245"
    local state_icon="○"
    [ "${state}" = "on" ] && { color="114"; state_icon="●"; }
    
    local module_upper
    module_upper=$(echo "$module" | tr '[:lower:]' '[:upper:]')
    [ "${module}" = "core" ] && module_upper="CORE & HARVESTER"

    # Build internal content
    local content="${state_icon} ${module_upper}"$'\n'"──────────────"
    
    local services_to_show
    services_to_show=$(module_services "${module}")
    # If core, also add harvester services
    if [ "${module}" = "core" ]; then
      services_to_show="${services_to_show} $(module_services "harvester")"
    fi

    for service in ${services_to_show}; do
      local s_icon="○"
      local port_info=""
      if printf "%s\n" "${running_services}" | grep -Fxq "${service}"; then
        s_icon="${C_GREEN}⚡${C_RESET}"
        port_info="${C_YELLOW}$(get_service_port "${service}")${C_RESET}"
      else
        s_icon="${C_GRAY}○${C_RESET}"
      fi
      content="${content}"$'\n'" ${s_icon} ${service}${port_info}"
    done
    
    # Single gum style call per module - Borderless
    blocks+=("$(gum style --padding "0 1" --margin "0 2" --width 28 --foreground "$color" "$content")")
  done

  # Split into rows
  local row1=("${blocks[@]:0:3}")
  local row2=("${blocks[@]:3:3}")
  local row3=("${blocks[@]:6:3}")

  gum join --vertical \
    "$(gum join --horizontal "${row1[@]}")" \
    "$(gum join --horizontal "${row2[@]}")" \
    "$(gum join --horizontal "${row3[@]}")"
}

wizard_modules() {
  clear_screen
  draw_header
  
  local optional_modules=("solr" "harvester" "dashboard" "entity-rest" "shell" "vufind" "elastic" "watch")
  local pre_selected=()
  for m in "${optional_modules[@]}"; do
    if [ "$(get_module_state "${m}")" = "on" ]; then
      pre_selected+=("${m}")
    fi
  done

  local pre_selected_joined
  pre_selected_joined=$(IFS=,; echo "${pre_selected[*]}")

  echo -e "${C_BOLD}📦 MODULE MANAGEMENT${C_RESET}"
  echo -e "${C_GRAY}The 'core' module (postgres database) is always active.${C_RESET}\n"
  
  local gum_args=(--no-limit)
  if [ -n "${pre_selected_joined}" ]; then
    gum_args+=(--selected="${pre_selected_joined}")
  fi

  local choices
  choices=$(gum choose "${gum_args[@]}" \
    --header "Instructions: [Space] Toggles selection | [Enter] Confirms all" \
    --item.foreground 245 --selected.foreground 114 --cursor.foreground 80 \
    "${optional_modules[@]}")

  # Reset all optional modules to off
  for m in "${optional_modules[@]}"; do
    set_module_state "${m}" off
  done

  # Activate selected ones
  local has_vufind_or_harvester=false
  for m in ${choices}; do
    set_module_state "${m}" on
    if [ "${m}" = "vufind" ] || [ "${m}" = "harvester" ]; then
      has_vufind_or_harvester=true
    fi
  done

  # Auto-activate solr if vufind or harvester is selected
  if [ "${has_vufind_or_harvester}" = true ]; then
    set_module_state "solr" on
  fi
  
  echo -e "\n${C_CYAN}Configuration updated.${C_RESET}"
  sleep 1
}

wizard_shell() {
  while true; do
    clear_screen
    gum style \
      --foreground 80 --border-foreground 80 --border double \
      --align center --width 80 --margin "1 2" --padding "1 2" \
      "💻 ENTER CONTAINER SHELL" \
      "Select a running service or access the interactive platform shell"

    local running_services=()
    # Read running services into array
    while IFS= read -r svc; do
      [ -n "$svc" ] && running_services+=("$svc")
    done < <(dc ps --status running --services 2>/dev/null)

    local menu_options=()
    menu_options+=("🐚 LA Referencia Interactive Shell (lrshell)")
    for svc in "${running_services[@]}"; do
      menu_options+=("$svc")
    done
    menu_options+=("🔙 Back")

    echo "⚡ AVAILABLE SHELLS:"
    echo
    
    local choice
    choice=$(gum choose "${menu_options[@]}")

    if [ "$choice" = "🔙 Back" ] || [ -z "$choice" ]; then
      return
    fi

    if [ "$choice" = "🐚 LA Referencia Interactive Shell (lrshell)" ]; then
      echo -e "\n${C_GREEN}Opening LA Referencia Interactive Shell... (type 'exit' to return)${C_RESET}"
      "${BASH_SOURCE[0]}" lrshell-interactive || true
    else
      # Run shell for the selected service
      echo -e "\n${C_GREEN}Opening bash shell in service '${choice}'... (type 'exit' to return)${C_RESET}"
      dc exec "${choice}" bash || dc exec "${choice}" sh || true
    fi
    
    echo
    gum input --placeholder "Shell closed. Press Enter to continue..." > /dev/null
  done
}

wizard_main() {
  # Set terminal title
  printf "\033]0;Lareferencia Docker Wizard\007"

  while true; do
    clear_screen
    
    local checks
    checks=$(get_check_status)
    IFS='|' read -r c1 c2 c3 <<< "$checks"

    local project_revision="unknown"
    if command -v git >/dev/null 2>&1 && git -C "${ROOT_DIR:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      project_revision=$(git -C "${ROOT_DIR:-.}" describe --tags --always --dirty 2>/dev/null || echo "unknown")
    fi

    gum style \
      --foreground 80 --border-foreground 80 --border double \
      --align center --width 80 --margin "1 2" --padding "1 2" \
      "🐳 LA REFERENCIA PLATFORM" \
      "Docker Management Wizard" \
      "Rev: ${project_revision}" \
      "" \
      "$(gum join --horizontal --align center "$c1   " "$c2   " "$c3")"

    local prefix="$(get_env_var SERVICE_PREFIX "lareferencia")"
    local offset="$(get_env_var SERVICES_PORT_OFFSET "0")"
    local profile="$(get_env_var LR_BUILD_PROFILE "lareferencia")"
    local cache_state="$(get_env_var DOCKER_BUILD_CACHE "on")"
    local cache_display="ON"
    [ "${cache_state}" = "off" ] && cache_display="OFF"
    
    # Status Table
    local res_profile="$(get_env_var LR_RESOURCE_PROFILE "medium")"
    local status_text="Project: ${COMPOSE_PROJECT_NAME:-lareferencia} | Prefix: ${prefix} | Offset: ${offset} | Profile: ${profile} | Resources: ${res_profile}"
    gum style --foreground 176 "$status_text"
    echo

    print_module_status_columns
    echo

    gum style --foreground 80 --bold --underline "⚡ SELECT ACTION"
    echo

    local choice
    choice=$(gum choose \
      --item.bold --selected.bold --selected.background 80 --selected.foreground 232 \
      --cursor.bold --cursor.foreground 80 \
      "🚀 Start Platform" \
      "🔄 Rebuild & Start Platform" \
      "🛑 Stop Platform (stop - fast)" \
      "🧹 Teardown Platform (down - clean)" \
      "📦 Manage Modules (on/off)" \
      "🏗️ Build Cache: [${cache_display}]" \
      "📝 View Logs (follow)" \
      "💻 Enter Container Shell" \
      "🏷️ Change SERVICE_PREFIX" \
      "🔌 Change PORT_OFFSET" \
      "🏗️ Change BUILD_PROFILE" \
      "⚡ Resource Profile: [${res_profile}]" \
      "📡 Configure External Solr" \
      "🛠️ Run Init-DB (migrations)" \
      "🧹 Reset Data (CLEAN ALL)" \
      "🚪 Exit")

    case "$choice" in
      "🚀 Start Platform")
        echo -e "\n${C_GREEN}🚀 Starting the platform...${C_RESET}"
        local build_cmd="\"${BASH_SOURCE[0]}\" up"
        execute_with_progress "${build_cmd}" "Platform Start"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "🔄 Rebuild & Start Platform")
        echo -e "\n${C_GREEN}🔄 Rebuilding and starting the platform...${C_RESET}"
        local build_cmd="\"${BASH_SOURCE[0]}\" up --build --pull-modules"
        [ "${cache_state}" = "off" ] && build_cmd="${build_cmd} --no-cache"
        execute_with_progress "${build_cmd}" "Platform Rebuild & Start"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "🛑 Stop Platform (stop - fast)")
        echo -e "\n${C_RED}🛑 Stopping the platform (preserving containers)...${C_RESET}"
        execute_with_progress "\"${BASH_SOURCE[0]}\" stop" "Stopping Platform"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "🧹 Teardown Platform (down - clean)")
        echo -e "\n${C_RED}🧹 Tearing down the platform (removing containers)...${C_RESET}"
        execute_with_progress "\"${BASH_SOURCE[0]}\" down" "Teardown Platform"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "📦 Manage Modules (on/off)")
        wizard_modules
        ;;
      "🏗️ Build Cache: ["*)
        if [ "${cache_state}" = "on" ]; then
          set_env_var "DOCKER_BUILD_CACHE" "off"
        else
          set_env_var "DOCKER_BUILD_CACHE" "on"
        fi
        ;;
      "📝 View Logs (follow)")
        echo -e "\n${C_CYAN}📝 Showing logs (Ctrl+C to stop)...${C_RESET}"
        "${BASH_SOURCE[0]}" logs -f
        gum input --placeholder "Logs stopped. Press Enter to return to menu..." > /dev/null
        ;;
      "💻 Enter Container Shell")
        wizard_shell
        ;;
      "🏷️ Change SERVICE_PREFIX")
        if is_any_service_running; then
          gum style --foreground 222 "⚠️  WARNING: Containers are currently running."
          if gum confirm "Do you want to stop them now to change the service prefix?"; then
            execute_with_progress "\"${BASH_SOURCE[0]}\" down" "Stopping Platform"
          else
            continue
          fi
        fi
        local val
        val=$(gum input --placeholder "New SERVICE_PREFIX" --value "$prefix")
        if [[ -n "$val" ]]; then
          if [[ $val =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            set_env_var "SERVICE_PREFIX" "${val}"
            export_service_prefix
          else
            gum style --foreground 204 "❌ Invalid prefix. Must be lowercase alphanumeric, hyphens or underscores."
            sleep 2
          fi
        fi
        ;;
      "🔌 Change PORT_OFFSET")
        if is_any_service_running; then
          gum style --foreground 222 "⚠️  WARNING: Containers are currently running."
          if gum confirm "Do you want to stop them now to change the port offset?"; then
            execute_with_progress "\"${BASH_SOURCE[0]}\" down" "Stopping Platform"
          else
            continue
          fi
        fi
        local val
        val=$(gum input --placeholder "New PORT_OFFSET (number)" --value "$offset")
        if [[ -n "$val" && $val =~ ^[0-9]+$ ]]; then
          set_env_var "SERVICES_PORT_OFFSET" "${val}"
        fi
        ;;
      "🏗️ Change BUILD_PROFILE")
        local val
        val=$(gum choose "lareferencia" "ibict" "rcaap" "lite")
        set_env_var "LR_BUILD_PROFILE" "${val}"
        ;;
      "⚡ Resource Profile: ["*)
        local choice
        choice=$(gum choose "low" "medium" "high" "custom")
        if [ "${choice}" = "custom" ]; then
          local services=("HARVESTER" "SOLR" "POSTGRES" "DASHBOARD" "ENTITY" "VUFIND" "ELASTIC")
          local custom_file="${SCRIPT_DIR}/profiles/custom.env"
          echo "# Profile: custom" > "${custom_file}"
          
          for s in "${services[@]}"; do
            local current_mem=$(get_env_var "LR_MEM_${s}" "1G")
            local current_cpu=$(get_env_var "LR_CPU_${s}" "0.5")
            
            echo -e "\n${C_BOLD}${C_MAGENTA}⚙️  Configuring ${s}${C_RESET}"
            local mem=$(gum input --header "Memory Limit (e.g., 2G, 512M):" --value "${current_mem}")
            local cpu=$(gum input --header "CPU Limit (e.g., 1.0, 0.5):" --value "${current_cpu}")
            
            local final_mem="${mem:-$current_mem}"
            local final_cpu="${cpu:-$current_cpu}"
            
            set_env_var "LR_MEM_${s}" "${final_mem}"
            set_env_var "LR_CPU_${s}" "${final_cpu}"
            echo "LR_MEM_${s}=${final_mem}" >> "${custom_file}"
            echo "LR_CPU_${s}=${final_cpu}" >> "${custom_file}"
          done
          set_env_var "LR_RESOURCE_PROFILE" "custom"
        else
          apply_resource_profile "${choice}"
        fi
        ;;
      "📡 Configure External Solr")
        local current_ext
        current_ext=$(get_env_var SOLR_EXTERNAL_URL "")
        local val
        val=$(gum input --placeholder "External Solr URL (leave empty for internal Docker Solr)" --value "$current_ext")
        set_env_var "SOLR_EXTERNAL_URL" "${val}"
        if [ -n "$val" ]; then
          gum style --foreground 114 "📡 External Solr configured: $val"
        else
          gum style --foreground 114 "🟢 Using internal Docker Solr."
        fi
        sleep 2
        ;;
      "🛠️ Run Init-DB (migrations)")
        echo -e "\n${C_MAGENTA}🛠️  Running database migrations...${C_RESET}"
        execute_with_progress "\"${BASH_SOURCE[0]}\" init-db" "Database Migrations"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "🧹 Reset Data (CLEAN ALL)")
        echo
        gum style --foreground 204 --border double --border-foreground 204 --padding "0 1" "⚠️  DANGER ZONE: ALL DATA AND ALL CONTAINERS WILL BE PERMANENTLY DELETED"
        if gum confirm "Are you absolutely sure you want to reset EVERYTHING?"; then
          "${BASH_SOURCE[0]}" reset-data --yes
          gum input --placeholder "System reset completed. Press Enter to continue..." > /dev/null
        fi
        ;;
      "🚪 Exit")
        echo -e "\n${C_CYAN}Goodbye! 👋${C_RESET}"
        exit 0
        ;;
    esac
  done
}

usage() {
  cat <<USAGE
Usage: ./Docker/docker.sh <command> [options]

Core Commands:
  wizard               Start the interactive assistant (RECOMMENDED)
  up [--build]         Start active modules
  down                 Stop and remove containers
  start/stop/restart   Manage existing containers
  ps / logs / health   Monitoring
  modules <on|off>     Enable/disable modules (vufind, elastic, watch)
  res <profile>        Apply resource profile (low, medium, high, custom)
  init-db              Migrate database
  reset-data           Clean Docker/data
  shell <service>      Start a bash shell in a running container
  lrshell-interactive  Start interactive session in the shell container

Variables in Docker/.env:
  SERVICE_PREFIX       Instance isolation
  SERVICES_PORT_OFFSET Port shifting
  LR_BUILD_PROFILE     Maven profile (ibict, rcaap, lareferencia)
USAGE
}

# --- Argument Parsing ---

cmd="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "${cmd}" in
  help|-h|--help)
    usage
    ;;

  wizard)
    ensure_docker_installed
    ensure_env_file
    export_service_prefix
    wizard_main
    ;;

  up)
    build_flag=false
    no_cache_flag=false
    pull_modules_flag=false
    explicit_vufind_request=false
    requested_modules=()
    services=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --build) build_flag=true ;;
        --no-cache) no_cache_flag=true ;;
        --pull-modules) pull_modules_flag=true ;;
        --prefix=*) set_env_var "SERVICE_PREFIX" "${1#*=}" ;;
        --offset=*) set_env_var "SERVICES_PORT_OFFSET" "${1#*=}" ;;
        --module) shift; requested_modules+=("$1"); [ "$1" = "vufind" ] && explicit_vufind_request=true ;;
        --vufind) requested_modules+=(vufind); explicit_vufind_request=true ;;
        --elastic) requested_modules+=(elastic) ;;
        --watch) requested_modules+=(watch); explicit_vufind_request=true ;;
        *) services+=("$1"); service_requires_vufind "$1" && explicit_vufind_request=true ;;
      esac
      shift
    done

    if [ "${#services[@]}" -eq 0 ]; then
      modules=()
      if [ "${#requested_modules[@]}" -gt 0 ]; then
        for m in "${requested_modules[@]}"; do validate_module_name "$m" && ! contains_item "$m" "${modules[@]-}" && modules+=("$m"); done
      else
        while IFS= read -r m; do [ -n "$m" ] && modules+=("$m"); done < <(enabled_modules)
      fi

      # --- Dependency Resolution ---
      # 1. harvester, dashboard, entity-rest, and shell need postgres (core)
      if contains_item "harvester" "${modules[@]-}" || contains_item "dashboard" "${modules[@]-}" || contains_item "entity-rest" "${modules[@]-}" || contains_item "shell" "${modules[@]-}"; then
        if ! contains_item "core" "${modules[@]-}"; then
          modules+=(core)
        fi
      fi

      # 2. harvester, shell, and vufind need solr
      if contains_item "harvester" "${modules[@]-}" || contains_item "shell" "${modules[@]-}" || contains_item "vufind" "${modules[@]-}"; then
        if ! contains_item "solr" "${modules[@]-}"; then
          modules+=(solr)
        fi
      fi

      collect_from_modules "${modules[@]}"
      services=("${COLLECTED_SERVICES[@]}")

      # If vufind or watch are enabled via environment/wizard, treat as explicit
      if contains_item "vufind" "${modules[@]-}" || contains_item "watch" "${modules[@]-}"; then
        explicit_vufind_request=true
      fi
    else
      collect_profiles_for_services "${services[@]}"
    fi

    filter_vufind_services_if_checkout_missing "${explicit_vufind_request}" "${services[@]}"
    services=("${FILTERED_SERVICES[@]}")
    collect_profiles_for_services "${services[@]}"

    ensure_m2_cache_dir
    ensure_vufind_for_services "${services[@]}"

    if [ "${build_flag}" = false ]; then
      if ! are_images_built "${services[@]}"; then
        echo -e "${C_YELLOW}⚠️  First-time run or missing Docker images detected. Forcing initial build...${C_RESET}"
        build_flag=true
        pull_modules_flag=true
      fi
    fi

    if [ "${build_flag}" = true ]; then
      ensure_java_parent_modules_ready "${pull_modules_flag}"
      contains_item solr "${services[@]-}" && ensure_solr_build_context
      run_global_build
      run_init_db
    fi

    args=(up -d --remove-orphans)
    if [ "${build_flag}" = true ]; then
      args+=(--force-recreate --build)
      [ "${no_cache_flag}" = true ] && args+=(--no-cache)
    fi

    if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
      p_args=()
      for p in "${COLLECTED_PROFILES[@]-}"; do p_args+=(--profile "$p"); done
      dc "${p_args[@]}" "${args[@]}" "${services[@]}"
    else
      dc "${args[@]}" "${services[@]}"
    fi
    ;;

  down)
    # Collect all possible profiles to ensure everything is stopped (elastic, tools, watch, etc.)
    all_profiles=()
    for m in "${ALL_MODULES[@]}"; do
      for p in $(module_profiles "${m}"); do
        if [ -n "${p}" ] && ! contains_item "${p}" "${all_profiles[@]-}"; then
          all_profiles+=("${p}")
        fi
      done
    done
    
    p_args=()
    for p in "${all_profiles[@]}"; do p_args+=(--profile "$p"); done
    
    down_args=(down --remove-orphans)
    # If the first argument is 'v', we add --volumes
    if [ "${1:-}" = "v" ]; then
      down_args+=(--volumes)
      shift
    fi
    
    dc "${p_args[@]}" "${down_args[@]}" ${1+"$@"}
    ;;

  start|stop|restart|build)
    services=()
    v_req=false
    if [ "$#" -eq 0 ]; then
      collect_from_modules $(enabled_modules)
      services=("${COLLECTED_SERVICES[@]}")
    else
      services=("$@")
      for s in "${services[@]}"; do service_requires_vufind "$s" && v_req=true; done
    fi
    filter_vufind_services_if_checkout_missing "$v_req" "${services[@]}"
    services=("${FILTERED_SERVICES[@]}")
    collect_profiles_for_services "${services[@]}"
    
    ensure_m2_cache_dir
    ensure_vufind_for_services "${services[@]}"
    
    p_args=()
    for p in "${COLLECTED_PROFILES[@]-}"; do p_args+=(--profile "$p"); done
    
    dc "${p_args[@]}" "${cmd}" "${services[@]}"
    ;;

  pull)
    dc pull vufind-db postgres elasticsearch vufind-scss-watch
    ;;

  ps) dc ps ;;
  logs) dc logs "${@}" ;;
  health)
    dc ps
    echo -e "\nEndpoints:"
    curl -fsS -o /dev/null -w "VuFind: http://localhost:${LR_PORT_VUFIND_WEB:-8080} -> %{http_code}\n" http://localhost:${LR_PORT_VUFIND_WEB:-8080}/ || true
    curl -fsS -o /dev/null -w "Harvester: http://localhost:${LR_PORT_HARVESTER:-8090} -> %{http_code}\n" http://localhost:${LR_PORT_HARVESTER:-8090}/ || true
    curl -fsS -o /dev/null -w "Entity REST: http://localhost:${LR_PORT_ENTITY_REST:-8094} -> %{http_code}\n" http://localhost:${LR_PORT_ENTITY_REST:-8094}/ || true
    ;;

  init-db)
    ensure_java_parent_modules_ready
    ensure_shell_service_running
    run_init_db "$@"
    ;;

  lrshell-interactive)
    ensure_java_parent_modules_ready
    ensure_shell_service_running
    exec_shell_command_interactive "$@"
    ;;

  reset-data)
    auto_yes=false
    [ "${1:-}" = "--yes" ] && auto_yes=true
    if [ "${auto_yes}" != true ]; then
      echo -e "${C_RED}This will clear data in Docker/data, REMOVE ALL containers, and DELETE cloned modules!${C_RESET}"
      read -r -p "Type RESET to confirm: " confirmation
      [ "${confirmation}" != "RESET" ] && exit 1
    fi
    echo "--- Stopping and removing all containers, networks and volumes ---"
    "${BASH_SOURCE[0]}" down v || true

    # Remove any compose containers matching the lareferencia-platform project name patterns
    if command -v docker >/dev/null 2>&1; then
      compose_containers=$(docker ps -a --filter "label=com.docker.compose.project" --format "{{.ID}} {{.Names}}" 2>/dev/null || true)
      if [ -n "${compose_containers}" ]; then
        echo "--- Cleaning up related compose containers from other project names ---"
        while read -r cid cname; do
          if [ -n "${cname}" ] && [[ "${cname}" == *"lareferencia"* || "${cname}" == "lr-"* || "${cname}" == "laref"* ]]; then
            echo "Stopping & removing container: ${cname}"
            docker rm -f "${cid}" >/dev/null 2>&1 || true
          fi
        done <<< "${compose_containers}"
      fi
    fi

    clean_data_preserving_tracked

    echo "--- Removing cloned workspace modules ---"
    if [ -f "${ROOT_DIR}/modules.txt" ]; then
      while IFS= read -r module || [ -n "$module" ]; do
        [ -z "$module" ] && continue
        [[ "$module" =~ ^# ]] && continue
        # Trim whitespace
        module="${module#"${module%%[![:space:]]*}"}"
        module="${module%"${module##*[![:space:]]}"}"
        
        module_dir="${ROOT_DIR}/${module}"
        if [ -d "${module_dir}" ]; then
          echo "Removing cloned module directory: ${module}"
          rm -rf "${module_dir}"
        fi
      done < "${ROOT_DIR}/modules.txt"
    else
      # Fallback list if modules.txt is not found
      fallback_modules=(
        lareferencia-solr-cores
        lareferencia-oclc-harvester
        lareferencia-core-lib
        lareferencia-entity-lib
        lareferencia-contrib-rcaap
        lareferencia-contrib-ibict
        lareferencia-indexing-filters-lib
        lareferencia-shell-entity-plugin
        lareferencia-shell
        lareferencia-dark-lib
        lareferencia-lrharvester-app
        lareferencia-entity-rest
        lareferencia-dashboard-rest
      )
      for module in "${fallback_modules[@]}"; do
        module_dir="${ROOT_DIR}/${module}"
        if [ -d "${module_dir}" ]; then
          echo "Removing cloned module directory: ${module}"
          rm -rf "${module_dir}"
        fi
      done
    fi
    ;;

  shell)
    svc="${1:-}"
    [ -z "${svc}" ] && echo "Usage: shell <service>" && exit 1
    dc exec "${svc}" bash
    ;;

  modules)
    sub="${1:-status}"
    [ "$#" -gt 0 ] && shift
    case "${sub}" in
      status) [ "$#" -eq 0 ] && print_module_status || print_module_status_one "$1" ;;
      on) validate_module_name "$1" && set_module_state "$1" on && echo "Module $1 activated." ;;
      off) validate_module_name "$1" && set_module_state "$1" off && echo "Module $1 deactivated." ;;
    esac
    ;;

  resource-profile|res)
    profile="${1:-}"
    [ -z "${profile}" ] && echo "Usage: res <low|medium|high|custom>" && exit 1
    apply_resource_profile "${profile}"
    ;;

  *)
    usage
    exit 1
    ;;
esac
