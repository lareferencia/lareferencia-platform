#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
DEV_COMPOSE_FILE="${ROOT_DIR}/docker-compose.dev.yml"
BASE_ENV_FILE="${SCRIPT_DIR}/.env"
DEV_ENV_FILE="${SCRIPT_DIR}/.env.dev"
DEV_LOG_FILE="/tmp/lareferencia-docker-dev.log"

ALL_MODULES=(core solr harvester entity-rest shell vufind elastic watch oai)

# Keep the developer wizard visually aligned with docker.sh without importing it.
# docker.sh may already have downloaded gum into this local directory.
[ -x "${SCRIPT_DIR}/.bin/gum" ] && PATH="${SCRIPT_DIR}/.bin:${PATH}"
C_RESET=$(printf '\033[0m')
C_BOLD=$(printf '\033[1m')
C_BLUE=$(printf '\033[38;5;75m')
C_CYAN=$(printf '\033[38;5;80m')
C_GREEN=$(printf '\033[38;5;114m')
C_YELLOW=$(printf '\033[38;5;222m')
C_RED=$(printf '\033[38;5;204m')
C_MAGENTA=$(printf '\033[38;5;176m')
C_GRAY=$(printf '\033[38;5;245m')

die() { echo "Error: $*" >&2; exit 1; }
is_java_service() {
  case "$1" in harvester|entity-rest|shell|oai-pmh|db-init) return 0;; *) return 1;; esac
}
is_truthy() { case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in 1|true|on|yes) return 0;; *) return 1;; esac; }

ensure_gum() {
  command -v gum >/dev/null 2>&1 && return 0
  local version=0.15.0 os arch filename url temp_dir gum_binary
  case "$(uname -s)" in
    Darwin|Linux) os="$(uname -s)" ;;
    *) die 'Unsupported OS for gum; install gum manually or use command-line commands' ;;
  esac
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) die 'Unsupported architecture for gum; install gum manually or use command-line commands' ;;
  esac
  command -v curl >/dev/null 2>&1 || die 'curl is required to download gum; install gum manually or use command-line commands'
  filename="gum_${version}_${os}_${arch}.tar.gz"
  url="https://github.com/charmbracelet/gum/releases/download/v${version}/${filename}"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/lr-dev-gum.XXXXXX")"
  echo "Downloading gum v${version} for ${os}-${arch}..." >&2
  if ! curl -fsSL --connect-timeout 15 --max-time 120 "$url" -o "${temp_dir}/${filename}" ||
     ! tar -xzf "${temp_dir}/${filename}" -C "$temp_dir"; then
    rm -rf -- "$temp_dir"
    die 'Failed to download/extract gum; install gum manually or use command-line commands'
  fi
  gum_binary="$(find "$temp_dir" -type f -name gum -print -quit)"
  if [ -z "$gum_binary" ]; then
    rm -rf -- "$temp_dir"
    die 'The gum release archive contains no gum binary'
  fi
  mkdir -p "${SCRIPT_DIR}/.bin"
  chmod +x "$gum_binary"
  mv "$gum_binary" "${SCRIPT_DIR}/.bin/gum"
  rm -rf -- "$temp_dir"
  export PATH="${SCRIPT_DIR}/.bin:${PATH}"
}

ensure_dev_env() {
  if [ ! -f "${DEV_ENV_FILE}" ]; then
    # Keep this local-only file out of Git without changing tracked ignore files.
    if [ -d "${ROOT_DIR}/.git" ]; then
      local exclude_file="${ROOT_DIR}/.git/info/exclude"
      if [ -w "${exclude_file}" ]; then
        grep -qxF 'Docker/.env.dev' "${exclude_file}" 2>/dev/null || printf '\nDocker/.env.dev\n' >> "${exclude_file}"
      fi
    fi
    cat > "${DEV_ENV_FILE}" <<'EOF'
DEV_INSTANCE_MODE=isolated
SERVICE_PREFIX=lareferencia-dev
COMPOSE_PROJECT_NAME=lareferencia-dev
SERVICES_PORT_OFFSET=100
DEV_DATA_ROOT=./Docker/volume/dev/lareferencia-dev
LR_BUILD_PROFILE=lareferencia
DEV_WATCH_INTERVAL=2
DEV_COMPOSE_PROFILES=
EOF
  fi
}

