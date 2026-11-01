#!/usr/bin/env bash
# =============================================================================
# docker.sh — Entry point for managing the LA Referencia platform with Docker.
#
#   ./Docker/docker.sh wizard        interactive assistant (recommended)
#   ./Docker/docker.sh help          list every command
#
# This file only bootstraps the environment and dispatches the command.
# The logic lives in Docker/lib, one file per responsibility:
#
#   lib/core/utils.sh       generic helpers (lists, text, hashes, git)
#   lib/core/ui.sh          colors, gum wrapper, messages
#   lib/core/progress.sh    background runner with live progress panel
#   lib/config.sh           Config         — Docker/.env read/write, resource profiles
#   lib/system.sh           System         — host requirements (docker, compose, daemon)
#   lib/settings.sh         Settings       — user settings and their validation rules
#   lib/modules.sh          Module/Service — module registry, states, dependencies
#   lib/compose.sh          Compose        — `dc` wrapper, ports, project name, image tag
#   lib/selection.sh        ServiceSelection — services/profiles a command acts on
#   lib/search.sh           VuFind / Solr  — checkout and core staging
#   lib/workspace.sh        Workspace      — Java modules (githelper, workspace.ini)
#   lib/build.sh            Builder        — Maven, frontends, docker images
#   lib/database.sh         Database/PgUpgrade/LrShell — postgres, init-db,
#                           major version upgrade/rollback, Spring Shell
#   lib/users.sh            HarvesterUsers — admin accounts of the harvester
#   lib/data.sh             DataStore      — bind-mounted volumes and reset
#   lib/backup.sh           Backup         — backup script, cron/systemd scheduling
#   lib/templates/          files copied verbatim (e.g. backup restore.sh)
#
#   MVC-like layering:
#     model / services  lib/*.sh          rules, files, docker, SQL, .env
#     CLI controller    lib/commands.sh   argument parsing + command table
#     wizard views      lib/wizard/*.sh   screens only: render, ask, call a service
#
# Conventions: functions are namespaced as `<namespace>::<method>` (a poor
# man's class); names starting with `_` are private to their file.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_SH="${SCRIPT_DIR}/docker.sh"   # used to re-invoke ourselves (wizard, backups)
LIB_DIR="${SCRIPT_DIR}/lib"

COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
DATA_DIR="${ROOT_DIR}/Docker/data"
VOLUME_DIR="${ROOT_DIR}/Docker/volume"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

# VuFind is not versioned in this repository: make sure its directory exists.
mkdir -p "${ROOT_DIR}/vufind"

# shellcheck source=/dev/null
for lib in \
  core/utils.sh core/ui.sh core/progress.sh \
  config.sh system.sh modules.sh compose.sh selection.sh settings.sh \
  search.sh workspace.sh build.sh database.sh users.sh data.sh backup.sh \
  commands.sh \
  wizard/status.sh wizard/modules.sh wizard/shell.sh wizard/users.sh \
  wizard/settings.sh wizard/backup.sh wizard/postgres.sh wizard/main.sh
do
  source "${LIB_DIR}/${lib}"
done
unset lib

command::dispatch "$@"
