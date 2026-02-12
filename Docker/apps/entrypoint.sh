#!/usr/bin/env bash
set -euo pipefail

APP_MODULE="${APP_MODULE:?APP_MODULE is required}"
APP_JAR="${APP_JAR:?APP_JAR is required}"
LR_BUILD_PROFILE="${LR_BUILD_PROFILE:-lareferencia}"
BUILD_ON_START="${BUILD_ON_START:-true}"
DOCKER_OVERRIDES_DIR="${DOCKER_OVERRIDES_DIR:-/docker-overrides}"
APP_RUN_CONFIG_DIR="${APP_RUN_CONFIG_DIR:-/tmp/lr-config/${APP_MODULE}}"

APP_DIR="/workspace/${APP_MODULE}"
APP_CONFIG_DIR="${APP_CONFIG_DIR:-${APP_DIR}/config}"

if [ ! -d "${APP_DIR}" ]; then
  echo "Module directory not found: ${APP_DIR}" >&2
  exit 1
fi

if [ "${BUILD_ON_START}" = "true" ] && [ ! -f "${APP_DIR}/${APP_JAR}" ]; then
  echo "Building ${APP_MODULE} (profile=${LR_BUILD_PROFILE})..."
  cd /workspace
  mvn -pl "${APP_MODULE}" -am clean package install -DskipTests -Dmaven.javadoc.skip=true -P"${LR_BUILD_PROFILE}"
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
exec java ${JAVA_OPTS:-} "${JAVA_OVERRIDE_PROPS[@]}" -Dapp.config.dir="${APP_RUN_CONFIG_DIR}" -jar "${APP_JAR}" "$@"
