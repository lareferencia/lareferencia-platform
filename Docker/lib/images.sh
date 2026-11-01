#!/usr/bin/env bash
# =============================================================================
# images.sh — "ImageStore": La Referencia images and their build cache.
#
# Every cleanup here touches ONLY La Referencia artifacts, never other
# projects sharing the same Docker:
#   - images      lareferencia/* tagged for THIS installation (checkout hash)
#   - dangling    untagged images labelled with this compose project
#   - build cache kept in a dedicated buildx builder (LR_BUILDER_NAME), so it
#                 can be limited/pruned without touching the default builder
#
# Settings (Docker/.env):
#   LR_BUILD_CACHE_MAX_SIZE   cap of the dedicated builder cache (default 5GB,
#                             off = no cap); least recently used goes first
#   LR_IMAGE_KEEP_PREVIOUS    previous builds kept besides the current one (default 1)
#   LR_DEDICATED_BUILDER      true (default) | false = use Docker's default builder
#
# Docker/.image-tags (local, not versioned) records the tag of every successful
# build: it tells which previous builds are the most recent ones.
#
# Public API:
#   buildx::use_dedicated           creates/selects the builder (exports BUILDX_BUILDER)
#   images::cleanup_after_build     superseded images + dangling + cache cap
#   images::prune_all               manual prune: everything La Referencia can rebuild
#   images::remove_superseded <n>   keeps the current tag + <n> previous builds
#   images::prune_dangling
#   buildx::limit_cache
# =============================================================================

LR_BUILDER_DEFAULT_NAME="lareferencia"
LR_BUILD_CACHE_DEFAULT_MAX="5GB"
LR_IMAGE_DEFAULT_KEEP_PREVIOUS=1

# --- Dedicated builder (isolated build cache) ------------------------------------------

buildx::name() {
  config::get LR_BUILDER_NAME "${LR_BUILDER_DEFAULT_NAME}"
}

# True when builds go to the dedicated builder in this process.
buildx::dedicated_active() {
  [ -n "${BUILDX_BUILDER:-}" ] && [ "${BUILDX_BUILDER}" = "$(buildx::name)" ]
}

buildx::use_dedicated() {
  [ "$(config::get LR_DEDICATED_BUILDER true)" = "true" ] || return 0
  if ! system::buildx_available; then
    ui::warn "docker buildx not available: using Docker's default builder (no build cache cap)."
    return 0
  fi

  local name
  name="$(buildx::name)"
  if ! docker buildx inspect "${name}" >/dev/null 2>&1; then
    echo "Creating dedicated buildx builder '${name}' (isolated La Referencia build cache)..."
    if ! docker buildx create --name "${name}" --driver docker-container >/dev/null; then
      ui::warn "Could not create builder '${name}': using Docker's default builder."
      return 0
    fi
  fi
  export BUILDX_BUILDER="${name}"
}

# Buildx >= 0.17 calls it --max-used-space; older versions --keep-storage.
_buildx::cap_flag() {
  if docker buildx prune --help 2>/dev/null | grep -q -- '--max-used-space'; then
    echo "--max-used-space"
  else
    echo "--keep-storage"
  fi
}

# Shrinks the dedicated builder cache to LR_BUILD_CACHE_MAX_SIZE (LRU first).
buildx::limit_cache() {
  local max
  max="$(config::get LR_BUILD_CACHE_MAX_SIZE "${LR_BUILD_CACHE_DEFAULT_MAX}")"
  case "$(text::lower "${max}")" in off|none|0) return 0 ;; esac
  buildx::dedicated_active || return 0

  echo "Limiting La Referencia build cache to ${max}..."
  docker buildx prune --builder "$(buildx::name)" -f "$(_buildx::cap_flag)" "${max}" >/dev/null 2>&1 \
    || ui::warn "Could not limit the build cache (continuing)."
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
  buildx::limit_cache
}

# Manual prune: everything La Referencia can rebuild (current images are kept).
images::prune_all() {
  echo -e "\n${C_CYAN}--- Pruning La Referencia images & build cache (other projects are not touched) ---${C_RESET}"
  echo "1. Removing images of previous builds of this installation..."
  images::remove_superseded 0

  echo -e "\n2. Removing dangling La Referencia images..."
  images::prune_dangling

  echo -e "\n3. Clearing the La Referencia build cache (builder '$(buildx::name)')..."
  if system::buildx_available && docker buildx inspect "$(buildx::name)" >/dev/null 2>&1; then
    docker buildx prune --builder "$(buildx::name)" -af 2>&1 | tail -n 1 || true
  else
    echo "   No dedicated builder yet (it is created by the next build)."
  fi

  echo -e "\n${C_GREEN}Current Docker Disk Usage (whole Docker, all projects):${C_RESET}"
  docker system df || true
  echo -e "${C_GREEN}Prune completed successfully.${C_RESET}"
}
