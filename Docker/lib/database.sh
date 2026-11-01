#!/usr/bin/env bash
# =============================================================================
# database.sh — "Database" (PostgreSQL), "PgUpgrade" (major version migration)
# and "LrShell" (Spring Shell container).
#
# Public API — database:
#   db::wait_until_ready             polls pg_isready (30s)
#   db::init [shell command...]      runs migrations / db_init_script.txt
#   db::psql <sql>                   runs SQL in the postgres container
#
# Public API — major version upgrade (see the section below for the design):
#   pg::status                       fresh | ok | upgrade_required | incompatible | interrupted
#   pg::ensure_compatible            guard used before starting postgres
#   pg::describe                     human readable report
#   pg::upgrade                      dump/restore migration to PG_TARGET_IMAGE
#   pg::rollback                     goes back to the preserved old cluster
#   pg::remove_legacy                deletes the preserved old cluster
#   pg::legacy_removal_due           true once the retention period has passed
#   pg::last_migration <field>       from_major | to_major | migrated_at | legacy_dir | status
#   pg::legacy_path                  absolute path of the preserved old cluster
#   pg::target_major                 major version of the default image
#   pg::pin_data_version             pins the image matching the data (prints it)
#   pg::unpin                        back to the default image
#   pg::format_date <epoch>
#   pg::path [relative]              absolute path under the postgres volume
#   pg::default_image
#
# Public API — lrshell:
#   lrshell::run [cmd...]            non-interactive command in the shell service
#   lrshell::run_interactive [cmd...]
# =============================================================================

DB_USER="lrharvester"
DB_PASSWORD="lrharvester"
DB_NAME="lrharvester"
DB_INIT_SCRIPT="${ROOT_DIR}/Docker/config-overrides/lareferencia-shell/db_init_script.txt"
LRSHELL_ENTRYPOINT="/usr/local/bin/lr-app-entrypoint.sh"

# --- PostgreSQL -------------------------------------------------------------------

db::wait_until_ready() {
  local retries=30
  echo -n "Waiting for PostgreSQL to be ready..."
  while [ "${retries}" -gt 0 ]; do
    if dc exec -T postgres pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
      echo " ready."
      return 0
    fi
    retries=$((retries - 1))
    echo -n "."
    sleep 1
  done
  echo -e "\n${C_RED}❌ Timed out waiting for PostgreSQL to become ready.${C_RESET}" >&2
  return 1
}

db::start_infrastructure() {
  dc up -d postgres solr
  db::wait_until_ready
}

db::psql() {
  dc exec -T postgres psql -U "${DB_USER}" -d "${DB_NAME}" -c "$1"
}

db::init() {
  local shell_cmd=("$@")
  if [ "${#shell_cmd[@]}" -eq 0 ]; then
    if [ -f "${DB_INIT_SCRIPT}" ]; then
      shell_cmd=(script /tmp/lr-config/lareferencia-shell/db_init_script.txt)
    else
      shell_cmd=(database_migrate)
    fi
  fi

  echo "--- Cleaning up potential remnants from previous runs ---"
  # Only ephemeral containers: postgres/solr are preserved.
  dc --profile tools rm -f -s -v shell db-init 2>/dev/null || true

  echo "--- Running Database Initialization ---"
  dc --profile tools up -d postgres solr
  db::wait_until_ready

  local exit_code=0
  dc --profile tools run --rm -T --no-deps shell "${LRSHELL_ENTRYPOINT}" "${shell_cmd[@]}" || exit_code=$?

  if [ "${exit_code}" -ne 0 ]; then
    echo -e "\n${C_RED}❌ Database initialization failed with exit code ${exit_code}.${C_RESET}"
    exit "${exit_code}"
  fi
  echo -e "\n${C_GREEN}✔ Database initialization completed successfully.${C_RESET}"
}

