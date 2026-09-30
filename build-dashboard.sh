#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="${ROOT_DIR}/lareferencia-repository-dashboard"
HARVESTER_DIR="${HARVESTER_APP_DIR:-${ROOT_DIR}/lareferencia-lrharvester-app}"

command -v mvn >/dev/null 2>&1 || { echo 'Maven is required to build the repository dashboard.' >&2; exit 1; }
[ -f "${DASHBOARD_DIR}/pom.xml" ] || { echo "Dashboard Maven project not found: ${DASHBOARD_DIR}" >&2; exit 1; }
[ -f "${DASHBOARD_DIR}/angular/package-lock.json" ] || { echo "Dashboard package-lock.json not found: ${DASHBOARD_DIR}/angular" >&2; exit 1; }
[ -d "${HARVESTER_DIR}" ] || { echo "Harvester app not found: ${HARVESTER_DIR}" >&2; exit 1; }

echo 'Building the Angular Repository Dashboard with the Node version pinned in its Maven POM...'
mvn -f "${DASHBOARD_DIR}/pom.xml" -Ddashboard.static.dir="${HARVESTER_DIR}/dashboard-static" package

echo "Dashboard built and published to ${HARVESTER_DIR}/dashboard-static"
