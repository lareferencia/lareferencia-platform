#!/bin/bash

#set -eou pipefail

bash create-submodules.sh

# pull from the remote
git pull

# push all modules, not stop on error
git submodule foreach --recursive "git pull || true"


