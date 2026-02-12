# Git Conventions

## Commit Messages

Follow Conventional Commits: `<type>(scope): description`

**Types:**
- `feat` — New feature (wholly new functionality)
- `fix` — Bug fix
- `docs` — Documentation only
- `style` — Formatting, no code change
- `refactor` — Code restructuring, no behavior change
- `perf` — Performance improvement
- `test` — Adding or updating tests
- `chore` — Build, tooling, dependencies
- `ci` — CI/CD configuration

**Guidelines:**
- Focus on "why" rather than "what"
- Keep the first line under 72 characters
- Use imperative mood ("add feature" not "added feature")
- `add` means wholly new functionality, `update` means enhancement to existing

## Branch Naming

Format: `<type>/<description>` or `<type>/<ticket>-<description>`

Examples:
- `feat/user-authentication`
- `fix/login-redirect-loop`
- `refactor/api-error-handling`

## Commit Safety

- Never commit files containing secrets (.env, credentials, API keys, tokens)
- Warn if `.env`, `credentials.json`, or similar files are being staged
- Prefer adding specific files by name over `git add -A` or `git add .`
