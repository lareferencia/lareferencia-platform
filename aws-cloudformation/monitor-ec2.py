#!/usr/bin/env python3
"""Read-only monitor for the EC2 instance created by the CloudFormation stack."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import time
from datetime import datetime, timezone


def find_aws_cli() -> str:
    candidates = (os.environ.get("AWS_CLI"), "/opt/homebrew/bin/aws", shutil.which("aws"), "/usr/local/bin/aws")
    for candidate in candidates:
        if not candidate or not os.path.isfile(candidate) or not os.access(candidate, os.X_OK):
            continue
        if subprocess.run([candidate, "--version"], capture_output=True, check=False).returncode == 0:
            return candidate
    raise RuntimeError("a compatible AWS CLI is required (macOS Apple Silicon: brew install awscli)")


AWS_CLI = find_aws_cli()


def aws(args: list[str]) -> object:
    result = subprocess.run([AWS_CLI, *args], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def sample(stack: str, region: str | None, profile: str | None) -> dict:
    common = (["--region", region] if region else []) + (["--profile", profile] if profile else [])
    stack_data = aws([*common, "cloudformation", "describe-stacks", "--stack-name", stack,
                      "--query", "Stacks[0].Outputs", "--output", "json"])
    outputs = {item["OutputKey"]: item["OutputValue"] for item in stack_data}
    instance_id = outputs.get("InstanceId")
    if not instance_id:
        raise RuntimeError("CloudFormation stack has no InstanceId output")
    instances = aws([*common, "ec2", "describe-instances", "--instance-ids", instance_id,
                     "--query", "Reservations[0].Instances[0]", "--output", "json"])
    info = aws([*common, "ssm", "describe-instance-information", "--filters",
                f"Key=InstanceIds,Values={instance_id}", "--output", "json"])
    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "stack": stack,
        "instance": {key: instances.get(key) for key in
                      ("InstanceId", "State", "InstanceType", "Placement", "PrivateIpAddress", "PublicIpAddress")},
        "ssm": info.get("InstanceInformationList", []),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stack", required=True)
    parser.add_argument("--region")
    parser.add_argument("--profile")
    parser.add_argument("--interval", type=float, default=60)
    parser.add_argument("--output", default="-", help="JSONL output path, or - for stdout")
    args = parser.parse_args()
    stream = None if args.output == "-" else open(args.output, "a", encoding="utf-8")
    try:
        while True:
            record = json.dumps(sample(args.stack, args.region, args.profile), ensure_ascii=False)
            print(record, flush=True)
            if stream:
                stream.write(record + "\n")
                stream.flush()
            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass
    finally:
        if stream:
            stream.close()


if __name__ == "__main__":
    main()
