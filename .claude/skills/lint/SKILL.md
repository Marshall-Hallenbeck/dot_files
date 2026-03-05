---
name: lint
description: "Run formatting, linting, and type checking. Fixes auto-fixable issues and stages changes."
---

# Lint

Runs prettier, ESLint, and TypeScript type checking on changed files or all files.

## Usage

```text
/lint
/lint backend
/lint frontend
/lint --fix
```

## Behavior

### 1. Detect Changed Files

```bash
git diff --name-only HEAD
```

If no argument provided, scope to changed files only. If `backend` or `frontend` specified, scope to that workspace.

### 2. Formatting (Prettier)

Run prettier check first, then fix:

```bash
# Backend (run from backend/)
npx prettier --check <changed-backend-files>

# Frontend (run from frontend/)
npx prettier --check <changed-frontend-files>
```

If `--fix` is passed (or when called from a composite skill that expects fixes):

```bash
npx prettier --write <changed-files>
```

Stage any formatting fixes:
```bash
git add <fixed-files>
```

### 3. Linting (ESLint)

```bash
# Backend (run from backend/)
npx eslint <changed-backend-files>

# Frontend (run from frontend/)
npx eslint <changed-frontend-files>
```

If lint errors exist in changed files, attempt auto-fix (max 3 attempts):

```bash
npx eslint --fix <changed-files>
```

Stage any lint fixes. Only lint files in the diff — ignore errors in files you didn't change.

### 4. Type Checking

```bash
# Backend (if tsconfig.json exists)
cd backend && npx tsc --noEmit --pretty 2>&1

# Frontend (if tsconfig.json exists)
cd frontend && npx tsc --noEmit --pretty 2>&1
```

Report type errors in changed files. Ignore errors in files you didn't change.

## Output

```markdown
## Lint Results

- Prettier: PASS / FIXED N files / FAIL
- ESLint: PASS / FIXED N errors / FAIL (N remaining)
- TypeScript: PASS / FAIL (N errors in changed files)
- Files staged: N
- Verdict: PASS / FAIL
```

## Rules

- Only lint and check files in the diff (unless `all` scope specified).
- Stage auto-fix changes so the user sees them.
- If type errors exist in changed files, fix them (max 3 attempts). Ignore errors in files you didn't change.
- Report everything — even if all checks pass, show the summary.
