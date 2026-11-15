#!/usr/bin/env bash
# callimachus-kit: run the Callimachus `cal` CLI for the plugin's skills.
#
#   cal.sh <cal args…>   run cal; an argument that is exactly "@repo" becomes this repo's name
#                        (for cal's -p/--project filter, which substring-matches project paths)
#   cal.sh repo          print this repo's name
#
# It finds cal at $CALLIMACHUS_CAL, ~/.local/bin/cal (where the Callimachus app and
# `npx callimachus-mcp --install-cal` link it) or on PATH, and only uses one that answers
# `cal version` with "callimachus": the system calendar is also called cal.
#
# It always exits 0, so the skill reading its output gets the explanation rather than a bare
# failure: a missing cal or a failed run prints a line starting with "callimachus-kit:".
set -u

repo_name() {
  local top common
  top=$(git rev-parse --show-toplevel 2>/dev/null) || top=$PWD
  # In a linked worktree, name the main checkout, which is what the index groups sessions under.
  if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
    [ "$(basename "$common")" = .git ]; then
    top=$(dirname "$common")
  fi
  basename "$top"
}

find_cal() {
  local c
  for c in "${CALLIMACHUS_CAL:-}" "$HOME/.local/bin/cal" "$(command -v cal 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    case "$("$c" version 2>/dev/null)" in
    callimachus*)
      printf '%s\n' "$c"
      return 0
      ;;
    esac
  done
  return 1
}

if [ "${1:-}" = repo ]; then
  repo_name
  exit 0
fi

if ! cal=$(find_cal); then
  cat <<'EOF'
callimachus-kit: the Callimachus cal CLI was not found (looked at $CALLIMACHUS_CAL, ~/.local/bin/cal and PATH).
Install it one of two ways, then try again:
  - Open the Callimachus app > Settings > Agents > "Install the cal CLI"
  - Or run: npx callimachus-mcp --install-cal   (then `cal index` once to build the index)
EOF
  exit 0
fi

args=()
for a in "$@"; do
  if [ "$a" = "@repo" ]; then args+=("$(repo_name)"); else args+=("$a"); fi
done

"$cal" "${args[@]}" 2>&1
code=$?
if [ "$code" -ne 0 ]; then
  echo "callimachus-kit: \`cal ${args[0]:-}\` exited with code $code."
fi
exit 0
