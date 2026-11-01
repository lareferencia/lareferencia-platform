#!/usr/bin/env bash
# =============================================================================
# settings.sh — "Settings": user-facing platform settings stored in .env,
# with their validation rules.
#
# Public API:
#   settings::build_cache_enabled / settings::toggle_build_cache
#   settings::parallel_build_enabled / settings::toggle_parallel_build
#   settings::service_prefix / settings::set_service_prefix <v>    (validated)
#   settings::port_offset / settings::set_port_offset <n>          (validated)
#   settings::build_profile / settings::set_build_profile <p>      (validated)
#   settings::resource_profile / settings::apply_resource_profile <p>
#   settings::resource_limit <MEM|CPU> <SERVICE>
#   settings::save_custom_resources "<SERVICE>|<mem>|<cpu>"...
#   settings::external_solr / settings::set_external_solr <url>
#
# Lists offered to the user:
#   SETTINGS_BUILD_PROFILES, SETTINGS_RESOURCE_PROFILES, SETTINGS_RESOURCE_SERVICES
# =============================================================================

SETTINGS_BUILD_PROFILES=(lareferencia ibict rcaap lite)
SETTINGS_RESOURCE_PROFILES=(low medium high custom)
SETTINGS_RESOURCE_SERVICES=(HARVESTER SOLR POSTGRES DASHBOARD ENTITY VUFIND ELASTIC)

# --- Build ------------------------------------------------------------------------

settings::build_cache_enabled() {
  [ "$(config::get DOCKER_BUILD_CACHE on)" != "off" ]
}

settings::toggle_build_cache() {
  if settings::build_cache_enabled; then
    config::set DOCKER_BUILD_CACHE off
  else
    config::set DOCKER_BUILD_CACHE on
  fi
}

settings::parallel_build_enabled() {
  [ "$(config::get BUILD_PARALLEL false)" = "true" ]
}

settings::toggle_parallel_build() {
  if settings::parallel_build_enabled; then
    config::set BUILD_PARALLEL false
  else
    config::set BUILD_PARALLEL true
  fi
}

settings::build_profile() {
  config::get LR_BUILD_PROFILE lareferencia
}

settings::set_build_profile() {
  list::contains "$1" "${SETTINGS_BUILD_PROFILES[@]}" || return 1
  config::set LR_BUILD_PROFILE "$1"
}

# --- Instance identity (change only while containers are stopped) ----------------

settings::service_prefix() {
  config::get SERVICE_PREFIX lareferencia
}

# Lowercase alphanumeric, hyphens or underscores; must start alphanumeric.
settings::set_service_prefix() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
  config::set SERVICE_PREFIX "$1"
  compose::export_service_prefix
}

settings::port_offset() {
  config::get SERVICES_PORT_OFFSET 0
}

settings::set_port_offset() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  config::set SERVICES_PORT_OFFSET "$1"
}

# --- Resources ---------------------------------------------------------------------

settings::resource_profile() {
  config::get LR_RESOURCE_PROFILE medium
}

settings::apply_resource_profile() {
  config::apply_resource_profile "$1"
}

# settings::resource_limit MEM HARVESTER  →  current value (defaults 1G / 0.5)
settings::resource_limit() {
  local kind="$1" service="$2" default="1G"
  [ "${kind}" = "CPU" ] && default="0.5"
  config::get "LR_${kind}_${service}" "${default}"
}

# Saves Docker/profiles/custom.env and applies it.
#   settings::save_custom_resources "HARVESTER|2G|1.0" "SOLR|1G|0.5" ...
settings::save_custom_resources() {
  local custom_file="${SCRIPT_DIR}/profiles/custom.env" entry service mem cpu
  echo "# Profile: custom" > "${custom_file}"
  for entry in "$@"; do
    IFS='|' read -r service mem cpu <<< "${entry}"
    config::set "LR_MEM_${service}" "${mem}"
    config::set "LR_CPU_${service}" "${cpu}"
    echo "LR_MEM_${service}=${mem}" >> "${custom_file}"
    echo "LR_CPU_${service}=${cpu}" >> "${custom_file}"
  done
  config::set LR_RESOURCE_PROFILE custom
}

# --- External services ---------------------------------------------------------------

settings::external_solr() {
  config::get SOLR_EXTERNAL_URL ""
}

settings::set_external_solr() {
  config::set SOLR_EXTERNAL_URL "$1"
}
