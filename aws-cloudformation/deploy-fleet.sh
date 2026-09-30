#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: deploy-fleet.sh --configs-dir DIR [--region REGION]
                       [--profile PROFILE] [--plan|--apply]

Deploys one independent CloudFormation stack per *.yaml file in DIR.
The stack name is the file name without the .yaml suffix.
EOF
  exit 2
}

CONFIGS_DIR=''
REGION=''
PROFILE=''
MODE='plan'

while (($#)); do
  case "$1" in
    --configs-dir) [[ $# -ge 2 ]] || usage; CONFIGS_DIR=$2; shift 2 ;;
    --region) [[ $# -ge 2 ]] || usage; REGION=$2; shift 2 ;;
    --profile) [[ $# -ge 2 ]] || usage; PROFILE=$2; shift 2 ;;
    --plan) MODE='plan'; shift ;;
    --apply) MODE='apply'; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$CONFIGS_DIR" ]] || { echo '--configs-dir is required' >&2; usage; }
[[ -d "$CONFIGS_DIR" ]] || { echo "directory not found: $CONFIGS_DIR" >&2; exit 1; }
command -v rain >/dev/null || { echo 'rain is required in PATH' >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shopt -s nullglob
configs=("$CONFIGS_DIR"/*.yaml)
(( ${#configs[@]} > 0 )) || { echo "no .yaml configs found in $CONFIGS_DIR" >&2; exit 1; }

for config in "${configs[@]}"; do
  filename="$(basename "$config")"
  stack="${filename%.yaml}"
  echo "==> $stack"
  template_name="${stack#lareferencia-}"
  template="$script_dir/$template_name.yaml"
  [[ -f "$template" ]] || { echo "template not found for $stack: $template" >&2; exit 1; }
  args=(deploy "$template" "$stack" --config "$config" --no-analytics)
  [[ -n "$REGION" ]] && args+=(--region "$REGION")
  [[ -n "$PROFILE" ]] && args+=(--profile "$PROFILE")
  if [[ "$MODE" == 'plan' ]]; then
    args+=(--no-exec)
  else
    # Keep apply interactive so Rain can request HeadscaleAuthKey when omitted.
    :
  fi
  rain "${args[@]}"
done