module_key() {
  case "$1" in
    core) printf '%s\n' DEV_MODULE_CORE;; solr) printf '%s\n' DEV_MODULE_SOLR;;
    harvester) printf '%s\n' DEV_MODULE_HARVESTER;;
    entity-rest) printf '%s\n' DEV_MODULE_ENTITY_REST;; shell) printf '%s\n' DEV_MODULE_SHELL;;
    vufind) printf '%s\n' DEV_MODULE_VUFIND;; elastic) printf '%s\n' DEV_MODULE_ELASTIC;;
    watch) printf '%s\n' DEV_MODULE_WATCH;; oai) printf '%s\n' DEV_MODULE_OAI;;
  esac
}

module_default() {
  case "$1" in core|solr|harvester|vufind|oai) printf 'on\n';; *) printf 'off\n';; esac
}

module_state() {
  [ "$1" = core ] && { printf 'on\n'; return; }
  local key="$(module_key "$1")"
  if is_truthy "$(env_get "${key}" "$(module_default "$1")")"; then printf 'on\n'; else printf 'off\n'; fi
}

set_module_state() {
  [ "$1" = core ] && return 0
  env_set "$(module_key "$1")" "$2"
}

module_services() {
  case "$1" in
    core) printf 'postgres\n';; solr) printf 'solr\n';; harvester) printf 'harvester\nadmin-web-dev\nweb-gateway-dev\n';;
    entity-rest) printf 'entity-rest\n';; shell) printf 'shell\n';;
    vufind) printf 'vufind-db\nvufind-web\n';; elastic) printf 'elasticsearch\n';;
    watch) printf 'vufind-scss-watch\n';; oai) printf 'oai-pmh\n';;
  esac
}

module_profile() {
  case "$1" in shell) printf 'tools\n';; elastic) printf 'elastic\n';; watch) printf 'watch\n';; oai) printf 'oai\n';; esac
}

contains() { local needle="$1" item; shift; for item in "$@"; do [ "$item" = "$needle" ] && return 0; done; return 1; }

selected_services() {
  local modules=() module service profile
  for module in "${ALL_MODULES[@]}"; do [ "$(module_state "$module")" = on ] && modules+=("$module"); done
  if { contains harvester "${modules[@]}" || contains entity-rest "${modules[@]}" || contains shell "${modules[@]}"; } && ! contains core "${modules[@]}"; then modules+=(core); fi
  if { contains harvester "${modules[@]}" || contains shell "${modules[@]}" || contains vufind "${modules[@]}"; } && ! contains solr "${modules[@]}"; then modules+=(solr); fi
  DEV_SELECTED_SERVICES=()
  DEV_SELECTED_PROFILES=()
  for module in "${modules[@]}"; do
    while IFS= read -r service; do [ -n "$service" ] && ! contains "$service" "${DEV_SELECTED_SERVICES[@]-}" && DEV_SELECTED_SERVICES+=("$service"); done < <(module_services "$module")
    while IFS= read -r profile; do [ -n "$profile" ] && ! contains "$profile" "${DEV_SELECTED_PROFILES[@]-}" && DEV_SELECTED_PROFILES+=("$profile"); done < <(module_profile "$module")
  done
  local joined="$(IFS=,; echo "${DEV_SELECTED_PROFILES[*]-}")"
  env_set DEV_COMPOSE_PROFILES "$joined"
}

manage_modules() {
  local optional=(solr harvester entity-rest shell vufind elastic watch oai) choices module
  if command -v gum >/dev/null 2>&1; then
    local selected=(); for module in "${optional[@]}"; do [ "$(module_state "$module")" = on ] && selected+=("$module"); done
    local gum_args=(--no-limit)
    if [ "${#selected[@]}" -gt 0 ]; then
      local selected_joined
      selected_joined="$(IFS=,; echo "${selected[*]}")"
      gum_args+=("--selected=${selected_joined}")
    fi
    choices="$(gum choose "${gum_args[@]}" "${optional[@]}")"
  else
    echo "Modules currently enabled:"; for module in "${optional[@]}"; do echo "  ${module}: $(module_state "$module")"; done
    printf 'Enter modules to enable (space-separated): '; read -r choices
  fi
  for module in "${optional[@]}"; do set_module_state "$module" off; done
  for module in ${choices:-}; do set_module_state "$module" on; done
  if [ "$(module_state harvester)" = on ] || [ "$(module_state vufind)" = on ]; then set_module_state solr on; fi
}

