#!/bin/sh
set -eu

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

# Ensure directories exist and have correct permissions
mkdir -p "${SOLR_DATA_DIR}" "${SOLR_LOG_DIR}" "${SOLR_CACHE_DIR}"
mkdir -p /var/solr/vendor
mkdir -p /import

# Initialize Solr cores from template if marker is missing
if [ ! -f "${INIT_MARKER}" ]; then
  echo "Initializing Solr cores from ${SOLR_TEMPLATE_DIR}..."
  # Use cp -ru to fill missing cores without overwriting existing data if any
  cp -ru "${SOLR_TEMPLATE_DIR}/." "${SOLR_DATA_DIR}/"
  touch "${INIT_MARKER}"
fi

# Always sync jars to the data directory to ensure they are available for the cores
if [ -d "${SOLR_JARS_TEMPLATE_DIR}" ]; then
  echo "Syncing Solr jars..."
  cp -ru "${SOLR_JARS_TEMPLATE_DIR}/." "${SOLR_DATA_DIR}/jars/"
fi

# Sync import templates
if [ -d "${SOLR_IMPORT_TEMPLATE_DIR}" ]; then
  cp -ru "${SOLR_IMPORT_TEMPLATE_DIR}/." /import/
fi

# Setup vendor modules link
if [ ! -e /var/solr/vendor/modules ]; then
  ln -s /opt/solr/modules /var/solr/vendor/modules
fi

# Ensure solr user owns everything it needs to write to
echo "Fixing permissions for solr user..."
chown -R solr:solr "${SOLR_DATA_DIR}" "${SOLR_LOG_DIR}" "${SOLR_CACHE_DIR}" /var/solr/vendor /import

# Execute Solr as the solr user using gosu
echo "Starting Solr as solr user (via gosu)..."
exec gosu solr /opt/solr/bin/solr start -f -s "${SOLR_DATA_DIR}" -p 8983
