---
name: safe-commit-all
description: "Group ALL working-tree changes into logical commits."
argument-hint: "[message]"
disable-model-invocation: true
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git commit:*)
---

# Safe Commit All

Groups all working-tree changes into logical commits.

## Usage

```text
/safe-commit-all                # auto-group all changes
/safe-commit-all "<message>"    # use message (single commit if all related)
```

## Required Behavior

### 1. Assess Changes

```bash
git status --short
git diff --stat
```

### 2. Group Into Logical Commits

Analyze all changes and split them into logical groups. Each group should represent a single coherent change (one feature, one fix, one refactor, etc.).

Grouping heuristics:
- Files that serve the same purpose (e.g., a component + its test + its styles) belong together.
- Config changes that are unrelated to code changes get their own commit.
- Unrelated bug fixes get separate commits from feature work.
- If ALL changes are genuinely related, a single commit is fine.

### 3. Commit Each Group

For each logical group:
1. Stage that group's files:
   ```bash
   git add <files-in-group...>
   ```
2. Generate a commit message following Conventional Commits (`<type>(scope): description`).
   - If the user provided a message and there's only one group, use that message.
   - If the user provided a message and there are multiple groups, use it for the most relevant group and generate messages for the others.
3. **Add required traceability references**:
   - If the branch has an open pull request, end the subject with `(#<PR>)` and add `Refs #<PR>` in the body.
   - If the work has a Sentry issue, add `Sentry-Issue: <SENTRY-ID>` in the body.
   - If the work has a related GitHub issue, add `Refs #<issue>` in the body. Use `Closes #<issue>` only when the commit fully resolves that issue.
   - If no pull request exists yet, use the related GitHub issue number for the subject suffix. Do not invent a reference.
   - Use the same references on merge commits.
4. Commit:
   ```bash
   git commit -m "<type>(<scope>): <description> (#<PR>)" \
     -m "Refs #<PR>" \
     -m "Sentry-Issue: <SENTRY-ID>"
   ```

### 4. Report Results

After all commits, show a summary:
```
Committed:
  abc1234 fix(auth): tighten role checks
  def5678 chore(deps): bump eslint to v9
```

### 5. Empty Commits

If no changes exist and the user explicitly requested a checkpoint:
```bash
git commit --allow-empty -m "<message> (#<PR>)" \
  -m "Refs #<PR>" \
  -m "Sentry-Issue: <SENTRY-ID>"
```
Apply only verified references. If no pull request or Sentry issue applies, omit its placeholder and trailer.

## Hard Rules

- Never run tests, linters, type checks, or quality gates.
- Never use `--no-verify` or `git commit -n`.
- If no changes exist and no checkpoint was requested, abort.
