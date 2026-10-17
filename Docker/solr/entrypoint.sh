#!/bin/bash
set -euo pipefail

SOLR_DATA_DIR="/var/solr/data"
SOLR_LOG_DIR="/var/solr/logs"
SOLR_CACHE_DIR="/var/solr/cache"
SOLR_TEMPLATE_DIR="/opt/lr-solr-cores"
SOLR_JARS_TEMPLATE_DIR="/opt/lr-solr-jars"
SOLR_IMPORT_TEMPLATE_DIR="/opt/lr-solr-import"
INIT_MARKER="${SOLR_DATA_DIR}/.lr_initialized"

export SOLR_MODULES="${SOLR_MODULES:-analysis-extras}"
export SOLR_SECURITY_MANAGER_ENABLED="${SOLR_SECURITY_MANAGER_ENABLED:-false}"
export SOLR_OPTS="${SOLR_OPTS:-} -Ddisable.configEdit=true -Dsolr.config.lib.enabled=true"

# Ensure base directories exist
mkdir -p "${SOLR_DATA_DIR}" "${SOLR_LOG_DIR}" "${SOLR_CACHE_DIR}" /var/solr/vendor /import

# Setup vendor modules link
if [ ! -e /var/solr/vendor/modules ]; then
  ln -s /opt/solr/modules /var/solr/vendor/modules
fi

# Log source revision metadata if present
log_build_info() {
  if [ -f "${SOLR_TEMPLATE_DIR}/build-info.properties" ]; then
    echo "--- Solr Cores Metadata ---"
    cat "${SOLR_TEMPLATE_DIR}/build-info.properties"
    echo "---------------------------"
    cp -f "${SOLR_TEMPLATE_DIR}/build-info.properties" "${SOLR_DATA_DIR}/.lr_cores_build_info" 2>/dev/null || true
  fi
}

