#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: check-bootstrap.sh [--stack NAME] [--region REGION] [--profile PROFILE] [--timeout SECONDS]' >&2
  exit 2
}

STACK=''
REGION='us-east-1'
PROFILE=''
TIMEOUT=120
while (($#)); do
  case "$1" in
    --stack) [[ $# -ge 2 ]] || usage; STACK=$2; shift 2 ;;
    --region) [[ $# -ge 2 ]] || usage; REGION=$2; shift 2 ;;
    --profile) [[ $# -ge 2 ]] || usage; PROFILE=$2; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || usage; TIMEOUT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
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

[[ -n "$STACK" ]] || usage
aws_args=(--region "$REGION")
[[ -n "$PROFILE" ]] && aws_args+=(--profile "$PROFILE")
instance_id="$("$aws_bin" "${aws_args[@]}" cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)"
[[ -n "$instance_id" && "$instance_id" != None ]] || { echo 'InstanceId output not found' >&2; exit 1; }

command_id="$("$aws_bin" "${aws_args[@]}" ssm send-command --document-name AWS-RunShellScript \
  --instance-ids "$instance_id" --comment 'lareferencia bootstrap check' \
  --parameters '{"commands":["test -f /var/lib/lareferencia/bootstrap-complete && cat /var/lib/lareferencia/bootstrap-complete || { echo MISSING:bootstrap-complete; exit 1; }"]}' \
  --query 'Command.CommandId' --output text)"

waited=0
status='Pending'
while :; do
  status="$("$aws_bin" "${aws_args[@]}" ssm get-command-invocation --command-id "$command_id" \
    --instance-id "$instance_id" --query Status --output text 2>/dev/null || echo Unknown)"
  case "$status" in Success|Failed|TimedOut|Cancelled) break ;; esac
  [[ "$waited" -ge "$TIMEOUT" ]] && { status=TimedOut; break; }
  sleep 5; waited=$((waited + 5))
done
out="$("$aws_bin" "${aws_args[@]}" ssm get-command-invocation --command-id "$command_id" \
  --instance-id "$instance_id" --query StandardOutputContent --output text 2>/dev/null || true)"
echo "instance=$instance_id status=$status"
echo "$out"
[[ "$status" == Success ]]
