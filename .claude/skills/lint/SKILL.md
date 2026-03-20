---
name: lint
description: "Run formatting, linting, and type checking. Auto-detects project languages (Python, JS/TS, Bash). Fixes auto-fixable issues and stages changes."
argument-hint: "[scope] [--fix]"
disable-model-invocation: true
---

# Lint

Auto-detects project languages and runs the appropriate formatting, linting, and type checking tools.

## Usage

```text
/lint
/lint --fix
/lint backend
/lint frontend
```

## Behavior

### 1. Detect Changed Files

```bash
git diff --name-only HEAD
```

If no argument provided, scope to changed files only. If `backend` or `frontend` specified, scope to that workspace.

### 2. Detect Project Languages

Check for these files in the project root (or relevant subdirectory):

| Indicator | Language | Tools |
|-----------|----------|-------|
| `pyproject.toml`, `setup.py`, `setup.cfg`, `*.py` in diff | Python | ruff, pyright |
| `package.json`, `tsconfig.json`, `*.ts`/`*.tsx`/`*.js`/`*.jsx` in diff | JS/TS | prettier, eslint, tsc |
| `*.sh` in diff | Bash | shellcheck |

Run only the tools that apply. If a tool isn't installed, ask the user if they want to install it via AskUserQuestion.

### 3. Python

**Linting (Ruff):**

```bash
# Check only
ruff check <changed-py-files>

# If --fix passed
ruff check --fix <changed-py-files>
```

**Formatting (Ruff):**

```bash
# Check only
ruff format --check <changed-py-files>

# If --fix passed
ruff format <changed-py-files>
```

If the project uses `uv`, prefix with `uv run` (check for `uv.lock` or project CLAUDE.md instructions).

Stage any fixes:
```bash
git add <fixed-files>
```

**Type checking (Pyright):**

```bash
pyright <changed-py-files>
```

Or `uv run pyright` if the project uses uv. Report type errors.

### 4. JavaScript / TypeScript

**Formatting (Prettier):**

```bash
npx prettier --check <changed-js-ts-files>
```

If `--fix`:
```bash
npx prettier --write <changed-js-ts-files>
```

Stage any fixes.

**Linting (ESLint):**

```bash
npx eslint <changed-js-ts-files>
```

If lint errors, attempt auto-fix:
```bash
npx eslint --fix <changed-js-ts-files>
```

Stage any fixes. Only lint files in the diff.

**Type checking (TypeScript):**

```bash
npx tsc --noEmit --pretty 2>&1
```

Report type errors.

### 5. Bash

**Linting (shellcheck):**

```bash
shellcheck <changed-sh-files>
```

Report issues. shellcheck has no auto-fix mode -- report findings for manual review.

## Output

```markdown
## Lint Results

### Python
- Ruff: PASS / FIXED N files / FAIL (N remaining)
- Pyright: PASS / FAIL (N errors in changed files)

### JavaScript / TypeScript
- Prettier: PASS / FIXED N files / FAIL
- ESLint: PASS / FIXED N errors / FAIL (N remaining)
- TypeScript: PASS / FAIL (N errors in changed files)

### Bash
- shellcheck: PASS / FAIL (N warnings)

- Files staged: N
- Verdict: PASS / FAIL
```

Only include sections for detected languages.

## Rules

- Only lint and check files in the diff (unless `all` scope specified).
- Stage auto-fix changes so the user sees them.
- If type errors exist in changed files, fix them.
- Report everything -- even if all checks pass, show the summary.
- If a tool isn't installed, ask the user if they want to install it via AskUserQuestion.
