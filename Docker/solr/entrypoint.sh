#!/bin/bash
# =============================================================================
# Solr entrypoint for La Referencia.
#
# Core templates come from /opt/lr-solr-cores (bind mount of Docker/solr/cores,
# staged from the owning modules by Docker/solr/stage-cores.sh). They are
# installed into the persistent Solr home (/var/solr/data) as they are.
#
# Upgrades need no manual step ("stop, pull, start"): on every start each core
# whose installed configuration differs from the template is brought up to date
# when that is safe for its index:
#   - core missing                          → installed
#   - no schema change, or a compatible one → conf/ replaced (backup in
#     (fields/types added or removed),         conf.bak.<ts>), index kept;
#     or an empty index                        reindex recommended if the schema changed
#   - schema incompatible with the index    → LR_SOLR_SCHEMA_MIGRATION=keep (default):
#     (an existing field/type redefined,       the core keeps its current configuration
#     e.g. Trie* → *PointField)                and keeps working; the migration is
#                                              reported and marked (.lr_migration_pending)
#                                            → LR_SOLR_SCHEMA_MIGRATION=rebuild: new
#                                              configuration + empty index (old index
#                                              kept in previous-index-<ts>/), reindex
#   SOLR_UPDATE_CONFIG=false disables the automatic update (warning only).
#
# Commands:
#   (no args)        start Solr (as above)
#   update-config    same update, now; reloads the cores when Solr runs.
#                    Exit 3 when a migration is pending.
#   migrate          update-config allowing the index rebuild (Solr must be stopped)
#   verify-config    installed configuration == templates? (exit 1 when not)
#   pending-migrations  read-only: "<core>\t<incompatible definitions>" for every
#                    core whose staged schema the existing index cannot take
#                    (used on the host by docker.sh / the wizard, before starting)
#   <command>        any other executable is run as is
#
# Paths can be overridden with LR_SOLR_* variables (used by the unit tests).
# =============================================================================
set -euo pipefail

SOLR_DATA_DIR="${LR_SOLR_DATA_DIR:-/var/solr/data}"
SOLR_LOG_DIR="${LR_SOLR_LOG_DIR:-/var/solr/logs}"
SOLR_CACHE_DIR="${LR_SOLR_CACHE_DIR:-/var/solr/cache}"
SOLR_VENDOR_DIR="${LR_SOLR_VENDOR_DIR:-/var/solr/vendor}"
SOLR_MODULES_DIR="${LR_SOLR_MODULES_DIR:-/opt/solr/modules}"
SOLR_TEMPLATE_DIR="${LR_SOLR_TEMPLATE_DIR:-/opt/lr-solr-cores}"
SOLR_JARS_TEMPLATE_DIR="${LR_SOLR_JARS_TEMPLATE_DIR:-/opt/lr-solr-jars}"
SOLR_IMPORT_TEMPLATE_DIR="${LR_SOLR_IMPORT_TEMPLATE_DIR:-/opt/lr-solr-import}"
SOLR_IMPORT_DIR="${LR_SOLR_IMPORT_DIR:-/import}"
SOLR_LOCAL_URL="${LR_SOLR_LOCAL_URL:-http://localhost:8983/solr}"
SOLR_BIN="${LR_SOLR_BIN:-/opt/solr/bin/solr}"
INIT_MARKER="${SOLR_DATA_DIR}/.lr_initialized"
BUILD_INFO_FILE="build-info.properties"
REINDEX_MARKER=".lr_reindex_required"
MIGRATION_MARKER=".lr_migration_pending"

export SOLR_MODULES="${SOLR_MODULES:-analysis-extras}"
export SOLR_SECURITY_MANAGER_ENABLED="${SOLR_SECURITY_MANAGER_ENABLED:-false}"
export SOLR_OPTS="${SOLR_OPTS:-} -Ddisable.configEdit=true -Dsolr.config.lib.enabled=true"

REINDEX_CORES=()
PENDING_CORES=()
REBUILT_CORES=()
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# --- helpers -------------------------------------------------------------------

prepare_dirs() {
  mkdir -p "${SOLR_DATA_DIR}" "${SOLR_LOG_DIR}" "${SOLR_CACHE_DIR}" "${SOLR_VENDOR_DIR}" "${SOLR_IMPORT_DIR}"
  # VuFind's solrconfig.xml loads ../vendor/modules/... relative to the Solr home.
  if [ ! -e "${SOLR_VENDOR_DIR}/modules" ] && [ ! -L "${SOLR_VENDOR_DIR}/modules" ]; then
    ln -s "${SOLR_MODULES_DIR}" "${SOLR_VENDOR_DIR}/modules"
  fi
}

