#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
DATA_DIR="${ROOT_DIR}/Docker/data"
ENV_FILE="${ROOT_DIR}/.env"

DEFAULT_UP_SERVICES=(vufind-db solr postgres vufind-web harvester dashboard-rest)
DEFAULT_VUFIND_REPO_URL="https://github.com/vufind-org/vufind"
DEFAULT_VUFIND_REF="v11.0.1"


dc() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

sync_solr_assets_from_vufind() {
  src_import="${ROOT_DIR}/vufind/import"
  src_jars="${ROOT_DIR}/vufind/solr/vufind/jars"
  dst_import="${ROOT_DIR}/Docker/solr/import"
  dst_jars="${ROOT_DIR}/Docker/solr/jars"

  if [ ! -d "${src_import}" ]; then
    echo "No existe fuente de import en ${src_import}" >&2
    exit 1
  fi

  if [ ! -d "${src_jars}" ]; then
    echo "No existe fuente de jars en ${src_jars}" >&2
    exit 1
  fi

  echo "Sincronizando Docker/solr/import desde vufind/import..."
  rm -rf "${dst_import}"
  mkdir -p "${dst_import}"
  cp -a "${src_import}/." "${dst_import}/"

  echo "Sincronizando Docker/solr/jars desde vufind/solr/vufind/jars..."
  rm -rf "${dst_jars}"
  mkdir -p "${dst_jars}"
  cp -a "${src_jars}/." "${dst_jars}/"

  echo "Sync Solr completado."
}

ensure_vufind_checkout() {
  cloned_vufind=false

  if [ -d "${ROOT_DIR}/vufind" ]; then
    :
  else
    repo_url="${VUFIND_REPO_URL:-$(get_env_var VUFIND_REPO_URL "${DEFAULT_VUFIND_REPO_URL}")}"
    repo_ref="${VUFIND_REF:-$(get_env_var VUFIND_REF "${DEFAULT_VUFIND_REF}")}"

    echo "No se encontró el directorio ${ROOT_DIR}/vufind."

    if [ -t 0 ]; then
      read -r -p "Repositorio GitHub de VuFind [${repo_url}]: " input_repo
      if [ -n "${input_repo}" ]; then
        repo_url="${input_repo}"
      fi

      read -r -p "Branch/tag de VuFind [${repo_ref}]: " input_ref
      if [ -n "${input_ref}" ]; then
        repo_ref="${input_ref}"
      fi
    else
      echo "Sin terminal interactiva; usando defaults:"
      echo "  repo=${repo_url}"
      echo "  ref=${repo_ref}"
    fi

    if ! command -v git >/dev/null 2>&1; then
      echo "git no está disponible en PATH; no se puede clonar VuFind." >&2
      exit 1
    fi

    echo "Clonando VuFind: ${repo_url} (${repo_ref})..."
    git clone --branch "${repo_ref}" --single-branch "${repo_url}" "${ROOT_DIR}/vufind"
    cloned_vufind=true
  fi

  if [ "${cloned_vufind}" = true ]; then
    echo "Sincronizando assets Solr (import/jars) desde VuFind..."
    sync_solr_assets_from_vufind
  fi
}

set_env_var() {
  key="$1"
  value="$2"
  file="$3"

  touch "${file}"
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
    sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*$|${key}=${value}|g" "${file}"
    rm -f "${file}.bak"
  else
    printf "%s=%s\n" "${key}" "${value}" >> "${file}"
  fi
}

get_env_var() {
  key="$1"
  default_value="$2"
  value=""

  if [ -f "${ENV_FILE}" ]; then
    value="$(awk -F= -v k="${key}" '$1 ~ "^[[:space:]]*"k"[[:space:]]*$" {v=$2} END {gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/^"|"$/, "", v); print v}' "${ENV_FILE}" || true)"
  fi

  if [ -z "${value}" ]; then
    value="${default_value}"
  fi
  printf "%s\n" "${value}"
}

get_current_theme() {
  theme=""
  theme="$(get_env_var VUFIND_THEME "")"

  if [ -z "${theme}" ] && [ -f "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" ]; then
    theme="$(awk -F= '/^[[:space:]]*theme[[:space:]]*=/ {gsub(/[[:space:]"]/, "", $2); print $2; exit}' "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" || true)"
  fi

  if [ -z "${theme}" ]; then
    theme="bootstrap5"
  fi
  printf "%s\n" "${theme}"
}

