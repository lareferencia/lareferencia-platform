#!/usr/bin/env bats
# Two installations on one host: `up` must stop BEFORE building, stopping or
# recreating anything when the ports it publishes are taken, and the port
# offset must not move a port onto the default port of another service.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

# Running container of another installation: name|project|working dir|image|ports
other_vufind_on_8090='otherlr-vufind-web|otherlr|/srv/other/lareferencia-platform|lareferencia/vufind-web:x|0.0.0.0:8090->80/tcp, [::]:8090->80/tcp'

@test "up: port taken by a container of another project → fails before touching anything" {
  export FAKE_PS="${other_vufind_on_8090}"
  docker_sh up
  assert_failure
  assert_output_contains "8090 (harvester) is in use by container otherlr-vufind-web (project otherlr, /srv/other/lareferencia-platform)"
  assert_output_contains "Nothing was built, stopped or recreated"
  refute_called " up -d"
  refute_called "compose build"
  refute_called "mvn clean package"
}

@test "up: missing images + port conflict → still fails before the build" {
  export FAKE_IMAGES=none FAKE_PS="${other_vufind_on_8090}"
  docker_sh up
  assert_failure
  refute_called "githelper"
  refute_called "mvn clean package"
  refute_called " up -d"
}

@test "up <service>: ports of compose dependencies are checked too" {
  export FAKE_PS='otherlr-postgres|otherlr|/srv/other|postgres:17|127.0.0.1:5432->5432/tcp'
  docker_sh up harvester
  assert_failure
  assert_output_contains "5432 (postgres) is in use by container otherlr-postgres"
}

@test "up: ports published by this project's own containers are not conflicts" {
  local project
  docker_sh modules status   # creates .env and the project name
  project="$(env_get COMPOSE_PROJECT_NAME)"
  export FAKE_PS="${project}-harvester|${project}|${SANDBOX_ROOT}|lareferencia/harvester:x|127.0.0.1:8090->8090/tcp"
  export FAKE_LISTEN="8090"   # docker-proxy of our own container
  docker_sh up
  assert_success
  assert_called " up -d"
}

@test "up: port taken by a process on the host → fails" {
  export FAKE_LISTEN="8983"
  docker_sh up
  assert_failure
  assert_output_contains "8983 (solr) is in use by a process on the host"
  refute_called " up -d"
}

@test "up: port of a disabled module taken elsewhere → no conflict" {
  export FAKE_PS='x-entity|x|/srv/x|lareferencia/entity-rest:x|0.0.0.0:8094->8094/tcp'
  docker_sh up
  assert_success
}

@test "up: another installation without port conflicts → warns and continues (non-interactive)" {
  export FAKE_PS='otherlr-harvester|otherlr|/srv/other/lareferencia-platform|lareferencia/harvester:x|127.0.0.1:9090->8090/tcp'
  docker_sh up
  assert_success
  assert_output_contains "Other LA Referencia installation(s) running on this host"
  assert_output_contains "project otherlr  /srv/other/lareferencia-platform"
  assert_output_contains "This checkout: ${SANDBOX_ROOT}"
  assert_called " up -d"
}

@test "up --offset=10: rejected (VuFind would take 8090, the default Harvester port)" {
  docker_sh up --offset=10
  assert_failure
  assert_output_contains "Port offset 10 is not allowed"
  assert_output_contains "VUFIND_WEB would use port 8090, the default port of HARVESTER"
  [ -z "$(env_get SERVICES_PORT_OFFSET)" ]
  refute_called " up -d"
}

@test "up --offset=abc: rejected" {
  docker_sh up --offset=abc
  assert_failure
  assert_output_contains "must be a number"
}

@test "up --offset=1000: accepted, ports shifted" {
  docker_sh up --offset=1000
  assert_success
  [ "$(env_get LR_PORT_HARVESTER)" = "9090" ]
  [ "$(env_get LR_PORT_VUFIND_WEB)" = "9080" ]
}
