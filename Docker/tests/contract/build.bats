#!/usr/bin/env bats
# build: what gets compiled for each selection, and failures stop the pipeline.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

@test "build: solr staging + frontends + Java + images, in this order" {
  docker_sh build
  assert_success
  assert_snapshot build-all
}

@test "build: writes the build manifests (commit + jar hash + dark-lib check)" {
  docker_sh build
  assert_success
  local manifest="${SANDBOX_ROOT}/lareferencia-lrharvester-app/target/docker-build-info.properties"
  grep -q '^git.commit=' "${manifest}"
  grep -q '^application.sha256=' "${manifest}"
  grep -q '^dark-lib.sha256=' "${manifest}"
}

@test "build oai-pmh: Java only, no frontends, no solr staging" {
  docker_sh build oai-pmh
  assert_success
  assert_called "mvn clean package"
  refute_called "build-admin-web.sh"
  refute_called "stage-cores.sh"
  assert_snapshot build-oai-pmh
}

@test "build solr: staging only, no compilation" {
  docker_sh build solr
  assert_success
  assert_called "stage-cores.sh"
  refute_called "mvn"
  refute_called "build-admin-web.sh"
}

@test "build: a frontend failure stops before Java and images" {
  export FAKE_FAIL="build-dashboard.sh"
  docker_sh build
  assert_failure
  assert_output_contains "Angular Dashboard build failed"
  refute_called "mvn clean package"
  refute_called "compose -f"   # no image build
}

@test "build: a Maven failure stops before the images" {
  export FAKE_FAIL="mvn clean package"
  docker_sh build
  assert_failure
  assert_output_contains "Maven build failed"
  refute_called "--profile tools build"   # no images from stale JARs
  [ ! -f "${SANDBOX_ROOT}/lareferencia-oai-pmh/target/docker-build-info.properties" ]
}

@test "build with BUILD_PARALLEL=true: same components, built in parallel" {
  docker_sh up --prefix=x            # creates .env
  echo "BUILD_PARALLEL=true" >> "${SANDBOX_ROOT}/Docker/.env"
  : > "${FAKE_LOG}"
  docker_sh build
  assert_success
  assert_output_contains "Building Components in Parallel"
  assert_called "build-admin-web.sh"
  assert_called "build-dashboard.sh"
  assert_called "mvn clean package"
}

@test "build: missing Java modules are cloned with githelper (never pulled)" {
  rm -rf "${SANDBOX_ROOT}/lareferencia-shell"
  docker_sh build oai-pmh
  # githelper is a recorder: the module is still missing, but it was asked for
  assert_called "githelper init"
  assert_called "--modules lareferencia-shell"
  refute_called "githelper pull"
}

@test "build: the Maven image cannot be pulled → stops before compiling" {
  export FAKE_FAIL="maven:3"     # image inspect + pull of the Maven image fail
  docker_sh build oai-pmh
  assert_failure
  assert_output_contains "Failed to pull builder image"
  refute_called "mvn clean package"
}
