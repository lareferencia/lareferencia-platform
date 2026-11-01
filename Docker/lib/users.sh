#!/usr/bin/env bash
# =============================================================================
# users.sh — "HarvesterUsers": accounts of the harvester admin (local_user table)
# and the default account of users.properties.
#
# Public API:
#   users::database_available         true when the postgres container runs
#   users::list                       prints the users table
#   users::create_admin <username>    interactive (asks the password)
#   users::reset_password <username>  interactive (asks the password)
#   users::delete <username>
#   users::remove_default_admin       drops "admin=" from users.properties
# =============================================================================

USERS_PROPERTIES="${ROOT_DIR}/lareferencia-lrharvester-app/config/users.properties"

users::database_available() {
  compose::is_running postgres
}

users::list() {
  db::psql "SELECT username, global_role, enabled, created_at FROM local_user;"
}

users::create_admin() {
  lrshell::run_interactive "security-create-admin" "$1"
}

users::reset_password() {
  lrshell::run_interactive "security-reset-password" "$1"
}

# The username is passed as a psql variable (quoted by psql), never
# concatenated into the SQL text.
users::delete() {
  printf '%s\n' "DELETE FROM local_user WHERE username = :'username';" \
    | dc exec -T postgres psql -v ON_ERROR_STOP=1 -v username="$1" -U "${DB_USER}" -d "${DB_NAME}"
}

# The wizard never keeps the default "admin" account of users.properties.
users::remove_default_admin() {
  [ -f "${USERS_PROPERTIES}" ] || return 0
  sed -i.bak '/^admin=/d' "${USERS_PROPERTIES}" 2>/dev/null || sed -i '/^admin=/d' "${USERS_PROPERTIES}"
  rm -f "${USERS_PROPERTIES}.bak"
}
