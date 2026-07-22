# Parallelism & Agent Orchestration

## When to Use Agent Teams

Agent teams put each teammate in a tmux split pane (`teammateMode: auto`) so the user can watch, redirect, and steer them mid-flight. This is valuable when the user would want to course-correct early — not for every multi-file task.

Use agent teams when:
- **Investigation/debugging** with multiple hypotheses to explore in parallel
- **Ambiguous or exploratory tasks** where early findings change the direction
- **Multi-perspective review** (security + correctness + performance) where the user may want to deepen one angle
- The user explicitly asks for parallel, team-based, or `/run-team` work

Do NOT default to agent teams for:
- **Tasks where the user won't be watching** — teams only help if the user is steering. Unattended teams are just expensive subagents.

Try to cap at 4-6 teammates for most tasks. Beyond 6, tmux panes get hard to read and you can only focus on one at a time.

## When to Use Subagents (Agent Tool)

Subagents are invisible helpers that return a result. Use them for:
- Focused lookups ("find where X is defined", "grep for Y")
- Tasks that take <30 seconds and whose result gates the next step
- Research that feeds directly into the main conversation's next action
- Well-defined implementation tracks that don't need steering

Set `run_in_background: true` when the result doesn't gate the next step, so the main conversation continues. Only block (foreground) when you need the result immediately.

## When to Use Workflows

Use the Workflow tool for:
- Structured sweeps across many files with the same pattern (migrations, audits)
- Tasks where the fan-out structure is known upfront and steering isn't needed
- Exhaustive coverage with adversarial verification

## Teammate Spawn Guidelines

When spawning teammates:
- Give each a short, descriptive name (e.g., "db-hypothesis", "network-check", "security-review")
- Assign non-overlapping file ownership — two teammates must not edit the same file
- Include full context in the spawn prompt (teammates don't inherit conversation history)
- Let teammates self-claim tasks from the shared task list rather than micromanaging
