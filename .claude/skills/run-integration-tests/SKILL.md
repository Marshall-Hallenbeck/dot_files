---
name: run-integration-tests
description: "Run configured integration or browser suites with the required test services."
argument-hint: "[scope]"
disable-model-invocation: true
---

# Run Integration Tests

Use `/run-integration-tests [workspace, e2e, test path, or all]`.
Read [runner selection](../run-tests/references/runner-selection.md) first.

Inspect integration markers, directories, scripts, and service requirements.
Select one configured command per suite. Do not run both a marker and directory
command for the same tests. Do not try several package scripts.

For browser tests, use the documented test environment and service startup.
Keep the selected restricted or full suite fixed. Do not broaden it after a
failure or after a successful restricted run.

Report environment failures with the exact missing service, tool, or credential
name. Do not print credential values. Report NOT APPLICABLE only when the scope
has no integration suite. An empty selected collection is a failure.
