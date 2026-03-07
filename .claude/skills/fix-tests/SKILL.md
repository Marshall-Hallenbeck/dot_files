---
name: fix-tests
description: "Autonomous test-fix pipeline. Runs full suite, diagnoses each failure, fixes source code, and iterates until all tests pass. Asks the user when uncertain about intended behavior."
---

# Fix Tests

Autonomous test-driven debugging pipeline. Runs the full test suite, diagnoses every failure, fixes source code, and iterates until green. If uncertain about intended behavior or what a correct fix looks like, asks the user before guessing.

## Usage

```
/fix-tests [optional: specific test file or pattern]
```

If called from a composite skill (e.g., `/full-review`) that already has test failure output, accept that output and skip Step 1 — go directly to Step 2 (Parse Failures).

## Behavior

### 0. Detect Test Runner

Auto-detect from project files:
- `jest.config.*` or `package.json` scripts → Jest
- `vitest.config.*` → Vitest
- `pyproject.toml` / `pytest.ini` → pytest
- `Cargo.toml` → cargo test
- `go.mod` → go test
- `Makefile` with test target → make test

### 1. Run Full Test Suite

Run the complete suite (or scoped to the pattern if provided) and capture all output:

```bash
# Capture full output including failure details
npx jest --verbose --no-coverage 2>&1
# or equivalent for detected runner
```

If all tests pass, report success and stop.

### 2. Parse Failures

Extract from the output:
- Failing test name and file path
- Error message and stack trace
- Expected vs actual values

Build a list of all distinct failures.

### 3. Fix Each Failure (Sequential)

For each failing test, in order:

#### a) Read the test
Read the failing test file. Understand what behavior it's asserting.

#### b) Read the source code it exercises
Trace from the test to the source — read imports, the function/component under test, and any dependencies.

#### c) Diagnose the root cause
Compare expected vs actual behavior. Determine whether:
- The **source code** has a bug → fix the source
- The **test assertion** is genuinely wrong (e.g., testing removed behavior, wrong expected value from a spec change) → fix the test
- A **dependency or mock** is stale → update it

When uncertain whether a test assertion or the source code is wrong, ask the user before proceeding. If you can clearly justify that the test expectation is incorrect (e.g., outdated spec, explicitly removed feature), change the test with justification. Otherwise, fix the source code.

#### d) Apply the fix
Edit the source code (or test, with justification). Keep the fix minimal — don't refactor surrounding code.

#### e) Re-run that specific test

```bash
npx jest --testPathPattern="<test-file>" --testNamePattern="<test-name>" 2>&1
# or equivalent
```

**If it passes:** Record the fix and move to the next failure.

**If it still fails:** Try a different approach. Keep iterating until the test passes. If you're unsure about the intended behavior or what a correct fix looks like, ask the user with AskUserQuestion before guessing.

### 4. Run Full Suite Again

After fixing all individual failures, run the complete suite:

```bash
npx jest --verbose --no-coverage 2>&1
```

#### If new failures appeared (regression):

1. Identify which fix introduced the regression (compare against the fix log)
2. Revert that specific fix using git:
   ```bash
   git checkout -- <file-that-was-fixed>
   ```
3. Try a different approach to fix the original failure
4. Re-run full suite again

#### If still some failures remain:

Repeat from Step 2 for remaining failures. Keep iterating until all tests pass. If stuck on a failure and unsure about the intended behavior, ask the user.

### 5. Final Report

After the suite is green (or max iterations reached), present:

```markdown
## Test Fix Results

### Suite Status: ALL PASSING (147/147) ✓

### Fixes Applied
1. **`src/utils/scoring.ts:45`** — `calculateTiebreaker` was using `>` instead of `>=` for equal scores
   - Root cause: Off-by-one in comparison operator
   - Test: `scoring.test.ts:78` — "handles tied scores correctly"

2. **`src/components/Bracket.tsx:112`** — Missing null check on `match.opponent2`
   - Root cause: BYE rounds have null opponent, component assumed non-null
   - Test: `Bracket.test.tsx:34` — "renders BYE match"

### Test Assertions Changed (with justification)
1. **`api.test.ts:56`** — Updated expected status from 200 to 201
   - Justification: POST endpoint was changed to return 201 on creation (correct REST semantics)

### Regressions Caught & Reverted
- Reverted change to `scoring.ts:30` — fixed tiebreaker but broke ranking sort. Applied alternative fix at line 52.
```

### 6. Commit (only if ALL tests pass)

If the full suite is green, create a commit:

```bash
git add <all-fixed-files>
git commit -m "fix: resolve N test failures

<for each fix, one line with file:line and root cause>

Fixes applied autonomously via /fix-tests.
Test assertions changed where justified (see details above)."
```

If any tests remain failing, do NOT commit. Present the report and let the user decide.

## Important Rules

- **Ask when uncertain.** If unsure about intended behavior, what a test is meant to verify, or what a correct fix looks like, ask the user.
- **Fix source code by default**, not test assertions. Only change tests with explicit justification.
- **Never dismiss failures** — assume your changes (or the current code state) caused it. Fix every failure you see.
- **Never call a test "flaky"** without investigating the root cause.
- **Revert and retry** if a fix causes regressions — don't pile fixes on top of broken fixes.
- **Keep iterating** until all tests pass. No arbitrary attempt limits.
- **Keep fixes minimal** — don't refactor or "improve" surrounding code.
