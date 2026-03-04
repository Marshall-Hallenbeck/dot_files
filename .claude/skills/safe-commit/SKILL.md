---
name: safe-commit
description: "Scoped commit: commit only task-related changes after validation passes."
allowed-tools: Bash(git add:*), Bash(git restore:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git commit:*)
---

# Safe Commit (Scoped)

Creates a commit from only the intended task scope, never from the full worktree.

## Usage

```text
/safe-commit "<message>" [file1 file2 ...]
```

## Examples

```text
/safe-commit "fix(api): reject unauthorized role updates" backend/src/api/user.ts backend/tests/integration/user-role.test.ts
/safe-commit "chore(ai): split test workflow skills" .claude/skills/run-tests/SKILL.md .claude/skills/run-quality-gate/SKILL.md
```

## Required Behavior

1. Confirm the user explicitly requested a commit.
2. Determine scope:
   - If file args are provided, commit exactly those files.
   - Otherwise derive the scope from task context and current diff.
3. Stage only scoped files:
   ```bash
   git add <scoped-files...>
   git diff --cached --name-only
   ```
4. Run `/run-quality-gate`.
5. Commit:
   ```bash
   git commit -m "<message>"
   ```

## Guardrails

- Never use `git add -A` or `git add .` here.
- Abort if staged diff is empty.
- Abort on any failing quality gate step.
- Use `/safe-commit-all` when the user explicitly wants a full-worktree commit.
