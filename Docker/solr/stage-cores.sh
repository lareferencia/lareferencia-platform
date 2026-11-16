#!/usr/bin/env bash
# =============================================================================
# stage-cores.sh — prepares the Solr build context from the modules that own
# each core. Nothing here edits a core: files are copied byte for byte.
#
#   oai     lareferencia-oai-pmh/solr.core/oai/   (core.properties + conf/)
#   biblio  vufind/solr/vufind/biblio/            (VuFind checkout selected by
#                                                  VUFIND_REPO_URL / VUFIND_REF)
#   jars    vufind/solr/vufind/jars/              (same VuFind checkout)
#   import  vufind/import/                        (same VuFind checkout)
#
# Output (generated, git-ignored, bind-mounted read-only into the container):
#   Docker/solr/cores/{oai,biblio}/  Docker/solr/cores/build-info.properties
#   Docker/solr/jars/                Docker/solr/import/
#
# Usage:
#   stage-cores.sh            stage (default)
#   stage-cores.sh --check    compare the staged copy with the sources, change nothing
#
# Settings (environment > Docker/.env > default):
#   VUFIND_REPO_URL, VUFIND_REF   VuFind used by the deployment (also cloned when missing)
#   LR_SOLR_VUFIND_CHECK          warn (default) | strict | off
#       The biblio core always comes from ./vufind, the same checkout VuFind web
#       runs from, so Solr and VuFind never disagree. The check compares that
#       checkout with the configured VUFIND_REPO_URL / VUFIND_REF and local changes:
#       warn:   differences are reported, staging goes on (upgrades never block)
#       strict: any difference stops the staging (pinned deployments)
#               Only settings actually configured are compared: when VUFIND_REPO_URL
#               or VUFIND_REF is not set, ./vufind itself is the selection (the
#               built-in defaults are used only to clone a missing checkout).
#       warn:   same checks, reported as warnings
#       off:    no checks (revision is still recorded)
#
# Every check runs before the staging directories are touched: on failure the
# previous staging stays as it was. Directories are updated in place (never
# replaced) because a running Solr container bind-mounts them.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OAI_MODULE_DIR="${ROOT_DIR}/lareferencia-oai-pmh"
SRC_OAI="${OAI_MODULE_DIR}/solr.core/oai"
SRC_VUFIND="${ROOT_DIR}/vufind"
SRC_BIBLIO="${SRC_VUFIND}/solr/vufind/biblio"
SRC_JARS="${SRC_VUFIND}/solr/vufind/jars"
SRC_IMPORT="${SRC_VUFIND}/import"

DST_CORES="${SCRIPT_DIR}/cores"
DST_JARS="${SCRIPT_DIR}/jars"
DST_IMPORT="${SCRIPT_DIR}/import"

DEFAULT_VUFIND_REPO_URL="https://github.com/vufind-org/vufind"
DEFAULT_VUFIND_REF="v11.0.1"

ERRORS=()
WARNINGS=()

err()  { ERRORS+=("$*"); }
warn() { WARNINGS+=("$*"); }

# Value of a setting: environment, then Docker/.env (quotes removed), then default.
get_env_val() {
  local var_name="$1" default_val="${2:-}" env_file="${ROOT_DIR}/Docker/.env" value=""
  if [ -n "${!var_name:-}" ]; then
    printf '%s\n' "${!var_name}"
    return 0
  fi
  if [ -f "${env_file}" ]; then
    value="$(grep -E "^[[:space:]]*${var_name}[[:space:]]*=" "${env_file}" 2>/dev/null | tail -n 1 || true)"
    value="${value#*=}"
    value="$(printf '%s' "${value}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')"
  fi
  printf '%s\n' "${value:-${default_val}}"
}

# https://github.com/Org/Repo(.git)(/), git@github.com:Org/Repo.git and
# ssh://git@github.com/Org/Repo are the same repository.
normalize_repo_url() {
  local url="$1"
  url="${url%/}"
  url="${url%.git}"
  case "${url}" in
    git@*:*)      url="${url#git@}"; url="https://${url/://}" ;;
    ssh://git@*)  url="https://${url#ssh://git@}" ;;
  esac
  # drop credentials (https://user:token@host/...)
  url="$(printf '%s' "${url}" | sed -E 's#^([a-z]+://)[^/@]+@#\1#')"
  printf '%s\n' "${url}" | tr '[:upper:]' '[:lower:]'
}

is_git_checkout() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && [ "$(cd "$1" && pwd -P)" = "$(cd "$(git -C "$1" rev-parse --show-toplevel)" && pwd -P)" ]
}