# =============================================================================
# PostgreSQL major version upgrade ("PgUpgrade")
#
# PostgreSQL cannot open a data directory created by another major version, so
# moving from 14 to 17 is done with dump/restore:
#
#   1. stop the platform
#   2. start a temporary container with the OLD image on the current data
#   3. dump globals + every database with the NEW version's pg_dump
#   4. move   data/  →  pg<old>-backup-<timestamp>/data/      (kept for rollback)
#   5. start the NEW postgres on an empty data/ and restore the dumps
#   6. ANALYZE and compare exact row counts of every table (old vs new)
#   7. any failure after step 4 → automatic rollback to the old cluster
#
# Layout under Docker/volume/lareferencia/postgres/:
#
#   data/                               cluster in use (mounted by compose)
#   pg14-backup-<ts>/data/              preserved old cluster (rollback)
#   pg14-backup-<ts>/dump/              dumps, row counts, README
#   pg17-rolledback-<ts>/data/          cluster set aside by a rollback
#   upgrade.state                       key=value record of the last migration
#
# Configuration (Docker/.env):
#   LR_POSTGRES_IMAGE                   pins the postgres image (empty = default)
#   LR_PG_LEGACY_RETENTION_SECONDS      after this time the wizard offers to
#                                       delete the old cluster (default 30 days)
#
# The directory is usually owned by the container user (uid 70, mode 0700), so
# file operations run inside a throw-away alpine container (_pg::sh).
# =============================================================================

# Must match the default of `image:` in docker-compose.yml.
PG_DEFAULT_IMAGE="postgres:17-alpine3.23"
# Exact image previously used for each major version (others: postgres:<N>-alpine).
PG_KNOWN_IMAGES=("14|postgres:14.15-alpine")
PG_DEFAULT_RETENTION_SECONDS=2592000   # 30 days

PG_DATA_ROOT="${VOLUME_DIR}/lareferencia/postgres"
PG_STATE_FILE="upgrade.state"          # relative to PG_DATA_ROOT
PG_LOCK_DIR="${SCRIPT_DIR}/.pg-upgrade.lock"

# --- Low-level helpers ----------------------------------------------------------------

# Runs a shell command with PG_DATA_ROOT mounted at /pg.
_pg::sh() {
  mkdir -p "${PG_DATA_ROOT}" 2>/dev/null || true
  docker run --rm -v "${PG_DATA_ROOT}:/pg" alpine sh -c "$1"
}

# Writes stdin to /pg/<path>.
_pg::write() {
  docker run --rm -i -v "${PG_DATA_ROOT}:/pg" alpine sh -c 'cat > "/pg/$1"' _ "$1"
}

# Prints /pg/<path> (reads directly when the host user is allowed to).
_pg::read() {
  local path="$1"
  [ -d "${PG_DATA_ROOT}" ] || return 0
  if [ -r "${PG_DATA_ROOT}/${path}" ]; then
    cat "${PG_DATA_ROOT}/${path}"
  else
    _pg::sh "cat '/pg/${path}' 2>/dev/null" || true
  fi
}

_pg::now() { date +%s; }

pg::format_date() {
  date -d "@$1" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$1" "+%Y-%m-%d %H:%M"
}

# --- State file (key=value) ---------------------------------------------------------------

_pg::state_get() {
  _pg::read "${PG_STATE_FILE}" | awk -F= -v k="$1" '$1 == k { v = substr($0, length(k) + 2) } END { print v }'
}

# _pg::state_save key=value...   (replaces the whole file)
_pg::state_save() {
  printf '%s\n' "$@" | _pg::write "${PG_STATE_FILE}"
}

# _pg::state_update key=value...  (merges into the existing file)
_pg::state_update() {
  local current pair key
  current="$(_pg::read "${PG_STATE_FILE}")"
  for pair in "$@"; do
    key="${pair%%=*}"
    current="$(printf '%s\n' "${current}" | grep -v "^${key}=" || true)"
    current="${current:+${current}$'\n'}${pair}"
  done
  printf '%s\n' "${current}" | _pg::write "${PG_STATE_FILE}"
}

