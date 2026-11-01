#!/usr/bin/env bash
# =============================================================================
# modules.sh — "Module" and "Service" models.
#
# A *module* is a feature the user switches on/off (vufind, elastic, ...).
# Each module owns one or more docker-compose *services*.
#
# Module registry (one row per module — think of it as the class definition):
#
#   name          .env key                 default  services                cli profile  compose profile
# -----------------------------------------------------------------------------
MODULE_REGISTRY=(
  "core        | DEV_MODULE_CORE        | on  | postgres              |       | core"
  "solr        | DEV_MODULE_SOLR        | on  | solr                  |       |"
  "harvester   | DEV_MODULE_HARVESTER   | on  | harvester             |       | harvester"
  "entity-rest | DEV_MODULE_ENTITY_REST | off | entity-rest           |       | entity-rest"
  "shell       | DEV_MODULE_SHELL       | off | shell                 | tools | tools"
  "vufind      | DEV_MODULE_VUFIND      | on  | vufind-db vufind-web  |       | vufind"
  "elastic     | DEV_MODULE_ELASTIC     | off | elasticsearch         | elastic | elastic"
  "watch       | DEV_MODULE_WATCH       | off | vufind-scss-watch     | watch | watch"
  "oai         | DEV_MODULE_OAI         | on  | oai-pmh               | oai   | oai"
)
#
#   cli profile      → passed as `--profile X` when the module is targeted
#   compose profile  → written to COMPOSE_PROFILES when the module is enabled
#
# Public API (module::*):
#   module::all                     lists every module name
#   module::validate <m>            fails (with message) for unknown modules
#   module::state <m>               "on" | "off"  (core is always on)
#   module::set_state <m> <on|off>
#   module::enabled                 lists enabled modules
#   module::services <m>            compose services of a module
#   module::cli_profile <m>
#   module::compose_profile <m>
#   module::with_dependencies <m...>  adds core/solr when required
#   module::apply_selection <m...>    enables exactly these optional modules
#
# Public API (service::*):
#   service::requires_vufind <s>    true for services built from the VuFind checkout
#   service::is_java <s>            true for services built from the Java workspace
#   service::has_own_image <s>      true for services whose image is built locally
#   service::profile <s>            compose profile needed to address the service
# =============================================================================

MODULES_OPTIONAL=(solr harvester entity-rest shell vufind elastic watch oai)

# --- Registry access ---------------------------------------------------------

# _module::field <module> <column-index>   (0 = name ... 5 = compose profile)
_module::field() {
  local module="$1" column="$2" row
  for row in "${MODULE_REGISTRY[@]}"; do
    local fields=()
    IFS='|' read -r -a fields <<< "${row}"
    if [ "$(text::trim "${fields[0]}")" = "${module}" ]; then
      text::trim "${fields[$column]:-}"
      echo
      return 0
    fi
  done
  return 1
}

module::all() {
  local row
  for row in "${MODULE_REGISTRY[@]}"; do
    text::trim "${row%%|*}"
    echo
  done
}

module::exists() {
  _module::field "$1" 0 >/dev/null
}

module::validate() {
  module::exists "$1" && return 0
  ui::error "Invalid module: $1"
  return 1
}

module::env_key()         { _module::field "$1" 1; }
module::default_state()   { _module::field "$1" 2; }
module::cli_profile()     { _module::field "$1" 4; }
module::compose_profile() { _module::field "$1" 5; }

module::services() {
  local module="$1"
  # An external Solr replaces the solr container.
  if [ "${module}" = "solr" ] && [ -n "$(config::get SOLR_EXTERNAL_URL "")" ]; then
    return 0
  fi
  _module::field "${module}" 3
}

# --- State (persisted in .env) -----------------------------------------------

module::state() {
  local module="$1"
  if [ "${module}" = "core" ]; then
    echo "on"
    return 0
  fi
  text::to_toggle "$(config::get "$(module::env_key "${module}")" "$(module::default_state "${module}")")"
}

module::is_on() {
  [ "$(module::state "$1")" = "on" ]
}

module::set_state() {
  local module="$1" state="$2"
  if [ "${module}" = "core" ] && [ "${state}" = "off" ]; then
    echo "Core module cannot be deactivated." >&2
    return 1
  fi
  config::set "$(module::env_key "${module}")" "${state}"
}

module::enabled() {
  local module
  for module in $(module::all); do
    module::is_on "${module}" && echo "${module}"
  done
  return 0
}

# --- Dependencies ------------------------------------------------------------
#   harvester, entity-rest, shell  → need core (postgres)
#   harvester, shell, vufind       → need solr
module::with_dependencies() {
  local result=("$@")
  local m needs_core=false needs_solr=false

  for m in "$@"; do
    case "${m}" in
      harvester|entity-rest|shell) needs_core=true ;;
    esac
    case "${m}" in
      harvester|shell|vufind) needs_solr=true ;;
    esac
  done

  if [ "${needs_core}" = true ] && ! list::contains core "$@"; then result+=(core); fi
  if [ "${needs_solr}" = true ] && ! list::contains solr "$@"; then result+=(solr); fi

  printf "%s\n" "${result[@]}"
}

# Enables exactly the given optional modules (core is always on). VuFind and
# the harvester cannot work without Solr, so selecting them enables it too.
module::apply_selection() {
  local m
  for m in "${MODULES_OPTIONAL[@]}"; do
    module::set_state "${m}" off
  done
  for m in "$@"; do
    module::validate "${m}"
    module::set_state "${m}" on
  done
  if list::contains vufind "$@" || list::contains harvester "$@"; then
    module::set_state solr on
  fi
  return 0
}

# --- Services ----------------------------------------------------------------

service::requires_vufind() {
  case "$1" in
    vufind-web|vufind-db|vufind-scss-watch) return 0 ;;
    *) return 1 ;;
  esac
}

service::is_java() {
  case "$1" in
    harvester|entity-rest|shell|oai-pmh|db-init) return 0 ;;
    *) return 1 ;;
  esac
}

service::has_own_image() {
  case "$1" in
    harvester|entity-rest|shell|solr|vufind-web|vufind-scss-watch|oai-pmh) return 0 ;;
    *) return 1 ;;
  esac
}

service::profile() {
  case "$1" in
    shell)             echo "tools" ;;
    elasticsearch)     echo "elastic" ;;
    vufind-scss-watch) echo "watch" ;;
  esac
}
