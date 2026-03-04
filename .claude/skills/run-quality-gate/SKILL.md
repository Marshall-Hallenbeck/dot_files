---
name: run-quality-gate
description: "Run full quality gate: linting, type checks, unit tests, and integration tests."
---

# Run Quality Gate

Runs the full verification pipeline for high-confidence changes.

## Usage

```text
/run-quality-gate
```

## Examples

```text
/run-quality-gate
```

## Pipeline

1. **Lint/format checks** (if scripts exist):
   ```bash
   npm run prettier:check --if-present
   npm run lint --if-present
   ```
2. **Type checks** (if script exists):
   ```bash
   npm run typecheck --if-present
   npx tsc --noEmit --pretty 2>&1
   ```
3. **Unit tests**:
   - Run `/run-unit-tests all`
4. **Integration tests**:
   - Run `/run-integration-tests all`

## Enforcement

- Any failing stage means overall failure.
- Do not label failures as "pre-existing" without explicit before/after evidence.
- Do not skip failing suites to force a pass.

## Output Format

```markdown
## Quality Gate Results

- Lint/format: ✅/❌
- Typecheck: ✅/❌
- Unit tests: ✅/❌
- Integration tests: ✅/❌
- Final verdict: PASS/FAIL
```
