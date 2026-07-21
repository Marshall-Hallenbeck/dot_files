#!/bin/bash
# PreToolUse hook (Write|Edit|MultiEdit): if the content being written contains
# fallback / graceful-degradation / silent-default patterns, ask the user to
# confirm — per rules/error-handling.md these require an explicit request.
#
# Hook input arrives on STDIN as JSON (there is no CLAUDE_TOOL_INPUT env var,
# and the user's prompt is NOT in the PreToolUse payload — so we cannot
# auto-allow "the user asked for it". We surface an ask decision instead of a
# hard block so a genuinely-requested fallback can be approved in place.

command -v jq >/dev/null 2>&1 || { echo "guard-fallback-patterns: jq unavailable, guard disabled" >&2; exit 0; }

input=$(cat)
# Cover Write (.content), Edit (.new_string), and MultiEdit (.edits[].new_string).
content=$(echo "$input" | jq -r '[.tool_input.new_string, .tool_input.content, (.tool_input.edits[]?.new_string)] | map(select(. != null)) | join("\n")')
[ -z "$content" ] && exit 0

if echo "$content" | grep -Eiq '\bfallback\b|graceful[[:space:]]+degrad|degraded[[:space:]]+path|retryWithoutAuth|defaulting[[:space:]]+to|\?\?[[:space:]]*\[\]|\|\|[[:space:]]*\[\]|\?\?[[:space:]]*\{\}|\|\|[[:space:]]*\{\}'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "Content contains a fallback / graceful-degradation / silent-default pattern. Per rules/error-handling.md these require an explicit request — confirm this is intended."
    }
  }'
fi
exit 0
