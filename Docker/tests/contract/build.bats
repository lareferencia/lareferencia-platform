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
  export FAKE_CLONE_FAILURES=0
  docker_sh build oai-pmh
  # the fake Maven creates no JAR for the new clone: what matters is reaching it
  assert_called "mvn clean package"
  assert_called "githelper init --jobs 4 --depth 1 --modules lareferencia-shell"
  refute_called "githelper pull"
}

@test "build: a clone broken by the network is retried, one at a time, only for what is missing" {
  rm -rf "${SANDBOX_ROOT}/lareferencia-shell" "${SANDBOX_ROOT}/lareferencia-oai-pmh"
  env_set GIT_CLONE_RETRY_DELAY 0
  export FAKE_CLONE_FAILURES=1
  docker_sh build oai-pmh
  refute_output_contains "could not clone"
  assert_output_contains "attempt 2/3, one at a time"
  assert_called "githelper init --jobs 4 --depth 1 --modules lareferencia-shell,lareferencia-oai-pmh"
  assert_called "githelper init --jobs 1 --depth 1 --modules lareferencia-shell,lareferencia-oai-pmh"
  assert_called "mvn clean package"
}

@test "build: clones still failing after GIT_CLONE_ATTEMPTS → stops before compiling, names the modules" {
  rm -rf "${SANDBOX_ROOT}/lareferencia-shell"
  env_set GIT_CLONE_RETRY_DELAY 0
  env_set GIT_CLONE_ATTEMPTS 2
  export FAKE_CLONE_FAILURES=99
  docker_sh build oai-pmh
  assert_failure
  assert_output_contains "could not clone after 2 attempt(s): lareferencia-shell"
  [ "$(grep -c "^githelper init" "${FAKE_LOG}")" -eq 2 ]
  refute_called "mvn clean package"
}

@test "build: an interrupted clone (.git without a commit) is removed before retrying" {
  rm -rf "${SANDBOX_ROOT}/lareferencia-shell"
  "${REAL_GIT}" init -q "${SANDBOX_ROOT}/lareferencia-shell"     # unborn HEAD, no pom.xml
  env_set GIT_CLONE_RETRY_DELAY 0
  export FAKE_CLONE_FAILURES=1
  docker_sh build oai-pmh
  refute_output_contains "could not clone"
  assert_output_contains "Removing incomplete clone: lareferencia-shell"
  [ -f "${SANDBOX_ROOT}/lareferencia-shell/pom.xml" ]
}

@test "build: a module checkout with commits but no pom.xml is never deleted" {
  rm -rf "${SANDBOX_ROOT}/lareferencia-shell"
  "${REAL_GIT}" init -q "${SANDBOX_ROOT}/lareferencia-shell"
  echo work > "${SANDBOX_ROOT}/lareferencia-shell/notes.txt"
  "${REAL_GIT}" -C "${SANDBOX_ROOT}/lareferencia-shell" add -A
  "${REAL_GIT}" -C "${SANDBOX_ROOT}/lareferencia-shell" -c user.name=t -c user.email=t@e commit -qm wip
  env_set GIT_CLONE_RETRY_DELAY 0
  env_set GIT_CLONE_ATTEMPTS 2
  export FAKE_CLONE_FAILURES=99
  docker_sh build oai-pmh
  assert_failure
  refute_output_contains "Removing incomplete clone"
  [ -f "${SANDBOX_ROOT}/lareferencia-shell/notes.txt" ]
}

@test "build: the Maven image cannot be pulled → stops before compiling" {
  export FAKE_FAIL="maven:3"     # image inspect + pull of the Maven image fail
  docker_sh build oai-pmh
  assert_failure
  assert_output_contains "Failed to pull builder image"
  refute_called "mvn clean package"
}

# --- network failures while downloading images ----------------------------------------

@test "build: image download timed out → compose build is repeated and the build completes" {
  env_set DOCKER_NETWORK_RETRY_DELAY 0
  export FAKE_NET_FAIL=" build oai-pmh" FAKE_NET_FAILURES=1
  docker_sh build oai-pmh
  assert_success
  assert_output_contains "Network failure while downloading images; retrying"
  [ "$(calls | grep -c ' build oai-pmh')" -eq 2 ]
}

@test "build: a failure that is not the network is not repeated" {
  env_set DOCKER_NETWORK_RETRY_DELAY 0
  export FAKE_FAIL=" build oai-pmh"
  docker_sh build oai-pmh
  assert_failure
  refute_output_contains "retrying"
  [ "$(calls | grep -c ' build oai-pmh')" -eq 1 ]
}

@test "build: network keeps failing → stops after DOCKER_NETWORK_ATTEMPTS with a hint" {
  env_set DOCKER_NETWORK_RETRY_DELAY 0
  env_set DOCKER_NETWORK_ATTEMPTS 2
  export FAKE_NET_FAIL=" build oai-pmh" FAKE_NET_FAILURES=99
  docker_sh build oai-pmh
  assert_failure
  assert_output_contains "network failure persisted after 2 attempt(s)"
  [ "$(calls | grep -c ' build oai-pmh')" -eq 2 ]
}
