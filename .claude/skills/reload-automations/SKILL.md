---
description: Reload global and project instruction files (AGENTS.md, CLAUDE.md, rules) into this session after config changes (local or remote). Skills, agents, and hooks auto-update — only instruction files need re-reading.
---

# Reload Automations

The current contents of all AGENTS.md, CLAUDE.md and rules files are below (deduplicated by content hash). These versions supersede any earlier versions in this conversation.

!`declare -A seen; while read -r f; do hash=$(md5sum "$f" 2>/dev/null | cut -d' ' -f1) || continue; [[ -z "${seen[$hash]:-}" ]] && seen[$hash]=1 && echo "--- FILE: $f ---" && cat "$f" && echo; done < <(echo ~/.claude/CLAUDE.md; ls ~/.claude/rules/*.md 2>/dev/null; ls .claude/rules/*.md 2>/dev/null; find . -maxdepth 2 \( -name "CLAUDE.md" -o -name "AGENTS.md" \) -not -path "./.git/*" 2>/dev/null)`

## After reloading

Confirm to the user which files were loaded, then resume whatever was in progress before the reload was invoked.
