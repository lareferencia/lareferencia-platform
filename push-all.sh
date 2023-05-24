#!/bin/bash
set -eou pipefail

# get current branch
branch=$(git rev-parse --abbrev-ref HEAD)

# if branch is not main, ask for confirmation
if [ "$branch" != "main" ]; then
  read -p "You are about to push changes to branch $branch on all modules. Upstream will be set up in all submodules to the branch name of the parent proyect. Are you sure you want to continue? (y/n) " confirm
  if [ "$confirm" != "y" ]; then
    echo "Aborting push."
    exit 1
  fi
fi

#set upstream to all submodules
git submodule foreach --recursive "git push --set-upstream origin $branch"

# push the parent project
git push --set-upstream origin $branch

