#!/usr/bin/env bash
set -euo pipefail

# 1. Execute custom system commands IMMEDIATELY if provided
if [ "$#" -gt 0 ] && command -v "$1" >/dev/null 2>&1; then
  echo "--- Entrypoint: Detected system command '$1'. Executing directly... ---"
  exec "$@"
elif [ "$#" -gt 0 ]; then
  echo "--- Entrypoint: Passing arguments to Java app: $@ ---"
  APP_ARGS=("$@")
else
  APP_ARGS=()
fi

APP_MODULE="${APP_MODULE:?APP_MODULE is required}"
SHELL_IDLE="${SHELL_IDLE:-false}"
DOCKER_OVERRIDES_DIR="${DOCKER_OVERRIDES_DIR:-/docker-overrides}"
APP_RUN_CONFIG_DIR="${APP_RUN_CONFIG_DIR:-/tmp/lr-config/${APP_MODULE}}"
M2_DIR="${M2_DIR:-/root/.m2}"

echo "--- Initializing ${APP_MODULE} container ---"

APP_DIR="/workspace/${APP_MODULE}"
APP_CONFIG_DIR="${APP_CONFIG_DIR:-${APP_DIR}/config}"

is_truthy() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# If it's the shell module and idle is requested, wait
if [ "${APP_MODULE}" = "lareferencia-shell" ] && is_truthy "${SHELL_IDLE}" && [ "${#APP_ARGS[@]}" -eq 0 ]; then
  echo "Starting ${APP_MODULE} in idle mode (SHELL_IDLE=true)."
  exec tail -f /dev/null
fi

# Build isolated runtime config
rm -rf "${APP_RUN_CONFIG_DIR}"
mkdir -p "${APP_RUN_CONFIG_DIR}"
if [ -d "${APP_CONFIG_DIR}" ]; then
  cp -a "${APP_CONFIG_DIR}/." "${APP_RUN_CONFIG_DIR}/"
fi

OVERRIDE_FILE="${DOCKER_OVERRIDES_DIR}/${APP_MODULE}/99-docker.properties"
JAVA_OVERRIDE_PROPS=()

if [ -f "${OVERRIDE_FILE}" ]; then
  echo "Applying overrides from ${OVERRIDE_FILE}"
  mkdir -p "${APP_RUN_CONFIG_DIR}/application.properties.d"
  cp "${OVERRIDE_FILE}" "${APP_RUN_CONFIG_DIR}/application.properties.d/99-docker.properties"

  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    line="$(printf '%s' "${raw_line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]]; then continue; fi
    key="${line%%=*}"; value="${line#*=}"
    key="$(printf '%s' "${key}" | sed -e 's/[[:space:]]*$//')"
    value="$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//')"
    if [ -n "${key}" ]; then JAVA_OVERRIDE_PROPS+=("-D${key}=${value}"); fi
  done < "${OVERRIDE_FILE}"
fi

# Dynamic configuration variables
if [ -n "${SPRING_PROFILES_ACTIVE:-}" ]; then
  echo "Active Profiles: ${SPRING_PROFILES_ACTIVE}"
  JAVA_OVERRIDE_PROPS+=("-Dspring.profiles.active=${SPRING_PROFILES_ACTIVE}")
fi
if [ -n "${ACTIONS_BEANS_FILENAME:-}" ]; then
  echo "Actions File: ${ACTIONS_BEANS_FILENAME}"
  JAVA_OVERRIDE_PROPS+=("-Dactions.beans.filename=${ACTIONS_BEANS_FILENAME}")
fi

cd "${APP_DIR}"

# RUN LOGIC: Check if it's layers or a single JAR fallback
if [ -f "application/app.jar" ]; then
  echo "Starting ${APP_MODULE} via single JAR..."
  exec java ${JAVA_OPTS:-} "${JAVA_OVERRIDE_PROPS[@]}" -Dapp.config.dir="${APP_RUN_CONFIG_DIR}" -jar application/app.jar "${APP_ARGS[@]}"
else
  echo "Starting ${APP_MODULE} via JarLauncher (Layers)..."
  # Spring Boot 3 uses org.springframework.boot.loader.launch.JarLauncher
  # We try both old and new launcher locations for safety
  LAUNCHER="org.springframework.boot.loader.launch.JarLauncher"
  if ! java -cp . "${LAUNCHER}" --help >/dev/null 2>&1; then
      LAUNCHER="org.springframework.boot.loader.JarLauncher"
  fi
  exec java ${JAVA_OPTS:-} "${JAVA_OVERRIDE_PROPS[@]}" -Dapp.config.dir="${APP_RUN_CONFIG_DIR}" "${LAUNCHER}" "${APP_ARGS[@]}"
fi
