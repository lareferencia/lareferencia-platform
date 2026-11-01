#!/usr/bin/env bash
# =============================================================================
# ui.sh — Terminal presentation: colors, the `gum` wrapper and small widgets.
#
# Namespaces:
#   gum           transparent wrapper that downloads gum on first use
#   ui::*         messages, pauses, screen helpers
# =============================================================================

# --- Visual theme (flat ANSI) ------------------------------------------------
C_RESET=$(printf '\033[0m')
C_BOLD=$(printf '\033[1m')
C_BLUE=$(printf '\033[38;5;75m')     # Soft blue
C_CYAN=$(printf '\033[38;5;80m')     # Flat cyan
C_GREEN=$(printf '\033[38;5;114m')   # Soft green
C_YELLOW=$(printf '\033[38;5;222m')  # Flat yellow
C_RED=$(printf '\033[38;5;204m')     # Flat red
C_MAGENTA=$(printf '\033[38;5;176m') # Flat magenta
C_GRAY=$(printf '\033[38;5;245m')    # Gray

GUM_VERSION="0.15.0"
GUM_BIN_DIR="${SCRIPT_DIR}/.bin"

# --- gum (downloaded on demand, like mvnw) -----------------------------------

# Prints the path of the local gum binary, downloading it if necessary.
gum::binary_path() {
  local gum_bin="${GUM_BIN_DIR}/gum"

  if [ -x "${gum_bin}" ]; then
    printf "%s" "${gum_bin}"
    return 0
  fi

  local os arch
  case "$(uname -s)" in
    Darwin) os="Darwin" ;;
    Linux)  os="Linux" ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64)        arch="x86_64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported Arch: $(uname -m)" >&2; exit 1 ;;
  esac

  local filename="gum_${GUM_VERSION}_${os}_${arch}.tar.gz"
  local url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${filename}"

  echo -e "${C_CYAN}Downloading gum wrapper v${GUM_VERSION} for ${os}-${arch}...${C_RESET}" >&2
  mkdir -p "${GUM_BIN_DIR}"

  cmd::exists curl || { echo "Error: curl is required to download the gum wrapper." >&2; exit 1; }
  curl -sSL "${url}" -o "${GUM_BIN_DIR}/${filename}" \
    || { echo "Error: Failed to download gum from ${url}" >&2; exit 1; }

  # Releases ship the binary inside a folder: extract, move it up, clean up.
  (
    cd "${GUM_BIN_DIR}" || exit 1
    tar -xzf "${filename}"
    find . -name "gum" -type f -exec mv {} . \;
    find . -maxdepth 1 -type d -name "gum_*" -exec rm -rf {} \;
  )

  chmod +x "${gum_bin}"
  rm -f "${GUM_BIN_DIR}/${filename}"
  printf "%s" "${gum_bin}"
}

gum() {
  local gum_path
  gum_path="$(gum::binary_path)"
  "${gum_path}" "$@"
}

# --- Messages ----------------------------------------------------------------

ui::info()    { echo -e "${C_CYAN}$*${C_RESET}"; }
ui::success() { echo -e "${C_GREEN}$*${C_RESET}"; }
ui::warn()    { echo -e "${C_YELLOW}$*${C_RESET}"; }
ui::error()   { echo -e "${C_RED}$*${C_RESET}" >&2; }

# ui::pause [placeholder]   →  waits for Enter using gum
ui::pause() {
  gum input --placeholder "${1:-Press Enter to continue...}" > /dev/null
}

ui::clear_screen() {
  printf "\033c"
}

# Terminal size read from the tty itself (works inside $(...) too).
ui::term_size() {
  local size
  size="$(stty size < /dev/tty 2>/dev/null || true)"
  [ -n "${size}" ] || size="$(tput lines 2>/dev/null || echo 24) $(tput cols 2>/dev/null || echo 80)"
  echo "${size}"
}
ui::term_rows() { local r c; read -r r c <<< "$(ui::term_size)"; echo "${r}"; }
ui::term_cols() { local r c; read -r r c <<< "$(ui::term_size)"; echo "${c}"; }

ui::show_cursor() { printf "\033[?25h"; }
ui::hide_cursor() { printf "\033[?25l"; }

ui::rule() {
  echo -e "${1:-${C_CYAN}}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}

ui::header() {
  ui::rule
  echo -e "${C_CYAN}  🐳 ${C_BOLD}LA REFERENCIA PLATFORM${C_RESET} ${C_CYAN}- Docker Management Wizard${C_RESET}"
  ui::rule
}

# ui::banner <line...>   →  big double-bordered box used as screen title
ui::banner() {
  gum style \
    --foreground 80 --border-foreground 80 --border double \
    --align center --width 80 --margin "1 2" --padding "1 2" \
    "$@"
}

# ui::title <text>   →  underlined section title
ui::title() {
  gum style --foreground 80 --bold --underline "$1"
}
