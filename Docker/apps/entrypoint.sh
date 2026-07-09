#!/usr/bin/env bash
set -euo pipefail

# 1. Execute custom system commands IMMEDIATELY if provided
# Exclude Spring Shell built-in commands ('script', 'help', 'version') so they go to the Java application
if [ "$#" -gt 0 ] && [ "$1" != "script" ] && [ "$1" != "help" ] && [ "$1" != "version" ] && command -v "$1" >/dev/null 2>&1; then
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

# --- PERMISSIONS & USER SETUP ---
# Ensure runtime and log directories exist and are owned by the app user
mkdir -p "${APP_RUN_CONFIG_DIR}"
mkdir -p "${DATA_DIR:-/data}" "${LOG_DIR:-/var/log/harvester}"
chown -R lareferencia:lareferencia "${APP_RUN_CONFIG_DIR}" "${DATA_DIR:-/data}" "${LOG_DIR:-/var/log/harvester}"

# If standard input is a terminal, ensure the app user has permissions to read/write to it
if [ -t 0 ]; then
  CURRENT_TTY=$(tty)
  if [ -c "${CURRENT_TTY}" ]; then
    chown lareferencia:lareferencia "${CURRENT_TTY}"
  fi
fi

# --- SEED EXTERNAL CONFIG VOLUME ---
if [ -n "${EXTERNAL_CONFIG_DIR:-}" ]; then
  if [ ! -d "${EXTERNAL_CONFIG_DIR}" ]; then
    mkdir -p "${EXTERNAL_CONFIG_DIR}"
  fi
  
  # Ensure the app user can write to the external volume
  chown lareferencia:lareferencia "${EXTERNAL_CONFIG_DIR}"

  # Ensure the volume has at least the base configuration files
  # We use cp -ru (update) to fill in missing files. Since image defaults are older 
  # than files in the volume, this preserves user modifications.
  echo "Ensuring base configuration in ${EXTERNAL_CONFIG_DIR}..."
  cp -ru "${APP_CONFIG_DIR}/." "${EXTERNAL_CONFIG_DIR}/" > /dev/null 2>&1
  
  # --- MERGE OVERRIDES INTO EXTERNAL VOLUME ---
  # This allows persistent changes to the volume to be augmented by version-controlled overrides
  OVERRIDE_MODULE_DIR="${DOCKER_OVERRIDES_DIR}/${APP_MODULE}"
  if [ -d "${OVERRIDE_MODULE_DIR}" ]; then
    echo "Merging overrides from ${OVERRIDE_MODULE_DIR} into ${EXTERNAL_CONFIG_DIR}..."
    cp -a "${OVERRIDE_MODULE_DIR}/." "${EXTERNAL_CONFIG_DIR}/"
  fi

  # Switch base config source to the external volume
  echo "Using external config from ${EXTERNAL_CONFIG_DIR}"
  APP_CONFIG_DIR="${EXTERNAL_CONFIG_DIR}"
  
  # Re-ensure ownership of everything in the config dir after copies
  chown -R lareferencia:lareferencia "${EXTERNAL_CONFIG_DIR}"
fi

is_truthy() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# If it's the shell module and idle is requested, wait
if [ "${APP_MODULE}" = "lareferencia-shell" ] && is_truthy "${SHELL_IDLE}" && [ "${#APP_ARGS[@]}" -eq 0 ]; then
  echo "Starting ${APP_MODULE} in idle mode (SHELL_IDLE=true)."
  exec gosu lareferencia tail -f /dev/null
fi

# Build isolated runtime config
rm -rf "${APP_RUN_CONFIG_DIR}"
mkdir -p "${APP_RUN_CONFIG_DIR}"
if [ -d "${APP_CONFIG_DIR}" ]; then
  echo "Copying config from ${APP_CONFIG_DIR} to runtime dir"
  cp -a "${APP_CONFIG_DIR}/." "${APP_RUN_CONFIG_DIR}/"
  chown -R lareferencia:lareferencia "${APP_RUN_CONFIG_DIR}"
