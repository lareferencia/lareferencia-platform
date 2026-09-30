#!/bin/bash
set -eou pipefail

REACTOR_MODULES=(
  lareferencia-oclc-harvester
  lareferencia-core-lib
  lareferencia-entity-lib
  lareferencia-indexing-filters-lib
  lareferencia-shell-entity-plugin
  lareferencia-shell
  lareferencia-dark-lib
  lareferencia-lrharvester-admin-web
  lareferencia-repository-dashboard
  lareferencia-lrharvester-app
  lareferencia-entity-rest
  lareferencia-oai-pmh
)

ensure_reactor_modules_ready() {
  local root_dir
  local missing=()
  local module

  root_dir="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"

  for module in "${REACTOR_MODULES[@]}"; do
    if [ ! -f "${root_dir}/${module}/pom.xml" ]; then
      missing+=("${module}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Faltan módulos del reactor inicializados (pom.xml ausente):" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    echo "Ejecutando: ./githelper init para clonar modulos..." >&2
    if [ -x "${root_dir}/githelper" ]; then
      "${root_dir}/githelper" init
    else
      python3 "${root_dir}/githelper" init
    fi
  fi

  # Re-verificar
  missing=()
  for module in "${REACTOR_MODULES[@]}"; do
    if [ ! -f "${root_dir}/${module}/pom.xml" ]; then
      missing+=("${module}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Error: Aun faltan modulos despues de la inicializacion." >&2
    exit 1
  fi
}

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [lite|lareferencia|ibict|rcaap]" >&2
  exit 2
fi

PROFILE="${1:-lite}"
case "${PROFILE}" in
  lite|lareferencia|ibict|rcaap) ;;
  *) echo "Unknown build profile: ${PROFILE}" >&2; echo "Usage: $0 [lite|lareferencia|ibict|rcaap]" >&2; exit 2 ;;
esac

ensure_reactor_modules_ready
cd "$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
mvn clean install -DskipTests -Dmaven.javadoc.skip=true "-P${PROFILE}"
