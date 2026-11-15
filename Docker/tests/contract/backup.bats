#!/usr/bin/env bats
# backup-db: database dumps only, now, without stopping services.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup() {
  sandbox::create
  DEST="${BATS_TEST_TMPDIR}/backups dir"     # with a space on purpose
}

dump_dir() { find "${DEST}" -mindepth 1 -maxdepth 1 -type d -name 'db_*'; }

@test "backup-db: PostgreSQL + VuFind running → two gzip dumps + RESTORE.txt" {
  export FAKE_RUNNING="postgres vufind-db solr"
  docker_sh backup-db "${DEST}"
  assert_success
  assert_output_contains "Database dump saved to: ${DEST}/db_"

  local dir
  dir="$(dump_dir)"
  [ "$(gzip -cd "${dir}/postgres_lrharvester.sql.gz")" = "-- fake PostgreSQL dump" ]
  [ "$(gzip -cd "${dir}/mysql_vufind.sql.gz")" = "-- fake MySQL dump" ]
  grep -q "psql -U lrharvester -d lrharvester" "${dir}/RESTORE.txt"
  assert_snapshot backup-db
}

@test "backup-db: does not stop or restart any service" {
  export FAKE_RUNNING="postgres vufind-db"
  docker_sh backup-db "${DEST}"
  assert_success
  refute_called " stop "
  refute_called " start "
  refute_called " up "
}

@test "backup-db: VuFind not running → only PostgreSQL, and says so" {
  export FAKE_RUNNING="postgres"
  docker_sh backup-db "${DEST}"
  assert_success
  assert_output_contains "Skipping VuFind database"
  local dir
  dir="$(dump_dir)"
  [ -f "${dir}/postgres_lrharvester.sql.gz" ]
  [ ! -e "${dir}/mysql_vufind.sql.gz" ]
}

@test "backup-db: PostgreSQL not running → fails, nothing created" {
  export FAKE_RUNNING="vufind-db"
  docker_sh backup-db "${DEST}"
  assert_failure
  assert_output_contains "PostgreSQL is not running"
  [ -z "$(dump_dir)" ]
  refute_called "pg_dump"
}

@test "backup-db: pg_dump fails → fails and removes the incomplete folder" {
  export FAKE_RUNNING="postgres vufind-db" FAKE_FAIL="pg_dump"
  docker_sh backup-db "${DEST}"
  assert_failure
  assert_output_contains "PostgreSQL dump failed"
  [ -z "$(dump_dir)" ]
}

@test "backup-db: mariadb-dump fails → fails and removes the incomplete folder" {
  export FAKE_RUNNING="postgres vufind-db" FAKE_FAIL="mariadb-dump"
  docker_sh backup-db "${DEST}"
  assert_failure
  assert_output_contains "VuFind dump failed"
  [ -z "$(dump_dir)" ]
}

@test "backup-db: destination not writable → fails before dumping" {
  export FAKE_RUNNING="postgres"
  mkdir -p "${DEST}" && chmod 500 "${DEST}"
  docker_sh backup-db "${DEST}/sub"
  chmod 700 "${DEST}"
  assert_failure
  assert_output_contains "destination is not writable"
  refute_called "pg_dump"
}

@test "backup-db: does not touch the daily backup plan" {
  export FAKE_RUNNING="postgres"
  docker_sh backup-db "${DEST}"
  assert_success
  [ ! -e "${SANDBOX_ROOT}/.system_backup.sh" ]
}

# --- backup-db --schedule: daily database dumps only -------------------------------------

crontab_file() { echo "${BATS_TEST_TMPDIR}/crontab"; }
db_script() { echo "${SANDBOX_ROOT}/.db_backup.sh"; }

@test "backup-db --schedule: one crontab line running .db_backup.sh daily at 03:xx" {
  docker_sh backup-db --schedule "${DEST}"
  assert_success
  assert_output_contains "Daily database dump scheduled (cron) at 03:"
  assert_output_contains "into: ${DEST}"

  [ -x "$(db_script)" ]
  [ "$(wc -l < "$(crontab_file)")" -eq 1 ]
  grep -Eq '^[0-9]+ 3 \* \* \* cd .* && bash .*/\.db_backup\.sh >> .*\.cron_db_backup\.log 2>&1$' "$(crontab_file)"
  # Only scheduled: nothing dumped now, services untouched.
  refute_called "pg_dump"
  [ -z "$(dump_dir)" ]
}

@test "backup-db --schedule: does not create or schedule the full backup plan" {
  docker_sh backup-db --schedule "${DEST}"
  assert_success
  [ ! -e "${SANDBOX_ROOT}/.system_backup.sh" ]
  ! grep -q "system_backup" "$(crontab_file)"
}

