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
3. **Add GitHub issue references** if the work relates to an issue:
   - Include `(#<number>)` at the end of the commit subject line.
   - If the commit fully resolves the issue, add `Closes #<number>` in the body.
4. Commit:
   ```bash
   git commit -m "<message>"
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
git commit --allow-empty -m "<message>"
```

## Hard Rules

- Never run tests, linters, type checks, or quality gates.
- If no changes exist and no checkpoint was requested, abort.
