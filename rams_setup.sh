#!/usr/bin/env bash
#
# rams_setup.sh <branch_name> [base_branch]
#
# Sets up a RAMS worktree for the given branch under ./<branch_name> in the
# current directory, then installs it. RAMS lives in a single monorepo
# (uni-rams-monorepo), so one worktree holds both apps:
#
#   <branch_name>/apps/backend
#   <branch_name>/apps/frontend
#
# After the worktree is created, the install phase runs (skip with
# RAMS_SKIP_INSTALL=1):
#
#   awsfix                                   (once, up front; aws sso + env)
#   apps/backend:   just install_packages && just copy-assets
#   apps/frontend:  bun run ar-login && bun install
#
# awsfix is a zsh shell function (not a binary), so the install phase runs in
# an interactive zsh; its exported env (DEVPI_URL, CODEARTIFACT token, ...) is
# what `just install_packages` needs.
#
# The branch name may contain slashes (e.g. a Linear branch name); they become
# nested directories. Branch handling is delegated to setup_worktree.sh
# (existing branch -> checked out, otherwise created off [base_branch], which
# defaults to the default branch — pass a parent branch to stack on it).

set -euo pipefail

RAMS_REPO="uni-rams-monorepo"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_worktree="$script_dir/setup_worktree.sh"
backend_env="$script_dir/env/rams.env"

usage() {
  echo "usage: rams_setup.sh <branch_name> [base_branch]" >&2
  exit 2
}

[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || usage

branch="$1"
base_branch="${2:-}"

base="$PWD/$branch"

# A script can't change its parent shell's cwd, so to actually leave the user
# *in* the new folder we cd there and hand off to a fresh interactive shell.
enter_target() {
  echo "==> entering $base"
  cd "$base"
  exec "${SHELL:-/bin/zsh}"
}

# --- create the worktree ------------------------------------------------------
echo "==> $RAMS_REPO -> $base"
if [ -n "$base_branch" ]; then
  WORKTREE_PATH="$base" "$setup_worktree" "$RAMS_REPO" "$branch" "$base_branch"
else
  WORKTREE_PATH="$base" "$setup_worktree" "$RAMS_REPO" "$branch"
fi

# --- backend env --------------------------------------------------------------
# Drop the checked-in backend env into the new worktree (it's git-ignored, so a
# fresh worktree won't have it).
if [ -f "$backend_env" ]; then
  echo "==> env $backend_env -> $base/apps/backend/.env-local"
  cp "$backend_env" "$base/apps/backend/.env-local"
else
  echo "warning: no backend env at '$backend_env'; skipping .env-local" >&2
fi

# --- vscode multi-root workspace ----------------------------------------------
# Drop the checked-in multi-root .code-workspace into the worktree root so both
# apps open together. Each folder keeps its own .vscode/launch.json;
# ${workspaceFolder} resolves per-folder.
workspace_template="$script_dir/rams.code-workspace"
if [ -f "$workspace_template" ]; then
  echo "==> workspace $workspace_template -> $base/rams.code-workspace"
  cp "$workspace_template" "$base/rams.code-workspace"

  common_dir="$(git -C "$base" rev-parse --path-format=absolute --git-common-dir)"
  exclude_file="$common_dir/info/exclude"
  mkdir -p "$(dirname "$exclude_file")"
  if ! grep -qxF '/rams.code-workspace' "$exclude_file" 2>/dev/null; then
    echo '/rams.code-workspace' >>"$exclude_file"
  fi
else
  echo "warning: no workspace template at '$workspace_template'; skipping" >&2
fi

# --- install phase ------------------------------------------------------------
if [ "${RAMS_SKIP_INSTALL:-}" = "1" ]; then
  echo "RAMS_SKIP_INSTALL=1 set -> skipping install phase"
  echo "done: $base"
  enter_target
fi

# Build a single zsh program so awsfix runs once and its env is inherited by
# every install command. Quote paths portably for the embedded shell.
#
# awsfix runs several commands internally and tolerates non-fatal errors (e.g.
# a "not implemented" credential-store warning), returning 0 on its own. Run it
# BEFORE enabling `set -e` — otherwise one of those internal non-zero commands
# trips `set -e` and aborts the whole install before any package is installed.
printf -v base_q '%q' "$base"
post=$'awsfix\nset -e\n'
post+="printf '\\n==> installing backend\\n'"$'\n'
post+="cd $base_q/apps/backend && just install_packages && just copy-assets"$'\n'
post+="printf '\\n==> installing frontend\\n'"$'\n'
post+="cd $base_q/apps/frontend && bun run ar-login && bun install"$'\n'

# awsfix is defined in the user's interactive zsh config, so use `zsh -i`.
if zsh -ic 'typeset -f awsfix >/dev/null 2>&1'; then
  zsh -ic "$post"
else
  echo "warning: 'awsfix' not found in interactive zsh; skipping install phase." >&2
  echo "         run it yourself in $base" >&2
  exit 1
fi

echo "done: $base"
enter_target
