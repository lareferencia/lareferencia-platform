#!/bin/bash

set -eou pipefail

# recursively remove target directories
# avoid errors if target directories do not exist
git submodule foreach --recursive "rm -r target/* || true "



