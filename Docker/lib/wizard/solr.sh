#!/usr/bin/env bash
# =============================================================================
# wizard/solr.sh — View: dialogs for Solr schema migrations.
# The routines themselves live in lib/search.sh (solr::*) and in the Solr
# entrypoint (Docker/solr/entrypoint.sh).
#
#   wizard::solr_preflight      asked before Start / Rebuild & Start when a new
#                               schema cannot be applied to the existing index:
#                               keep it (default) or migrate after starting
#   wizard::solr_after_start    runs the migration chosen in the preflight
#   wizard::solr_screen         "🔎 Solr" menu: status / migrate / verify
#   wizard::solr_menu_label
# =============================================================================

WIZARD_SOLR_MIGRATE=false

_wizard::solr_explain_migration() {
  local cores="$1"
  echo
  gum style --foreground 222 --border rounded --border-foreground 222 --padding "0 1" \
    "Migrating ${cores} will:" \
    " 1. stop Solr for a moment" \
    " 2. install the new schema with an EMPTY index" \
    "    (the current index is kept in <core>/previous-index-<date>/ for rollback)" \
    " 3. start Solr again" \
    "" \
    "Until the networks are reindexed, these cores have no documents:" \
    " oai    → OAI-PMH publishes nothing until the xOAI indexing runs" \
    " biblio → VuFind finds nothing until the frontend indexing runs" \
    "Run those indexing actions in full (not incremental) afterwards."
}

_wizard::solr_reindex_hint() {
  gum style --foreground 114 \
    "✅ New Solr schema installed. Now reindex: Admin Web → networks → run the" \
    "   xOAI (oai) / frontend (biblio) indexing actions in full, not incremental." \
    "   Progress: ./Docker/docker.sh solr status"
}

# Returns 0 when the start may proceed (and sets WIZARD_SOLR_MIGRATE).
wizard::solr_preflight() {
  WIZARD_SOLR_MIGRATE=false
  solr::is_local || return 0
  [ "$(module::state solr)" = "on" ] || return 0

  # Compare with what this checkout will install. A staging problem is not
  # handled here: the start itself reports it.
  echo -e "${C_GRAY}Checking Solr core configurations...${C_RESET}"
  solr::stage >/dev/null 2>&1 || return 0

  local cores
  cores="$(solr::pending_cores)"
  [ -n "${cores}" ] || return 0

  echo
  gum style --foreground 222 --bold \
    "🔎 This version has a new Solr schema for: ${cores}" \
    "   It is not compatible with the documents already indexed, so it can only" \
    "   be installed with an empty index and a reindex."
  local choice
  choice=$(gum choose \
    "📌 Keep the current Solr schema for now (recommended: no downtime)" \
    "⬆️  Migrate ${cores} after starting (empty index, then reindex)" \
    "❌ Cancel") || return 1

  case "${choice}" in
    "📌"*)
      gum style --foreground 114 "📌 Keeping the current schema. Migrate later from the menu: 🔎 Solr."
      sleep 1.5
      return 0
      ;;
    "⬆️"*)
      _wizard::solr_explain_migration "${cores}"
      if gum confirm "Empty the index of ${cores} and migrate after starting?"; then
        WIZARD_SOLR_MIGRATE=true
      else
        gum style --foreground 114 "📌 Keeping the current schema."
        sleep 1
      fi
      return 0
      ;;
    *) return 1 ;;
  esac
}

# After a successful start: the migration chosen in the preflight, if any.
wizard::solr_after_start() {
  [ "${WIZARD_SOLR_MIGRATE}" = true ] || return 0
  WIZARD_SOLR_MIGRATE=false
  if wizard::run_command "Solr Schema Migration" solr migrate; then
    _wizard::solr_reindex_hint
    return 0
  fi
  ui::warn "Solr migration failed (details above); the previous index is kept in <core>/previous-index-*."
  return 1
}

wizard::solr_menu_label() {
  local cores
  solr::is_local || { echo "🔎 Solr [external]"; return 0; }
  cores="$(solr::pending_cores)"
  if [ -n "${cores}" ]; then
    echo "🔎 Solr [schema migration available: ${cores}]"
  else
    echo "🔎 Solr"
  fi
}

wizard::solr_screen() {
  while true; do
    ui::clear_screen
    ui::title "🔎 Solr"
    echo
    solr::status
    echo

    local cores options=()
    cores="$(solr::pending_cores)"
    [ -n "${cores}" ] && options+=("⬆️  Migrate ${cores} now (empty index, then reindex)")
    options+=("🔍 Verify (modules == staging == installed)")
    options+=("🔙 Back")

    local choice
    choice=$(gum choose "${options[@]}") || return 0
    case "${choice}" in
      "⬆️"*)
        _wizard::solr_explain_migration "${cores}"
        if gum confirm "Empty the index of ${cores} and migrate now?"; then
          if wizard::run_command "Solr Schema Migration" solr migrate; then
            _wizard::solr_reindex_hint
          fi
          ui::pause
        fi
        ;;
      "🔍"*)
        wizard::run_command "Solr Verify" solr verify || true
        ui::pause
        ;;
      *) return 0 ;;
    esac
  done
}
