#!/bin/bash
# Stop hook: remind to persist ★ Insight blocks that weren't saved.
#
# Hook input arrives on STDIN as JSON. Stop events expose the completed response
# directly at .last_assistant_message. If this hook already blocked one stop,
# .stop_hook_active is true and the next stop must pass to avoid a loop.
set -euo pipefail

input=$(cat)
stop_hook_active=$(jq -r '.stop_hook_active // false' <<< "$input")
[ "$stop_hook_active" = "true" ] && exit 0

last_assistant=$(jq -r '.last_assistant_message // empty' <<< "$input")
[ -z "$last_assistant" ] && exit 0

if [[ "$last_assistant" == *"★ Insight"* && "$last_assistant" != *"learned-insights"* ]]; then
    reason="Your response contained ★ Insight blocks that were not saved. Persist noteworthy ones: global → ~/.claude/global-learned-insights.md, project → .claude/project-learned-insights.md. Skip if trivial or duplicate."
    jq -cn --arg reason "$reason" '{decision:"block",reason:$reason}'
fi
