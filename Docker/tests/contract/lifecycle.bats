#!/usr/bin/env bats
# up / down / start / stop / restart: which services and compose profiles are used.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

@test "up: images already built → only 'compose up' of the enabled modules" {
  docker_sh up
  assert_success
  refute_called "compose build"
  refute_called "mvn clean package"
  assert_snapshot up
}

@test "up: missing images on first run → pull modules, build everything, init db, up --build" {
  export FAKE_IMAGES=none
  docker_sh up
  assert_success
  assert_output_contains "First-time run or missing Docker images detected"
  assert_called "githelper pull"
  assert_called "mvn clean package"
  assert_called "up -d --remove-orphans --force-recreate --build"
  assert_snapshot up-first-run
}

@test "up --build --no-cache: rebuilds without cache and keeps the modules as they are" {
  docker_sh up --build --no-cache
  assert_success
  refute_called "githelper pull"
  assert_called "build --no-cache"
  assert_snapshot up-build-no-cache
}

@test "up <service>: only the requested service" {
  docker_sh up solr
  assert_success
  assert_called "up -d --remove-orphans solr"
  refute_called "harvester"
}

@test "up --prefix/--offset: saved in .env and used for the project name and ports" {
  docker_sh up --prefix=mylr --offset=100
  assert_success
  [ "$(env_get SERVICE_PREFIX)" = "mylr" ]
  [ "$(env_get SERVICES_PORT_OFFSET)" = "100" ]
  [ "$(env_get COMPOSE_PROJECT_NAME)" = "mylr" ]
}

@test "down: every module profile, so disabled modules are removed too" {
  docker_sh down
  assert_success
  assert_snapshot down
}

@test "down v: also removes named volumes" {
  docker_sh down v
  assert_success
  assert_called "down --remove-orphans --volumes"
}

@test "start / stop / restart: enabled modules by default" {
  local action
  for action in start stop restart; do
    : > "${FAKE_LOG}"
    docker_sh "${action}"
    assert_success
    assert_snapshot "${action}"
  done
}

@test "start <services>: only those services" {
  docker_sh start solr harvester
  assert_success
  assert_called "start solr harvester"
}

@test "unknown command: prints the help and fails" {
  docker_sh no-such-command
  assert_failure
  assert_output_contains "Usage"
  [ ! -s "${FAKE_LOG}" ]
}

# The image tag is <profile>-<checkout hash>-<commit>. After a `git pull` the
# commit changes, and `up` must look for images of the NEW commit (the tag
# saved in .env by the previous run is stale).
current_image_tag() {
  local hash commit
  hash="$(printf "%s" "${SANDBOX_ROOT}" | shasum -a 256 | cut -c1-7)"
  commit="$("${REAL_GIT}" -C "${SANDBOX_ROOT}" rev-parse --short=7 HEAD)"
  echo "lareferencia-${hash}-${commit}"
}

@test "up after a new commit: images of the previous commit are not enough → build" {
  docker_sh modules status                                  # creates .env
  echo "LR_IMAGE_TAG=lareferencia-0000000-oldcomm" >> "${SANDBOX_ROOT}/Docker/.env"
  export FAKE_IMAGES="oldcomm"                              # only old images exist
  : > "${FAKE_LOG}"
  docker_sh up
  assert_success
  assert_output_contains "missing Docker images detected"
  assert_called "image inspect lareferencia/solr:lareferencia-<HASH>-<COMMIT>"
  [ "$(env_get LR_IMAGE_TAG)" = "$(current_image_tag)" ]
}

@test "up: images of the current commit exist → no build" {
  export FAKE_IMAGES="$(current_image_tag)"
  docker_sh up
  assert_success
  refute_called "mvn clean package"
  assert_called "image inspect lareferencia/solr:lareferencia-<HASH>-<COMMIT>"
}
