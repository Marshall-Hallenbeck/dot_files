---
name: normalize-ai-config
description: "Normalize agents/skills/hooks so responsibilities are separated and workflows are coherent."
disable-model-invocation: true
---

# Normalize AI Config

Audits and normalizes AI configuration so commands are logically separated without overlap.

## Usage

```text
/normalize-ai-config
```

## Examples

```text
/normalize-ai-config
```

Use when skills/agents drift, overlap, or routing behavior becomes confusing.

## What This Skill Does

1. **Inventory**
   - Skills (`.claude/skills/*/SKILL.md`)
   - Agents (`.claude/agents/*.md`)
   - Hook commands in `.claude/settings.json`, hook scripts, and `hookify*.md`
   - Global instructions (`global-AGENTS.md`)
2. **Detect overlaps**
   - Multiple skills trying to own the same command intent
   - Test workflows mixing unit/integration/full-gate responsibilities
   - Commit workflows mixing scoped vs full-worktree behavior
3. **Normalize boundaries**
   - Commit group: `/commit` (session scope) and `/safe-commit-all` (all changes), sharing one commit procedure
   - Test group: `/run-unit-tests`, `/run-integration-tests`, `/run-quality-gate`, `/run-tests`
   - Review group: `/ship` (review-to-merge pipeline) + `/review` + `/security-review` + `/overcautious-check`
4. **Validate install wiring (dotfiles repo)**
   - Check directory loops in `install_environment.sh` and `.local/libexec/codex-config-sync.py`.
   - Verify links resolve and managed exclusions survive updates. Keep account downloads out of Git.
5. **Report**
   - What overlapped
   - What changed
   - Final command map

## Output Expectations

- Show overlap findings
- Show normalized command ownership
- Show whether install wiring is complete
