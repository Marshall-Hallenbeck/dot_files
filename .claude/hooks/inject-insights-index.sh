#!/bin/bash
set -euo pipefail

# Load the full insight file when it fits. Use its topic index when it is too large.

# Consume the SessionStart event JSON on stdin (not reading it can cause
# broken-pipe errors — see reinject-on-compact.sh).
cat >/dev/null

INSIGHTS="$HOME/.claude/global-learned-insights.md"
[ -r "$INSIGHTS" ] || exit 0

SIZE_LIMIT=${CLAUDE_INSIGHTS_SIZE_LIMIT:-120000}
case "$SIZE_LIMIT" in
    ''|*[!0-9]*)
        echo "ERROR: CLAUDE_INSIGHTS_SIZE_LIMIT must be a nonnegative integer" >&2
        exit 1
        ;;
esac
size=$(wc -c <"$INSIGHTS")

if [ "$size" -le "$SIZE_LIMIT" ]; then
    context="Accumulated global insights (~/.claude/global-learned-insights.md), loaded in full.
Check the matching topic BEFORE running a command or applying a pattern you have
not used this session — these entries exist because each one was learned the hard way.

$(cat "$INSIGHTS")"
else
    topics=$(awk '/^## / {sub(/^## /, "- "); print}' "$INSIGHTS")
    [ -z "$topics" ] && exit 0
    context="Accumulated global insights live in ~/.claude/global-learned-insights.md.
The file is ${size} bytes, over the ${SIZE_LIMIT}-byte inject limit, so only its
topic index is loaded — read the matching section before working in that area.
Prune or split the file to restore full loading.

$topics"
fi

jq -n --arg ctx "$context" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
