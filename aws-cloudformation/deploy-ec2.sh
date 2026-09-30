#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: deploy-ec2.sh --config FILE [--stack NAME] [--region REGION]
                      [--profile PROFILE] [--plan|--apply]

Creates a CloudFormation change set with Rain by default. --apply executes it.
EOF
  exit 2
}

CONFIG=''
STACK='lareferencia-ec2'
REGION=''
PROFILE=''
MODE='plan'

while (($#)); do
  case "$1" in
    --config) [[ $# -ge 2 ]] || usage; CONFIG=$2; shift 2 ;;
    --stack) [[ $# -ge 2 ]] || usage; STACK=$2; shift 2 ;;
    --region) [[ $# -ge 2 ]] || usage; REGION=$2; shift 2 ;;
    --profile) [[ $# -ge 2 ]] || usage; PROFILE=$2; shift 2 ;;
    --plan) MODE='plan'; shift ;;
    --apply) MODE='apply'; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$CONFIG" ]] || { echo '--config is required' >&2; usage; }
[[ -f "$CONFIG" ]] || { echo "config not found: $CONFIG" >&2; exit 1; }
command -v rain >/dev/null || { echo 'rain is required in PATH' >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_name="$(basename "$CONFIG" .yaml)"
template_name="${config_name#lareferencia-}"
template="$script_dir/${template_name}.yaml"
[[ -f "$template" ]] || { echo "template not found: $template" >&2; exit 1; }
args=(deploy "$template" "$STACK" --config "$CONFIG" --no-analytics)
[[ -n "$REGION" ]] && args+=(--region "$REGION")
[[ -n "$PROFILE" ]] && args+=(--profile "$PROFILE")
if [[ "$MODE" == 'plan' ]]; then
  args+=(--no-exec)
else
  # Keep apply interactive so Rain can request HeadscaleAuthKey when omitted.
  :
fi
exec rain "${args[@]}"
