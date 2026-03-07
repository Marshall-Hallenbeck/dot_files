#!/bin/bash
set -euo pipefail

# Re-inject critical behavioral rules after context compaction.
# These are the rules most likely to cause drift when compacted.

RULES_DIR="$HOME/.claude/rules"

echo "=== CRITICAL RULES (re-injected after compaction) ==="
echo ""

for rule in hard-constraints.md error-handling.md coding-practices.md verification.md; do
  if [[ -f "$RULES_DIR/$rule" ]]; then
    cat "$RULES_DIR/$rule"
    echo ""
  fi
done

# Re-inject key sections from global CLAUDE.md
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
if [[ -f "$GLOBAL_CLAUDE" ]]; then
  echo "=== GLOBAL CLAUDE.MD (re-injected after compaction) ==="
  echo ""
  cat "$GLOBAL_CLAUDE"
fi
