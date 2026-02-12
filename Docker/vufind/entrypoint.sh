#!/bin/sh
set -eu

VUFIND_HOME="${VUFIND_HOME:-/usr/local/vufind}"
VUFIND_LOCAL_DIR="${VUFIND_LOCAL_DIR:-$VUFIND_HOME/local/docker}"
VUFIND_BASEPATH="${VUFIND_BASEPATH:-/vufind}"
VUFIND_SITE_URL="${VUFIND_SITE_URL:-http://localhost:8080}"
VUFIND_THEME="${VUFIND_THEME:-bootstrap5}"
VUFIND_NOILS_MODE="${VUFIND_NOILS_MODE:-ils-none}"
VUFIND_ENV="${VUFIND_ENV:-development}"
VUFIND_SYSTEM_DEBUG="${VUFIND_SYSTEM_DEBUG:-true}"

VUFIND_PHP_DISPLAY_ERRORS="${VUFIND_PHP_DISPLAY_ERRORS:-1}"
VUFIND_PHP_DISPLAY_STARTUP_ERRORS="${VUFIND_PHP_DISPLAY_STARTUP_ERRORS:-1}"
VUFIND_PHP_ERROR_REPORTING="${VUFIND_PHP_ERROR_REPORTING:-E_ALL}"
VUFIND_PHP_HTML_ERRORS="${VUFIND_PHP_HTML_ERRORS:-1}"

VUFIND_DB_HOST="${VUFIND_DB_HOST:-db}"
VUFIND_DB_PORT="${VUFIND_DB_PORT:-3306}"
VUFIND_DB_NAME="${VUFIND_DB_NAME:-vufind}"
VUFIND_DB_USER="${VUFIND_DB_USER:-vufind}"
VUFIND_DB_PASSWORD="${VUFIND_DB_PASSWORD:-vufind}"
VUFIND_DB_ROOT_USER="${VUFIND_DB_ROOT_USER:-root}"
VUFIND_DB_ROOT_PASSWORD="${VUFIND_DB_ROOT_PASSWORD:-root}"

VUFIND_SOLR_URL="${VUFIND_SOLR_URL:-http://solr:8983/solr}"

export VUFIND_ENV

normalize_bool() {
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${value}" in
    1|true|yes|on)
      echo "true"
      ;;
    0|false|no|off)
      echo "false"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

configure_php_debug() {
  php_ini_file="/usr/local/etc/php/conf.d/zz-vufind-debug.ini"
  cat > "${php_ini_file}" <<EOF
display_errors=${VUFIND_PHP_DISPLAY_ERRORS}
display_startup_errors=${VUFIND_PHP_DISPLAY_STARTUP_ERRORS}
error_reporting=${VUFIND_PHP_ERROR_REPORTING}
html_errors=${VUFIND_PHP_HTML_ERRORS}
log_errors=On
EOF
}

wait_for_db() {
  echo "Waiting for MariaDB at ${VUFIND_DB_HOST}:${VUFIND_DB_PORT}..."
  until mysqladmin ping \
    --host="${VUFIND_DB_HOST}" \
    --port="${VUFIND_DB_PORT}" \
    --user="${VUFIND_DB_ROOT_USER}" \
    --password="${VUFIND_DB_ROOT_PASSWORD}" \
    --silent; do
    sleep 2
  done
}

wait_for_solr() {
  echo "Waiting for Solr at ${VUFIND_SOLR_URL}..."
  until curl --silent --fail "${VUFIND_SOLR_URL}/admin/info/system?wt=json" >/dev/null; do
    sleep 2
  done
}

set_ini_value() {
  section="$1"
  key="$2"
  value="$3"
  file="$4"
  tmp_file="$(mktemp)"

  awk -v section="${section}" -v key="${key}" -v value="${value}" '
    BEGIN {
      in_section = 0
      section_found = 0
      key_written = 0
    }
    /^\[[^]]+\]$/ {
      if (in_section && !key_written) {
        print key " = " value
        key_written = 1
      }
      if ($0 == "[" section "]") {
        in_section = 1
        section_found = 1
      } else {
        in_section = 0
      }
      print
      next
    }
    {
      if (in_section && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=")) {
        print key " = " value
        key_written = 1
        next
      }
      print
    }
    END {
      if (!section_found) {
        print ""
        print "[" section "]"
        print key " = " value
      } else if (in_section && !key_written) {
        print key " = " value
      }
    }
  ' "${file}" > "${tmp_file}"

  mv "${tmp_file}" "${file}"
}

cd "${VUFIND_HOME}"

