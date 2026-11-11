#!/usr/bin/env bash
# =============================================================================
# search.sh — "VuFind" and "Solr": the discovery/indexing stack.
#
# Public API:
#   vufind::ensure_checkout          clones VuFind (shallow) when missing
#   vufind::ensure_for_selection     clones VuFind if a selected service needs it
#   solr::stage                      stages cores/jars/import via Docker/solr/stage-cores.sh
#   solr::ensure_staged              stages only when the staging is missing
#   solr::update_config              stages + applies the config to the Solr volume
#                                    (keeps the index, reloads a running Solr)
#   solr::verify                     sources == staging == installed configuration?
#   solr::migrate                    installs an incompatible schema with an empty
#                                    index (Solr stopped meanwhile); reindex afterwards
#   solr::is_local                   false when SOLR_EXTERNAL_URL replaces the container
#   solr::pending_migrations         "<core>\t<definitions>": staged schemas the existing
#                                    index cannot take (kept until solr::migrate)
#   solr::pending_cores              the same, core names only ("oai biblio")
#   solr::status                     sources, pending migrations and reindexes
# =============================================================================

VUFIND_DIR="${ROOT_DIR}/vufind"
DEFAULT_VUFIND_REPO_URL="https://github.com/vufind-org/vufind"
DEFAULT_VUFIND_REF="v11.0.1"
SOLR_STAGE_SCRIPT="${SCRIPT_DIR}/solr/stage-cores.sh"
SOLR_ENTRYPOINT="${SCRIPT_DIR}/solr/entrypoint.sh"
SOLR_HOST_DATA_DIR="${VOLUME_DIR}/solr/data"

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
    "${SOLR_STAGE_SCRIPT}" "$@"
  else
    bash "${SOLR_STAGE_SCRIPT}" "$@"
  fi
}

# The cores are bind-mounted from Docker/solr/cores: a container started
# without a staging would come up with no cores at all.
solr::is_staged() {
  local core
  for core in oai biblio; do
    [ -f "${SCRIPT_DIR}/solr/cores/${core}/core.properties" ] || return 1
  done
}

solr::ensure_staged() {
  solr::is_staged && return 0
  echo "Solr cores are not staged yet; staging them from the modules..."
  solr::stage
}

solr::is_running() {
  dc ps --status running solr 2>/dev/null | grep -q solr
}

# Applies the staged configuration to the persistent Solr home: inside the
# running container (then RELOAD), or with a one-off container when Solr is
# stopped. Index data is never touched.
solr::update_config() {
  solr::stage
  if solr::is_running; then
    echo "Applying the Solr configuration inside the running container..."
    dc exec -T solr /usr/local/bin/lr-solr-entrypoint.sh update-config
  else
    echo "Solr is not running; applying the configuration with a one-off container..."
    dc run --rm --no-deps -T solr update-config
  fi
}

# Schema changes that the existing index cannot take (e.g. Trie* → *PointField)
# are kept pending by the automatic update. This installs them: Solr is
# stopped, the old index is moved to <core>/previous-index-<ts>/, Solr starts
# with empty cores for those schemas, and the networks must be reindexed.
solr::migrate() {
  solr::stage
  local was_running=false
  if solr::is_running; then
    was_running=true
    echo "Stopping Solr to rebuild the indexes with incompatible schemas..."
    dc stop solr
  fi
  local status=0
  dc run --rm --no-deps -T solr migrate || status=$?
  if [ "${was_running}" = true ]; then
    dc start solr
  fi
  return "${status}"
}

solr::is_local() {
  [ -z "$(config::get SOLR_EXTERNAL_URL "")" ]
}

# Same rule the container applies at start (Docker/solr/entrypoint.sh,
# read-only command), evaluated on the host over the Solr volume and the
# current staging — so the wizard can ask before starting.
solr::pending_migrations() {
  solr::is_local || return 0
  [ -d "${SOLR_HOST_DATA_DIR}" ] || return 0
  LR_SOLR_DATA_DIR="${SOLR_HOST_DATA_DIR}" LR_SOLR_TEMPLATE_DIR="${SCRIPT_DIR}/solr/cores" \
    bash "${SOLR_ENTRYPOINT}" pending-migrations 2>/dev/null || true
}

solr::pending_cores() {
  solr::pending_migrations | cut -f1 | paste -sd ' ' -
}

solr::status() {
  if ! solr::is_local; then
    echo "External Solr: $(config::get SOLR_EXTERNAL_URL "")"
    return 0
  fi
  local info="${SCRIPT_DIR}/solr/cores/build-info.properties" core pending
  if [ -f "${info}" ]; then
    echo "Staged core sources:"
    grep -E '^(solr\.version|core\.(oai|biblio)\.(repository|revision))=' "${info}" | sed 's/^/  /'
  else
    echo "Solr cores are not staged yet (./Docker/docker.sh solr stage)."
  fi
  pending="$(solr::pending_migrations)"
  if [ -n "${pending}" ]; then
    echo "Schema migration pending (core keeps its current schema until 'solr migrate'):"
    printf '%s\n' "${pending}" | while IFS=$'\t' read -r core defs; do
      echo "  ${core}: incompatible ${defs}"
    done
  else
    echo "No schema migration pending."
  fi
  for core in oai biblio; do
    [ -f "${SOLR_HOST_DATA_DIR}/${core}/.lr_reindex_required" ] \
      && echo "Reindex pending: ${core} (delete ${SOLR_HOST_DATA_DIR#"${ROOT_DIR}/"}/${core}/.lr_reindex_required when done)"
  done
  return 0
}

# Module sources == Docker/solr staging == configuration installed in Solr.
solr::verify() {
  local status=0
  echo "--- Staging vs module checkouts ---"
  solr::stage --check || status=1
  echo "--- Installed configuration vs staging ---"
  if solr::is_running; then
    dc exec -T solr /usr/local/bin/lr-solr-entrypoint.sh verify-config || status=1
  else
    dc run --rm --no-deps -T solr verify-config || status=1
  fi
  return "${status}"
}
