#!/usr/bin/env bash
#
# rams_remove_worktree.sh <b|f|bf> <branch_name>
#
# Removes the RAMS worktrees created by rams_setup.sh for the given branch
# under ./<branch_name> in the current directory:
#
#   b   backend only   -> <branch_name>/backend   (uni-reach-backend-rams)
#   f   frontend only  -> <branch_name>/frontend  (uni-flyways-reach-rams)
#   bf  both           -> both of the above
#
# Removal is delegated to remove_worktree.sh. After both worktrees are gone the
# now-empty <branch_name> wrapper directory is removed too.
#
# Env (passed through to remove_worktree.sh):
#   FORCE=1          remove even with uncommitted/untracked changes
#   DELETE_BRANCH=1  also delete each worktree's LOCAL branch afterwards
#                    (never touches the remote branch)

set -euo pipefail

BACKEND_REPO="uni-reach-backend-rams"
FRONTEND_REPO="uni-flyways-reach-rams"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
remove_worktree="$script_dir/remove_worktree.sh"

usage() {
  echo "usage: rams_remove_worktree.sh <b|f|bf> <branch_name>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

mode="$1"
branch="$2"

case "$mode" in
  b|f|bf) ;;
  *) echo "error: mode must be one of: b, f, bf" >&2; usage ;;
esac

do_backend=false
do_frontend=false
case "$mode" in
  b)  do_backend=true ;;
  f)  do_frontend=true ;;
  bf) do_backend=true; do_frontend=true ;;
esac

base="$PWD/$branch"

remove_one() {
  local repo="$1" subdir="$2"
  echo "==> $repo <- $base/$subdir"
  WORKTREE_PATH="$base/$subdir" "$remove_worktree" "$repo" "$branch"
}

$do_backend  && remove_one "$BACKEND_REPO" backend
$do_frontend && remove_one "$FRONTEND_REPO" frontend

# Drop the wrapper directory if it's now empty.
if [ -d "$base" ] && [ -z "$(ls -A "$base")" ]; then
  rmdir "$base"
  echo "removed empty wrapper dir: $base"
fi

echo "done: $base"
