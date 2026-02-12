---
name: summarize-changes
description: "Summarize git changes for PRs or commits. Does not commit unless explicitly asked."
---

# Summarize Changes

Summarizes git changes for PR descriptions, release notes, or branch reviews.

## Usage

```
/summarize-changes [branch|commits|range]
```

## Examples

- `/summarize-changes` — Summarize uncommitted changes
- `/summarize-changes feature-branch` — Summarize branch vs main
- `/summarize-changes HEAD~5..HEAD` — Summarize last 5 commits

## Behavior

### 1. Gather Changes

```bash
# For uncommitted changes
git diff --stat
git diff --name-only

# For branch comparison
git log main..HEAD --oneline
git diff main...HEAD --stat
```

### 2. Categorize by Type

- Features (feat:)
- Bug fixes (fix:)
- Refactoring (refactor:)
- Tests (test:)
- Documentation (docs:)
- Chores (chore:)

### 3. Generate Summary

```markdown
## Summary
- 3 features added
- 2 bug fixes
- 15 files changed

### Features
- Added tournament editing UI
- Implemented search functionality

### Bug Fixes
- Fixed caching issue
```

### 4. Commit Gating

- Do **not** commit by default
- If the user explicitly asks to "summarize and commit", proceed to `/safe-commit` after summarizing
- If scope is ambiguous, ask for confirmation before staging
