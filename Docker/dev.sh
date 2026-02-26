#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
DATA_DIR="${ROOT_DIR}/Docker/data"
ENV_FILE="${ROOT_DIR}/.env"

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


dc() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

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

set_env_var() {
  local key="$1"
  local value="$2"
  local file="$3"

  touch "${file}"
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
    sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*$|${key}=${value}|g" "${file}"
    rm -f "${file}.bak"
  else
    printf "%s=%s\n" "${key}" "${value}" >> "${file}"
  fi
}

get_env_var() {
  local key="$1"
  local default_value="$2"
  local value=""

  if [ -f "${ENV_FILE}" ]; then
    value="$(awk -F= -v k="${key}" '$1 ~ "^[[:space:]]*"k"[[:space:]]*$" {v=$2} END {gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/^"|"$/, "", v); print v}' "${ENV_FILE}" || true)"
  fi

  if [ -z "${value}" ]; then
    value="${default_value}"
  fi
  printf "%s\n" "${value}"
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
  echo "Módulo inválido: ${module}. Usa: ${ALL_MODULES[*]}" >&2
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
    echo "El módulo core no se puede desactivar." >&2
    return 1
  fi

  key="$(module_env_key "${module}")"
  set_env_var "${key}" "${state}" "${ENV_FILE}"
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
  local dst_import="${ROOT_DIR}/Docker/solr/import"
  local dst_jars="${ROOT_DIR}/Docker/solr/jars"

  if [ ! -d "${src_import}" ]; then
    echo "No existe fuente de import en ${src_import}" >&2
    exit 1
  fi

  if [ ! -d "${src_jars}" ]; then
    echo "No existe fuente de jars en ${src_jars}" >&2
    exit 1
  fi

  echo "Sincronizando Docker/solr/import desde vufind/import..."
  rm -rf "${dst_import}"
  mkdir -p "${dst_import}"
  cp -a "${src_import}/." "${dst_import}/"

  echo "Sincronizando Docker/solr/jars desde vufind/solr/vufind/jars..."
  rm -rf "${dst_jars}"
  mkdir -p "${dst_jars}"
  cp -a "${src_jars}/." "${dst_jars}/"

  echo "Sync Solr completado."
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

  echo "No se encontró el directorio ${ROOT_DIR}/vufind."

  if [ -t 0 ]; then
    read -r -p "Repositorio GitHub de VuFind [${repo_url}]: " input_repo
    if [ -n "${input_repo}" ]; then
      repo_url="${input_repo}"
    fi

    read -r -p "Branch/tag de VuFind [${repo_ref}]: " input_ref
    if [ -n "${input_ref}" ]; then
      repo_ref="${input_ref}"
    fi
  else
    echo "Sin terminal interactiva; usando defaults:"
    echo "  repo=${repo_url}"
    echo "  ref=${repo_ref}"
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "git no está disponible en PATH; no se puede clonar VuFind." >&2
    exit 1
  fi

  echo "Clonando VuFind: ${repo_url} (${repo_ref})..."
  git clone --branch "${repo_ref}" --single-branch "${repo_url}" "${ROOT_DIR}/vufind"
  cloned_vufind=true

  if [ "${cloned_vufind}" = true ]; then
    echo "Sincronizando assets Solr (import/jars) desde VuFind..."
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
    echo "VuFind no está clonado; se omiten servicios: ${skipped[*]}."
    echo "Para incluirlos explícitamente: ./Docker/dev.sh vufind up  (o ./Docker/dev.sh up --vufind)"
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
      echo "Assets Solr faltantes/incompletos; sincronizando desde vufind/..."
      sync_solr_assets_from_vufind
    else
      echo "Aviso: Docker/solr/import o Docker/solr/jars está vacío. Solr compilará con placeholders." >&2
    fi
  fi
}

refresh_solr_for_vufind_assets() {
  ensure_vufind_checkout
  sync_solr_assets_from_vufind
  echo "Recreando servicio solr para aplicar jars/import de VuFind..."
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
    echo "Faltan submódulos Java inicializados (pom.xml ausente):" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Ejecuta: ./githelper pull" >&2
    return 1
  fi

  return 0
}

