#!/usr/bin/env bash
# =============================================================================
# backup.sh — "Backup": full-state backup of the platform.
#
# Generates <repo>/.system_backup.sh (git sources, configs, volumes, database
# dumps + an autonomous restore.sh copied from Docker/lib/templates/restore.sh)
# and schedules it daily at 03:xx via crontab or a systemd user timer.
# A second, independent plan schedules only the database dumps (.db_backup.sh).
#
# Public API:
#   backup::missing_requirements       prints one line per missing requirement
#   backup::default_destination
#   backup::prepare_destination <dir>  creates it; fails when not writable
#   backup::write_script <dir>
#   backup::schedule_daily             prints "<method> 03:<MM>" (cron|systemd)
#   backup::unschedule
#   backup::run                        runs .system_backup.sh now
#   backup::dump_databases <dir>       database dumps only (now, services keep
#                                      running) into <dir>/db_<date>/
#   backup::latest_db_dump <dir>       newest db_<date> folder in <dir>
#
#   Scheduled database dumps only (independent of the full plan):
#   backup::db_schedule_missing_requirements
#   backup::write_db_script <dir>      writes .db_backup.sh
#   backup::schedule_db_daily          prints "<method> 03:<MM>" (cron|systemd)
#   backup::unschedule_db
#   backup::db_schedule_status         prints "<method> 03:<MM>" or nothing
#   backup::db_schedule_destination    destination saved in .db_backup.sh
# =============================================================================

BACKUP_SCRIPT="${ROOT_DIR}/.system_backup.sh"
BACKUP_LOG="${ROOT_DIR}/.cron_backup.log"
BACKUP_SYSTEMD_DIR="${HOME}/.config/systemd/user"

backup::missing_requirements() {
  local cmd
  for cmd in tar docker; do
    cmd::exists "${cmd}" || echo "'${cmd}' is required but not installed."
  done
  if ! cmd::exists crontab && ! cmd::exists systemctl; then
    echo "Either 'crontab' or 'systemctl' is required for scheduling backups."
  fi
  system::compose_available || echo "'docker compose' or 'docker-compose' is required but not installed."
  return 0
}

backup::default_destination() {
  echo "/var/backups/$(basename "${ROOT_DIR}")"
}

backup::prepare_destination() {
  mkdir -p "$1" 2>/dev/null && [ -w "$1" ]
}

# Writes .system_backup.sh. The content below is a template: `\$` escapes
# survive into the generated script, unescaped variables are expanded now.
# The restore.sh shipped with each snapshot is copied at backup time from
# Docker/lib/templates/restore.sh (edit that file to change it).
backup::write_script() {
  local dest_dir="$1"
  cat << EOF > "${BACKUP_SCRIPT}"
#!/usr/bin/env bash
# Auto-generated full-state backup script for LA Referencia
set -e

PROJECT_DIR="${ROOT_DIR}"
DEST_DIR="${dest_dir}"
DATE=\$(date +"%Y%m%d_%H%M")
BACKUP_PATH="\$DEST_DIR/\$DATE"
SNAPSHOT_NAME="lareferencia_snapshot_\$DATE.tar.gz"
RESTORE_TEMPLATE="\$PROJECT_DIR/Docker/lib/templates/restore.sh"

mkdir -p "\$BACKUP_PATH"
cd "\$PROJECT_DIR"

cleanup() {
  echo "Ensuring services are resumed..."
  ./Docker/docker.sh start solr elasticsearch vufind-web 2>/dev/null || true
}
trap cleanup EXIT

echo "1. Generating autonomous restore script..."
if [ ! -f "\$RESTORE_TEMPLATE" ]; then
  echo "Error: restore template not found: \$RESTORE_TEMPLATE" >&2
  exit 1
fi
cp "\$RESTORE_TEMPLATE" "\$BACKUP_PATH/restore.sh"
chmod +x "\$BACKUP_PATH/restore.sh"

echo "2. Exporting Database Dumps..."
./Docker/docker.sh dc exec -T postgres pg_dump --clean --if-exists -U lrharvester lrharvester > "\$BACKUP_PATH/postgres_dump.sql" 2>/dev/null || true
./Docker/docker.sh dc exec -T vufind-db mariadb-dump -u vufind -pvufind vufind > "\$BACKUP_PATH/mysql_vufind_dump.sql" 2>/dev/null || true

echo "3. Pausing indexers safely..."
./Docker/docker.sh stop solr elasticsearch vufind-web 2>/dev/null || true

echo "4. Packaging absolute snapshot (Git, Configs, Volumes)..."
if command -v docker >/dev/null 2>&1; then
  docker run --rm -v "\$PROJECT_DIR/Docker/volume:/volume" -v "\$PROJECT_DIR/Docker/data:/data" alpine sh -c "find /volume /data \\( -path '*/postgres' -o -path '*/vufind/data/db' -o -path '*/vufind-db' \\) -prune -o -exec chmod ugo+rX {} + 2>/dev/null || true" 2>/dev/null || true
fi
tar_code=0
tar -czf "\$BACKUP_PATH/\$SNAPSHOT_NAME" \\
    --exclude="*/target" \\
    --exclude="./Docker/volume/lareferencia/postgres" \\
    --exclude="./Docker/volume/vufind/data/db" \\
    --exclude="./Docker/volume/vufind-db" \\
    --exclude="./Docker/volume/dev/*/lareferencia/postgres" \\
    --exclude="./Docker/volume/dev/*/vufind/data/db" \\
    --exclude="./.idea" \\
    -C "\$PROJECT_DIR" . \\
    -C "\$BACKUP_PATH" postgres_dump.sql mysql_vufind_dump.sql || tar_code=\$?

if [ "\$tar_code" -ne 0 ] && [ "\$tar_code" -ne 1 ]; then
  echo "Error: tar failed with exit code \$tar_code" >&2
  exit "\$tar_code"
fi

rm -f "\$BACKUP_PATH/postgres_dump.sql" "\$BACKUP_PATH/mysql_vufind_dump.sql"

echo "5. Restarting services..."
./Docker/docker.sh start solr elasticsearch vufind-web 2>/dev/null || true

echo "Cleaning old backups (keeping 7 days)..."
find "\$DEST_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \\;
EOF
  chmod +x "${BACKUP_SCRIPT}"
}

