#!/usr/bin/env bash
# =============================================================================
# wizard/status.sh — View: environment checks and module status widgets.
#
#   wizard::require_docker          renders missing tools and aborts
#   wizard::dependency_badges       "✓ Docker|✓ Compose|✓ Daemon"
#   wizard::print_module_columns    gum grid of modules/services (main menu)
# =============================================================================

wizard::require_docker() {
  local missing
  missing="$(system::missing_docker_tools)"
  [ -z "${missing}" ] && return 0

  echo -e "${C_RED}${C_BOLD}❌ FATAL ERROR: Missing required tools:${C_RESET}"
  local tool
  while IFS= read -r tool; do
    echo -e "  - ${tool}"
  done <<< "${missing}"
  echo -e "\nPlease install Docker and the Docker Compose plugin to use this wizard."
  echo -e "Documentation: https://docs.docker.com/get-docker/"
  exit 1
}

# _wizard::badge <check-function> <label>
_wizard::badge() {
  if "$1"; then
    printf "%s" "${C_GREEN}✓${C_RESET} $2"
  else
    printf "%s" "${C_RED}✗${C_RESET} $2"
  fi
}

wizard::dependency_badges() {
  printf "%s|%s|%s" \
    "$(_wizard::badge system::buildx_available "Docker & Buildx")" \
    "$(_wizard::badge system::compose_available "Compose")" \
    "$(_wizard::badge system::daemon_running "Daemon")"
}

# One gum-styled block per module (harvester is shown together with core).
_wizard::module_block() {
  local module="$1" running="$2"
  local color="245" icon="○" title services service

  module::is_on "${module}" && { color="114"; icon="●"; }

  title="$(echo "${module}" | tr '[:lower:]' '[:upper:]')"
  services="$(module::services "${module}")"
  if [ "${module}" = "core" ]; then
    title="CORE & HARVESTER"
    services="${services} $(module::services harvester)"
  fi

  local content="${icon} ${title}"$'\n'"──────────────"
  for service in ${services}; do
    if printf "%s\n" "${running}" | grep -Fxq "${service}"; then
      content="${content}"$'\n'" ${C_GREEN}⚡${C_RESET} ${service}${C_YELLOW}$(ports::for_service "${service}")${C_RESET}"
    else
      content="${content}"$'\n'" ${C_GRAY}○${C_RESET} ${service}"
    fi
  done

  gum style --padding "0 1" --margin "0 2" --width 28 --foreground "${color}" "${content}"
}

wizard::print_module_columns() {
  local running module blocks=()
  running="$(compose::running_services)"

  for module in $(module::all); do
    [ "${module}" = "harvester" ] && continue
    blocks+=("$(_wizard::module_block "${module}" "${running}")")
  done

  # Lay blocks out in rows of three.
  local rows=() i
  for ((i = 0; i < ${#blocks[@]}; i += 3)); do
    rows+=("$(gum join --horizontal "${blocks[@]:i:3}")")
  done
  gum join --vertical "${rows[@]}"
}
