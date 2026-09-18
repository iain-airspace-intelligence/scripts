#!/usr/bin/env bash
#
# rams_remove_worktree.sh <branch_name>
#
# Removes the RAMS worktree created by rams_setup.sh for the given branch at
# ./<branch_name> in the current directory. RAMS lives in a single monorepo
# (uni-rams-monorepo), so that one worktree holds both apps.
#
# Removal is delegated to remove_worktree.sh.
#
# Env (passed through to remove_worktree.sh):
#   FORCE=1          remove even with uncommitted/untracked changes
#   DELETE_BRANCH=1  also delete the worktree's LOCAL branch afterwards
#                    (never touches the remote branch)

set -euo pipefail

RAMS_REPO="uni-rams-monorepo"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
remove_worktree="$script_dir/remove_worktree.sh"

usage() {
  echo "usage: rams_remove_worktree.sh <branch_name>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

branch="$1"
base="$PWD/$branch"

rm -f "$base/rams.code-workspace"

echo "==> $RAMS_REPO <- $base"
WORKTREE_PATH="$base" "$remove_worktree" "$RAMS_REPO" "$branch"

echo "done: $base"
