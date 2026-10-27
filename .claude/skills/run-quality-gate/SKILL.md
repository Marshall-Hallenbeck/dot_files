---
name: run-quality-gate
description: "Run the project's applicable lint, type, unit, and integration checks within available resource limits."
disable-model-invocation: false
---

# Run Quality Gate

Use `/run-quality-gate` for full validation of the requested work.
Read [runner selection](../run-tests/references/runner-selection.md) first.

Use the project's documented quality-gate wrapper when it provides the requested
checks. Otherwise, select applicable checks from the project's configuration.
Do not assume a Python backend or a `frontend/` directory.

Run independent checks in parallel within available process and agent limits.
Use batches or sequential execution when needed. If subagents are unavailable,
run the same checks directly. Do not require a fixed number of agents.

Complete file-changing fixes before checks that consume those files.
Do not stage changes as part of validation.

Resolve failures within the authorized scope. Do not hide warnings, omit failing
suites, or change assertions solely to pass. Report external blockers or required
scope decisions directly. Re-run affected checks after a fix.

Report exact commands, workspaces, and results. Distinguish NOT APPLICABLE from
PASS. The final result fails if a required check fails or remains unrun.
