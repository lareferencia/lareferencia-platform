#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
DATA_DIR="${ROOT_DIR}/Docker/data"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

DEFAULT_VUFIND_REPO_URL="https://github.com/vufind-org/vufind"
DEFAULT_VUFIND_REF="v11.0.1"

ALL_MODULES=(core vufind elastic watch)
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
  
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
    sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*$|${key}=${value}|g" "${file}"
    rm -f "${file}.bak"
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
  fi
}

export_salted_ports() {
  unset LR_PORT_VUFIND_WEB LR_PORT_VUFIND_DB LR_PORT_SOLR LR_PORT_POSTGRES LR_PORT_HARVESTER LR_PORT_DASHBOARD LR_PORT_ELASTIC_9200 LR_PORT_ELASTIC_9300

  local salt
  salt="$(get_env_var SERVICES_PORT_OFFSET 0)"
  salt="${salt//[^0-9]/}"

  if [ -z "${salt}" ] || [ "${salt}" -eq 0 ]; then
    return 0
  fi

  local base_vufind_web=8080
  local base_vufind_db=3307
  local base_solr=8983
  local base_postgres=5432
  local base_harvester=8090
  local base_dashboard=8092
  local base_elastic_9200=9200
  local base_elastic_9300=9300

  export LR_PORT_VUFIND_WEB=$((base_vufind_web + salt))
  export LR_PORT_VUFIND_DB=$((base_vufind_db + salt))
  export LR_PORT_SOLR=$((base_solr + salt))
  export LR_PORT_POSTGRES=$((base_postgres + salt))
  export LR_PORT_HARVESTER=$((base_harvester + salt))
  export LR_PORT_DASHBOARD=$((base_dashboard + salt))
  export LR_PORT_ELASTIC_9200=$((base_elastic_9200 + salt))
  export LR_PORT_ELASTIC_9300=$((base_elastic_9300 + salt))
}

dc() {
  ensure_env_file
  export_salted_ports
  export_service_prefix
  
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
    vufind) printf "DEV_MODULE_VUFIND\n" ;;
    elastic) printf "DEV_MODULE_ELASTIC\n" ;;
    watch) printf "DEV_MODULE_WATCH\n" ;;
    *) return 1 ;;
  esac
}

module_default_state() {
  local module="$1"
  case "${module}" in
    core) printf "on\n" ;;
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
      printf "postgres solr harvester dashboard-rest shell\n"
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
    core)
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

  if [ -d "${ROOT_DIR}/vufind" ]; then
    return 0
  fi

  repo_url="${VUFIND_REPO_URL:-$(get_env_var VUFIND_REPO_URL "${DEFAULT_VUFIND_REPO_URL}")}"
  repo_ref="${VUFIND_REF:-$(get_env_var VUFIND_REF "${DEFAULT_VUFIND_REF}")}"

  echo "Directory ${ROOT_DIR}/vufind not found."

  if [ -t 0 ]; then
    repo_url=$(gum input --placeholder "VuFind GitHub Repository" --value "${repo_url}")
    repo_ref=$(gum input --placeholder "VuFind Branch/tag" --value "${repo_ref}")
  else
    echo "Non-interactive terminal; using defaults:"
    echo "  repo=${repo_url}"
    echo "  ref=${repo_ref}"
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "git is not available in PATH; cannot clone VuFind." >&2
    exit 1
  fi

  echo "Cloning VuFind: ${repo_url} (${repo_ref})..."
  git clone --branch "${repo_ref}" --single-branch "${repo_url}" "${ROOT_DIR}/vufind"
  cloned_vufind=true

  if [ "${cloned_vufind}" = true ]; then
    echo "Syncing Solr assets (import/jars) from VuFind..."
    sync_solr_assets_from_vufind
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
  local missing=()
  local module

  for module in "${JAVA_PARENT_MODULES[@]}"; do
    if [ ! -f "${ROOT_DIR}/${module}/pom.xml" ]; then
      missing+=("${module}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing initialized Java submodules (pom.xml absent):" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Run: ./githelper pull" >&2
    return 1
  fi

  return 0
}

ensure_m2_cache_dir() {
  mkdir -p "${ROOT_DIR}/Docker/data/m2/repository"
}

run_global_build() {
  echo "--- Building images using Multi-stage Dockerfiles ---"
  dc build
  echo "--- Build completed successfully ---"
}

