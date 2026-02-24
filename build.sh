#!/bin/bash
set -eou pipefail

JAVA_PARENT_MODULES=(
  lareferencia-oclc-harvester
  lareferencia-core-lib
  lareferencia-entity-lib
  lareferencia-indexing-filters-lib
  lareferencia-shell-entity-plugin
  lareferencia-shell
  lareferencia-dark-lib
  lareferencia-lrharvester-app
  lareferencia-entity-rest
  lareferencia-dashboard-rest
)

ensure_java_parent_modules_ready() {
  local root_dir
  local missing=()
  local module

  root_dir="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"

  for module in "${JAVA_PARENT_MODULES[@]}"; do
    if [ ! -f "${root_dir}/${module}/pom.xml" ]; then
      missing+=("${module}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Faltan submódulos Java inicializados (pom.xml ausente):" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Ejecuta: ./githelper pull" >&2
    exit 1
  fi
}

# check parameters passed to script and print usage
if [ $# -lt 1 ]; then
  echo "Usage: $0 <profile>"
  echo "  profile: profile to build (default: lite)"
  echo "  options: lite, lareferencia, ibict, rcaap"

  exit 1
fi

ensure_java_parent_modules_ready

if [ -z "$1" ]; then
   mvn clean package install -DskipTests -Dmaven.javadoc.skip=true
else
   mvn clean package install -DskipTests -Dmaven.javadoc.skip=true -P$1
fi