# Public, read-only view of the last migration record.
pg::last_migration() {
  _pg::state_get "$1"
}

# --- Versions --------------------------------------------------------------------------------

# Image compose will use (LR_POSTGRES_IMAGE pin or the default).
pg::configured_image() {
  config::get LR_POSTGRES_IMAGE "${PG_DEFAULT_IMAGE}"
}

pg::is_pinned() {
  [ -n "$(config::get LR_POSTGRES_IMAGE "")" ]
}

# Major version of an image, from its tag or by asking the binary.
pg::image_major() {
  local image="$1" tag="${1##*:}"
  if [[ "${tag}" =~ ^([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    docker run --rm --entrypoint postgres "${image}" --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1
  fi
}

# Image to use for a given major version.
pg::image_for_major() {
  local major="$1" row
  for row in "${PG_KNOWN_IMAGES[@]}"; do
    [ "${row%%|*}" = "${major}" ] && { echo "${row#*|}"; return 0; }
  done
  echo "postgres:${major}-alpine"
}

pg::path() {
  echo "${PG_DATA_ROOT}${1:+/$1}"
}

pg::default_image() {
  echo "${PG_DEFAULT_IMAGE}"
}

pg::target_major() {
  pg::image_major "${PG_DEFAULT_IMAGE}"
}

# Keeps the current data version: pins its image in .env and prints it.
pg::pin_data_version() {
  local image
  image="$(pg::image_for_major "$(pg::data_major)")"
  config::set LR_POSTGRES_IMAGE "${image}"
  echo "${image}"
}

pg::unpin() {
  config::set LR_POSTGRES_IMAGE ""
}

# Major version of the cluster in data/ (empty for a fresh install).
pg::data_major() {
  _pg::read "data/pgdata/PG_VERSION" | tr -d '[:space:]'
}

pg::retention_seconds() {
  local value
  value="$(config::get LR_PG_LEGACY_RETENTION_SECONDS "${PG_DEFAULT_RETENTION_SECONDS}")"
  [[ "${value}" =~ ^[0-9]+$ ]] || value="${PG_DEFAULT_RETENTION_SECONDS}"
  echo "${value}"
}

# --- Status ------------------------------------------------------------------------------------

pg::status() {
  if [ "$(_pg::state_get status)" = "in_progress" ]; then
    echo "interrupted"
    return 0
  fi

  local data_major image_major
  data_major="$(pg::data_major)"
  if [ -z "${data_major}" ]; then
    echo "fresh"
    return 0
  fi

  image_major="$(pg::image_major "$(pg::configured_image)")"
  if [ "${data_major}" -eq "${image_major}" ]; then
    echo "ok"
  elif [ "${data_major}" -lt "${image_major}" ]; then
    echo "upgrade_required"
  else
    echo "incompatible"
  fi
}

# True when the data is older than the default image (e.g. pinned to 14).
pg::upgrade_available() {
  local data_major
  data_major="$(pg::data_major)"
  [ -n "${data_major}" ] && [ "${data_major}" -lt "$(pg::image_major "${PG_DEFAULT_IMAGE}")" ]
}

# Old cluster preserved by the last successful migration (relative path) or empty.
pg::legacy_dir() {
  [ "$(_pg::state_get status)" = "done" ] || return 0
  local dir
  dir="$(_pg::state_get legacy_dir)"
  [ -n "${dir}" ] && [ -n "$(_pg::sh "[ -d '/pg/${dir}/data' ] && echo yes" 2>/dev/null)" ] && echo "${dir}"
  return 0
}

pg::legacy_path() {
  local dir
  dir="$(pg::legacy_dir)"
  [ -n "${dir}" ] && echo "${PG_DATA_ROOT}/${dir}"
  return 0
}

pg::rollback_available() {
  [ -n "$(pg::legacy_dir)" ]
}

# Epoch from which the wizard offers to delete the old cluster.
pg::legacy_removal_date() {
  local migrated_at
  migrated_at="$(_pg::state_get migrated_at)"
  [ -n "${migrated_at}" ] && echo $((migrated_at + $(pg::retention_seconds)))
}

pg::legacy_removal_due() {
  pg::rollback_available || return 1
  [ "$(_pg::now)" -ge "$(pg::legacy_removal_date)" ]
}

pg::dir_size() {
  _pg::sh "du -sh '/pg/$1' 2>/dev/null | cut -f1" || echo "?"
}

pg::describe() {
  local data_major legacy
  data_major="$(pg::data_major)"
  legacy="$(pg::legacy_dir)"

  echo -e "  ${C_GRAY}Data directory:${C_RESET}   ${PG_DATA_ROOT}/data"
  echo -e "  ${C_GRAY}Data version:${C_RESET}     ${data_major:-none (fresh install)}"
  echo -e "  ${C_GRAY}Configured image:${C_RESET} $(pg::configured_image)$(pg::is_pinned && echo " (pinned in .env)")"
  echo -e "  ${C_GRAY}Default image:${C_RESET}    ${PG_DEFAULT_IMAGE}"
  echo -e "  ${C_GRAY}Status:${C_RESET}           $(pg::status)"
  if [ -n "$(_pg::state_get migrated_at)" ]; then
    echo -e "  ${C_GRAY}Last migration:${C_RESET}   $(_pg::state_get from_major) → $(_pg::state_get to_major) on $(pg::format_date "$(_pg::state_get migrated_at)") ($(_pg::state_get status))"
  fi
  if [ -n "${legacy}" ]; then
    echo -e "  ${C_GRAY}Rollback copy:${C_RESET}    ${PG_DATA_ROOT}/${legacy}"
    echo -e "  ${C_GRAY}Removal offered:${C_RESET}  from $(pg::format_date "$(pg::legacy_removal_date)")"
  fi
}

# Guard used by every command that may start the postgres container.
pg::ensure_compatible() {
  local status
  status="$(pg::status)"
  case "${status}" in
    fresh|ok) return 0 ;;
    upgrade_required)
      ui::error "❌ PostgreSQL data is version $(pg::data_major), but the configured image is $(pg::configured_image)."
      echo "   PostgreSQL cannot open data from an older major version. Choose one:" >&2
      echo "   • Migrate (keeps a copy for rollback):  ./Docker/docker.sh postgres upgrade" >&2
      echo "   • Keep the old version for now:         set LR_POSTGRES_IMAGE=$(pg::image_for_major "$(pg::data_major)") in Docker/.env" >&2
      echo "   (The wizard offers both options.)" >&2
      ;;
    incompatible)
      ui::error "❌ PostgreSQL data is version $(pg::data_major), newer than the configured image $(pg::configured_image)."
      echo "   Remove LR_POSTGRES_IMAGE from Docker/.env, or go back with: ./Docker/docker.sh postgres rollback" >&2
      ;;
    interrupted)
      ui::error "❌ A PostgreSQL upgrade was interrupted. Restore the previous cluster first:"
      echo "   ./Docker/docker.sh postgres rollback" >&2
      ;;
  esac
  return 1
}

