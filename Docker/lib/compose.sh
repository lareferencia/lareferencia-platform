#!/usr/bin/env bash
# =============================================================================
# compose.sh — "Compose": everything needed to call docker compose correctly
# for this instance (project name, ports, image tag, profiles).
#
# Public API:
#   dc <compose args...>              runs docker compose with the instance env
#   compose::running_services         lists running services (one per line)
#   compose::is_running <service>
#   compose::any_running
#   compose::open_shell <service>     bash (or sh) inside a running container
#   compose::run_with_profiles <profile...> -- <compose args...>
#   compose::export_service_prefix    exports SERVICE_PREFIX / COMPOSE_PROJECT_NAME
#   compose::image_tag                tag of the images of the current checkout/commit
#   ports::for_service <service>      prints ":<host port>" (or nothing)
#   ports::offset_conflicts <offset>  ports that the offset shifts onto another base port
#   compose::check_host_conflicts <service...>
#       before `up`: fails on host ports taken outside this project, warns
#       about other LA Referencia installations on the host
# =============================================================================

# --- Port table ---------------------------------------------------------------
# Every host port is <base> + SERVICES_PORT_OFFSET.
#
#   .env suffix    base   service shown in the wizard
PORT_TABLE=(
  "VUFIND_WEB    8080   vufind-web"
  "VUFIND_DB     3307   vufind-db"
  "SOLR          8983   solr"
  "POSTGRES      5432   postgres"
  "HARVESTER     8090   harvester"
  "ENTITY_REST   8094   entity-rest"
  "ELASTIC_9200  9200   elasticsearch"
  "ELASTIC_9300  9300   elasticsearch"
  "OAI           8096   oai-pmh"
)

ports::offset() {
  local offset
  offset="$(config::get SERVICES_PORT_OFFSET 0)"
  offset="${offset//[^0-9]/}"
  echo "${offset:-0}"
}

ports::for_service() {
  local service="$1" offset row suffix base svc
  offset="$(ports::offset)"
  for row in "${PORT_TABLE[@]}"; do
    read -r suffix base svc <<< "${row}"
    if [ "${svc}" = "${service}" ]; then
      printf ":%s" $((base + offset))
      return 0
    fi
  done
}

# Exports LR_PORT_* (and persists them in .env so compose can read them).
ports::export() {
  local offset row suffix base svc
  offset="$(ports::offset)"
  for row in "${PORT_TABLE[@]}"; do
    read -r suffix base svc <<< "${row}"
    export "LR_PORT_${suffix}=$((base + offset))"
    config::set "LR_PORT_${suffix}" "$((base + offset))"
  done
  LR_IP_HARVESTER="$(config::get LR_IP_HARVESTER "127.0.0.1")"
  export LR_IP_HARVESTER
}

# ports::offset_conflicts <offset>
#   Prints "<port> <suffix> <other suffix>" for every port that <offset> shifts
#   onto the base port of another service (e.g. 10: VuFind 8080 → 8090, the
#   Harvester of an instance without offset), and "<port> <suffix> -" for ports
#   beyond 65535. No output = the offset is safe next to an offset-0 instance.
ports::offset_conflicts() {
  local offset="$1" row other suffix base svc osuffix obase osvc shifted
  for row in "${PORT_TABLE[@]}"; do
    read -r suffix base svc <<< "${row}"
    shifted=$((base + offset))
    if [ "${shifted}" -gt 65535 ]; then
      echo "${shifted} ${suffix} -"
      continue
    fi
    for other in "${PORT_TABLE[@]}"; do
      read -r osuffix obase osvc <<< "${other}"
      if [ "${osuffix}" != "${suffix}" ] && [ "${shifted}" -eq "${obase}" ]; then
        echo "${shifted} ${suffix} ${osuffix}"
      fi
    done
  done
  return 0
}

# --- Host conflicts -------------------------------------------------------------
# Two installations on one host share the host ports. A port clash only shows up
# halfway through `docker compose up`, after other containers were already
# recreated, so `up` checks first.

