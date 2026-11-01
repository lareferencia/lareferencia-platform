#!/usr/bin/env bats
# PostgreSQL major version guard: never start postgres 17 on PostgreSQL 14 data.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

@test "fresh install: up is allowed" {
  docker_sh up
  assert_success
  assert_called "up -d"
}

@test "PG14 data + PG17 image: up is blocked and explains the options" {
  with_pg_data 14
  docker_sh up
  assert_failure
  assert_output_contains "postgres upgrade"
  assert_output_contains "LR_POSTGRES_IMAGE=postgres:14.15-alpine"
  refute_called "up -d"
}

@test "PG14 data: start of every module is blocked" {
  with_pg_data 14
  docker_sh start
  assert_failure
  refute_called " start"
}

@test "PG14 data: start of services without postgres keeps working (nightly backup)" {
  with_pg_data 14
  docker_sh start solr
  assert_success
  assert_called "start solr"
}

@test "PG14 data pinned with LR_POSTGRES_IMAGE: up is allowed" {
  with_pg_data 14
  docker_sh modules status         # creates .env
  echo "LR_POSTGRES_IMAGE=postgres:14.15-alpine" >> "${SANDBOX_ROOT}/Docker/.env"
  docker_sh up
  assert_success
  assert_called "up -d"
}

@test "PG17 data: up is allowed" {
  with_pg_data 17
  docker_sh up
  assert_success
}

@test "postgres upgrade without --yes: wrong confirmation aborts before touching anything" {
  with_pg_data 14
  docker_sh_input "no" postgres upgrade
  assert_failure
  refute_called "docker run"
  refute_called "docker pull"
}