# Update core configurations without touching index data (/data/ directory)
update_cores_config() {
  echo "Updating Solr core configurations from ${SOLR_TEMPLATE_DIR}..."
  
  if [ ! -d "${SOLR_TEMPLATE_DIR}" ]; then
    echo "Error: Template directory ${SOLR_TEMPLATE_DIR} not found!" >&2
    return 1
  fi

  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"

  for core_dir in "${SOLR_TEMPLATE_DIR}"/*; do
    if [ ! -d "${core_dir}" ]; then
      continue
    fi
    local core
    core="$(basename "${core_dir}")"
    
    # Skip non-core directories or hidden files
    if [[ "${core}" == .* ]] || [ "${core}" = "jars" ] || [ "${core}" = "import" ]; then
      continue
    fi

    local target_core="${SOLR_DATA_DIR}/${core}"

    if [ -d "${target_core}" ]; then
      # Core already exists: preserve index data and replace conf/ with backup
      if [ -d "${target_core}/conf" ]; then
        local backup_conf="${target_core}/conf.bak.${timestamp}"
        echo "Backing up existing '${core}' conf to ${backup_conf}..."
        cp -a "${target_core}/conf" "${backup_conf}"
        rm -rf "${target_core}/conf"
      fi

      if [ -d "${core_dir}/conf" ]; then
        echo "Installing updated '${core}' conf from template..."
        cp -a "${core_dir}/conf" "${target_core}/conf"
      fi

      if [ -f "${core_dir}/core.properties" ]; then
        cp -f "${core_dir}/core.properties" "${target_core}/core.properties"
      fi

      echo "Core '${core}' configuration updated successfully. Index data in '${target_core}/data' preserved."
    else
      # Core does not exist yet: copy full template
      echo "Core '${core}' not found in data directory. Initializing from template..."
      cp -a "${core_dir}" "${target_core}"
    fi
  done

  # Sync jars to data directory
  if [ -d "${SOLR_JARS_TEMPLATE_DIR}" ]; then
    mkdir -p "${SOLR_DATA_DIR}/jars"
    cp -ru "${SOLR_JARS_TEMPLATE_DIR}/." "${SOLR_DATA_DIR}/jars/"
  fi

  # Sync import templates
  if [ -d "${SOLR_IMPORT_TEMPLATE_DIR}" ]; then
    cp -ru "${SOLR_IMPORT_TEMPLATE_DIR}/." /import/
  fi

  # Update metadata
  if [ -f "${SOLR_TEMPLATE_DIR}/build-info.properties" ]; then
    cp -f "${SOLR_TEMPLATE_DIR}/build-info.properties" "${SOLR_DATA_DIR}/.lr_cores_build_info" 2>/dev/null || true
  fi

  touch "${INIT_MARKER}"

  # Fix permissions
  chown -R solr:solr "${SOLR_DATA_DIR}" "${SOLR_LOG_DIR}" "${SOLR_CACHE_DIR}" /var/solr/vendor /import

  # If Solr is running, trigger CoreAdmin RELOAD for all cores
  if curl -s -f "http://localhost:8983/solr/admin/info/system" >/dev/null 2>&1; then
    echo "Solr instance is running. Reloading cores via CoreAdmin API..."
    for core_dir in "${SOLR_TEMPLATE_DIR}"/*; do
      [ -d "${core_dir}" ] || continue
      local c
      c="$(basename "${core_dir}")"
      if [ -d "${SOLR_DATA_DIR}/${c}" ]; then
        local reload_resp
        reload_resp="$(curl -s "http://localhost:8983/solr/admin/cores?action=RELOAD&core=${c}")"
        echo "Reloaded core '${c}': ${reload_resp}"
      fi
    done
  else
    echo "Note: Solr process is not currently running. New configurations will be loaded on next startup."
  fi
}

# Execute custom system commands directly if provided
if [ "$#" -gt 0 ] && [ "$1" != "update-config" ] && [ "$1" != "solr" ] && [ "$1" != "solr-foreground" ] && command -v "$1" >/dev/null 2>&1; then
  exec "$@"
fi

# Check if entrypoint was invoked as a CLI utility command
if [ "${1:-}" = "update-config" ]; then
  update_cores_config
  exit 0
fi

# Fresh initialization of Solr cores from template if marker is missing
if [ ! -f "${INIT_MARKER}" ]; then
  echo "Initializing Solr cores from ${SOLR_TEMPLATE_DIR}..."
  log_build_info
  cp -ru "${SOLR_TEMPLATE_DIR}/." "${SOLR_DATA_DIR}/"
  touch "${INIT_MARKER}"
elif [ "${SOLR_UPDATE_CONFIG:-false}" = "true" ]; then
  echo "SOLR_UPDATE_CONFIG=true detected. Updating core configurations on startup..."
  log_build_info
  update_cores_config
else
  log_build_info
fi

# Always sync jars to the data directory to ensure they are available for the cores
if [ -d "${SOLR_JARS_TEMPLATE_DIR}" ]; then
  mkdir -p "${SOLR_DATA_DIR}/jars"
  cp -ru "${SOLR_JARS_TEMPLATE_DIR}/." "${SOLR_DATA_DIR}/jars/"
fi

# Always sync import templates
if [ -d "${SOLR_IMPORT_TEMPLATE_DIR}" ]; then
  cp -ru "${SOLR_IMPORT_TEMPLATE_DIR}/." /import/
fi

# Ensure solr user owns everything it needs to write to
echo "Fixing permissions for solr user..."
chown -R solr:solr "${SOLR_DATA_DIR}" "${SOLR_LOG_DIR}" "${SOLR_CACHE_DIR}" /var/solr/vendor /import

# Execute Solr as the solr user using gosu
echo "Starting Solr as solr user (via gosu)..."
exec gosu solr /opt/solr/bin/solr start -f -s "${SOLR_DATA_DIR}" -p 8983