# --- Upgrade steps (private) -------------------------------------------------------------------

_PG_TMP_NET=""
_PG_TMP_OLD=""

_pg::cleanup_temporaries() {
  [ -n "${_PG_TMP_OLD}" ] && docker rm -f "${_PG_TMP_OLD}" >/dev/null 2>&1 || true
  [ -n "${_PG_TMP_NET}" ] && docker network rm "${_PG_TMP_NET}" >/dev/null 2>&1 || true
  rmdir "${PG_LOCK_DIR}" 2>/dev/null || true
}

_pg::acquire_lock() {
  if ! mkdir "${PG_LOCK_DIR}" 2>/dev/null; then
    ui::error "Another PostgreSQL upgrade/rollback seems to be running (lock: ${PG_LOCK_DIR})."
    ui::error "If that is not the case, remove the lock directory and try again."
    return 1
  fi
  trap _pg::cleanup_temporaries EXIT
}

# Stops every service and removes the postgres container (it is recreated later).
_pg::stop_platform() {
  echo "--- Stopping the platform ---"
  local profiles=() m
  for m in $(module::all); do profiles+=("$(module::cli_profile "${m}")"); done
  compose::run_with_profiles "${profiles[@]}" -- stop
  dc rm -f -s postgres >/dev/null 2>&1 || true
}