mkdir -p \
  "${VUFIND_LOCAL_DIR}/cache/cli" \
  "${VUFIND_LOCAL_DIR}/cache/public" \
  "${VUFIND_LOCAL_DIR}/config" \
  "${VUFIND_LOCAL_DIR}/config/vufind" \
  "${VUFIND_LOCAL_DIR}/harvest" \
  "${VUFIND_LOCAL_DIR}/import"
chmod -R 777 "${VUFIND_LOCAL_DIR}/cache" || true

configure_php_debug

if [ ! -f "${VUFIND_HOME}/vendor/autoload.php" ]; then
  echo "Installing Composer dependencies..."
  composer install --no-interaction --prefer-dist --no-scripts
fi

if [ ! -f "${VUFIND_LOCAL_DIR}/.installed" ]; then
  echo "Running VuFind installer for docker local dir..."
  php install.php \
    --non-interactive \
    --overridedir="${VUFIND_LOCAL_DIR}" \
    --basepath="${VUFIND_BASEPATH}" \
    --solr-port=8983 \
    --skip-backups \
    --no-apache-help
  touch "${VUFIND_LOCAL_DIR}/.installed"
fi

CONFIG_INI="${VUFIND_LOCAL_DIR}/config/vufind/config.ini"
if [ ! -f "${CONFIG_INI}" ]; then
  cp "${VUFIND_HOME}/config/vufind/config.ini" "${CONFIG_INI}"
fi

DB_DSN="mysql://${VUFIND_DB_USER}:${VUFIND_DB_PASSWORD}@${VUFIND_DB_HOST}:${VUFIND_DB_PORT}/${VUFIND_DB_NAME}"
set_ini_value "System" "autoConfigure" "false" "${CONFIG_INI}"
set_ini_value "System" "debug" "$(normalize_bool "${VUFIND_SYSTEM_DEBUG}")" "${CONFIG_INI}"
set_ini_value "Site" "url" "${VUFIND_SITE_URL}" "${CONFIG_INI}"
set_ini_value "Site" "theme" "${VUFIND_THEME}" "${CONFIG_INI}"
set_ini_value "Catalog" "driver" "NoILS" "${CONFIG_INI}"
set_ini_value "Index" "url" "${VUFIND_SOLR_URL}" "${CONFIG_INI}"
set_ini_value "Database" "database" "${DB_DSN}" "${CONFIG_INI}"

NOILS_INI="${VUFIND_LOCAL_DIR}/config/vufind/NoILS.ini"
if [ ! -f "${NOILS_INI}" ]; then
  cp "${VUFIND_HOME}/config/vufind/NoILS.ini" "${NOILS_INI}"
fi
sed -E -i "s|^mode[[:space:]]*=.*$|mode = ${VUFIND_NOILS_MODE}|" "${NOILS_INI}"

IMPORT_MAIN="${VUFIND_LOCAL_DIR}/import/import.properties"
if [ -f "${IMPORT_MAIN}" ]; then
  sed -E -i "s|^solr.hosturl[[:space:]]*=.*$|solr.hosturl = ${VUFIND_SOLR_URL}/biblio/update|" "${IMPORT_MAIN}"
fi

IMPORT_AUTH="${VUFIND_LOCAL_DIR}/import/import_auth.properties"
if [ -f "${IMPORT_AUTH}" ]; then
  sed -E -i "s|^solr.hosturl[[:space:]]*=.*$|solr.hosturl = ${VUFIND_SOLR_URL}/authority/update|" "${IMPORT_AUTH}"
fi

wait_for_db

DB_EXISTS="$(mysql \
  --host="${VUFIND_DB_HOST}" \
  --port="${VUFIND_DB_PORT}" \
  --user="${VUFIND_DB_ROOT_USER}" \
  --password="${VUFIND_DB_ROOT_PASSWORD}" \
  --batch \
  --skip-column-names \
  --execute="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${VUFIND_DB_NAME}'" \
  || true)"

if [ -z "${DB_EXISTS}" ]; then
  echo "Initializing VuFind database..."
  php public/index.php install/database \
    --dbHost="${VUFIND_DB_HOST}:${VUFIND_DB_PORT}" \
    --vufindHost="%" \
    --rootUser="${VUFIND_DB_ROOT_USER}" \
    --rootPass="${VUFIND_DB_ROOT_PASSWORD}" \
    "${VUFIND_DB_NAME}" \
    "${VUFIND_DB_USER}" \
    "${VUFIND_DB_PASSWORD}"
fi

wait_for_solr

exec "$@"