wait_postgres_ready() {
  local tries=0
  while [ "${tries}" -lt 60 ]; do
    if dc exec -T postgres pg_isready -U lrharvester >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  return 1
}

database_exists() {
  local exists
  exists="$(dc exec -T postgres psql -U lrharvester -tAc "SELECT 1 FROM pg_database WHERE datname='lrharvester' LIMIT 1;" 2>/dev/null | tr -d '[:space:]' || true)"
  [ "${exists}" = "1" ]
}

run_init_db() {
  local build_mode="$1"

  ensure_java_parent_modules_ready

  ensure_shell_service_running "${build_mode}"

  if database_exists; then
    echo "BD lrharvester ya existe; ejecutando init-db para asegurar schema actualizado."
  else
    echo "BD lrharvester no existe; ejecutando init-db."
  fi

  exec_shell_command_noninteractive "${build_mode}" database_migrate
}

ensure_shell_service_running() {
  local build_mode="$1"

  ensure_m2_cache_dir
  dc up -d postgres solr
  if ! wait_postgres_ready; then
    echo "PostgreSQL no quedó listo a tiempo; no se pudo iniciar shell." >&2
    return 1
  fi

  if ! dc --profile tools ps --status running --services 2>/dev/null | grep -Fxq shell; then
    BUILD_ON_START="${build_mode}" SHELL_IDLE=true dc --profile tools up -d shell
  fi
}

exec_shell_command_noninteractive() {
  local build_mode="$1"
  shift || true
  local cmd=("$@")

  dc --profile tools exec -T \
    -e BUILD_ON_START="${build_mode}" \
    -e SHELL_IDLE=false \
    shell /usr/local/bin/lr-app-entrypoint.sh "${cmd[@]}"
}

exec_shell_command_interactive() {
  local build_mode="$1"
  shift || true
  local cmd=("$@")

  dc --profile tools exec \
    -e BUILD_ON_START="${build_mode}" \
    -e SHELL_IDLE=false \
    shell /usr/local/bin/lr-app-entrypoint.sh "${cmd[@]}"
}

is_git_repo_available() {
  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi
  git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

clean_data_preserving_tracked() {
  local rel_data_dir
  local pending

  rel_data_dir="${DATA_DIR#${ROOT_DIR}/}"

  if is_git_repo_available; then
    git -C "${ROOT_DIR}" clean -fdx -- "${rel_data_dir}"
    pending="$(git -C "${ROOT_DIR}" clean -ndx -- "${rel_data_dir}" || true)"
    if [ -n "${pending}" ]; then
      echo "Quedaron rutas sin limpiar en ${DATA_DIR}:" >&2
      echo "${pending}" >&2
      return 1
    fi
    return 0
  fi

  find "${DATA_DIR}" -mindepth 1 -type f ! -name '.gitkeep' -delete
  find "${DATA_DIR}" -mindepth 1 -type l -delete
  find "${DATA_DIR}" -mindepth 1 -type d -empty -delete
}

ensure_m2_cache_dir() {
  mkdir -p "${ROOT_DIR}/Docker/data/m2/repository"
}

get_current_theme() {
  local theme=""
  theme="$(get_env_var VUFIND_THEME "")"

  if [ -z "${theme}" ] && [ -f "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" ]; then
    theme="$(awk -F= '/^[[:space:]]*theme[[:space:]]*=/ {gsub(/[[:space:]"]/, "", $2); print $2; exit}' "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" || true)"
  fi

  if [ -z "${theme}" ]; then
    theme="bootstrap5"
  fi
  printf "%s\n" "${theme}"
}

print_module_status() {
  local running_services
  local module
  local state
  local service
  local service_states
  local status
  local first

  running_services="$(dc ps --status running --services 2>/dev/null || true)"

  echo "Módulos disponibles:"
  for module in "${ALL_MODULES[@]}"; do
    state="$(get_module_state "${module}")"
    printf -- "- %s [%s]\n" "${module}" "${state}"

    service_states=""
    first=true
    for service in $(module_services "${module}"); do
      status="off"
      if printf "%s\n" "${running_services}" | grep -Fxq "${service}"; then
        status="on"
      fi

      if [ "${first}" = true ]; then
        service_states="${service}:${status}"
        first=false
      else
        service_states="${service_states}, ${service}:${status}"
      fi
    done

    echo "  servicios: ${service_states}"
  done
}

