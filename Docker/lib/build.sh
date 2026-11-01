#!/usr/bin/env bash
# =============================================================================
# build.sh — "Builder": compiles sources and builds the Docker images.
#
# Build pipeline (build::all):
#   1. solr::stage                 Solr cores/jars staging
#   2. build::components           React admin + Angular dashboard + Java (Maven)
#   3. docker compose build        multi-stage Dockerfiles
#
# Public API:
#   build::all [no-cache:true|false]
#   build::components              sequential (default) or parallel (BUILD_PARALLEL=true)
#   build::java                    Maven build inside a container
#   build::images_exist            true when every locally-built image of the selection exists
#   build::prune                   removes dangling images and builder cache
# =============================================================================

MAVEN_IMAGE="maven:3.9.11-eclipse-temurin-17"
MAVEN_CACHE_VOLUME="lr-maven-cache"
BUILD_LOG_DIR="${ROOT_DIR}/Docker/data/build-logs"

# Application modules whose JARs end up in Docker images.
JAVA_APP_MODULES=(
  lareferencia-lrharvester-app
  lareferencia-entity-rest
  lareferencia-shell
  lareferencia-oai-pmh
)

# --- Java (Maven in Docker) ------------------------------------------------------

_build::pull_maven_image() {
  docker image inspect "${MAVEN_IMAGE}" >/dev/null 2>&1 && return 0

  echo "Pulling Maven builder image (${MAVEN_IMAGE})..."
  local attempts=3
  until docker pull "${MAVEN_IMAGE}" || [ "${attempts}" -le 1 ]; do
    echo "Docker pull timed out or failed. Retrying in 3 seconds... (${attempts} attempts left)"
    attempts=$((attempts - 1))
    sleep 3
  done

  if ! docker image inspect "${MAVEN_IMAGE}" >/dev/null 2>&1; then
    echo "Error: Failed to pull builder image ${MAVEN_IMAGE} after multiple attempts." >&2
    return 1
  fi
}

build::java() {
  echo "--- Compiling Java Modules (using named volume ${MAVEN_CACHE_VOLUME}) ---"
  docker volume create "${MAVEN_CACHE_VOLUME}" >/dev/null 2>&1 || true
  _build::pull_maven_image || return 1

  local maven_args=(mvn clean package)
  if [ -f "${ROOT_DIR}/Docker/maven-mirror-alternative.xml" ]; then
    maven_args+=(-s /workspace/Docker/maven-mirror-alternative.xml)
  fi
  maven_args+=(
    -DskipTests -Dmaven.javadoc.skip=true -Dno-frontends -Dspring-boot.repackage.executable=false
    "-P$(config::get LR_BUILD_PROFILE "lareferencia")"
  )

  proc::nice docker run --rm \
    --cpus="$(config::get LR_JAVA_BUILD_CPUS 2)" \
    --memory="$(config::get LR_JAVA_BUILD_MEMORY 2g)" \
    -e MAVEN_OPTS="$(config::get LR_JAVA_BUILD_OPTS "-Xmx1536m -XX:ActiveProcessorCount=2 -XX:ParallelGCThreads=2")" \
    -v "${MAVEN_CACHE_VOLUME}:/root/.m2" \
    -v "${ROOT_DIR}:/workspace" \
    -w /workspace \
    "${MAVEN_IMAGE}" \
    "${maven_args[@]}" \
    || { echo "Error: Maven build failed." >&2; return 1; }
  # (explicit check: callers run this inside `if`/`||`, where `set -e` is off,
  #  and stale JARs from a previous build would otherwise be packaged)

  # Maven ran as root: give target/ back to the host user.
  if [ "$(id -u)" != "0" ]; then
    docker run --rm -v "${ROOT_DIR}:/workspace" -w /workspace alpine \
      sh -c "chown -R $(id -u):$(id -g) */target 2>/dev/null; chmod -R ugo+rwX */target 2>/dev/null || true"
  fi

  build::write_manifests
}

