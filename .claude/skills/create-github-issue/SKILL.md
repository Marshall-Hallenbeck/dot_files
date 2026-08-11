---
name: create-github-issue
description: Use when asked to create, open, file, or draft a GitHub issue
argument-hint: "[title]"
disable-model-invocation: true
---

# Create GitHub Issue

Create a complete issue only after duplicate and label checks.

## 1. Gather the Request

Gather the problem, expected behavior, actual behavior, acceptance criteria, and relevant scope. Ask for missing details only when they prevent an accurate issue.

## 2. Check for Duplicates

Search open and closed issues before creating a new issue:

```bash
gh issue list --state all --search "<search terms>" --limit 20
```

Stop and report the existing issue when a duplicate already covers the request.

## 3. Select Labels

List labels that exist in the repository:

```bash
gh label list --limit 200 --json name,description
```

Select all clearly applicable labels from the issue title, requested behavior, and scope.

- Prefer an existing work-type label such as `bug`, `enhancement`, `documentation`, `refactor`, `security`, or `tests` when it accurately describes the issue.
- Add existing affected-area labels when the requested scope clearly identifies the area.
- Use exact names from the command output. Never create, rename, or guess a label.
- If no existing label clearly applies, create the issue without a label and report that no match exists.

## 4. Build the Issue Body

Use this structure:

```markdown
## Summary

## Current Behavior

## Expected Behavior

## Acceptance Criteria
- [ ] Criterion

## Technical Notes
```

## 5. Create the Issue

Create the issue with one `--label "<label>"` argument for each selected label:

```bash
gh issue create --title "<title>" --body "<description>" \
  --label "<label>" --label "<label>"
```

## 6. Verify and Report

Verify the saved labels:

```bash
gh issue view <ISSUE-NUMBER> --json labels
```

Report the issue URL and saved labels.
