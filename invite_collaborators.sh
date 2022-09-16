#!/bin/bash
set -eou pipefail

GITHUB_API_URL="/repos/lareferencia/{PROJECT}/collaborators/{USER}"

if [ $# -gt 0 ]; then
   USER="$1"
else
   exit 1
fi


all_projects=(
  "lareferencia-docker"
  "lareferencia-platform"
  "lareferencia-oclc-harvester"
  "lareferencia-core-lib"
  "lareferencia-entity-lib"
  "lareferencia-indexing-filters-lib"
  "lareferencia-contrib-rcaap"
  "lareferencia-contrib-ibict"
  "lareferencia-shell"
  "lareferencia-shell-entity-plugin"
  "lareferencia-lrharvester-app"
  "lareferencia-entity-rest"
)

LAREFERENCIA_PROJECTS=("${all_projects[@]}")

msg() {
  echo -e "\x1B[32m[LAREFERENCIA]\x1B[0m $1"
}

msg_scoped() {
  echo -e "\x1B[32m[LAREFERENCIA]\x1B[0m\x1B[33m[$1]\x1B[0m $2"
}

msg_error() {
  echo -e "\x1B[32m[LAREFERENCIA]\x1B[0m\x1B[31m[Error]\x1B[0m $1"
  exit 1
}

_show_config() {
  msg "LAREFERENCIA_GITHUB_REPO: $GITHUB_API_URL"
  msg "LAREFERENCIA_PROJECTS: $(printf '%s ' ${LAREFERENCIA_PROJECTS[@]})"
}


_invite_to_project() {
  project=$1
  project_repo=$(echo $GITHUB_API_URL | sed -e 's/{PROJECT}/'$project'/g' | sed -e 's/{USER}/'$USER'/g')
  
  (msg_scoped $project "Invite $USER to $project" && gh api --method PUT -H 'Accept: application/vnd.github.v3+json' $project_repo || msg_error "Failed to build $project") || exit 255
}

_invite() {
  projects="$@"
  printf "%s\0" ${projects[@]} | xargs -0 -I% -n 1 -P1 bash -c '_invite_to_project %'
}

_configure() {
  # exports for xargs/parallel runs
  export -f msg
  export -f msg_scoped
  export -f msg_error
  export -f _invite_to_project
  export -p GITHUB_API_URL
  export -p USER
}

help() {
  echo "Invite collaborator to selected projects:"
  echo ""
  echo "  $0 [user...]"
  echo ""
  echo "Show help:"
  echo ""
  echo "  $0 help"
  echo ""
}

pull() {
  _configure
  _show_config
  _invite ${LAREFERENCIA_PROJECTS[@]}
  
  msg "Done."
}

[ "${1:-}" == "help" ] && help && exit 0

pull
