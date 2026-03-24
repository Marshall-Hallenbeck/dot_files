---
name: run-quality-gate
description: "Run full quality gate: linting, type checks, unit tests, and integration tests."
disable-model-invocation: false
---

# Run Quality Gate

Runs the full verification pipeline for high-confidence changes. Runs lint, type checks, and tests against the **entire codebase** — not just changed files.

## Usage

```text
/run-quality-gate
```

## Pipeline

1. **Lint/format (auto-fix, full codebase)**:
   - Run `/lint --fix all` — auto-fixes formatting and lint errors across the entire codebase, stages fixed files
2. **Type checking (full codebase)**:
   - Python: `pyright` (no file args = full project)
   - JS/TS: `tsc --noEmit` (full project)
   - Fix ALL type errors found, not just those in changed files
3. **Unit tests**:
   - Run `/run-unit-tests all`
4. **Integration tests**:
   - Run `/run-integration-tests all`

## Enforcement

- Any failing stage means overall failure.
- **Fix ALL errors** — lint, type, and test failures must be fixed regardless of when they were introduced. "Pre-existing" is not a valid reason to skip.
- Do not skip failing suites to force a pass.
- Do not report errors and move on — fix them before claiming the gate passed.

## Output Format

```markdown
## Quality Gate Results

- Lint/format/typecheck: PASS/FAIL
- Unit tests: PASS/FAIL
- Integration tests: PASS/FAIL
- Final verdict: PASS/FAIL
```
