#!/usr/bin/env bash
# =============================================================================
# config.sh — "Config": reads and writes settings persisted in Docker/.env.
#
# Public API:
#   config::ensure_file                 creates .env from .env.example if absent
#   config::get <KEY> [default]         prints the value (or default when empty)
#   config::set <KEY> <value> [file]    creates or replaces KEY=value
#   config::apply_resource_profile <low|medium|high|custom>
# =============================================================================

config::ensure_file() {
  [ -f "${ENV_FILE}" ] && return 0
  if [ -f "${ENV_EXAMPLE}" ]; then
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
  else
    touch "${ENV_FILE}"
  fi
}

config::get() {
  local key="$1"
  local default_value="${2:-}"
  local value=""

  if [ -f "${ENV_FILE}" ]; then
    # Last occurrence wins; surrounding whitespace and quotes are stripped.
    value="$(awk -v k="${key}" '
      $0 ~ "^[[:space:]]*"k"[[:space:]]*=" { idx = index($0, "="); v = substr($0, idx + 1) }
      END {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^"|"$/, "", v)
        gsub(/^'\''|'\''$/, "", v)
        print v
      }' "${ENV_FILE}" || true)"
  fi

  printf "%s\n" "${value:-${default_value}}"
}

config::set() {
  local key="$1"
  local value="$2"
  local file="${3:-$ENV_FILE}"

  config::ensure_file

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
    sed -E "s|^([[:space:]]*${key}[[:space:]]*=).*$|\1${value}|g" "${file}" > "${file}.tmp"
    mv "${file}.tmp" "${file}"
  else
    printf "%s=%s\n" "${key}" "${value}" >> "${file}"
  fi
}

# Copies every KEY=value of Docker/profiles/<profile>.env into .env.
config::apply_resource_profile() {
  local profile="$1"
  local profile_file="${SCRIPT_DIR}/profiles/${profile}.env"

  if [ ! -f "${profile_file}" ]; then
    ui::error "Error: Profile file ${profile_file} not found."
    return 1
  fi

  ui::info "Applying resource profile: ${profile}..."

  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue
    [[ "$line" == *"="* ]] || continue
    config::set "${line%%=*}" "${line#*=}"
  done < "${profile_file}"

  config::set "LR_RESOURCE_PROFILE" "${profile}"
}
