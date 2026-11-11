#!/usr/bin/env bats
# Docker/solr/entrypoint.sh: first start, automatic updates on start ("stop,
# pull, start"), incompatible schemas kept or rebuilt, update-config, migrate
# and verify-config — over fixture directories with fake gosu/chown/curl.

load ../helpers/unit

setup() {
  T="${BATS_TEST_TMPDIR}"
  TPL="${T}/tpl/cores"
  DATA="${T}/data"
  export LR_SOLR_DATA_DIR="${DATA}" LR_SOLR_LOG_DIR="${T}/log" LR_SOLR_CACHE_DIR="${T}/cache" \
         LR_SOLR_VENDOR_DIR="${T}/vendor" LR_SOLR_MODULES_DIR="${T}/modules" \
         LR_SOLR_TEMPLATE_DIR="${TPL}" LR_SOLR_JARS_TEMPLATE_DIR="${T}/tpl/jars" \
         LR_SOLR_IMPORT_TEMPLATE_DIR="${T}/tpl/import" LR_SOLR_IMPORT_DIR="${T}/import" \
         LR_SOLR_BIN="/opt/solr/bin/solr" LR_SOLR_LOCAL_URL="http://solr.test/solr"
  export CALLS="${T}/calls.log"
  unset SOLR_UPDATE_CONFIG LR_SOLR_SCHEMA_MIGRATION FAKE_SOLR_UP FAKE_RELOAD_FAIL
  : > "${CALLS}"

  # fakes: gosu (instead of starting Solr), chown (not root), curl (CoreAdmin)
  FAKES="${T}/fakes"
  mkdir -p "${FAKES}"
  printf '#!/usr/bin/env bash\necho "gosu $*" >> "${CALLS}"\n' > "${FAKES}/gosu"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${FAKES}/chown"
  cat > "${FAKES}/curl" <<'EOF'
#!/usr/bin/env bash
url="${!#}"
echo "curl ${url}" >> "${CALLS}"
[ "${FAKE_SOLR_UP:-0}" = 1 ] || exit 7
case "${url}" in
  *action=RELOAD*)
    for c in ${FAKE_RELOAD_FAIL:-}; do
      [[ "${url}" == *"core=${c}&"* ]] && { echo '{"responseHeader":{"status":500},"error":{"msg":"bad schema"}}'; exit 0; }
    done
    echo '{"responseHeader":{"status":0,"QTime":12}}' ;;
  *) echo '{"responseHeader":{"status":0}}' ;;