usage() {
  cat <<'USAGE'
Uso: ./Docker/dev.sh <comando> [opciones]

Nota:
  Si no existe ./vufind, se solicita repo/ref y se hace git clone antes de ejecutar.
  Al clonar VuFind, Docker/solr/import y Docker/solr/jars se sincronizan automáticamente.
  Defaults configurables en .env:
    VUFIND_REPO_URL=https://github.com/vufind-org/vufind
    VUFIND_REF=v11.0.1

Comandos principales:
  up [--build] [--elastic] [--watch] [servicios...]
  down
  start [servicios...]
  stop [servicios...]
  restart [servicios...]
  build [servicios...]
  pull [servicios...]
  ps
  logs [servicio] [-f]
  health

Comandos de plataforma:
  init-db [comando-shell...]
      Ejecuta migración de BD via lareferencia-shell (no interactivo).
      Default: database_migrate

  shell-interactive [comando-shell...]
      Ejecuta lareferencia-shell en modo interactivo (perfil tools).
      Sin argumentos abre prompt interactivo del shell.

  reset-data [--yes]
      Detiene contenedores y borra TODA la data persistida en Docker/data.
      Sin --yes pide confirmación interactiva.

  shell <servicio>
      Abre shell interactiva en: vufind-web | vufind-db | postgres | solr | harvester | dashboard-rest

Comandos VuFind:
  vufind debug <show|on|off>
      Alterna debug/dev y display errors de VuFind via .env.
  vufind theme <show|set <nombre>>
      Muestra o actualiza el theme de VuFind.
  vufind db
      Consola MariaDB de VuFind (root/root).
  vufind cli <args...>
      Ejecuta: php public/index.php <args...> en vufind-web.
  vufind shell [web|db|solr]
      Shell interactiva de servicios VuFind.

Comandos opcionales:
  solr <sync-from-vufind|status>
  elastic <on|off|logs|status>
  watch <start|stop|logs|status>
  exec <servicio> <cmd...>
  compose <args...>

Ejemplos:
  ./Docker/dev.sh up --build
  ./Docker/dev.sh init-db
  ./Docker/dev.sh shell-interactive
  ./Docker/dev.sh shell-interactive database_migrate
  ./Docker/dev.sh solr sync-from-vufind
  ./Docker/dev.sh vufind debug on
  ./Docker/dev.sh vufind debug off
  ./Docker/dev.sh vufind theme set bootstrap5
  ./Docker/dev.sh reset-data --yes
  ./Docker/dev.sh elastic on
  ./Docker/dev.sh up --elastic
USAGE
}

cmd="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

ensure_vufind_checkout

