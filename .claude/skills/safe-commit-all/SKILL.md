---
name: safe-commit-all
description: "Commit all working-tree changes (or an empty checkpoint commit) after validation."
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git diff:*), Bash(git commit:*)
---

# Safe Commit All

Commits the full working tree. Supports empty checkpoint commits when explicitly requested.

## Usage

```text
/safe-commit-all "<message>"
```

## Examples

```text
/safe-commit-all "chore: checkpoint before rebase"
/safe-commit-all "chore: empty checkpoint after full validation"
```

## Required Behavior

1. Confirm explicit user request to commit all changes.
2. Run `/run-quality-gate`.
3. Stage all changes:
   ```bash
   git add --all
   git diff --cached --name-only
   ```
4. Commit:
   - If staged changes exist:
     ```bash
     git commit -m "<message>"
     ```
   - If no staged changes exist:
     ```bash
     git commit --allow-empty -m "<message>"
     ```

## Guardrails

- Never run automatically.
- Do not use this for scoped feature commits; use `/safe-commit`.
- If validation fails, abort and report failures.
