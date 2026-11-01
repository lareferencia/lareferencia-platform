#!/usr/bin/env bash
# =============================================================================
# wizard/backup.sh — View: "System Backup" screen (logic in lib/backup.sh).
# =============================================================================

_backup_view::error() {
  gum style --foreground 204 "❌ Error: $*"
}

wizard::backup_screen() {
  ui::clear_screen
  ui::title "💾 System Backup"
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

  echo "Where should the backups be saved?"
  local dest_dir
  dest_dir=$(gum input --placeholder "Destination path" --value "$(backup::default_destination)") || true
  if [ -z "${dest_dir}" ]; then
    echo "Aborted."
    sleep 1
    return 0
  fi

  if ! backup::prepare_destination "${dest_dir}"; then
    echo
    _backup_view::error "The current user does not have write permissions for '${dest_dir}'."
    gum style --foreground 245 "Please grant permissions (e.g. sudo mkdir -p ${dest_dir} && sudo chown \$(whoami) ${dest_dir}) or choose another path."
    ui::pause "Press Enter to return..."
    return 0
  fi

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
