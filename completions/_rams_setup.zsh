#compdef rams_setup.sh
#
# zsh completion for rams_setup.sh:
#
#   arg 1  mode    -> b | f | bf
#   arg 2  branch  -> branch names known to the rams bare repos
#   arg 3  base    -> same, the branch to stack the new branch on (optional)
#
# Branch names are read from the local refs of the bare clones (refs/heads +
# refs/remotes/origin), exactly like `git checkout <TAB>` — instant, no network.
# Branches show up here once they've been fetched (which setup_worktree.sh does
# on demand, and `clone_uni_bare.sh` does for the default branch). Run
# `git -C ~/dev/repos/uni-reach-backend-rams.git fetch origin` to pull in every
# remote branch at once.
#
# Source this file from ~/.zshrc; it initializes the completion system if the
# enclosing shell hasn't already.

if ! whence compdef >/dev/null 2>&1; then
  autoload -Uz compinit && compinit
fi

_rams_setup() {
  local -a modes branches
  local repo dir
  case $CURRENT in
    2)
      modes=(
        'b:backend only'
        'f:frontend only'
        'bf:backend and frontend'
      )
      _describe -t modes 'mode' modes
      ;;
    3|4)
      branches=()
      for repo in uni-reach-backend-rams uni-flyways-reach-rams; do
        dir="$HOME/dev/repos/$repo.git"
        [[ -d $dir ]] || continue
        branches+=( ${(f)"$(git -C $dir for-each-ref \
          --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null)"} )
      done
      # Normalize remote-tracking names (origin/foo -> foo) and drop origin/HEAD,
      # then dedupe across the two repos.
      branches=( ${branches#origin/} )
      branches=( ${branches:#HEAD} )
      branches=( ${(u)branches} )
      if (( CURRENT == 3 )); then
        _describe -t branches 'rams branch' branches
      else
        _describe -t branches 'base branch' branches
      fi
      ;;
  esac
}

compdef _rams_setup rams_setup.sh
