#!/bin/bash
set -eou pipefail

# push this repository
git push

# push all modules
git submodule foreach --recursive "git push"