run_init_db() {
  local shell_cmd=("$@")
  if [ "${#shell_cmd[@]}" -eq 0 ]; then
    shell_cmd=(database_migrate)
  fi

  echo "--- Running Database Initialization ---"
  dc up -d postgres solr
  exec_shell_command_noninteractive "${shell_cmd[@]}"
}

ensure_shell_service_running() {
  dc up -d postgres solr
  return 0
}

exec_shell_command_noninteractive() {
  local cmd=("$@")
  dc run --rm -T shell /usr/local/bin/lr-app-entrypoint.sh "${cmd[@]}"
}

exec_shell_command_interactive() {
  local cmd=("$@")
  dc run --rm shell /usr/local/bin/lr-app-entrypoint.sh "${cmd[@]}"
}

clean_data_preserving_tracked() {
  local rel_data_dir="${DATA_DIR#${ROOT_DIR}/}"
  if command -v git >/dev/null 2>&1 && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${ROOT_DIR}" clean -fdx -- "${rel_data_dir}"
  else
    find "${DATA_DIR}" -mindepth 1 -type f ! -name '.gitkeep' -delete
    find "${DATA_DIR}" -mindepth 1 -type l -delete
    find "${DATA_DIR}" -mindepth 1 -type d -empty -delete
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
  
  echo -e "${C_MAGENTA}${C_BOLD}⚙️  CURRENT CONFIGURATION:${C_RESET}"
  echo -e "  🆔 ${C_GRAY}Project:${C_RESET} ${C_BOLD}${COMPOSE_PROJECT_NAME:-lareferencia}${C_RESET}"
  echo -e "  🏷️  ${C_GRAY}Prefix:${C_RESET}  ${C_BOLD}${prefix}${C_RESET}"
  echo -e "  🔌 ${C_GRAY}Offset:${C_RESET}  ${C_YELLOW}${offset}${C_RESET}"
  echo -e "  🏗️  ${C_GRAY}Profile:${C_RESET} ${C_BLUE}${profile}${C_RESET}"
  echo
  print_module_status
  echo
}

execute_with_progress() {
    local cmd="$1"
    local label="$2"
    local log_file="/tmp/lareferencia-docker.log"
    
    rm -f "$log_file"
    # Execute command in background and capture PID
    eval "$cmd" > "$log_file" 2>&1 &
    local pid=$!
    
    local width=40
    local i=0
    while kill -0 $pid 2>/dev/null; do
        local progress=$(( (i % width) + 1 ))
        local remaining=$(( width - progress ))
        printf "\r  ${C_CYAN}${label}${C_RESET} ["
        printf "${C_GREEN}"
        for ((j=0; j<progress; j++)); do printf "━"; done
        printf "${C_GRAY}"
        for ((j=0; j<remaining; j++)); do printf " "; done
        printf "${C_RESET}] "
        
        case $((i % 4)) in
            0) printf "⠋" ;;
            1) printf "⠙" ;;
            2) printf "⠹" ;;
            3) printf "⠸" ;;
        esac
        
        i=$((i + 1))
        sleep 0.1
    done
    wait $pid
    local status=$?
    
    if [ $status -eq 0 ]; then
        printf "\r  ${C_GREEN}✅ ${label} Completed!%-60s${C_RESET}\n" " "
    else
        printf "\r  ${C_RED}❌ ${label} Failed! (See details below)%-60s${C_RESET}\n" " "
        echo -e "${C_GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_RED}${C_BOLD}ERROR LOG (Last 20 lines):${C_RESET}"
        tail -n 20 "$log_file"
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

check_prerequisites() {
  local docker_ok="${C_GREEN}✓${C_RESET}"
  local compose_ok="${C_GREEN}✓${C_RESET}"
  local daemon_ok="${C_GREEN}✓${C_RESET}"
  local errors=0

  if ! command -v docker >/dev/null 2>&1; then
    docker_ok="${C_RED}✗${C_RESET}"
    errors=$((errors + 1))
  fi

  if ! docker compose version >/dev/null 2>&1; then
    compose_ok="${C_RED}✗${C_RESET}"
    errors=$((errors + 1))
  fi

  if ! docker info >/dev/null 2>&1; then
    daemon_ok="${C_RED}✗${C_RESET}"
    errors=$((errors + 1))
  fi

  gum style --foreground 212 --border normal --border-foreground 212 --margin "0 2" --padding "0 1" \
    "System Checks:" \
    "  $docker_ok Docker Engine" \
    "  $compose_ok Docker Compose V2" \
    "  $daemon_ok Docker Daemon Running"

  if [ $errors -gt 0 ]; then
    gum style --foreground 204 "⚠️  Some prerequisites are missing. The platform might not start correctly."
    echo
  fi
}