print_module_status_one() {
  local module="$1"
  local running_services
  local state
  local service
  local service_states
  local status
  local first

  validate_module_name "${module}"
  running_services="$(dc ps --status running --services 2>/dev/null || true)"
  state="$(get_module_state "${module}")"

  printf -- "- %s [%s]\n" "${module}" "${state}"

  service_states=""
  first=true
  for service in $(module_services "${module}"); do
    status="off"
    if printf "%s\n" "${running_services}" | grep -Fxq "${service}"; then
      status="on"
    fi

    if [ "${first}" = true ]; then
      service_states="${service}:${status}"
      first=false
    else
      service_states="${service_states}, ${service}:${status}"
    fi
  done

  echo "  servicios: ${service_states}"
}

module_up() {
  local module="$1"
  local services=()

  collect_from_modules "${module}"
  services=("${COLLECTED_SERVICES[@]}")

  ensure_vufind_for_services "${services[@]}"

  if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
    local profile_args=()
    local profile
    for profile in "${COLLECTED_PROFILES[@]}"; do
      profile_args+=(--profile "${profile}")
    done
    dc "${profile_args[@]}" up -d "${services[@]}"
  else
    dc up -d "${services[@]}"
  fi
}

module_down() {
  local module="$1"
  local services=()

  collect_from_modules "${module}"
  services=("${COLLECTED_SERVICES[@]}")

  if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
    local profile_args=()
    local profile
    for profile in "${COLLECTED_PROFILES[@]}"; do
      profile_args+=(--profile "${profile}")
    done
    dc "${profile_args[@]}" stop "${services[@]}"
  else
    dc stop "${services[@]}"
  fi
}

usage() {
  cat <<'USAGE'
Uso: ./Docker/dev.sh <comando> [opciones]

Módulos (organización de servicios):
  core    -> postgres, solr, harvester, dashboard-rest, shell
  vufind  -> vufind-db, vufind-web (opcional, on-demand)
  elastic -> elasticsearch (opcional)
  watch   -> vufind-scss-watch (opcional)

Comandos principales:
  up [--build] [--module <modulo>] [--vufind] [--elastic] [--watch] [servicios...]
      - Sin servicios explícitos: usa módulos activos.
      - --build: rebuild de imágenes + recompilación Java (BUILD_ON_START=always)
        y luego ejecuta init-db (database_migrate).
  down
  start [servicios...]
  stop [servicios...]
  restart [servicios...]
  build [servicios...]
  pull [servicios...]
  ps
  logs [servicio] [-f]
  health

Atajos por módulo:
  core <up|down|on|off|start|stop|status>
  vufind <up|down|on|off|status>
  elastic <up|down|on|off|logs|status>
  watch <up|down|on|off|start|stop|logs|status>

Gestión de módulos:
  modules status
      Muestra módulos on/off y estado on/off por servicio.
  modules on <core|vufind|elastic|watch>
      Activa el módulo en .env y levanta sus servicios.
  modules off <vufind|elastic|watch>
      Desactiva el módulo en .env y detiene sus servicios.

Comandos de plataforma:
  init-db [comando-shell...]
      Ejecuta migración de BD via lareferencia-shell (default: database_migrate).
  shell-interactive [comando-shell...]
  reset-data [--yes]
      Detiene contenedores y limpia data persistida NO versionada en Docker/data.
      Conserva archivos versionados del repo.
  shell <servicio>

Comandos VuFind:
  vufind <up|down|on|off|status>
      Atajos para módulo VuFind (equivalente a modules on/off/status vufind).
  vufind debug <show|on|off>
  vufind theme <show|set <nombre>>
  vufind db
  vufind cli <args...>
  vufind shell [web|db|solr]

Comandos opcionales:
  solr <sync-from-vufind|status>
  elastic <up|down|on|off|logs|status>
  watch <up|down|on|off|start|stop|logs|status>
  exec <servicio> <cmd...>
  compose <args...>

Notas:
  - VuFind se clona solo cuando se necesita (módulo/servicios VuFind).
  - Defaults de clone en .env:
      VUFIND_REPO_URL=https://github.com/vufind-org/vufind
      VUFIND_REF=v11.0.1
USAGE
}

