#compdef rams_setup.sh
#
# zsh completion for rams_setup.sh:
#
#   arg 1  branch  -> branch names known to the rams monorepo bare clone
#   arg 2  base    -> same, the branch to stack the new branch on (optional)
#
# Branch names are read from the local refs of the bare clone (refs/heads +
# refs/remotes/origin), exactly like `git checkout <TAB>` — instant, no network.
# Branches show up here once they've been fetched (which setup_worktree.sh does
# on demand, and `clone_uni_bare.sh` does for the default branch). Run
# `git -C ~/dev/repos/uni-rams-monorepo.git fetch origin` to pull in every
# remote branch at once.
#
# Source this file from ~/.zshrc; it initializes the completion system if the
# enclosing shell hasn't already.

if ! whence compdef >/dev/null 2>&1; then
  autoload -Uz compinit && compinit
fi

_rams_setup() {
  local -a branches
  local dir="$HOME/dev/repos/uni-rams-monorepo.git"
  case $CURRENT in
    2|3)
      [[ -d $dir ]] || return
      branches=( ${(f)"$(git -C $dir for-each-ref \
        --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null)"} )
      # Normalize remote-tracking names (origin/foo -> foo) and drop origin/HEAD,
      # then dedupe.
      branches=( ${branches#origin/} )
      branches=( ${branches:#HEAD} )
      branches=( ${(u)branches} )
      if (( CURRENT == 2 )); then
        _describe -t branches 'rams branch' branches
      else
        _describe -t branches 'base branch' branches
      fi
      ;;
  esac
}

compdef _rams_setup rams_setup.sh
