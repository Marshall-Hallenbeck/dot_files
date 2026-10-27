---
name: run-unit-tests
description: "Run the project's unit suites with its configured runners and wrappers."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Unit Tests

Use `/run-unit-tests [workspace, test path, or all]`.
Read [runner selection](../run-tests/references/runner-selection.md) first.

Identify unit suites from project configuration and existing tests. Select one
command per suite. For JavaScript and TypeScript, inspect package scripts and use
the one that matches the scope. Do not execute several candidate script names.

Honor configured test paths, exclusions, package manager, and required setup.
Report observed pass/fail counts where the runner supplies them. Report a missing
selected runner or an empty selected suite as a failure. If the scope has no unit
suite, report NOT APPLICABLE with the evidence.
