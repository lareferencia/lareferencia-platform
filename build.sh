#!/bin/bash
set -eou pipefail

# check parameters passed to script and print usage
if [ $# -lt 1 ]; then
  echo "Usage: $0 <profile>"
  echo "  profile: profile to build (default: lite)"
  echo "  options: lite, lareferencia, ibict, rcaap"

  exit 1
fi

if [ -z "$1" ]; then
   mvn clean package install -DskipTests -Dmaven.javadoc.skip=true
else
   mvn clean package install -DskipTests -Dmaven.javadoc.skip=true -P$1
fi

