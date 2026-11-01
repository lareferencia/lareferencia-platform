#!/usr/bin/env bash
# =============================================================================
# commands.sh — One function per CLI command (`./Docker/docker.sh <command>`).
#
# This is the command-line controller/view: it parses arguments, prints and
# delegates the work to the services in lib/*.sh.
#
# docker.sh maps the command name to a `command::<name>` function using the
# COMMANDS table at the bottom of this file. Adding a command = writing the
# function + one line in the table.
# =============================================================================

# --- help ---------------------------------------------------------------------------

command::help() {
  cat <<USAGE
Usage: ./Docker/docker.sh <command> [options]

Core Commands:
  wizard               Start the interactive assistant (RECOMMENDED)
  up [--build]         Start active modules
  down                 Stop and remove containers
  start/stop/restart   Manage existing containers
  build [service...]   Compile sources and build images
  ps / logs / health   Monitoring
  modules <on|off>     Enable/disable modules (vufind, elastic, watch, oai)
  res <profile>        Apply resource profile (low, medium, high, custom)
  init-db              Migrate database
  postgres <action>    PostgreSQL major version: status | upgrade | rollback | remove-legacy
  solr [update-config] Update Solr core configurations from modules with index preservation
  prune                Reclaim disk space: old La Referencia images + its build cache
  reset-data           Clean Docker/data
  backup-db [dir]      Dump the databases now (gzip) into <dir>/db_<date>/
  shell <service>      Start a bash shell in a running container
  lrshell-interactive  Start interactive session in the shell container
  dc <args>            Run docker compose with this instance's environment

Options for 'up':
  --build              Compile sources and rebuild images first
  --no-cache           Build images without Docker cache
  --pull-modules       Pull updates for the Java workspace modules
  --prefix=<name>      Set SERVICE_PREFIX
  --offset=<n>         Set SERVICES_PORT_OFFSET
  --module <m>         Start only module <m> (repeatable)
  --vufind --elastic --watch --oai   Shortcuts for --module <m>
  <service...>         Start only these compose services

Variables in Docker/.env:
  SERVICE_PREFIX       Instance isolation
  SERVICES_PORT_OFFSET Port shifting
  LR_BUILD_PROFILE     Maven profile (ibict, rcaap, lareferencia)
USAGE
}

# --- wizard ---------------------------------------------------------------------------

command::wizard() {
  wizard::require_docker
  config::ensure_file
  compose::export_service_prefix
  wizard::main
}

# --- up ---------------------------------------------------------------------------------
#
#   1. parse options               → UP_* variables
#   2. choose services             → SELECTED_SERVICES / SELECTED_PROFILES
#   3. prepare host (VuFind checkout, volumes)
#   4. build when asked or when images are missing (also runs init-db)
#   5. docker compose up

_up::parse_args() {
  UP_BUILD=false
  UP_NO_CACHE=false
  UP_PULL_MODULES=false
  UP_EXPLICIT_VUFIND=false   # user explicitly asked for a VuFind service
  UP_MODULES=()
  UP_SERVICES=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --build)        UP_BUILD=true ;;
      --no-cache)     UP_NO_CACHE=true ;;
      --pull-modules) UP_PULL_MODULES=true ;;
      --prefix=*)     config::set SERVICE_PREFIX "${1#*=}" ;;
      --offset=*)     config::set SERVICES_PORT_OFFSET "${1#*=}" ;;
      --module)       shift; UP_MODULES+=("$1") ;;
      --vufind)       UP_MODULES+=(vufind) ;;
      --elastic)      UP_MODULES+=(elastic) ;;
      --watch)        UP_MODULES+=(watch) ;;
      --oai)          UP_MODULES+=(oai) ;;
      *)              UP_SERVICES+=("$1") ;;
    esac
    shift
  done
}

