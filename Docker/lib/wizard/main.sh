#!/usr/bin/env bash
# =============================================================================
# wizard/main.sh — View: main menu of the interactive wizard.
#
# The wizard directory only renders screens, collects input and calls the
# services in lib/*.sh (model) or docker.sh commands (controller). No rules,
# file writes, SQL or docker calls live here.
#
# The menu is built as two parallel arrays (label → handler function), so
# reading _wizard::build_menu tells you everything the wizard can do.
# =============================================================================

MENU_LABELS=()
MENU_HANDLERS=()

_menu::add() {
  MENU_LABELS+=("$1")
  MENU_HANDLERS+=("$2")
}

_wizard::build_menu() {
  local cache="OFF" concurrency="Sequential"
  settings::build_cache_enabled    && cache="ON"
  settings::parallel_build_enabled && concurrency="Parallel"

  MENU_LABELS=()
  MENU_HANDLERS=()
  _menu::add "🚀 Start Platform"                       _action::start
  _menu::add "🔄 Rebuild & Start Platform"             _action::rebuild
  _menu::add "🛑 Stop Platform (stop - fast)"          _action::stop
  _menu::add "🧹 Teardown Platform (down - clean)"     _action::teardown
  _menu::add "📦 Manage Modules (on/off)"              wizard::modules_screen
  _menu::add "🏗️ Build Cache: [${cache}]"              wizard::toggle_build_cache
  _menu::add "⚙️ Build Concurrency: [${concurrency}]"  wizard::toggle_build_concurrency
  _menu::add "📝 View Logs (follow)"                   _action::logs
  _menu::add "💻 Enter Container Shell"                wizard::shell_screen
  _menu::add "💾 System Backup"                        wizard::backup_screen
  _menu::add "$(wizard::postgres_menu_label)"          wizard::postgres_screen
  if compose::is_running harvester; then
    _menu::add "👥 Manage Harvester Users"             wizard::users_screen
  fi
  _menu::add "🏷️ Change SERVICE_PREFIX"                wizard::change_service_prefix
  _menu::add "🔌 Change PORT_OFFSET"                   wizard::change_port_offset
  _menu::add "🏗️ Change BUILD_PROFILE"                 wizard::change_build_profile
  _menu::add "⚡ Resource Profile: [$(settings::resource_profile)]" wizard::change_resource_profile
  _menu::add "📡 Configure External Solr"              wizard::configure_external_solr
  _menu::add "🛠️ Run Init-DB (migrations)"             _action::init_db
  _menu::add "🧹 Prune La Referencia Images & Cache"   _action::prune
  _menu::add "🧹 Reset Data (CLEAN ALL)"               _action::reset_data
  _menu::add "🚪 Exit"                                 _action::exit
}

# Prints the handler registered for a label.
_wizard::handler_for() {
  local i
  for i in "${!MENU_LABELS[@]}"; do
    if [ "${MENU_LABELS[$i]}" = "$1" ]; then
      echo "${MENU_HANDLERS[$i]}"
      return 0
    fi
  done
  return 1
}

# --- Screen header ---------------------------------------------------------------

# Banner + configuration line: the fixed part of every wizard screen.
_wizard::draw_overview() {
  local c1 c2 c3
  IFS='|' read -r c1 c2 c3 <<< "$(wizard::dependency_badges)"

  ui::banner \
    "🐳 LA REFERENCIA PLATFORM" \
    "Docker Management Wizard" \
    "Rev: $(git::describe "${ROOT_DIR:-.}")" \
    "" \
    "$(gum join --horizontal --align center "$c1   " "$c2   " "$c3")"

  gum style --foreground 176 "Project: ${COMPOSE_PROJECT_NAME:-lareferencia} | Prefix: $(settings::service_prefix) | Offset: $(settings::port_offset) | Profile: $(settings::build_profile) | Resources: $(settings::resource_profile)"
  echo
}

_wizard::draw_dashboard() {
  _wizard::draw_overview

  wizard::print_module_columns
  echo

  ui::title "⚡ SELECT ACTION"
  echo
}

# --- Running docker.sh commands --------------------------------------------------------