_pg::check_disk_space() {
  local used_kb free_kb
  used_kb="$(_pg::sh "du -sk /pg/data | cut -f1")"
  free_kb="$(df -Pk "${PG_DATA_ROOT}" | awk 'NR == 2 { print $4 }')"
  echo "Current cluster: $((used_kb / 1024)) MB — free disk: $((free_kb / 1024)) MB"
  # New cluster + dump, conservatively estimated as twice the current size.
  if [ "${free_kb}" -lt $((used_kb * 2)) ]; then
    ui::error "❌ Not enough disk space: at least $((used_kb * 2 / 1024)) MB free are required."
    return 1
  fi
}

# Exact row count of every table: "<db>.<schema>.<table>|<count>" per line.
_PG_COUNT_SQL="SELECT format('SELECT %L || ''|'' || count(*) FROM %I.%I', current_database() || '.' || n.nspname || '.' || c.relname, n.nspname, c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname NOT LIKE 'pg_toast%'
ORDER BY 1
\\gexec"

# _pg::row_counts <psql command...>   (receives -d <db> as last args)
_pg::row_counts() {
  printf '%s\n' "${_PG_COUNT_SQL}" | "$@" -At -v ON_ERROR_STOP=1 -f -
}

# psql/pg_dump against the temporary OLD server, using the NEW client binaries.
_pg::old_client() {
  docker run --rm -i --network "${_PG_TMP_NET}" -e PGPASSWORD="${DB_PASSWORD}" \
    "${PG_TARGET_IMAGE}" "$@" -h old -U "${DB_USER}"
}

_pg::start_old_server() {
  local old_image="$1"
  _PG_TMP_NET="${COMPOSE_PROJECT_NAME}-pg-upgrade"
  _PG_TMP_OLD="${COMPOSE_PROJECT_NAME}-pg-upgrade-old"

  echo "--- Starting temporary ${old_image} on the current data ---"
  docker rm -f "${_PG_TMP_OLD}" >/dev/null 2>&1 || true
  docker network create "${_PG_TMP_NET}" >/dev/null 2>&1 || true
  docker run -d --name "${_PG_TMP_OLD}" --network "${_PG_TMP_NET}" --network-alias old \
    -e PGDATA=/var/lib/postgresql/data/pgdata -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
    -v "${PG_DATA_ROOT}/data:/var/lib/postgresql/data" \
    "${old_image}" >/dev/null || return 1

  local retries=60
  until docker exec "${_PG_TMP_OLD}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "${retries}" -le 0 ]; then
      ui::error "❌ Temporary PostgreSQL did not become ready."
      docker logs --tail 30 "${_PG_TMP_OLD}" >&2 || true
      return 1
    fi
    sleep 1
  done
}

