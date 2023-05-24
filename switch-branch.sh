#!/bin/bash

set -eou pipefail

# obtain branch name from command line
if [ $# -gt 0 ]; then
  branch="$1"
else
  branch="main"
fi

# fetch branches and checkout branch
git submodule foreach --recursive "git fetch origin"
git submodule foreach --recursive "git checkout $branch"

# switch to branch
git fetch origin
git checkout $branch

# sync modules
bash sync-modules.sh