# --- Scheduling (shared by the full plan and the database-only plan) -------------------
#
# Each plan is one generated script run daily at 03:<random minute>:
#   cron     one crontab line, identified by the script path
#   systemd  <unit>.service + <unit>.timer (user units), when crontab is missing

# The crontab line holds the script path as `printf %q` writes it: that
# spelling identifies the plan's line (and only this installation's).
_backup::cron_marker() {
  printf 'bash %q ' "$1"
}

# Line written by older versions of the full plan (relative script name).
_backup::cron_legacy_marker() {
  echo "cd ${ROOT_DIR} && bash .system_backup.sh"
}

# _backup::cron_without <script>   current crontab minus the plan's lines
_backup::cron_without() {
  local patterns=(-e "$(_backup::cron_marker "$1")")
  [ "$1" = "${BACKUP_SCRIPT}" ] && patterns+=(-e "$(_backup::cron_legacy_marker)")
  crontab -l 2>/dev/null | grep -F -v "${patterns[@]}" || true
}

# _backup::cron_install <minute> <script> <log>   replaces the plan's line
_backup::cron_install() {
  local minute="$1" script="$2" log="$3" job
  job="${minute} 3 * * * cd $(printf '%q' "${ROOT_DIR}") && $(_backup::cron_marker "${script}")>> $(printf '%q' "${log}") 2>&1"
  (_backup::cron_without "${script}"; echo "${job}") | crontab -
}

# _backup::cron_remove <script>
_backup::cron_remove() {
  _backup::cron_without "$1" | crontab -
}

# _backup::systemd_install <unit> <description> <minute> <script> <log>
_backup::systemd_install() {
  local unit="$1" description="$2" minute="$3" script="$4" log="$5"
  mkdir -p "${BACKUP_SYSTEMD_DIR}"
  cat << SYSTEMD_SVC > "${BACKUP_SYSTEMD_DIR}/${unit}.service"
[Unit]
Description=${description}

[Service]
Type=oneshot
ExecStart=/bin/bash "${script}"
WorkingDirectory=${ROOT_DIR}
StandardOutput=append:${log}
StandardError=append:${log}
SYSTEMD_SVC

  cat << SYSTEMD_TMR > "${BACKUP_SYSTEMD_DIR}/${unit}.timer"
[Unit]
Description=Runs ${description} Daily

[Timer]
OnCalendar=*-*-* 03:${minute}:00
Persistent=true

[Install]
WantedBy=timers.target
SYSTEMD_TMR

  systemctl --user daemon-reload
  systemctl --user enable --now "${unit}.timer"
  loginctl enable-linger "$(whoami)" 2>/dev/null || true
}

# _backup::systemd_remove <unit>
_backup::systemd_remove() {
  local unit="$1"
  systemctl --user disable --now "${unit}.timer" 2>/dev/null || true
  rm -f "${BACKUP_SYSTEMD_DIR}/${unit}.service" "${BACKUP_SYSTEMD_DIR}/${unit}.timer"
  systemctl --user daemon-reload 2>/dev/null || true
}

