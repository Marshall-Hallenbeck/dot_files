#!/bin/bash
# PreToolUse hook (Write|Edit|MultiEdit): if the content being written contains
# fallback / graceful-degradation / silent-default patterns, inject a reminder
# to the agent (additionalContext) instead of prompting the user. The edit
# proceeds; the agent must confirm the fallback is required by the user's ask,
# not added by instinct. See rules/error-handling.md.

command -v jq >/dev/null 2>&1 || { echo "guard-fallback-patterns: jq unavailable, guard disabled" >&2; exit 0; }

input=$(cat)

# Documentation and prose legitimately use the word "fallback"; the
# error-handling rule governs code behavior, so skip non-code files.
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
case "$file_path" in
  *.md|*.markdown|*.txt|*.rst|*.adoc) exit 0 ;;
esac

# Cover Write (.content), Edit (.new_string), and MultiEdit (.edits[].new_string).
content=$(echo "$input" | jq -r '[.tool_input.new_string, .tool_input.content, (.tool_input.edits[]?.new_string)] | map(select(. != null)) | join("\n")')
[ -z "$content" ] && exit 0

if echo "$content" | grep -Eiq '\bfallback\b|graceful[[:space:]]+degrad|degraded[[:space:]]+path|retryWithoutAuth|defaulting[[:space:]]+to|\?\?[[:space:]]*\[\]|\|\|[[:space:]]*\[\]|\?\?[[:space:]]*\{\}|\|\|[[:space:]]*\{\}'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "FALLBACK GUARD: this edit contains a fallback / graceful-degradation / silent-default pattern (fallback, defaulting to, `?? []`, `|| {}`, retry-without-auth, etc). Per rules/error-handling.md such code is allowed only when the user explicitly asked for it or the requirements make it necessary. Before continuing, re-check the user'"'"'s request: if the fallback is required, keep it and state in one clause why it is required. If you added it by instinct, remove it now and let the error propagate."
    }
  }'
fi
exit 0
