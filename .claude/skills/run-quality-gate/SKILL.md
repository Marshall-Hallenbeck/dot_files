---
name: run-quality-gate
description: "Run full quality gate: linting, type checks, unit tests, and integration tests — all in parallel."
disable-model-invocation: false
---

# Run Quality Gate

Runs the full verification pipeline for high-confidence changes. All gates run **in parallel via background agents** for maximum speed.

## Usage

```text
/run-quality-gate
```

## Execution Strategy

**IMPORTANT: Run all 6 gates in parallel as background agents in a single message.** Do not run them sequentially. Each gate is independent — spawn all 6 agents at once and wait for results.

### Gate 1: Lint/format (Python)
```bash
# Auto-detect: if project has uv.lock, use uv run
uv run ruff check --fix src/ tests/ && uv run ruff format src/ tests/
# If ruff --fix made changes, stage them
```
Agent prompt: "Run ruff check --fix and ruff format on src/ and tests/. Stage any auto-fixed files. Report errors that couldn't be auto-fixed."

### Gate 2: Python type checking
```bash
uv run pyright src/
```
Agent prompt: "Run pyright on src/. Report all type errors with file:line locations."

### Gate 3: TypeScript type checking
```bash
cd frontend && npx tsc --noEmit
```
Agent prompt: "Run tsc --noEmit in the frontend/ directory. Report all type errors."

### Gate 4: Python unit tests
```bash
uv run pytest tests/ -q
```
Agent prompt: "Run the full pytest suite. Report pass/fail counts and any failures with tracebacks."

### Gate 5: Frontend unit tests (Jest)
```bash
cd frontend && npx jest --no-coverage
```
Agent prompt: "Run the full Jest test suite in frontend/. Report pass/fail counts and any failures."

### Gate 6: E2E tests (Playwright)
```bash
cd frontend && npm run test:e2e:safe
```
This runs `playwright test --grep-invert @mutation` (read-only, skips mutation tests).
Agent prompt: "Run Playwright E2E tests via npm run test:e2e:safe in frontend/. Report pass/fail counts and any failures."

## After All Gates Complete

1. Collect results from all 6 agents
2. Present the summary table
3. If ANY gate failed, fix the errors — do not just report them
4. Re-run only the failed gates after fixing
5. Repeat until all gates pass

## Enforcement

- Any failing gate means overall failure.
- **Fix ALL errors** — lint, type, and test failures must be fixed regardless of when they were introduced. "Pre-existing" is not a valid reason to skip.
- Do not skip failing suites to force a pass.
- Do not report errors and move on — fix them before claiming the gate passed.

## Output Format

```markdown
## Quality Gate Results

| Gate | Result | Details |
|------|--------|---------|
| Ruff lint/format | PASS/FAIL | N errors |
| Pyright | PASS/FAIL | N errors |
| TypeScript | PASS/FAIL | N errors |
| Pytest | PASS/FAIL | N passed, N failed |
| Jest | PASS/FAIL | N passed, N failed |
| Playwright E2E | PASS/FAIL | N passed, N failed |
| **Final verdict** | **PASS/FAIL** | |
```
