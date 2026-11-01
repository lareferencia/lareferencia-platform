#!/usr/bin/env bash
# =============================================================================
# wizard/backup.sh — View: "System Backup" screen (logic in lib/backup.sh).
#
#   🗄️  Database dump only      dumps now, services keep running, no schedule
#   📦 Full backup plan         sources + configs + volumes + dumps, daily schedule
# =============================================================================

_backup_view::error() {
  gum style --foreground 204 "❌ Error: $*"
}

# Asks for the destination folder. Sets BACKUP_VIEW_DEST; returns 1 when the
# user aborted or the folder is not writable (message already shown).
_backup_view::ask_destination() {
  BACKUP_VIEW_DEST=""
  echo "Where should the backups be saved?"
  local dest_dir
  dest_dir=$(gum input --placeholder "Destination path" --value "$(backup::default_destination)") || true
  if [ -z "${dest_dir}" ]; then
    echo "Aborted."
    sleep 1
    return 1
  fi

  if ! backup::prepare_destination "${dest_dir}"; then
    echo
    _backup_view::error "The current user does not have write permissions for '${dest_dir}'."
    gum style --foreground 245 "Please grant permissions (e.g. sudo mkdir -p ${dest_dir} && sudo chown \$(whoami) ${dest_dir}) or choose another path."
    ui::pause "Press Enter to return..."
    return 1
  fi
  BACKUP_VIEW_DEST="${dest_dir}"
}

# --- Database dump only --------------------------------------------------------------

_backup_view::database_dump() {
  echo
  gum style --foreground 245 \
    "Dumps the databases right now, without stopping any service:" \
    "  • PostgreSQL (harvester)" \
    "  • VuFind MySQL (when vufind-db is running)" \
    "Files are gzip-compressed into <destination>/db_<date>/ with a RESTORE.txt." \
    "The daily backup schedule is not changed."
  echo

  if ! compose::is_running postgres; then
    _backup_view::error "PostgreSQL is not running. Start the platform first (🚀 Start Platform)."
    ui::pause "Press Enter to return..."
    return 0
  fi

  _backup_view::ask_destination || return 0
  local dest_dir="${BACKUP_VIEW_DEST}"

  echo
  if wizard::run_command "Database Dump" backup-db "${dest_dir}"; then
    local saved
    saved="$(backup::latest_db_dump "${dest_dir}")"
    echo
    gum style --foreground 114 "✅ Database dump saved to: ${saved}"
    ls -lh "${saved}" | tail -n +2
    gum style --foreground 245 "How to restore: ${saved}/RESTORE.txt"
  fi
  echo
  ui::pause "Press Enter to return to main menu..."
}

# --- Full backup plan ------------------------------------------------------------------

_backup_view::full_plan() {
  echo
  gum style --foreground 245 "This module configures a full backup of your LA Referencia environment,"
  gum style --foreground 245 "including Source Code (Git), DB Dumps, Indices, and configs."
  gum style --foreground 245 "Target build directories are safely excluded."
  echo

  gum confirm "Do you want to configure the backup plan?" || return 0

  local missing line
  missing="$(backup::missing_requirements)"
  if [ -n "${missing}" ]; then
    while IFS= read -r line; do _backup_view::error "${line}"; done <<< "${missing}"
    ui::pause "Press Enter to return..."
    return 0
  fi

  _backup_view::ask_destination || return 0
  local dest_dir="${BACKUP_VIEW_DEST}"

  local daily=false
  echo
  gum confirm "Enable automatic daily backup via Cron at a random time (03:xx AM)?" && daily=true

  echo
  ui::info "Generating system backup script (.system_backup.sh)..."
  backup::write_script "${dest_dir}"

  if [ "${daily}" = true ]; then
    local method time
    read -r method time <<< "$(backup::schedule_daily)"
    case "${method}" in
      cron)    gum style --foreground 114 "✅ Cron job successfully configured for: ${time} AM" ;;
      systemd) gum style --foreground 114 "✅ Systemd timer successfully configured for: ${time} AM" ;;
    esac
  else
    backup::unschedule
    gum style --foreground 222 "⚠️ Daily automatic backup is disabled."
  fi

  echo
  if gum confirm "Execute the first backup right now?"; then
    echo -e "\n${C_CYAN}Running full backup... (this may take a while)${C_RESET}"
    backup::run
    gum style --foreground 114 "✅ Backup complete! Dest: ${dest_dir}"
  fi

  echo
  ui::pause "Press Enter to return to main menu..."
}

# --- Screen ------------------------------------------------------------------------------

WIZARD_BACKUP_DB_OPTION="🗄️  Database dump only (PostgreSQL + VuFind, now)"
WIZARD_BACKUP_FULL_OPTION="📦 Full backup plan (sources, configs, volumes, dumps + daily schedule)"

wizard::backup_screen() {
  ui::clear_screen
  ui::title "💾 System Backup"
  echo

  local choice
  choice=$(gum choose "${WIZARD_BACKUP_DB_OPTION}" "${WIZARD_BACKUP_FULL_OPTION}" "🔙 Back") || return 0
  case "${choice}" in
    "${WIZARD_BACKUP_DB_OPTION}")   _backup_view::database_dump ;;
    "${WIZARD_BACKUP_FULL_OPTION}") _backup_view::full_plan ;;
    *) return 0 ;;
  esac
}
