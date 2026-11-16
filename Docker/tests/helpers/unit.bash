#!/usr/bin/env bash
# =============================================================================
# unit.bash — bats helper for the unit tests of the Solr scripts.
#
# Unlike the contract tests, these run the REAL Docker/solr/stage-cores.sh and
# Docker/solr/entrypoint.sh, over fixture directories and local git
# repositories created in $BATS_TEST_TMPDIR. No network, no Docker.
#
#   load ../helpers/unit
#
#   unit::git <args>              real git with an isolated, fixed identity
#   unit::commit <dir> <message>  git add -A + commit
#   inode_of <path>               inode number (the bind mount must survive)
#   assert_success / assert_failure / assert_output_contains / refute_output_contains
# =============================================================================

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${TESTS_DIR}/../.." && pwd)"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.org
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.org

unit::git() { git -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }

unit::commit() {
  unit::git -C "$1" add -A
  unit::git -C "$1" commit -q -m "$2"
}

inode_of() { ls -di "$1" | awk '{print $1}'; }

_fail() {
  printf '%s\n' "$@" >&2
  return 1
}

assert_success() {
  [ "${status}" -eq 0 ] || _fail "expected success, got exit ${status}" "--- output ---" "${output}"
}

assert_failure() {
  [ "${status}" -ne 0 ] || _fail "expected failure, got exit 0" "--- output ---" "${output}"
}

assert_output_contains() {
  [[ "${output}" == *"$1"* ]] || _fail "output does not contain: $1" "--- output ---" "${output}"
}

refute_output_contains() {
  if [[ "${output}" == *"$1"* ]]; then
    _fail "output unexpectedly contains: $1" "--- output ---" "${output}"
  fi
}