print_module_status_columns() {
  local running_services
  running_services="$(dc ps --status running --services 2>/dev/null || true)"
  local blocks=()

  for module in "${ALL_MODULES[@]}"; do
    local state="$(get_module_state "${module}")"
    local color="245"
    local state_icon="○"
    [ "${state}" = "on" ] && { color="114"; state_icon="●"; }
    
    local module_upper
    module_upper=$(echo "$module" | tr '[:lower:]' '[:upper:]')

    # Build internal content using Bash newline literals
    local content="${state_icon} ${module_upper}"
    content="${content}"$'\n'"──────────────"
    
    for service in $(module_services "${module}"); do
      local s_icon="○"
      if printf "%s\n" "${running_services}" | grep -Fxq "${service}"; then
        s_icon="${C_GREEN}⚡${C_RESET}"
      else
        s_icon="${C_GRAY}○${C_RESET}"
      fi
      content="${content}"$'\n'" ${s_icon} ${service}"
    done
    
    # Single gum style call per module
    blocks+=("$(gum style --border normal --border-foreground 240 --padding "0 1" --margin "0 1" --width 20 --foreground "$color" "$content")")
  done

  gum join --horizontal "${blocks[@]}"
}

wizard_modules() {
  clear_screen
  draw_header
  
  local optional_modules=("vufind" "elastic" "watch")
  local pre_selected=()
  for m in "${optional_modules[@]}"; do
    if [ "$(get_module_state "${m}")" = "on" ]; then
      pre_selected+=("${m}")
    fi
  done

  local pre_selected_joined
  pre_selected_joined=$(IFS=,; echo "${pre_selected[*]}")

  echo -e "${C_BOLD}📦 MODULE MANAGEMENT${C_RESET}"
  echo -e "${C_GRAY}The 'core' module is always active.${C_RESET}\n"
  
  local choices
  choices=$(gum choose --no-limit --selected="${pre_selected_joined}" \
    --item.foreground 245 --selected.foreground 114 --cursor.foreground 80 \
    "${optional_modules[@]}")

  # Reset all optional modules to off
  for m in "${optional_modules[@]}"; do
    set_module_state "${m}" off
  done

  # Activate selected ones
  for m in ${choices}; do
    set_module_state "${m}" on
  done
  
  echo -e "\n${C_CYAN}Configuration updated.${C_RESET}"
  sleep 1
}

