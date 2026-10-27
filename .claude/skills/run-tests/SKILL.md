---
name: run-tests
description: "Select and run the project's unit, integration, or full validation workflow."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Tests

Read [runner selection](references/runner-selection.md) before dispatch.

| Scope | Workflow |
|-------|----------|
| `unit` | `/run-unit-tests` |
| `integration` | `/run-integration-tests` |
| `all` | `/run-quality-gate` |
| `backend` | Relevant backend unit and integration suites |
| `frontend` | Relevant frontend unit suites |
| `e2e` | `/run-integration-tests e2e` |
| No argument | Select affected checks from the diff and project instructions |

Inspect shell changes for project regression tests, including hooks and installer
tests. Inspect configuration and script changes for their callers. Use actual
workspace definitions rather than assuming directory names.

Pass the selected command list and any existing results to child workflows.
Execute each distinct suite once. A change across several languages does not
alone require all tests in the repository.