git_origin() { git -C "$1" config --get remote.origin.url 2>/dev/null || echo "unknown"; }
git_head()   { git -C "$1" rev-parse HEAD 2>/dev/null || echo "unknown"; }

# Local changes (tracked files) under the given paths of a checkout.
git_dirty() {
  local dir="$1"
  shift
  if [ -n "$(git -C "${dir}" status --porcelain --untracked-files=no -- "$@" 2>/dev/null)" ]; then
    echo true
  else
    echo false
  fi
}

# Commit of a tag, branch or SHA known to the local checkout (empty if unknown).
resolve_ref() {
  local dir="$1" ref="$2" candidate
  for candidate in "refs/tags/${ref}" "refs/remotes/origin/${ref}" "refs/heads/${ref}" "${ref}"; do
    if git -C "${dir}" rev-parse -q --verify "${candidate}^{commit}" 2>/dev/null; then
      return 0
    fi
  done
  return 0
}

# A core directory must come complete from its module: Docker never fills gaps.
check_core_source() {
  local name="$1" dir="$2" owner="$3"
  if [ ! -d "${dir}" ]; then
    err "core '${name}': ${dir#"${ROOT_DIR}/"} not found (owner: ${owner})."
    return 0
  fi
  [ -f "${dir}/core.properties" ] \
    || err "core '${name}': ${dir#"${ROOT_DIR}/"}/core.properties is missing; ${owner} must provide it."
  [ -f "${dir}/conf/solrconfig.xml" ] \
    || err "core '${name}': ${dir#"${ROOT_DIR}/"}/conf/solrconfig.xml is missing."
  if [ ! -f "${dir}/conf/schema.xml" ] && ! compgen -G "${dir}/conf/managed-schema*" >/dev/null; then
    err "core '${name}': no schema.xml / managed-schema in ${dir#"${ROOT_DIR}/"}/conf."
  fi
}

# Where a setting comes from: "environment", "Docker/.env" or "" (not configured).
setting_source() {
  local var_name="$1" env_file="${ROOT_DIR}/Docker/.env" value
  if [ -n "${!var_name:-}" ]; then
    echo "environment"
    return 0
  fi
  if [ -f "${env_file}" ]; then
    value="$(get_env_val "${var_name}" "")"
    [ -n "${value}" ] && echo "Docker/.env"
  fi
  return 0
}

# --- sources -----------------------------------------------------------------

VUFIND_CHECK="$(get_env_val LR_SOLR_VUFIND_CHECK warn)"
VUFIND_REPO_URL_CFG="$(get_env_val VUFIND_REPO_URL "${DEFAULT_VUFIND_REPO_URL}")"
VUFIND_REF_CFG="$(get_env_val VUFIND_REF "${DEFAULT_VUFIND_REF}")"
VUFIND_REPO_URL_SRC="$(setting_source VUFIND_REPO_URL)"
VUFIND_REF_SRC="$(setting_source VUFIND_REF)"
case "${VUFIND_CHECK}" in
  strict|warn|off) ;;
  *) echo "Error: LR_SOLR_VUFIND_CHECK must be strict, warn or off (got '${VUFIND_CHECK}')." >&2; exit 1 ;;
esac

# Clones the configured VuFind when ./vufind has no checkout. Docker may have
# created vufind/local or vufind/vendor already: they are preserved.
ensure_vufind_checkout() {
  [ -f "${SRC_VUFIND}/composer.json" ] && return 0
  if [ -e "${SRC_VUFIND}/.git" ]; then
    echo "Error: ${SRC_VUFIND} has a .git but no composer.json (incomplete checkout); fix it before staging." >&2
    exit 1
  fi
  command -v git >/dev/null 2>&1 || { echo "Error: git is required to clone VuFind." >&2; exit 1; }

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/lr-solr-vufind.XXXXXX")"
  echo "VuFind checkout not found; cloning ${VUFIND_REPO_URL_CFG} (ref: ${VUFIND_REF_CFG})..."
  if ! git clone --quiet --depth 1 --branch "${VUFIND_REF_CFG}" --single-branch \
        "${VUFIND_REPO_URL_CFG}" "${tmp}/checkout"; then
    rm -rf -- "${tmp}"
    echo "Error: could not clone VuFind ${VUFIND_REF_CFG} from ${VUFIND_REPO_URL_CFG}." >&2
    exit 1
  fi
  mkdir -p "${SRC_VUFIND}"
  cp -an "${tmp}/checkout/." "${SRC_VUFIND}/"
  rm -rf -- "${tmp}"
}