fix_permissions() {
  chown -R solr:solr "${SOLR_DATA_DIR}" "${SOLR_LOG_DIR}" "${SOLR_CACHE_DIR}" "${SOLR_VENDOR_DIR}" "${SOLR_IMPORT_DIR}"
}

# Names of the cores in the template (directories with core.properties).
template_cores() {
  local dir
  for dir in "${SOLR_TEMPLATE_DIR}"/*/; do
    [ -f "${dir}core.properties" ] && basename "${dir}"
  done
  return 0
}

# Schema file of a conf/ directory (classic schema.xml or managed schema).
schema_file() {
  local conf="$1" f
  for f in "${conf}/schema.xml" "${conf}/managed-schema.xml" "${conf}/managed-schema"; do
    [ -f "${f}" ] && { echo "${f}"; return 0; }
  done
  return 0
}

conf_differs() {
  local core="$1"
  ! diff -rq "${SOLR_TEMPLATE_DIR}/${core}/conf" "${SOLR_DATA_DIR}/${core}/conf" >/dev/null 2>&1 \
    || ! cmp -s "${SOLR_TEMPLATE_DIR}/${core}/core.properties" "${SOLR_DATA_DIR}/${core}/core.properties"
}

# "<kind>:<name>\t<normalized opening tag>" for every field, dynamicField and
# fieldType of a schema (comments removed, whitespace normalized).
schema_defs() {
  awk '
    { buf = buf " " $0 }
    END {
      while ((s = index(buf, "<!--")) > 0) {
        rest = substr(buf, s + 4); e = index(rest, "-->")
        buf = substr(buf, 1, s - 1) (e > 0 ? substr(rest, e + 3) : "")
      }
      n = split(buf, parts, "<")
      for (i = 1; i <= n; i++) {
        t = parts[i]
        if (t !~ /^(field|dynamicField|fieldType|fieldtype)[ \t]/) continue
        sub(/>.*/, "", t); gsub(/[ \t]+/, " ", t); sub(/ *\/ *$/, "", t); sub(/ +$/, "", t)
        kind = t; sub(/ .*/, "", kind)
        if (kind == "fieldtype") { kind = "fieldType"; t = "fieldType" substr(t, 10) }
        if (!match(t, /name="[^"]*"/)) continue
        print kind ":" substr(t, RSTART + 6, RLENGTH - 7) "\t" t
      }
    }' "$1"
}

# Definitions present in both schemas but changed: Lucene refuses to index a
# field with another type/options than the one already in the index.
# Prints the conflicting "<kind>:<name>" (nothing = compatible).
schema_conflicts() {
  local old="$1" new="$2"
  [ -n "${old}" ] && [ -n "${new}" ] || return 0
  awk -F '\t' 'FILENAME == ARGV[1] { def[$1] = $2; next }
               ($1 in def) && def[$1] != $2 { print $1 }' \
    <(schema_defs "${old}") <(schema_defs "${new}")
}

# Lucene commit points of a core (outside conf/ and previous indexes).
index_segment_files() {
  find "${SOLR_DATA_DIR}/$1" \( -name conf -o -name 'conf.bak.*' -o -name 'previous-index-*' \) -prune \
    -o -type f -name 'segments_*' -print 2>/dev/null
}

# A new Solr core already has an index with only segments_N and write.lock:
# populated means segment data files (_0.cfs, _0.si, ...) next to segments_N.
index_populated() {
  local seg
  while IFS= read -r seg; do
    if [ -n "$(find "$(dirname "${seg}")" -maxdepth 1 -type f ! -name 'segments*' ! -name write.lock -print -quit)" ]; then
      return 0
    fi
  done < <(index_segment_files "$1")
  return 1
}

# Moves the index of a core (index/, tlog/, snapshot_metadata/ of its dataDir —
# oai/data for oai, the core directory itself for VuFind's biblio) aside.
move_index_aside() {
  local core="$1" target="${SOLR_DATA_DIR}/$1" seg index_dir data_dir rel dest item
  dest="${target}/previous-index-${TIMESTAMP}"
  while IFS= read -r seg; do
    index_dir="$(dirname "${seg}")"
    data_dir="$(dirname "${index_dir}")"
    rel="${data_dir#"${target}"}"
    mkdir -p "${dest}${rel}"
    for item in index tlog snapshot_metadata; do
      [ -e "${data_dir}/${item}" ] && mv "${data_dir}/${item}" "${dest}${rel}/"
    done
  done < <(index_segment_files "${core}" | sort -u)
  echo "Core '${core}': previous index moved to ${dest}"
}

