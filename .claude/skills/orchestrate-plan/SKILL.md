---
name: orchestrate-plan
description: "Decompose a plan into parallel work tracks and execute with subagents. Reads PLAN.md, splits into non-overlapping tracks, spawns agents, and runs integration tests."
---

# Orchestrate Plan

Reads an implementation plan and executes it via parallel subagents, with integration testing and regression tracking.

## Usage

```
/orchestrate-plan [path-to-plan]
```

If no path given, looks for `PLAN.md` in the current directory.

## Behavior

### 1. Read and Parse the Plan

Read the plan file and identify all discrete tasks. For each task, determine:
- Which files it will touch (create, modify, delete)
- What it depends on (must another task finish first?)
- What tests cover it

### 2. Decompose into Work Tracks

Group tasks into independent tracks that can run in parallel. A track is independent if:
- Its files do NOT overlap with any other track's files
- It does not depend on another track's output

If file overlap exists between tasks, they MUST be in the same track (sequential within that track).

Present the decomposition before executing:

```markdown
## Work Tracks

### Track 1: Backend API changes
- Files: src/api/tournaments.ts, src/api/seasons.ts
- Tasks: 1, 3, 5
- Tests: api.test.ts, seasons.test.ts

### Track 2: Frontend components
- Files: src/components/Bracket.tsx, src/components/Leaderboard.tsx
- Tasks: 2, 4
- Tests: Bracket.test.tsx, Leaderboard.test.tsx

### Track 3: Database migration
- Files: migrations/003_add_status.ts
- Tasks: 6
- Tests: migration.test.ts

### Overlap detected: None ✓
```

### 3. Create Task List

Use TaskCreate to create a task for each track, plus an integration task. Set up dependencies:
- Track tasks are independent (no blockedBy)
- Integration task is blockedBy all track tasks

### 4. Spawn Subagents

For each track, spawn a subagent via Task tool with:
- `subagent_type`: "general-purpose"
- `team_name`: current team (if in a team) or create one
- A focused prompt containing ONLY that track's tasks, files, and context
- Explicit instruction to run that track's tests after completing

Each subagent prompt must include:
- The specific tasks from the plan for this track
- The list of files it is allowed to touch
- The test commands to run after completion
- Instruction to mark its task as completed when done

### 5. Monitor Progress

Track completion via TaskList. As subagents complete:
- Verify each track's tests passed (check the subagent output)
- If a track fails, note the failure for integration step

### 6. Integration Testing

Once all tracks complete, run the full test suite:

```bash
npm test 2>&1
# And E2E if available
npx playwright test 2>&1
```

#### If integration failures appear:

1. Identify which track's changes caused the failure by examining:
   - Which files are in the stack trace
   - Which track modified those files
2. Create a targeted fix (do NOT re-run the entire track)
3. Re-run full suite to verify

#### If integration passes:

Proceed to summary.

### 7. Final Summary

```markdown
## Orchestration Results

### Tracks Completed: 3/3

| Track | Status | Files Changed | Tests |
|-------|--------|--------------|-------|
| Backend API | ✓ | 2 files (+45/-12) | 23/23 passing |
| Frontend | ✓ | 2 files (+89/-34) | 15/15 passing |
| Migration | ✓ | 1 file (+28/-0) | 4/4 passing |

### Integration: ALL PASSING (147/147) ✓

### Issues Resolved During Integration
- Fixed import path in `Bracket.tsx` after API response type changed in Track 1

### Total Changes
- 5 files changed, +162 insertions, -46 deletions
```

## Important Rules

- **Verify no file overlap between tracks** before spawning agents. If overlap exists, merge those tasks into one track.
- **Each subagent must run tests** — a track is not complete until its tests pass.
- **Do NOT let subagents touch files outside their track** — include the allowed file list in the prompt.
- **Integration test is mandatory** — never skip it, even if all tracks passed individually.
- **If a subagent fails**, do not retry the entire track. Read its output, diagnose the specific failure, and fix it directly.
- **Keep the task list updated** — mark tasks in_progress when starting, completed when done.
