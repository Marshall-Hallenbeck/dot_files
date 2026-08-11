---
name: create-pr
description: Use when asked to create, open, publish, or submit a pull request from the current branch
argument-hint: "[title]"
disable-model-invocation: true
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

### 4. Select Labels (REQUIRED)

List labels that exist in the repository:

```bash
gh label list --limit 200 --json name,description
```

Select all clearly applicable labels from the PR title, body, linked issue, and changed files.

- Prefer an existing work-type label such as `bug`, `enhancement`, `documentation`, `refactor`, `security`, or `tests` when it accurately describes the change.
- Add existing affected-area labels when the changed files clearly identify the area.
- Use exact names from the command output. Never create, rename, or guess a label.
- Keep labels already present on a linked issue only when they also describe the PR.
- If no existing label clearly applies, create the PR without a label and report that no match exists.

### 5. Generate PR Description

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

### 6. Create the PR

```bash
git push -u origin HEAD 2>/dev/null || git push
gh pr create --title "[title]" --body "[description]" --base main \
  --label "<label>" --label "<label>"
```

Then verify:

```bash
gh pr view <PR-NUMBER> --json labels
```

### 7. Report Success

```
PR Created
Title: [PR title]
URL: [PR URL]
Branch: [branch] → main
Labels: [saved labels]
```

## Error Handling

- **Tests failing** → Abort, report failures
- **Uncommitted changes** → Warn, suggest `/safe-commit`
- **Already on main** → Abort, suggest creating a branch
- **Label discovery failure** → Abort, report the failure
- **Label application or verification failure** → Abort, report the failure