record_build_info() {
  if [ -f "${SOLR_TEMPLATE_DIR}/${BUILD_INFO_FILE}" ]; then
    echo "--- Solr core sources (${BUILD_INFO_FILE}) ---"
    cat "${SOLR_TEMPLATE_DIR}/${BUILD_INFO_FILE}"
    echo "------------------------------------------------"
    cp -f "${SOLR_TEMPLATE_DIR}/${BUILD_INFO_FILE}" "${SOLR_DATA_DIR}/.lr_cores_build_info"
  fi
}

require_templates() {
  if [ -z "$(template_cores)" ]; then
    echo "Error: no Solr core templates in ${SOLR_TEMPLATE_DIR} (expected oai/ and biblio/ with core.properties)." >&2
    echo "       Stage them on the host with: ./Docker/docker.sh solr stage   (dev: ./Docker/docker-dev.sh solr stage)" >&2
    return 1
  fi
}

install_core() {
  local core="$1"
  echo "Installing core '${core}' from template..."
  cp -a "${SOLR_TEMPLATE_DIR}/${core}" "${SOLR_DATA_DIR}/${core}"
}

replace_conf() {
  local core="$1" target="${SOLR_DATA_DIR}/$1" template="${SOLR_TEMPLATE_DIR}/$1"
  if [ -d "${target}/conf" ]; then
    echo "Core '${core}': backing up conf/ to ${target}/conf.bak.${TIMESTAMP}"
    cp -a "${target}/conf" "${target}/conf.bak.${TIMESTAMP}"
  fi
  rm -rf "${target}/conf"
  cp -a "${template}/conf" "${target}/conf"
  cp -f "${template}/core.properties" "${target}/core.properties"
  rm -f "${target}/${MIGRATION_MARKER}"
}

mark_reindex() {
  local core="$1" reason="$2"
  REINDEX_CORES+=("${core}")
  {
    echo "core=${core}"
    echo "updated_at=${TIMESTAMP}"
    echo "previous_conf=${SOLR_DATA_DIR}/${core}/conf.bak.${TIMESTAMP}"
    echo "reason=${reason}"
  } > "${SOLR_DATA_DIR}/${core}/${REINDEX_MARKER}"
}

# Jars and import assets are not user data: they always mirror the template
# (cp -u would keep an older jar with a newer mtime).
sync_support_files() {
  if [ -d "${SOLR_JARS_TEMPLATE_DIR}" ]; then
    rm -rf "${SOLR_DATA_DIR}/jars"
    mkdir -p "${SOLR_DATA_DIR}/jars"
    cp -a "${SOLR_JARS_TEMPLATE_DIR}/." "${SOLR_DATA_DIR}/jars/"
    rm -f "${SOLR_DATA_DIR}/jars/.gitkeep"
  fi
  if [ -d "${SOLR_IMPORT_TEMPLATE_DIR}" ]; then
    find "${SOLR_IMPORT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "${SOLR_IMPORT_TEMPLATE_DIR}/." "${SOLR_IMPORT_DIR}/"
    rm -f "${SOLR_IMPORT_DIR}/.gitkeep"
  fi
}

# --- bringing one core up to date ------------------------------------------------------

# update_core <core> <allow_rebuild: true|false>
update_core() {
  local core="$1" allow_rebuild="$2"
  local target="${SOLR_DATA_DIR}/${core}" template="${SOLR_TEMPLATE_DIR}/${core}"

  if [ ! -d "${target}" ]; then
    install_core "${core}"
    return 0
  fi
  if ! conf_differs "${core}"; then
    echo "Core '${core}': configuration already up to date."
    return 0
  fi

  local old_schema new_schema conflicts="" schema_changed=false
  old_schema="$(schema_file "${target}/conf")"
  new_schema="$(schema_file "${template}/conf")"
  if [ -n "${old_schema}" ] && [ -n "${new_schema}" ] && ! cmp -s "${old_schema}" "${new_schema}"; then
    schema_changed=true
    conflicts="$(schema_conflicts "${old_schema}" "${new_schema}" | tr '\n' ' ' | sed 's/ $//')"
  fi

  if [ -n "${conflicts}" ] && index_populated "${core}"; then
    if [ "${allow_rebuild}" != true ]; then
      PENDING_CORES+=("${core}")
      {
        echo "core=${core}"
        echo "detected_at=${TIMESTAMP}"
        echo "incompatible=${conflicts}"
      } > "${target}/${MIGRATION_MARKER}"
      echo "Core '${core}': the new schema is incompatible with the existing index (${conflicts})."
      echo "Core '${core}': keeping the current configuration and index — the core keeps working."
      return 0
    fi
    replace_conf "${core}"
    move_index_aside "${core}"
    REBUILT_CORES+=("${core}")
    mark_reindex "${core}" "index rebuilt: incompatible schema (${conflicts})"
    echo "Core '${core}': new configuration installed with an empty index."
    return 0
  fi

  replace_conf "${core}"
  # Only conf/ and core.properties change: the index (data/ for oai; index/ and
  # tlog/ directly in the core directory for VuFind's biblio) is left alone.
  echo "Core '${core}': configuration updated; index data preserved (only conf/ and core.properties replaced)."
  if [ "${schema_changed}" = true ] && index_populated "${core}"; then
    mark_reindex "${core}" "schema changed (compatible)"
  fi
}

