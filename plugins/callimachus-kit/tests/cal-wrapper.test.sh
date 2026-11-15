#!/usr/bin/env bash
# Tests for scripts/cal.sh, using fake cal programs in a throwaway HOME.
# Run: bash plugins/callimachus-kit/tests/cal-wrapper.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
wrapper="$here/../scripts/cal.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() { # name, expected substring, actual output
  if [[ "$3" == *"$2"* ]]; then echo "ok   $1"; else
    echo "FAIL $1"; echo "  wanted: $2"; echo "  got:    $3"; fails=$((fails + 1))
  fi
}

# A fake Callimachus cal: answers `version`, echoes its arguments, fails on `boom`.
mkdir -p "$tmp/home/.local/bin" "$tmp/bin" "$tmp/repos/MyApp"
cat >"$tmp/home/.local/bin/cal" <<'EOF'
#!/usr/bin/env bash
[ "$1" = version ] && { echo "callimachus 0.12.3"; exit 0; }
[ "$1" = boom ] && { echo "error: no index" >&2; exit 1; }
printf 'args:'; printf ' [%s]' "$@"; echo
EOF
# The system calendar, which must never be used.
cat >"$tmp/bin/cal" <<'EOF'
#!/usr/bin/env bash
echo "     November 2026"
EOF
chmod +x "$tmp/home/.local/bin/cal" "$tmp/bin/cal"
git -C "$tmp/repos/MyApp" init -q

run() { (cd "$tmp/repos/MyApp" && HOME="$tmp/home" PATH="$tmp/bin:$PATH" CALLIMACHUS_CAL= bash "$wrapper" "$@"); }

check "passes arguments through" "args: [search] [two words] [-n] [3]" "$(run search 'two words' -n 3)"
check "expands @repo" "args: [recent] [-p] [MyApp]" "$(run recent -p @repo)"
check "prints the repo name" "MyApp" "$(run repo)"

out=$(run boom); code=$?
check "reports a failed run" "\`cal boom\` exited with code 1" "$out"
check "keeps cal's error text" "error: no index" "$out"
check "exits 0 after a failure" "0" "$code"

# A linked worktree is named after its main checkout.
git -C "$tmp/repos/MyApp" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$tmp/repos/MyApp" worktree add -q "$tmp/wt-feature" 2>/dev/null
check "names a worktree after its main repo" "MyApp" "$(cd "$tmp/wt-feature" && bash "$wrapper" repo)"

# With only the system calendar around, it says how to install cal.
rm "$tmp/home/.local/bin/cal"
out=$(run search x); code=$?
check "ignores the system calendar" "callimachus-kit: the Callimachus cal CLI was not found" "$out"
check "exits 0 when cal is missing" "0" "$code"

# $CALLIMACHUS_CAL points at a cal elsewhere.
cat >"$tmp/mycal" <<'EOF'
#!/usr/bin/env bash
[ "$1" = version ] && { echo "callimachus 0.12.3"; exit 0; }
echo "from override"
EOF
chmod +x "$tmp/mycal"
check "uses \$CALLIMACHUS_CAL" "from override" "$(cd "$tmp/repos/MyApp" && HOME="$tmp/home" PATH="$tmp/bin:$PATH" CALLIMACHUS_CAL="$tmp/mycal" bash "$wrapper" stats)"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
