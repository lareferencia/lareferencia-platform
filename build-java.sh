#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-}"
JAVA_MODULES='lareferencia-oclc-harvester,lareferencia-core-lib,lareferencia-entity-lib,lareferencia-indexing-filters-lib,lareferencia-shell-entity-plugin,lareferencia-shell,lareferencia-dark-lib,lareferencia-lrharvester-app,lareferencia-entity-rest,lareferencia-oai-pmh'

command -v mvn >/dev/null 2>&1 || { echo 'Maven is required.' >&2; exit 1; }

args=(clean install -pl "$JAVA_MODULES" -am -DskipTests -Dmaven.javadoc.skip=true)
[ -n "$PROFILE" ] && args+=("-P${PROFILE}")

cd "$ROOT_DIR"
echo 'Building Java modules only; Admin Web and Repository Dashboard are excluded.'
mvn "${args[@]}"