update_all_cores() {
  local allow_rebuild="$1" core
  echo "Updating Solr core configurations from ${SOLR_TEMPLATE_DIR}..."
  while IFS= read -r core; do
    update_core "${core}" "${allow_rebuild}"
  done < <(template_cores)
}

# Without automatic updates: install missing cores, report differences only.
report_outdated_cores() {
  local core outdated=()
  while IFS= read -r core; do
    if [ ! -d "${SOLR_DATA_DIR}/${core}" ]; then
      install_core "${core}"
    elif conf_differs "${core}"; then
      outdated+=("${core}")
    fi
  done < <(template_cores)
  if [ "${#outdated[@]}" -gt 0 ]; then
    echo "WARNING: SOLR_UPDATE_CONFIG=false — the configuration of ${outdated[*]} differs from the staged one and was NOT applied."
    echo "         Apply it (index kept, backup made): ./Docker/docker.sh solr update-config"
  fi
}

solr_is_up() {
  curl -s -f "${SOLR_LOCAL_URL}/admin/info/system" >/dev/null 2>&1
}

# RELOAD every template core present in Solr. Returns 1 if any reload failed.
reload_cores() {
  if ! solr_is_up; then
    echo "Solr is not running here: the new configuration loads on the next start."
    return 0
  fi
  local core response failed=0
  echo "Solr is running: reloading cores through the CoreAdmin API..."
  while IFS= read -r core; do
    [ -d "${SOLR_DATA_DIR}/${core}" ] || continue
    response="$(curl -s "${SOLR_LOCAL_URL}/admin/cores?action=RELOAD&core=${core}&wt=json" || true)"
    if printf '%s' "${response}" | grep -Eq '"status"[[:space:]]*:[[:space:]]*0'; then
      echo "Core '${core}': reloaded."
    else
      echo "Error: core '${core}' failed to reload with the new configuration:" >&2
      echo "  ${response}" >&2
      echo "  The previous conf/ is in ${SOLR_DATA_DIR}/${core}/conf.bak.* — see Docker/README.md (Solr cores) to roll back." >&2
      failed=1
    fi
  done < <(template_cores)
  return "${failed}"
}

print_summary() {
  local core
  if [ "${#PENDING_CORES[@]}" -gt 0 ]; then
    echo ""
    echo "=================================================================="
    echo " SCHEMA MIGRATION PENDING for: ${PENDING_CORES[*]}"
    echo " The new schema redefines fields of the existing index, so it can"
    echo " only be installed with an empty index followed by a reindex."
    echo " Until then these cores keep their current configuration and data."
    echo " When convenient (the cores start empty until reindexed):"
    echo "   ./Docker/docker.sh solr migrate"
    echo " or set LR_SOLR_SCHEMA_MIGRATION=rebuild in Docker/.env to do it"
    echo " on the next start. Details: Docker/README.md, 'Solr cores'."
    echo "=================================================================="
  fi
  [ "${#REINDEX_CORES[@]}" -gt 0 ] || return 0
  echo ""
  echo "=================================================================="
  echo " REINDEX REQUIRED for: ${REINDEX_CORES[*]}"
  [ "${#REBUILT_CORES[@]}" -gt 0 ] && echo " Empty index (previous one in previous-index-*): ${REBUILT_CORES[*]}"
  echo " Run the networks' indexing actions in full (not incremental):"
  for core in "${REINDEX_CORES[@]}"; do
    case "${core}" in
      oai)    echo "   oai    → xOAI indexing" ;;
      biblio) echo "   biblio → frontend (VuFind) indexing" ;;
      *)      echo "   ${core} → reindex its documents" ;;
    esac
  done
  echo " Marker: <core>/${REINDEX_MARKER} (delete it after reindexing)."
  echo "=================================================================="
}

