#!/usr/bin/env bash
# =============================================================================
# data.sh — "DataStore": host directories bind-mounted into the containers.
#
# Public API:
#   data::ensure_volume_directories    creates elasticsearch dirs with permissions
#   data::reset_paths                  lists dirs (relative to ROOT_DIR) wiped by reset
#   data::clean                        wipes data::reset_paths (keeps tracked files)
#   data::reset_all                    containers + data + cloned modules
# =============================================================================

data::ensure_volume_directories() {
  local es_dir="${VOLUME_DIR}/elasticsearch"
  mkdir -p "${es_dir}/data" "${es_dir}/log" 2>/dev/null || true
  chmod -R ugo+rwX "${es_dir}" 2>/dev/null || true

  # Directory owned by root (e.g. created by a container): fix it via Docker.
  if { [ ! -w "${es_dir}/log" ] || [ ! -w "${es_dir}/data" ]; } && cmd::exists docker; then
    docker run --rm -v "${VOLUME_DIR}:/vol" alpine \
      sh -c "mkdir -p /vol/elasticsearch/data /vol/elasticsearch/log && chmod -R 777 /vol/elasticsearch" 2>/dev/null || true
  fi
}

data::reset_paths() {
  local rel_data="${DATA_DIR#${ROOT_DIR}/}"
  local rel_volume="${VOLUME_DIR#${ROOT_DIR}/}"
  printf "%s\n" \
    "${rel_data}" \
    "${rel_volume}/postgres" \
    "${rel_volume}/solr" \
    "${rel_volume}/elasticsearch" \
    "${rel_volume}/lareferencia" \
    "${rel_volume}/vufind" \
    "${rel_volume}/vufind-db"
}

data::clean() {
  local paths=() p
  for p in $(data::reset_paths); do paths+=("${p}"); done

  echo "--- Surgically cleaning data in explicitly mapped directories ---"

  if cmd::exists docker; then
    echo "Fixing permissions for data directories using Docker..."
    local targets=""
    for p in "${paths[@]}"; do targets="${targets} /workspace/${p}"; done
    # Parents get non-recursive write permission so the host user can unlink
    # the folders themselves.
    docker run --rm -v "${ROOT_DIR}:/workspace" alpine sh -c \
      "chmod ugo+rwX /workspace/${DATA_DIR#${ROOT_DIR}/} /workspace/${VOLUME_DIR#${ROOT_DIR}/} 2>/dev/null; chmod -R ugo+rwX ${targets} 2>/dev/null" || true
  fi

  if git::is_repo "${ROOT_DIR}"; then
    git -C "${ROOT_DIR}" clean -fdx -- "${paths[@]}"
  else
    for p in "${paths[@]}"; do
      # Empty the directory but keep it (and its .gitkeep).
      [ -d "${ROOT_DIR}/${p}" ] && find "${ROOT_DIR}/${p}" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} + 2>/dev/null || true
    done
  fi
}

# Full surgical reset: containers/volumes, mapped data and cloned modules.
data::reset_all() {
  echo "--- Loading cloned workspace modules from workspace.ini ---"
  local modules=() m listing
  listing="$(workspace::cloned_modules)" || exit 1
  while IFS= read -r m; do
    [ -n "${m}" ] && modules+=("${m}")
  done <<< "${listing}"

  echo "--- Stopping and removing all containers, networks and volumes ---"
  "${DOCKER_SH}" down v || true

  data::clean

  echo "--- Removing cloned workspace modules ---"
  workspace::remove_modules ${modules[@]+"${modules[@]}"}
}
