---
name: pre-commit-validate
description: "Pre-commit validation pipeline that auto-fixes issues. Run before committing to catch and fix type errors, formatting, test failures, skipped tests, and secrets."
---

# Pre-Commit Validate

Autonomous pre-commit validation pipeline with self-healing. Detects available tooling, runs checks, fixes what it can, and reports what needs human decision.

## Usage

```
/pre-commit-validate
```

## Behavior

### 0. Detect Project Tooling

Before running any checks, detect what's available in the current project. Only run checks for tools that exist. Do NOT install anything.

```bash
git diff --cached --name-only   # staged files
git diff --name-only            # unstaged changes
```

Categorize changed files:
- **TypeScript**: `*.ts`, `*.tsx`
- **Frontend**: `*.tsx`, `*.jsx`, `*.css`, `*.scss`
- **Test files**: `*.test.*`, `*.spec.*`, `__tests__/*`
- **Config/docs**: `*.md`, `*.json`, `*.yml`, `*.env*`

### 1. TypeScript Compilation (if tsconfig.json exists)

Run type checking:

```bash
npx tsc --noEmit --pretty 2>&1
```

**If errors found in changed files:** Read the error, fix the source code, re-run `tsc`. Repeat until clean or you've made 3 attempts. If still failing after 3 attempts, report the remaining errors to the user.

**Ignore** type errors in files you did NOT change.

### 2. Formatting (if prettier/eslint config exists)

Check for a formatter and run it on changed files only:

```bash
# Detect formatter
# prettier: .prettierrc, .prettierrc.*, prettier.config.*
# eslint: .eslintrc.*, eslint.config.*
# biome: biome.json

npx prettier --write <changed-files>
# or
npx eslint --fix <changed-files>
```

Stage any formatting fixes automatically.

### 3. Test Suite (if test runner detected)

Scope tests to changed files. Detect the runner from `package.json` scripts or config files:

```bash
# Jest/Vitest: run tests related to changed files
npx jest --findRelatedTests <changed-source-files> --passWithNoTests
# or
npx vitest run --reporter=verbose <changed-test-files>

# Python: pytest for changed modules
# Go: go test for changed packages
```

**If tests fail:**
1. Read the failing test AND the source code it tests
2. Determine if the failure is in the source code or the test
3. Fix the source code (prefer fixing source over changing test assertions)
4. Re-run the failing tests
5. If still failing after 2 fix attempts, report to the user — do NOT keep guessing

### 4. Skipped Test Audit

Search for skipped tests in changed test files and test files related to changed source:

```bash
# Look for skip patterns in relevant test files
grep -n "\.skip\|\.only\|xit(\|xdescribe(\|xtest(\|@skip\|@pytest.mark.skip\|pending(" <test-files>
```

**If skipped tests found related to changed functionality:**
- Flag them to the user with file paths and line numbers
- Ask whether they should be unskipped or if the skip is intentional

### 5. Secrets & Sensitive Data Scan

Check the staged diff for potential secrets:

```bash
git diff --cached -U0
```

Flag if any of these patterns appear in added lines:
- API keys: `sk-`, `pk_`, `api_key`, `apikey`, `API_KEY`
- Tokens: `token`, `secret`, `password`, `credential`
- AWS: `AKIA`, `aws_secret`
- URLs with credentials: `://.*:.*@`
- `.env` file contents being committed

**If secrets detected:** BLOCK and warn the user. Do NOT auto-fix — the user must decide.

### 6. Coverage Check (if coverage tool available)

Only run if a coverage script exists in `package.json`:

```bash
# Run coverage scoped to changed files
npx jest --coverage --findRelatedTests <changed-files> --coverageReporters=text-summary
```

**If coverage dropped** on changed files, warn the user but do NOT block.

### 7. Frontend Visual Check (if Playwright available AND frontend files changed)

Only if `playwright` is in dependencies AND `.tsx`/`.jsx`/`.css` files changed:

- Take screenshots of pages likely affected by the changes
- Save to `.validation/` directory for user review
- Note: Do NOT run full E2E suite — just capture current state of affected pages

## Output Format

After all checks complete, present a summary:

```markdown
## Pre-Commit Validation Results

### Auto-Fixed
- [x] Fixed 2 TypeScript errors in `src/components/Bracket.tsx`
- [x] Formatted 3 files with Prettier

### Warnings
- [ ] Coverage dropped 3% in `src/utils/scoring.ts` (92% → 89%)
- [ ] 1 skipped test in `scoring.test.ts:45` — `.skip` on `calculates tiebreaker`

### Blocked
- [ ] Possible API key in `src/config.ts:12` — verify before committing

### Clean
- [x] No secrets in diff
- [x] All related tests passing (14/14)
- [x] TypeScript compilation clean
```

### Decision Flow

```
Run all checks → Auto-fix what's possible → Re-verify fixes
                                                │
                                    ┌───────────┴────────────┐
                                    ▼                        ▼
                              ALL CLEAN               ISSUES REMAIN
                                    │                        │
                                    ▼                        ▼
                          "Ready to commit"        Present summary,
                          Suggest /safe-commit     ask user to decide
```

### Important Rules

- **Never skip a check silently.** If a tool isn't available, say so explicitly.
- **Never modify test assertions** to make tests pass — fix the source code.
- **Never commit if secrets are detected** — always block and ask.
- **Stage auto-fix changes** so the user can review them in the diff.
- **Respect the 3-attempt limit** on type errors and 2-attempt limit on test fixes — don't loop forever.