# Dumps globals and every database into <legacy>/dump. Prints nothing else.
_pg::dump_old_server() {
  local dump_dir="$1" db
  echo "--- Dumping databases with $(basename "${PG_TARGET_IMAGE}") client ---"
  _pg::sh "mkdir -p '/pg/${dump_dir}'" || return 1

  _pg::old_client pg_dumpall --globals-only -l "${DB_NAME}" | _pg::write "${dump_dir}/globals.sql" || return 1

  _pg::old_client psql -d "${DB_NAME}" -At \
    -c "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY 1" \
    | _pg::write "${dump_dir}/databases.txt" || return 1

  for db in $(_pg::read "${dump_dir}/databases.txt"); do
    echo "  • ${db}"
    _pg::old_client pg_dump -Fc -d "${db}" | _pg::write "${dump_dir}/${db}.dump" || return 1
    _pg::row_counts _pg::old_client psql -d "${db}" >> "${PG_COUNTS_OLD_FILE}" || return 1
  done
  sort -o "${PG_COUNTS_OLD_FILE}" "${PG_COUNTS_OLD_FILE}"
  _pg::write "${dump_dir}/row-counts-old.txt" < "${PG_COUNTS_OLD_FILE}"
}

# Restores the dumps into the NEW server (started by compose) and verifies them.
_pg::restore_new_server() {
  local dump_dir="$1" db
  echo "--- Starting $(pg::configured_image) on an empty data directory ---"
  dc up -d postgres || return 1
  db::wait_until_ready || return 1

  echo "--- Restoring roles ---"
  # "role already exists" errors for the default user are expected.
  _pg::read "${dump_dir}/globals.sql" | dc exec -T postgres psql -q -U "${DB_USER}" -d postgres >/dev/null 2>&1 || true

  echo "--- Restoring databases ---"
  for db in $(_pg::read "${dump_dir}/databases.txt"); do
    echo "  • ${db}"
    # --create recreates the database with its original owner, encoding and
    # settings; the empty one created by the image entrypoint is dropped first.
    dc exec -T postgres dropdb -U "${DB_USER}" --if-exists "${db}" || return 1
    _pg::read "${dump_dir}/${db}.dump" \
      | dc exec -T postgres pg_restore -U "${DB_USER}" -d postgres --create --exit-on-error || return 1
  done

  echo "--- Updating planner statistics (ANALYZE) ---"
  dc exec -T postgres vacuumdb -U "${DB_USER}" --all --analyze-in-stages || return 1

  echo "--- Verifying row counts ---"
  local new_counts
  new_counts="$(mktemp)"
  for db in $(_pg::read "${dump_dir}/databases.txt"); do
    _pg::row_counts dc exec -T postgres psql -U "${DB_USER}" -d "${db}" >> "${new_counts}" || { rm -f "${new_counts}"; return 1; }
  done
  sort -o "${new_counts}" "${new_counts}"
  _pg::write "${dump_dir}/row-counts-new.txt" < "${new_counts}"

  if ! diff "${PG_COUNTS_OLD_FILE}" "${new_counts}" >&2; then
    rm -f "${new_counts}"
    ui::error "❌ Row counts differ between the old and the new cluster (see diff above)."
    return 1
  fi
  echo "Row counts match: $(wc -l < "${new_counts}" | tr -d ' ') tables verified."
  rm -f "${new_counts}"
}

# Moves data/ aside and puts the preserved cluster back. Used by the
# automatic rollback (failed upgrade) and by pg::rollback.
_pg::swap_back() {
  local legacy="$1" aside="$2"
  dc rm -f -s postgres >/dev/null 2>&1 || true
  _pg::sh "set -e
    mkdir -p '/pg/${aside}'
    if [ -d /pg/data ]; then mv /pg/data '/pg/${aside}/data'; fi
    mv '/pg/${legacy}/data' /pg/data"
}

_pg::write_readme() {
  local dir="$1" from="$2" to="$3"
  cat <<README | _pg::write "${dir}/README.txt"
PostgreSQL ${from} cluster preserved by ./Docker/docker.sh on $(date)
before migrating to PostgreSQL ${to}.

  data/   the untouched PostgreSQL ${from} data directory (used by rollback)
  dump/   dumps used for the migration and row counts (old vs new)

Rollback:  ./Docker/docker.sh postgres rollback   (or the wizard → 🐘 PostgreSQL)
Removal:   offered by the wizard after LR_PG_LEGACY_RETENTION_SECONDS
           (default ${PG_DEFAULT_RETENTION_SECONDS}s = 30 days)
README
}

