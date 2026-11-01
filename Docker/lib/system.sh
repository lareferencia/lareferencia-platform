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
