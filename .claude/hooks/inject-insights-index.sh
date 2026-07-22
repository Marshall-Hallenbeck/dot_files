#!/bin/bash
# SessionStart hook: inject the TOPIC INDEX of global-learned-insights.md as
# session context. Loads only the ~20 heading lines instead of the full file,
# so accumulated insights are discoverable without the per-turn context cost
# (or the cross-project noise) of importing every entry. The full section is
# read on demand when the current task matches a topic.

# Consume the SessionStart event JSON on stdin (not reading it can cause
# broken-pipe errors — see reinject-on-compact.sh).
cat >/dev/null

INSIGHTS="$HOME/.claude/global-learned-insights.md"
[ -r "$INSIGHTS" ] || exit 0

topics=$(grep -E '^## ' "$INSIGHTS" | sed 's/^## /- /')
[ -z "$topics" ] && exit 0

context="Accumulated global insights live in ~/.claude/global-learned-insights.md, organized by topic:
$topics

When the current task matches one of these topics, read that section of the file before proceeding. Only this index is loaded; the full entries are not."

jq -n --arg ctx "$context" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
