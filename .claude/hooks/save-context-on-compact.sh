#!/bin/bash
set -euo pipefail

# PreCompact hook: saves a snapshot of current work context before compaction.
# This helps the post-compaction SessionStart hook (reinject-on-compact.sh)
# by preserving what the agent was working on.

CONTEXT_FILE="$HOME/.claude/.pre-compact-context.txt"

cat > "$CONTEXT_FILE" <<'EOF'
=== PRE-COMPACT CONTEXT SNAPSHOT ===

This file was saved automatically before context compaction.
The SessionStart compact hook has already re-injected critical rules.
If you need to recall what you were working on, check the conversation
summary that was generated during compaction.

Key reminders:
- Check git status for uncommitted changes from this session
- Check git diff to see what was modified
- The user's task context should be in the compaction summary above
EOF

echo "Pre-compact context saved to $CONTEXT_FILE"
