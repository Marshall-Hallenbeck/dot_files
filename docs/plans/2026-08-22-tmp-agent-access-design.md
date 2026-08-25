# Agent Access to `/tmp` Design

## Goal

Let all managed AI agents create, change, and delete files in `/tmp` without
asking for permission. Keep the current protection for paths outside `/tmp`.

## Design

The canonical shared agent instructions state that `/tmp` is an approved
scratch area. An agent must not ask for permission when an operation changes
only paths in `/tmp`. Ruler and `agent-sync` publish this rule to the generated
Claude and Codex instruction files.

Claude settings allow the file tools to read, write, and edit paths below
`/tmp`. A `PreToolUse` hook handles direct `rm` commands. The hook allows the
command when every delete target is below `/tmp`. It requests permission for
all other targets and for commands that it cannot parse safely. The existing
global `Bash(rm:*)` ask rule is removed because an ask rule has priority over
an allow rule.

Codex keeps `sandbox_mode = "workspace-write"` and
`approval_policy = "on-request"`. The managed Codex configuration adds
`/tmp` to `sandbox_workspace_write.writable_roots`. The `agent-sync` process
applies this setting without changing unrelated Codex-only configuration.

Other agents receive the shared instruction. Their host permission system can
still apply a stronger policy.

## Validation

Regression tests verify these cases:

- Claude file tools can change paths below `/tmp`.
- A direct `rm` command for targets below `/tmp` is allowed.
- A direct `rm` command for a target outside `/tmp` requests permission.
- Codex configuration includes `/tmp` as a writable root.
- Ruler and `agent-sync` outputs contain the shared rule and have no drift.

## Scope

This change does not disable general permission checks. It does not permit an
operation that includes a target outside `/tmp`.
