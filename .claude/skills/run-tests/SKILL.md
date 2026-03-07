---
name: run-tests
description: "Dispatcher skill for unit, integration, or full quality-gate workflows."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Tests

Dispatcher skill that routes to the dedicated test workflows.

## Usage

```text
/run-tests [scope]
```

## Examples

```text
/run-tests unit
/run-tests integration
/run-tests backend
/run-tests all
```

| Scope         | Delegates To |
|---------------|--------------|
| `unit`        | `/run-unit-tests` |
| `integration` | `/run-integration-tests` |
| `all`         | `/run-quality-gate` |
| `backend`     | `/run-unit-tests backend` + `/run-integration-tests backend` |
| `frontend`    | `/run-unit-tests frontend` |
| `e2e`         | `/run-integration-tests e2e` |
| (no argument) | Auto-detect from changed files, then dispatch |

## Auto-Detection Rules

Use `git diff --name-only HEAD`:

- `backend/**` changed → include backend unit + backend integration
- `frontend/**` changed → include frontend unit
- `frontend/tests/**` or `playwright.config.*` changed → include e2e integration
- Changes across multiple layers → run `/run-quality-gate`
