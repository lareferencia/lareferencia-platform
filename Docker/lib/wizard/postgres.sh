#!/usr/bin/env bash
# =============================================================================
# wizard/postgres.sh — View: dialogs for PostgreSQL major version upgrades.
# The routines themselves live in lib/database.sh (pg::*).
#
#   wizard::postgres_preflight      asked before any action that starts postgres
#   wizard::postgres_screen         "🐘 PostgreSQL" menu: status/upgrade/rollback/remove
#   wizard::offer_legacy_removal    asked once per wizard session after the
#                                   retention period (LR_PG_LEGACY_RETENTION_SECONDS)
#   wizard::postgres_menu_label
# =============================================================================

_wizard::pg_upgrade() {
  local from to
  from="$(pg::data_major)"
  to="$(pg::target_major)"

  echo
  gum style --foreground 222 --border rounded --border-foreground 222 --padding "0 1" \
    "The migration will:" \
    " 1. stop the platform (downtime grows with the database size)" \
    " 2. dump every database from PostgreSQL ${from}" \
    " 3. keep the PostgreSQL ${from} directory untouched for rollback" \
    " 4. restore into PostgreSQL ${to} and compare row counts of every table" \
    " Any failure restores PostgreSQL ${from} automatically."
  gum confirm "Migrate PostgreSQL ${from} → ${to} now?" || return 1

  if wizard::run_command "PostgreSQL Upgrade ${from} → ${to}" postgres upgrade --yes; then
    gum style --foreground 114 "✅ PostgreSQL ${to} in use. A rollback copy of PostgreSQL ${from} was kept:" \
      "   $(pg::legacy_path)"
    return 0
  fi
  ui::pause "Upgrade failed (details above). Press Enter to continue..."
  return 1
}

_wizard::pg_rollback() {
  local from to legacy
  from="$(pg::last_migration from_major)"
  to="$(pg::last_migration to_major)"
  legacy="$(pg::last_migration legacy_dir)"

  echo
  gum style --foreground 204 --border rounded --border-foreground 204 --padding "0 1" \
    "Rollback to PostgreSQL ${from}" \
    "" \
    "Will be RESTORED: $(pg::path "${legacy}/data")" \
    "Will be SET ASIDE (kept): $(pg::path data)  (PostgreSQL ${to})" \
    "" \
    "⚠️  Data changed after the migration exists only in PostgreSQL ${to}" \
    "   and will NOT be visible after the rollback."
  gum confirm "Go back to PostgreSQL ${from}?" || return 1

  wizard::run_command "PostgreSQL Rollback to ${from}" postgres rollback --yes
  ui::pause
}

_wizard::pg_remove_legacy() {
  local legacy from to
  legacy="$(pg::legacy_dir)"
  [ -n "${legacy}" ] || return 1
  from="$(pg::last_migration from_major)"
  to="$(pg::last_migration to_major)"

  echo
  gum style --border rounded --padding "0 1" \
    "$(printf '%s' "${C_RED}🗑️  Will be DELETED:${C_RESET} $(pg::path "${legacy}")")" \
    "    PostgreSQL ${from} data + migration dumps ($(pg::dir_size "${legacy}"))" \
    "" \
    "$(printf '%s' "${C_GREEN}✅ Will be KEPT:${C_RESET}    $(pg::path data)")" \
    "    PostgreSQL ${to}, in use ($(pg::dir_size data))" \
    "" \
    "After this, going back to PostgreSQL ${from} is no longer possible."
  gum confirm "Delete the PostgreSQL ${from} directory?" || return 1

  pg::remove_legacy
  sleep 1.5
}

# Returns 0 when the action that starts postgres may proceed.
wizard::postgres_preflight() {
  local status
  status="$(pg::status)"

  case "${status}" in
    fresh|ok)
      return 0
      ;;

    upgrade_required)
      local from to old_image choice
      from="$(pg::data_major)"
      to="$(pg::image_major "$(pg::configured_image)")"
      old_image="$(pg::image_for_major "${from}")"   # only for the label
      echo
      gum style --foreground 222 --bold "🐘 This platform version uses PostgreSQL ${to}, but your data is PostgreSQL ${from}."
      choice=$(gum choose \
        "⬆️  Migrate to PostgreSQL ${to} now (keeps a rollback copy)" \
        "📌 Keep PostgreSQL ${from} for now (pins ${old_image} in .env)" \
        "❌ Cancel") || return 1
      case "${choice}" in
        "⬆️"*) _wizard::pg_upgrade ;;
        "📌"*)
          pg::pin_data_version >/dev/null
          gum style --foreground 114 "📌 PostgreSQL ${from} pinned. Upgrade later from the menu: 🐘 PostgreSQL."
          sleep 1.5
          return 0
          ;;
        *) return 1 ;;
      esac
      ;;

    interrupted)
      echo
      gum style --foreground 204 --bold "🐘 A PostgreSQL upgrade was interrupted. The previous cluster must be restored first."
      if gum confirm "Restore PostgreSQL $(pg::last_migration from_major) now?"; then
        wizard::run_command "PostgreSQL Rollback" postgres rollback --yes && return 0
      fi
      return 1
      ;;

    incompatible)
      echo
      gum style --foreground 204 --bold \
        "🐘 Your data is PostgreSQL $(pg::data_major), newer than the configured image $(pg::configured_image)."
      if pg::is_pinned && gum confirm "Remove the LR_POSTGRES_IMAGE pin and use $(pg::default_image)?"; then
        pg::unpin
        wizard::postgres_preflight
        return
      fi
      return 1
      ;;
  esac
}

wizard::offer_legacy_removal() {
  pg::legacy_removal_due || return 0
  ui::clear_screen
  ui::title "🐘 PostgreSQL $(pg::last_migration to_major) has been in use since $(pg::format_date "$(pg::last_migration migrated_at)")"
  echo
  echo "The PostgreSQL $(pg::last_migration from_major) directory is still kept for rollback."
  _wizard::pg_remove_legacy || true
}

wizard::postgres_menu_label() {
  local data_major
  data_major="$(pg::data_major)"
  if [ -z "${data_major}" ]; then
    echo "🐘 PostgreSQL"
  elif pg::upgrade_available; then
    echo "🐘 PostgreSQL ${data_major} [upgrade to $(pg::target_major) available]"
  else
    echo "🐘 PostgreSQL ${data_major}"
  fi
}

wizard::postgres_screen() {
  while true; do
    ui::clear_screen
    ui::title "🐘 PostgreSQL"
    echo
    pg::describe
    echo

    local options=()
    pg::upgrade_available && options+=("⬆️  Upgrade to PostgreSQL $(pg::target_major)")
    pg::rollback_available && options+=("↩️  Roll back to PostgreSQL $(pg::last_migration from_major)")
    pg::rollback_available && options+=("🗑️  Delete PostgreSQL $(pg::last_migration from_major) rollback copy")
    options+=("🔙 Back")

    local choice
    choice=$(gum choose "${options[@]}") || return 0
    case "${choice}" in
      "⬆️"*)  _wizard::pg_upgrade || true; ui::pause ;;
      "↩️"*)  _wizard::pg_rollback || true ;;
      "🗑️"*)  _wizard::pg_remove_legacy || true ;;
      *)      return 0 ;;
    esac
  done
}