env_get() {
  local key="$1" default_value="$2"
  local value
  value="$(awk -F= -v k="${key}" '$1 == k {v=$2} END {print v}' "${DEV_ENV_FILE}" 2>/dev/null || true)"
  printf '%s\n' "${value:-$default_value}"
}

env_set() {
  local key="$1" value="$2" tmp_file="${DEV_ENV_FILE}.tmp"
  if grep -qE "^${key}=" "${DEV_ENV_FILE}"; then
    sed -E "s|^${key}=.*$|${key}=${value}|" "${DEV_ENV_FILE}" > "${tmp_file}"
    mv "${tmp_file}" "${DEV_ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${DEV_ENV_FILE}"
  fi
}

base_env_get() {
  local key="$1" default_value="$2" value
  value="$(awk -F= -v k="${key}" '$1 == k {v=$2} END {print v}' "${BASE_ENV_FILE}" 2>/dev/null || true)"
  printf '%s\n' "${value:-$default_value}"
}

sync_ports() {
  local mode offset key base_port base_value
  mode="$(env_get DEV_INSTANCE_MODE isolated)"
  offset="$(env_get SERVICES_PORT_OFFSET 0)"
  [[ "${offset}" =~ ^[0-9]+$ ]] || offset=0
  local port_keys=(LR_PORT_VUFIND_WEB LR_PORT_VUFIND_DB LR_PORT_SOLR LR_PORT_POSTGRES LR_PORT_HARVESTER LR_PORT_ENTITY_REST LR_PORT_ELASTIC_9200 LR_PORT_ELASTIC_9300 LR_PORT_OAI LR_PORT_GATEWAY)
  local base_ports=(8080 3307 8983 5432 8090 8094 9200 9300 8096 8088)
  for i in "${!port_keys[@]}"; do
    key="${port_keys[$i]}"; base_port="${base_ports[$i]}"
    if [ "${mode}" = normal ]; then
      base_value="$(base_env_get "${key}" "${base_port}")"
      env_set "${key}" "${base_value}"
    else
      env_set "${key}" "$((base_port + offset))"
    fi
  done
}

select_instance() {
  local selected="${1:-}"
  if [ -z "${selected}" ]; then
    if command -v gum >/dev/null 2>&1; then
      selected="$(gum choose 'isolated (recommended)' 'normal (shared data and ports)')"
    else
      printf 'Use isolated developer instance? [Y/n] '
      read -r answer
      case "$(printf '%s' "${answer:-y}" | tr '[:upper:]' '[:lower:]')" in
        y|yes) selected='isolated' ;;
        n|no) selected='normal' ;;
        *) die "Please answer y or n" ;;
      esac
    fi
  fi
  case "${selected}" in
    isolated*|isolated)
      env_set DEV_INSTANCE_MODE isolated
      env_set SERVICE_PREFIX lareferencia-dev
      env_set COMPOSE_PROJECT_NAME lareferencia-dev
      env_set SERVICES_PORT_OFFSET 100
      env_set DEV_DATA_ROOT ./Docker/volume/dev/lareferencia-dev
      sync_ports
      ;;
    normal*|normal)
      env_set DEV_INSTANCE_MODE normal
      env_set SERVICE_PREFIX "$(awk -F= '$1=="SERVICE_PREFIX" {v=$2} END {print v}' "${BASE_ENV_FILE}" 2>/dev/null || true)"
      env_set COMPOSE_PROJECT_NAME "$(awk -F= '$1=="COMPOSE_PROJECT_NAME" {v=$2} END {print v}' "${BASE_ENV_FILE}" 2>/dev/null || true)"
      env_set SERVICES_PORT_OFFSET "$(awk -F= '$1=="SERVICES_PORT_OFFSET" {v=$2} END {print v}' "${BASE_ENV_FILE}" 2>/dev/null || true)"
      env_set DEV_DATA_ROOT ./Docker/volume
      sync_ports
      ;;
    *) die "Unknown instance mode: ${selected}" ;;
  esac
}

dc() {
  ensure_dev_env
  sync_ports
  local args=(docker compose -f "${BASE_COMPOSE_FILE}" -f "${DEV_COMPOSE_FILE}")
  [ -f "${BASE_ENV_FILE}" ] && args+=(--env-file "${BASE_ENV_FILE}")
  args+=(--env-file "${DEV_ENV_FILE}")
  local profiles="$(env_get DEV_COMPOSE_PROFILES '')" profile
  IFS=, read -ra profile_list <<< "${profiles}"
  for profile in "${profile_list[@]-}"; do [ -n "${profile}" ] && args+=(--profile "${profile}"); done
  "${args[@]}" "$@"
}

