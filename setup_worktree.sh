#!/usr/bin/env bash
#
# setup_worktree.sh [-d <folder>] <repo> <branch_name> [base_branch]
#
# Creates a git worktree for <repo> at ./<branch_name> in the current
# directory, or at ./<folder> when -d/--dir is given. <repo> may be an absolute
# path or a name/path under ~/dev/repos, with or without a trailing ".git" —
# bare clones (e.g. "uni-foo.git", as produced by clone_uni_bare.sh) and
# regular working clones both work. The branch name may contain slashes (e.g. a
# Linear branch name like "iain/asi-123-add-evaluator"), which become nested
# directories.
#
# Branch handling: if the branch already exists (local or remote) it is
# checked out in the new worktree; otherwise a new branch is created off
# [base_branch], defaulting to the repo's default branch. The base may itself
# be checked out in another worktree (stacked branches) — git only forbids
# checking out the *same* branch twice, not branching off it.

set -euo pipefail

REPOS_ROOT="${REPOS_ROOT:-$HOME/dev/repos}"

usage() {
  echo "usage: setup_worktree.sh [-d|--dir <folder>] <repo> <branch_name> [base_branch]" >&2
  exit 2
}

folder=""
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--dir)
      [ "$#" -ge 2 ] || usage
      folder="$2"
      shift 2
      ;;
    --dir=*)
      folder="${1#--dir=}"
      shift
      ;;
    -h|--help) usage ;;
    --)
      shift
      args+=("$@")
      break
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      usage
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
set -- ${args[@]+"${args[@]}"}

[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || usage

repo_arg="$1"
branch="$2"
base_branch="${3:-}"
folder="${folder:-$branch}"

is_git_repo() {
  # True for a working clone or a bare repo.
  [ -d "$1" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# A `--bare --single-branch` clone has no `+refs/heads/*:refs/remotes/origin/*`
# fetch refspec, so git doesn't treat anything under refs/remotes/origin/ as a
# remote-tracking branch and `worktree add --track` fails with "not a branch".
fetch_remote_branch() {
  local ref="$1"
  if ! git -C "$repo_dir" config --get-all remote.origin.fetch | grep -q 'refs/remotes/origin/\*'; then
    git -C "$repo_dir" config --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  fi
  git -C "$repo_dir" fetch --quiet origin "+refs/heads/$ref:refs/remotes/origin/$ref"
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

# Worktree path: <folder> (defaulting to <branch_name>, slashes included) under
# the current directory. Callers (e.g. rams_setup.sh) may override the
# destination via $WORKTREE_PATH.
worktree_path="${WORKTREE_PATH:-$PWD/$folder}"
if [ -e "$worktree_path" ]; then
  echo "error: '$worktree_path' already exists" >&2
  exit 1
fi
mkdir -p "$(dirname "$worktree_path")"

# Refresh whatever the remote refspec covers (for a single-branch bare clone
# that's just the default branch); ignore failures (offline, etc.).
git -C "$repo_dir" fetch --quiet --prune origin || true

# Default branch: in a bare clone HEAD points at it directly; fall back to the
# remote-tracking HEAD (working clones), then to "main".
default_branch="$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -n "$default_branch" ] || default_branch="$(git -C "$repo_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_branch#origin/}"
default_branch="${default_branch:-main}"

if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
  # Existing local branch.
  echo "checking out existing local branch '$branch'"
  git -C "$repo_dir" worktree add "$worktree_path" "$branch"
elif git -C "$repo_dir" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  # Branch exists on the remote but not locally.
  echo "checking out remote branch 'origin/$branch'"
  fetch_remote_branch "$branch"
  git -C "$repo_dir" worktree add --track -b "$branch" "$worktree_path" "origin/$branch"
else
  # New branch off [base_branch], defaulting to the repo's default branch.
  if [ -z "$base_branch" ]; then
    base_ref="$default_branch"
  elif git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$base_branch"; then
    base_ref="$base_branch"
  elif git -C "$repo_dir" ls-remote --exit-code --heads origin "$base_branch" >/dev/null 2>&1; then
    fetch_remote_branch "$base_branch"
    base_ref="origin/$base_branch"
  else
    echo "error: base branch '$base_branch' not found locally or on origin" >&2
    exit 1
  fi
  echo "creating new branch '$branch' off '$base_ref'"
  git -C "$repo_dir" worktree add -b "$branch" "$worktree_path" "$base_ref"
fi

echo "worktree ready: $worktree_path"
