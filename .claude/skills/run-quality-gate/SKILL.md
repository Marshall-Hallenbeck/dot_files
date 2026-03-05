---
name: run-quality-gate
description: "Run full quality gate: linting, type checks, unit tests, and integration tests."
---

# Run Quality Gate

Runs the full verification pipeline for high-confidence changes. Composes `/lint`, `/run-unit-tests`, and `/run-integration-tests`.

## Usage

```text
/run-quality-gate
```

## Pipeline

1. **Lint/format/typecheck**:
   - Run `/lint`
2. **Unit tests**:
   - Run `/run-unit-tests all`
3. **Integration tests**:
   - Run `/run-integration-tests all`

## Enforcement

- Any failing stage means overall failure.
- Do not dismiss failures — if a test fails, fix it regardless of when it was introduced.
- Do not skip failing suites to force a pass.

## Output Format

```markdown
## Quality Gate Results

- Lint/format/typecheck: PASS/FAIL
- Unit tests: PASS/FAIL
- Integration tests: PASS/FAIL
- Final verdict: PASS/FAIL
```