cmd="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "${cmd}" in
  help|-h|--help)
    usage
    ;;

  up)
    build_flag=false
    explicit_vufind_request=false
    requested_modules=()
    services=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --build)
          build_flag=true
          ;;
        --module)
          shift
          if [ "$#" -eq 0 ]; then
            echo "Falta valor para --module" >&2
            exit 1
          fi
          requested_modules+=("$1")
          if [ "$1" = "vufind" ] || [ "$1" = "watch" ]; then
            explicit_vufind_request=true
          fi
          ;;
        --vufind)
          requested_modules+=(vufind)
          explicit_vufind_request=true
          ;;
        --elastic)
          requested_modules+=(elastic)
          ;;
        --watch)
          requested_modules+=(watch)
          explicit_vufind_request=true
          ;;
        *)
          services+=("$1")
          if service_requires_vufind "$1"; then
            explicit_vufind_request=true
          fi
          ;;
      esac
      shift
    done

    if [ "${#services[@]}" -eq 0 ]; then
      modules=()
      if [ "${#requested_modules[@]}" -gt 0 ]; then
        modules+=(core)
        for module in "${requested_modules[@]}"; do
          validate_module_name "${module}"
          if ! contains_item "${module}" "${modules[@]-}"; then
            modules+=("${module}")
          fi
        done
      else
        while IFS= read -r module; do
          if [ -n "${module}" ]; then
            modules+=("${module}")
          fi
        done < <(enabled_modules)
      fi

      collect_from_modules "${modules[@]}"
      services=("${COLLECTED_SERVICES[@]}")
    else
      collect_profiles_for_services "${services[@]}"
    fi

    if [ "${#services[@]}" -eq 0 ]; then
      echo "No hay servicios seleccionados para levantar." >&2
      exit 1
    fi

    filter_vufind_services_if_checkout_missing "${explicit_vufind_request}" "${services[@]}"
    services=("${FILTERED_SERVICES[@]}")
    collect_profiles_for_services "${services[@]}"

    if [ "${#services[@]}" -eq 0 ]; then
      echo "No hay servicios seleccionados para levantar después de omitir VuFind." >&2
      exit 1
    fi

    ensure_m2_cache_dir
    ensure_vufind_for_services "${services[@]}"

    if [ "${build_flag}" = true ]; then
      ensure_java_parent_modules_ready
      if contains_item solr "${services[@]-}"; then
        ensure_solr_build_context
      fi
    fi

    args=(up -d)
    if [ "${build_flag}" = true ]; then
      args+=(--build)
    fi

    if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
      profile_args=()
      for profile in "${COLLECTED_PROFILES[@]}"; do
        profile_args+=(--profile "${profile}")
      done
      if [ "${build_flag}" = true ]; then
        BUILD_ON_START=always dc "${profile_args[@]}" "${args[@]}" "${services[@]}"
      else
        dc "${profile_args[@]}" "${args[@]}" "${services[@]}"
      fi
    else
      if [ "${build_flag}" = true ]; then
        BUILD_ON_START=always dc "${args[@]}" "${services[@]}"
      else
        dc "${args[@]}" "${services[@]}"
      fi
    fi

    if [ "${build_flag}" = true ]; then
      run_init_db smart
    fi
    ;;

  down)
    dc down --remove-orphans
    ;;

  start)
    explicit_vufind_request=false
    services=()
    if [ "$#" -eq 0 ]; then
      collect_from_modules $(enabled_modules)
      services=("${COLLECTED_SERVICES[@]}")
    else
      services=("$@")
      for service in "${services[@]}"; do
        if service_requires_vufind "${service}"; then
          explicit_vufind_request=true
        fi
      done
      collect_profiles_for_services "${services[@]}"
    fi

    filter_vufind_services_if_checkout_missing "${explicit_vufind_request}" "${services[@]}"
    services=("${FILTERED_SERVICES[@]}")
    collect_profiles_for_services "${services[@]}"

    if [ "${#services[@]}" -eq 0 ]; then
      echo "No hay servicios para iniciar después de omitir VuFind." >&2
      exit 1
    fi

    ensure_m2_cache_dir
    ensure_vufind_for_services "${services[@]}"
    if contains_item solr "${services[@]-}"; then
      ensure_solr_build_context
    fi

    if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
      profile_args=()
      for profile in "${COLLECTED_PROFILES[@]}"; do
        profile_args+=(--profile "${profile}")
      done
      dc "${profile_args[@]}" start "${services[@]}"
    else
      dc start "${services[@]}"
    fi
    ;;

  stop)
    services=()
    if [ "$#" -eq 0 ]; then
      collect_from_modules $(enabled_modules)
      services=("${COLLECTED_SERVICES[@]}")
    else
      services=("$@")
      collect_profiles_for_services "${services[@]}"
    fi

    if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
      profile_args=()
      for profile in "${COLLECTED_PROFILES[@]}"; do
        profile_args+=(--profile "${profile}")
      done
      dc "${profile_args[@]}" stop "${services[@]}"
    else
      dc stop "${services[@]}"
    fi
    ;;

  restart)
    explicit_vufind_request=false
    services=()
    if [ "$#" -eq 0 ]; then
      collect_from_modules $(enabled_modules)
      services=("${COLLECTED_SERVICES[@]}")
    else
      services=("$@")
      for service in "${services[@]}"; do
        if service_requires_vufind "${service}"; then
          explicit_vufind_request=true
        fi
      done
      collect_profiles_for_services "${services[@]}"
    fi

    filter_vufind_services_if_checkout_missing "${explicit_vufind_request}" "${services[@]}"
    services=("${FILTERED_SERVICES[@]}")
    collect_profiles_for_services "${services[@]}"

    if [ "${#services[@]}" -eq 0 ]; then
      echo "No hay servicios para reiniciar después de omitir VuFind." >&2
      exit 1
    fi

    ensure_m2_cache_dir
    ensure_vufind_for_services "${services[@]}"

    if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
      profile_args=()
      for profile in "${COLLECTED_PROFILES[@]}"; do
        profile_args+=(--profile "${profile}")
      done
      dc "${profile_args[@]}" restart "${services[@]}"
    else
      dc restart "${services[@]}"
    fi
    ;;

  build)
    explicit_vufind_request=false
    services=()
    if [ "$#" -eq 0 ]; then
      collect_from_modules $(enabled_modules)
      services=("${COLLECTED_SERVICES[@]}")
      if ! contains_item shell "${services[@]-}"; then
        services+=(shell)
      fi
    else
      services=("$@")
      for service in "${services[@]}"; do
        if service_requires_vufind "${service}"; then
          explicit_vufind_request=true
        fi
      done
      collect_profiles_for_services "${services[@]}"
    fi

    filter_vufind_services_if_checkout_missing "${explicit_vufind_request}" "${services[@]}"
    services=("${FILTERED_SERVICES[@]}")
    collect_profiles_for_services "${services[@]}"

    if [ "${#services[@]}" -eq 0 ]; then
      echo "No hay servicios para build después de omitir VuFind." >&2
      exit 1
    fi

    ensure_m2_cache_dir
    ensure_vufind_for_services "${services[@]}"

    if [ "${#COLLECTED_PROFILES[@]}" -gt 0 ]; then
      profile_args=()
      for profile in "${COLLECTED_PROFILES[@]}"; do
        profile_args+=(--profile "${profile}")
      done
      dc "${profile_args[@]}" build "${services[@]}"
    else
      dc build "${services[@]}"
    fi
    ;;

  pull)
    if [ "$#" -eq 0 ]; then
      dc pull vufind-db postgres elasticsearch vufind-scss-watch
    else
      dc pull "$@"
    fi
    ;;

  ps)
    dc ps
    ;;

  logs)
    if [ "$#" -eq 0 ]; then
      dc logs -f --tail=200
    else
      service="$1"
      shift || true
      dc logs --tail=200 "$@" "${service}"
    fi
    ;;

  health)
    echo "== docker compose ps =="
    dc ps
    echo
    echo "== endpoints =="
    curl -fsS -o /dev/null -w "http://localhost:8080 -> HTTP %{http_code}\n" http://localhost:8080/ || true
    curl -fsS -o /dev/null -w "http://localhost:8090 -> HTTP %{http_code}\n" http://localhost:8090/ || true
    curl -fsS -o /dev/null -w "http://localhost:8092 -> HTTP %{http_code}\n" http://localhost:8092/ || true
    curl -fsS -o /dev/null -w "http://localhost:8983/solr -> HTTP %{http_code}\n" http://localhost:8983/solr || true
    ;;

  core)
    sub="${1:-status}"
    if [ "$#" -gt 0 ]; then
      shift
    fi

    case "${sub}" in
      up|on|start)
        module_up core
        print_module_status_one core
        ;;
      down|off|stop)
        module_down core
        print_module_status_one core
        ;;
      status)
        print_module_status_one core
        ;;
      help|-h|--help)
        echo "Uso: ./Docker/dev.sh core <up|down|on|off|start|stop|status>"
        ;;
      *)
        echo "Subcomando inválido para core: ${sub}" >&2
        echo "Uso: ./Docker/dev.sh core <up|down|on|off|start|stop|status>" >&2
        exit 1
        ;;
    esac
    ;;

  modules)
    sub="${1:-status}"
    if [ "$#" -gt 0 ]; then
      shift
    fi

    case "${sub}" in
      status)
        print_module_status
        ;;
      on)
        module="${1:-}"
        if [ -z "${module}" ]; then
          echo "Uso: ./Docker/dev.sh modules on <core|vufind|elastic|watch>" >&2
          exit 1
        fi
        validate_module_name "${module}"
        set_module_state "${module}" on
        if [ "${module}" = "vufind" ]; then
          refresh_solr_for_vufind_assets
        fi
        module_up "${module}"
        echo "Módulo ${module} activado."
        ;;
      off)
        module="${1:-}"
        if [ -z "${module}" ]; then
          echo "Uso: ./Docker/dev.sh modules off <vufind|elastic|watch>" >&2
          exit 1
        fi
        validate_module_name "${module}"
        set_module_state "${module}" off
        module_down "${module}"
        echo "Módulo ${module} desactivado."
        ;;
      *)
        echo "Subcomando inválido para modules: ${sub}" >&2
        exit 1
        ;;
    esac
    ;;

  init-db)
    shell_cmd=("$@")
    if [ "${#shell_cmd[@]}" -eq 0 ]; then
      shell_cmd=(database_migrate)
    fi

    ensure_java_parent_modules_ready
    ensure_shell_service_running smart
    exec_shell_command_noninteractive smart "${shell_cmd[@]}"
    ;;

  shell-interactive)
    ensure_java_parent_modules_ready
    ensure_shell_service_running smart
    if [ "$#" -eq 0 ]; then
      exec_shell_command_interactive smart
    else
      exec_shell_command_interactive smart "$@"
    fi
    ;;

  reset-data)
    auto_yes=false

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --yes)
          auto_yes=true
          ;;
        *)
          echo "Uso: ./Docker/dev.sh reset-data [--yes]" >&2
          exit 1
          ;;
      esac
      shift
    done

    if [ ! -d "${DATA_DIR}" ]; then
      echo "No existe el directorio de data: ${DATA_DIR}" >&2
      exit 1
    fi

    case "${DATA_DIR}" in
      */Docker/data) ;;
      *)
        echo "Ruta de data inválida: ${DATA_DIR}" >&2
        exit 1
        ;;
    esac

    if [ "${auto_yes}" != true ]; then
      echo "Esto va a limpiar data persistida NO versionada en: ${DATA_DIR}"
      echo "Servicios afectados: postgres, solr, vufind-db, elasticsearch y stores locales."
      read -r -p "Escribe RESET para confirmar: " confirmation
      if [ "${confirmation}" != "RESET" ]; then
        echo "Operación cancelada."
        exit 1
      fi
    fi

    echo "Deteniendo contenedores..."
    dc down --remove-orphans || true

    echo "Borrando contenido persistido no versionado..."
    clean_data_preserving_tracked

    echo "Data reset completado."
    ;;

  vufind)
    sub="${1:-help}"
    if [ "$#" -gt 0 ]; then
      shift
    fi

    case "${sub}" in
      up|on)
        set_module_state vufind on
        refresh_solr_for_vufind_assets
        module_up vufind
        print_module_status_one vufind
        ;;

      down|off)
        set_module_state vufind off
        module_down vufind
        print_module_status_one vufind
        ;;

      status)
        print_module_status_one vufind
        ;;

      debug)
        action="${1:-show}"
        case "${action}" in
          show)
            echo "VUFIND_ENV=$(get_env_var VUFIND_ENV production)"
            echo "VUFIND_SYSTEM_DEBUG=$(get_env_var VUFIND_SYSTEM_DEBUG false)"
            echo "VUFIND_PHP_DISPLAY_ERRORS=$(get_env_var VUFIND_PHP_DISPLAY_ERRORS 0)"
            echo "VUFIND_PHP_DISPLAY_STARTUP_ERRORS=$(get_env_var VUFIND_PHP_DISPLAY_STARTUP_ERRORS 0)"
            echo "VUFIND_PHP_ERROR_REPORTING=$(get_env_var VUFIND_PHP_ERROR_REPORTING E_ALL)"
            echo "VUFIND_PHP_HTML_ERRORS=$(get_env_var VUFIND_PHP_HTML_ERRORS 0)"
            if [ -f "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" ]; then
              echo
              echo "config.ini local:"
              awk -F= '/^[[:space:]]*(debug|autoConfigure)[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0}' "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" || true
            fi
            ;;
          on)
            ensure_vufind_checkout
            set_env_var "VUFIND_ENV" "development" "${ENV_FILE}"
            set_env_var "VUFIND_SYSTEM_DEBUG" "true" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_ERRORS" "1" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_STARTUP_ERRORS" "1" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_ERROR_REPORTING" "E_ALL" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_HTML_ERRORS" "1" "${ENV_FILE}"
            echo "Debug de VuFind activado en ${ENV_FILE}"
            dc up -d vufind-web
            ;;
          off)
            ensure_vufind_checkout
            set_env_var "VUFIND_ENV" "production" "${ENV_FILE}"
            set_env_var "VUFIND_SYSTEM_DEBUG" "false" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_ERRORS" "0" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_STARTUP_ERRORS" "0" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_ERROR_REPORTING" "E_ALL" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_HTML_ERRORS" "0" "${ENV_FILE}"
            echo "Debug de VuFind desactivado en ${ENV_FILE}"
            dc up -d vufind-web
            ;;
          *)
            echo "Uso: ./Docker/dev.sh vufind debug <show|on|off>" >&2
            exit 1
            ;;
        esac
        ;;

      theme)
        action="${1:-show}"
        case "${action}" in
          show)
            echo "VUFIND_THEME=$(get_current_theme)"
            ;;
          set)
            name="${2:-}"
            if [ -z "${name}" ]; then
              echo "Uso: ./Docker/dev.sh vufind theme set <nombre>" >&2
              exit 1
            fi
            ensure_vufind_checkout
            set_env_var "VUFIND_THEME" "${name}" "${ENV_FILE}"
            echo "VUFIND_THEME=${name} escrito en ${ENV_FILE}"
            dc up -d vufind-web
            ;;
          *)
            echo "Uso: ./Docker/dev.sh vufind theme <show|set <nombre>>" >&2
            exit 1
            ;;
        esac
        ;;

      db)
        dc exec vufind-db mariadb -uroot -proot
        ;;

      cli)
        if [ "$#" -eq 0 ]; then
          echo "Uso: ./Docker/dev.sh vufind cli <args...>" >&2
          exit 1
        fi
        ensure_vufind_checkout
        dc exec vufind-web php public/index.php "$@"
        ;;

      shell)
        target="${1:-web}"
        case "${target}" in
          web)
            ensure_vufind_checkout
            dc exec vufind-web bash
            ;;
          db)
            dc exec vufind-db sh
            ;;
          solr)
            dc exec solr bash
            ;;
          *)
            echo "Servicio inválido: ${target} (usa web|db|solr)" >&2
            exit 1
            ;;
        esac
        ;;

      help|-h|--help)
        echo "Uso: ./Docker/dev.sh vufind <up|down|on|off|status|debug|theme|db|cli|shell>"
        echo "  up|on"
        echo "  down|off"
        echo "  status"
        echo "  debug <show|on|off>"
        echo "  theme <show|set <nombre>>"
        echo "  db"
        echo "  cli <args...>"
        echo "  shell [web|db|solr]"
        ;;

      *)
        echo "Subcomando inválido para vufind: ${sub}" >&2
        echo "Uso: ./Docker/dev.sh vufind <up|down|on|off|status|debug|theme|db|cli|shell>" >&2
        exit 1
        ;;
    esac
    ;;

  shell)
    svc="${1:-}"
    if [ -z "${svc}" ]; then
      echo "Uso: ./Docker/dev.sh shell <servicio>" >&2
      exit 1
    fi
    dc exec "${svc}" bash
    ;;

  solr)
    sub="${1:-status}"
    case "${sub}" in
      sync-from-vufind|sync)
        ensure_vufind_checkout
        sync_solr_assets_from_vufind
        echo "Recreando servicio solr para aplicar jars/import actualizados..."
        dc up -d --force-recreate solr
        ;;
      status)
        echo "VuFind import:"
        ls -la "${ROOT_DIR}/vufind/import" 2>/dev/null | sed -n '1,8p' || true
        echo
        echo "Docker import:"
        ls -la "${ROOT_DIR}/Docker/solr/import" 2>/dev/null | sed -n '1,8p' || true
        echo
        echo "VuFind jars:"
        ls -la "${ROOT_DIR}/vufind/solr/vufind/jars" 2>/dev/null | sed -n '1,8p' || true
        echo
        echo "Docker jars:"
        ls -la "${ROOT_DIR}/Docker/solr/jars" 2>/dev/null | sed -n '1,8p' || true
        ;;
      *)
        echo "Subcomando inválido para solr: ${sub}" >&2
        echo "Uso: ./Docker/dev.sh solr <sync-from-vufind|status>" >&2
        exit 1
        ;;
    esac
    ;;

  elastic)
    sub="${1:-status}"
    case "${sub}" in
      up|on)
        set_module_state elastic on
        module_up elastic
        ;;
      down|off)
        set_module_state elastic off
        module_down elastic
        ;;
      logs)
        dc --profile elastic logs -f --tail=200 elasticsearch
        ;;
      status)
        dc --profile elastic ps elasticsearch
        ;;
      help|-h|--help)
        echo "Uso: ./Docker/dev.sh elastic <up|down|on|off|logs|status>"
        ;;
      *)
        echo "Subcomando inválido para elastic: ${sub}" >&2
        echo "Uso: ./Docker/dev.sh elastic <up|down|on|off|logs|status>" >&2
        exit 1
        ;;
    esac
    ;;

  watch)
    sub="${1:-status}"
    case "${sub}" in
      up|on|start)
        set_module_state watch on
        module_up watch
        ;;
      down|off|stop)
        set_module_state watch off
        module_down watch
        ;;
      logs)
        dc --profile watch logs -f --tail=200 vufind-scss-watch
        ;;
      status)
        dc --profile watch ps vufind-scss-watch
        ;;
      help|-h|--help)
        echo "Uso: ./Docker/dev.sh watch <up|down|on|off|start|stop|logs|status>"
        ;;
      *)
        echo "Subcomando inválido para watch: ${sub}" >&2
        echo "Uso: ./Docker/dev.sh watch <up|down|on|off|start|stop|logs|status>" >&2
        exit 1
        ;;
    esac
    ;;

  exec)
    if [ "$#" -lt 2 ]; then
      echo "Uso: ./Docker/dev.sh exec <servicio> <cmd...>" >&2
      exit 1
    fi
    svc="$1"
    shift
    dc exec "${svc}" "$@"
    ;;

  compose)
    dc "$@"
    ;;

  *)
    echo "Comando inválido: ${cmd}" >&2
    usage
    exit 1
    ;;
esac
