# Shared commit procedure

The calling skill supplies session, explicit-file, or all-change scope.

1. Inspect `git status --short`, staged and unstaged diffs, and relevant untracked
   files. Review existing staged changes before adding anything.
2. Read project commit and validation requirements. Use passing results already
   obtained for the current content. Run missing required checks for the selected
   changes. Do not repeat passing checks unless inputs changed. Report a blocker
   rather than skipping hooks or claiming an unrun check passed.
3. Group authorized changes into coherent commits. Keep unrelated changes apart.
   Never include secrets, credentials, or unrelated work.
4. Stage exact file paths. Never use `git add .` or `git add -A`. For a file with
   mixed ownership, build a patch containing only authorized hunks and apply it
   with `git apply --cached`. Preserve other staged content. If unrelated changes
   are already staged, temporarily unstage their exact paths and restore their
   staged patches after the authorized commit. Do not discard working edits.
5. Inspect each staged diff before committing. Use Conventional Commit subjects.
   Use the user's message when supplied. Add issue, PR, or Sentry references only
   when verified and applicable. Do not add AI attribution or session links.
   For an open PR, include `(#<PR>)` in the subject and `Refs #<PR>` in the body.
   Without a PR, use the related issue number when one exists. Use `Closes #<issue>`
   only for a complete resolution. Add `Sentry-Issue: <SENTRY-ID>` when applicable.
   Omit unavailable references and placeholders. Follow the same rules for merge
   commits.
6. Commit without `--no-verify` or `-n`. Diagnose hook failures. Run any checks
   affected by a subsequent fix before trying again.
7. Report commit IDs, subjects, validation results, and excluded files. Check the
   final status. Push only when the user requested it.

Stop if no authorized changes exist. An empty checkpoint requires an explicit
user request.