_build::find_jar() {
  local module="$1"
  find "${ROOT_DIR}/${module}/target" -maxdepth 1 -name "${module}-*.jar" \
    ! -name '*-javadoc.jar' ! -name '*-sources.jar' -type f -print -quit
}

# Writes target/docker-build-info.properties (commit + jar hash) for each app,
# and checks that the harvester embeds the freshly built dark-lib.
build::write_manifests() {
  local git_commit module app_jar
  git_commit="$(git -C "${ROOT_DIR}" rev-parse --verify HEAD 2>/dev/null || printf 'unknown')"

  for module in "${JAVA_APP_MODULES[@]}"; do
    app_jar="$(_build::find_jar "${module}")"
    if [ -z "${app_jar}" ]; then
      echo "Error: packaged JAR not found for ${module}" >&2
      return 1
    fi
    {
      printf 'git.commit=%s\n' "${git_commit}"
      printf 'application.sha256=%s\n' "$(hash::sha256_file "${app_jar}")"
    } > "${ROOT_DIR}/${module}/target/docker-build-info.properties"
  done

  _build::verify_dark_lib
}

_build::verify_dark_lib() {
  local harvester_jar dark_jar dark_entry packaged_hash
  harvester_jar="$(_build::find_jar lareferencia-lrharvester-app)"
  dark_jar="$(_build::find_jar lareferencia-dark-lib)"

  if ! cmd::exists unzip; then
    echo "Warning: unzip command not found. Skipping lareferencia-dark-lib artifact verification." >&2
    return 0
  fi

  local pattern='^BOOT-INF/lib/lareferencia-dark-lib-.*\.jar$'
  dark_entry="$(unzip -Z1 "${harvester_jar}" 2>/dev/null | grep -E "${pattern}" || true)"
  # Fallback for unzip builds without -Z1 (e.g. busybox).
  [ -z "${dark_entry}" ] && dark_entry="$(unzip -l "${harvester_jar}" 2>/dev/null | awk '{print $4}' | grep -E "${pattern}" || true)"

  if [ -z "${dark_jar}" ] || [ -z "${dark_entry}" ]; then
    echo "Error: unable to verify lareferencia-dark-lib packaged in harvester (or not found)" >&2
    return 0
  fi

  packaged_hash="$(unzip -p "${harvester_jar}" "${dark_entry}" | hash::sha256_stdin)"
  if [ "${packaged_hash}" != "$(hash::sha256_file "${dark_jar}")" ]; then
    echo "Error: harvester contains a stale lareferencia-dark-lib artifact" >&2
    return 1
  fi
  printf 'dark-lib.sha256=%s\n' "${packaged_hash}" \
    >> "${ROOT_DIR}/lareferencia-lrharvester-app/target/docker-build-info.properties"
}

# --- Components (frontends + Java) ------------------------------------------------
#
# Each component is a "<name>|<function>|<log file>" triple.

_build::admin_web() { proc::nice "${ROOT_DIR}/build-admin-web.sh"; }
_build::dashboard() { proc::nice "${ROOT_DIR}/build-dashboard.sh"; }

_build::print_failure() {
  local name="$1" log="$2"
  echo -e "\n${C_RED}❌ ${name} build failed! (Log: ${log})${C_RESET}"
  echo -e "${C_YELLOW}--- Last 25 lines of ${log} ---${C_RESET}"
  tail -n 25 "${log}" >&2
}

_build::components_parallel() {
  local components=("$@")
  echo -e "\n${C_CYAN}--- Building Components in Parallel (Java Backend, Admin Web, Repository Dashboard) ---${C_RESET}"

  local pids=() i name fn log
  for i in "${!components[@]}"; do
    IFS='|' read -r name fn log <<< "${components[$i]}"
    ( "${fn}" ) > "${log}" 2>&1 &
    pids+=($!)
    echo "  ▶ [$((i + 1))/${#components[@]}] ${name} started (PID: $!)..."
  done

  local failed=0
  for i in "${!pids[@]}"; do
    IFS='|' read -r name fn log <<< "${components[$i]}"
    if wait "${pids[$i]}"; then
      echo -e "${C_GREEN}✔ ${name} completed successfully.${C_RESET}"
    else
      _build::print_failure "${name}" "${log}"
      failed=1
    fi
  done

  if [ "${failed}" -ne 0 ]; then
    echo -e "\n${C_RED}Error: One or more component builds failed. Aborting.${C_RESET}" >&2
    return 1
  fi
  echo -e "${C_GREEN}--- All components built successfully in parallel ---${C_RESET}\n"
}