module_for() {
  case "$1" in
    harvester) printf '%s\n' lareferencia-lrharvester-app ;;
    entity-rest) printf '%s\n' lareferencia-entity-rest ;;
    shell|db-init) printf '%s\n' lareferencia-shell ;;
    oai-pmh) printf '%s\n' lareferencia-oai-pmh ;;
    *) return 1 ;;
  esac
}

compile_service() {
  local service="$1" module profile
  [ "${service}" = all ] && { compile_all; return; }
  is_java_service "${service}" || die "${service} is not a Java application"
  module="$(module_for "${service}")"
  if [ "${service}" = harvester ]; then
    compile_frontend
    compile_dashboard
  fi
  profile="$(env_get LR_BUILD_PROFILE lareferencia)"
  echo "Compiling ${module} and local dependencies..."
  dc --profile developer-builder run --rm --no-deps maven-builder -pl "${module}" -am install -DskipTests -Dmaven.javadoc.skip=true -Dspring-boot.repackage.executable=false "-P${profile}"
}

compile_frontend() {
  echo "Compiling React admin web and publishing it to harvester/admin-static..."
  dc --profile developer-builder run --rm --no-deps maven-builder -f lareferencia-lrharvester-admin-web/pom.xml package
}

compile_dashboard() {
  echo "Compiling Angular dashboard and publishing it to harvester/dashboard-static..."
  dc --profile developer-builder run --rm --no-deps maven-builder -f lareferencia-repository-dashboard/pom.xml package
}

compile_all() {
  local profile="$(env_get LR_BUILD_PROFILE lareferencia)"
  local java_modules='lareferencia-oclc-harvester,lareferencia-core-lib,lareferencia-entity-lib,lareferencia-indexing-filters-lib,lareferencia-shell-entity-plugin,lareferencia-shell,lareferencia-dark-lib,lareferencia-lrharvester-app,lareferencia-entity-rest,lareferencia-oai-pmh'
  echo "Compiling Java modules..."
  dc --profile developer-builder run --rm --no-deps maven-builder -pl "${java_modules}" -am install -DskipTests -Dmaven.javadoc.skip=true -Dspring-boot.repackage.executable=false "-P${profile}"
  compile_frontend
  compile_dashboard
}

compile_selected_java() {
  local service needs_db_init=false shell_compiled=false
  for service in "${DEV_SELECTED_SERVICES[@]}"; do
    if is_java_service "${service}"; then
      compile_service "${service}"
      [ "${service}" = shell ] && shell_compiled=true
    fi
    # Harvester and the REST apps depend on db-init at startup. db-init runs
    # the Spring Shell JAR, so it must be built with the selected Maven profile
    # even when the optional interactive shell module is disabled in the UI.
    case "${service}" in harvester|entity-rest) needs_db_init=true ;; esac
  done
  if [ "${needs_db_init}" = true ] && [ "${shell_compiled}" = false ]; then
    compile_service shell
  fi
}

rebuild_platform() {
  selected_services
  [ "${#DEV_SELECTED_SERVICES[@]}" -gt 0 ] || die 'No developer modules selected'
  ensure_vufind_for_services "${DEV_SELECTED_SERVICES[@]}"
  echo "Rebuilding Java applications, Admin Web, and Repository Dashboard..."
  compile_all
  echo "Starting local developer services with the rebuilt platform..."
  dc up -d --build "${DEV_SELECTED_SERVICES[@]}"
}

restart_service() {
  local service="$1"
  ensure_vufind_for_services "$service"
  # The application JAR is mounted from the host. Restarting reruns the
  # developer entrypoint and loads the new JAR without replacing the container.
  if dc ps -a --services 2>/dev/null | grep -Fxq "${service}"; then
    dc restart "${service}"
  else
    dc up -d --no-deps "${service}"
  fi
}

run_spring_shell() {
  # The Spring Shell container normally stays idle so docker exec remains available.
  # Start a one-off attached container for an actual interactive command session.
  dc up -d postgres solr
  dc --profile tools run --rm --no-deps -e SHELL_IDLE=false shell "$@"
}

