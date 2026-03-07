---
name: full-review-ultra
description: "Full review pipeline plus code simplification. Runs /simplify first, then the complete /full-review pipeline."
---

# Full Review Ultra

Everything `/full-review` does, plus a `/simplify` pass up front. Use this when you want maximum code quality — not just correctness, but clarity and maintainability too.

## Usage

```text
/full-review-ultra
```

## Pipeline

### Phase 1: Simplify

Run `/simplify` on uncommitted changes. This refactors recently modified code for clarity, consistency, and maintainability while preserving functionality.

### Phase 2–9: Full Review

Run `/full-review`. This executes all standard phases:

2. Code Review (iterative)
3. Security Review
4. Overcautious Check
5. Quality Gate (lint --fix + all tests)
6. Fix Test Failures (if any)
7. Audits (read-only)
8. Final Review (conditional)
9. Summarize Changes

See `/full-review` for details on each phase.

## Output

```markdown
## Full Review Ultra Report

### Phase Results
- Simplify: PASS / REFACTORED N files
- [All /full-review phase results]

### Final Verdict: PASS / FAIL
```

## Rules

- **Compose, don't duplicate.** Delegate to `/simplify` and `/full-review`. Don't reimplement their logic.
- Phase 1 runs first so that all subsequent validation (review, security, tests) runs against the simplified code.
- If `/simplify` makes no changes, continue — the rest of the pipeline still runs.
