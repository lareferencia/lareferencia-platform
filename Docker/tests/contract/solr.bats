#!/usr/bin/env bats
# solr: core staging before Solr starts, update-config and verify (docker.sh and docker-dev.sh).

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

# --- docker.sh ---------------------------------------------------------------------

@test "up: cores not staged → staged from the modules before Solr starts" {
  docker_sh up --prefix=x            # creates .env (images exist: no build)
  : > "${FAKE_LOG}"
  unstage_solr
  docker_sh up
  assert_success
  assert_output_contains "Solr cores are not staged yet"
  local stage up
  stage="$(call_line "stage-cores.sh")"
  up="$(call_line " up -d --remove-orphans")"
  [ "${stage}" -gt 0 ] && [ "${up}" -gt "${stage}" ]
}

@test "up: cores already staged → no restaging without a build" {
  docker_sh up
  assert_success
  refute_called "stage-cores.sh"
}

@test "start: cores not staged → staged before starting" {
  docker_sh up --prefix=x
  : > "${FAKE_LOG}"
  unstage_solr
  docker_sh start
  assert_success
  assert_called "stage-cores.sh"
}

@test "start postgres only: Solr is not involved → no staging" {
  unstage_solr
  docker_sh start postgres
  assert_success
  refute_called "stage-cores.sh"
}

@test "solr stage: runs the staging script only" {
  docker_sh solr stage
  assert_success
  assert_called "Docker/solr/stage-cores.sh"
  refute_called "compose -f"
}

@test "solr update-config with Solr running: stage, then apply inside the container" {
  export FAKE_RUNNING="solr"
  docker_sh solr update-config
  assert_success
  local stage apply
  stage="$(call_line "stage-cores.sh")"
  apply="$(call_line "exec -T solr /usr/local/bin/lr-solr-entrypoint.sh update-config")"
  [ "${stage}" -gt 0 ] && [ "${apply}" -gt "${stage}" ]
  refute_called "run --rm --no-deps -T solr"
}

@test "solr update-config with Solr stopped: applied by a one-off container" {
  docker_sh solr update-config
  assert_success
  assert_called "run --rm --no-deps -T solr update-config"
  refute_called "exec -T solr"
}

@test "solr update-config: a staging failure stops before touching Solr" {
  export FAKE_FAIL="stage-cores.sh"
  docker_sh solr update-config
  assert_failure
  refute_called "update-config"
}

@test "solr verify: checks the staging against the modules and Solr against the staging" {
  export FAKE_RUNNING="solr"
  docker_sh solr verify
  assert_success
  assert_called "Docker/solr/stage-cores.sh --check"
  assert_called "exec -T solr /usr/local/bin/lr-solr-entrypoint.sh verify-config"
}

@test "solr verify: a difference makes it fail" {
  export FAKE_FAIL="stage-cores.sh --check"
  docker_sh solr verify
  assert_failure
}

@test "solr migrate with Solr running: stop, rebuild with a one-off container, start again" {
  export FAKE_RUNNING="solr"
  docker_sh solr migrate
  assert_success
  local stage stop run start
  stage="$(call_line "stage-cores.sh")"
  stop="$(call_line " stop solr")"
  run="$(call_line "run --rm --no-deps -T solr migrate")"
  start="$(call_line " start solr")"
  [ "${stage}" -gt 0 ] && [ "${stop}" -gt "${stage}" ] && [ "${run}" -gt "${stop}" ] && [ "${start}" -gt "${run}" ]
}

@test "solr migrate with Solr stopped: rebuild only, Solr left stopped" {
  docker_sh solr migrate
  assert_success
  assert_called "run --rm --no-deps -T solr migrate"
  refute_called " stop solr"
  refute_called " start solr"
}

@test "solr migrate: a failed rebuild is reported and Solr is started again" {
  export FAKE_RUNNING="solr" FAKE_FAIL="solr migrate"
  docker_sh solr migrate
  assert_failure
  assert_called " start solr"
}

@test "solr <unknown>: usage and failure" {
  docker_sh solr nope
  assert_failure
  assert_output_contains "solr [update-config|stage|verify|migrate|status]"
}

# --- docker-dev.sh ----------------------------------------------------------------

@test "dev up: Solr is restaged before the containers start" {
  dev_sh up
  assert_success
  local stage up
  stage="$(call_line "stage-cores.sh")"
  up="$(call_line " up -d --build")"
  [ "${stage}" -gt 0 ] && [ "${up}" -gt "${stage}" ]
}

@test "dev up solr: explicit solr is always restaged" {
  dev_sh up solr
  assert_success
  assert_called "stage-cores.sh"
}

@test "dev up postgres with cores staged: no restaging" {
  dev_sh up postgres
  assert_success
  refute_called "stage-cores.sh"
}

@test "dev up of a service without staged cores: staged first (compose may start solr)" {
  unstage_solr
  dev_sh up postgres
  assert_success
  assert_called "stage-cores.sh"
}

@test "dev up: a staging failure stops before any container starts" {
  export FAKE_FAIL="stage-cores.sh"
  dev_sh up
  assert_failure
  refute_called " up -d"
}

@test "dev solr update-config with Solr stopped: one-off container" {
  dev_sh solr update-config
  assert_success
  assert_called "stage-cores.sh"
  assert_called "run --rm --no-deps -T solr update-config"
}

@test "dev reload solr with Solr running: applied inside the container" {
  export FAKE_RUNNING="solr"
  dev_sh reload solr
  assert_success
  assert_called "exec -T solr /usr/local/bin/lr-solr-entrypoint.sh update-config"
}

@test "dev solr verify: staging check + installed check" {
  dev_sh solr verify
  assert_success
  assert_called "stage-cores.sh --check"
  assert_called "run --rm --no-deps -T solr verify-config"
}

@test "dev solr migrate with Solr running: stop, rebuild, start" {
  export FAKE_RUNNING="solr"
  dev_sh solr migrate
  assert_success
  assert_called " stop solr"
  assert_called "run --rm --no-deps -T solr migrate"
  assert_called " start solr"
}