_up::select_services() {
  selection::clear

  if [ "${#UP_SERVICES[@]}" -gt 0 ]; then
    selection::add_services "${UP_SERVICES[@]}"
    selection::needs_vufind && UP_EXPLICIT_VUFIND=true
    return 0
  fi

  # No explicit services: requested modules, or every enabled module.
  local modules=() m
  if [ "${#UP_MODULES[@]}" -gt 0 ]; then
    for m in "${UP_MODULES[@]}"; do
      module::validate "${m}"
      list::contains "${m}" ${modules[@]+"${modules[@]}"} || modules+=("${m}")
    done
  else
    for m in $(module::enabled); do modules+=("${m}"); done
  fi

  local resolved=()
  for m in $(module::with_dependencies ${modules[@]+"${modules[@]}"}); do resolved+=("${m}"); done

  selection::add_modules ${resolved[@]+"${resolved[@]}"}

  if list::contains vufind ${resolved[@]+"${resolved[@]}"} || list::contains watch ${resolved[@]+"${resolved[@]}"}; then
    UP_EXPLICIT_VUFIND=true
  fi
  return 0
}

command::up() {
  _up::parse_args "$@"
  pg::ensure_compatible   # compose would start postgres (directly or as a dependency)
  _up::select_services
  selection::drop_vufind_if_not_cloned "${UP_EXPLICIT_VUFIND}"

  vufind::ensure_for_selection
  data::ensure_volume_directories

  if [ "${UP_BUILD}" = false ] && ! build::images_exist; then
    ui::warn "⚠️  First-time run or missing Docker images detected. Forcing initial build..."
    UP_BUILD=true
    UP_PULL_MODULES=true
  fi

  local up_args=(up -d --remove-orphans)
  if [ "${UP_BUILD}" = true ]; then
    workspace::ensure_java_modules "${UP_PULL_MODULES}"
    build::all "${UP_NO_CACHE}"
    db::init
    up_args+=(--force-recreate --build)
  fi

  selection::run "${up_args[@]}"
}

# --- down -------------------------------------------------------------------------------
#   down [v] [compose args...]     "v" also removes named volumes

command::down() {
  # Every profile, so containers of disabled modules are removed too.
  local profiles=() m
  for m in $(module::all); do profiles+=("$(module::cli_profile "${m}")"); done

  local down_args=(down --remove-orphans)
  if [ "${1:-}" = "v" ]; then
    down_args+=(--volumes)
    shift
  fi

  compose::run_with_profiles "${profiles[@]}" -- "${down_args[@]}" "$@"
}

# --- start / stop / restart -----------------------------------------------------------
#   <action> [service...]          default: services of every enabled module

_lifecycle::select() {
  selection::from_args_or_enabled "$@"
  local explicit=false
  [ "$#" -gt 0 ] && selection::needs_vufind && explicit=true
  selection::drop_vufind_if_not_cloned "${explicit}"
  vufind::ensure_for_selection
}

# Only when postgres itself is targeted (the nightly backup restarts solr & co.
# without touching postgres, and must keep working).
_lifecycle::guard_postgres() {
  if selection::has postgres; then
    pg::ensure_compatible
  fi
  return 0
}

command::start() {
  _lifecycle::select "$@"
  _lifecycle::guard_postgres
  data::ensure_volume_directories
  selection::run start
}

command::stop() {
  _lifecycle::select "$@"
  selection::run stop
}

command::restart() {
  _lifecycle::select "$@"
  _lifecycle::guard_postgres
  data::ensure_volume_directories
  selection::run restart
}

# --- build ---------------------------------------------------------------------------------
#   build [service...]             default: services of every enabled module
#   - frontends + Java when harvester is selected
#   - Java only when another Java service is selected

command::build() {
  _lifecycle::select "$@"
  workspace::ensure_java_modules false

  if selection::is_empty || selection::has solr; then
    solr::stage
  fi

  if selection::is_empty || selection::has harvester; then
    build::components
  elif selection::has_java_service; then
    build::java
  fi

  buildx::use_dedicated
  selection::run build
  images::cleanup_after_build
}

# --- simple pass-through commands ------------------------------------------------------------

