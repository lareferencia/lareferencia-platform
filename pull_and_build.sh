#!/bin/bash
set -eou pipefail

set -eou pipefail

# check parameters passed to script and print usage
if [ $# -lt 1 ]; then
  echo "Usage: $0 <profile>"
  echo "  profile: profile to build (default: lite)"
  echo "  options: lite, lareferencia, ibict, rcaap"

  exit 1
fi

# parameters
if [ $# -gt 0 ]; then
   PROFILE="$1"
else
   PROFILE="lite"
fi

# pull and build all modules
bash pull-all.sh
bash build.sh $PROFILE