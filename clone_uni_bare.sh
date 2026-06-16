#!/usr/bin/env bash
#
# Clone each repo listed in the repos_to_clone file next to this script
# (one URL per line) as a bare repo,
# so you can make worktrees off them elsewhere:
#
#   git -C uni-foo.git worktree add ~/work/foo main
#
# Re-run any time to update: it clones what's missing and fetches the current
# branch for what already exists.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEST="$HOME/dev/repos"
REPO_LIST="${REPO_LIST:-$SCRIPT_DIR/repos_to_clone}"

if [[ ! -f "$REPO_LIST" ]]; then
  echo "No repo list found at '$REPO_LIST'. Create one with a repo URL per line." >&2
  exit 1
fi

mkdir -p "$DEST"
cd "$DEST"

while IFS= read -r url || [[ -n "$url" ]]; do
  # Skip blank lines and comments.
  url="${url%%#*}"
  url="${url//[[:space:]]/}"
  [[ -z "$url" ]] && continue

  name="$(basename "$url" .git)"
  dir="$name.git"

  if [[ -d "$dir" ]]; then
    # Re-fetch the branch the bare repo's HEAD points at.
    branch="$(git --git-dir="$dir" symbolic-ref --short HEAD)"
    echo "fetch  $name ($branch)"
    git --git-dir="$dir" fetch --quiet origin "+refs/heads/$branch:refs/heads/$branch"
  else
    echo "clone  $name"
    git clone --bare --single-branch "$url" "$dir"
  fi
done < "$REPO_LIST"

echo "Done."
