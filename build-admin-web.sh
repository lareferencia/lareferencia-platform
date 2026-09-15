#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_DIR="${ROOT_DIR}/lareferencia-lrharvester-admin-web"
HARVESTER_DIR="${HARVESTER_APP_DIR:-${ROOT_DIR}/lareferencia-lrharvester-app}"
STATIC_DIR="${HARVESTER_DIR}/static"

command -v docker >/dev/null 2>&1 || { echo 'Docker is required to build the admin web.' >&2; exit 1; }
[ -f "${ADMIN_DIR}/package.json" ] || { echo "Admin web not found: ${ADMIN_DIR}" >&2; exit 1; }
[ -f "${ADMIN_DIR}/package-lock.json" ] || { echo "package-lock.json not found: ${ADMIN_DIR}" >&2; exit 1; }
[ -d "${HARVESTER_DIR}" ] || { echo "Harvester app not found: ${HARVESTER_DIR}" >&2; exit 1; }

echo 'Building the admin web with Node 22 in Docker...'
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e NPM_CONFIG_CACHE=/tmp/npm-cache \
  -v "${ADMIN_DIR}:/workspace/admin-web" \
  -v "${HARVESTER_DIR}:/workspace/harvester" \
  -w /workspace/admin-web \
  node:22-bookworm-slim \
  sh -ec 'npm ci --no-audit --no-fund && npm run build && rm -rf /workspace/harvester/static && mkdir -p /workspace/harvester/static && cp -a dist/. /workspace/harvester/static/'

echo "Admin web built and published to ${STATIC_DIR}"
