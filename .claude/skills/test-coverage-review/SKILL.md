---
name: test-coverage-review
description: "Review uncommitted changes for missing test coverage, then create the missing tests. Use after implementation and before commit."
disable-model-invocation: true
---

# Test Coverage Review

Examines uncommitted changes to identify new or modified code that lacks test coverage, then creates the missing tests. Covers unit, integration, and E2E test gaps.

## Usage

```
/test-coverage-review
/test-coverage-review src/components/   (scope to specific paths)
```

## Behavior

### 1. Gather Changes

```bash
git diff HEAD --name-only
git diff HEAD --stat
```

If arguments were provided, scope to those paths. If no uncommitted changes, say so and stop.

### 2. Identify Testable Code

Read each changed file and identify NEW or MODIFIED:

- **Functions/methods** — exported or public functions with meaningful logic
- **Components** — React/Vue/Svelte components (new files or significantly changed)
- **API routes/handlers** — new endpoints, middleware, route handlers
- **Classes** — new classes or classes with new methods
- **Database queries/models** — new ORM models, migrations, query functions
- **Hooks/utilities** — custom React hooks, utility functions
- **CLI commands** — new or modified Typer/Click commands
- **Tool runners/analyzers** — recon wrappers, vulnerability analyzers, exploit modules
- **Async services** — workers, schedulers, background tasks, WebSocket handlers
- **Serializers/parsers** — output parsing, data transformation, format conversion

Skip: type definitions, interfaces, constants, config files, documentation, CSS/styles, simple re-exports.

### 3. Check Existing Coverage

For each testable item identified, search for existing tests:

- Find test files that import the changed module (search `*.test.*`, `*.spec.*`, `test_*`)
- Find test files by naming convention matching the source file
- Read matching test files and check if the specific function/component/route is tested

### 4. Classify Gaps

For each untested item, classify the type of test needed:

| Code Type | Required Tests |
|-----------|---------------|
| Pure function/utility | Unit tests: happy path, error paths, edge cases |
| React/UI component | Render test + interaction tests (clicks, forms, keyboard) + conditional rendering |
| API route/handler | Smoke test (200 response) + request/response validation + error responses |
| Database query/model | Integration test with test database or realistic mock |
| Custom React hook | Unit test with renderHook: state changes, effects, cleanup |
| CLI command | Invocation test (help output, argument parsing, expected side effects) |
| Tool runner/analyzer | Unit test: output parsing, finding generation, edge cases (empty output, errors) |
| FastAPI route | Pytest with TestClient: status codes, response schema, query param handling, error responses |
| Async worker/service | Pytest-asyncio: task execution, error propagation, state transitions |
| Bug fix | Regression test that fails without the fix |
| Multi-step user workflow | E2E test covering the full flow |
| New page/route | E2E smoke test (page loads, heading visible, key data renders) |

### 5. Plan Implementation Order

When there are 3+ gaps, plan before writing:

1. **Dependency order** — write tests for foundational modules first (utilities, models, services) before code that imports them. This avoids duplicating mock/fixture work.
2. **Group by test file** — if multiple gaps land in the same test file, write them together.
3. **Complexity order within groups** — start with simple pure functions, then stateful logic, then integration/E2E.

For 1-2 gaps, skip this step and write directly.

### 6. Create Missing Tests

For each gap (in the order determined by step 5):

1. Read 1-2 existing test files in the project to learn conventions (import style, test organization, mocking patterns, naming)
2. Write tests following those conventions exactly
3. Run each new test file immediately to verify it passes
4. If a test fails, fix the test (not the source code — this skill creates tests, not fixes)
5. Lint the test file

### 7. Run Full Suite

After all new tests are written, run **both** unit and E2E test suites to confirm no regressions:

**Unit tests:**
- Python: `uv run pytest tests/ -q`
- Frontend: `cd frontend && npx jest --no-coverage`

**E2E tests (if services are running):**
- Frontend: `cd frontend && npx playwright test --grep-invert @mutation`

If E2E tests cannot run (services down), say so explicitly — do not silently skip them.

If new tests caused regressions, fix them.

### 8. Report

```markdown
## Test Coverage Review

### Changes Analyzed
N files with uncommitted changes reviewed.

### Coverage Gaps Found & Fixed

1. **`src/components/Dashboard.tsx`** — NEW component, no tests
   - Created: `src/components/__tests__/Dashboard.test.tsx`
   - Tests: render, user click on tab, conditional empty state (3 tests)

2. **`src/api/tournaments.ts:createTournament`** — NEW function, no tests
   - Created: `tests/api/test_tournaments.py`
   - Tests: happy path, validation error, duplicate name (3 tests)

3. **`src/hooks/useAuth.ts`** — MODIFIED hook, new refresh logic untested
   - Updated: `src/hooks/__tests__/useAuth.test.ts`
   - Tests: token refresh on expiry, refresh failure (2 tests added)

### Already Covered
- `src/utils/format.ts:formatDate` — tested in `utils/format.test.ts`
- `src/api/tournaments.ts:listTournaments` — tested in `tests/api/test_tournaments.py`

### Test Results: ALL PASSING (N/N)
```

## Rules

- **Follow existing conventions.** Read existing tests first. Match their style exactly.
- **Don't fix source code.** If a test reveals a bug, note it in the report but write the test to match current behavior. Separately flag the bug.
- **Create tests, don't just report gaps.** The output of this skill is test files, not a todo list.
- **Both unit AND integration/E2E.** Don't stop at unit tests. If the change involves UI workflows, create interaction/E2E tests. If it involves API endpoints, create integration tests. For new frontend pages, always create a Playwright E2E smoke test in `e2e/` alongside Jest unit tests.
- **Regression tests for bug fixes.** If the diff contains a bug fix (check commit messages, PR descriptions, or code comments), verify a regression test exists. If not, create one.
- **Run everything.** All new tests must pass. Run both Jest (`npx jest`) AND Playwright (`npx playwright test --grep-invert @mutation`) for frontend changes. Run pytest for backend changes. Never run only one test runner when multiple apply.
