#!/bin/sh
set -eu

SOLR_DATA_DIR="/var/solr/data"
SOLR_TEMPLATE_DIR="/opt/lr-solr-cores"
SOLR_JARS_TEMPLATE_DIR="/opt/lr-solr-jars"
SOLR_IMPORT_TEMPLATE_DIR="/opt/lr-solr-import"
INIT_MARKER="${SOLR_DATA_DIR}/.lr_initialized"

export SOLR_MODULES="${SOLR_MODULES:-analysis-extras}"
export SOLR_SECURITY_MANAGER_ENABLED="${SOLR_SECURITY_MANAGER_ENABLED:-false}"
export SOLR_OPTS="${SOLR_OPTS:-} -Ddisable.configEdit=true -Dsolr.config.lib.enabled=true"

mkdir -p "${SOLR_DATA_DIR}"
mkdir -p /var/solr/vendor
mkdir -p /import

if [ ! -f "${INIT_MARKER}" ]; then
  echo "Initializing Solr cores (biblio, oai) from Docker/solr/cores..."
  rm -rf "${SOLR_DATA_DIR}/biblio" "${SOLR_DATA_DIR}/oai"
  cp -a "${SOLR_TEMPLATE_DIR}/biblio" "${SOLR_DATA_DIR}/biblio"
  cp -a "${SOLR_TEMPLATE_DIR}/oai" "${SOLR_DATA_DIR}/oai"
  touch "${INIT_MARKER}"
fi

# biblio core expects custom VuFind jars in ../jars and SolrMarc libs in /import.
if [ -d "${SOLR_JARS_TEMPLATE_DIR}" ]; then
  rm -rf "${SOLR_DATA_DIR}/jars"
  cp -a "${SOLR_JARS_TEMPLATE_DIR}" "${SOLR_DATA_DIR}/jars"
fi

if [ -d "${SOLR_IMPORT_TEMPLATE_DIR}" ]; then
  cp -a "${SOLR_IMPORT_TEMPLATE_DIR}/." /import/
fi

if [ ! -e /var/solr/vendor/modules ]; then
  ln -s /opt/solr/modules /var/solr/vendor/modules
fi

chown -R solr:solr "${SOLR_DATA_DIR}"
chown -R solr:solr /var/solr/vendor
chown -R solr:solr /import

exec su -s /bin/sh solr -c "/opt/solr/bin/solr start -f -s ${SOLR_DATA_DIR} -p 8983"
