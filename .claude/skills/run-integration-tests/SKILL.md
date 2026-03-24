---
name: run-integration-tests
description: "Run integration-level suites. Auto-detects runner (pytest markers, Jest, E2E)."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Integration Tests

Runs integration-level validation only. Auto-detects the test runner from project files.

## Usage

```text
/run-integration-tests [scope]
```

## Examples

```text
/run-integration-tests backend
/run-integration-tests e2e
/run-integration-tests all
```

| Scope           | Behavior |
|-----------------|----------|
| `backend`       | Run backend integration tests only |
| `e2e`           | Run E2E / browser integration tests only |
| `all` (default) | Run both when available |

## Command Strategy

### Python (pytest)

```bash
# Run tests marked as integration
pytest tests/ -v -m integration 2>&1

# If no integration marker exists, check for an integration test directory
pytest tests/integration/ -v 2>&1
```

If the project uses `uv`, prefix with `uv run`.

Check `pyproject.toml` for `[tool.pytest.ini_options]` markers -- the project may use different marker names (e.g., `slow`, `db`, `e2e`).

### JS/TS (npm scripts)

```bash
# Backend integration
npm run jest:integration --if-present
npm run test:integration --if-present
```

### E2E / Browser (Playwright, Cypress)

Detect by checking for `playwright.config.*` or `cypress.config.*` in any workspace (root, `frontend/`, `e2e/`, etc.).

**npm script convention** — projects define what "safe E2E" means via scripts:

```bash
# Prefer safe (read-only) E2E tests — avoids mutations against live services
npm run test:e2e:safe --if-present

# Fall back to full E2E
npm run test:e2e --if-present
npm run e2e --if-present
```

**Direct fallback** — if no npm script matches but a Playwright/Cypress config exists:

```bash
# Playwright (detected via playwright.config.*)
npx playwright test --reporter=line 2>&1

# Cypress (detected via cypress.config.*)
npx cypress run 2>&1
```

Run E2E from the directory containing the config file (e.g., `cd frontend && npx playwright test`).

## Guardrails

- Fail fast on environment errors (missing services, auth setup, database not running, etc.).
- Do not skip selected integration scopes silently.
- If no integration tests are found for a scope, report it explicitly.
- Prefer `test:e2e:safe` over `test:e2e` — projects use this convention to exclude destructive/mutation tests from automated runs.
