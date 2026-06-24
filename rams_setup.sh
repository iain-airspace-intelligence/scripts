#!/usr/bin/env bash
#
# rams_setup.sh <b|f|bf> <branch_name>
#
# Sets up RAMS worktrees for the given branch under ./<branch_name> in the
# current directory, then installs each one:
#
#   b   backend only   -> <branch_name>/backend   (uni-reach-backend-rams)
#   f   frontend only  -> <branch_name>/frontend  (uni-flyways-reach-rams)
#   bf  both           -> both of the above
#
# After the worktrees are created, the install phase runs (skip with
# RAMS_SKIP_INSTALL=1):
#
#   awsfix                                  (once, up front; aws sso + env)
#   backend:  just install_packages && just copy-assets
#   frontend: bun run ar-login && bun install
#
# awsfix is a zsh shell function (not a binary), so the install phase runs in
# an interactive zsh; its exported env (DEVPI_URL, CODEARTIFACT token, ...) is
# what `just install_packages` needs.
#
# The branch name may contain slashes (e.g. a Linear branch name); they become
# nested directories. Branch handling is delegated to setup_worktree.sh
# (existing branch -> checked out, otherwise created off the default branch).

set -euo pipefail

BACKEND_REPO="uni-reach-backend-rams"
FRONTEND_REPO="uni-flyways-reach-rams"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_worktree="$script_dir/setup_worktree.sh"
backend_env="$script_dir/env/rams.env"

usage() {
  echo "usage: rams_setup.sh <b|f|bf> <branch_name>" >&2
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

setup_one() {
  local repo="$1" subdir="$2"
  echo "==> $repo -> $base/$subdir"
  WORKTREE_PATH="$base/$subdir" "$setup_worktree" "$repo" "$branch"
}

# --- create worktrees ---------------------------------------------------------
$do_backend  && setup_one "$BACKEND_REPO" backend
$do_frontend && setup_one "$FRONTEND_REPO" frontend

# --- backend env --------------------------------------------------------------
# Drop the checked-in backend env into the new worktree (it's git-ignored, so a
# fresh worktree won't have it).
if $do_backend; then
  if [ -f "$backend_env" ]; then
    echo "==> env $backend_env -> $base/backend/.env-local"
    cp "$backend_env" "$base/backend/.env-local"
  else
    echo "warning: no backend env at '$backend_env'; skipping .env-local" >&2
  fi
fi

# --- vscode multi-root workspace ----------------------------------------------
# Drop the checked-in multi-root .code-workspace into the branch dir so backend +
# frontend open together. Each folder keeps its own .vscode/launch.json;
# ${workspaceFolder} resolves per-folder.
workspace_template="$script_dir/rams.code-workspace"
if [ -f "$workspace_template" ]; then
  echo "==> workspace $workspace_template -> $base/rams.code-workspace"
  cp "$workspace_template" "$base/rams.code-workspace"
else
  echo "warning: no workspace template at '$workspace_template'; skipping" >&2
fi

# --- install phase ------------------------------------------------------------
if [ "${RAMS_SKIP_INSTALL:-}" = "1" ]; then
  echo "RAMS_SKIP_INSTALL=1 set -> skipping install phase"
  echo "done: $base"
  exit 0
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
if $do_backend; then
  post+="printf '\\n==> installing backend\\n'"$'\n'
  post+="cd $base_q/backend && just install_packages && just copy-assets"$'\n'
fi
if $do_frontend; then
  post+="printf '\\n==> installing frontend\\n'"$'\n'
  post+="cd $base_q/frontend && bun run ar-login && bun install"$'\n'
fi

# awsfix is defined in the user's interactive zsh config, so use `zsh -i`.
if zsh -ic 'typeset -f awsfix >/dev/null 2>&1'; then
  zsh -ic "$post"
else
  echo "warning: 'awsfix' not found in interactive zsh; skipping install phase." >&2
  echo "         run it yourself in each worktree under $base" >&2
  exit 1
fi

echo "done: $base"
