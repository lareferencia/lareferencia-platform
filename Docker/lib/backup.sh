#!/usr/bin/env bash
# =============================================================================
# backup.sh — "Backup": full-state backup of the platform.
#
# Generates <repo>/.system_backup.sh (git sources, configs, volumes, database
# dumps + an autonomous restore.sh copied from Docker/lib/templates/restore.sh)
# and schedules it daily at 03:xx via crontab or a systemd user timer.
#
# Public API:
#   backup::missing_requirements       prints one line per missing requirement
#   backup::default_destination
#   backup::prepare_destination <dir>  creates it; fails when not writable
#   backup::write_script <dir>
#   backup::schedule_daily             prints "<method> 03:<MM>" (cron|systemd)
#   backup::unschedule
#   backup::run                        runs .system_backup.sh now
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
./Docker/docker.sh dc exec -T vufind-db mysqldump -u vufind -pvufind vufind > "\$BACKUP_PATH/mysql_vufind_dump.sql" 2>/dev/null || true

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

_backup::schedule_with_cron() {
  local minute="$1"
  local job="${minute} 3 * * * cd ${ROOT_DIR} && bash .system_backup.sh >> ${BACKUP_LOG} 2>&1"
  (crontab -l 2>/dev/null | grep -F -v ".system_backup.sh" || true; echo "${job}") | crontab -
}

_backup::schedule_with_systemd() {
  local minute="$1"
  mkdir -p "${BACKUP_SYSTEMD_DIR}"
  cat << SYSTEMD_SVC > "${BACKUP_SYSTEMD_DIR}/lareferencia-backup.service"
[Unit]
Description=LA Referencia Backup Service

[Service]
Type=oneshot
ExecStart=/bin/bash ${BACKUP_SCRIPT}
WorkingDirectory=${ROOT_DIR}
StandardOutput=append:${BACKUP_LOG}
StandardError=append:${BACKUP_LOG}
SYSTEMD_SVC

  cat << SYSTEMD_TMR > "${BACKUP_SYSTEMD_DIR}/lareferencia-backup.timer"
[Unit]
Description=Runs LA Referencia Backup Daily

[Timer]
OnCalendar=*-*-* 03:${minute}:00
Persistent=true

[Install]
WantedBy=timers.target
SYSTEMD_TMR

  systemctl --user daemon-reload
  systemctl --user enable --now lareferencia-backup.timer
  loginctl enable-linger "$(whoami)" 2>/dev/null || true
}

# Schedules the daily run at a random minute after 03:00.
backup::schedule_daily() {
  local minute=$((RANDOM % 60))
  if cmd::exists crontab; then
    _backup::schedule_with_cron "${minute}"
    echo "cron 03:${minute}"
  elif cmd::exists systemctl; then
    _backup::schedule_with_systemd "${minute}"
    echo "systemd 03:${minute}"
  else
    return 1
  fi
}

backup::unschedule() {
  if cmd::exists crontab; then
    (crontab -l 2>/dev/null | grep -F -v ".system_backup.sh" || true) | crontab -
  fi
  if cmd::exists systemctl; then
    systemctl --user disable --now lareferencia-backup.timer 2>/dev/null || true
    rm -f "${BACKUP_SYSTEMD_DIR}/lareferencia-backup.service" "${BACKUP_SYSTEMD_DIR}/lareferencia-backup.timer"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  return 0
}

backup::run() {
  bash "${BACKUP_SCRIPT}"
}
