---
name: postflight
description: "Wrap up a task: summarize changes, recommend test scope, and remind about commit policy."
---

# Postflight

Summarize work and recommend validation steps after changes.

## Usage

```
/postflight
```

## Steps

### 1. Format Changed Files

For all changed files, ensure formatting is consistent (run project formatter if available).

### 2. Summarize Changes

Use `/summarize-changes` to generate a summary of what was done.

### 3. Recommend Test Scope

Use path-based selection from `git diff --name-only`:
- Detect which areas of the project changed
- Recommend the appropriate test commands
- If monorepo, recommend per-workspace test commands

### 4. Commit Reminder (Conditional)

Only suggest committing when the user explicitly asks. If prompted, run `/summarize-changes` first, then `/safe-commit`.

## Output Format

```markdown
## Postflight

### Summary
[Brief summary of changes]

### Recommended Tests
- [test command for changed area]

### Notes
[Any follow-ups or risks]
```
