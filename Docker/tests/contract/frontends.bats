#!/usr/bin/env bats
# Frontend builds (React admin web, Angular dashboard) and the ownership guard:
# files left by a container that ran as root must not break the next build.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup() {
  sandbox::create
  # Real build scripts instead of the recorders, with minimal Node projects.
  cp "${PROJECT_DIR}/build-admin-web.sh" "${PROJECT_DIR}/build-dashboard.sh" "${SANDBOX_ROOT}/"
  local d
  for d in lareferencia-lrharvester-admin-web lareferencia-repository-dashboard/angular; do
    mkdir -p "${SANDBOX_ROOT}/${d}"
    echo '{}' > "${SANDBOX_ROOT}/${d}/package.json"
    echo '{}' > "${SANDBOX_ROOT}/${d}/package-lock.json"
  done
  HARVESTER="${SANDBOX_ROOT}/lareferencia-lrharvester-app"
  mkdir -p "${HARVESTER}/admin-static/assets" "${HARVESTER}/dashboard-static"
  echo old > "${HARVESTER}/admin-static/index.html"
  echo old > "${HARVESTER}/dashboard-static/index.html"
}

# Pretends to be another user (uid 4242): every existing file "belongs to someone else".
as_other_user() {
  mkdir -p "${BATS_TEST_TMPDIR}/idbin"
  cat > "${BATS_TEST_TMPDIR}/idbin/id" <<'ID'
#!/bin/sh
case "$1" in -u|-g) echo "${FAKE_UID}" ;; -un) echo fakeuser ;; *) exec /usr/bin/id "$@" ;; esac
ID
  chmod +x "${BATS_TEST_TMPDIR}/idbin/id"
  export FAKE_UID="$1" PATH="${BATS_TEST_TMPDIR}/idbin:${PATH}"
}

run_script() { run _sandbox::run_env "${SANDBOX_ROOT}/$1"; }

@test "admin web: own files → no extra container, then the Node build" {
  run_script build-admin-web.sh
  assert_success
  refute_called "chown"
  assert_called "node:22-bookworm-slim"
}

@test "admin web: files of another owner are given back before the build" {
  as_other_user 4242
  run_script build-admin-web.sh
  assert_success
  assert_output_contains "Fixing ownership of files created by another user"
  assert_called "docker run --rm -v <ROOT>/lareferencia-lrharvester-app:/workspace -w /workspace alpine chown -R 4242:4242 -- admin-static"
  # the fix comes BEFORE the Node container that deletes admin-static
  [ "$(calls | grep -n 'chown -R' | cut -d: -f1)" -lt "$(calls | grep -n 'node:22' | cut -d: -f1)" ]
  refute_called "dashboard-static"
}

@test "dashboard: files of another owner are given back before the build" {
  as_other_user 4242
  run_script build-dashboard.sh
  assert_success
  assert_called "alpine chown -R 4242:4242 -- dashboard-static"
  assert_called "node:18-bookworm-slim"
}

@test "running as root: nothing to fix" {
  as_other_user 0
  run_script build-admin-web.sh
  assert_success
  refute_called "chown"
}

@test "no previous output yet: nothing to fix" {
  rm -rf "${HARVESTER}/admin-static"
  as_other_user 4242
  run_script build-admin-web.sh
  assert_success
  refute_called "chown"
}

@test "harvester folder not writable: clear error with the fix, no Node build" {
  chmod 555 "${HARVESTER}"
  run_script build-admin-web.sh
  chmod 755 "${HARVESTER}"
  assert_failure
  assert_output_contains "is not writable by"
  assert_output_contains "sudo chown -R"
  refute_called "node:22"
}

@test "reclaim-ownership: globs, several paths, one container" {
  mkdir -p "${SANDBOX_ROOT}/mod-a/target" "${SANDBOX_ROOT}/mod-b/target"
  touch "${SANDBOX_ROOT}/mod-a/target/x.jar" "${SANDBOX_ROOT}/mod-b/target/y.jar"
  as_other_user 4242
  run _sandbox::run_env "${SANDBOX_ROOT}/Docker/scripts/reclaim-ownership.sh" "${SANDBOX_ROOT}" '*/target' lareferencia-lrharvester-app/admin-static missing-dir
  assert_success
  [ "$(calls | grep -c 'chown')" = 1 ]
  assert_called "chown -R 4242:4242 -- "
  assert_called "mod-a/target"
  assert_called "mod-b/target"
  assert_called "lareferencia-lrharvester-app/admin-static"
  refute_called "missing-dir"
}

@test "reclaim-ownership: docker fails → warns with the sudo command, does not fail the build" {
  as_other_user 4242
  export FAKE_FAIL="alpine chown"
  run_script build-admin-web.sh
  assert_success
  assert_output_contains "sudo chown -R 4242:4242 admin-static"
}
