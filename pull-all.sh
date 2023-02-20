#!/bin/bash

set -eou pipefail

# pull from the remote
git pull

# push all modules
git submodule foreach --recursive "git pull"