case "${cmd}" in
  help|-h|--help)
    usage
    ;;

  up)
    build_flag=false
    include_elastic=false
    include_watch=false
    services=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --build)
          build_flag=true
          ;;
        --elastic)
          include_elastic=true
          ;;
        --watch)
          include_watch=true
          ;;
        *)
          services+=("$1")
          ;;
      esac
      shift
    done

    if [ "${#services[@]}" -eq 0 ]; then
      services=("${DEFAULT_UP_SERVICES[@]}")
    fi

    args=(up -d)
    if [ "${build_flag}" = true ]; then
      args+=(--build)
    fi

    profiles=()
    if [ "${include_elastic}" = true ]; then
      profiles+=(--profile elastic)
      services+=(elasticsearch)
    fi
    if [ "${include_watch}" = true ]; then
      profiles+=(--profile watch)
      services+=(vufind-scss-watch)
    fi

    if [ "${#profiles[@]}" -gt 0 ]; then
      dc "${profiles[@]}" "${args[@]}" "${services[@]}"
    else
      dc "${args[@]}" "${services[@]}"
    fi
    ;;

  down)
    dc down --remove-orphans
    ;;

  start)
    if [ "$#" -eq 0 ]; then
      dc start "${DEFAULT_UP_SERVICES[@]}"
    else
      dc start "$@"
    fi
    ;;

  stop)
    if [ "$#" -eq 0 ]; then
      dc stop "${DEFAULT_UP_SERVICES[@]}"
    else
      dc stop "$@"
    fi
    ;;

  restart)
    if [ "$#" -eq 0 ]; then
      dc restart "${DEFAULT_UP_SERVICES[@]}"
    else
      dc restart "$@"
    fi
    ;;

  build)
    if [ "$#" -eq 0 ]; then
      dc build vufind-web solr harvester dashboard-rest shell
    else
      dc build "$@"
    fi
    ;;

  pull)
    if [ "$#" -eq 0 ]; then
      dc pull vufind-db postgres elasticsearch vufind-scss-watch
    else
      dc pull "$@"
    fi
    ;;

  ps)
    dc ps
    ;;

  logs)
    if [ "$#" -eq 0 ]; then
      dc logs -f --tail=200
    else
      service="$1"
      shift || true
      dc logs --tail=200 "$@" "${service}"
    fi
    ;;

  health)
    echo "== docker compose ps =="
    dc ps
    echo
    echo "== endpoints =="
    curl -fsS -o /dev/null -w "http://localhost:8080 -> HTTP %{http_code}\n" http://localhost:8080/ || true
    curl -fsS -o /dev/null -w "http://localhost:8090 -> HTTP %{http_code}\n" http://localhost:8090/ || true
    curl -fsS -o /dev/null -w "http://localhost:8092 -> HTTP %{http_code}\n" http://localhost:8092/ || true
    curl -fsS -o /dev/null -w "http://localhost:8983/solr -> HTTP %{http_code}\n" http://localhost:8983/solr || true
    ;;

  init-db)
    dc up -d postgres
    shell_cmd=("$@")
    if [ "${#shell_cmd[@]}" -eq 0 ]; then
      shell_cmd=(database_migrate)
    fi
    dc --profile tools run --rm shell "${shell_cmd[@]}"
    ;;

  shell-interactive)
    dc up -d postgres solr
    if [ "$#" -eq 0 ]; then
      dc --profile tools run --rm shell
    else
      dc --profile tools run --rm shell "$@"
    fi
    ;;

  reset-data)
    auto_yes=false

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --yes)
          auto_yes=true
          ;;
        *)
          echo "Uso: ./Docker/dev.sh reset-data [--yes]" >&2
          exit 1
          ;;
      esac
      shift
    done

    if [ ! -d "${DATA_DIR}" ]; then
      echo "No existe el directorio de data: ${DATA_DIR}" >&2
      exit 1
    fi

    case "${DATA_DIR}" in
      */Docker/data) ;;
      *)
        echo "Ruta de data inválida: ${DATA_DIR}" >&2
        exit 1
        ;;
    esac

    if [ "${auto_yes}" != true ]; then
      echo "Esto va a borrar TODA la data persistida en: ${DATA_DIR}"
      echo "Servicios afectados: postgres, solr, vufind-db, elasticsearch y stores locales."
      read -r -p "Escribe RESET para confirmar: " confirmation
      if [ "${confirmation}" != "RESET" ]; then
        echo "Operación cancelada."
        exit 1
      fi
    fi

    echo "Deteniendo contenedores..."
    dc down --remove-orphans || true

    echo "Borrando contenido persistido..."
    find "${DATA_DIR}" -mindepth 1 -type f ! -name '.gitkeep' -delete
    find "${DATA_DIR}" -mindepth 1 -type l -delete
    find "${DATA_DIR}" -mindepth 1 -type d -empty -delete

    echo "Data reset completado."
    ;;

  vufind)
    sub="${1:-help}"
    if [ "$#" -gt 0 ]; then
      shift
    fi

    case "${sub}" in
      debug)
        action="${1:-show}"
        case "${action}" in
          show)
            echo "VUFIND_ENV=$(get_env_var VUFIND_ENV production)"
            echo "VUFIND_SYSTEM_DEBUG=$(get_env_var VUFIND_SYSTEM_DEBUG false)"
            echo "VUFIND_PHP_DISPLAY_ERRORS=$(get_env_var VUFIND_PHP_DISPLAY_ERRORS 0)"
            echo "VUFIND_PHP_DISPLAY_STARTUP_ERRORS=$(get_env_var VUFIND_PHP_DISPLAY_STARTUP_ERRORS 0)"
            echo "VUFIND_PHP_ERROR_REPORTING=$(get_env_var VUFIND_PHP_ERROR_REPORTING E_ALL)"
            echo "VUFIND_PHP_HTML_ERRORS=$(get_env_var VUFIND_PHP_HTML_ERRORS 0)"
            if [ -f "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" ]; then
              echo
              echo "config.ini local:"
              awk -F= '/^[[:space:]]*(debug|autoConfigure)[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0}' "${ROOT_DIR}/vufind/local/docker/config/vufind/config.ini" || true
            fi
            ;;
          on)
            set_env_var "VUFIND_ENV" "development" "${ENV_FILE}"
            set_env_var "VUFIND_SYSTEM_DEBUG" "true" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_ERRORS" "1" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_STARTUP_ERRORS" "1" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_ERROR_REPORTING" "E_ALL" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_HTML_ERRORS" "1" "${ENV_FILE}"
            echo "Debug de VuFind activado en ${ENV_FILE}"
            dc up -d vufind-web
            ;;
          off)
            set_env_var "VUFIND_ENV" "production" "${ENV_FILE}"
            set_env_var "VUFIND_SYSTEM_DEBUG" "false" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_ERRORS" "0" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_DISPLAY_STARTUP_ERRORS" "0" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_ERROR_REPORTING" "E_ALL" "${ENV_FILE}"
            set_env_var "VUFIND_PHP_HTML_ERRORS" "0" "${ENV_FILE}"
            echo "Debug de VuFind desactivado en ${ENV_FILE}"
            dc up -d vufind-web
            ;;
          *)
            echo "Uso: ./Docker/dev.sh vufind debug <show|on|off>" >&2
            exit 1
            ;;
        esac
        ;;

      theme)
        action="${1:-show}"
        case "${action}" in
          show)
            echo "VUFIND_THEME=$(get_current_theme)"
            ;;
          set)
            name="${2:-}"
            if [ -z "${name}" ]; then
              echo "Uso: ./Docker/dev.sh vufind theme set <nombre>" >&2
              exit 1
            fi
            set_env_var "VUFIND_THEME" "${name}" "${ENV_FILE}"
            echo "VUFIND_THEME=${name} escrito en ${ENV_FILE}"
            dc up -d vufind-web
            ;;
          *)
            echo "Uso: ./Docker/dev.sh vufind theme <show|set <nombre>>" >&2
            exit 1
            ;;
        esac
        ;;

      db)
        dc exec vufind-db mariadb -uroot -proot
        ;;

      cli)
        if [ "$#" -eq 0 ]; then
          echo "Uso: ./Docker/dev.sh vufind cli <args...>" >&2
          exit 1
        fi
        dc exec vufind-web php public/index.php "$@"
        ;;

      shell)
        target="${1:-web}"
        case "${target}" in
          web) dc exec vufind-web bash ;;
          db) dc exec vufind-db sh ;;
          solr) dc exec solr bash ;;
          *)
            echo "Servicio inválido: ${target} (usa web|db|solr)" >&2
            exit 1
            ;;
        esac
        ;;

      help|-h|--help)
        echo "Uso: ./Docker/dev.sh vufind <debug|theme|db|cli|shell>"
        echo "  debug <show|on|off>"
        echo "  theme <show|set <nombre>>"
        echo "  db"
        echo "  cli <args...>"
        echo "  shell [web|db|solr]"
        ;;

      *)
        echo "Subcomando inválido para vufind: ${sub}" >&2
        echo "Uso: ./Docker/dev.sh vufind <debug|theme|db|cli|shell>" >&2
        exit 1
        ;;
    esac
    ;;

  shell)
    svc="${1:-}"
    if [ -z "${svc}" ]; then
      echo "Uso: ./Docker/dev.sh shell <servicio>" >&2
      exit 1
    fi
    dc exec "${svc}" bash
    ;;

  solr)
    sub="${1:-status}"
    case "${sub}" in
      sync-from-vufind|sync)
        sync_solr_assets_from_vufind
        ;;
      status)
        echo "VuFind import:"
        ls -la "${ROOT_DIR}/vufind/import" 2>/dev/null | sed -n '1,8p' || true
        echo
        echo "Docker import:"
        ls -la "${ROOT_DIR}/Docker/solr/import" 2>/dev/null | sed -n '1,8p' || true
        echo
        echo "VuFind jars:"
        ls -la "${ROOT_DIR}/vufind/solr/vufind/jars" 2>/dev/null | sed -n '1,8p' || true
        echo
        echo "Docker jars:"
        ls -la "${ROOT_DIR}/Docker/solr/jars" 2>/dev/null | sed -n '1,8p' || true
        ;;
      *)
        echo "Subcomando inválido para solr: ${sub}" >&2
        echo "Uso: ./Docker/dev.sh solr <sync-from-vufind|status>" >&2
        exit 1
        ;;
    esac
    ;;

  elastic)
    sub="${1:-status}"
    case "${sub}" in
      on)
        dc --profile elastic up -d elasticsearch
        ;;
      off)
        dc --profile elastic stop elasticsearch
        ;;
      logs)
        dc --profile elastic logs -f --tail=200 elasticsearch
        ;;
      status)
        dc --profile elastic ps elasticsearch
        ;;
      *)
        echo "Subcomando inválido para elastic: ${sub}" >&2
        exit 1
        ;;
    esac
    ;;

  watch)
    sub="${1:-status}"
    case "${sub}" in
      start)
        dc --profile watch up -d vufind-scss-watch
        ;;
      stop)
        dc --profile watch stop vufind-scss-watch
        ;;
      logs)
        dc --profile watch logs -f --tail=200 vufind-scss-watch
        ;;
      status)
        dc --profile watch ps vufind-scss-watch
        ;;
      *)
        echo "Subcomando inválido para watch: ${sub}" >&2
        exit 1
        ;;
    esac
    ;;

  exec)
    if [ "$#" -lt 2 ]; then
      echo "Uso: ./Docker/dev.sh exec <servicio> <cmd...>" >&2
      exit 1
    fi
    svc="$1"
    shift
    dc exec "${svc}" "$@"
    ;;

  compose)
    dc "$@"
    ;;

  *)
    echo "Comando inválido: ${cmd}" >&2
    usage
    exit 1
    ;;
esac
