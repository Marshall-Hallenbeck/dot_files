---
name: safe-commit-all
description: "Group all working-tree changes into logical commits."
argument-hint: "[message]"
disable-model-invocation: true
---

# Safe Commit All

Use `/safe-commit-all ["message"]` to review and commit all working-tree changes.

Read [the shared commit procedure](../commit/references/commit-procedure.md).
Use all-change scope, including staged and relevant untracked files. Check each
file for secrets before staging it.

If there are no changes, stop unless the user explicitly requested an empty
checkpoint. Use `git commit --allow-empty` only for that explicit request.

For an empty checkpoint with a verified open PR:

```bash
git commit --allow-empty -m "<message> (#<PR>)" -m "Refs #<PR>"
```