wizard_main() {
  while true; do
    clear_screen
    
    gum style \
      --foreground 80 --border-foreground 80 --border double \
      --align center --width 80 --margin "1 2" --padding "1 2" \
      "🐳 LA REFERENCIA PLATFORM" "Docker Management Wizard"

    check_prerequisites

    local prefix="$(get_env_var SERVICE_PREFIX "lareferencia")"
    local offset="$(get_env_var SERVICES_PORT_OFFSET "0")"
    local profile="$(get_env_var LR_BUILD_PROFILE "lareferencia")"
    
    # Status Table
    local status_text="Project: ${COMPOSE_PROJECT_NAME:-lareferencia} | Prefix: ${prefix} | Offset: ${offset} | Profile: ${profile}"
    gum style --foreground 176 "$status_text"
    echo

    print_module_status_columns
    echo

    gum style --foreground 80 --bold --underline "⚡ SELECT ACTION"
    echo

    local choice
    choice=$(gum choose \
      --item.bold --selected.bold --selected.background 80 --selected.foreground 232 \
      --cursor.bold --cursor.foreground 80 --height 15 \
      "🚀 Start Platform (up --build)" \
      "🛑 Stop Platform (down)" \
      "📦 Manage Modules (on/off)" \
      "📝 View Logs (follow)" \
      "🏷️ Change SERVICE_PREFIX" \
      "🔌 Change PORT_OFFSET" \
      "🏗️ Change BUILD_PROFILE" \
      "🛠️ Run Init-DB (migrations)" \
      "🧹 Reset Data (CLEAN ALL)" \
      "🚪 Exit")

    case "$choice" in
      "🚀 Start Platform (up --build)")
        echo -e "\n${C_GREEN}🚀 Starting the platform...${C_RESET}"
        execute_with_progress "\"${BASH_SOURCE[0]}\" up --build" "Platform Build & Start"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "🛑 Stop Platform (down)")
        echo -e "\n${C_RED}🛑 Stopping the platform...${C_RESET}"
        execute_with_progress "\"${BASH_SOURCE[0]}\" down" "Stopping Platform"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "📦 Manage Modules (on/off)")
        wizard_modules
        ;;
      "📝 View Logs (follow)")
        echo -e "\n${C_CYAN}📝 Showing logs (Ctrl+C to stop)...${C_RESET}"
        "${BASH_SOURCE[0]}" logs -f
        gum input --placeholder "Logs stopped. Press Enter to return to menu..." > /dev/null
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
      "🛠️ Run Init-DB (migrations)")
        echo -e "\n${C_MAGENTA}🛠️  Running database migrations...${C_RESET}"
        execute_with_progress "\"${BASH_SOURCE[0]}\" init-db" "Database Migrations"
        gum input --placeholder "Press Enter to continue..." > /dev/null
        ;;
      "🧹 Reset Data (CLEAN ALL)")
        echo
        gum style --foreground 204 --border double --border-foreground 204 --padding "0 1" "⚠️  DANGER ZONE: ALL DATA IN Docker/data WILL BE PERMANENTLY DELETED"
        if gum confirm "Are you absolutely sure you want to reset all persistent data?"; then
          "${BASH_SOURCE[0]}" reset-data --yes
          gum input --placeholder "Data reset completed. Press Enter to continue..." > /dev/null
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
  init-db              Migrate database
  reset-data           Clean Docker/data

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
    explicit_vufind_request=false
    requested_modules=()
    services=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --build) build_flag=true ;;
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
        modules+=(core)
        for m in "${requested_modules[@]}"; do validate_module_name "$m" && ! contains_item "$m" "${modules[@]-}" && modules+=("$m"); done
      else
        while IFS= read -r m; do [ -n "$m" ] && modules+=("$m"); done < <(enabled_modules)
      fi
      collect_from_modules "${modules[@]}"
      services=("${COLLECTED_SERVICES[@]}")
    else
      collect_profiles_for_services "${services[@]}"
    fi

    filter_vufind_services_if_checkout_missing "${explicit_vufind_request}" "${services[@]}"
    services=("${FILTERED_SERVICES[@]}")
    collect_profiles_for_services "${services[@]}"

    ensure_m2_cache_dir
    ensure_vufind_for_services "${services[@]}"

    if [ "${build_flag}" = true ]; then
      ensure_java_parent_modules_ready
      contains_item solr "${services[@]-}" && ensure_solr_build_context
      run_global_build
    fi

    args=(up -d)
    [ "${build_flag}" = true ] && args+=(--force-recreate)

    if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
      p_args=()
      for p in "${COLLECTED_PROFILES[@]}"; do p_args+=(--profile "$p"); done
      dc "${p_args[@]}" "${args[@]}" "${services[@]}"
    else
      dc "${args[@]}" "${services[@]}"
    fi

    [ "${build_flag}" = true ] && run_init_db
    ;;

  down)
    dc down --remove-orphans
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
    for p in "${COLLECTED_PROFILES[@]}"; do p_args+=(--profile "$p"); done
    
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
    ;;

  init-db)
    ensure_java_parent_modules_ready
    ensure_shell_service_running
    run_init_db "$@"
    ;;

  shell-interactive)
    ensure_java_parent_modules_ready
    ensure_shell_service_running
    exec_shell_command_interactive "$@"
    ;;

  reset-data)
    auto_yes=false
    [ "${1:-}" = "--yes" ] && auto_yes=true
    if [ "${auto_yes}" != true ]; then
      echo -e "${C_RED}This will clear data in Docker/data!${C_RESET}"
      read -r -p "Type RESET to confirm: " confirmation
      [ "${confirmation}" != "RESET" ] && exit 1
    fi
    dc down --remove-orphans || true
    clean_data_preserving_tracked
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

  *)
    usage
    exit 1
    ;;
esac
