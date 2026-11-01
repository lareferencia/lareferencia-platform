#!/usr/bin/env bash
# =============================================================================
# wizard/users.sh — View: "Manage Harvester Users" (logic in lib/users.sh).
# =============================================================================

# Each action returns 1 when the user cancelled (back straight to the menu).

_users_view::require_database() {
  users::database_available && return 0
  echo "Postgres container is not running."
  return 1
}

_users_view::ask_username() {
  local username
  username=$(gum input --placeholder "$1") || true
  [ -n "${username}" ] || return 1
  echo "${username}"
}

_users_view::list() {
  echo -e "\n${C_CYAN}Current Users in Database:${C_RESET}"
  _users_view::require_database || return 0
  users::list || echo "Failed to query database."
}

_users_view::create_admin() {
  local username
  username="$(_users_view::ask_username "Admin Username")" || return 1
  echo "Launching Spring Shell to create admin..."
  users::create_admin "${username}" || true
}

_users_view::reset_password() {
  local username
  username="$(_users_view::ask_username "Username to reset")" || return 1
  echo "Launching Spring Shell to reset password..."
  users::reset_password "${username}" || true
}

_users_view::delete() {
  local username
  username="$(_users_view::ask_username "Username to delete")" || return 1
  gum confirm "Are you sure you want to delete user ${username}?" || return 0
  _users_view::require_database || return 0
  if users::delete "${username}"; then
    echo -e "${C_GREEN}User deleted.${C_RESET}"
  else
    echo -e "${C_RED}Failed to delete user.${C_RESET}"
  fi
}

wizard::users_screen() {
  while true; do
    ui::clear_screen
    ui::title "👥 Manage Harvester Users (V5 SQL)"
    echo

    local choice action
    choice=$(gum choose \
      "📋 List Users" \
      "👑 Create First Admin" \
      "🔑 Reset Password" \
      "🗑️  Delete User" \
      "🔙 Back to Main Menu") || true

    case "${choice}" in
      "📋 List Users")         action=_users_view::list ;;
      "👑 Create First Admin") action=_users_view::create_admin ;;
      "🔑 Reset Password")     action=_users_view::reset_password ;;
      "🗑️  Delete User")       action=_users_view::delete ;;
      *)                       return ;;
    esac

    "${action}" || continue
    echo
    ui::pause
  done
}