# _backup::schedule <unit> <description> <script> <log>
# Schedules the daily run at a random minute after 03:00; prints "<method> 03:<MM>".
_backup::schedule() {
  local unit="$1" description="$2" script="$3" log="$4" minute
  minute="$(printf '%02d' $((RANDOM % 60)))"
  if cmd::exists crontab; then
    _backup::cron_install "${minute}" "${script}" "${log}"
    echo "cron 03:${minute}"
  elif cmd::exists systemctl; then
    _backup::systemd_install "${unit}" "${description}" "${minute}" "${script}" "${log}"
    echo "systemd 03:${minute}"
  else
    return 1
  fi
}

# _backup::unschedule <unit> <script>
_backup::unschedule() {
  if cmd::exists crontab; then
    _backup::cron_remove "$2"
  fi
  if cmd::exists systemctl; then
    _backup::systemd_remove "$1"
  fi
  return 0
}

# _backup::schedule_status <unit> <script>   prints "<method> 03:<MM>" or nothing
_backup::schedule_status() {
  local unit="$1" script="$2" line minute
  if cmd::exists crontab; then
    line="$(crontab -l 2>/dev/null | grep -F -- "$(_backup::cron_marker "${script}")" | head -n 1 || true)"
    if [ -n "${line}" ]; then
      minute="$(printf '%02d' "$((10#$(awk '{print $1}' <<< "${line}")))")"
      echo "cron 03:${minute}"
      return 0
    fi
  fi
  if [ -f "${BACKUP_SYSTEMD_DIR}/${unit}.timer" ]; then
    line="$(grep -E '^OnCalendar=' "${BACKUP_SYSTEMD_DIR}/${unit}.timer" | head -n 1)"
    echo "systemd $(sed -E 's/.* ([0-9]{2}:[0-9]{2}):[0-9]{2}$/\1/' <<< "${line}")"
  fi
  return 0
}

# Full plan: .system_backup.sh daily.
backup::schedule_daily() {
  _backup::schedule lareferencia-backup "LA Referencia Backup" "${BACKUP_SCRIPT}" "${BACKUP_LOG}"
}

backup::unschedule() {
  _backup::unschedule lareferencia-backup "${BACKUP_SCRIPT}"
}

backup::run() {
  bash "${BACKUP_SCRIPT}"
}

# --- Database dumps only --------------------------------------------------------------
#
#   <dir>/db_<YYYYmmdd_HHMMSS>/
#     postgres_lrharvester.sql.gz    harvester database (required)
#     mysql_vufind.sql.gz            VuFind database (when vufind-db is running)
#     RESTORE.txt                    how to restore each file
#
# Unlike the full backup, any failed dump fails the whole operation and the
# incomplete folder is removed (an empty dump must never look like a backup).

BACKUP_DB_PREFIX="db_"

# _backup::dump_to <file.gz> <command...>   runs the command, gzips its stdout
_backup::dump_to() {
  local file="$1"
  shift
  "$@" | gzip > "${file}" || return 1
  # gzip of nothing is still a valid (tiny) file: require real content.
  [ -n "$(gzip -cd "${file}" 2>/dev/null | head -c 1)" ] || { echo "Error: empty dump: ${file}" >&2; return 1; }
}

_backup::write_db_restore_notes() {
  cat > "$1/RESTORE.txt" << NOTES
LA Referencia — database dump of $(date "+%Y-%m-%d %H:%M")
Run from the project directory ($(basename "${ROOT_DIR}")) with the containers running.

PostgreSQL (harvester) — replaces the current database objects:
  gunzip -c postgres_lrharvester.sql.gz | ./Docker/docker.sh dc exec -T postgres psql -U ${DB_USER} -d ${DB_NAME}

VuFind (MySQL), if mysql_vufind.sql.gz is present:
  gunzip -c mysql_vufind.sql.gz | ./Docker/docker.sh dc exec -T vufind-db mariadb -u vufind -pvufind vufind
NOTES
}

_backup::dump_harvester() {
  local dir="$1"
  echo "Dumping PostgreSQL database '${DB_NAME}'..."
  if ! _backup::dump_to "${dir}/postgres_lrharvester.sql.gz" \
      dc exec -T postgres pg_dump --clean --if-exists -U "${DB_USER}" "${DB_NAME}"; then
    echo "Error: PostgreSQL dump failed (nothing was kept)." >&2
    return 1
  fi
}

_backup::dump_vufind() {
  local dir="$1" running="$2"
  if printf '%s\n' "${running}" | grep -Fxq vufind-db; then
    echo "Dumping VuFind database (MySQL)..."
    if ! _backup::dump_to "${dir}/mysql_vufind.sql.gz" \
        dc exec -T vufind-db mariadb-dump --single-transaction -u vufind -pvufind vufind; then
      echo "Error: VuFind dump failed (nothing was kept)." >&2
      return 1
    fi
  else
    echo "Skipping VuFind database (vufind-db is not running)."
  fi
}

backup::dump_databases() {
  local root="$1" dir running
  if ! backup::prepare_destination "${root}"; then
    echo "Error: destination is not writable: ${root}" >&2
    return 1
  fi

  running="$(compose::running_services)"
  if ! printf '%s\n' "${running}" | grep -Fxq postgres; then
    echo "Error: PostgreSQL is not running. Start the platform first." >&2
    return 1
  fi

  dir="${root}/${BACKUP_DB_PREFIX}$(date +%Y%m%d_%H%M%S)"
  mkdir -p "${dir}"

  _backup::dump_harvester "${dir}" || { rm -rf "${dir}"; return 1; }
  _backup::dump_vufind "${dir}" "${running}" || { rm -rf "${dir}"; return 1; }

  _backup::write_db_restore_notes "${dir}"
  echo "Database dump saved to: ${dir}"
}

backup::latest_db_dump() {
  find -H "$1" -mindepth 1 -maxdepth 1 -type d -name "${BACKUP_DB_PREFIX}*" 2>/dev/null | sort | tail -n 1
}

# --- Scheduled database dumps only ---------------------------------------------------------
#
# Independent of the full plan: its own script, log, cron line and systemd
# units, so either plan can be enabled or disabled without touching the other.
# Each run = `docker.sh backup-db <dir>` (services keep running), then removes
# db_<date> folders older than BACKUP_DB_KEEP_DAYS (only those, never other
# folders of the destination). Old dumps are only pruned after a good dump.

BACKUP_DB_SCRIPT="${ROOT_DIR}/.db_backup.sh"
BACKUP_DB_LOG="${ROOT_DIR}/.cron_db_backup.log"
BACKUP_DB_KEEP_DAYS=7

# One unit per installation: several checkouts on the same host must not
# overwrite each other's timer.
_backup::db_unit() {
  echo "lareferencia-db-backup-$(hash::short "${ROOT_DIR}")"
}

# Prints one line per missing requirement of the scheduled dump.
backup::db_schedule_missing_requirements() {
  cmd::exists docker || echo "'docker' is required but not installed."
  cmd::exists gzip || echo "'gzip' is required but not installed."
  if ! cmd::exists crontab && ! cmd::exists systemctl; then
    echo "Either 'crontab' or 'systemctl' is required for scheduling backups."
  fi
  system::compose_available || echo "'docker compose' or 'docker-compose' is required but not installed."
  return 0
}

# backup::write_db_script <dir>   writes .db_backup.sh (values quoted with %q)
backup::write_db_script() {
  local dest_dir="$1"
  {
    echo '#!/usr/bin/env bash'
    echo '# Auto-generated database-only backup script for LA Referencia'
    echo '# (PostgreSQL + VuFind MySQL dumps; services keep running).'
    echo 'set -euo pipefail'
    echo
    echo '# cron runs with a minimal PATH: make docker reachable.'
    echo 'export PATH="${PATH:-/usr/bin:/bin}:/usr/local/bin:/opt/homebrew/bin"'
    printf 'PROJECT_DIR=%q\n' "${ROOT_DIR}"
    printf 'DEST_DIR=%q\n' "${dest_dir}"
    printf 'KEEP_DAYS=%q\n' "${BACKUP_DB_KEEP_DAYS}"
    cat << 'EOF'

echo "=== Database dump: $(date '+%Y-%m-%d %H:%M:%S') ==="
cd "${PROJECT_DIR}"
./Docker/docker.sh backup-db "${DEST_DIR}"

echo "Cleaning old database dumps (keeping ${KEEP_DAYS} days)..."
find "${DEST_DIR}" -mindepth 1 -maxdepth 1 -type d -name 'db_*' -mtime +"${KEEP_DAYS}" -exec rm -rf {} +
EOF
  } > "${BACKUP_DB_SCRIPT}"
  chmod +x "${BACKUP_DB_SCRIPT}"
}

# Prints "<method> 03:<MM>".
backup::schedule_db_daily() {
  _backup::schedule "$(_backup::db_unit)" "LA Referencia Database Backup" "${BACKUP_DB_SCRIPT}" "${BACKUP_DB_LOG}"
}

backup::unschedule_db() {
  _backup::unschedule "$(_backup::db_unit)" "${BACKUP_DB_SCRIPT}"
}

# Prints "<method> 03:<MM>" when the database-only plan is scheduled, else nothing.
backup::db_schedule_status() {
  _backup::schedule_status "$(_backup::db_unit)" "${BACKUP_DB_SCRIPT}"
}

# Destination configured in .db_backup.sh (empty when never configured).
backup::db_schedule_destination() {
  [ -f "${BACKUP_DB_SCRIPT}" ] || return 0
  (
    eval "$(grep -E '^DEST_DIR=' "${BACKUP_DB_SCRIPT}" | head -n 1)"
    printf '%s\n' "${DEST_DIR:-}"
  )
}

