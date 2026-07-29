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

## Branch Naming

Format: `<type>/<description>` or `<type>/<ticket>-<description>`

## Commit Safety

- Never commit files containing secrets (.env, credentials, API keys, tokens)
- Warn if `.env`, `credentials.json`, or similar files are being staged
- Prefer adding specific files by name over `git add -A` or `git add .`