# --- Upgrade / rollback / cleanup (public) ---------------------------------------------------------

pg::upgrade() {
  compose::export_service_prefix

  local status
  status="$(pg::status)"
  if [ "${status}" != "upgrade_required" ] && ! { [ "${status}" = "ok" ] && pg::upgrade_available; }; then
    echo "Nothing to upgrade (status: ${status})."
    [ "${status}" = "ok" ] || [ "${status}" = "fresh" ]
    return
  fi

  local from_major to_major old_image ts legacy dump_dir
  from_major="$(pg::data_major)"
  old_image="$(pg::image_for_major "${from_major}")"
  PG_TARGET_IMAGE="${PG_DEFAULT_IMAGE}"
  to_major="$(pg::image_major "${PG_TARGET_IMAGE}")"
  ts="$(date +%Y%m%d-%H%M%S)"
  legacy="pg${from_major}-backup-${ts}"
  dump_dir="${legacy}/dump"
  PG_COUNTS_OLD_FILE="$(mktemp)"

  echo "=== PostgreSQL upgrade ${from_major} → ${to_major} ==="
  echo "Old image: ${old_image}   New image: ${PG_TARGET_IMAGE}"

  _pg::acquire_lock || return 1
  _pg::check_disk_space || return 1
  docker pull -q "${old_image}" >/dev/null && docker pull -q "${PG_TARGET_IMAGE}" >/dev/null || return 1

  # Phase 1 — read-only on the old cluster. A failure here changes nothing.
  _pg::stop_platform
  if ! _pg::start_old_server "${old_image}" || ! _pg::dump_old_server "${dump_dir}"; then
    ui::error "❌ Dump failed. The PostgreSQL ${from_major} data was not modified."
    _pg::sh "rm -rf '/pg/${legacy}'" || true
    return 1
  fi
  docker rm -f "${_PG_TMP_OLD}" >/dev/null 2>&1 || true

  # Phase 2 — switch directories. From here on, failures trigger a rollback.
  _pg::state_save status=in_progress from_major="${from_major}" to_major="${to_major}" \
    old_image="${old_image}" new_image="${PG_TARGET_IMAGE}" legacy_dir="${legacy}" started_at="$(_pg::now)"
  _pg::write_readme "${legacy}" "${from_major}" "${to_major}"
  echo "--- Preserving the PostgreSQL ${from_major} cluster in ${PG_DATA_ROOT}/${legacy}/data ---"
  _pg::sh "mv /pg/data '/pg/${legacy}/data' && mkdir -p /pg/data" || return 1

  config::set LR_POSTGRES_IMAGE ""   # use the default (new) image
  if ! _pg::restore_new_server "${dump_dir}"; then
    ui::error "❌ Migration failed. Restoring PostgreSQL ${from_major}..."
    _pg::swap_back "${legacy}" "${legacy}/failed-pg${to_major}"
    config::set LR_POSTGRES_IMAGE "${old_image}"
    _pg::state_update status=failed failed_at="$(_pg::now)"
    ui::warn "PostgreSQL ${from_major} restored and pinned in Docker/.env (LR_POSTGRES_IMAGE=${old_image})."
    ui::warn "Failed attempt kept in ${PG_DATA_ROOT}/${legacy}/failed-pg${to_major} for analysis."
    return 1
  fi

  _pg::state_update status=done migrated_at="$(_pg::now)"
  rm -f "${PG_COUNTS_OLD_FILE}"
  ui::success "✔ PostgreSQL migrated to ${to_major}."
  echo "  In use:        ${PG_DATA_ROOT}/data"
  echo "  Rollback copy: ${PG_DATA_ROOT}/${legacy}"
  echo "  The wizard will offer to delete the rollback copy after $(pg::format_date "$(pg::legacy_removal_date)")."
}

