#!/bin/bash
# PostToolUse hook (Edit|Write|MultiEdit): run the right linter for the edited
# file, dispatching by extension. Non-blocking — surfaces linter output to the
# transcript without failing the tool.
#
# Hook input arrives on STDIN as JSON. The file path is at .tool_input.file_path
# (NOT top-level .file_path, and NOT a CLAUDE_TOOL_INPUT env var).

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0
[ -f "$file_path" ] || exit 0

case "$file_path" in
  *.ts|*.tsx)
    command -v npx >/dev/null 2>&1 || exit 0
    # Walk up from the file to the nearest tsconfig.json (handles monorepos).
    d=$(cd "$(dirname "$file_path")" 2>/dev/null && pwd) || exit 0
    tsconfig=""
    while [ -n "$d" ] && [ "$d" != "/" ]; do
      if [ -f "$d/tsconfig.json" ]; then tsconfig="$d/tsconfig.json"; break; fi
      d=$(dirname "$d")
    done
    [ -n "$tsconfig" ] || exit 0
    ( cd "$(dirname "$tsconfig")" && npx --no-install tsc --noEmit --pretty 2>&1 | head -20 )
    ;;
  *.py)
    command -v ruff >/dev/null 2>&1 || exit 0
    ruff check --fix -- "$file_path" 2>&1 | head -20
    ruff format --check -- "$file_path" 2>&1 | head -5
    ;;
  *.sh|*.bash)
    command -v shellcheck >/dev/null 2>&1 || exit 0
    shellcheck -S style -- "$file_path" 2>&1 | head -20
    ;;
esac
exit 0
