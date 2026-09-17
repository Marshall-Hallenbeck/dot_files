#!/bin/bash
# PostToolUse hook (Edit|Write|MultiEdit): run the right linter for the edited
# file, dispatching by extension. Non-blocking — linter output is returned to
# the agent as additionalContext so it can act on it. Plain stdout from a
# PostToolUse hook is only shown in the transcript view, never to the agent.
#
# Hook input arrives on STDIN as JSON. The file path is at .tool_input.file_path
# (NOT top-level .file_path, and NOT a CLAUDE_TOOL_INPUT env var).

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0
[ -f "$file_path" ] || exit 0

output=""
case "$file_path" in
  *.ts|*.tsx)
    # A TypeScript check is a whole-program operation. Running it after every
    # edit multiplied CPU use and left orphan workers when a hook was stopped.
    # Projects must batch type checks at a turn or delivery boundary instead.
    exit 0
    ;;
  *.py)
    command -v ruff >/dev/null 2>&1 || exit 0
    output=$( { ruff check --fix -- "$file_path" 2>&1 | head -20; ruff format --check -- "$file_path" 2>&1 | head -5; } | grep -vE '^(All checks passed!|1 file already formatted)$' )
    ;;
  *.sh|*.bash)
    command -v shellcheck >/dev/null 2>&1 || exit 0
    output=$(shellcheck -S style -- "$file_path" 2>&1 | head -20)
    ;;
esac

[ -z "$output" ] && exit 0
jq -n --arg file "$file_path" --arg out "$output" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("LINT (" + $file + "):\n" + $out + "\nFix every reported issue before finishing.")
  }
}'
exit 0
