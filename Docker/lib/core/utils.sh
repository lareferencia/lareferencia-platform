#!/usr/bin/env bash
# =============================================================================
# utils.sh — Small, dependency-free helpers shared by every other module.
#
# Namespaces:
#   list::*   operations on bash arrays (passed as "$@")
#   text::*   string helpers
#   hash::*   portable hashing (sha256sum / shasum / md5)
#   cmd::exists
#
# NOTE: the platform must run on macOS' bash 3.2. Under `set -u`, bash 3.2
# treats an empty array expansion ("${arr[@]}") as an unbound variable, so
# arrays that may be empty are always expanded as ${arr[@]+"${arr[@]}"}.
# =============================================================================

# Returns 0 when the command is available on PATH.
cmd::exists() {
  command -v "$1" >/dev/null 2>&1
}

# list::contains <needle> <item...>
list::contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [ "${item}" = "${needle}" ] && return 0
  done
  return 1
}

# list::join <separator> <item...>   →  prints the items joined by separator
list::join() {
  local IFS="$1"
  shift || true
  printf "%s" "$*"
}

# text::lower <value>
text::lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# text::trim <value>   →  strips leading/trailing whitespace
text::trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

# text::to_toggle <value>   →  "on" for 1/true/on/yes, "off" otherwise
text::to_toggle() {
  case "$(text::lower "$1")" in
    1|true|on|yes) printf "on\n" ;;
    *)             printf "off\n" ;;
  esac
}

# hash::short <string>   →  first 7 hex chars of a hash of the string
hash::short() {
  if cmd::exists sha256sum; then
    printf "%s" "$1" | sha256sum | awk '{print substr($1, 1, 7)}'
  elif cmd::exists shasum; then
    printf "%s" "$1" | shasum -a 256 | awk '{print substr($1, 1, 7)}'
  elif cmd::exists md5sum; then
    printf "%s" "$1" | md5sum | awk '{print substr($1, 1, 7)}'
  else
    printf "%s" "$1" | md5 | awk '{print substr($1, 1, 7)}'
  fi
}

# hash::sha256_stdin   →  sha256 of whatever is piped in
hash::sha256_stdin() {
  if cmd::exists sha256sum; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# hash::sha256_file <path>
hash::sha256_file() {
  hash::sha256_stdin < "$1"
}

# git::is_repo <dir>
git::is_repo() {
  cmd::exists git && git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# git::describe <dir>   →  "v1.2-3-gabc-dirty" style revision, or "unknown"
git::describe() {
  local dir="${1:-.}"
  if git::is_repo "${dir}"; then
    git -C "${dir}" describe --tags --always --dirty 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

# Runs a command with lowered CPU priority when `nice` is available.
proc::nice() {
  if cmd::exists nice; then
    nice -n 10 "$@"
  else
    "$@"
  fi
}
