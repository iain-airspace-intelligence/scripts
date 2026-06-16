#!/usr/bin/env bash
#
# install.sh
#
# Wires this scripts directory into your ~/.zshrc so that:
#
#   * the scripts here are on PATH (run them by name: rams_setup.sh, ...)
#   * their zsh completions (completions/*.zsh) are sourced in new shells
#
# Idempotent: the lines live in a marked block, so re-running refreshes that
# block in place instead of appending duplicates. Override the target file
# with ZSHRC=... (handy for testing).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="${ZSHRC:-$HOME/.zshrc}"

BEGIN="# >>> scripts (managed by install.sh) >>>"
END="# <<< scripts (managed by install.sh) <<<"

# Build the managed block: the home line (PATH) plus one source line per
# completion file that actually exists.
block="$BEGIN"
block+=$'\n'"export PATH=\"$SCRIPT_DIR:\$PATH\""
if [[ -e "$SCRIPT_DIR/iain.sh" ]]; then
  block+=$'\n'"source \"$SCRIPT_DIR/iain.sh\""
fi
for f in "$SCRIPT_DIR"/completions/*.zsh; do
  [[ -e "$f" ]] || continue
  block+=$'\n'"source \"$f\""
done
block+=$'\n'"$END"

touch "$ZSHRC"

if grep -qF "$BEGIN" "$ZSHRC"; then
  # Drop the existing managed block so we can re-append a fresh one, keeping
  # the surrounding lines untouched.
  tmp="$(mktemp)"
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$ZSHRC" >"$tmp"
  # Drop trailing blank lines so refreshes don't accumulate whitespace.
  awk 'NF{last=NR} {line[NR]=$0} END{for(i=1;i<=last;i++) print line[i]}' \
    "$tmp" >"$ZSHRC"
  rm -f "$tmp"
  action="refreshed"
else
  action="added"
fi

printf '\n%s\n' "$block" >>"$ZSHRC"
echo "$action scripts block in $ZSHRC"
echo "open a new shell or run: source \"$ZSHRC\""
