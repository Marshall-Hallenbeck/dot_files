# Git Conventions

## Commit Messages

Follow Conventional Commits: `<type>(scope): description`. Focus on "why" not "what". Use imperative mood. `add` = wholly new, `update` = enhancement to existing.

**Required references:**
- Open pull request: end the subject with `(#<PR>)` and add `Refs #<PR>` in the body.
- Sentry work: add `Sentry-Issue: <SENTRY-ID>` in the body.
- Related GitHub issue: add `Refs #<issue>` in the body.
- Resolved GitHub issue: use `Closes #<issue>`, `Fixes #<issue>`, or `Resolves #<issue>` in the body.
- Merge commits use the same references.
- If no pull request exists, use the related GitHub issue in the subject. Never invent a reference.
- Agent commit commands must not use `--no-verify` or `git commit -n`.

## Pull Requests

Before creating a PR with `gh pr create`, check for a PR template in the target repository:
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/pull_request_template.md`
- `PULL_REQUEST_TEMPLATE.md`

If a template exists, use its exact structure. Fill every applicable section and checkbox. Do not invent a different format.

## Branch Naming

Format: `<type>/<description>` or `<type>/<ticket>-<description>`

## Merging

A request to merge a branch includes integrating and publishing the result. Do not stop at the local merge commit and ask whether to push.

1. `git fetch origin` before merging, and merge the latest base into the feature branch first so conflicts surface on the branch, not on the trunk.
2. Resolve every conflict semantically, preserving upstream and feature intent. Never drop incoming changes silently.
3. Rerun the checks affected by the integrated diff. A merge that pulls in new base behavior is not covered by pre-merge test evidence.
4. Merge into the target branch, then `git push` immediately.
5. Confirm the push landed: the branch must report in sync with its remote (`git status -sb` shows no ahead/behind), and the merge must have applied with no conflict markers left.

Report the merge commit, the push result, and the remote sync state together. A merge that is not pushed is unfinished work.

A merge request authorizes the commits the merge needs: committing the pending work being merged, and the merge commit itself. This is the one exception to "Never Auto-Commit" in `hard-constraints.md`; it does not authorize committing unrelated changes that happen to be in the tree.

Never `git push --force` or `--force-with-lease` without explicit approval. Never rebase a shared branch to resolve a merge conflict.

## Commit Safety

- Never commit files containing secrets (.env, credentials, API keys, tokens)
- Warn if `.env`, `credentials.json`, or similar files are being staged
- Prefer adding specific files by name over `git add -A` or `git add .`