rebuild_service() {
  local service="$1"
  ensure_vufind_for_services "$service"
  if [ "${service}" = frontend ] || [ "${service}" = admin-web ]; then
    compile_frontend
    restart_service harvester
  elif [ "${service}" = dashboard ]; then
    compile_dashboard
    restart_service harvester
  elif is_java_service "${service}"; then
    compile_service "${service}"
    restart_service "${service}"
  elif [ "${service}" = solr ] || [ "${service}" = vufind-web ]; then
    dc build "${service}"
    # Image-based services must be recreated to run the newly built image;
    # a plain restart keeps the container on the old image. --no-deps leaves
    # the rest of the stack untouched.
    dc up -d --no-deps "${service}"
  else
    die "rebuild supports Java services, solr, and vufind-web"
  fi
}

watch_service() {
  local service="$1" module stamp interval current watch_root
  is_java_service "${service}" || die "watch supports Java services only"
  module="$(module_for "${service}")"
  interval="$(env_get DEV_WATCH_INTERVAL 2)"
  stamp="$(mktemp /tmp/lr-dev-watch.XXXXXX)"
  trap 'rm -f "${stamp}"' EXIT INT TERM
  touch "${stamp}"
  echo "Watching ${module}; press Ctrl-C to stop."
  while true; do
    watch_root="${ROOT_DIR}/${module}"
    if [ "${service}" = harvester ]; then
      current="$(find "${ROOT_DIR}/lareferencia-lrharvester-admin-web" "${ROOT_DIR}/lareferencia-repository-dashboard" "${watch_root}" -type d \( -name node_modules -o -name node -o -name dist -o -name target \) -prune -o -type f \( -path '*/src/*' -o -name pom.xml -o -name package.json -o -name package-lock.json \) -newer "${stamp}" -print -quit)"
    else
      current="$(find "${watch_root}" -type f \( -path '*/src/*' -o -name pom.xml \) -newer "${stamp}" -print -quit)"
    fi
    if [ -n "${current}" ]; then
      echo "Change detected: ${current}"
      if [[ "${current}" == "${ROOT_DIR}/lareferencia-lrharvester-admin-web/"* ]]; then
        if compile_frontend && restart_service harvester; then touch "${stamp}"; else echo "Frontend build failed; keeping the current container." >&2; fi
      elif [[ "${current}" == "${ROOT_DIR}/lareferencia-repository-dashboard/"* ]]; then
        if compile_dashboard && restart_service harvester; then touch "${stamp}"; else echo "Dashboard build failed; keeping the current container." >&2; fi
      elif rebuild_service "${service}"; then
        touch "${stamp}"
      else
        echo "Build failed; keeping the current container." >&2
      fi
    fi
    sleep "${interval}"
  done
}

reload_solr() {
  echo "Restarting Solr to apply local core changes..."
  restart_service solr
}

