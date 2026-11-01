#!/usr/bin/env bash
# =============================================================================
# sandbox.bash — bats helper for contract tests.
#
# Every test runs the REAL docker.sh inside a disposable copy of the project
# (the "sandbox"), with fake `docker`, `git`, `githelper` and build scripts
# that only record what they were asked to do. Nothing touches the real
# checkout, the real .env, the Docker daemon or the network.
#
#   load ../helpers/sandbox          # in a .bats file
#
#   setup_file  → sandbox::build_template   (once per file)
#   setup       → sandbox::create           (fresh copy per test)
#
#   docker_sh <args...>             runs docker.sh (bats `run`: $status, $output)
#   docker_sh_input <stdin> <args>  same, feeding stdin (e.g. "RESET")
#   calls                           normalized call log (paths/hashes replaced)
#   assert_snapshot <name>          calls == snapshots/<name>.log (fails if missing;
#                                   UPDATE_SNAPSHOTS=1 creates/rewrites it)
#   assert_called <text>            some call contains <text>
#   refute_called <text>            no call contains <text>
#   env_get <KEY>                   value in the sandbox Docker/.env
#   env_set <KEY> <value>           sets it (creates .env from .env.example if needed)
#   sandbox_hash / current_image_tag   checkout hash and image tag of the sandbox
#   with_pg_data <major>            pretends the postgres volume holds that version
# =============================================================================

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${TESTS_DIR}/../.." && pwd)"
FAKES_DIR="${TESTS_DIR}/fakes"
SNAPSHOT_DIR="${TESTS_DIR}/contract/snapshots"
REAL_GIT="${REAL_GIT:-$(command -v git)}"   # resolved before fakes/ enters PATH
HOST_UID_GID="$(id -u):$(id -g)"            # real ids (tests may fake `id`)

# Java modules expected by docker.sh (pom.xml) and the apps that ship a JAR.
SANDBOX_JAVA_MODULES=(
  lareferencia-oclc-harvester lareferencia-core-lib lareferencia-entity-lib
  lareferencia-indexing-filters-lib lareferencia-shell-entity-plugin lareferencia-shell
  lareferencia-dark-lib lareferencia-lrharvester-admin-web lareferencia-repository-dashboard
  lareferencia-lrharvester-app lareferencia-entity-rest lareferencia-oai-pmh
)
SANDBOX_APP_MODULES=(
  lareferencia-lrharvester-app lareferencia-entity-rest lareferencia-shell lareferencia-oai-pmh
)

# --- Template (built once per .bats file) --------------------------------------------

sandbox::build_template() {
  local t="${BATS_FILE_TMPDIR}/template"
  rm -rf "${t}"
  mkdir -p "${t}/Docker"

  # Project files docker.sh reads.
  cp -R "${PROJECT_DIR}/Docker/lib" "${PROJECT_DIR}/Docker/profiles" \
        "${PROJECT_DIR}/Docker/config-overrides" "${PROJECT_DIR}/Docker/scripts" "${t}/Docker/"
  cp "${PROJECT_DIR}/Docker/docker.sh" "${PROJECT_DIR}/Docker/.env.example" \
     "${PROJECT_DIR}/Docker/.gitignore" "${t}/Docker/"
  cp "${PROJECT_DIR}/docker-compose.yml" "${PROJECT_DIR}/workspace.ini" \
     "${PROJECT_DIR}/.gitignore" "${t}/"
  # gum is only needed by the wizard; reuse the downloaded binary if any.
  [ -d "${PROJECT_DIR}/Docker/.bin" ] && ln -s "${PROJECT_DIR}/Docker/.bin" "${t}/Docker/.bin"

  # Project scripts replaced by recorders.
  mkdir -p "${t}/Docker/solr"
  local s
  for s in githelper build-admin-web.sh build-dashboard.sh Docker/solr/stage-cores.sh; do
    cp "${FAKES_DIR}/recorder" "${t}/${s}"
  done

  # Bind-mounted data with placeholders (.gitkeep must survive a reset).
  local d
  for d in data/build-logs volume/postgres volume/solr volume/elasticsearch \
           volume/lareferencia volume/vufind volume/vufind-db; do
    mkdir -p "${t}/Docker/${d}"
    touch "${t}/Docker/${d}/.gitkeep"
    echo "user data" > "${t}/Docker/${d}/sample.dat"
  done

  # VuFind already cloned.
  mkdir -p "${t}/vufind" && echo '{}' > "${t}/vufind/composer.json"

  # The sandbox root is a git repository, like a real installation.
  ( cd "${t}" \
    && "${REAL_GIT}" init -q -b main \
    && "${REAL_GIT}" add -A \
    && GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
       "${REAL_GIT}" -c user.name=test -c user.email=test@example.org commit -q -m sandbox )

  # Cloned Java modules (nested checkouts, ignored by the parent repo) with JARs.
  local m
  for m in "${SANDBOX_JAVA_MODULES[@]}"; do
    mkdir -p "${t}/${m}/.git" "${t}/${m}/target"
    echo "<project/>" > "${t}/${m}/pom.xml"
    echo "/target/" >> "${t}/.git/info/exclude"
    echo "/${m}/" >> "${t}/.git/info/exclude"
  done
  for m in "${SANDBOX_APP_MODULES[@]}" lareferencia-dark-lib; do
    echo "${m} jar" > "${t}/${m}/target/${m}-1.0.jar"
  done
  # The harvester JAR embeds the dark-lib JAR (checked by build::write_manifests).
  python3 - "${t}" <<'PY'
import sys, zipfile
root = sys.argv[1]
dark = f"{root}/lareferencia-dark-lib/target/lareferencia-dark-lib-1.0.jar"
with zipfile.ZipFile(f"{root}/lareferencia-lrharvester-app/target/lareferencia-lrharvester-app-1.0.jar", "w") as z:
    z.write(dark, "BOOT-INF/lib/lareferencia-dark-lib-1.0.jar")
PY
}

