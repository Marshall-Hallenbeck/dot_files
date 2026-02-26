---
name: pre-commit-validate
description: "Full pre-commit pipeline: review, fix tests, audit, then report. Composes /review and /fix-tests with formatting, secret scanning, and coverage checks."
---

# Pre-Commit Validate

Full-stack validation pipeline that composes other skills and runs audits. Use before committing to catch everything.

## Usage

```
/pre-commit-validate
```

## Pipeline

### Phase 1: Code Review (iterative)

Run `/review` on uncommitted changes. If it reports P0 or P1 findings:
1. Fix each finding
2. Run `/review` again on the updated diff
3. Repeat until verdict is PASS or max 3 iterations

If findings persist after 3 rounds, report them and continue to Phase 2.

### Phase 2: Formatting

Run the project's formatter on changed files only:

```bash
# Detect changed files
git diff --name-only HEAD

# Run formatter (detect from project config)
npx prettier --write <changed-files>
# or: npx eslint --fix <changed-files>
```

Stage any formatting fixes automatically.

### Phase 3: Type Checking

If `tsconfig.json` exists:

```bash
npx tsc --noEmit --pretty 2>&1
```

If type errors exist in changed files, fix them (max 3 attempts). Ignore errors in files you didn't change.

### Phase 4: Tests

Run `/fix-tests` to execute the test suite and auto-fix any failures. This handles:
- Running the full suite
- Diagnosing each failure
- Fixing source code (not test assertions)
- Re-running until green or max iterations reached

### Phase 5: Audits

Run these checks in sequence. These are read-only — flag issues but don't auto-fix.

**Skipped test audit:**
Search changed test files and related test files for skip patterns:
- `.skip`, `.only`, `xit(`, `xdescribe(`, `xtest(`, `@skip`, `pending(`

Flag any found with file paths and line numbers.

**Secret scan:**
Check the diff for potential secrets in added lines:
- API keys: `sk-`, `pk_`, `api_key`, `AKIA`, `aws_secret`
- Credentials: `password`, `secret`, `token`, `credential`
- URLs with embedded creds: `://.*:.*@`
- `.env` file contents being committed

If secrets detected: **BLOCK.** Do not continue. Warn the user.

**Coverage check** (if coverage script exists in `package.json`):
```bash
npx jest --coverage --findRelatedTests <changed-files> --coverageReporters=text-summary
```
Warn if coverage dropped on changed files. Do not block.

### Phase 6: Summarize Changes

Run `/summarize-changes` to categorize all uncommitted changes by type (feat, fix, refactor, test, docs, chore) and generate a structured summary. This gives the user a clear picture of what they're about to commit.

### Phase 7: Report

```markdown
## Pre-Commit Validation

### Review
- /review ran N iteration(s) — verdict: PASS/NEEDS FIXES
- [List any remaining findings]

### Auto-Fixed
- [x] Formatted N files
- [x] Fixed N type errors
- [x] Fixed N test failures

### Warnings
- [ ] Coverage dropped N% in `file.ts`
- [ ] Skipped test in `file.test.ts:45`

### Blocked
- [ ] Possible secret in `file.ts:12`

### Changes Summary
[Output from /summarize-changes — categorized list of what changed]

### Status: READY / NOT READY
```

**READY** = no blockers, no P0/P1 findings remaining.
**NOT READY** = has blockers or unresolved critical findings.

## Rules

- **Compose, don't duplicate.** Use `/review` for code review and `/fix-tests` for test fixing. Don't reimplement their logic.
- **Never modify test assertions** to make tests pass.
- **Never commit if secrets are detected.**
- **Stage auto-fix changes** so the user sees them in the diff.
- **Report everything.** Even if all checks pass, show the summary so the user knows what was validated.
