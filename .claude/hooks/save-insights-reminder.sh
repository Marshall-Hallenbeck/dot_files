#!/bin/bash
# Stop hook: remind to persist ★ Insight blocks that weren't saved.
#
# Hook input arrives on STDIN as JSON. The assistant's response text is NOT in
# the Stop payload — it lives in the transcript file at .transcript_path, so we
# read the last assistant message from there (there is no CLAUDE_STOP_RESPONSE
# env var). Low practical value now that insight-saving is decoupled from ★
# blocks (see rules/auto-save-insights.md); kept as a backstop.

input=$(cat)
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[ -z "$transcript" ] && exit 0
[ -f "$transcript" ] || exit 0

# Last assistant message's text blocks, joined.
last_assistant=$(jq -rs '
  map(select(.type == "assistant")) | last | .message.content
  | if type == "array" then map(select(.type == "text") | .text) | join("\n") else (. // "") end
' "$transcript" 2>/dev/null || true)
[ -z "$last_assistant" ] && exit 0

if echo "$last_assistant" | grep -qF '★ Insight'; then
    if ! echo "$last_assistant" | grep -qF 'learned-insights'; then
        echo "Your response contained ★ Insight blocks that were not saved. Persist noteworthy ones: global → ~/.claude/global-learned-insights.md, project → .claude/project-learned-insights.md. Skip if trivial or duplicate."
    fi
fi
exit 0