# --- Per test ------------------------------------------------------------------------------

sandbox::create() {
  SANDBOX_ROOT="${BATS_TEST_TMPDIR}/root"
  cp -R "${BATS_FILE_TMPDIR}/template" "${SANDBOX_ROOT}"
  SANDBOX_ROOT="$(cd "${SANDBOX_ROOT}" && pwd)"   # same spelling docker.sh will use
  FAKE_LOG="${BATS_TEST_TMPDIR}/calls.log"
  : > "${FAKE_LOG}"
  export SANDBOX_ROOT FAKE_LOG REAL_GIT
  # Knobs of fakes/docker, reset for each test.
  unset FAKE_DOCKER_DOWN FAKE_RUNNING FAKE_IMAGES FAKE_FAIL
}

_sandbox::run_env() {
  env -u COMPOSE_PROJECT_NAME -u SERVICE_PREFIX -u LR_IMAGE_TAG -u COMPOSE_PROFILES \
    PATH="${FAKES_DIR}:${PATH}" HOME="${BATS_TEST_TMPDIR}/home" TERM=dumb NO_COLOR=1 "$@"
}

docker_sh() {
  run _sandbox::run_env "${SANDBOX_ROOT}/Docker/docker.sh" "$@"
}

docker_sh_input() {
  local input="$1"
  shift
  run _sandbox::run_env bash -c 'printf "%s\n" "$1" | "${@:2}"' _ "${input}" "${SANDBOX_ROOT}/Docker/docker.sh" "$@"
}

# --- Assertions -------------------------------------------------------------------------------

# Call log with machine-specific values replaced by stable placeholders.
calls() {
  local root_hash commit
  root_hash="$(printf "%s" "${SANDBOX_ROOT}" | shasum -a 256 | cut -c1-7)"
  commit="$("${REAL_GIT}" -C "${SANDBOX_ROOT}" rev-parse --short=7 HEAD)"
  # `docker compose version` precedes every compose call (binary detection): noise.
  sed -e '/^docker compose version$/d' \
      -e "s#${SANDBOX_ROOT}#<ROOT>#g" \
      -e "s#${root_hash}#<HASH>#g" \
      -e "s#${commit}#<COMMIT>#g" \
      -e "s#${HOST_UID_GID}#<UID>:<GID>#g" \
      "${FAKE_LOG}"
}

_fail() {
  printf '%s\n' "$@" >&2
  return 1
}

assert_success() {
  [ "${status}" -eq 0 ] || _fail "expected success, got exit ${status}" "--- output ---" "${output}"
}

assert_failure() {
  [ "${status}" -ne 0 ] || _fail "expected failure, got exit 0" "--- output ---" "${output}"
}

assert_output_contains() {
  [[ "${output}" == *"$1"* ]] || _fail "output does not contain: $1" "--- output ---" "${output}"
}

assert_called() {
  calls | grep -qF -- "$1" || _fail "no call contains: $1" "--- calls ---" "$(calls)"
}

refute_called() {
  if calls | grep -qF -- "$1"; then
    _fail "unexpected call containing: $1" "--- calls ---" "$(calls)"
  fi
}

assert_snapshot() {
  local name="$1" file="${SNAPSHOT_DIR}/$1.log" actual
  actual="$(calls)"
  if [ "${UPDATE_SNAPSHOTS:-0}" = 1 ]; then
    printf '%s\n' "${actual}" > "${file}"
    return 0
  fi
  # A missing snapshot must not pass silently (e.g. not committed).
  [ -f "${file}" ] || _fail "snapshot '${name}' not found: ${file}" \
    "Create it with: UPDATE_SNAPSHOTS=1 ./Docker/tests/run.sh contract -f '...'" \
    "--- actual calls ---" "${actual}"
  diff -u "${file}" <(printf '%s\n' "${actual}") >&2 \
    || _fail "calls differ from snapshot '${name}'." \
             "If the change is intended: UPDATE_SNAPSHOTS=1 ./Docker/tests/run.sh contract"
}

env_get() {
  grep -E "^$1=" "${SANDBOX_ROOT}/Docker/.env" | tail -n 1 | cut -d= -f2-
}

with_pg_data() {
  local dir="${SANDBOX_ROOT}/Docker/volume/lareferencia/postgres/data/pgdata"
  mkdir -p "${dir}"
  echo "$1" > "${dir}/PG_VERSION"
}

env_set() {
  local env="${SANDBOX_ROOT}/Docker/.env"
  [ -f "${env}" ] || cp "${SANDBOX_ROOT}/Docker/.env.example" "${env}"
  grep -v "^$1=" "${env}" > "${env}.tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "${env}.tmp"
  mv "${env}.tmp" "${env}"
}

sandbox_hash() {
  printf "%s" "${SANDBOX_ROOT}" | shasum -a 256 | cut -c1-7
}

# Tag of the images of the sandbox checkout (see compose::image_tag).
current_image_tag() {
  echo "lareferencia-$(sandbox_hash)-$("${REAL_GIT}" -C "${SANDBOX_ROOT}" rev-parse --short=7 HEAD)"
}
