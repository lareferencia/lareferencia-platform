#!/usr/bin/env bash
# =============================================================================
# images.sh — "ImageStore": cleanup of La Referencia images.
#
# Every cleanup here touches ONLY La Referencia artifacts, never other
# projects sharing the same Docker:
#   - images      lareferencia/* tagged for THIS installation (checkout hash)
#   - dangling    untagged images labelled with this compose project
# Builds use Docker's default builder; its build cache is shared by every
# project on the host, so it is never pruned here.
#
# Settings (Docker/.env):
#   LR_IMAGE_KEEP_PREVIOUS    previous builds kept besides the current one (default 1)
#
# Docker/.image-tags (local, not versioned) records the tag of every successful
# build: it tells which previous builds are the most recent ones.
#
# Public API:
#   images::cleanup_after_build     superseded images + dangling (+ legacy builder)
#   images::prune_all               manual prune: every previous build of this installation
#   images::remove_superseded <n>   keeps the current tag + <n> previous builds
#   images::prune_dangling
# =============================================================================

LR_IMAGE_DEFAULT_KEEP_PREVIOUS=1

# A previous version built in a dedicated buildx builder named "lareferencia"
# (its own cache + a running buildkit container). Builds now use Docker's
# default builder, so that builder is only dead weight: remove it.
LEGACY_BUILDER_NAME="lareferencia"

_images::remove_legacy_builder() {
  system::buildx_available || return 0
  docker buildx inspect "${LEGACY_BUILDER_NAME}" >/dev/null 2>&1 || return 0
  echo "Removing the unused '${LEGACY_BUILDER_NAME}' buildx builder of a previous version (and its cache)..."
  docker buildx rm "${LEGACY_BUILDER_NAME}" >/dev/null 2>&1 \
    || ui::warn "Could not remove it; run: docker buildx rm ${LEGACY_BUILDER_NAME}"
  return 0
}

# --- Images of this installation -----------------------------------------------------------
#
# Tags of this installation contain "-<checkout hash>" (see compose::image_tag).
# Docker's creation date cannot tell which build is newer (a build fully served
# from cache keeps the old date), so every successful build appends its tag to
# IMAGE_HISTORY_FILE and "previous builds" are read from there.

IMAGE_HISTORY_FILE="${SCRIPT_DIR}/.image-tags"
IMAGE_HISTORY_MAX_LINES=50

images::record_build() {
  local tag
  tag="$(compose::image_tag)"
  [ "$(tail -n 1 "${IMAGE_HISTORY_FILE}" 2>/dev/null)" = "${tag}" ] && return 0
  echo "${tag}" >> "${IMAGE_HISTORY_FILE}"
  # Bounded: only the last builds matter.
  tail -n "${IMAGE_HISTORY_MAX_LINES}" "${IMAGE_HISTORY_FILE}" > "${IMAGE_HISTORY_FILE}.tmp" \
    && mv "${IMAGE_HISTORY_FILE}.tmp" "${IMAGE_HISTORY_FILE}"
}

# The <n> most recent previous builds (current excluded), newest first.
_images::recent_previous_tags() {
  local keep="$1" current
  [ "${keep}" -gt 0 ] && [ -f "${IMAGE_HISTORY_FILE}" ] || return 0
  current="$(compose::image_tag)"
  awk -v current="${current}" '
      { lines[NR] = $0 }
      END { for (i = NR; i >= 1; i--) if (lines[i] != current && !seen[lines[i]]++) print lines[i] }' \
    "${IMAGE_HISTORY_FILE}" | head -n "${keep}"
}

# Every "repo:tag" of this installation, except the current tag.
_images::installation_refs() {
  local hash current
  hash="$(hash::short "${ROOT_DIR}")"
  current="$(compose::image_tag)"
  docker images --filter "reference=lareferencia/*" --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
    | awk -v hash="${hash}" -v current="${current}" '
        { tag = $0; sub(/^[^:]*:/, "", tag) }
        tag != current && tag ~ ("-" hash "(-|$)") { print }'
}

# images::remove_superseded <keep>
#   Removes the images of older builds of this installation, keeping the current
#   tag and the <keep> most recent previous ones (from the build history).
#   Images used by a container are kept (docker refuses without -f).
images::remove_superseded() {
  local keep="${1:-0}" ref tag kept_tags removed=0
  [[ "${keep}" =~ ^[0-9]+$ ]] || keep="${LR_IMAGE_DEFAULT_KEEP_PREVIOUS}"

  # No history yet (first build after this feature): be conservative.
  if [ "${keep}" -gt 0 ] && [ ! -f "${IMAGE_HISTORY_FILE}" ]; then
    echo "No build history yet: previous images are kept this time."
    return 0
  fi

  kept_tags="$(_images::recent_previous_tags "${keep}")"
  while IFS= read -r ref; do
    [ -n "${ref}" ] || continue
    tag="${ref#*:}"
    printf '%s\n' "${kept_tags}" | grep -Fxq "${tag}" && continue
    if docker rmi "${ref}" >/dev/null 2>&1; then
      removed=$((removed + 1))
    else
      echo "  kept ${ref} (in use by a container)"
    fi
  done < <(_images::installation_refs)

  [ "${removed}" -gt 0 ] && echo "Removed ${removed} image(s) of previous La Referencia builds."
  return 0
}

images::prune_dangling() {
  [ -n "${COMPOSE_PROJECT_NAME:-}" ] || compose::export_service_prefix
  local filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}"
  if [ -n "$(docker images -q --filter dangling=true --filter "${filter}" 2>/dev/null || true)" ]; then
    echo "Removing dangling La Referencia images (project ${COMPOSE_PROJECT_NAME})..."
    docker image prune -f --filter "${filter}" >/dev/null 2>&1 || true
  fi
  return 0
}

# --- Policies ---------------------------------------------------------------------------------

images::cleanup_after_build() {
  echo "--- Cleaning up La Referencia build artifacts ---"
  if [ -f "${IMAGE_HISTORY_FILE}" ]; then
    images::record_build
    images::remove_superseded "$(config::get LR_IMAGE_KEEP_PREVIOUS "${LR_IMAGE_DEFAULT_KEEP_PREVIOUS}")"
  else
    # First build with history: we cannot tell which old images are recent.
    images::record_build
    echo "Build history started (Docker/$(basename "${IMAGE_HISTORY_FILE}")): previous images are kept this time."
  fi
  images::prune_dangling
  _images::remove_legacy_builder
}

# Manual prune: every previous build of this installation (current images are kept).
images::prune_all() {
  echo -e "\n${C_CYAN}--- Pruning La Referencia images (other projects are not touched) ---${C_RESET}"
  echo "1. Removing images of previous builds of this installation..."
  images::remove_superseded 0

  echo -e "\n2. Removing dangling La Referencia images..."
  images::prune_dangling
  _images::remove_legacy_builder

  echo -e "\n${C_GREEN}Current Docker Disk Usage (whole Docker, all projects):${C_RESET}"
  docker system df || true
  echo -e "${C_GREEN}Prune completed successfully.${C_RESET}"
}
