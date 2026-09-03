#!/usr/bin/env bash
set -euo pipefail

APP_MODULE="${APP_MODULE:?APP_MODULE is required}"
SHELL_IDLE="${SHELL_IDLE:-false}"
DOCKER_OVERRIDES_DIR="${DOCKER_OVERRIDES_DIR:-/docker-overrides}"
APP_RUN_CONFIG_DIR="${APP_RUN_CONFIG_DIR:-/tmp/lr-config/${APP_MODULE}}"
APP_DIR="/workspace/${APP_MODULE}"
APP_CONFIG_DIR="${APP_CONFIG_DIR:-${APP_DIR}/config}"
APP_ARGS=("$@")
cd "${APP_DIR}"

is_truthy() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

echo "--- Developer runtime: ${APP_MODULE} ---"
mkdir -p "${APP_RUN_CONFIG_DIR}" "${DATA_DIR:-/data}" "${LOG_DIR:-/var/log/harvester}"

if [ -n "${EXTERNAL_CONFIG_DIR:-}" ]; then
  mkdir -p "${EXTERNAL_CONFIG_DIR}"
  if [ -d "${APP_CONFIG_DIR}" ]; then
    cp -ru "${APP_CONFIG_DIR}/." "${EXTERNAL_CONFIG_DIR}/" 2>/dev/null || true
  fi
  APP_CONFIG_DIR="${EXTERNAL_CONFIG_DIR}"
fi

rm -rf "${APP_RUN_CONFIG_DIR}"
mkdir -p "${APP_RUN_CONFIG_DIR}"
if [ -d "${APP_CONFIG_DIR}" ]; then
  cp -a "${APP_CONFIG_DIR}/." "${APP_RUN_CONFIG_DIR}/"
fi

OVERRIDE_MODULE_DIR="${DOCKER_OVERRIDES_DIR}/${APP_MODULE}"
if [ -d "${OVERRIDE_MODULE_DIR}" ]; then
  cp -a "${OVERRIDE_MODULE_DIR}/." "${APP_RUN_CONFIG_DIR}/"
fi

JAVA_OVERRIDE_PROPS=()
if [ -n "${SPRING_PROFILES_ACTIVE:-}" ]; then
  JAVA_OVERRIDE_PROPS+=("-Dspring.profiles.active=${SPRING_PROFILES_ACTIVE}")
fi
if [ -n "${ACTIONS_BEANS_FILENAME:-}" ]; then
  JAVA_OVERRIDE_PROPS+=("-Dactions.beans.filename=${ACTIONS_BEANS_FILENAME}")
fi

OVERRIDE_FILE="${APP_RUN_CONFIG_DIR}/99-docker.properties"
if [ -f "${OVERRIDE_FILE}" ]; then
  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    line="$(printf '%s' "${raw_line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    JAVA_OVERRIDE_PROPS+=("-D${key}=${value}")
  done < "${OVERRIDE_FILE}"
  rm -f "${OVERRIDE_FILE}"
fi

# Developer-only convenience account.  It is written into the ephemeral runtime
# configuration, never into the mounted source tree or the normal platform data.
if [ "${APP_MODULE}" = "lareferencia-lrharvester-app" ] && is_truthy "${DEV_DEFAULT_ADMIN:-true}"; then
  DEV_USERS_FILE="${APP_RUN_CONFIG_DIR}/users.properties"
  DEV_ADMIN_HASH='$2a$10$4y1zPBq1Sab.k62WLj7QNudiifOuJq/Da27oIT1S7SgPwdvheGw5W'
  DEV_USERS_TMP="${DEV_USERS_FILE}.tmp"
  [ -f "${DEV_USERS_FILE}" ] || : > "${DEV_USERS_FILE}"
  grep -v '^admin=' "${DEV_USERS_FILE}" > "${DEV_USERS_TMP}" || true
  printf 'admin=%s,ROLE_ADMIN\n' "${DEV_ADMIN_HASH}" >> "${DEV_USERS_TMP}"
  mv "${DEV_USERS_TMP}" "${DEV_USERS_FILE}"
  JAVA_OVERRIDE_PROPS+=("-Dsecurity.users.file=${DEV_USERS_FILE}")
  echo 'Developer Harvester account enabled: admin / admin'
fi

if [ "${APP_MODULE}" = "lareferencia-shell" ] && is_truthy "${SHELL_IDLE}" && [ "${#APP_ARGS[@]}" -eq 0 ]; then
  echo "Starting ${APP_MODULE} in idle mode."
  exec tail -f /dev/null
fi

APP_JAR_PATH="${APP_JAR_PATH:-}"
if [ -z "${APP_JAR_PATH}" ]; then
  APP_JAR_PATH="$(find "${APP_DIR}/target" -maxdepth 1 -type f -name "${APP_MODULE}-*.jar" ! -name '*-sources.jar' ! -name '*-javadoc.jar' -print -quit 2>/dev/null || true)"
fi
if [ -z "${APP_JAR_PATH}" ] || [ ! -f "${APP_JAR_PATH}" ]; then
  echo "Developer JAR not found for ${APP_MODULE}. Run: docker-dev.sh build ${APP_MODULE}" >&2
  exit 1
fi

echo "Starting ${APP_MODULE} from ${APP_JAR_PATH}"
exec java ${JAVA_OPTS:-} "${JAVA_OVERRIDE_PROPS[@]}" -Dapp.config.dir="${APP_RUN_CONFIG_DIR}" -jar "${APP_JAR_PATH}" "${APP_ARGS[@]}"
