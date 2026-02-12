---
name: git-status
description: "Check git repository status including current branch, uncommitted changes, staged files, and recent commits."
---

# Git Status

Check and report the current git repository state.

## Usage

```
/git-status
```

## Steps

### 1. Get Current Status

```bash
git status
```

### 2. Get Unstaged Changes

```bash
git diff --stat
```

### 3. Get Staged Changes

```bash
git diff --cached --stat
```

### 4. Get Recent Commits

```bash
git log --oneline -5
```

## Output Format

```markdown
## Git Status

**Branch:** [branch name]
**Clean:** [Yes/No]

### Changes
- Modified: [files]
- Staged: [files]
- Untracked: [files]

### Recent Commits
[5 most recent commits]

### Recommendations
[Advice based on state — e.g., "uncommitted changes, consider committing or stashing"]
```
