#!/usr/bin/env bash
# =============================================================================
# progress.sh — "ProgressRunner": runs a command in the background and draws a
# live panel (last log lines, spinner, progress bar, CPU/MEM gauges).
#
# Public API:
#   progress::run <command-string> <label> [log-file]
#       Returns the command's exit status, or 130 when cancelled with Ctrl+C.
#   PROGRESS_HEADER_FN=<function>
#       Optional. A view function drawn ONCE at the top of the progress screen
#       (e.g. the wizard banner); the panel is then redrawn below it. When it
#       does not fit the terminal height, the panel is shown alone.
#
# Everything else in this file is a private helper (prefixed with `_`).
#
# Drawing: while running, the panel lives on the terminal's alternate screen
# and every frame is drawn at an absolute position (the line below the optional
# header) followed by "clear to end of screen". Output written to the terminal by other programs (e.g.
# ssh "channel N: open failed" messages) is therefore wiped by the next frame
# instead of shifting the panel. When finished, the normal screen comes back
# and the last frame is printed once.
# =============================================================================

PROGRESS_PANEL_LINES=5
PROGRESS_BAR_WIDTH=15
PROGRESS_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# --- Private state (valid only while progress::run is executing) ------------
PROGRESS_HEADER_FN=""
PROGRESS_BOTTOM_MARGIN=3    # free rows kept below the panel (absorb stray output)

_PROGRESS_PID=""
_PROGRESS_INTERRUPTED=false
_PROGRESS_ON_ALT_SCREEN=false

_progress::enter_screen() {
  printf '\033[?1049h\033[H\033[2J'   # alternate screen, home, clear
  ui::hide_cursor
  _PROGRESS_ON_ALT_SCREEN=true
}

_progress::leave_screen() {
  [ "${_PROGRESS_ON_ALT_SCREEN}" = true ] || return 0
  printf '\033[?1049l'                 # back to the normal screen
  ui::show_cursor
  _PROGRESS_ON_ALT_SCREEN=false
}

_progress::on_interrupt() {
  _PROGRESS_INTERRUPTED=true
  _progress::leave_screen
  printf "\r\033[K\n  ${C_YELLOW}⚠️  Execution cancelled by user (Ctrl+C). Terminating background task...${C_RESET}\n"
  if [ -n "${_PROGRESS_PID}" ] && kill -0 "${_PROGRESS_PID}" 2>/dev/null; then
    pkill -P "${_PROGRESS_PID}" 2>/dev/null || true
    kill -TERM "${_PROGRESS_PID}" 2>/dev/null || true
    sleep 0.5
    kill -9 "${_PROGRESS_PID}" 2>/dev/null || true
  fi
}

_progress::cpu_count() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sysctl -n hw.ncpu 2>/dev/null || echo 1
  else
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
  fi
}

# Current cursor row, asked to the terminal (DSR). Fails if it does not answer.
#
# gum (termenv) also sends cursor-position queries to the terminal, and their
# answers may still be pending on the tty. So we send our query followed by a
# "device status" query (ESC[5n → ESC[0n) as a sentinel, read everything up to
# the sentinel and keep the LAST position answer, which is ours (terminals
# answer in order). No other answer contains an "n".
_progress::cursor_row() {
  local reply="" row
  printf '\033[6n\033[5n' > /dev/tty
  IFS= read -r -s -t 1 -d "n" reply < /dev/tty 2>/dev/null || true
  case "${reply}" in *R*) ;; *) return 1 ;; esac
  reply="${reply%R*}"     # up to the last "row;colR" answer
  row="${reply##*[}"      # "row;col"
  row="${row%%;*}"
  [[ "${row}" =~ ^[0-9]+$ ]] && echo "${row}"
}

# Draws the optional header and prints the row where the panel must start.
_progress::draw_header() {
  [ -n "${PROGRESS_HEADER_FN}" ] || { echo 1; return 0; }

  # No echo while drawing: terminal answers to gum's queries are consumed by
  # _progress::cursor_row instead of being printed as "^[[1;1R".
  local tty_mode row rows
  tty_mode="$(stty -g < /dev/tty 2>/dev/null)" || tty_mode=""
  stty -echo < /dev/tty 2>/dev/null || true
  "${PROGRESS_HEADER_FN}" > /dev/tty 2>&1 || true
  row="$(_progress::cursor_row)" || row=""
  [ -n "${tty_mode}" ] && stty "${tty_mode}" < /dev/tty 2>/dev/null || true

  rows="$(ui::term_rows)"
  if [ -n "${row}" ] && [ $((row + PROGRESS_PANEL_LINES + 2 + PROGRESS_BOTTOM_MARGIN)) -le "${rows}" ]; then
    echo "${row}"
  else
    printf '\033[H\033[2J' > /dev/tty   # header does not fit: panel alone
    echo 1
  fi
}