# Sequential is the default: it avoids CPU saturation and server freezes.
_build::components_sequential() {
  local components=("$@")
  echo -e "\n${C_CYAN}--- Building Components Sequentially (React Admin Web, Angular Dashboard, Java Backend) ---${C_RESET}"

  local i name fn log
  for i in "${!components[@]}"; do
    IFS='|' read -r name fn log <<< "${components[$i]}"
    echo "  ▶ [$((i + 1))/${#components[@]}] Building ${name}..."
    if [ "${fn}" = "build::java" ]; then
      # Java output is also streamed to the terminal.
      ( "${fn}" 2>&1 | tee "${log}" ) || { _build::print_failure "${name}" "${log}"; return 1; }
    else
      ( "${fn}" ) > "${log}" 2>&1 || { _build::print_failure "${name}" "${log}"; return 1; }
    fi
    echo -e "  ${C_GREEN}✔ ${name} completed successfully.${C_RESET}"
  done
  echo -e "${C_GREEN}--- All components built successfully sequentially ---${C_RESET}\n"
}

build::components() {
  mkdir -p "${BUILD_LOG_DIR}"

  local admin="React Admin Web|_build::admin_web|${BUILD_LOG_DIR}/build-admin.log"
  local dashboard="Angular Dashboard|_build::dashboard|${BUILD_LOG_DIR}/build-dashboard.log"
  local java="Java Backend|build::java|${BUILD_LOG_DIR}/build-java.log"

  if [ "$(config::get BUILD_PARALLEL false)" = "true" ]; then
    _build::components_parallel "${java}" "${admin}" "${dashboard}"
  else
    _build::components_sequential "${admin}" "${dashboard}" "${java}"
  fi
}

# --- Docker images -----------------------------------------------------------------

build::all() {
  local no_cache="${1:-false}"
  solr::stage
  build::components

  echo "--- Building images using Multi-stage Dockerfiles ---"
  local profiles=(tools)
  module::is_on elastic && profiles+=(elastic)
  module::is_on watch   && profiles+=(watch)

  local build_args=(build)
  [ "${no_cache}" = true ] && build_args+=(--no-cache)

  compose::run_with_profiles "${profiles[@]}" -- "${build_args[@]}"
  echo "--- Build completed successfully ---"
  build::clean_dangling_images
}

# True when every locally-built image needed by the current selection exists
# with the tag compose will use (same commit). An empty selection counts as
# "not built" (forces a first build).
build::images_exist() {
  selection::is_empty && return 1

  local expected_tag s
  expected_tag="$(compose::image_tag)"

  for s in "${SELECTED_SERVICES[@]}"; do
    service::has_own_image "${s}" || continue
    docker image inspect "lareferencia/${s}:${expected_tag}" >/dev/null 2>&1 || return 1
  done
  return 0
}

# --- Housekeeping --------------------------------------------------------------------

build::clean_dangling_images() {
  if [ -n "$(docker images -f "dangling=true" -q 2>/dev/null || true)" ]; then
    echo "Cleaning up dangling intermediate images to reclaim disk space..."
    docker image prune -f >/dev/null 2>&1 || true
  fi
}

build::prune() {
  echo -e "\n${C_CYAN}--- Pruning Docker Build Artifacts & Cache ---${C_RESET}"
  echo "1. Removing dangling images (<none>:<none>)..."
  docker image prune -f || true

  echo -e "\n2. Removing BuildKit builder cache..."
  docker builder prune -f || true

  echo -e "\n${C_GREEN}Current Docker Disk Usage:${C_RESET}"
  docker system df || true
  echo -e "${C_GREEN}Prune completed successfully.${C_RESET}"
}
