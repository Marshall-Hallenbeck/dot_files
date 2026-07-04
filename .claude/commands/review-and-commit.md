# Review, Fix, and Commit

Run the full review-fix-verify-commit pipeline on the current working tree.

## Arguments
`$ARGUMENTS` — optional scope or context (e.g. "auth module" or "feature/login branch"). If blank, review all uncommitted changes.

## Steps

1. **Inventory** — Run `git status` and `git diff --stat` to list what changed. If there is nothing to commit, say so and stop.

2. **Quality gates** — Run the project's full quality pipeline. Detect which apply:
   - TypeScript projects: `npx tsc --noEmit` + `npx eslint` (if configured)
   - Python projects: `ruff check` + `pyright`
   - All projects: full test suite (`npm test`, `pytest`, `./gradlew test`, etc.)
   - Fix every failure before continuing.

3. **Full code review** — Scan all changed files for P0–P3 issues:
   - P0: broken logic, data loss, security holes
   - P1: bugs, type errors, missing error handling
   - P2: code quality, missing tests, naming
   - P3: style, dead code, minor inefficiencies
   - Fix ALL findings at every level. Do not skip P2/P3 as "noted".

4. **E2E verification** — If the project has E2E tests and a live stack:
   - Check containers are healthy: `docker compose ps`
   - Run the relevant E2E suite
   - Fix any failures before proceeding

5. **Commit** — Group related changes into logical commits (one feature/fix per commit). Use Conventional Commits format. Include issue numbers if applicable. Do NOT commit unless explicitly asked or unless $ARGUMENTS includes "commit".

6. **Summary** — Report: what was fixed, what tests passed, what was committed (or is ready to commit).