command::dc()   { dc "$@"; }
command::ps()   { dc ps; }
command::logs() { dc logs "$@"; }
command::pull() { dc pull vufind-db postgres elasticsearch vufind-scss-watch; }
command::prune() { images::prune_all; }

command::health() {
  dc ps   # also exports LR_PORT_* for the checks below
  echo -e "\nEndpoints:"
  local check name port
  for check in "VuFind:${LR_PORT_VUFIND_WEB:-8080}" \
               "Harvester:${LR_PORT_HARVESTER:-8090}" \
               "Entity REST:${LR_PORT_ENTITY_REST:-8094}" \
               "OAI PMH:${LR_PORT_OAI:-8096}"; do
    name="${check%%:*}"
    port="${check##*:}"
    curl -fsS -o /dev/null -w "${name}: http://localhost:${port} -> %{http_code}\n" "http://localhost:${port}/" || true
  done
}

command::shell() {
  local service="${1:-}"
  if [ -z "${service}" ]; then
    echo "Usage: shell <service>"
    exit 1
  fi
  dc exec "${service}" bash
}

# --- database / lrshell ----------------------------------------------------------------------

command::init_db() {
  pg::ensure_compatible
  workspace::ensure_java_modules
  db::init "$@"
}

command::lrshell_interactive() {
  pg::ensure_compatible
  workspace::ensure_java_modules
  db::start_infrastructure
  lrshell::run_interactive "$@"
}

# --- reset-data [--yes] -----------------------------------------------------------------------

_reset::print_paths() {
  local p
  for p in $(data::reset_paths); do
    echo -e "  - ${p}"
  done
}

command::reset_data() {
  if [ "${1:-}" != "--yes" ]; then
    compose::export_service_prefix
    echo -e "${C_RED}⚠️  DANGER ZONE: SURGICAL RESET${C_RESET}"
    echo -e "This will remove the Compose containers for project: ${C_YELLOW}${COMPOSE_PROJECT_NAME}${C_RESET}"
    echo -e "And permanently delete data ONLY in these specific directories:"
    _reset::print_paths
    echo -e "\nOther directories (like dev or backups) will remain untouched."
    local confirmation
    read -r -p "Type RESET to confirm: " confirmation
    [ "${confirmation}" = "RESET" ] || exit 1
  fi
  data::reset_all
}

# --- modules [status [m] | on <m> | off <m>] ----------------------------------------------------

_modules::print_status() {
  local running module service
  running="$(compose::running_services)"

  echo -e "${C_CYAN}${C_BOLD}📦 Platform Modules:${C_RESET}"
  for module in $(module::all); do
    local state color=$C_GRAY icon="⚪"
    state="$(module::state "${module}")"
    [ "${state}" = "on" ] && { color=$C_GREEN; icon="🟢"; }
    printf "  %-10s [${color}%-3s${C_RESET}] %s\n" "${module}" "${state}" "${icon}"

    for service in $(module::services "${module}"); do
      local status="${C_GRAY}off${C_RESET}" status_icon="⭕"
      if printf "%s\n" "${running}" | grep -Fxq "${service}"; then
        status="${C_GREEN}running${C_RESET}"
        status_icon="⚡"
      fi
      printf "    └─ %-15s [${status_icon}${status}]\n" "${service}"
    done
  done
}

command::modules() {
  local action="${1:-status}"
  [ "$#" -gt 0 ] && shift
  local module="${1:-}"

  case "${action}" in
    status)
      if [ -z "${module}" ]; then
        _modules::print_status
      else
        module::validate "${module}"
        echo -e "${C_BOLD}${module}${C_RESET}: $(module::state "${module}")"
      fi
      ;;
    on)
      module::validate "${module}" && module::set_state "${module}" on && echo "Module ${module} activated."
      ;;
    off)
      module::validate "${module}" && module::set_state "${module}" off && echo "Module ${module} deactivated."
      ;;
  esac
}

# --- postgres [status | upgrade | rollback | remove-legacy] [--yes] -----------------------------

