---
name: run-unit-tests
description: "Run unit-test suites. Auto-detects runner (pytest, Jest, Vitest, cargo, go test)."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Unit Tests

Runs unit-level suites only. Auto-detects the test runner from project files.

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
| `backend`       | Run backend unit tests only |
| `frontend`      | Run frontend unit tests only |
| `all` (default) | Run all detected test suites |

## Runner Detection

Check for these files to determine which runner(s) to use:

| Indicator | Runner | Command |
|-----------|--------|---------|
| `pyproject.toml`, `pytest.ini`, `conftest.py`, `tests/` | pytest | `pytest tests/ -v` |
| `jest.config.*`, `package.json` with jest | Jest | `npx jest --verbose --no-coverage` |
| `vitest.config.*` | Vitest | `npx vitest run` |
| `Cargo.toml` | cargo | `cargo test` |
| `go.mod` | go | `go test ./...` |

If the project uses `uv` (check for `uv.lock`), use `uv run pytest` instead of bare `pytest`.

For each selected workspace, run the first matching runner.

### Python-Specific

```bash
# Run all unit tests
pytest tests/ -v 2>&1

# Run specific file
pytest tests/test_module.py -v 2>&1

# Exclude integration tests (if markers are used)
pytest tests/ -v -m "not integration" 2>&1
```

Check `pyproject.toml` for `[tool.pytest.ini_options]` -- the project may define custom markers, test paths, or default args.

### JS/TS-Specific

```bash
npm run jest:unit --if-present
npm run test:unit --if-present
npm run jest --if-present
npx jest --verbose --no-coverage 2>&1
```

## Output Requirements

- Report pass/fail counts per runner.
- If any selected workspace fails, mark overall result as failed.
- If no test runner is detected for a workspace, report it explicitly (do not silently pretend success).
