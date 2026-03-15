#!/bin/bash
set -euo pipefail

# Re-inject critical behavioral rules after context compaction.
# These are the rules most likely to cause drift when compacted.

RULES_DIR="$HOME/.claude/rules"

echo "=== CRITICAL RULES (re-injected after compaction) ==="
echo ""

for rule in "$RULES_DIR"/*.md; do
  if [[ -f "$rule" ]]; then
    echo "# $(basename "$rule" .md)"
    echo ""
    cat "$rule"
    echo ""
  fi
done

# Re-inject global CLAUDE.md
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
if [[ -f "$GLOBAL_CLAUDE" ]]; then
  echo "=== GLOBAL CLAUDE.MD (re-injected after compaction) ==="
  echo ""
  cat "$GLOBAL_CLAUDE"
  echo ""
fi

# Re-inject project CLAUDE.md and project rules if in a git repo
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$PROJECT_ROOT" ]]; then
  if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    echo "=== PROJECT CLAUDE.MD (re-injected after compaction) ==="
    echo ""
    cat "$PROJECT_ROOT/CLAUDE.md"
    echo ""
  fi
  PROJECT_RULES="$PROJECT_ROOT/.claude/rules"
  if [[ -d "$PROJECT_RULES" ]]; then
    for rule in "$PROJECT_RULES"/*.md; do
      if [[ -f "$rule" ]]; then
        echo "# $(basename "$rule" .md) (project rule)"
        echo ""
        cat "$rule"
        echo ""
      fi
    done
  fi
fi