# Asks the user to type a word unless --yes was given.
_postgres::confirm() {
  local word="$1" flag="$2" answer
  [ "${flag}" = "--yes" ] && return 0
  read -r -p "Type ${word} to confirm: " answer
  [ "${answer}" = "${word}" ]
}

command::postgres() {
  local action="${1:-status}"
  local flag="${2:-}"

  case "${action}" in
    status)
      pg::describe
      ;;
    upgrade)
      _postgres::confirm UPGRADE "${flag}" || exit 1
      pg::upgrade
      ;;
    rollback)
      ui::warn "Rollback restores the data as it was BEFORE the migration."
      ui::warn "Changes made afterwards stay only in the set-aside PostgreSQL directory."
      _postgres::confirm ROLLBACK "${flag}" || exit 1
      pg::rollback
      ;;
    remove-legacy)
      local legacy
      legacy="$(pg::legacy_dir)"
      [ -n "${legacy}" ] || { echo "There is no preserved PostgreSQL cluster to remove."; exit 1; }
      echo -e "  ${C_RED}DELETE:${C_RESET} ${PG_DATA_ROOT}/${legacy}"
      echo -e "  ${C_GREEN}KEEP:${C_RESET}   ${PG_DATA_ROOT}/data"
      _postgres::confirm DELETE "${flag}" || exit 1
      pg::remove_legacy
      ;;
    *)
      echo "Usage: ./Docker/docker.sh postgres [status|upgrade|rollback|remove-legacy] [--yes]" >&2
      exit 1
      ;;
  esac
}

# --- backup-db [destination] -------------------------------------------------------------------

command::backup_db() {
  backup::dump_databases "${1:-$(backup::default_destination)}"
}

# --- res <profile> ------------------------------------------------------------------------------

command::resource_profile() {
  local profile="${1:-}"
  if [ -z "${profile}" ]; then
    echo "Usage: res <low|medium|high|custom>"
    exit 1
  fi
  config::apply_resource_profile "${profile}"
}

# --- solr [update-config | stage] ---------------------------------------------------------------

command::solr() {
  local action="${1:-update-config}"
  [ "$#" -gt 0 ] && shift
  case "${action}" in
    update-config) solr::update_config ;;
    stage)         solr::stage ;;
    *)
      echo "Usage: ./Docker/docker.sh solr [update-config|stage]" >&2
      exit 1
      ;;
  esac
}

# =============================================================================
# Command table:  "<name(s) typed by the user> → <function>"
# =============================================================================
COMMANDS=(
  "help -h --help            → command::help"
  "wizard                    → command::wizard"
  "up                        → command::up"
  "down                      → command::down"
  "start                     → command::start"
  "stop                      → command::stop"
  "restart                   → command::restart"
  "build                     → command::build"
  "dc                        → command::dc"
  "pull                      → command::pull"
  "ps                        → command::ps"
  "logs                      → command::logs"
  "health                    → command::health"
  "init-db                   → command::init_db"
  "postgres pg               → command::postgres"
  "lrshell-interactive       → command::lrshell_interactive"
  "prune                     → command::prune"
  "reset-data                → command::reset_data"
  "backup-db                 → command::backup_db"
  "shell                     → command::shell"
  "modules                   → command::modules"
  "resource-profile res      → command::resource_profile"
  "solr                      → command::solr"
)

# Prints the handler function for a command name (fails when unknown).
command::resolve() {
  local name="$1" row aliases handler alias
  for row in "${COMMANDS[@]}"; do
    aliases="${row%%→*}"
    handler="$(text::trim "${row##*→}")"
    for alias in ${aliases}; do
      if [ "${alias}" = "${name}" ]; then
        echo "${handler}"
        return 0
      fi
    done
  done
  return 1
}

command::dispatch() {
  local name="${1:-help}"
  [ "$#" -gt 0 ] && shift

  local handler
  if ! handler="$(command::resolve "${name}")"; then
    command::help
    exit 1
  fi
  "${handler}" "$@"
}
