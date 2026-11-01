#!/usr/bin/env bash
# =============================================================================
# wizard/modules.sh — View: "Manage Modules" multi-select (rules in lib/modules.sh).
# =============================================================================

wizard::modules_screen() {
  ui::clear_screen
  ui::header

  local m pre_selected=()
  for m in "${MODULES_OPTIONAL[@]}"; do
    module::is_on "${m}" && pre_selected+=("${m}")
  done

  echo -e "${C_BOLD}📦 MODULE MANAGEMENT${C_RESET}"
  echo -e "${C_GRAY}The 'core' module (postgres database) is always active.${C_RESET}\n"

  local gum_args=(--no-limit)
  if [ "${#pre_selected[@]}" -gt 0 ]; then
    gum_args+=(--selected="$(list::join , "${pre_selected[@]}")")
  fi

  local choices
  choices=$(gum choose "${gum_args[@]}" \
    --header "Instructions: [Space] Toggles selection | [Enter] Confirms all" \
    --item.foreground 245 --selected.foreground 114 --cursor.foreground 80 \
    "${MODULES_OPTIONAL[@]}")

  # shellcheck disable=SC2086 # one module per word
  module::apply_selection ${choices}

  echo -e "\n${C_CYAN}Configuration updated.${C_RESET}"
  sleep 1
}