# --- commands ---------------------------------------------------------------------------

update_config() {
  local allow_rebuild="$1"
  require_templates
  update_all_cores "${allow_rebuild}"
  sync_support_files
  record_build_info
  touch "${INIT_MARKER}"
  fix_permissions
}

verify_config() {
  require_templates
  local core failed=0
  while IFS= read -r core; do
    if [ ! -d "${SOLR_DATA_DIR}/${core}" ]; then
      echo "MISSING    ${core}: not installed in ${SOLR_DATA_DIR}"
      failed=1
    elif conf_differs "${core}"; then
      echo "DIFFERENT  ${core}: installed configuration differs from the template"
      diff -rq "${SOLR_TEMPLATE_DIR}/${core}/conf" "${SOLR_DATA_DIR}/${core}/conf" 2>&1 | sed 's/^/             /' || true
      failed=1
    else
      echo "OK         ${core}: installed configuration matches the template"
    fi
    if [ -f "${SOLR_DATA_DIR}/${core}/${MIGRATION_MARKER}" ]; then
      echo "           ${core}: schema migration pending (./Docker/docker.sh solr migrate)"
    fi
    if [ -f "${SOLR_DATA_DIR}/${core}/${REINDEX_MARKER}" ]; then
      echo "           ${core}: reindex still pending (${REINDEX_MARKER})"
    fi
  done < <(template_cores)
  return "${failed}"
}

# Read-only (no mkdir, no copy): safe to run on the host over the Solr volume.
pending_migrations() {
  local core target template old_schema new_schema conflicts
  while IFS= read -r core; do
    target="${SOLR_DATA_DIR}/${core}"
    template="${SOLR_TEMPLATE_DIR}/${core}"
    [ -d "${target}" ] || continue
    conf_differs "${core}" || continue
    old_schema="$(schema_file "${target}/conf")"
    new_schema="$(schema_file "${template}/conf")"
    [ -n "${old_schema}" ] && [ -n "${new_schema}" ] || continue
    cmp -s "${old_schema}" "${new_schema}" && continue
    conflicts="$(schema_conflicts "${old_schema}" "${new_schema}" | tr '\n' ' ' | sed 's/ $//')"
    [ -n "${conflicts}" ] || continue
    index_populated "${core}" || continue
    printf '%s\t%s\n' "${core}" "${conflicts}"
  done < <(template_cores)
}

start_solr() {
  prepare_dirs
  require_templates
  local mode="${SOLR_UPDATE_CONFIG:-auto}" migration="${LR_SOLR_SCHEMA_MIGRATION:-keep}"
  case "${migration}" in keep|rebuild) ;; *)
    echo "Error: LR_SOLR_SCHEMA_MIGRATION must be keep or rebuild (got '${migration}')." >&2; return 1 ;;
  esac
  case "${mode}" in
    false|no|off|0) report_outdated_cores ;;
    *)              update_all_cores "$([ "${migration}" = rebuild ] && echo true || echo false)" ;;
  esac
  record_build_info
  touch "${INIT_MARKER}"
  sync_support_files
  print_summary
  echo "Fixing permissions for solr user..."
  fix_permissions
  echo "Starting Solr as solr user (via gosu)..."
  exec gosu solr "${SOLR_BIN}" start -f -s "${SOLR_DATA_DIR}" -p 8983
}

main() {
  case "${1:-}" in
    update-config)
      prepare_dirs
      update_config false
      local status=0
      reload_cores || status=1
      print_summary
      [ "${status}" -eq 0 ] && [ "${#PENDING_CORES[@]}" -gt 0 ] && status=3
      return "${status}"
      ;;
    migrate)
      if solr_is_up; then
        echo "Error: migrate moves index files: stop Solr first (./Docker/docker.sh solr migrate does it)." >&2
        return 1
      fi
      prepare_dirs
      update_config true
      print_summary
      return 0
      ;;
    verify-config)
      verify_config
      return $?
      ;;
    pending-migrations)
      pending_migrations
      return 0
      ;;
    ""|solr|solr-foreground)
      start_solr
      ;;
    *)
      if command -v "$1" >/dev/null 2>&1; then
        exec "$@"
      fi
      echo "Error: unknown command '$1' (use update-config, migrate, verify-config, pending-migrations or no argument)." >&2
      return 1
      ;;
  esac
}

main "$@"