esac
EOF
  chmod +x "${FAKES}"/*

  # Staged templates (what stage-cores.sh produces).
  local core
  for core in oai biblio; do
    mkdir -p "${TPL}/${core}/conf"
    echo "name=${core}" > "${TPL}/${core}/core.properties"
    echo "<config/>" > "${TPL}/${core}/conf/solrconfig.xml"
    schema "${core}" "${TPL}/${core}/conf/schema.xml" LongPointField
  done
  echo "core.biblio.revision=abc123" > "${TPL}/build-info.properties"
  touch "${TPL}/.gitkeep"
  mkdir -p "${T}/tpl/jars" "${T}/tpl/import"
  echo "jar 1" > "${T}/tpl/jars/MarcImporter.jar"
  touch "${T}/tpl/jars/.gitkeep"
  echo "import" > "${T}/tpl/import/import.properties"
}

# schema <core> <file> <class of the "long" type> [extra field line]
schema() {
  cat > "$2" <<EOF
<schema name="$1" version="1.6">
  <!-- <fieldType name="long" class="solr.Commented"/> is ignored -->
  <fieldType name="long" class="solr.$3" omitNorms="true"/>
  <fieldType name="string" class="solr.StrField"/>
  <field name="item.id" type="long" indexed="true" stored="true"/>
  <field name="item.handle" type="string" indexed="true" stored="true"/>
  ${4:-}
</schema>
EOF
}

entrypoint() {
  run env PATH="${FAKES}:${PATH}" bash "${PROJECT_DIR}/Docker/solr/entrypoint.sh" "$@"
}

# An installation with documents. Index layouts as Solr writes them:
# oai → dataDir oai/data/ ; VuFind's biblio → dataDir is the core directory.
installed() {
  entrypoint
  assert_success
  mkdir -p "${DATA}/oai/data/index" "${DATA}/oai/data/tlog" "${DATA}/biblio/index" "${DATA}/biblio/tlog"
  echo "segment of oai" > "${DATA}/oai/data/index/_0.cfs"
  echo "segment of biblio" > "${DATA}/biblio/index/_0.cfs"
  touch "${DATA}/oai/data/index/segments_2" "${DATA}/biblio/index/segments_5" \
        "${DATA}/oai/data/tlog/tlog.0" "${DATA}/biblio/tlog/tlog.0"
  : > "${CALLS}"
}

# The installed oai core is the old Docker copy: Trie fields, as one month ago.
old_trie_oai() {
  schema oai "${DATA}/oai/conf/schema.xml" TrieLongField
}

# --- first start -----------------------------------------------------------------

@test "first start: installs every core as staged and starts Solr as the solr user" {
  entrypoint
  assert_success
  diff -r "${TPL}/oai" "${DATA}/oai"
  diff -r "${TPL}/biblio" "${DATA}/biblio"
  [ -f "${DATA}/.lr_initialized" ]
  grep -qx "core.biblio.revision=abc123" "${DATA}/.lr_cores_build_info"
  grep -qx "gosu solr /opt/solr/bin/solr start -f -s ${DATA} -p 8983" "${CALLS}"
}

@test "first start: staging metadata is not copied into the Solr home as if it were a core" {
  entrypoint
  assert_success
  [ ! -e "${DATA}/build-info.properties" ]
  [ ! -e "${DATA}/.gitkeep" ]
}

@test "first start without staged cores: fails, no init marker, Solr not started" {
  rm -rf "${TPL:?}"/oai "${TPL:?}"/biblio
  entrypoint
  assert_failure
  assert_output_contains "no Solr core templates"
  assert_output_contains "docker.sh solr stage"
  [ ! -f "${DATA}/.lr_initialized" ]
  ! grep -q gosu "${CALLS}"
}

@test "jars and import assets mirror the staging (no .gitkeep, stale jars removed)" {
  installed
  echo "stale" > "${DATA}/jars/old-version.jar"
  entrypoint
  assert_success
  [ ! -e "${DATA}/jars/old-version.jar" ]
  [ ! -e "${DATA}/jars/.gitkeep" ]
  [ "$(cat "${DATA}/jars/MarcImporter.jar")" = "jar 1" ]
  [ -f "${T}/import/import.properties" ]
}

# --- stop, pull, start: automatic updates -------------------------------------------

@test "start after a pull, compatible change (new field): applied automatically, index kept, reindex flagged" {
  installed
  schema biblio "${TPL}/biblio/conf/schema.xml" LongPointField '<field name="vector" type="knn" indexed="true"/>'
  entrypoint
  assert_success
  diff -r "${TPL}/biblio/conf" "${DATA}/biblio/conf"
  [ "$(cat "${DATA}/biblio/index/_0.cfs")" = "segment of biblio" ]
  ls -d "${DATA}"/biblio/conf.bak.* >/dev/null
  [ -f "${DATA}/biblio/.lr_reindex_required" ]
  assert_output_contains "REINDEX REQUIRED for: biblio"
  grep -q "gosu solr" "${CALLS}"
}

@test "start after a pull, solrconfig-only change: applied, no reindex" {
  installed
  echo "<config><!-- tuned --></config>" > "${TPL}/oai/conf/solrconfig.xml"
  entrypoint
  assert_success
  grep -q tuned "${DATA}/oai/conf/solrconfig.xml"
  [ ! -f "${DATA}/oai/.lr_reindex_required" ]
  refute_output_contains "REINDEX"
}

@test "start after a pull, Trie → Point on a populated index: keeps working on the old schema, migration reported" {
  installed
  old_trie_oai
  entrypoint
  assert_success                                   # Solr starts: no outage
  grep -q "gosu solr" "${CALLS}"
  grep -q TrieLongField "${DATA}/oai/conf/schema.xml"
  [ "$(cat "${DATA}/oai/data/index/_0.cfs")" = "segment of oai" ]
  assert_output_contains "incompatible with the existing index (fieldType:long)"
  assert_output_contains "SCHEMA MIGRATION PENDING for: oai"
  assert_output_contains "./Docker/docker.sh solr migrate"
  grep -qx "incompatible=fieldType:long" "${DATA}/oai/.lr_migration_pending"
}

@test "start with LR_SOLR_SCHEMA_MIGRATION=rebuild: new schema + empty index, old index kept aside" {
  installed
  old_trie_oai
  LR_SOLR_SCHEMA_MIGRATION=rebuild entrypoint
  assert_success
  grep -q LongPointField "${DATA}/oai/conf/schema.xml"
  [ ! -e "${DATA}/oai/data/index" ]
  local prev
  prev="$(ls -d "${DATA}"/oai/previous-index-*)"
  [ "$(cat "${prev}/data/index/_0.cfs")" = "segment of oai" ]
  [ -f "${prev}/data/tlog/tlog.0" ]
  [ ! -f "${DATA}/oai/.lr_migration_pending" ]
  [ -f "${DATA}/oai/.lr_reindex_required" ]
  assert_output_contains "REINDEX REQUIRED for: oai"
  # biblio unchanged and untouched
  [ "$(cat "${DATA}/biblio/index/_0.cfs")" = "segment of biblio" ]
}

@test "incompatible schema on an empty core: installed directly (nothing to lose)" {
  entrypoint
  old_trie_oai
  : > "${CALLS}"
  entrypoint
  assert_success
  grep -q LongPointField "${DATA}/oai/conf/schema.xml"
  refute_output_contains "MIGRATION PENDING"
}

@test "incompatible schema on a core Solr created but never filled (segments_1 + write.lock only): installed directly" {
  entrypoint
  mkdir -p "${DATA}/oai/data/index"
  touch "${DATA}/oai/data/index/segments_1" "${DATA}/oai/data/index/write.lock"
  old_trie_oai
  entrypoint
  assert_success
  grep -q LongPointField "${DATA}/oai/conf/schema.xml"
  refute_output_contains "MIGRATION PENDING"
}

@test "SOLR_UPDATE_CONFIG=false: nothing applied automatically, only a warning" {
  installed
  echo "<config><!-- tuned --></config>" > "${TPL}/oai/conf/solrconfig.xml"
  SOLR_UPDATE_CONFIG=false entrypoint
  assert_success
  ! grep -q tuned "${DATA}/oai/conf/solrconfig.xml"
  assert_output_contains "configuration of oai differs from the staged one and was NOT applied"
}

@test "restart with a core added to the staging: the new core is installed" {
  installed
  mkdir -p "${TPL}/extra/conf"
  echo "name=extra" > "${TPL}/extra/core.properties"
  entrypoint
  assert_success
  [ -f "${DATA}/extra/core.properties" ]
}

@test "an invalid LR_SOLR_SCHEMA_MIGRATION stops the start" {
  LR_SOLR_SCHEMA_MIGRATION=maybe entrypoint
  assert_failure
  assert_output_contains "LR_SOLR_SCHEMA_MIGRATION must be keep or rebuild"
}

# --- update-config / migrate ----------------------------------------------------------

@test "update-config: replaces conf/ and core.properties, keeps the index and a backup" {
  installed
  schema oai "${TPL}/oai/conf/schema.xml" LongPointField '<field name="new" type="string"/>'
  printf 'name=oai\nconfig=solrconfig.xml\n' > "${TPL}/oai/core.properties"
  entrypoint update-config
  assert_success
  diff -r "${TPL}/oai/conf" "${DATA}/oai/conf"
  cmp "${TPL}/oai/core.properties" "${DATA}/oai/core.properties"
  [ "$(cat "${DATA}/oai/data/index/_0.cfs")" = "segment of oai" ]
  local backup
  backup="$(ls -d "${DATA}"/oai/conf.bak.*)"
  ! grep -q 'name="new"' "${backup}/schema.xml"
  ! grep -q gosu "${CALLS}"        # does not start a second Solr
}

@test "update-config: nothing changed → no backup, no reindex" {
  installed
  entrypoint update-config
  assert_success
  assert_output_contains "Core 'oai': configuration already up to date."
  ! ls -d "${DATA}"/oai/conf.bak.* 2>/dev/null
  refute_output_contains "REINDEX"
}

@test "update-config: an incompatible schema is never forced over the index (exit 3, core unchanged)" {
  installed
  old_trie_oai
  export FAKE_SOLR_UP=1
  entrypoint update-config
  [ "${status}" -eq 3 ]
  grep -q TrieLongField "${DATA}/oai/conf/schema.xml"
  [ -e "${DATA}/oai/data/index/_0.cfs" ]
  assert_output_contains "SCHEMA MIGRATION PENDING for: oai"
}

@test "update-config: works on an installation that never had the init marker" {
  mkdir -p "${DATA}"
  entrypoint update-config
  assert_success
  [ -f "${DATA}/.lr_initialized" ]
  diff -r "${TPL}/biblio" "${DATA}/biblio"
}

@test "update-config with Solr running: every core is reloaded through CoreAdmin" {
  installed
  export FAKE_SOLR_UP=1
  entrypoint update-config
  assert_success
  grep -q "action=RELOAD&core=oai&" "${CALLS}"
  grep -q "action=RELOAD&core=biblio&" "${CALLS}"
  assert_output_contains "Core 'biblio': reloaded."
}

@test "update-config: a core that fails to reload → exit 1 with the rollback hint" {
  installed
  echo "<config><!-- broken --></config>" > "${TPL}/biblio/conf/solrconfig.xml"
  export FAKE_SOLR_UP=1 FAKE_RELOAD_FAIL="biblio"
  entrypoint update-config
  [ "${status}" -eq 1 ]
  assert_output_contains "core 'biblio' failed to reload"
  assert_output_contains "conf.bak"
  assert_output_contains "Core 'oai': reloaded."
}

@test "update-config without staged cores: fails without touching the Solr home" {
  installed
  rm -rf "${TPL:?}"/oai "${TPL:?}"/biblio
  entrypoint update-config
  assert_failure
  [ -d "${DATA}/oai/conf" ]
}

@test "migrate (Solr stopped): rebuilds the incompatible core, VuFind biblio layout handled" {
  installed
  old_trie_oai
  schema biblio "${DATA}/biblio/conf/schema.xml" TrieLongField
  entrypoint migrate
  assert_success
  grep -q LongPointField "${DATA}/oai/conf/schema.xml"
  grep -q LongPointField "${DATA}/biblio/conf/schema.xml"
  # biblio's dataDir is the core directory: index/ and tlog/ moved from there
  [ ! -e "${DATA}/biblio/index" ] && [ ! -e "${DATA}/biblio/tlog" ]
  [ "$(cat "$(ls -d "${DATA}"/biblio/previous-index-*)/index/_0.cfs")" = "segment of biblio" ]
  assert_output_contains "REINDEX REQUIRED for: biblio oai"
}

@test "migrate refuses while Solr is running (would move open index files)" {
  installed
  old_trie_oai
  export FAKE_SOLR_UP=1
  entrypoint migrate
  assert_failure
  assert_output_contains "stop Solr first"
  [ -e "${DATA}/oai/data/index/_0.cfs" ]
}

# --- verify-config ---------------------------------------------------------------------

@test "verify-config: installed == staged → OK" {
  installed
  entrypoint verify-config
  assert_success
  assert_output_contains "OK         oai"
  assert_output_contains "OK         biblio"
}

@test "verify-config: a staged change not applied yet → DIFFERENT, exit 1" {
  installed
  echo "<config><!-- new --></config>" > "${TPL}/biblio/conf/solrconfig.xml"
  entrypoint verify-config
  assert_failure
  assert_output_contains "DIFFERENT  biblio"
  assert_output_contains "OK         oai"
}

@test "verify-config: shows a pending migration and a pending reindex" {
  installed
  old_trie_oai
  schema biblio "${TPL}/biblio/conf/schema.xml" LongPointField '<field name="vector" type="knn"/>'
  entrypoint
  entrypoint verify-config
  assert_failure
  assert_output_contains "oai: schema migration pending"
  assert_output_contains "biblio: reindex still pending"
}

@test "an unknown argument that is not a command fails clearly" {
  entrypoint not-a-command
  assert_failure
  assert_output_contains "unknown command 'not-a-command'"
}

# --- pending-migrations (read-only, run on the host by docker.sh / the wizard) ------------

@test "pending-migrations: lists the incompatible populated core and changes nothing" {
  installed
  old_trie_oai
  local before
  before="$(find "${DATA}" -print | sort | shasum)"
  entrypoint pending-migrations
  assert_success
  [ "${output}" = "$(printf 'oai\tfieldType:long')" ]
  [ "$(find "${DATA}" -print | sort | shasum)" = "${before}" ]
  ! grep -q gosu "${CALLS}"
}

@test "pending-migrations: compatible changes and empty cores are not migrations" {
  installed
  schema biblio "${TPL}/biblio/conf/schema.xml" LongPointField '<field name="vector" type="knn"/>'
  entrypoint pending-migrations
  assert_success
  [ -z "${output}" ]
}

@test "pending-migrations: no Solr volume yet → nothing, nothing created" {
  entrypoint pending-migrations
  assert_success
  [ -z "${output}" ]
  [ ! -e "${DATA}" ]
}