# Services compose starts as dependencies (mirrors depends_on in docker-compose.yml).
_compose::dependencies() {
  case "$1" in
    vufind-web)                          echo "vufind-db solr" ;;
    harvester|entity-rest|shell|db-init) echo "postgres solr" ;;
    oai-pmh)                             echo "solr" ;;
  esac
  return 0
}

# ports::published_by <service...>   "<host port> <service>" for the services and their dependencies
ports::published_by() {
  local services=() s d
  for s in "$@"; do
    services+=("${s}")
    for d in $(_compose::dependencies "${s}"); do services+=("${d}"); done
  done
  [ "${#services[@]}" -gt 0 ] || return 0

  local offset row suffix base svc
  offset="$(ports::offset)"
  for row in "${PORT_TABLE[@]}"; do
    read -r suffix base svc <<< "${row}"
    if list::contains "${svc}" "${services[@]}"; then
      echo "$((base + offset)) ${svc}"
    fi
  done
  return 0
}

# True when a process on the host listens on the TCP port (best effort).
_ports::host_listening() {
  if cmd::exists ss; then
    [ -n "$(ss -Hltn "sport = :$1" 2>/dev/null)" ]
  elif cmd::exists lsof; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1
  fi
}

compose::check_host_conflicts() {
  compose::export_service_prefix

  # name|project|working dir|image|ports of every running container
  local containers
  containers="$(docker ps --format '{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Image}}|{{.Ports}}' 2>/dev/null || true)"

  # 1. Host ports this `up` publishes, taken by someone else.
  local conflicts=() port svc owner own name project dir image ports
  while read -r port svc; do
    [ -n "${port}" ] || continue
    owner="" own=false
    while IFS='|' read -r name project dir image ports; do
      [ -n "${name}" ] || continue
      [[ ", ${ports}" == *":${port}->"* ]] || continue
      if [ "${project}" = "${COMPOSE_PROJECT_NAME}" ]; then
        own=true
      else
        owner="container ${name} (project ${project:-none}${dir:+, ${dir}})"
      fi
    done <<< "${containers}"

    if [ -z "${owner}" ] && [ "${own}" = false ] && _ports::host_listening "${port}"; then
      owner="a process on the host"
    fi
    if [ -n "${owner}" ]; then
      conflicts+=("${port} (${svc}) is in use by ${owner}")
    fi
  done <<< "$(ports::published_by "$@")"

  if [ "${#conflicts[@]}" -gt 0 ]; then
    ui::error "❌ Cannot start: host ports of project ${COMPOSE_PROJECT_NAME} (${ROOT_DIR}) are already in use:"
    local c
    for c in "${conflicts[@]}"; do ui::error "   - ${c}"; done
    ui::error "Nothing was built, stopped or recreated."
    ui::error "Stop the other installation, or give this one free ports, e.g.: ./Docker/docker.sh up --offset=1000"
    return 1
  fi

  # 2. Other LA Referencia installations running on this host.
  local others
  others="$(printf '%s\n' "${containers}" | awk -F'|' -v self="${COMPOSE_PROJECT_NAME}" \
    '$4 ~ /^lareferencia\// && $2 != self { print "   - project " ($2 == "" ? "none" : $2) "  " $3 }' | sort -u)"
  [ -n "${others}" ] || return 0

  ui::warn "⚠️  Other LA Referencia installation(s) running on this host:"
  ui::warn "${others}"
  ui::warn "   This checkout: ${ROOT_DIR} (project ${COMPOSE_PROJECT_NAME})"

  if [ "$(config::get LR_ALLOW_OTHER_INSTANCES false)" = true ] || [ ! -t 0 ]; then
    return 0
  fi
  local answer
  read -r -p "Continue with THIS checkout? [y/N] " answer || true
  case "${answer}" in
    y|Y|yes|s|S|sim) return 0 ;;
    *) ui::error "Aborted. Nothing was built, stopped or recreated."; return 1 ;;
  esac
}

