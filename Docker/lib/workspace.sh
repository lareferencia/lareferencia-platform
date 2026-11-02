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

# A checkout with .git but no commit is what an interrupted clone leaves
# behind; githelper would report it as "already exists" forever.
_workspace::remove_incomplete_clones() {
  local module
  for module in "$@"; do
    [ -d "${ROOT_DIR}/${module}/.git" ] || continue
    [ -f "${ROOT_DIR}/${module}/pom.xml" ] && continue
    git --git-dir="${ROOT_DIR}/${module}/.git" rev-parse --verify --quiet HEAD >/dev/null 2>&1 && continue
    echo "Removing incomplete clone: ${module}" >&2
    rm -rf "${ROOT_DIR:?}/${module}"
  done
}

# _workspace::clone <attempt> <module...>
#   Retries run one clone at a time and over HTTP/1.1, which survives the
#   "RPC failed; curl 56 ... Connection reset by peer" of unstable networks.
_workspace::clone() {
  local attempt="$1"
  shift
  local jobs depth
  jobs="$(config::get GIT_CLONE_JOBS 4)"
  depth="$(config::get GIT_CLONE_DEPTH 1)"
  local modules
  modules="$(echo "$@" | tr ' ' ',')"

  if [ "${attempt}" -eq 1 ]; then
    workspace::githelper init --jobs "${jobs}" --depth "${depth}" --modules "${modules}"
  else
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.version GIT_CONFIG_VALUE_0=HTTP/1.1 \
      workspace::githelper init --jobs 1 --depth "${depth}" --modules "${modules}"
  fi
}

workspace::ensure_java_modules() {
  local pull_existing="${1:-false}"
  local missing attempts delay attempt=1
  missing="$(workspace::missing_java_modules)"
  attempts="$(config::get GIT_CLONE_ATTEMPTS 3)"
  delay="$(config::get GIT_CLONE_RETRY_DELAY 5)"
  [[ "${attempts}" =~ ^[1-9][0-9]*$ ]] || attempts=3
  [[ "${delay}" =~ ^[0-9]+$ ]] || delay=5

  if [ -n "${missing}" ]; then
    echo "Missing initialized Java workspace modules (pom.xml absent):" >&2
    printf '  - %s\n' ${missing} >&2
    echo "Cloning missing modules using githelper..." >&2
  fi

  while [ -n "${missing}" ]; do
    if [ "${attempt}" -gt 1 ]; then
      echo "Retrying the clone of: $(echo ${missing}) (attempt ${attempt}/${attempts}, one at a time, HTTP/1.1)..." >&2
      sleep $(( (attempt - 1) * delay ))
      _workspace::remove_incomplete_clones ${missing}
    fi
    # githelper exits non-zero when any clone fails: decide by what is missing.
    _workspace::clone "${attempt}" ${missing} || true
    missing="$(workspace::missing_java_modules)"
    [ "${attempt}" -ge "${attempts}" ] && break
    attempt=$((attempt + 1))
  done

  if [ "${pull_existing}" = "true" ]; then
    echo "Pulling updates for existing modules using githelper..." >&2
    workspace::githelper pull || true
  fi

  missing="$(workspace::missing_java_modules)"
  if [ -n "${missing}" ]; then
    echo "Error: could not clone after ${attempts} attempt(s): $(echo ${missing})" >&2
    echo "  Usually a network problem (connection reset/timeout). Run the same action again:" >&2
    echo "  only the missing modules are cloned. More attempts: GIT_CLONE_ATTEMPTS in Docker/.env" >&2
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
