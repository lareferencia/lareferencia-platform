#!/usr/bin/env bats
# Settings changed from the CLI end up in Docker/.env.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

@test "first run creates Docker/.env from .env.example" {
  [ ! -f "${SANDBOX_ROOT}/Docker/.env" ]
  docker_sh modules status
  assert_success
  [ -f "${SANDBOX_ROOT}/Docker/.env" ]
}

@test "modules on/off: changes the module state in .env" {
  docker_sh modules on elastic
  assert_success
  [ "$(env_get DEV_MODULE_ELASTIC)" = "on" ]

  docker_sh modules off elastic
  assert_success
  [ "$(env_get DEV_MODULE_ELASTIC)" = "off" ]
}

@test "modules on: an enabled module joins the next 'up'" {
  docker_sh modules on elastic
  docker_sh up
  assert_success
  assert_called "elasticsearch"
}

@test "modules on <unknown>: fails" {
  docker_sh modules on nope
  assert_failure
}

@test "modules status: lists every module and its services" {
  export FAKE_RUNNING="solr"
  docker_sh modules status
  assert_success
  local m
  for m in core solr harvester entity-rest shell vufind elastic watch oai; do
    assert_output_contains "${m}"
  done
  assert_output_contains "running"
}

@test "res <profile>: applies the resource profile" {
  docker_sh res low
  assert_success
  local key
  key="$(grep -m1 -oE '^[A-Z_]+' "${SANDBOX_ROOT}/Docker/profiles/low.env")"
  [ "$(env_get "${key}")" = "$(grep -m1 "^${key}=" "${SANDBOX_ROOT}/Docker/profiles/low.env" | cut -d= -f2-)" ]
}
