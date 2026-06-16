#!/usr/bin/env bash
#
# prune_worktrees.sh [repo]
#
# Prunes stale worktree admin entries — the bookkeeping git keeps for worktrees
# whose directories have been deleted by hand (`git worktree prune`). Without
# an argument it sweeps every repo under ~/dev/repos (bare clones and working
# clones alike). With a <repo> argument it prunes just that one, resolved the
# same way as setup_worktree.sh (path or bare name, with/without ".git").
#
# By default it prunes all stale entries regardless of age (--expire now);
# git's own `worktree prune` keeps a ~3-month grace period, which would leave
# recently-deleted worktrees holding their branch.
#
# Env:
#   DRY_RUN=1      show what would be pruned without removing anything
#   EXPIRE=<when>  grace period for pruning (default "now")

set -euo pipefail

REPOS_ROOT="${REPOS_ROOT:-$HOME/dev/repos}"
EXPIRE="${EXPIRE:-now}"

is_git_repo() {
  # True for a working clone or a bare repo.
  [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

prune_one() {
  local repo_dir="$1"
  local name; name="$(basename "$repo_dir")"

  # List what's stale first so we can report it. The verbose dry-run report is
  # written to stderr, so fold it into stdout for capture.
  local stale; stale="$(git -C "$repo_dir" worktree prune -v -n --expire "$EXPIRE" 2>&1 || true)"

  if [ -z "$stale" ]; then
    echo "ok    $name (nothing to prune)"
    return
  fi

  echo "prune $name"
  echo "$stale" | sed 's/^/        /'
  [ "${DRY_RUN:-}" = "1" ] || git -C "$repo_dir" worktree prune --expire "$EXPIRE"
}

# --- single repo --------------------------------------------------------------
if [ "$#" -ge 1 ]; then
  repo_arg="$1"
  repo_dir=""
  for cand in \
    "$repo_arg" \
    "$repo_arg.git" \
    "$REPOS_ROOT/$repo_arg" \
    "$REPOS_ROOT/$repo_arg.git"; do
    if is_git_repo "$cand"; then
      repo_dir="$(cd "$cand" && pwd)"
      break
    fi
  done
  if [ -z "$repo_dir" ]; then
    echo "error: could not find a git repo for '$repo_arg'" >&2
    exit 1
  fi
  prune_one "$repo_dir"
  exit 0
fi

# --- sweep every repo under $REPOS_ROOT --------------------------------------
if [ ! -d "$REPOS_ROOT" ]; then
  echo "error: REPOS_ROOT '$REPOS_ROOT' does not exist" >&2
  exit 1
fi

[ "${DRY_RUN:-}" = "1" ] && echo "(dry run — nothing will be removed)"

for entry in "$REPOS_ROOT"/*; do
  is_git_repo "$entry" || continue
  prune_one "$(cd "$entry" && pwd)"
done

echo "done."
