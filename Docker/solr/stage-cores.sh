#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SRC_OAI="${ROOT_DIR}/lareferencia-oai-pmh/solr.core/oai"
SRC_VUFIND="${ROOT_DIR}/vufind"
SRC_BIBLIO="${SRC_VUFIND}/solr/vufind/biblio"
SRC_JARS="${SRC_VUFIND}/solr/vufind/jars"
SRC_IMPORT="${SRC_VUFIND}/import"
SRC_VENDOR="${SRC_VUFIND}/solr/vendor/modules/analysis-extras/lib"

DST_CORES="${SCRIPT_DIR}/cores"
DST_JARS="${SCRIPT_DIR}/jars"
DST_IMPORT="${SCRIPT_DIR}/import"
DST_VENDOR="${SCRIPT_DIR}/vendor"

DEFAULT_VUFIND_REPO_URL="https://github.com/vufind-org/vufind"
DEFAULT_VUFIND_REF="v11.0.1"

# Helper to read environment variables from Docker/.env if present
get_env_val() {
  local var_name="$1" default_val="${2:-}"
  local env_file="${ROOT_DIR}/Docker/.env"
  if [ -n "${!var_name:-}" ]; then
    printf '%s\n' "${!var_name}"
    return 0
  fi
  if [ -f "${env_file}" ]; then
    local line
    line="$(grep -E "^${var_name}=" "${env_file}" 2>/dev/null | tail -n 1 || true)"
    if [ -n "${line}" ]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  fi
  printf '%s\n' "${default_val}"
}

echo "=== Staging Solr 9.11.0 assets and core configurations ==="

# 1. Ensure VuFind checkout is available
if [ ! -f "${SRC_VUFIND}/composer.json" ]; then
  repo_url="$(get_env_val VUFIND_REPO_URL "${DEFAULT_VUFIND_REPO_URL}")"
  repo_ref="$(get_env_val VUFIND_REF "${DEFAULT_VUFIND_REF}")"
  echo "VuFind checkout not found in ${SRC_VUFIND}."
  echo "Cloning VuFind (${repo_ref}) from ${repo_url}..."
  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to clone VuFind." >&2
    exit 1
  fi
  git clone --quiet --depth 1 --branch "${repo_ref}" --single-branch "${repo_url}" "${SRC_VUFIND}"
fi

# 2. Check OAI source directory (lareferencia-oai-pmh)
if [ ! -d "${SRC_OAI}" ]; then
  if [ -x "${ROOT_DIR}/githelper" ]; then
    echo "OAI source directory not found. Initializing lareferencia-oai-pmh using githelper..."
    "${ROOT_DIR}/githelper" init --modules lareferencia-oai-pmh 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1 && [ -f "${ROOT_DIR}/githelper" ]; then
    echo "OAI source directory not found. Initializing lareferencia-oai-pmh using githelper..."
    python3 "${ROOT_DIR}/githelper" init --modules lareferencia-oai-pmh 2>/dev/null || true
  fi
fi

# 3. Validate source core availability
has_oai=true
has_biblio=true

if [ ! -d "${SRC_OAI}" ]; then
  echo "Warning: OAI source core directory '${SRC_OAI}' does not exist yet." >&2
  echo "         OAI core staging will be deferred until lareferencia-oai-pmh is initialized." >&2
  has_oai=false
fi

if [ ! -d "${SRC_BIBLIO}" ]; then
  echo "Warning: Biblio source core directory '${SRC_BIBLIO}' does not exist in VuFind checkout!" >&2
  has_biblio=false
fi

if [ "${has_oai}" = false ] && [ "${has_biblio}" = false ]; then
  echo "Error: Neither OAI nor Biblio core directories are available. Cannot stage Solr cores." >&2
  exit 1
fi

# 4. Create destination staging directories
mkdir -p "${DST_CORES}/oai" "${DST_CORES}/biblio" "${DST_JARS}" "${DST_IMPORT}" "${DST_VENDOR}"

# 5. Stage OAI core from lareferencia-oai-pmh (if present)
if [ "${has_oai}" = true ]; then
  echo "Staging 'oai' core from lareferencia-oai-pmh/solr.core/oai..."
  rm -rf "${DST_CORES}/oai"
  mkdir -p "${DST_CORES}/oai"
  cp -a "${SRC_OAI}/." "${DST_CORES}/oai/"
  if [ ! -f "${DST_CORES}/oai/core.properties" ]; then
    echo "name=oai" > "${DST_CORES}/oai/core.properties"
  fi
fi

# 6. Stage Biblio core from vufind (if present)
if [ "${has_biblio}" = true ]; then
  echo "Staging 'biblio' core from vufind/solr/vufind/biblio..."
  rm -rf "${DST_CORES}/biblio"
  mkdir -p "${DST_CORES}/biblio"
  cp -a "${SRC_BIBLIO}/." "${DST_CORES}/biblio/"
  if [ ! -f "${DST_CORES}/biblio/core.properties" ]; then
    echo "name=biblio" > "${DST_CORES}/biblio/core.properties"
  fi
fi

# 7. Stage VuFind JARs and import assets
if [ -d "${SRC_JARS}" ]; then
  echo "Staging supporting JARs from vufind/solr/vufind/jars..."
  rm -rf "${DST_JARS}"
  mkdir -p "${DST_JARS}"
  cp -a "${SRC_JARS}/." "${DST_JARS}/"
fi

if [ -d "${SRC_IMPORT}" ]; then
  echo "Staging import assets from vufind/import..."
  rm -rf "${DST_IMPORT}"
  mkdir -p "${DST_IMPORT}"
  cp -a "${SRC_IMPORT}/." "${DST_IMPORT}/"
fi

if [ -d "${SRC_VENDOR}" ]; then
  cp "${SRC_VENDOR}"/icu4j-*.jar "${DST_VENDOR}/" 2>/dev/null || true
  cp "${SRC_VENDOR}"/lucene-analysis-icu-*.jar "${DST_VENDOR}/" 2>/dev/null || true
fi

# 8. Record source repository and revision used for each core
oai_repo="uninitialized"
oai_rev="none"
if [ "${has_oai}" = true ]; then
  oai_repo="$(git -C "${ROOT_DIR}/lareferencia-oai-pmh" config --get remote.origin.url 2>/dev/null || echo "lareferencia-oai-pmh")"
  oai_rev="$(git -C "${ROOT_DIR}/lareferencia-oai-pmh" rev-parse HEAD 2>/dev/null || echo "unknown")"
fi

vufind_repo="uninitialized"
vufind_rev="none"
if [ "${has_biblio}" = true ]; then
  vufind_repo="$(git -C "${SRC_VUFIND}" config --get remote.origin.url 2>/dev/null || echo "vufind")"
  vufind_rev="$(git -C "${SRC_VUFIND}" rev-parse HEAD 2>/dev/null || echo "unknown")"
fi

cat <<EOF > "${DST_CORES}/build-info.properties"
solr.version=9.11.0
core.oai.source=lareferencia-oai-pmh
core.oai.repository=${oai_repo}
core.oai.revision=${oai_rev}
core.biblio.source=vufind
core.biblio.repository=${vufind_repo}
core.biblio.revision=${vufind_rev}
staged_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

# Ensure gitkeep files remain present
touch "${DST_CORES}/.gitkeep" "${DST_JARS}/.gitkeep" "${DST_IMPORT}/.gitkeep"

echo "=== Staging complete. Source revisions recorded: ==="
cat "${DST_CORES}/build-info.properties"
echo "====================================================="