ensure_oai_checkout() {
  [ -d "${SRC_OAI}" ] && return 0
  [ -f "${ROOT_DIR}/githelper" ] || return 0
  echo "lareferencia-oai-pmh not found; cloning it with githelper..."
  if [ -x "${ROOT_DIR}/githelper" ]; then
    "${ROOT_DIR}/githelper" init --depth 1 --modules lareferencia-oai-pmh || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 "${ROOT_DIR}/githelper" init --depth 1 --modules lareferencia-oai-pmh || true
  fi
}

check_vufind_checkout() {
  [ "${VUFIND_CHECK}" = off ] && return 0
  local report=err
  [ "${VUFIND_CHECK}" = warn ] && report=warn

  if ! is_git_checkout "${SRC_VUFIND}"; then
    "${report}" "vufind/ is not a git checkout: cannot prove it is ${VUFIND_REPO_URL_CFG} at ${VUFIND_REF_CFG}."
    return 0
  fi

  local origin head want
  origin="$(git_origin "${SRC_VUFIND}")"
  head="$(git_head "${SRC_VUFIND}")"

  if [ -z "${VUFIND_REPO_URL_SRC}" ]; then
    echo "Note: VUFIND_REPO_URL is not configured; using vufind/ as it is (origin ${origin})."
  elif [ "$(normalize_repo_url "${origin}")" != "$(normalize_repo_url "${VUFIND_REPO_URL_CFG}")" ]; then
    "${report}" "vufind/ comes from ${origin}, but VUFIND_REPO_URL (${VUFIND_REPO_URL_SRC}) is ${VUFIND_REPO_URL_CFG}. Set VUFIND_REPO_URL=${origin} in Docker/.env if that checkout is the intended one, or re-clone vufind/ from ${VUFIND_REPO_URL_CFG}."
  fi

  if [ -z "${VUFIND_REF_SRC}" ]; then
    echo "Note: VUFIND_REF is not configured; using vufind/ at its current revision (${head})."
  else
    want="$(resolve_ref "${SRC_VUFIND}" "${VUFIND_REF_CFG}")"
    if [ -z "${want}" ]; then
      "${report}" "VUFIND_REF '${VUFIND_REF_CFG}' (${VUFIND_REF_SRC}) is unknown to vufind/ (try: git -C vufind fetch --depth 1 origin tag ${VUFIND_REF_CFG})."
    elif [ "${head}" != "${want}" ]; then
      "${report}" "vufind/ is at ${head}, but VUFIND_REF '${VUFIND_REF_CFG}' (${VUFIND_REF_SRC}) is ${want} (git -C vufind checkout ${VUFIND_REF_CFG})."
    fi
  fi

  if [ "$(git_dirty "${SRC_VUFIND}" solr/vufind/biblio solr/vufind/jars import)" = true ]; then
    "${report}" "vufind/ has local changes in solr/vufind/biblio, solr/vufind/jars or import (git -C vufind status)."
  fi
}

# --- check mode ----------------------------------------------------------------

# Staged copy == sources?  Prints one line per item, exits 1 on any difference.
check_staged() {
  local failed=0 item src dst
  for item in "oai|${SRC_OAI}|${DST_CORES}/oai" "biblio|${SRC_BIBLIO}|${DST_CORES}/biblio" \
              "jars|${SRC_JARS}|${DST_JARS}" "import|${SRC_IMPORT}|${DST_IMPORT}"; do
    IFS='|' read -r name src dst <<< "${item}"
    if [ ! -d "${src}" ]; then
      echo "MISSING SOURCE  ${name}: ${src#"${ROOT_DIR}/"}"
      failed=1
    elif diff -rq -x .gitkeep "${src}" "${dst}" >/dev/null 2>&1; then
      echo "OK              ${name}: ${dst#"${ROOT_DIR}/"} matches ${src#"${ROOT_DIR}/"}"
    else
      echo "DIFFERENT       ${name}: ${dst#"${ROOT_DIR}/"} differs from ${src#"${ROOT_DIR}/"} (run: ./Docker/docker.sh solr stage)"
      failed=1
    fi
  done
  return "${failed}"
}

# --- staging ---------------------------------------------------------------------

# Replaces the content of <dst> by the content of <src>, keeping <dst> itself
# (bind mount) and its .gitkeep.
replace_dir_content() {
  local src="$1" dst="$2"
  mkdir -p "${dst}"
  find "${dst}" -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
  cp -a "${src}/." "${dst}/"
}

solr_image_version() {
  sed -nE 's/^FROM[[:space:]]+solr:([^[:space:]]+).*/\1/p' "${SCRIPT_DIR}/Dockerfile" 2>/dev/null | head -n 1
}

