---
name: run-unit-tests
description: "Run unit-test suites only (backend/frontend/root depending on scope)."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Unit Tests

Runs unit-level suites only.

## Usage

```text
/run-unit-tests [scope]
```

## Examples

```text
/run-unit-tests backend
/run-unit-tests frontend
/run-unit-tests all
```

| Scope           | Behavior |
|-----------------|----------|
| `backend`       | Run unit scripts in `backend/` only |
| `frontend`      | Run unit scripts in `frontend/` only |
| `all` (default) | Run backend + frontend if present, otherwise root |

## Command Strategy

For each selected workspace (`backend`, `frontend`, or root), run the first matching unit script:

```bash
npm run jest:unit --if-present
npm run test:unit --if-present
npm run jest --if-present
```

If no unit script exists in a workspace, report it explicitly (do not silently pretend success).

## Output Requirements

- Report pass/fail counts per workspace.
- If any selected workspace fails, mark overall result as failed.