# Panel width: 78 columns (same as the wizard header) or less on narrow terms.
_progress::panel_width() {
  local width=78 cols
  cols=$(ui::term_cols)
  [ "${cols}" -lt 80 ] && width=$((cols - 2))
  [ "${width}" -lt 40 ] && width=40
  echo "${width}"
}

# Prints "<cpu%> <mem%>" (integers) for the host.
_progress::system_usage() {
  local ncpu="$1" cpu=0 mem=0
  if [[ "$OSTYPE" == "darwin"* ]]; then
    local raw_cpu
    raw_cpu=$(LC_ALL=C ps -A -o %cpu | LC_ALL=C awk '{s+=$1} END {printf "%.0f", s}')
    [[ "$raw_cpu" =~ ^[0-9]+$ ]] || raw_cpu=0
    cpu=$(( raw_cpu / ncpu ))
    [ "$cpu" -gt 100 ] && cpu=100
    mem=$(LC_ALL=C memory_pressure | grep "System-wide memory free percentage" | LC_ALL=C awk '{printf "%.0f", 100-$5}' || echo "0")
  else
    # Force C locale to avoid comma decimals and translated labels.
    cpu=$(LC_ALL=C top -bn1 | grep -i "Cpu(s)" | tr ',' '.' | LC_ALL=C awk '{s+=$2+$4} END {printf "%.0f", s}' || echo "0")
    mem=$(LC_ALL=C free | grep -i "Mem" | tr ',' '.' | LC_ALL=C awk '{printf "%.0f", $3/$2 * 100}' || echo "0")
  fi
  [[ "$cpu" =~ ^[0-9]+$ ]] || cpu=0
  [[ "$mem" =~ ^[0-9]+$ ]] || mem=0
  echo "${cpu} ${mem}"
}

# One-character colored gauge for a 0..100 value.
_progress::mini_gauge() {
  local val="${1:-0}"
  [[ "$val" =~ ^[0-9]+$ ]] || val=0
  local color=$C_GREEN
  [ "$val" -gt 60 ] && color=$C_YELLOW
  [ "$val" -gt 85 ] && color=$C_RED
  local blocks=(" " "▂" "▃" "▄" "▅" "▆" "▇" "█")
  local idx=$(( val * 7 / 100 ))
  [ "$idx" -gt 7 ] && idx=7
  printf "${color}${blocks[$idx]}${C_RESET}"
}

