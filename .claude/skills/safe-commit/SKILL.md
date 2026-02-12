---
name: safe-commit
description: "Commit changes only after tests pass. Use when the user explicitly requests a commit."
---

# Safe Commit

Commits changes only after verifying tests pass. Enforces a "no broken commits" policy.

## Usage

```
/safe-commit [message]
```

## Behavior

### 1. Check for Uncommitted Changes

```bash
git status --porcelain
```

If no changes, abort with message.

### 2. Select Relevant Files

If the user requested a commit for a specific feature/bug, include only relevant changes. If scope is unclear, ask the user before staging.

### 3. Auto-Detect and Run Tests

Detect the project's test runner and run relevant tests:

```bash
# Check what changed
git diff --name-only HEAD

# Auto-detect test runner based on project files
# Node.js (package.json): npm test or npm run jest
# Python (pyproject.toml/setup.py): pytest or python -m pytest
# Rust (Cargo.toml): cargo test
# Go (go.mod): go test ./...
# Makefile: make test
```

For monorepos, only run tests for the changed area:
- If backend files changed → run backend tests
- If frontend files changed → run frontend tests
- If both changed → run both

### 4. Run Linting/Type Checks (if available)

```bash
# Auto-detect based on project config
# Node.js: npm run typecheck && npm run lint (if scripts exist)
# Python: mypy, ruff, or flake8 (if configured)
# Rust: cargo clippy
```

### 5. Decision Flow

```
Check changes → Identify test runner → Run tests
                                          │
                                 ┌───────┴───────┐
                                 ▼               ▼
                            PASSING          FAILING
                                │               │
                                ▼               ▼
                            COMMIT       ABORT & REPORT
```

### Test Pass → Commit

```bash
git add <relevant-files>
git commit -m "<commit message>"
```

### Test Fail → Abort

```
COMMIT ABORTED - Tests are failing

Failing tests:
- [list failures]

Please fix the failing tests before committing.
```

### Exceptions

Allow commits WITHOUT full test suite for:
- Documentation-only changes (`*.md`, `docs/`)
- Config file changes (`.env*`, `*.config.*`) — but warn user
- Workflow/tooling changes (`.claude/**`, `.github/**`)
- Test file changes only — run just those specific tests
