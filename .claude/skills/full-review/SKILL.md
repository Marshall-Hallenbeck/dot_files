---
name: full-review
description: "Holistic review pipeline: simplification, correctness, security, overcautious check, lint/fix, all tests, fix failures, audits, and final review. Fixes EVERYTHING — every severity and every warning — so nothing is left open."
---

# Full Review

The holistic review pipeline. Runs every review, every check, every test, and **fixes everything it finds** — every severity and every warning. The end state is zero open issues. Use this before merge/PR when you want maximum confidence.

**Core mandate: nothing is "defer for later." Every finding (P0–P3, CRITICAL–LOW, BLOCK/WARN), every lint warning, and every coverage regression gets fixed in this run.** The only two things that are NOT a silent skip: a verified false positive (stated, with reasoning) or a fix that needs a product/threat-model decision (surfaced to the user). Everything else is fixed.

## Usage

```text
/full-review
```

## Pipeline

### Phase 1: Simplify

Run `/simplify` on uncommitted changes. This refactors recently modified code for clarity, consistency, and maintainability while preserving functionality. Apply every cleanup it surfaces. If no changes are made, continue -- the rest of the pipeline still runs. This phase runs first so all subsequent validation runs against the simplified code.

### Phase 2: Code Review (iterative)

Run `/review` on uncommitted changes. `/review` finds AND fixes every finding. Then:
1. Fix **every** finding — P0, P1, P2, AND P3. No severity is deferred.
2. Run `/review` again on the updated diff.
3. Repeat until it reports ZERO findings.
4. If a fix is genuinely ambiguous, or would require adding code that violates a project rule (e.g. unrequested defensive guards), ask the user before guessing — do NOT silently leave the finding.

### Phase 3: Security Review

Run `/security-review` on uncommitted changes. Fix **every** finding it reports — CRITICAL, HIGH, MEDIUM, AND LOW — and add a regression test for each where one is meaningful. Re-run until it reports zero findings. Only pause to ask the user when a fix needs a threat-model decision or would change an auth model in a way that affects behavior; never defer a finding silently.

### Phase 4: Overcautious Check

Run `/overcautious-check` on uncommitted changes. Fix **every** finding — BLOCK and WARN (and any INFO that is a genuine masking pattern rather than a legitimate boundary). Re-run until it reports zero findings. The fix is always to let the failure surface (remove the swallow/fallback/silencer) — never to add new defensive code.

### Phase 5: Quality Gate (lint + tests)

Run `/run-quality-gate`. This runs lint/format (`--fix`), type checks, and the full unit + integration suites.

A passing gate means **zero lint errors AND zero lint warnings**, zero type errors, and all tests green. Treat lint warnings as failures and fix them. Never silence a warning with an inline disable (`eslint-disable`, `@ts-ignore`, etc.) to force a pass — fix the underlying cause. If a lint rule is genuinely wrong for this codebase, change the lint *config* deliberately and say so. If tests fail, pass the failure output to Phase 6.

### Phase 6: Fix Test Failures (if any)

If Phase 5 had test failures, run `/fix-tests` with the failure output from Phase 5 (skip re-running the suite):
- Diagnose each failure
- Fix source code (not test assertions)
- Iterate until all tests pass
- If uncertain about intended behavior or what a correct fix looks like, ask the user before guessing

Record: fixes applied.

### Phase 7: Test Coverage Review + Regression Tests

Run `/test-coverage-review` on uncommitted changes. This identifies new or modified code lacking test coverage and creates the missing tests.

**Additionally, create a regression test for every finding fixed in Phases 2-4** (every severity), except pure style/naming nits where a test adds no behavioral value. For each fixed finding:
1. Write a test that specifically reproduces the bug scenario
2. The test must verify the correct behavior (pass with the fix, would fail without it)
3. Choose the appropriate test type:
   - **Unit test** — for logic bugs, incorrect calculations, wrong return values
   - **Integration/API test** — for endpoint bugs, query issues, missing headers
   - **E2E test** — for rendering bugs, UI regressions, page-level failures
4. Name regression tests descriptively: `test_<what_broke>_regression` or `"<what_broke> regression"`

If the `/review` phase already created regression tests inline, verify they exist and are sufficient. If not, create them now.

If new tests are created, run the full suite again to verify they pass and don't cause regressions.

Record: tests created, coverage gaps filled, regression tests for N findings.

### Phase 8: Audits (fix, don't just flag)

Run these checks and **fix** what they surface — do not merely flag.

**Skipped test audit:**
Search changed test files for skip/focus patterns:
- `.skip`, `.only`, `xit(`, `xdescribe(`, `xtest(`, `@skip`, `pending(`

