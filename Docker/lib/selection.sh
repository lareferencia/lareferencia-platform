#!/usr/bin/env bash
# =============================================================================
# selection.sh — "ServiceSelection": the set of compose services (and the
# compose profiles they need) that a command is going to act on.
#
# State (read it after calling the methods below):
#   SELECTED_SERVICES   ordered, de-duplicated list of services
#   SELECTED_PROFILES   compose profiles required by SELECTED_SERVICES
#
# Public API:
#   selection::clear
#   selection::add_services <service...>
#   selection::add_modules <module...>        adds every service of each module
#   selection::from_args_or_enabled <service...>
#       explicit services if given, otherwise the services of enabled modules
#   selection::drop_vufind_if_not_cloned <explicit:true|false>
#   selection::has <service>
#   selection::is_empty
#   selection::run <compose args...>          dc --profile ... <args> <services>
# =============================================================================

SELECTED_SERVICES=()
SELECTED_PROFILES=()

selection::clear() {
  SELECTED_SERVICES=()
  SELECTED_PROFILES=()
}

selection::has() {
  list::contains "$1" ${SELECTED_SERVICES[@]+"${SELECTED_SERVICES[@]}"}
}

selection::is_empty() {
  [ "${#SELECTED_SERVICES[@]}" -eq 0 ]
}

# True when any selected service needs the VuFind checkout.
selection::needs_vufind() {
  local s
  for s in ${SELECTED_SERVICES[@]+"${SELECTED_SERVICES[@]}"}; do
    service::requires_vufind "${s}" && return 0
  done
  return 1
}

selection::has_java_service() {
  local s
  for s in ${SELECTED_SERVICES[@]+"${SELECTED_SERVICES[@]}"}; do
    service::is_java "${s}" && return 0
  done
  return 1
}

_selection::refresh_profiles() {
  SELECTED_PROFILES=()
  local s p
  for s in ${SELECTED_SERVICES[@]+"${SELECTED_SERVICES[@]}"}; do
    p="$(service::profile "${s}")"
    if [ -n "${p}" ] && ! list::contains "${p}" ${SELECTED_PROFILES[@]+"${SELECTED_PROFILES[@]}"}; then
      SELECTED_PROFILES+=("${p}")
    fi
  done
}

selection::add_services() {
  local s
  for s in "$@"; do
    selection::has "${s}" || SELECTED_SERVICES+=("${s}")
  done
  _selection::refresh_profiles
}

selection::add_modules() {
  local module
  for module in "$@"; do
    module::validate "${module}"
    # shellcheck disable=SC2046 # a module may own several services
    selection::add_services $(module::services "${module}")
  done
}

selection::from_args_or_enabled() {
  selection::clear
  if [ "$#" -gt 0 ]; then
    selection::add_services "$@"
  else
    # shellcheck disable=SC2046
    selection::add_modules $(module::enabled)
  fi
}

# Without a VuFind checkout, VuFind services are skipped unless the user asked
# for them explicitly (in which case they will trigger a clone later).
selection::drop_vufind_if_not_cloned() {
  local explicit="$1"
  if [ "${explicit}" = true ] || [ -d "${ROOT_DIR}/vufind" ]; then
    return 0
  fi

  local kept=() skipped=() s
  for s in ${SELECTED_SERVICES[@]+"${SELECTED_SERVICES[@]}"}; do
    if service::requires_vufind "${s}"; then
      skipped+=("${s}")
    else
      kept+=("${s}")
    fi
  done

  SELECTED_SERVICES=(${kept[@]+"${kept[@]}"})
  _selection::refresh_profiles

  if [ "${#skipped[@]}" -gt 0 ]; then
    echo "VuFind is not cloned; skipping services: ${skipped[*]}."
    echo "To include them explicitly: ./Docker/docker.sh up --vufind  (or ./Docker/docker.sh up vufind-web)"
  fi
}

# Runs `dc <args> <selected services>` with the profiles the selection needs.
selection::run() {
  compose::run_with_profiles ${SELECTED_PROFILES[@]+"${SELECTED_PROFILES[@]}"} -- \
    "$@" ${SELECTED_SERVICES[@]+"${SELECTED_SERVICES[@]}"}
}
