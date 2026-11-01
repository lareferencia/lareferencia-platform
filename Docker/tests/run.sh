#!/usr/bin/env bash
# =============================================================================
# run.sh — test runner for Docker/docker.sh.
#
#   ./Docker/tests/run.sh              lint + contract (default, ~1 min)
#   ./Docker/tests/run.sh lint         syntax, shellcheck, undefined functions
#   ./Docker/tests/run.sh contract     docker.sh commands against fake docker/git
#   ./Docker/tests/run.sh contract -f "reset"    only tests whose name matches
#
#   UPDATE_SNAPSHOTS=1 ./Docker/tests/run.sh contract
#       accepts the current calls as the new expected snapshots
#       (review the result with `git diff Docker/tests/contract/snapshots`)
#
# Nothing here touches the real checkout, .env, Docker daemon or network:
# see Docker/tests/helpers/sandbox.bash. The only download is the test tools
# (bats, shellcheck), pinned and checksum-verified, into Docker/tests/.bin.
# =============================================================================
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
# shellcheck source=lib/tools.sh
source "${TESTS_DIR}/lib/tools.sh"

C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'

section() { printf '\n%s== %s ==%s\n' "${C_BOLD}" "$1" "${C_RESET}"; }
ok()      { printf '  %s✔%s %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
ko()      { printf '  %s✘%s %s\n' "${C_RED}" "${C_RESET}" "$1"; }

# Every shell file of docker.sh (templates are standalone scripts).
_shell_files() {
  cd "${DOCKER_DIR}"
  printf '%s\n' docker.sh lib/*.sh lib/core/*.sh lib/wizard/*.sh lib/templates/*.sh
}

# --- lint ------------------------------------------------------------------------------

lint::syntax() {
  local f failed=0
  while IFS= read -r f; do
    bash -n "${DOCKER_DIR}/${f}" || failed=1
  done < <(_shell_files)
  return "${failed}"
}

lint::shellcheck() {
  local shellcheck files=()
  shellcheck="$(tools::shellcheck)" || return 1
  while IFS= read -r f; do files+=("${f}"); done < <(_shell_files)
  # .shellcheckrc in Docker/ holds the project configuration.
  ( cd "${DOCKER_DIR}" && "${shellcheck}" --severity=warning --format=gcc "${files[@]}" )
}

# Every `namespace::function` referenced in the code must be defined somewhere.
lint::undefined_functions() {
  local files=() defined used missing
  while IFS= read -r f; do
    [[ "${f}" == lib/templates/* ]] || files+=("${DOCKER_DIR}/${f}")
  done < <(_shell_files)

  defined="$(grep -hoE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z0-9_]+)+[[:space:]]*\(\)' "${files[@]}" \
    | tr -d ' ()' | sort -u)"
  used="$(sed -E 's/(^|[[:space:]])#.*$//' "${files[@]}" \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z0-9_]+)+' | sort -u)"
  missing="$(comm -13 <(echo "${defined}") <(echo "${used}"))"

  if [ -n "${missing}" ]; then
    echo "Called but never defined:"
    printf '    %s\n' ${missing}
    return 1
  fi
}

run_lint() {
  section "lint"
  local failed=0 check
  for check in "syntax (bash -n)|lint::syntax" \
               "shellcheck|lint::shellcheck" \
               "every namespace::function is defined|lint::undefined_functions"; do
    if "${check#*|}"; then ok "${check%%|*}"; else ko "${check%%|*}"; failed=1; fi
  done
  return "${failed}"
}

# --- contract ----------------------------------------------------------------------------

run_contract() {
  section "contract (docker.sh with fake docker/git)"
  local bats
  bats="$(tools::bats)" || return 1
  "${bats}" --print-output-on-failure "$@" "${TESTS_DIR}/contract"
}

# --- main --------------------------------------------------------------------------------

main() {
  local suite="${1:-all}"
  [ "$#" -gt 0 ] && shift

  case "${suite}" in
    lint)     run_lint ;;
    contract) run_contract "$@" ;;
    all)
      local failed=0
      run_lint || failed=1
      run_contract "$@" || failed=1
      return "${failed}"
      ;;
    -h|--help|help)
      sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      ;;
    *)
      echo "Unknown suite: ${suite} (use: lint | contract | all)" >&2
      return 1
      ;;
  esac
}

main "$@"
