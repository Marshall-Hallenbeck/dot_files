---
name: normalize-ai-config
description: "Normalize agents/skills/hooks so responsibilities are separated and workflows are coherent."
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
   - Hooks (`.claude/hooks.json`, `hookify*.md`)
   - Global rules (`.claude/rules/*.md`)
2. **Detect overlaps**
   - Multiple skills trying to own the same command intent
   - Test workflows mixing unit/integration/full-gate responsibilities
   - Commit workflows mixing scoped vs full-worktree behavior
3. **Normalize boundaries**
   - Commit group: `/safe-commit`, `/safe-commit-all`
   - Test group: `/run-unit-tests`, `/run-integration-tests`, `/run-quality-gate`, `/run-tests`
   - Review group: `/full-review` + `/overcautious_check` + `/review`
4. **Validate install wiring (dotfiles repo)**
   - Ensure `install_environment.sh` includes every canonical skill in `SKILL_DIRS`.
5. **Report**
   - What overlapped
   - What changed
   - Final command map

## Output Expectations

- Show overlap findings
- Show normalized command ownership
- Show whether install wiring is complete