# Guesses a short "what is happening now" text from the last log lines.
_progress::status_from_log() {
  local log_file="$1" status="Initializing..."
  if [ -f "$log_file" ]; then
    local found
    found=$(grep -E "Container|Building|Compiling|#|Step|cloned|pulled|Cloning|Pulling" "$log_file" | tail -n 1 \
      | sed -E 's/.*Container ([^ ]+).*/\1/; s/.*(Building|Compiling) ([^ ]+).*/\2/; s/.*#[0-9]+ (\[[^]]+\]).*/\1/; s/.*OK[[:space:]]+(lareferencia-[^:]+): (cloned|pulled).*/\2 \1/; s/.*(Cloning|Pulling) (missing|updates)( for existing)? modules.*/\1 modules/; s/lareferencia-//g')
    [ -n "$found" ] && status="$found"
    status=${status//"${COMPOSE_PROJECT_NAME:-lr}-"/}
    status=$(echo "$status" | tr -d '\r\n')
    [ ${#status} -gt 15 ] && status="${status:0:12}..."
  fi
  printf "%s" "${status}"
}

_progress::repeat() {
  local char="$1" count="$2" j
  for ((j=0; j<count; j++)); do printf "%s" "${char}"; done
}

# Draws the bordered box with the last log lines.
_progress::draw_panel() {
  local label="$1" spinner="$2" log_file="$3" total_width="$4"
  local content_width=$((total_width - 4))

  local border_len=$((total_width - 9 - ${#label}))
  [ "${border_len}" -lt 2 ] && border_len=2
  printf "\033[K${C_CYAN}┌─ %s [%s] %s┐${C_RESET}\n" "${label}" "${spinner}" "$(_progress::repeat '─' "${border_len}")"

  local lines=() idx=0 line
  if [ -f "$log_file" ]; then
    while IFS= read -r line || [ -n "${line}" ]; do
      lines[idx]="${line}"
      idx=$((idx + 1))
    done < <(tail -n "${PROGRESS_PANEL_LINES}" "$log_file" 2>/dev/null)
  fi

  local k
  for ((k=0; k<PROGRESS_PANEL_LINES; k++)); do
    line="${lines[$k]:-}"
    line=$(echo "${line}" | tr -d '\r')
    [ "${#line}" -gt "${content_width}" ] && line="${line:0:$((content_width - 3))}..."
    printf "\033[K${C_CYAN}│${C_RESET} %-${content_width}s ${C_CYAN}│${C_RESET}\n" "${line}"
  done

  printf "\033[K${C_CYAN}└%s┘${C_RESET}\n" "$(_progress::repeat '─' $((total_width - 2)))"
}

# Draws the bottom status line: [━━━   ] ➜ status CPU:▃12% MEM:▅60%
_progress::draw_status_line() {
  local tick="$1" status_text="$2" cpu="$3" mem="$4"
  local progress=$(( (tick % PROGRESS_BAR_WIDTH) + 1 ))
  local remaining=$(( PROGRESS_BAR_WIDTH - progress ))

  printf "\r\033[K  [${C_GREEN}%s${C_GRAY}%s${C_RESET}] " \
    "$(_progress::repeat '━' "${progress}")" "$(_progress::repeat ' ' "${remaining}")"
  printf " ${C_GRAY}➜ ${C_BOLD}%-15s${C_RESET} " "$status_text"
  printf "${C_GRAY}CPU:${C_RESET}$(_progress::mini_gauge "$cpu")${C_GRAY}%-3s${C_RESET} " "$cpu%"
  printf "${C_GRAY}MEM:${C_RESET}$(_progress::mini_gauge "$mem")${C_GRAY}%-3s${C_RESET}" "$mem%"
}

_progress::report_failure() {
  local label="$1" log_file="$2"
  printf "\r  ${C_RED}❌ ${label} Failed! [Rev: %s] (See details below)${C_RESET}\n" "$(git::describe "${ROOT_DIR:-.}")"
  ui::rule "${C_GRAY}"
  echo -e "${C_RED}${C_BOLD}ERROR LOG (Last 20 lines):${C_RESET}"
  if [ -f "$log_file" ]; then
    tail -n 20 "$log_file"
  else
    echo "Log file not found."
  fi
  ui::rule "${C_GRAY}"
  echo -e "${C_YELLOW}Full log available at: $log_file${C_RESET}\n"
}

progress::run() {
  local cmd="$1"
  local label="$2"
  local log_file="${3:-/tmp/lareferencia-docker_${COMPOSE_PROJECT_NAME}.log}"

  rm -f "$log_file"
  eval "$cmd" > "$log_file" 2>&1 &
  _PROGRESS_PID=$!
  _PROGRESS_INTERRUPTED=false
  trap _progress::on_interrupt INT TERM

  local ncpu total_width top tick=0 cpu=0 mem=0
  ncpu=$(_progress::cpu_count)
  total_width=$(_progress::panel_width)

  _progress::enter_screen
  top="$(_progress::draw_header)"
  set +e   # we collect the exit status manually below
  while kill -0 "${_PROGRESS_PID}" 2>/dev/null; do
    [ "${_PROGRESS_INTERRUPTED}" = true ] && break

    # Absolute redraw below the header, then wipe anything under the panel.
    printf '\033[%d;1H' "${top}"
    _progress::draw_panel "${label}" "${PROGRESS_SPINNER[$((tick % 10))]}" "${log_file}" "${total_width}"

    # Refresh system stats every ~1.5s to avoid overhead.
    if (( tick % 15 == 0 )); then
      read -r cpu mem <<< "$(_progress::system_usage "${ncpu}")"
    fi
    _progress::draw_status_line "${tick}" "$(_progress::status_from_log "${log_file}")" "${cpu}" "${mem}"
    printf '\033[J'

    tick=$((tick + 1))
    sleep 0.1
  done
  trap - INT TERM
  _progress::leave_screen

  if [ "${_PROGRESS_INTERRUPTED}" = true ]; then
    set -e
    return 130
  fi

  wait "${_PROGRESS_PID}"
  local status=$?
  set -e

  # Keep the last frame visible on the normal screen.
  _progress::draw_panel "${label}" "■" "${log_file}" "${total_width}"

  if [ $status -eq 0 ]; then
    printf "  ${C_GREEN}✅ ${label} Completed!${C_RESET}\n"
  else
    _progress::report_failure "${label}" "${log_file}"
  fi
  return $status
}