@test "backup-db --schedule twice: replaces its line, keeps the full plan and other jobs" {
  cat > "$(crontab_file)" << CRON
0 1 * * * /usr/bin/other-job
7 3 * * * cd ${SANDBOX_ROOT} && bash .system_backup.sh >> ${SANDBOX_ROOT}/.cron_backup.log 2>&1
CRON
  docker_sh backup-db --schedule "${DEST}"
  assert_success
  docker_sh backup-db --schedule "${DEST}"
  assert_success

  [ "$(grep -c "db_backup.sh" "$(crontab_file)")" -eq 1 ]
  grep -qF "/usr/bin/other-job" "$(crontab_file)"
  grep -qF "bash .system_backup.sh" "$(crontab_file)"
}

@test "backup-db --unschedule: removes only the database line" {
  docker_sh backup-db --schedule "${DEST}"
  echo "7 3 * * * cd ${SANDBOX_ROOT} && bash .system_backup.sh >> x.log 2>&1" >> "$(crontab_file)"
  docker_sh backup-db --unschedule
  assert_success
  assert_output_contains "Daily database dump disabled."
  ! grep -q "db_backup.sh" "$(crontab_file)"
  grep -qF "bash .system_backup.sh" "$(crontab_file)"
}

@test "backup-db --status: disabled, then enabled with time and destination" {
  docker_sh backup-db --status
  assert_success
  assert_output_contains "Daily database dump: disabled"

  docker_sh backup-db --schedule "${DEST}"
  docker_sh backup-db --status
  assert_success
  assert_output_contains "Daily database dump: enabled (cron 03:"
  assert_output_contains "into: ${DEST}"
}

@test "backup-db --schedule: destination not writable → fails, nothing scheduled" {
  mkdir -p "${DEST}" && chmod 500 "${DEST}"
  docker_sh backup-db --schedule "${DEST}/sub"
  chmod 700 "${DEST}"
  assert_failure
  assert_output_contains "destination is not writable"
  [ ! -e "$(db_script)" ]
  [ ! -s "$(crontab_file)" ]
}

@test "backup-db: unknown option → usage" {
  docker_sh backup-db --bogus
  assert_failure
  assert_output_contains "Usage: ./Docker/docker.sh backup-db"
}

@test ".db_backup.sh: dumps the databases and prunes only old db_* folders" {
  docker_sh backup-db --schedule "${DEST}"
  assert_success
  mkdir -p "${DEST}/db_20200101_030000" "${DEST}/20200101_0300" "${DEST}/db_recent"
  touch -t 202001010300 "${DEST}/db_20200101_030000" "${DEST}/20200101_0300"

  export FAKE_RUNNING="postgres vufind-db"
  run _sandbox::run_env bash "$(db_script)"
  assert_success
  assert_output_contains "Database dump saved to: ${DEST}/db_"

  [ ! -e "${DEST}/db_20200101_030000" ]   # old database dump: pruned
  [ -d "${DEST}/20200101_0300" ]          # full-plan snapshot: never touched
  [ -d "${DEST}/db_recent" ]
  [ -n "$(find "${DEST}" -name postgres_lrharvester.sql.gz)" ]
  refute_called " stop "
}

@test ".db_backup.sh: failed dump → fails and keeps the old dumps" {
  docker_sh backup-db --schedule "${DEST}"
  mkdir -p "${DEST}/db_20200101_030000"
  touch -t 202001010300 "${DEST}/db_20200101_030000"

  export FAKE_RUNNING="postgres" FAKE_FAIL="pg_dump"
  run _sandbox::run_env bash "$(db_script)"
  assert_failure
  [ -d "${DEST}/db_20200101_030000" ]
}

# --- wizard: 💾 System Backup → 🗓️ Daily database dumps only ----------------------------

@test "wizard daily database dumps: shows the option and the current status" {
  wizard "💾" "🗓" no
  grep -qF "choose: 🗓️  Daily database dumps only" "${GUM_LOG}"
  grep -qF "confirm: Enable the daily database dump? → no" "${GUM_LOG}"
  assert_output_contains "Current status: disabled"
  assert_output_contains "Daily database dump is disabled."
}

@test "wizard daily database dumps: answering no disables only the database schedule" {
  docker_sh backup-db --schedule "${DEST}"
  echo "7 3 * * * cd ${SANDBOX_ROOT} && bash .system_backup.sh >> x.log 2>&1" >> "$(crontab_file)"

  wizard "💾" "🗓" no
  assert_output_contains "Current status: enabled (cron, daily at 03:"
  ! grep -q "db_backup.sh" "$(crontab_file)"
  grep -qF "bash .system_backup.sh" "$(crontab_file)"
}
