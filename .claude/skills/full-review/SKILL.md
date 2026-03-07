---
name: full-review
description: "Holistic review pipeline: correctness, security, overcautious check, lint/fix, all tests, fix failures, audits, and final review. The one command that checks everything."
---

# Full Review

The holistic review pipeline. Runs every review, every check, every test, fixes what it can, and reports what it can't. Use this before merge/PR when you want maximum confidence.

## Usage

```text
/full-review
```

## Pipeline

### Phase 1: Code Review (iterative)

Run `/review` on uncommitted changes. If it reports P0 or P1 findings:
1. Fix each finding
2. Run `/review` again on the updated diff
3. Repeat until verdict is PASS
4. If unsure how to fix a finding, ask the user before guessing

### Phase 2: Security Review

Run `/security-review` on uncommitted changes. Record verdict (SECURE / NEEDS FIXES).

If CRITICAL or HIGH findings, fix them before continuing.

### Phase 3: Overcautious Check

Run `/overcautious-check` on uncommitted changes. Record verdict (CLEAN / BLOCKED).

If BLOCK-level findings, fix them before continuing.

### Phase 4: Quality Gate (lint + tests)

Run `/run-quality-gate`. This runs:
- `/lint --fix` (auto-fixes formatting and lint errors, stages fixed files)
- `/run-unit-tests all`
- `/run-integration-tests all`

If all pass, continue. If tests fail, pass the failure output to Phase 5.

### Phase 5: Fix Test Failures (if any)

If Phase 4 had test failures, run `/fix-tests` with the failure output from Phase 4 (skip re-running the suite):
- Diagnose each failure
- Fix source code (not test assertions)
- Iterate until all tests pass
- If uncertain about intended behavior or what a correct fix looks like, ask the user before guessing

Record: fixes applied.

### Phase 6: Audits (read-only)

Run these checks in sequence. Flag issues but don't auto-fix.

**Skipped test audit:**
Search changed test files for skip patterns:
- `.skip`, `.only`, `xit(`, `xdescribe(`, `xtest(`, `@skip`, `pending(`

Flag any found with file paths and line numbers.

**Secret scan:**
Check the diff for potential secrets in added lines:
- API keys: `sk-`, `pk_`, `api_key`, `AKIA`, `aws_secret`
- Credentials: `password`, `secret`, `token`, `credential`
- URLs with embedded creds
- `.env` file contents being committed

If secrets detected: **BLOCK.** Do not continue. Warn the user.

**Coverage check** (if coverage script exists):
```bash
npx jest --coverage --findRelatedTests <changed-files> --coverageReporters=text-summary
```
Warn if coverage dropped on changed files. Do not block.

### Phase 7: Final Review (conditional)

**Only if changes were made in Phases 1-5** (fixes applied by review, lint, or fix-tests):

Run `/review` one final time on the updated diff to verify fixes didn't introduce new issues.

If no changes were made (everything passed clean on first try), skip this phase.

### Phase 8: Summarize Changes

Run `/summarize-changes` to categorize all uncommitted changes and give the user a clear picture of what they're about to commit.

## Enforcement

- Any phase failure = overall failure.
- No deferring issues. If you see it, you own it — fix it now.
- Secrets detected = hard block. Do not proceed.
- Do not dismiss test failures as flaky. Investigate and fix.

## Output

```markdown
## Full Review Report

### Phase Results
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
- [ ] Coverage dropped N% in `file.ts`
- [ ] Skipped test in `file.test.ts:45`

### Blocked
- [ ] Possible secret in `file.ts:12`
- [ ] Unresolved P1 finding: ...

### Changes Summary
[Output from /summarize-changes]

### Final Verdict: PASS / FAIL
```

**PASS** = no blockers, no unresolved P0/P1/CRITICAL/HIGH/BLOCK findings, all tests green.
**FAIL** = has blockers or unresolved critical findings.

## Rules

- **Compose, don't duplicate.** Delegate to `/review`, `/security-review`, `/overcautious-check`, `/run-quality-gate`, `/fix-tests`, and `/summarize-changes`. Don't reimplement their logic.
- **Never modify test assertions** to make tests pass.
- **Never commit if secrets are detected.**
- **Stage auto-fix changes** so the user sees them in the diff.
- **Report everything.** Even if all checks pass, show the summary so the user knows what was validated.
- **Skip the final review** if nothing was changed — don't waste time re-reviewing clean code.
