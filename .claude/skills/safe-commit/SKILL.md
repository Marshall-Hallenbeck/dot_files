---
name: safe-commit
description: "Group changes into logical commits. Same as /commit."
argument-hint: "[message] [files...]"
disable-model-invocation: true
allowed-tools: Bash(git add:*), Bash(git restore:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git commit:*)
---

# Safe Commit

Groups working-tree changes into logical commits. Same behavior as `/commit`.

## Usage

```text
/safe-commit                              # auto-group all changes
/safe-commit "<message>" [file1 file2 ...]  # commit specific files with message
```

## Required Behavior

### 1. Assess Changes

```bash
git status --short
git diff --stat
git diff --cached --stat
```

### 2. Group Into Logical Commits

Analyze all unstaged and staged changes and split them into logical groups. Each group should represent a single coherent change (one feature, one fix, one refactor, etc.).

Grouping heuristics:
- Files that serve the same purpose (e.g., a component + its test + its styles) belong together.
- Config changes that are unrelated to code changes get their own commit.
- Unrelated bug fixes get separate commits from feature work.
- If ALL changes are genuinely related, a single commit is fine.

### 3. Commit Each Group

For each logical group:
1. Stage only that group's files:
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

## Hard Rules

- Never use `git add -A` or `git add .`.
- Never run tests, linters, type checks, or quality gates.
- If no changes exist, abort.
- If file args are provided, commit exactly those files (skip grouping).
- For full-worktree commits, use `/safe-commit-all`.
