#!/usr/bin/env bash
set -euo pipefail

STACK='lareferencia-base'
REGION='us-east-1'
PROFILE=''
while (($#)); do
  case "$1" in
    --stack) STACK=$2; shift 2 ;;
    --region) REGION=$2; shift 2 ;;
    --profile) PROFILE=$2; shift 2 ;;
    -h|--help) echo 'Usage: connect-ssm-headscale.sh [--stack NAME] [--region REGION] [--profile PROFILE]'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
aws_bin=''
for candidate in "${AWS_CLI:-}" /opt/homebrew/bin/aws "$(command -v aws 2>/dev/null || true)" /usr/local/bin/aws; do
  [[ -n "$candidate" && -x "$candidate" ]] || continue
  if "$candidate" --version >/dev/null 2>&1; then
    aws_bin="$candidate"
    break
  fi
done
[[ -n "$aws_bin" ]] || { echo 'a compatible AWS CLI is required (macOS Apple Silicon: brew install awscli)' >&2; exit 1; }
aws_args=(--region "$REGION")
[[ -n "$PROFILE" ]] && aws_args+=(--profile "$PROFILE")
instance_id="$("$aws_bin" "${aws_args[@]}" cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`HeadscaleInstanceId`].OutputValue' --output text)"
[[ -n "$instance_id" && "$instance_id" != None ]] || { echo "HeadscaleInstanceId not found in $STACK" >&2; exit 1; }
exec "$aws_bin" "${aws_args[@]}" ssm start-session --target "$instance_id"