pg::rollback() {
  compose::export_service_prefix

  local status legacy old_image from_major to_major aside
  status="$(pg::status)"
  legacy="$(_pg::state_get legacy_dir)"
  old_image="$(_pg::state_get old_image)"
  from_major="$(_pg::state_get from_major)"
  to_major="$(_pg::state_get to_major)"

  case "$(_pg::state_get status)" in
    done|in_progress) ;;
    *) echo "No migration to roll back."; return 1 ;;
  esac

  # Interrupted before the directories were switched: the old data is still
  # in place, so only the configuration and the state need to go back.
  if [ "${status}" = "interrupted" ] && [ -z "$(_pg::sh "[ -d '/pg/${legacy}/data' ] && echo yes")" ] \
     && [ "$(pg::data_major)" = "${from_major}" ]; then
    config::set LR_POSTGRES_IMAGE "${old_image}"
    _pg::state_update status=failed failed_at="$(_pg::now)"
    ui::success "✔ PostgreSQL ${from_major} data was never moved. Pinned ${old_image} in Docker/.env."
    return 0
  fi

  if [ -z "$(_pg::sh "[ -d '/pg/${legacy}/data' ] && echo yes")" ]; then
    ui::error "The preserved cluster ${PG_DATA_ROOT}/${legacy}/data no longer exists."
    return 1
  fi

  _pg::acquire_lock || return 1
  aside="pg${to_major}-rolledback-$(date +%Y%m%d-%H%M%S)"
  [ "${status}" = "interrupted" ] && aside="${legacy}/failed-pg${to_major}"

  _pg::stop_platform
  echo "--- Restoring PostgreSQL ${from_major} from ${PG_DATA_ROOT}/${legacy}/data ---"
  _pg::swap_back "${legacy}" "${aside}" || return 1
  config::set LR_POSTGRES_IMAGE "${old_image}"
  _pg::state_update status=rolled_back rolled_back_at="$(_pg::now)" rolled_back_dir="${aside}"

  ui::success "✔ PostgreSQL ${from_major} restored and pinned in Docker/.env (LR_POSTGRES_IMAGE=${old_image})."
  echo "  In use:           ${PG_DATA_ROOT}/data  (PostgreSQL ${from_major})"
  echo "  Set aside (PG ${to_major}): ${PG_DATA_ROOT}/${aside}"
  ui::warn "  Changes made while running PostgreSQL ${to_major} exist only in the set-aside directory."
  echo "  Start the platform again to use it."
}

pg::remove_legacy() {
  local legacy
  legacy="$(pg::legacy_dir)"
  if [ -z "${legacy}" ]; then
    echo "There is no preserved PostgreSQL cluster to remove."
    return 1
  fi
  echo "Removing ${PG_DATA_ROOT}/${legacy} ..."
  _pg::sh "rm -rf '/pg/${legacy}'" || return 1
  _pg::state_update legacy_removed_at="$(_pg::now)" status=done_cleaned
  ui::success "✔ Removed. Rollback to PostgreSQL $(_pg::state_get from_major) is no longer possible."
}

# --- lrshell (Spring Shell) -------------------------------------------------------------
# Uses `exec` when the shell service is already running, otherwise a one-off `run`.

_lrshell::exec() {
  local tty_flag="$1"
  shift
  local flags=(-e SHELL_IDLE=false)
  [ -n "${tty_flag}" ] && flags=("${tty_flag}" "${flags[@]}")

  if compose::is_running shell; then
    dc exec "${flags[@]}" shell "${LRSHELL_ENTRYPOINT}" "$@"
  else
    dc run --rm "${flags[@]}" shell "$@"
  fi
}

lrshell::run()             { _lrshell::exec -T "$@"; }
lrshell::run_interactive() { _lrshell::exec ""  "$@"; }
