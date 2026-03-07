---
name: write-tests
description: "Write comprehensive unit tests for a module or function. Handles test runner detection, mock conventions, and iterates until all tests pass."
argument-hint: "<module-or-file>"
disable-model-invocation: true
---

# Write Tests

Write comprehensive unit tests for a given module or file. Detects the test runner, follows existing test conventions, and iterates until all tests pass.

## Usage

```
/write-tests src/services/auth.py
/write-tests src/components/Dashboard.tsx
/write-tests src/utils/scoring.ts
```

## Behavior

### 1. Detect Test Runner and Conventions

Auto-detect from project files:
- `jest.config.*` or `vitest.config.*` → Jest/Vitest
- `pyproject.toml` / `pytest.ini` / `conftest.py` → pytest
- `Cargo.toml` → cargo test
- `go.mod` → go test

Then read 1-2 existing test files in the project to learn conventions:
- Import style and test organization
- Fixture/helper patterns (conftest.py, test utils, factories)
- Mocking approach (jest.mock, unittest.mock, testify)
- Naming conventions (test_*, *_test, *.spec.*)

### 2. Read the Target Module

Read the module specified by the user. Identify:
- All public functions, classes, and methods
- Input types, return types, and side effects
- Dependencies that will need mocking
- Edge cases (null/empty inputs, error paths, boundary values)

### 3. Write the Test File

Create the test file following the project's existing conventions for path and naming:
- Python: `tests/test_<module>.py` or mirror the source path under `tests/`
- JS/TS: `<module>.test.ts` or `__tests__/<module>.test.ts`

#### Mock Conventions

**Python (unittest.mock):**
- Always set `mock.__name__ = 'MockClassName'` and `mock.__module__ = 'test'` on MagicMock objects used as class or function replacements
- Patch at the import location, not the definition location
- Import helpers directly in the test file — do not rely on conftest.py auto-imports

**JavaScript/TypeScript:**
- Use `jest.mock()` / `vi.mock()` at the top of the file
- Mock external modules, not internal functions
- Use `jest.spyOn` for partial mocks

#### Test Coverage Targets

- Happy path for every public function/method
- Error/exception paths
- Boundary values and edge cases (empty, null, zero, max)
- Any branching logic (if/else, match/switch)

### 4. Run the Tests

```bash
# Run only the new test file
pytest tests/test_<module>.py -v 2>&1
# or
npx jest <test-file> --verbose --no-coverage 2>&1
```

If any tests fail:
1. Read the failure output
2. Diagnose whether the test assertion is wrong or the test setup is wrong
3. Fix the test (not the source code — this skill writes tests, not fixes)
4. Re-run and iterate until all pass

### 5. Lint the Test File

```bash
# Python
ruff check --fix <test-file> && ruff format <test-file>
# JS/TS
npx eslint --fix <test-file>
```

Fix any lint errors before reporting.

### 6. Run Full Suite

Run the entire test suite to confirm the new tests don't break anything:

```bash
pytest -v 2>&1
# or
npx jest --verbose --no-coverage 2>&1
```

If new tests caused regressions, fix them.

### 7. Report

```markdown
## Tests Written

**Module:** `<module-path>`
**Test file:** `<test-file-path>`
**Tests:** N passed, 0 failed

### Coverage
- `function_a` — happy path, error path, edge cases (3 tests)
- `ClassB.method_c` — happy path, null input, boundary (3 tests)
- `ClassB.method_d` — happy path, exception (2 tests)

### Full Suite: ALL PASSING (X/X)
```

## Important Rules

- **Follow existing conventions.** Read existing tests first. Match their style exactly.
- **Set dunder attributes on mocks.** Python MagicMock objects used as class/function replacements must have `__name__` and `__module__` set.
- **Import directly.** Don't rely on conftest auto-imports — import what you need in the test file.
- **Don't fix source code.** If a test reveals a bug, note it in the report but write the test to match current behavior or mark it with a clear comment. Use `/fix-tests` for source fixes.
- **Iterate until green.** Keep running and fixing until all tests pass. No giving up.
- **Lint before reporting.** The test file must be clean.
