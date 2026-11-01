#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="${ROOT_DIR}/lareferencia-repository-dashboard"
HARVESTER_DIR="${HARVESTER_APP_DIR:-${ROOT_DIR}/lareferencia-lrharvester-app}"
ANGULAR_DIR="${DASHBOARD_DIR}/angular"
STATIC_DIR="${HARVESTER_DIR}/dashboard-static"

command -v docker >/dev/null 2>&1 || { echo 'Docker is required to build the repository dashboard.' >&2; exit 1; }
[ -f "${ANGULAR_DIR}/package.json" ] || { echo "Dashboard Angular project not found: ${ANGULAR_DIR}" >&2; exit 1; }
[ -f "${DASHBOARD_DIR}/angular/package-lock.json" ] || { echo "Dashboard package-lock.json not found: ${DASHBOARD_DIR}/angular" >&2; exit 1; }
[ -d "${HARVESTER_DIR}" ] || { echo "Harvester app not found: ${HARVESTER_DIR}" >&2; exit 1; }

# Outputs left by a container that ran as root (e.g. docker-dev.sh, or a run
# with sudo) cannot be replaced by this user: give them back first.
"${ROOT_DIR}/Docker/scripts/reclaim-ownership.sh" "${HARVESTER_DIR}" dashboard-static
[ -w "${HARVESTER_DIR}" ] || {
  echo "Error: ${HARVESTER_DIR} is not writable by $(id -un) (uid $(id -u))." >&2
  echo "Fix it with: sudo chown -R $(id -u):$(id -g) ${HARVESTER_DIR}" >&2
  exit 1
}

# Keep Node inside the container: official host binaries require newer glibc.
# Node 18 matches the Angular dashboard runtime configured in its Maven POM.
echo 'Building the Angular Repository Dashboard with Node 18 in Docker...'
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e NPM_CONFIG_CACHE=/tmp/npm-cache \
  -v "${ANGULAR_DIR}:/workspace/dashboard:ro" \
  -v "${HARVESTER_DIR}:/workspace/harvester" \
  node:18-bookworm-slim \
  sh -ec '
    mkdir -p /tmp/app
    tar -C /workspace/dashboard --exclude=node_modules --exclude=dist --exclude=.git -cf - . | tar -C /tmp/app -xf -
    cd /tmp/app
    npm ci --no-audit --no-fund
    npm run build
    rm -rf /workspace/harvester/dashboard-static
    mkdir -p /workspace/harvester/dashboard-static
    cp -a dist/frontend/. /workspace/harvester/dashboard-static/
  '

echo "Dashboard built and published to ${STATIC_DIR}"
