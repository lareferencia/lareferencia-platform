#!/bin/bash

# load configuration from enviroment.sh
source enviroment.sh

# print configuration
echo "LAREFERENCIA_PLATFORM_PATH: $LAREFERENCIA_PLATFORM_PATH"
echo "LAREFERENCIA_HOME: $LAREFERENCIA_HOME"
echo "LAREFERENCIA_GITHUB_REPO: $LAREFERENCIA_GITHUB_REPO"

# load modules from modules.txt
read -r -a modules <<< $(cat modules.txt)

# print modules
echo "Modules: ${modules[@]}"

# iterate over modules and create submodules
for module in "${modules[@]}"; do
    echo "Creating submodule $module"

    module_repo=$(echo $LAREFERENCIA_GITHUB_REPO | sed -e 's/{PROJECT}/'$module'/g')
    module_path=$LAREFERENCIA_HOME/$module

    # create submodule
    git submodule add $module_repo
done
