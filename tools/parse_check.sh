#!/usr/bin/env sh
# Dev helper (Git Bash): parse-check scripts like check.bat does, printing only real errors.
# Usage: tools/parse_check.sh [files...]   (default: every script)
cd "$(dirname "$0")/.." || exit 1
G=tools/godot/Godot_v4.7.2-stable_win64_console.exe
FILES="$*"
[ -z "$FILES" ] && FILES=$(find scripts tests -name "*.gd")
FAIL=0
for f in $FILES; do
  out=$($G --headless --path . --check-only --script "res://$f" 2>&1 | grep "SCRIPT ERROR" | grep -v "Identifier not found: \(SaveManager\|ChatLog\|AIClient\|GameState\)" | grep -v "Failed to compile depended scripts")
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; FAIL=1; fi
done
[ $FAIL -eq 0 ] && echo "parse check: ok"
exit $FAIL
