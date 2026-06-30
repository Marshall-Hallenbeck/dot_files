---
name: optimize-setup
description: "End-to-end Claude Code setup optimization: update CLAUDE.md with session learnings, recommend new automations, audit config quality, clean stale memory, and check for new capabilities."
---

# Optimize Setup

Iterative improvement pipeline for the Claude Code harness. Run periodically (after major sessions, before starting new project phases) to keep CLAUDE.md, skills, hooks, rules, and memory current.

## Pipeline

Run each phase in order. Report what changed at the end.

### Phase 1: Revise CLAUDE.md

Invoke `/claude-md-management:revise-claude-md`.

This updates CLAUDE.md files with learnings from the current session — new patterns discovered, gotchas hit, commands verified, architecture changes made. The goal is to keep CLAUDE.md reflecting ground truth so future sessions start with accurate context.

### Phase 2: Recommend Automations

Invoke `/claude-code-setup:claude-automation-recommender`.

This analyzes the codebase and current Claude Code config to recommend new automations: hooks (pre/post command triggers), subagent types, skills, plugins, and MCP server integrations. It identifies repetitive workflows that could be automated and gaps in the current setup.

After this phase returns recommendations, evaluate each one:
- **Implement** recommendations that are clearly valuable and well-scoped
- **Ask the user** about recommendations that involve tradeoffs or preference
- **Skip** recommendations that are speculative or low-value

### Phase 3: Audit & Improve CLAUDE.md Quality

Invoke `/claude-md-management:claude-md-improver`.

This audits all CLAUDE.md files for quality — checks for stale information, missing sections, inconsistencies, excessive length, and adherence to best practices. It makes targeted updates to improve structure and accuracy.

### Phase 4: Clean Stale Memory

Read the memory index (`MEMORY.md`) and each referenced memory file. For each entry:

1. **Check staleness** — Is the memory still accurate? Has the code/behavior it references changed?
2. **Check relevance** — Is this still useful for future sessions, or was it session-specific?
3. **Check duplication** — Is this information already in CLAUDE.md, project-learned-insights, or derivable from the code?

Remove or update stale entries. Do NOT remove memories the user explicitly asked to save — flag those for user review instead.

Report: N memories reviewed, N updated, N removed, N flagged for user review.

### Phase 5: Refresh Learned Insights

Read both insight files:
- `~/.claude/global-learned-insights.md`
- `<project-root>/.claude/project-learned-insights.md`

For each insight:
1. **Verify** — Is the insight still true? Spot-check claims about file paths, function names, or behavior against current code.
2. **Deduplicate** — Are any insights redundant with each other or with CLAUDE.md?
3. **Prune** — Remove insights that are now obvious from the code or documented elsewhere.

Do not expand or add insights in this phase — that happens organically during work sessions.

### Phase 6: Review Settings & Hooks

Read the current settings files:
- `.claude/settings.json` (project)
- `~/.claude/settings.json` (user)
- `~/.claude/settings.local.json` (local, if exists)

Check for:
- **Permission gaps** — Common commands that still trigger permission prompts (candidates for allowlist)
- **Hook opportunities** — Repetitive manual steps that could be automated with pre/post hooks
- **Stale permissions** — Allowed commands for tools/packages no longer in use

Propose changes but do NOT modify settings without user approval — use `AskUserQuestion` for any setting changes.

### Phase 7: Check for New Capabilities

Search for recent Claude Code updates that the current setup isn't using:

1. Run `claude --version` to check the current version
2. Check if any new skill types, hook events, or agent features are available that aren't configured
3. Look for deprecated patterns in the current config that have better replacements

Report findings as suggestions, not changes.

## Output

```markdown
## Setup Optimization Report

### Phase 1: CLAUDE.md Revisions
- [list of sections updated]

### Phase 2: Automation Recommendations
- Implemented: [list]
- Skipped: [list with reasons]
- User decision needed: [list]

### Phase 3: CLAUDE.md Quality Audit
- [findings and fixes]

### Phase 4: Memory Cleanup
- Reviewed: N memories
- Updated: N
- Removed: N
- Flagged for review: N

### Phase 5: Insights Refresh
- Verified: N insights
- Pruned: N (stale or redundant)

### Phase 6: Settings & Hooks
- [recommendations]

### Phase 7: New Capabilities
- [findings]
```

## Rules

- **Don't bloat CLAUDE.md.** Every line added should earn its place. If something is derivable from the code, don't document it.
- **Don't remove user-created memories** without flagging them first.
- **Don't modify settings** without asking — use `AskUserQuestion`.
- **Be conservative with automation recommendations.** Only recommend automations that solve a real, observed problem. "This could theoretically help" is not enough.
- **Report everything.** Even if all checks pass clean, show the summary so the user knows what was validated.
