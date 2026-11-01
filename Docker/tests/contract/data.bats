#!/usr/bin/env bats
# reset-data: deletes exactly the mapped data directories and cloned modules.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

data_files() {
  ( cd "${SANDBOX_ROOT}/Docker" && find data volume -type f | sort )
}

@test "reset-data --yes: wipes data, keeps .gitkeep, removes cloned modules" {
  touch "${SANDBOX_ROOT}/keep-me.txt"
  docker_sh reset-data --yes
  assert_success

  # only the placeholders survive
  run data_files
  [ -z "$(printf '%s\n' "${output}" | grep -v '/\.gitkeep$')" ] || { echo "${output}"; false; }
  [ -n "$(printf '%s\n' "${output}" | grep '/\.gitkeep$')" ]

  # cloned Java modules are gone, everything else stays
  [ ! -d "${SANDBOX_ROOT}/lareferencia-core-lib" ]
  [ -f "${SANDBOX_ROOT}/keep-me.txt" ]
  [ -f "${SANDBOX_ROOT}/Docker/docker.sh" ]
  [ -f "${SANDBOX_ROOT}/vufind/composer.json" ]

  assert_snapshot reset-data
}

@test "reset-data: wrong confirmation → nothing is deleted" {
  docker_sh_input "nope" reset-data
  assert_failure
  assert_output_contains "DANGER ZONE"
  [ -f "${SANDBOX_ROOT}/Docker/volume/postgres/sample.dat" ]
  [ -d "${SANDBOX_ROOT}/lareferencia-core-lib" ]
  refute_called "down"
}

@test "reset-data: typing RESET confirms" {
  docker_sh_input "RESET" reset-data
  assert_success
  [ ! -f "${SANDBOX_ROOT}/Docker/volume/postgres/sample.dat" ]
}

@test "reset-data: lists exactly the directories that will be deleted" {
  docker_sh_input "nope" reset-data
  local dir
  for dir in Docker/data Docker/volume/postgres Docker/volume/solr Docker/volume/elasticsearch \
             Docker/volume/lareferencia Docker/volume/vufind Docker/volume/vufind-db; do
    assert_output_contains "- ${dir}"
  done
}
