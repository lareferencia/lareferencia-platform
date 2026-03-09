#!/usr/bin/env bash
set -euo pipefail

APP_MODULE="${APP_MODULE:?APP_MODULE is required}"
APP_JAR="${APP_JAR:?APP_JAR is required}"
LR_BUILD_PROFILE="${LR_BUILD_PROFILE:-lareferencia}"
BUILD_ON_START="${BUILD_ON_START:-smart}"
SHELL_IDLE="${SHELL_IDLE:-false}"
DOCKER_OVERRIDES_DIR="${DOCKER_OVERRIDES_DIR:-/docker-overrides}"
APP_RUN_CONFIG_DIR="${APP_RUN_CONFIG_DIR:-/tmp/lr-config/${APP_MODULE}}"
M2_DIR="${M2_DIR:-/root/.m2}"
BUILD_LOCK_DIR="${M2_DIR}/.lr-build-lock"
BUILD_LOCK_PID_FILE="${BUILD_LOCK_DIR}/pid"
BUILD_LOCK_HELD=false

APP_DIR="/workspace/${APP_MODULE}"
APP_CONFIG_DIR="${APP_CONFIG_DIR:-${APP_DIR}/config}"
JAR_PATH="${APP_DIR}/${APP_JAR}"

if [ ! -d "${APP_DIR}" ]; then
  echo "Module directory not found: ${APP_DIR}" >&2
  exit 1
fi

is_truthy() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "${APP_MODULE}" = "lareferencia-shell" ] && [ "$#" -eq 0 ] && is_truthy "${SHELL_IDLE}"; then
  echo "Starting ${APP_MODULE} in idle mode (SHELL_IDLE=true)."
  exec tail -f /dev/null
fi

should_build=false
build_mode="$(printf '%s' "${BUILD_ON_START}" | tr '[:upper:]' '[:lower:]')"

if [ ! -f "${JAR_PATH}" ]; then
  should_build=true
else
  case "${build_mode}" in
    always|rebuild|force)
      should_build=true
      ;;
    smart)
      # Rebuild only if relevant source/config/pom files are newer than the jar.
      if [ -f "/workspace/pom.xml" ] && [ "/workspace/pom.xml" -nt "${JAR_PATH}" ]; then
        should_build=true
      elif find /workspace/lareferencia-* \
        -type f \( -name '*.java' -o -name '*.xml' -o -name '*.properties' -o -name '*.yml' -o -name '*.yaml' -o -name 'pom.xml' \) \
        -newer "${JAR_PATH}" -print -quit 2>/dev/null | grep -q .; then
        should_build=true
      fi
      ;;
    false|off|no|0)
      should_build=false
      ;;
    true|missing|if-missing|"")
      should_build=false
      ;;
    *)
      echo "Unknown BUILD_ON_START='${BUILD_ON_START}', using missing-only behavior." >&2
      should_build=false
      ;;
  esac
fi

cleanup_build_lock() {
  if [ "${BUILD_LOCK_HELD}" = true ]; then
    rm -rf "${BUILD_LOCK_DIR}" || true
    BUILD_LOCK_HELD=false
  fi
}

lock_owner_is_alive() {
  local lock_pid

  if [ ! -f "${BUILD_LOCK_PID_FILE}" ]; then
    return 1
  fi

  lock_pid="$(cat "${BUILD_LOCK_PID_FILE}" 2>/dev/null || true)"
  if [ -z "${lock_pid}" ]; then
    return 1
  fi

  kill -0 "${lock_pid}" 2>/dev/null
}

acquire_build_lock() {
  local wait_announced=false

  mkdir -p "${M2_DIR}"

  while ! mkdir "${BUILD_LOCK_DIR}" 2>/dev/null; do
    if ! lock_owner_is_alive; then
      echo "Found stale build lock at ${BUILD_LOCK_DIR}; removing it."
      rm -rf "${BUILD_LOCK_DIR}" || true
      continue
    fi

    if [ "${wait_announced}" = false ]; then
      echo "Waiting for build lock at ${BUILD_LOCK_DIR}..."
      wait_announced=true
    fi
    sleep 1
  done

  printf '%s\n' "$$" > "${BUILD_LOCK_PID_FILE}"
  BUILD_LOCK_HELD=true
}

if [ "${should_build}" = true ]; then
  trap cleanup_build_lock EXIT INT TERM
  acquire_build_lock
  echo "Building ${APP_MODULE} (profile=${LR_BUILD_PROFILE})..."
  cd /workspace
  mvn -pl "${APP_MODULE}" -am clean package install -DskipTests -Dmaven.test.skip=true -Dmaven.javadoc.skip=true -P"${LR_BUILD_PROFILE}"
  cleanup_build_lock
fi

# Build an isolated runtime config so Docker overrides can be merged
# without mutating repository files under /workspace.
rm -rf "${APP_RUN_CONFIG_DIR}"
mkdir -p "${APP_RUN_CONFIG_DIR}"
cp -a "${APP_CONFIG_DIR}/." "${APP_RUN_CONFIG_DIR}/"

OVERRIDE_FILE="${DOCKER_OVERRIDES_DIR}/${APP_MODULE}/99-docker.properties"
JAVA_OVERRIDE_PROPS=()

if [ -f "${OVERRIDE_FILE}" ]; then
  mkdir -p "${APP_RUN_CONFIG_DIR}/application.properties.d"
  cp "${OVERRIDE_FILE}" "${APP_RUN_CONFIG_DIR}/application.properties.d/99-docker.properties"

  # Promote overrides as JVM system properties so they win over classpath
  # defaults and over low-priority custom property sources.
  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    line="$(printf '%s' "${raw_line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ -z "${line}" || "${line}" == \#* ]]; then
      continue
    fi

    if [[ "${line}" != *=* ]]; then
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    key="$(printf '%s' "${key}" | sed -e 's/[[:space:]]*$//')"
    value="$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//')"

    if [ -n "${key}" ]; then
      JAVA_OVERRIDE_PROPS+=("-D${key}=${value}")
    fi
  done < "${OVERRIDE_FILE}"
fi

cd "${APP_DIR}"

echo "Starting ${APP_MODULE}/${APP_JAR} with app.config.dir=${APP_RUN_CONFIG_DIR}"
cleanup_build_lock
exec java ${JAVA_OPTS:-} "${JAVA_OVERRIDE_PROPS[@]}" -Dapp.config.dir="${APP_RUN_CONFIG_DIR}" -jar "${APP_JAR}" "$@"
