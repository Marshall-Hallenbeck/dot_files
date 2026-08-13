---
name: claim-issue
description: Use when starting, checking, or finishing work on a GitHub issue in any repo where multiple agents may work in parallel — posts a session-info claim comment and manages the in-progress label so other agents skip claimed issues
argument-hint: "<check|claim|release> <issue-number> [release reason]"
---

# Claim a GitHub Issue

Coordinates parallel agents on one repository. A claim is an issue comment
carrying the agent's session ID, agent kind, host, branch, and worktree, plus
an `in-progress` label. Other agents check for the claim before starting work.

## Script

The bundled script does all the work:

```bash
~/.claude/skills/claim-issue/claim-issue.sh check <N>              # exit 3 = actively claimed
~/.claude/skills/claim-issue/claim-issue.sh claim <N>
~/.claude/skills/claim-issue/claim-issue.sh release <N> ["reason"]
```

**Project override:** if the repository has its own copy (e.g.
`scripts/agent-claim-issue.sh` in Turin's Tavern), use that instead — the
comment markers are identical, and the repo copy may add project-specific
runtime details and is what the project's other agents (Codex, CI) invoke.

## Lifecycle

1. **Before any work on an issue:** run `check <N>`. Exit 3 means another
   session holds an active claim — stop and report the claim instead of
   duplicating work, unless the user says otherwise.
2. **When starting:** run `claim <N>` from the branch you will implement on,
   so the comment carries the real branch. `claim` creates the `in-progress`
   label idempotently if the repo lacks it.
3. **When stopping — always release, whatever the outcome:**
   - PR merged: `release <N> "merged in PR #<PR>"`
   - blocked or handed off: `release <N> "<why work stopped>"`
   - abandoned: `release <N> "abandoned: <reason>"`

A claim with no later release is active. Stale claims (host gone, session
dead) may be overridden after reporting them to the user.

## Semantics

- `check` reads only the newest claim/release marker comment; a release after
  a claim frees the issue.
- Claims coordinate; they do not lock. Two simultaneous `claim` calls can
  race — the comment trail shows both sessions, and the newest comment wins
  `check`. Report a race if you see one.
- Never add or remove the `in-progress` label manually; let the script own it.
