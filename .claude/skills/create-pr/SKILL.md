---
name: create-pr
description: "Creates a pull request with proper formatting, running tests first and including a structured description."
---

# Create Pull Request

Creates a well-formatted pull request after verifying tests pass.

## Usage

```
/create-pr [title]
```

## Pre-PR Validation (REQUIRED)

### 1. Pre-Flight Checks

```bash
# Check we're not on main
BRANCH=$(git branch --show-current)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot create PR from main branch"
  exit 1
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: Uncommitted changes exist."
fi
```

### 2. Run Tests

Auto-detect and run the project's test suite. Only proceed if tests pass.

### 3. Gather PR Context

```bash
git log main..HEAD --oneline
git diff main --stat
git diff main --name-only
```

### 4. Generate PR Description

```markdown
## Summary
[2-3 bullet points describing what this PR does]

## Changes
[Categorized list of changes]

## Test Plan
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing completed

## Screenshots (if UI changes)
[Include relevant screenshots]

## Related Issues
Closes #[issue-number]
```

### 5. Create the PR

```bash
git push -u origin HEAD 2>/dev/null || git push
gh pr create --title "[title]" --body "[description]" --base main
```

### 6. Report Success

```
PR Created
Title: [PR title]
URL: [PR URL]
Branch: [branch] → main
```

## Error Handling

- **Tests failing** → Abort, report failures
- **Uncommitted changes** → Warn, suggest `/safe-commit`
- **Already on main** → Abort, suggest creating a branch
