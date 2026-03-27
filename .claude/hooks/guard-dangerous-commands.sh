#!/bin/bash
set -euo pipefail

# PreToolUse hook for Bash: force user approval on dangerous commands.
# Outputs permissionDecision "ask" to show the permission prompt UI.

COMMAND=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.command // empty')

# git add, commit, push, checkout, rm
if echo "$COMMAND" | grep -qP '(^|\s|;|&&|\|\|)git\s+(add|commit|push|checkout|rm)\b'; then
  cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git add/commit/push/checkout/rm requires explicit user approval."}}
HOOK
  exit 0
fi

# rm commands
if echo "$COMMAND" | grep -qP '(^|\s|;|&&|\|\|)rm\s'; then
  cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"rm command requires explicit user approval."}}
HOOK
  exit 0
fi

exit 0
