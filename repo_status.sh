#!/usr/bin/env bash

set -uo pipefail

MAX_DEPTH=3
CHANGED_ONLY=0
DO_FETCH=0
ROOT="."
SKIP_DIRS="node_modules|vendor|target|build|dist|.venv|venv|Library|Applications"

usage() {
  cat <<'EOT'
repo_status.sh [options] [dir]

Scan dir (default: current directory) for git repos and summarise each one:
its branch, whether it has working changes, and how far it is ahead/behind
its upstream.

Options:
  -c, --changed    only list repos with working changes or unpushed/unpulled commits
  -f, --fetch      fetch each repo first so ahead/behind reflects the remote
  -d, --depth N    how deep to search for repos (default 3)
  -h, --help       show this help
EOT
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c|--changed) CHANGED_ONLY=1; shift ;;
    -f|--fetch)   DO_FETCH=1; shift ;;
    -d|--depth)   MAX_DEPTH="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "error: unknown option '$1'" >&2; usage >&2; exit 1 ;;
    *)            ROOT="$1"; shift ;;
  esac
done

if [ ! -d "$ROOT" ]; then
  echo "error: '$ROOT' is not a directory" >&2
  exit 1
fi
ROOT="$(cd "$ROOT" && pwd)"

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
  GREEN=$'\033[32m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; YELLOW=""; GREEN=""; CYAN=""; RESET=""
fi

is_work_repo() { [ -e "$1/.git" ]; }
is_bare_repo() { [ -f "$1/HEAD" ] && [ -d "$1/objects" ] && [ -d "$1/refs" ]; }

REPOS=()

