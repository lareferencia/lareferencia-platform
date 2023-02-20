#!/bin/bash

# load configuration from enviroment.sh
source enviroment.sh

# print configuration
echo "LAREFERENCIA_PLATFORM_PATH: $LAREFERENCIA_PLATFORM_PATH"
echo "LAREFERENCIA_HOME: $LAREFERENCIA_HOME"
echo "LAREFERENCIA_GITHUB_REPO: $LAREFERENCIA_GITHUB_REPO"

# check parameters passed to script and print usage
if [ $# -lt 1 ]; then
  echo "Usage: $0 <branch> [publish]"
  echo "  branch: branch to merge to main"
  exit 1
fi

# obtain branch name from command line
if [ $# -gt 0 ]; then
  branch="$1"
fi

# ask user if is sure to merge main into branch and store answer in variable REPLY
read -p "Are you sure you want to merge $branch into main? (yes/no) " yn

case $yn in 
	yes ) echo ok, we will proceed;;
	no ) echo exiting...;
		exit;;
	* ) echo invalid response;
		exit 1;;
esac


# load modules from modules.txt
read -r -a modules <<< $(cat modules.txt)

# merge branch into main
git checkout main
git pull
git merge $branch

# print modules
echo "Modules: ${modules[@]}"

# iterate over modules and switch to /create  branch
for module in "${modules[@]}"; do

    echo "Module: $module"
    cd $LAREFERENCIA_HOME/$module

    # check if branch exists in local
    if [[ `git branch | egrep "^\*?[[:space:]]+${branch}$"` ]]; then
      echo "Module: $module branch $branch exists in local"
      echo "Will merge $branch into main"
      
      git checkout main
      git pull
      git merge $branch

    fi

done