For each one found: un-skip it and make it pass (fix the code or the test). The only exception is a test skipped for a documented, legitimate reason (e.g. an `it.skip` with an inline comment explaining a known external blocker) — leave those and record why. Never leave an undocumented skip or any `.only`.

**Secret scan:**
Check the diff for potential secrets in added lines:
- API keys: `sk-`, `pk_`, `api_key`, `AKIA`, `aws_secret`
- Credentials: `password`, `secret`, `token`, `credential`
- URLs with embedded creds
- `.env` file contents being committed

If secrets detected: **BLOCK.** Do not continue. Warn the user. (Secrets are the one hard stop — never auto-"fix" by committing around them.)

**Coverage check** (if a coverage script exists):
```bash
npx jest --coverage --findRelatedTests <changed-files> --coverageReporters=text-summary
```
If coverage dropped on changed files, **add the missing tests to restore it.** Do not leave a coverage regression as a standing warning.

### Phase 9: Final Review (conditional)

**Only if changes were made in Phases 1-8** (fixes applied by review, lint, fix-tests, test-coverage-review, or audits):

Run `/review` one final time on the updated diff to verify fixes didn't introduce new issues. Fix anything it surfaces (all severities), then re-run until clean.

If no changes were made (everything passed clean on first try), skip this phase.

### Phase 10: Summarize Changes

Run `/summarize-changes` to categorize all uncommitted changes and give the user a clear picture of what they're about to commit.

## Enforcement

- **Fix every finding at every severity — P0, P1, P2, P3, CRITICAL→LOW, BLOCK/WARN — plus every lint warning and every coverage regression. "Clean" means ZERO open issues, warnings included. There is no "defer for later," no "P2 is optional," no "warning, won't block."**
- Any phase failure = overall failure.
- The ONLY acceptable reasons to not fix a finding: (a) it is a verified false positive — state which finding and why it's not real; or (b) the fix requires a product/threat-model/scope decision only the user can make — surface it explicitly and ask. Neither is a silent skip.
- No deferring issues. If you see it, you own it — fix it now.
- Secrets detected = hard block. Do not proceed.
- Do not dismiss test failures as flaky. Investigate and fix.
- Never silence a warning to make it "pass" (no inline lint/type disables, no un-restored console mocks, no skipping suites).

## Output

```markdown
## Full Review Report

### Phase Results
- Simplify: PASS / REFACTORED N files
- Code review: PASS (N findings fixed across M iterations)
- Security review: SECURE (N findings fixed)
- Overcautious check: CLEAN (N findings fixed)
- Quality gate: PASS (lint: 0 errors/0 warnings, types clean, all tests green)
- Test fixes: N/A / FIXED N failures
- Test coverage: PASS / CREATED N tests (N regression tests for findings)
- Audits: CLEAN (N skips resolved, coverage restored) / BLOCKED (secret)

### Fixed (everything that was found)
- [x] Simplified N files
- [x] Fixed N review findings (P0–P3) + regression tests
- [x] Fixed N security findings (CRITICAL–LOW)
- [x] Fixed N overcautious findings (BLOCK/WARN)
- [x] Fixed N lint warnings/errors, N type errors
- [x] Fixed N test failures
- [x] Created N missing/regression tests; restored coverage

### Needs your decision (could not fix without input)
- [ ] <finding> — why it needs a product/threat-model/scope decision
- [ ] <finding> — flagged as a likely false positive; confirm before dismissing

### Blocked
- [ ] Possible secret in `file.ts:12`

### Changes Summary
[Output from /summarize-changes]

### Final Verdict: PASS / NEEDS INPUT / FAIL
```

**PASS** = ZERO open findings at any severity (P0–P3, CRITICAL–LOW, BLOCK/WARN), zero lint warnings, zero coverage regressions, all tests green. A clean run leaves nothing for "later."
**NEEDS INPUT** = everything else is fixed, but ≥1 finding is surfaced for a user decision or as a flagged false positive.
**FAIL** = a blocker remains (e.g. secret) or a finding was left unaddressed without being surfaced.

## Rules

- **Compose, don't duplicate.** Delegate to `/simplify`, `/review`, `/security-review`, `/overcautious-check`, `/run-quality-gate`, `/fix-tests`, `/test-coverage-review`, and `/summarize-changes`. Don't reimplement their logic.
- **Fix everything.** Every severity, every warning. The whole point of this command is to leave nothing open.
- **Never modify test assertions** to make tests pass.
- **Never commit if secrets are detected.**
- **Never silence to pass.** No inline lint/type disables, no skipped suites, no swallowed errors.
- **Stage auto-fix changes** so the user sees them in the diff.
- **Report everything.** Show what was fixed, what (if anything) needs the user's decision, and the final verdict.
- **Skip the final review** if nothing was changed — don't waste time re-reviewing clean code.
