#!/usr/bin/env bash
#
# remove_worktree.sh <repo> <branch_name>
#
# Removes the git worktree created by setup_worktree.sh for <repo> at
# ./<branch_name> in the current directory (callers may override the path via
# $WORKTREE_PATH, mirroring setup_worktree.sh). <repo> is resolved the same way
# as setup_worktree.sh: an absolute/relative path or a bare name, with or
# without a ".git" suffix, located directly or under ~/dev/repos.
#
# Env:
#   FORCE=1          remove even with uncommitted/untracked changes
#   DELETE_BRANCH=1  also delete the worktree's LOCAL branch afterwards
#                    (git branch -D; never touches the remote branch)

set -euo pipefail

REPOS_ROOT="${REPOS_ROOT:-$HOME/dev/repos}"

usage() {
  echo "usage: remove_worktree.sh <repo> <branch_name>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

repo_arg="$1"
branch="$2"

is_git_repo() {
  # True for a working clone or a bare repo.
  [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# Resolve the repo directory: accept an absolute/relative path or a bare name,
# with or without a ".git" suffix, located either directly or under
# $REPOS_ROOT. Bare clones are named "<name>.git".
repo_dir=""
for cand in \
  "$repo_arg" \
  "$repo_arg.git" \
  "$REPOS_ROOT/$repo_arg" \
  "$REPOS_ROOT/$repo_arg.git"; do
  if is_git_repo "$cand"; then
    repo_dir="$cand"
    break
  fi
done

if [ -z "$repo_dir" ]; then
  echo "error: could not find a git repo for '$repo_arg' (tried '$repo_arg', '$repo_arg.git', and the same under '$REPOS_ROOT')" >&2
  exit 1
fi
repo_dir="$(cd "$repo_dir" && pwd)"

# Worktree path: <branch_name> (with slashes) under the current directory,
# unless overridden (e.g. by rams_remove_worktree.sh).
worktree_path="${WORKTREE_PATH:-$PWD/$branch}"

remove_args=()
[ "${FORCE:-}" = "1" ] && remove_args+=(--force)

if [ -e "$worktree_path" ]; then
  echo "removing worktree '$worktree_path'"
  git -C "$repo_dir" worktree remove "${remove_args[@]}" "$worktree_path"
else
  echo "worktree path '$worktree_path' is gone; pruning stale admin entry"
fi

# Clean up any stale worktree bookkeeping (e.g. if the dir was deleted by hand).
git -C "$repo_dir" worktree prune

if [ "${DELETE_BRANCH:-}" = "1" ]; then
  # Local branch only — the remote branch is intentionally left untouched.
  if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "deleting local branch '$branch'"
    git -C "$repo_dir" branch -D "$branch"
  else
    echo "no local branch '$branch' to delete"
  fi
fi

echo "removed: $worktree_path"
