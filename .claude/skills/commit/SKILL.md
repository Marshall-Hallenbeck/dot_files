---
name: commit
description: "Create a scoped git commit (same behavior as /safe-commit)."
allowed-tools: Bash(git add:*), Bash(git restore:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git commit:*)
---

# Commit (Scoped)

Creates a commit from only task-related files. This is the global alias for `/safe-commit`.

## Usage

```text
/commit "<message>" [file1 file2 ...]
/safe-commit "<message>" [file1 file2 ...]
```

## Examples

```text
/commit "fix(auth): tighten role checks" backend/src/api/auth.ts backend/tests/integration/auth.test.ts
/safe-commit "chore(ai): update skill routing docs" .claude/CLAUDE.md .claude/skills/run-tests/SKILL.md
```

## Required Behavior

1. Scope commit to task files only:
   - If file args are provided, use only those files.
   - If no file args are provided, derive scope from this conversation's work and exclude unrelated diffs.
2. Stage only scoped files:
   ```bash
   git add <scoped-files...>
   git diff --cached --name-only
   ```
3. Run `/run-quality-gate` before final commit.
4. Commit with the provided message:
   ```bash
   git commit -m "<message>"
   ```

## Hard Rules

- Never use `git add -A` or `git add .` in this skill.
- If no scoped changes are staged, abort (no empty commit here).
- If validation fails, abort and report exact failures.
- For full-worktree commits or checkpoint commits, use `/safe-commit-all`.
