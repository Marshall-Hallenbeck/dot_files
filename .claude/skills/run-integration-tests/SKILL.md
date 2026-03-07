---
name: run-integration-tests
description: "Run integration-level suites (backend integration and/or E2E, depending on scope)."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Integration Tests

Runs integration-level validation only.

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
| `backend`       | Run backend integration scripts only |
| `e2e`           | Run frontend/browser integration scripts only |
| `all` (default) | Run both when available |

## Command Strategy

Use the first available script for each selected workspace:

```bash
# backend integration
npm run jest:integration --if-present
npm run test:integration --if-present

# e2e / browser integration
npm run test:e2e --if-present
npm run e2e --if-present
```

## Guardrails

- Fail fast on environment errors (missing services, auth setup, etc.).
- Do not skip selected integration scopes silently.
