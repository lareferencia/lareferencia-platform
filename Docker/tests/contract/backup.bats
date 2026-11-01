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

@test "backup-db: mysqldump fails → fails and removes the incomplete folder" {
  export FAKE_RUNNING="postgres vufind-db" FAKE_FAIL="mysqldump"
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
