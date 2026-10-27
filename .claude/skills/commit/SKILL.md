---
name: commit
description: "Commit session changes only, or all changes if no session edits."
argument-hint: "[message] [files...]"
disable-model-invocation: true
---

# Commit

Use `/commit ["message"] [files...]` to group and commit the requested changes.

- Explicit file arguments select those files.
- Otherwise, select changes made in this session.
- If there are no session edits, review all working-tree changes.
- Preserve unrelated edits and staged content. For mixed files, select only the
  authorized hunks.

Read [the shared commit procedure](references/commit-procedure.md) before staging.
It defines validation, grouping, commit messages, and reporting.
