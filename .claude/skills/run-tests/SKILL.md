---
name: run-tests
description: "Dispatcher skill for unit, integration, or full quality-gate workflows. Auto-detects language and scope."
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

- `backend/**` or `src/**/*.py` or `tests/**/*.py` changed → include backend unit + backend integration
- `frontend/**` or `*.ts`/`*.tsx`/`*.js`/`*.jsx` changed → include frontend unit
- `frontend/tests/**` or `playwright.config.*` or `*.e2e.*` changed → include e2e integration
- `*.sh` changed → no test dispatch (shell scripts rarely have test suites, but note the change)
- Changes across multiple layers → run `/run-quality-gate`
