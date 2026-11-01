#!/usr/bin/env bash
# =============================================================================
# workspace.sh — "Workspace": the Java source modules cloned next to this repo
# (managed by the `githelper` tool and listed in workspace.ini).
#
# Public API:
#   workspace::ensure_java_modules [pull:true|false]
#       clones missing modules (and optionally pulls existing ones)
#   workspace::cloned_modules        lists module dirs that are git checkouts
#   workspace::remove_modules <dir...>
# =============================================================================

JAVA_PARENT_MODULES=(
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

# Runs ./githelper (directly when executable, otherwise through python3).
workspace::githelper() {
  if [ -x "${ROOT_DIR}/githelper" ]; then
    "${ROOT_DIR}/githelper" "$@"
  else
    python3 "${ROOT_DIR}/githelper" "$@"
  fi
}

# Prints the Java modules whose pom.xml is missing.
workspace::missing_java_modules() {
  local module
  for module in "${JAVA_PARENT_MODULES[@]}"; do
    [ -f "${ROOT_DIR}/${module}/pom.xml" ] || echo "${module}"
  done
  return 0
}

workspace::ensure_java_modules() {
  local pull_existing="${1:-false}"
  local missing
  missing="$(workspace::missing_java_modules)"

  if [ -n "${missing}" ]; then
    echo "Missing initialized Java workspace modules (pom.xml absent):" >&2
    printf '  - %s\n' ${missing} >&2
    echo "Cloning missing modules using githelper..." >&2
    workspace::githelper init \
      --jobs "$(config::get GIT_CLONE_JOBS 4)" \
      --depth "$(config::get GIT_CLONE_DEPTH 1)" \
      --modules "$(echo ${missing} | tr ' ' ',')"
  fi

  if [ "${pull_existing}" = "true" ]; then
    echo "Pulling updates for existing modules using githelper..." >&2
    workspace::githelper pull || true
  fi

  if [ -n "$(workspace::missing_java_modules)" ]; then
    echo "Error: Some modules are still missing after initialization." >&2
    return 1
  fi
}

# Module paths declared as [module.*] sections in workspace.ini.
workspace::manifest_paths() {
  python3 - "${ROOT_DIR}/workspace.ini" <<'PY'
import configparser
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
parser = configparser.ConfigParser(interpolation=None)
parser.optionxform = str
try:
    if not parser.read(manifest):
        raise ValueError(f"could not read {manifest}")
    paths = []
    for section in parser.sections():
        if not section.startswith("module."):
            continue
        name = section[len("module."):].strip()
        path = parser.get(section, "path", fallback=name).strip() or name
        candidate = Path(path)
        if not name or not path or path in {".", ".."} or candidate.is_absolute() or ".." in candidate.parts:
            raise ValueError(f"invalid module path in [{section}]: {path!r}")
        if "\n" in path or "\r" in path:
            raise ValueError(f"invalid module path in [{section}]: newline is not allowed")
        paths.append(path)
    if not paths:
        raise ValueError(f"{manifest} contains no [module.*] sections")
    print("\n".join(paths))
except Exception as error:
    print(f"Error reading workspace module paths: {error}", file=sys.stderr)
    sys.exit(1)
PY
}

# Only initialized nested git checkouts named by the manifest are listed.
workspace::cloned_modules() {
  local paths module
  paths="$(workspace::manifest_paths)" || return 1
  while IFS= read -r module; do
    [ -n "${module}" ] || continue
    [ -d "${ROOT_DIR}/${module}" ] && [ -e "${ROOT_DIR}/${module}/.git" ] && echo "${module}"
  done <<< "${paths}"
  return 0
}

workspace::remove_modules() {
  [ "$#" -gt 0 ] || return 0

  if cmd::exists docker; then
    echo "Fixing permissions for cloned modules using Docker..."
    local targets="" module
    for module in "$@"; do
      targets="${targets} /workspace/${module}"
    done
    docker run --rm -v "${ROOT_DIR}:/workspace" alpine sh -c "chmod -R ugo+rwX ${targets} 2>/dev/null" || true
  fi

  for module in "$@"; do
    echo "Removing cloned module directory: ${module}"
    rm -rf "${ROOT_DIR:?}/${module}"
  done
}
