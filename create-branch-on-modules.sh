
# obtain branch name from command line
if [ $# -gt 0 ]; then
  branch="$1"
else
  branch="main"
fi

# push all modules
git submodule foreach --recursive "git checkout -b $branch || true"

# switch to branch
git checkout -b $branch



