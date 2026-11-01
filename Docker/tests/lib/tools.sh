#!/usr/bin/env bash
# =============================================================================
# tools.sh — test tools downloaded on first use into Docker/tests/.bin
# (pinned versions, checked by sha256), like Docker/.bin/gum for the wizard.
#
#   tools::bats         prints the path of bats
#   tools::shellcheck   prints the path of shellcheck
# =============================================================================

TOOLS_BIN_DIR="${TESTS_DIR}/.bin"

BATS_VERSION="1.11.1"
BATS_SHA256="5c57ed9616b78f7fd8c553b9bae3c7c9870119edd727ec17dbd1185c599f79d9"

SHELLCHECK_VERSION="0.10.0"
# <os.arch>|sha256 of shellcheck-v<version>.<os.arch>.tar.xz
SHELLCHECK_SHA256=(
  "darwin.aarch64|bbd2f14826328eee7679da7221f2bc3afb011f6a928b848c80c321f6046ddf81"
  "darwin.x86_64|ef27684f23279d112d8ad84e0823642e43f838993bbb8c0963db9b58a90464c2"
  "linux.x86_64|6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87"
  "linux.aarch64|324a7e89de8fa2aed0d0c28f3dab59cf84c6d74264022c00c22af665ed1a09bb"
)

_tools::sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# _tools::download <url> <file> <sha256>
_tools::download() {
  echo "Downloading $(basename "$1")..." >&2
  curl -fsSL "$1" -o "$2" || { echo "Error: download failed: $1" >&2; return 1; }
  if [ "$(_tools::sha256 "$2")" != "$3" ]; then
    rm -f "$2"
    echo "Error: checksum mismatch for $1" >&2
    return 1
  fi
}

tools::bats() {
  local dir="${TOOLS_BIN_DIR}/bats-core-${BATS_VERSION}"
  if [ ! -x "${dir}/bin/bats" ]; then
    mkdir -p "${TOOLS_BIN_DIR}"
    local archive="${TOOLS_BIN_DIR}/bats.tar.gz"
    _tools::download "https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz" \
      "${archive}" "${BATS_SHA256}" || return 1
    tar -xzf "${archive}" -C "${TOOLS_BIN_DIR}" && rm -f "${archive}"
  fi
  echo "${dir}/bin/bats"
}

tools::shellcheck() {
  local bin="${TOOLS_BIN_DIR}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
  if [ ! -x "${bin}" ]; then
    local os arch platform row sha=""
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    [ "${arch}" = arm64 ] && arch=aarch64
    platform="${os}.${arch}"
    for row in "${SHELLCHECK_SHA256[@]}"; do
      [ "${row%%|*}" = "${platform}" ] && sha="${row#*|}"
    done
    [ -n "${sha}" ] || { echo "Error: no shellcheck build for ${platform}" >&2; return 1; }

    mkdir -p "${TOOLS_BIN_DIR}"
    local archive="${TOOLS_BIN_DIR}/shellcheck.tar.xz"
    _tools::download "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.${platform}.tar.xz" \
      "${archive}" "${sha}" || return 1
    tar -xJf "${archive}" -C "${TOOLS_BIN_DIR}" && rm -f "${archive}"
  fi
  echo "${bin}"
}
