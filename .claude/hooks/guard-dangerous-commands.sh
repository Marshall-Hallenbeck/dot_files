#!/bin/bash
set -euo pipefail

# PreToolUse hook for Bash: force user approval on dangerous commands.
# Outputs permissionDecision "ask" to show the permission prompt UI.

COMMAND=$(jq -r '.tool_input.command // empty')

# git add, commit, push, checkout, rm
if echo "$COMMAND" | grep -qE '(^|[[:space:]]|;|&&|\|\|)git[[:space:]]+(add|commit|push|checkout|rm)\b'; then
  cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git add/commit/push/checkout/rm requires explicit user approval."}}
HOOK
  exit 0
fi

# rm commands
if echo "$COMMAND" | grep -qE '(^|[[:space:]]|;|&&|\|\|)rm[[:space:]]'; then
  cat <<'HOOK'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"rm command requires explicit user approval."}}
HOOK
  exit 0
fi

exit 0