clean_developer_instance() {
  local confirmed="${1:-false}" mode data_root data_path project image
  mode="$(env_get DEV_INSTANCE_MODE isolated)"
  [ "$mode" = isolated ] || die 'clean is blocked while DEV_INSTANCE_MODE is normal'
  data_root="$(env_get DEV_DATA_ROOT ./Docker/volume/dev/lareferencia-dev)"
  case "$data_root" in
    ./Docker/volume/dev/*) data_path="${ROOT_DIR}/${data_root#./}" ;;
    "${ROOT_DIR}"/Docker/volume/dev/*) data_path="$data_root" ;;
    *) die "Refusing to delete unexpected developer data path: ${data_root}" ;;
  esac
  if [ "$confirmed" != true ]; then
    echo 'This permanently removes the isolated developer containers, volumes, data, Maven cache and runtime image.' >&2
    if command -v gum >/dev/null 2>&1; then
      gum confirm 'Delete all isolated developer data?' || return 0
    else
      printf 'Type DELETE to continue: '; read -r answer; [ "$answer" = DELETE ] || return 0
    fi
  fi
  project="$(env_get COMPOSE_PROJECT_NAME lareferencia-dev)"
  image="lareferencia/app-runtime-dev:$(env_get LR_BUILD_PROFILE lareferencia)"
  dc down --volumes --remove-orphans || true
  docker volume rm "${project}_lr-maven-cache-dev" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  if [ -d "$data_path" ]; then
    rm -rf -- "$data_path"
  fi
  echo "Developer cleanup completed for ${project}."
}

start_selected() {
  selected_services
  [ "${#DEV_SELECTED_SERVICES[@]}" -gt 0 ] || die 'No developer modules selected'
  ensure_vufind_for_services "${DEV_SELECTED_SERVICES[@]}"
  echo "Compiling selected Java services before startup..."
  compile_selected_java
  echo "Starting local developer services with the newly compiled local artifacts."
  dc up -d --build "${DEV_SELECTED_SERVICES[@]}"
}

ensure_vufind_for_services() {
  local service needed=false checkout_dir repo_url repo_ref
  for service in "$@"; do
    case "$service" in vufind-web|vufind-scss-watch) needed=true ;; esac
  done
  [ "$needed" = true ] || return 0
  [ ! -f "${ROOT_DIR}/vufind/composer.json" ] || return 0
  [ ! -e "${ROOT_DIR}/vufind/.git" ] || die 'VuFind checkout is incomplete; restore its composer.json before starting it'
  repo_url="${VUFIND_REPO_URL:-$(base_env_get VUFIND_REPO_URL https://github.com/vufind-org/vufind)}"
  repo_ref="${VUFIND_REF:-$(base_env_get VUFIND_REF v11.0.1)}"
  checkout_dir="$(mktemp -d "${TMPDIR:-/tmp}/lr-dev-vufind.XXXXXX")"
  echo "Preparing VuFind ${repo_ref}..."
  if ! git clone --depth 1 --branch "$repo_ref" --single-branch "$repo_url" "${checkout_dir}/checkout"; then
    rm -rf -- "$checkout_dir"
    die 'Failed to clone VuFind'
  fi
  # Docker can create local/ and vendor/ before the source is cloned.
  # Preserve those files while filling in the missing checkout.
  mkdir -p "${ROOT_DIR}/vufind"
  cp -an "${checkout_dir}/checkout/." "${ROOT_DIR}/vufind/"
  rm -rf -- "$checkout_dir"
  [ -f "${ROOT_DIR}/vufind/composer.json" ] || die 'VuFind checkout contains no composer.json'
}

clear_screen() { printf '\033c'; }

get_check_status() {
  local docker_ok="${C_GREEN}✓${C_RESET} Docker" compose_ok="${C_GREEN}✓${C_RESET} Compose" daemon_ok="${C_GREEN}✓${C_RESET} Daemon"
  command -v docker >/dev/null 2>&1 || docker_ok="${C_RED}✗${C_RESET} Docker"
  docker compose version >/dev/null 2>&1 || compose_ok="${C_RED}✗${C_RESET} Compose"
  docker info >/dev/null 2>&1 || daemon_ok="${C_RED}✗${C_RESET} Daemon"
  printf '%s|%s|%s' "$docker_ok" "$compose_ok" "$daemon_ok"
}

get_service_port() {
  local service="$1" offset="$(env_get SERVICES_PORT_OFFSET 0)"
  offset="${offset//[^0-9]/}"; [ -n "$offset" ] || offset=0
  case "$service" in
    vufind-web) printf ':%s' "$((8080 + offset))" ;; vufind-db) printf ':%s' "$((3307 + offset))" ;;
    solr) printf ':%s' "$((8983 + offset))" ;; postgres) printf ':%s' "$((5432 + offset))" ;;
    harvester) printf ':%s' "$((8090 + offset))" ;;
    entity-rest) printf ':%s' "$((8094 + offset))" ;; elasticsearch) printf ':%s' "$((9200 + offset))" ;;
    oai-pmh) printf ':%s' "$((8096 + offset))" ;; web-gateway-dev) printf ':%s' "$((8088 + offset))" ;;
  esac
}

print_module_status_columns() {
  local running_services module state color icon module_upper services service content port_info s_icon
  running_services="$(dc ps --status running --services 2>/dev/null || true)"
  local blocks=()
  for module in "${ALL_MODULES[@]}"; do
    [ "$module" = harvester ] && continue
    state="$(module_state "$module")"; color=245; icon='○'
    [ "$state" = on ] && { color=114; icon='●'; }
    module_upper="$(printf '%s' "$module" | tr '[:lower:]' '[:upper:]')"
    services="$(module_services "$module")"
    if [ "$module" = core ]; then module_upper='CORE & HARVESTER'; services="${services}"$'\n'"$(module_services harvester)"; fi
    content="${icon} ${module_upper}"$'\n──────────────'
    while IFS= read -r service; do
      [ -n "$service" ] || continue
      s_icon="${C_GRAY}○${C_RESET}"; port_info=''
      if printf '%s\n' "$running_services" | grep -Fxq "$service"; then
        s_icon="${C_GREEN}⚡${C_RESET}"; port_info="${C_YELLOW}$(get_service_port "$service")${C_RESET}"
      fi
      content="${content}"$'\n'" ${s_icon} ${service}${port_info}"
    done <<< "$services"
    blocks+=("$(gum style --padding '0 1' --margin '0 2' --width 28 --foreground "$color" "$content")")
  done
  local row1=("${blocks[@]:0:3}") row2=("${blocks[@]:3:3}") row3=("${blocks[@]:6:3}")
  gum join --vertical "$(gum join --horizontal "${row1[@]}")" "$(gum join --horizontal "${row2[@]}")" "$(gum join --horizontal "${row3[@]}")"
}

wait_for_key() {
  if command -v gum >/dev/null 2>&1; then gum input --placeholder 'Press Enter to continue...' >/dev/null; else read -r _; fi
}

execute_with_progress() {
  local label="$1"; shift
  rm -f "$DEV_LOG_FILE"
  echo -e "${C_CYAN}🚀 ${label}...${C_RESET}"
  # Keep the complete build output visible while retaining a full log copy.
  set +e
  "$@" 2>&1 | tee "$DEV_LOG_FILE"
  local status="${PIPESTATUS[0]}"
  set -e
  if [ "$status" -eq 0 ]; then
    echo -e "${C_GREEN}✅ ${label} Completed!${C_RESET}"
  else
    echo -e "${C_RED}❌ ${label} Failed!${C_RESET}"
    echo -e "${C_RED}${C_BOLD}ERROR LOG (Last 20 lines):${C_RESET}"
    tail -n 20 "$DEV_LOG_FILE" 2>/dev/null || true
    echo -e "${C_YELLOW}Full log available at: ${DEV_LOG_FILE}${C_RESET}"
  fi
  return "$status"
}

wizard() {
  ensure_gum
  ensure_dev_env
  while true; do
    clear_screen
    local checks c1 c2 c3 revision mode prefix offset profile data_root
    checks="$(get_check_status)"; IFS='|' read -r c1 c2 c3 <<< "$checks"
    revision="$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo unknown)"
    mode="$(env_get DEV_INSTANCE_MODE isolated)"; prefix="$(env_get SERVICE_PREFIX lareferencia-dev)"; offset="$(env_get SERVICES_PORT_OFFSET 100)"; profile="$(env_get LR_BUILD_PROFILE lareferencia)"; data_root="$(env_get DEV_DATA_ROOT '')"
    gum style --foreground 80 --border-foreground 80 --border double --align center --width 80 --margin '1 2' --padding '1 2' \
      '🐳 LA REFERENCIA PLATFORM' 'Developer Docker Wizard' "Rev: ${revision}" '' "$(gum join --horizontal --align center "$c1   " "$c2   " "$c3")"
    gum style --foreground 176 "Project: ${COMPOSE_PROJECT_NAME:-lareferencia-dev} | Prefix: ${prefix} | Offset: ${offset} | Profile: ${profile} | Instance: ${mode}"
    echo
    print_module_status_columns
    echo
    gum style --foreground 80 --bold --underline '⚡ SELECT ACTION'
    echo
    local options=(
      '🚀 Start Developer Platform' '🏗️ Rebuild Full Platform' '🔄 Build all platform applications' '📦 Manage Modules (on/off)'
      '♻️ Rebuild harvester' '♻️ Rebuild admin web' '♻️ Rebuild dashboard' '♻️ Rebuild entity-rest'
      '♻️ Rebuild oai-pmh' '🔁 Restart VuFind'
      '🔁 Reload Solr' '📝 View Logs (follow)' '💻 Enter Container Shell'
      '🐚 Open Interactive Spring Shell' '🛠️ Run Init-DB (migrations)' '🧹 Clean Developer Instance' '🧩 Choose instance' '🚪 Exit'
    ) choice
    choice="$(gum choose --item.bold --selected.bold --selected.background 80 --selected.foreground 232 --cursor.bold --cursor.foreground 80 "${options[@]}")"
    case "${choice}" in
      '🚀 Start Developer Platform') execute_with_progress 'Developer Platform Start' start_selected || true; wait_for_key ;;
      '🏗️ Rebuild Full Platform') execute_with_progress 'Full Platform Rebuild' rebuild_platform || true; wait_for_key ;;
      '🔄 Build all platform applications') execute_with_progress 'Platform Applications Build' compile_all || true; wait_for_key ;;
      '📦 Manage Modules (on/off)') manage_modules ;;
      '♻️ Rebuild harvester') execute_with_progress 'Harvester Rebuild' rebuild_service harvester || true; wait_for_key ;;
      '♻️ Rebuild admin web') execute_with_progress 'Admin Web Rebuild' rebuild_service frontend || true; wait_for_key ;;
      '♻️ Rebuild dashboard') execute_with_progress 'Dashboard Rebuild' rebuild_service dashboard || true; wait_for_key ;;
      '♻️ Rebuild entity-rest') execute_with_progress 'Entity REST Rebuild' rebuild_service entity-rest || true; wait_for_key ;;
      '♻️ Rebuild oai-pmh') execute_with_progress 'OAI-PMH Rebuild' rebuild_service oai-pmh || true; wait_for_key ;;
      '🔁 Restart VuFind') execute_with_progress 'VuFind Restart' restart_service vufind-web || true; wait_for_key ;;
      '🔁 Reload Solr') execute_with_progress 'Solr Reload' reload_solr || true; wait_for_key ;;
      '📝 View Logs (follow)') dc logs -f --tail=100 || true; wait_for_key ;;
      '💻 Enter Container Shell') dc exec harvester bash || dc exec harvester sh || true ;;
      '🐚 Open Interactive Spring Shell') run_spring_shell || true ;;
      '🛠️ Run Init-DB (migrations)') execute_with_progress 'Database Migrations' dc run --rm --no-deps db-init database_migrate || true; wait_for_key ;;
      '🧹 Clean Developer Instance') clean_developer_instance; wait_for_key ;;
      '🧩 Choose instance') select_instance ;;
      '🚪 Exit'|'' ) return ;;
    esac
  done
}

usage() {
  cat <<'EOF'
Usage: ./Docker/docker-dev.sh <command> [service]

Commands:
  wizard                 Interactive developer wizard
  instance [isolated|normal]
  up [service...]        Start the developer platform or selected services
  down                   Stop and remove developer containers
  clean [--yes]          Permanently remove all isolated developer artifacts
  build <service|all|frontend|dashboard> Compile Java JARs or a frontend
  rebuild-platform       Recompile Java and frontend, then restart selected services
  restart <service>      Recreate one service without dependencies
  rebuild <service>      Compile/rebuild and recreate one service
  watch <service>        Watch Java sources and rebuild on change
  frontend-dev            Start or restart the live Vite admin web server
  reload solr            Restart Solr after core changes
  logs [service]         Follow logs
  shell [service]        Open a shell (default: harvester)
  lrshell [command...]   Open an interactive Spring Shell or run shell commands with a TTY
  ps                     Show service status
  init-db                Run database migrations
EOF
}

ensure_dev_env
command="${1:-wizard}"; shift || true
case "${command}" in
  wizard) wizard ;;
  instance) select_instance "${1:-}" ;;
  up)
    if [ "$#" -eq 0 ]; then
      start_selected
    else
      ensure_vufind_for_services "$@"
      for service in "$@"; do
        is_java_service "${service}" && compile_service "${service}"
      done
      dc up -d --build "$@"
    fi
    ;;
  down) dc down "$@" ;;
  clean) [ "$#" -le 1 ] || die 'clean accepts only --yes'; [ "${1:-}" = --yes ] && clean_developer_instance true || clean_developer_instance false ;;
  ps) dc ps ;;
  logs) dc logs -f --tail=100 "$@" ;;
  shell) dc exec "${1:-harvester}" bash || dc exec "${1:-harvester}" sh ;;
  lrshell) run_spring_shell "$@" ;;
  init-db) dc run --rm --no-deps db-init database_migrate ;;
  rebuild-platform) rebuild_platform ;;
  build)
    [ "$#" -eq 1 ] || die 'build requires a service or all'
    case "$1" in frontend|admin-web) compile_frontend ;; dashboard) compile_dashboard ;; all) compile_all ;; *) compile_service "$1" ;; esac
    ;;
  restart) [ "$#" -eq 1 ] || die 'restart requires a service'; restart_service "$1" ;;
  rebuild) [ "$#" -eq 1 ] || die 'rebuild requires a service'; rebuild_service "$1" ;;
  frontend-dev)
    dc up -d harvester web-gateway-dev admin-web-dev
    ;;
  watch) [ "$#" -eq 1 ] || die 'watch requires a Java service'; watch_service "$1" ;;
  reload) [ "${1:-}" = solr ] || die 'only reload solr is supported'; reload_solr ;;
  help|-h|--help) usage ;;
  *) die "Unknown command: ${command}" ;;
esac