write_build_info() {
  local file="$1" oai_repo oai_rev oai_dirty vufind_repo vufind_rev vufind_dirty
  if is_git_checkout "${OAI_MODULE_DIR}"; then
    oai_repo="$(git_origin "${OAI_MODULE_DIR}")"
    oai_rev="$(git_head "${OAI_MODULE_DIR}")"
    oai_dirty="$(git_dirty "${OAI_MODULE_DIR}" solr.core/oai)"
  else
    oai_repo="unknown" oai_rev="unknown" oai_dirty="unknown"
  fi
  if is_git_checkout "${SRC_VUFIND}"; then
    vufind_repo="$(git_origin "${SRC_VUFIND}")"
    vufind_rev="$(git_head "${SRC_VUFIND}")"
    vufind_dirty="$(git_dirty "${SRC_VUFIND}" solr/vufind/biblio solr/vufind/jars import)"
  else
    vufind_repo="unknown" vufind_rev="unknown" vufind_dirty="unknown"
  fi

  cat > "${file}" <<EOF
solr.version=$(solr_image_version)
staged_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
core.oai.source=lareferencia-oai-pmh/solr.core/oai
core.oai.repository=${oai_repo}
core.oai.revision=${oai_rev}
core.oai.dirty=${oai_dirty}
core.biblio.source=vufind/solr/vufind/biblio
core.biblio.repository=${vufind_repo}
core.biblio.revision=${vufind_rev}
core.biblio.dirty=${vufind_dirty}
core.biblio.expected.repository=${VUFIND_REPO_URL_SRC:+${VUFIND_REPO_URL_CFG}}
core.biblio.expected.ref=${VUFIND_REF_SRC:+${VUFIND_REF_CFG}}
core.biblio.check=${VUFIND_CHECK}
vufind.jars.source=vufind/solr/vufind/jars
vufind.import.source=vufind/import
EOF
}

print_messages() {
  local m
  for m in ${WARNINGS[@]+"${WARNINGS[@]}"}; do echo "Warning: ${m}" >&2; done
  for m in ${ERRORS[@]+"${ERRORS[@]}"}; do echo "Error: ${m}" >&2; done
}

main() {
  local mode="${1:-stage}"
  case "${mode}" in
    stage|--stage) mode=stage ;;
    check|--check) mode=check ;;
    *) echo "Usage: $0 [--check]" >&2; exit 1 ;;
  esac

  if [ "${mode}" = check ]; then
    check_staged
    return $?
  fi

  echo "=== Staging Solr $(solr_image_version) core configurations from their modules ==="
  ensure_vufind_checkout
  ensure_oai_checkout

  check_core_source oai "${SRC_OAI}" "lareferencia-oai-pmh"
  check_core_source biblio "${SRC_BIBLIO}" "the VuFind checkout"
  [ -d "${SRC_JARS}" ] || err "VuFind jars not found: ${SRC_JARS#"${ROOT_DIR}/"}"
  [ -d "${SRC_IMPORT}" ] || err "VuFind import assets not found: ${SRC_IMPORT#"${ROOT_DIR}/"}"
  [ -d "${SRC_VUFIND}" ] && check_vufind_checkout
  if is_git_checkout "${OAI_MODULE_DIR}" && [ "$(git_dirty "${OAI_MODULE_DIR}" solr.core/oai)" = true ]; then
    warn "lareferencia-oai-pmh has local changes in solr.core/oai (staged as they are, recorded as dirty)."
  fi

  print_messages
  if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo "Nothing was staged; the previous Docker/solr staging is unchanged." >&2
    [ "${VUFIND_CHECK}" = strict ] && \
      echo "(LR_SOLR_VUFIND_CHECK=strict is set in Docker/.env or the environment; warn reports these differences without stopping.)" >&2
    return 1
  fi

  mkdir -p "${DST_CORES}"
  # Cores no longer provided by any module must not survive in the staging.
  find "${DST_CORES}" -mindepth 1 -maxdepth 1 ! -name .gitkeep ! -name oai ! -name biblio -exec rm -rf {} +
  replace_dir_content "${SRC_OAI}" "${DST_CORES}/oai"
  replace_dir_content "${SRC_BIBLIO}" "${DST_CORES}/biblio"
  replace_dir_content "${SRC_JARS}" "${DST_JARS}"
  replace_dir_content "${SRC_IMPORT}" "${DST_IMPORT}"
  write_build_info "${DST_CORES}/build-info.properties"
  touch "${DST_CORES}/.gitkeep" "${DST_JARS}/.gitkeep" "${DST_IMPORT}/.gitkeep"

  echo "=== Staging complete. Sources recorded in Docker/solr/cores/build-info.properties: ==="
  cat "${DST_CORES}/build-info.properties"
}

main "$@"
