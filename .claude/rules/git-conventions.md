# Git Conventions

## Commit Messages

Follow Conventional Commits: `<type>(scope): description`. Focus on "why" not "what". Use imperative mood. `add` = wholly new, `update` = enhancement to existing.

**GitHub Issue References:**
- Include `(#<number>)` at the end of the commit subject line
- Closing keywords in body: `Closes #<number>`, `Fixes #<number>`, `Resolves #<number>`
- Partial progress: `Part of #<number>` or just `(#<number>)` in the subject

## Branch Naming

Format: `<type>/<description>` or `<type>/<ticket>-<description>`

## Commit Safety

- Never commit files containing secrets (.env, credentials, API keys, tokens)
- Warn if `.env`, `credentials.json`, or similar files are being staged
- Prefer adding specific files by name over `git add -A` or `git add .`