fi

JAVA_OVERRIDE_PROPS=()

# --- DYNAMIC ENVIRONMENT VARIABLES ---
# These have lower priority than 99-docker.properties
if [ -n "${SPRING_PROFILES_ACTIVE:-}" ]; then
  echo "Environment Active Profiles: ${SPRING_PROFILES_ACTIVE}"
  JAVA_OVERRIDE_PROPS+=("-Dspring.profiles.active=${SPRING_PROFILES_ACTIVE}")
fi
if [ -n "${ACTIONS_BEANS_FILENAME:-}" ]; then
  echo "Environment Actions File: ${ACTIONS_BEANS_FILENAME}"
  JAVA_OVERRIDE_PROPS+=("-Dactions.beans.filename=${ACTIONS_BEANS_FILENAME}")
fi

# --- NEW FLEXIBLE OVERRIDES ---
OVERRIDE_MODULE_DIR="${DOCKER_OVERRIDES_DIR}/${APP_MODULE}"
if [ -d "${OVERRIDE_MODULE_DIR}" ]; then
  echo "Applying custom overrides from ${OVERRIDE_MODULE_DIR}"
  # Merge override directory into the run config dir
  cp -a "${OVERRIDE_MODULE_DIR}/." "${APP_RUN_CONFIG_DIR}/"
  
  # Special case: If 99-docker.properties exists, we extract its values as System Properties
  # to ensure they have priority over classpath properties and environment variables.
  OVERRIDE_FILE="${APP_RUN_CONFIG_DIR}/99-docker.properties"
  if [ -f "${OVERRIDE_FILE}" ]; then
    echo "Processing system property overrides from 99-docker.properties"
    mkdir -p "${APP_RUN_CONFIG_DIR}/application.properties.d"
    # We copy first, then read to ensure it exists in both places if needed
    cp "${OVERRIDE_FILE}" "${APP_RUN_CONFIG_DIR}/application.properties.d/99-docker.properties"
    
    while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
      line="$(printf '%s' "${raw_line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]]; then continue; fi
      key="${line%%=*}"; value="${line#*=}"
      key="$(printf '%s' "${key}" | sed -e 's/[[:space:]]*$//')"
      value="$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//')"
      if [ -n "${key}" ]; then 
        # Overwrite if already added (from env variables)
        found=false
        for i in "${!JAVA_OVERRIDE_PROPS[@]}"; do
          if [[ "${JAVA_OVERRIDE_PROPS[$i]}" == "-D${key}="* ]]; then
            JAVA_OVERRIDE_PROPS[$i]="-D${key}=${value}"
            found=true
            break
          fi
        done
        if [ "$found" = false ]; then
          JAVA_OVERRIDE_PROPS+=("-D${key}=${value}")
        fi
      fi
    done < "${OVERRIDE_FILE}"
    rm "${OVERRIDE_FILE}"
  fi
fi

cd "${APP_DIR}"

# RUN LOGIC
if [ -f "application/app.jar" ]; then
  echo "Starting ${APP_MODULE} via single JAR (as lareferencia)..."
  exec gosu lareferencia java ${JAVA_OPTS:-} "${JAVA_OVERRIDE_PROPS[@]}" -Dapp.config.dir="${APP_RUN_CONFIG_DIR}" -jar application/app.jar "${APP_ARGS[@]}"
else
  echo "Starting ${APP_MODULE} via JarLauncher (Layers) (as lareferencia)..."
  LAUNCHER="org.springframework.boot.loader.launch.JarLauncher"
  if ! java -cp . "${LAUNCHER}" --help >/dev/null 2>&1; then
      LAUNCHER="org.springframework.boot.loader.JarLauncher"
  fi
  exec gosu lareferencia java ${JAVA_OPTS:-} "${JAVA_OVERRIDE_PROPS[@]}" -Dapp.config.dir="${APP_RUN_CONFIG_DIR}" "${LAUNCHER}" "${APP_ARGS[@]}"
fi
