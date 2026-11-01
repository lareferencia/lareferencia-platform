#!/usr/bin/env bash
# =============================================================================
# wizard/shell.sh — View: "Enter Container Shell" screen.
# =============================================================================

WIZARD_LRSHELL_OPTION="🐚 LA Referencia Interactive Shell (lrshell)"
WIZARD_BACK_OPTION="🔙 Back"

wizard::shell_screen() {
  while true; do
    ui::clear_screen
    ui::banner "💻 ENTER CONTAINER SHELL" "Select a running service or access the interactive platform shell"

    local options=("${WIZARD_LRSHELL_OPTION}") svc
    while IFS= read -r svc; do
      [ -n "${svc}" ] && options+=("${svc}")
    done <<< "$(compose::running_services)"
    options+=("${WIZARD_BACK_OPTION}")

    echo "⚡ AVAILABLE SHELLS:"
    echo

    local choice
    choice=$(gum choose "${options[@]}") || true

    case "${choice}" in
      "${WIZARD_BACK_OPTION}"|"")
        return
        ;;
      "${WIZARD_LRSHELL_OPTION}")
        echo -e "\n${C_GREEN}Opening LA Referencia Interactive Shell... (type 'exit' to return)${C_RESET}"
        "${DOCKER_SH}" lrshell-interactive || true
        ;;
      *)
        echo -e "\n${C_GREEN}Opening bash shell in service '${choice}'... (type 'exit' to return)${C_RESET}"
        compose::open_shell "${choice}" || true
        ;;
    esac

    echo
    ui::pause "Shell closed. Press Enter to continue..."
  done
}
