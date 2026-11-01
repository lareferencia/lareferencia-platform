#!/usr/bin/env bash
# =============================================================================
# reclaim-ownership.sh — gives build outputs back to the current user.
#
#   Docker/scripts/reclaim-ownership.sh <base dir> <path>...
#       <path> is relative to <base dir>; globs are allowed (e.g. '*/target').
#
# Containers that write into the checkout as root (the dev `maven-builder`,
# a wizard run with sudo, ...) leave files the normal user cannot delete, and
# the next build fails with "rm: cannot remove ...: Permission denied".
#
# The check runs on the host first: only paths that really contain files of
# another owner are fixed, with a short-lived alpine container (no sudo).
# Nothing to do when running as root.
# =============================================================================
set -euo pipefail

base="${1:?usage: reclaim-ownership.sh <base dir> <path>...}"
shift

uid="$(id -u)"
gid="$(id -g)"
[ "${uid}" = 0 ] && exit 0
cd "${base}"

shopt -s nullglob
targets=()
for pattern in "$@"; do
  # shellcheck disable=SC2206 # the pattern is expanded on purpose (globs)
  matches=(${pattern})
  for path in ${matches[@]+"${matches[@]}"}; do
    [ -e "${path}" ] || continue
    # A directory we cannot read is reported itself (it is not ours either).
    if [ -n "$(find "${path}" ! -user "${uid}" -print -quit 2>/dev/null || echo unreadable)" ]; then
      targets+=("${path}")
    fi
  done
done
[ "${#targets[@]}" -gt 0 ] || exit 0

echo "Fixing ownership of files created by another user (e.g. root): ${targets[*]}"
docker run --rm -v "${PWD}:/workspace" -w /workspace alpine \
  chown -R "${uid}:${gid}" -- "${targets[@]}" \
  || echo "Warning: could not fix ownership; run: sudo chown -R ${uid}:${gid} ${targets[*]} (in ${PWD})" >&2