# wizard::run_command <label> <docker.sh args...>
#   Runs a docker.sh command behind the progress panel.
#   Returns its exit status, or 130 when the user pressed Ctrl+C.
wizard::run_command() {
  local label="$1"
  shift
  local status=0
  PROGRESS_HEADER_FN=_wizard::draw_overview   # keep the wizard banner on top
  local cmd
  cmd="$(printf '%q ' "${DOCKER_SH}" "$@")"   # quoted: arguments may contain spaces
  progress::run "${cmd}" "${label}" || status=$?
  PROGRESS_HEADER_FN=""
  trap _action::exit INT TERM   # progress::run replaces the wizard's trap
  if [ "${status}" -eq 130 ]; then
    echo -e "\n${C_YELLOW}Action cancelled by user.${C_RESET}"
    sleep 0.8
  fi
  return "${status}"
}

# Same as wizard::run_command, then waits for Enter (unless cancelled).
_wizard::run_and_pause() {
  local status=0
  wizard::run_command "$@" || status=$?
  [ "${status}" -eq 130 ] && return 130
  gum input --placeholder "Press Enter to continue..." > /dev/null 2>&1 || true
  return "${status}"
}

# --- Actions ------------------------------------------------------------------------

_action::start() {
  wizard::postgres_preflight || return 0
  echo -e "\n${C_GREEN}🚀 Starting the platform...${C_RESET}"
  users::remove_default_admin
  _wizard::run_and_pause "Platform Start" up
}

_action::rebuild() {
  wizard::postgres_preflight || return 0
  echo -e "\n${C_GREEN}🔄 Rebuilding and starting the platform...${C_RESET}"
  users::remove_default_admin
  local args=(up --build --pull-modules)
  settings::build_cache_enabled || args+=(--no-cache)
  _wizard::run_and_pause "Platform Rebuild & Start" "${args[@]}"
}

_action::stop() {
  echo -e "\n${C_RED}🛑 Stopping the platform (preserving containers)...${C_RESET}"
  _wizard::run_and_pause "Stopping Platform" stop
}

_action::teardown() {
  echo -e "\n${C_RED}🧹 Tearing down the platform (removing containers)...${C_RESET}"
  _wizard::run_and_pause "Teardown Platform" down
}

_action::init_db() {
  wizard::postgres_preflight || return 0
  echo -e "\n${C_MAGENTA}🛠️  Running database migrations...${C_RESET}"
  _wizard::run_and_pause "Database Migrations" init-db
}

_action::logs() {
  echo -e "\n${C_CYAN}📝 Showing logs (Ctrl+C to stop)...${C_RESET}"
  trap ':' INT                  # Ctrl+C stops the logs, not the wizard
  "${DOCKER_SH}" logs -f || true
  trap _action::exit INT TERM
  ui::pause "Logs stopped. Press Enter to return to menu..."
}

_action::prune() {
  images::prune_all
  ui::pause "Prune completed. Press Enter to continue..."
}

_action::reset_data() {
  echo
  gum style --foreground 204 --border double --border-foreground 204 --padding "0 1" \
    "⚠️  DANGER ZONE: ALL DATA AND ALL CONTAINERS WILL BE PERMANENTLY DELETED"
  echo -e "${C_YELLOW}This will remove ALL Compose containers for project:${C_RESET} ${COMPOSE_PROJECT_NAME}"
  echo -e "${C_YELLOW}And permanently delete data ONLY in these specific directories:${C_RESET}"
  local p
  for p in $(data::reset_paths); do echo -e "  - ${p}"; done
  echo -e "${C_YELLOW}And any generated/cloned workspace modules.${C_RESET}\n"

  if gum confirm "Are you sure you want to delete these containers and directories?"; then
    "${DOCKER_SH}" reset-data --yes
    ui::pause "System reset completed. Press Enter to continue..."
  fi
}

_action::exit() {
  ui::show_cursor
  echo -e "\n${C_CYAN}Goodbye! 👋${C_RESET}"
  exit 0
}

# --- Main loop -----------------------------------------------------------------------

wizard::main() {
  printf "\033]0;Lareferencia Docker Wizard\007"   # terminal title
  trap _action::exit INT TERM

  # Once per session: offer to delete the old PostgreSQL cluster after the
  # retention period (LR_PG_LEGACY_RETENTION_SECONDS).
  wizard::offer_legacy_removal || true

  while true; do
    ui::clear_screen
    _wizard::draw_dashboard
    _wizard::build_menu

    local choice
    choice=$(gum choose \
      --item.bold --selected.bold --selected.background 80 --selected.foreground 232 \
      --cursor.bold --cursor.foreground 80 \
      "${MENU_LABELS[@]}") || _action::exit   # Ctrl+C / Esc

    local handler
    handler="$(_wizard::handler_for "${choice}")" || _action::exit
    "${handler}" || true
  done
}
