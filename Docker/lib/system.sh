#!/usr/bin/env bash
# =============================================================================
# system.sh — "System": host requirements (docker, compose, daemon).
#
# Public API:
#   system::docker_installed
#   system::buildx_available
#   system::compose_available         docker compose (v2) or docker-compose (v1)
#   system::daemon_running
#   system::missing_docker_tools      prints one line per missing tool
#   system::retry_on_network_error <cmd...>
#                                     runs <cmd>; repeats it only when it failed
#                                     because of the network (image pulls)
# =============================================================================

system::docker_installed() {
  cmd::exists docker
}

system::buildx_available() {
  system::docker_installed && docker buildx version >/dev/null 2>&1
}

system::compose_available() {
  docker compose version >/dev/null 2>&1 || cmd::exists docker-compose
}

system::daemon_running() {
  docker info >/dev/null 2>&1
}

system::missing_docker_tools() {
  system::docker_installed  || echo "docker (Engine)"
  system::compose_available || echo "docker compose or docker-compose (V1/V2)"
  return 0
}

# --- Network retries ------------------------------------------------------------------
#
# Image pulls (compose build/up/pull) on unstable links fail with messages like
#   failed to copy: read tcp ...: read: connection timed out
# Docker keeps the layers already downloaded, so running the same command again
# resumes where it stopped. Real failures (a broken Dockerfile, a failed test)
# do not match the pattern and are never repeated.
#
# Settings (Docker/.env): DOCKER_NETWORK_ATTEMPTS (default 3),
#                         DOCKER_NETWORK_RETRY_DELAY (seconds, default 10, grows per attempt)

SYSTEM_NETWORK_ERROR_PATTERN='connection timed out|connection reset|connection refused|i/o timeout|TLS handshake timeout|unexpected EOF|failed to copy|failed to do request|net/http: request canceled|temporary failure in name resolution|no such host|network is unreachable|502 Bad Gateway|503 Service Unavailable|504 Gateway Time-?out'

# system::retry_on_network_error <cmd...>
#   stdout and stderr of <cmd> are merged (and still shown as they happen).
system::retry_on_network_error() {
  local attempts delay attempt=1 status log
  attempts="$(config::get DOCKER_NETWORK_ATTEMPTS 3)"
  delay="$(config::get DOCKER_NETWORK_RETRY_DELAY 10)"
  [[ "${attempts}" =~ ^[1-9][0-9]*$ ]] || attempts=3
  [[ "${delay}" =~ ^[0-9]+$ ]] || delay=10
  log="$(mktemp "${TMPDIR:-/tmp}/lareferencia-net.XXXXXX")"

  while true; do
    status=0
    "$@" 2>&1 | tee "${log}" || status="${PIPESTATUS[0]}"
    [ "${status}" -eq 0 ] && break
    grep -Eqi "${SYSTEM_NETWORK_ERROR_PATTERN}" "${log}" || break   # not a network error

    if [ "${attempt}" -ge "${attempts}" ]; then
      echo "Error: network failure persisted after ${attempts} attempt(s) (downloading images)." >&2
      echo "  Run the same action again: layers already downloaded are kept." >&2
      echo "  More attempts: DOCKER_NETWORK_ATTEMPTS in Docker/.env. Frequent timeouts in a VM" >&2
      echo "  usually mean an MTU problem (see 'ip link' / the Docker 'mtu' daemon option)." >&2
      break
    fi
    echo "⚠️  Network failure while downloading images; retrying in $((attempt * delay))s (attempt $((attempt + 1))/${attempts})..." >&2
    sleep $((attempt * delay))
    attempt=$((attempt + 1))
  done

  rm -f "${log}"
  return "${status}"
}
