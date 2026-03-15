#!/bin/bash
# Stop hook: reminds Claude to persist ★ Insight blocks to insights files.

response="${CLAUDE_STOP_RESPONSE:-}"
[ -z "$response" ] && exit 0

# Only remind if response has insight blocks but no evidence of saving them
if echo "$response" | grep -qF '★ Insight'; then
    if ! echo "$response" | grep -qF 'learned-insights'; then
        echo "Your response contained ★ Insight blocks that were not saved. Persist noteworthy ones: global → ~/.claude/global-learned-insights.md, project → .claude/project-learned-insights.md. Skip if trivial or duplicate."
    fi
fi
