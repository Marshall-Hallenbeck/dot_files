---
name: full-review-team
description: "Holistic review pipeline ran as a team: simplification, correctness, security, overcautious check, lint/fix, all tests, fix failures, audits, and final review. The one command that checks everything with a team of Opus 4.6 Max Effort agents"
disable-model-invocation: true
---

# Full Review

The holistic review pipeline ran as a team of Opus 4.6 Max Effort agents. Runs every review, every check, every test, fixes what it can, and reports what it can't. Use this before merge/PR when you want maximum confidence.

## Usage

```text
/full-review-team
```

## Pipeline

### Phase 1: Simplify

Run `/simplify` on uncommitted changes. This refactors recently modified code for clarity, consistency, and maintainability while preserving functionality. If no changes are made, continue -- the rest of the pipeline still runs. This phase runs first so all subsequent validation runs against the simplified code.

### Phase 2: Code Review (iterative)

Run `/review` on uncommitted changes. If it reports P0 or P1 findings:
1. Fix each finding
2. Run `/review` again on the updated diff
3. Repeat until verdict is PASS
4. If unsure how to fix a finding, ask the user before guessing

### Phase 3: Security Review

Run `/security-review` on uncommitted changes. Record verdict (SECURE / NEEDS FIXES).

If CRITICAL or HIGH findings, fix them before continuing.

### Phase 4: Overcautious Check

Run `/overcautious-check` on uncommitted changes. Record verdict (CLEAN / BLOCKED).

If BLOCK-level findings, fix them before continuing.

### Phase 5: Quality Gate (lint + tests)

Run `/run-quality-gate`. This runs:
- `/lint --fix` (auto-fixes formatting and lint errors, stages fixed files)
- `/run-unit-tests all`
- `/run-integration-tests all`

If all pass, continue. If tests fail, pass the failure output to Phase 6.

### Phase 6: Fix Test Failures (if any)

If Phase 5 had test failures, run `/fix-tests` with the failure output from Phase 5 (skip re-running the suite):
- Diagnose each failure
- Fix source code (not test assertions)
- Iterate until all tests pass
- If uncertain about intended behavior or what a correct fix looks like, ask the user before guessing

Record: fixes applied.

### Phase 7: Audits (read-only)

Run these checks in sequence. Flag issues but don't auto-fix.

**Skipped test audit:**
Search changed test files for skip patterns:

JS/TS: `.skip`, `.only`, `xit(`, `xdescribe(`, `xtest(`, `pending(`
Python: `@pytest.mark.skip`, `@pytest.mark.skipif`, `pytest.skip(`, `@unittest.skip`, `@unittest.skipIf`, `@unittest.skipUnless`

Flag any found with file paths and line numbers.

**Secret scan:**
Check the diff for potential secrets in added lines:
- API keys: `sk-`, `pk_`, `api_key`, `AKIA`, `aws_secret`
- Credentials: `password`, `secret`, `token`, `credential`
- URLs with embedded creds
- `.env` file contents being committed

If secrets detected: **BLOCK.** Do not continue. Warn the user.

**Coverage check** (if coverage tooling exists):

JS/TS:
```bash
npx jest --coverage --findRelatedTests <changed-files> --coverageReporters=text-summary
```

Python (if pytest-cov is installed):
```bash
pytest --cov --cov-report=term-summary <changed-test-files>
```

Warn if coverage dropped on changed files. Do not block.

### Phase 8: Final Review (conditional)

**Only if changes were made in Phases 1-5** (fixes applied by review, lint, or fix-tests):

Run `/review` one final time on the updated diff to verify fixes didn't introduce new issues.

If no changes were made (everything passed clean on first try), skip this phase.

### Phase 9: Summarize Changes

Run `/summarize-changes` to categorize all uncommitted changes and give the user a clear picture of what they're about to commit.

## Enforcement

- Any phase failure = overall failure.
- No deferring issues. If you see it, you own it -- fix it now.
- Secrets detected = hard block. Do not proceed.
- Do not dismiss test failures as flaky. Investigate and fix.

## Output

```markdown
## Full Review Report

### Phase Results
- Simplify: PASS / REFACTORED N files
- Code review: PASS / NEEDS FIXES (N iterations)
- Security review: SECURE / NEEDS FIXES
- Overcautious check: CLEAN / BLOCKED
- Quality gate: PASS / FAIL (includes lint --fix + all tests)
- Test fixes: N/A / FIXED N failures
- Audits: CLEAN / WARNINGS / BLOCKED

### Auto-Fixed
- [x] Formatted N files
- [x] Fixed N lint errors
- [x] Fixed N review findings
- [x] Fixed N test failures

### Warnings
- [ ] Coverage dropped N% in `file`
- [ ] Skipped test in `file:45`

### Blocked
- [ ] Possible secret in `file:12`
- [ ] Unresolved P1 finding: ...

### Changes Summary
[Output from /summarize-changes]

### Final Verdict: PASS / FAIL
```

**PASS** = no blockers, no unresolved findings, all tests green.
**FAIL** = has blockers, unresolved findings, blamed issues as pre-existing, or test failures that weren't fixed.

## Rules

- **Ask questions.** If you're unsure about how to fix something, or what the intended behavior is, ask the user instead of guessing. It's better to get clarification than to introduce a bad fix. Make free use of AskUserQuestion when you need more info to proceed confidently.
- **Fix everything.** Don't blame things as pre-existing or flaky. If it exists in the diff, you own it. Fix it.
- **Orchestrate.** Create a team of Opus 4.6 Max Effort agents and run `/review`, `/security-review`, `/overcautious-check`, `/run-quality-gate`, `/fix-tests`, and `/summarize-changes`. Don't reimplement their logic, just orchestrate them.
- **Never modify test assertions** to make tests pass.
- **Never commit if secrets are detected.**
- **Stage auto-fix changes** so the user sees them in the diff.
- **Report everything.** Even if all checks pass, show the summary so the user knows what was validated.

