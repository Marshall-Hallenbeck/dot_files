---
name: run-team
description: "Spawn an agent team in tmux split panes for parallel exploration. Best for investigation, debugging, ambiguous tasks, and multi-angle review where you want to steer work in real-time."
argument-hint: "<task description>"
---

# Run as Agent Team

Spawn an agent team with teammates in tmux split panes so the user can watch and steer them in real-time. Best for exploration, investigation, and ambiguous work — not for mechanical implementation with a clear plan.

## Usage

```
/run-team investigate why the API is slow — check DB queries, caching, and network
/run-team debug the auth failure — check token validation, middleware, and session store
/run-team review this PR from security, correctness, and performance angles
/run-team explore approaches for the new notification system
```

## When NOT to Use This

If the task is well-defined and mechanical (clear files, clear changes, no ambiguity), suggest running it directly or with subagents instead. Say something like:

> "This task has a clear plan — teams add coordination overhead without steering benefit here. Want me to just implement it directly, or do you specifically want parallel visibility?"

Only push back once. If the user still wants a team, proceed.

## Behavior

### 1. Analyze the Request

Read the user's task description (passed as arguments). Determine:
- What distinct angles, hypotheses, or concerns exist
- Which files/areas each angle will touch
- Whether any angles depend on another's output

If no arguments were provided, ask the user what they want the team to work on.

### 2. Propose Team Composition

Present the team plan before spawning:

```markdown
## Team Plan

**Task:** <one-line summary>

| Teammate | Angle | Area | Depends On |
|----------|-------|------|------------|
| db-check | Database query performance | src/db/, slow query logs | — |
| cache    | Cache hit rates and config | src/cache/, redis config | — |
| network  | Network latency and timeouts | src/api/, infra config | — |
```

Ask for confirmation before proceeding. If the user says to just go, spawn immediately.

### 3. Spawn Teammates

Spawn each teammate with a detailed prompt that includes:
- Their specific angle and what to investigate/produce
- Which files they own (non-overlapping with other teammates)
- What "done" looks like for their track
- Any dependencies on other teammates' work (use task dependencies for ordering)

Create shared tasks via TaskCreate so teammates can coordinate through the task list.

### 4. Hand Off to the User

After spawning, tell the user:
- Which tmux panes correspond to which teammates
- They can click into any pane to steer a teammate directly
- They can press Escape on a selected teammate to interrupt it

Then monitor progress via the task list and synthesize results when teammates finish.

## Important Rules

- **2-3 teammates max.** Beyond 3, panes get small and you can't effectively watch them all. Only go to 4-5 if the user explicitly asks.
- **No file overlap.** Two teammates must never own the same file. If overlap is unavoidable, put those tasks in the same teammate's scope.
- **Rich spawn prompts.** Teammates don't inherit this conversation's history. Include all necessary context.
- **Dependencies via tasks.** If teammate B needs teammate A's output, create tasks with `blockedBy` so B waits.
- **Let the user steer.** After spawning, don't micromanage teammates. The whole point is that the user interacts with them directly.
- **Push back on mechanical tasks.** If the request is well-defined implementation work, suggest direct execution instead — but defer to the user if they insist.
