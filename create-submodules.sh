#!/bin/bash

# load configuration from enviroment.sh
source enviroment.sh

# print configuration
echo "LAREFERENCIA_PLATFORM_PATH: $LAREFERENCIA_PLATFORM_PATH"
echo "LAREFERENCIA_HOME: $LAREFERENCIA_HOME"
echo "LAREFERENCIA_GITHUB_REPO: $LAREFERENCIA_GITHUB_REPO"

# load read_modules function
source read_modules.sh

# read modules from modules.txt
modules=($(read_modules))

# print modules
echo "Modules: ${modules[@]}"

LAREFERENCIA_PROJECTS=("${modules[@]}")

# iterate over modules and create submodules
for module in "${modules[@]}"; do
    echo "Creating submodule $module"

    module_repo=$(echo $LAREFERENCIA_GITHUB_REPO | sed -e 's/{PROJECT}/'$module'/g')
    module_path=$LAREFERENCIA_HOME/$module

    # create submodule
    git submodule add $module_repo
done
