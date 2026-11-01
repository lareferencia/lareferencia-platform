#!/usr/bin/env bash
# =============================================================================
# search.sh — "VuFind" and "Solr": the discovery/indexing stack.
#
# Public API:
#   vufind::ensure_checkout          clones VuFind (shallow) when missing
#   vufind::ensure_for_selection     clones VuFind if a selected service needs it
#   solr::stage                      stages cores/jars via Docker/solr/stage-cores.sh
#   solr::update_config              stages + hot-reloads config in a running Solr
# =============================================================================

VUFIND_DIR="${ROOT_DIR}/vufind"
DEFAULT_VUFIND_REPO_URL="https://github.com/vufind-org/vufind"
DEFAULT_VUFIND_REF="v11.0.1"
SOLR_STAGE_SCRIPT="${SCRIPT_DIR}/solr/stage-cores.sh"

# --- VuFind ---------------------------------------------------------------------

vufind::is_cloned() {
  [ -f "${VUFIND_DIR}/composer.json" ]
}

vufind::ensure_checkout() {
  vufind::is_cloned && return 0

  local repo_url repo_ref
  repo_url="${VUFIND_REPO_URL:-$(config::get VUFIND_REPO_URL "${DEFAULT_VUFIND_REPO_URL}")}"
  repo_ref="${VUFIND_REF:-$(config::get VUFIND_REF "${DEFAULT_VUFIND_REF}")}"

  if ! cmd::exists git; then
    echo "Error: git is not available in PATH; cannot clone VuFind." >&2
    exit 1
  fi

  echo "--- VuFind not found. Cloning ${repo_url} (ref: ${repo_ref}) with --depth 1 ---"
  git clone --progress --depth 1 --branch "${repo_ref}" --single-branch "${repo_url}" "${VUFIND_DIR}"
  echo "--- VuFind checkout completed successfully ---"

  # Solr's biblio core comes from the VuFind checkout: refresh the staging.
  solr::stage || true
}

vufind::ensure_for_selection() {
  if selection::needs_vufind; then
    vufind::ensure_checkout
  fi
  return 0
}

# --- Solr ------------------------------------------------------------------------

solr::stage() {
  if [ ! -f "${SOLR_STAGE_SCRIPT}" ]; then
    echo "Error: Solr staging script not found: ${SOLR_STAGE_SCRIPT}" >&2
    return 1
  fi
  if [ -x "${SOLR_STAGE_SCRIPT}" ]; then
    "${SOLR_STAGE_SCRIPT}"
  else
    bash "${SOLR_STAGE_SCRIPT}"
  fi
}

solr::update_config() {
  solr::stage
  if dc ps --status running solr 2>/dev/null | grep -q solr; then
    echo "Updating Solr configuration inside running container..."
    dc exec -T solr /usr/local/bin/lr-solr-entrypoint.sh update-config
  else
    echo "Solr container is not running. Staged configuration will be applied on next startup."
  fi
}