collect() {
  local dir="$1" depth="$2" entry
  if is_work_repo "$dir" || is_bare_repo "$dir"; then
    REPOS+=("$dir")
    [ "$dir" = "$ROOT" ] || return 0
  fi
  [ "$depth" -le 0 ] && return 0
  for entry in "$dir"/*/; do
    entry="${entry%/}"
    [ -d "$entry" ] || continue
    [ -L "$entry" ] && continue
    case "$(basename "$entry")" in
      .*) continue ;;
    esac
    if [[ "$(basename "$entry")" =~ ^($SKIP_DIRS)$ ]]; then continue; fi
    collect "$entry" $((depth - 1))
  done
}

collect "$ROOT" "$MAX_DEPTH"

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "no git repos found under $ROOT"
  exit 0
fi

if [ "$DO_FETCH" -eq 1 ]; then
  echo "${DIM}fetching ${#REPOS[@]} repos...${RESET}" >&2
  jobs=0
  for repo in "${REPOS[@]}"; do
    git -C "$repo" fetch --quiet --all --prune >/dev/null 2>&1 &
    jobs=$((jobs + 1))
    if [ "$jobs" -ge 8 ]; then wait; jobs=0; fi
  done
  wait
fi

read_status() {
  git -C "$1" status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null | awk '
    /^# branch\.head /     { head = $3 }
    /^# branch\.upstream / { up = $3 }
    /^# branch\.ab /       { ahead = substr($3, 2) + 0; behind = substr($4, 2) + 0 }
    /^[12] /               { if (substr($2,1,1) != ".") staged++; if (substr($2,2,1) != ".") unstaged++ }
    /^u /                  { conflicts++ }
    /^\? /                 { untracked++ }
    END {
      printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n",
        (head == "" ? "-" : head), (up == "" ? "-" : up),
        ahead, behind, staged, unstaged, untracked, conflicts
    }
  '
}

names=(); branches=(); syncs=(); changes=(); dirty_flags=()
width=4
dirty_count=0
total=0

for repo in "${REPOS[@]}"; do
  name="${repo#$ROOT/}"
  [ "$name" = "$repo" ] && name="$(basename "$repo")"

  if ! is_work_repo "$repo"; then
    branch="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo '?')"
    names+=("$name"); branches+=("$branch"); syncs+=("-")
    changes+=("${DIM}bare${RESET}"); dirty_flags+=(0)
    total=$((total + 1))
    [ "${#name}" -gt "$width" ] && width="${#name}"
    continue
  fi

  IFS=$'\t' read -r head up ahead behind staged unstaged untracked conflicts \
    < <(read_status "$repo")

  if [ "${head:-}" = "-" ]; then
    names+=("$name"); branches+=("?"); syncs+=("-")
    changes+=("${RED}unreadable${RESET}"); dirty_flags+=(0)
    total=$((total + 1))
    [ "${#name}" -gt "$width" ] && width="${#name}"
    continue
  fi

  if [ "$head" = "(detached)" ]; then
    branch="${YELLOW}detached${RESET}"
  else
    branch="$head"
  fi

  if [ "$up" = "-" ]; then
    sync="${DIM}no upstream${RESET}"
  elif [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
    sync="${GREEN}in sync${RESET}"
  else
    sync=""
    [ "$ahead" -gt 0 ] && sync="${YELLOW}ahead $ahead${RESET}"
    [ "$behind" -gt 0 ] && sync="${sync:+$sync }${CYAN}behind $behind${RESET}"
  fi

  parts=()
  [ "$staged" -gt 0 ] && parts+=("$staged staged")
  [ "$unstaged" -gt 0 ] && parts+=("$unstaged modified")
  [ "$untracked" -gt 0 ] && parts+=("$untracked untracked")
  [ "$conflicts" -gt 0 ] && parts+=("${RED}$conflicts conflicted${RESET}")

  if [ "${#parts[@]}" -eq 0 ]; then
    change="${DIM}clean${RESET}"
    dirty=0
  else
    joined="${parts[0]}"
    for part in "${parts[@]:1}"; do joined="$joined, $part"; done
    change="${RED}${joined}${RESET}"
    dirty=1
    dirty_count=$((dirty_count + 1))
  fi

  interesting=$dirty
  [ "$up" != "-" ] && { [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; } && interesting=1
  if [ "$CHANGED_ONLY" -eq 1 ] && [ "$interesting" -eq 0 ]; then
    total=$((total + 1))
    continue
  fi

  names+=("$name"); branches+=("$branch"); syncs+=("$sync")
  changes+=("$change"); dirty_flags+=("$dirty")
  total=$((total + 1))
  [ "${#name}" -gt "$width" ] && width="${#name}"
done

visible_len() {
  local plain; plain="$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')"
  printf '%s' "${#plain}"
}

bwidth=6
swidth=14
for b in "${branches[@]}"; do
  n="$(visible_len "$b")"
  [ "$n" -gt "$bwidth" ] && bwidth="$n"
done
for sy in "${syncs[@]}"; do
  n="$(visible_len "$sy")"
  [ "$n" -gt "$swidth" ] && swidth="$n"
done

pad() {
  local n; n="$(visible_len "$1")"
  printf '%s%*s' "$1" $(( $2 - n )) ""
}

if [ "${#names[@]}" -gt 0 ]; then
  printf '%s  %s  %s  %s  %s%s\n' "$BOLD" "$(pad REPO "$width")" \
    "$(pad BRANCH "$bwidth")" "$(pad SYNC "$swidth")" "CHANGES" "$RESET"
  for i in "${!names[@]}"; do
    if [ "${dirty_flags[$i]}" = "1" ]; then marker="${RED}*${RESET} "; else marker="  "; fi
    printf '%s%s  %s  %s  %s\n' \
      "$marker" \
      "$(pad "${names[$i]}" "$width")" \
      "$(pad "${branches[$i]}" "$bwidth")" \
      "$(pad "${syncs[$i]}" "$swidth")" "${changes[$i]}"
  done
  echo
fi

printf '%s%d repos, %d with working changes%s\n' "$BOLD" "$total" "$dirty_count" "$RESET"
