#!/usr/bin/env bash
# =============================================================================
# wizard/settings.sh — View: dialogs that edit settings (rules in lib/settings.sh).
# =============================================================================

wizard::toggle_build_cache()       { settings::toggle_build_cache; }
wizard::toggle_build_concurrency() { settings::toggle_parallel_build; }

# Some settings cannot change while containers exist. Returns 1 if the user
# prefers to keep the platform running.
_settings_view::stop_platform_first() {
  local what="$1"
  compose::any_running || return 0
  gum style --foreground 222 "⚠️  WARNING: Containers are currently running."
  gum confirm "Do you want to stop them now to change the ${what}?" || return 1
  wizard::run_command "Stopping Platform" down || true
}

wizard::change_service_prefix() {
  _settings_view::stop_platform_first "service prefix" || return 0

  local value
  value=$(gum input --placeholder "New SERVICE_PREFIX" --value "$(settings::service_prefix)") || true
  [ -z "${value}" ] && return 0

  if ! settings::set_service_prefix "${value}"; then
    gum style --foreground 204 "❌ Invalid prefix. Must be lowercase alphanumeric, hyphens or underscores."
    sleep 2
  fi
}

wizard::change_port_offset() {
  _settings_view::stop_platform_first "port offset" || return 0

  local value
  value=$(gum input --placeholder "New PORT_OFFSET (number)" --value "$(settings::port_offset)") || true
  [ -z "${value}" ] && return 0
  settings::set_port_offset "${value}" || { gum style --foreground 204 "❌ The offset must be a number."; sleep 2; }
  return 0
}

wizard::change_build_profile() {
  local value
  value=$(gum choose "${SETTINGS_BUILD_PROFILES[@]}") || true
  [ -n "${value}" ] && settings::set_build_profile "${value}"
  return 0
}

_settings_view::custom_resources() {
  local entries=() s mem cpu current_mem current_cpu
  for s in "${SETTINGS_RESOURCE_SERVICES[@]}"; do
    current_mem="$(settings::resource_limit MEM "${s}")"
    current_cpu="$(settings::resource_limit CPU "${s}")"

    echo -e "\n${C_BOLD}${C_MAGENTA}⚙️  Configuring ${s}${C_RESET}"
    mem=$(gum input --header "Memory Limit (e.g., 2G, 512M):" --value "${current_mem}") || true
    cpu=$(gum input --header "CPU Limit (e.g., 1.0, 0.5):" --value "${current_cpu}") || true
    entries+=("${s}|${mem:-$current_mem}|${cpu:-$current_cpu}")
  done
  settings::save_custom_resources "${entries[@]}"
}

wizard::change_resource_profile() {
  local choice
  choice=$(gum choose "${SETTINGS_RESOURCE_PROFILES[@]}") || true
  case "${choice}" in
    "")     return 0 ;;
    custom) _settings_view::custom_resources ;;
    *)      settings::apply_resource_profile "${choice}" ;;
  esac
}

wizard::configure_external_solr() {
  local value
  value=$(gum input --placeholder "External Solr URL (leave empty for internal Docker Solr)" \
    --value "$(settings::external_solr)") || true
  settings::set_external_solr "${value}"
  if [ -n "${value}" ]; then
    gum style --foreground 114 "📡 External Solr configured: ${value}"
  else
    gum style --foreground 114 "🟢 Using internal Docker Solr."
  fi
  sleep 2
}