# --- Instance identity --------------------------------------------------------

compose::export_service_prefix() {
  local prefix
  prefix="$(config::get SERVICE_PREFIX "")"
  prefix="${prefix//\"/}"
  prefix="${prefix//\'/}"

  if [ -n "${prefix}" ]; then
    export SERVICE_PREFIX="${prefix}"
    local clean_name="${prefix%[_-]}"
    export COMPOSE_PROJECT_NAME="${clean_name//_/-}"
  else
    # No prefix: derive a stable project name from the checkout path.
    export SERVICE_PREFIX=""
    COMPOSE_PROJECT_NAME="lareferencia-$(hash::short "${ROOT_DIR}")"
    export COMPOSE_PROJECT_NAME
  fi

  config::set "SERVICE_PREFIX" "${SERVICE_PREFIX}"
  config::set "COMPOSE_PROJECT_NAME" "${COMPOSE_PROJECT_NAME}"
}

# Image tag of the CURRENT checkout = <build profile>-<checkout hash>[-<git short commit>]
# Computed every time (the value saved in .env is stale after a `git pull`).
compose::image_tag() {
  local tag
  tag="$(config::get LR_BUILD_PROFILE "lareferencia")-$(hash::short "${ROOT_DIR}")"

  if git::is_repo "${ROOT_DIR}"; then
    local commit
    commit="$(git -C "${ROOT_DIR}" rev-parse --short=7 HEAD 2>/dev/null || true)"
    [ -n "${commit}" ] && tag="${tag}-${commit}"
  fi
  echo "${tag}"
}

compose::export_image_tag() {
  LR_IMAGE_TAG="$(compose::image_tag)"
  export LR_IMAGE_TAG
  config::set "LR_IMAGE_TAG" "${LR_IMAGE_TAG}"
}

# Writes COMPOSE_PROFILES from the enabled modules.
compose::sync_profiles() {
  local profiles=() module profile
  for module in $(module::enabled); do
    profile="$(module::compose_profile "${module}")"
    [ -n "${profile}" ] && profiles+=("${profile}")
  done

  local joined
  joined="$(list::join , ${profiles[@]+"${profiles[@]}"})"
  export COMPOSE_PROFILES="${joined}"
  config::set "COMPOSE_PROFILES" "${joined}"
}

# --- docker compose wrapper ---------------------------------------------------

compose::binary() {
  if ! docker compose version >/dev/null 2>&1 && cmd::exists docker-compose; then
    echo "docker-compose"
  else
    echo "docker compose"
  fi
}

dc() {
  config::ensure_file
  ports::export
  compose::export_service_prefix
  compose::export_image_tag
  compose::sync_profiles

  local external_solr
  external_solr="$(config::get SOLR_EXTERNAL_URL "")"
  [ -n "${external_solr}" ] && export SOLR_HOST="${external_solr}"

  local env_args=()
  [ -f "${ENV_FILE}" ] && env_args+=(--env-file "${ENV_FILE}")

  # shellcheck disable=SC2046 # "docker compose" must split into two words
  $(compose::binary) -f "${COMPOSE_FILE}" ${env_args[@]+"${env_args[@]}"} "$@"
}

# --- Queries --------------------------------------------------------------------

compose::running_services() {
  dc ps --status running --services 2>/dev/null || true
}

compose::is_running() {
  compose::running_services | grep -Fxq "$1"
}

compose::any_running() {
  [ -n "$(compose::running_services)" ]
}

compose::open_shell() {
  dc exec "$1" bash || dc exec "$1" sh
}

# compose::run_with_profiles <profile...> -- <compose args...>
#   e.g. compose::run_with_profiles tools elastic -- up -d shell
#   Empty profile names are ignored.
compose::run_with_profiles() {
  local profile_args=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    [ -n "$1" ] && profile_args+=(--profile "$1")
    shift
  done
  [ "$#" -gt 0 ] && shift  # drop the "--"
  dc ${profile_args[@]+"${profile_args[@]}"} "$@"
}
