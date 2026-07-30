#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"

JAVA_PARENT_MODULES=(
  lareferencia-oclc-harvester
  lareferencia-core-lib
  lareferencia-entity-lib
  lareferencia-contrib-rcaap
  lareferencia-contrib-ibict
  lareferencia-indexing-filters-lib
  lareferencia-shell-entity-plugin
  lareferencia-shell
  lareferencia-dark-lib
  lareferencia-lrharvester-app
  lareferencia-entity-rest
  lareferencia-dashboard-rest
)

ensure_java_parent_modules_ready() {
  local missing=()
  local module

  for module in "${JAVA_PARENT_MODULES[@]}"; do
    if [ ! -f "${ROOT_DIR}/${module}/pom.xml" ]; then
      missing+=("${module}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Faltan modulos Java inicializados:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Ejecutando ./githelper init para descargar el workspace 4.2.7..." >&2
    "${ROOT_DIR}/githelper" init
  fi

  for module in "${JAVA_PARENT_MODULES[@]}"; do
    if [ ! -f "${ROOT_DIR}/${module}/pom.xml" ]; then
      echo "Error: falta ${module}/pom.xml despues de inicializar el workspace." >&2
      exit 1
    fi
  done
}

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "Usage: $0 <profile>" >&2
  echo "  profiles: lite, lareferencia, ibict, rcaap" >&2
  exit 1
fi

ensure_java_parent_modules_ready

mvn --settings "${ROOT_DIR}/.mvn/settings.xml" \
  clean package install \
  -DskipTests \
  -Dmaven.javadoc.skip=true \
  -P"$1"
