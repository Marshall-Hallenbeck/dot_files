---
name: ship
description: "Adversarial subagent review, fix, logical commits, PR to the default branch, CI watch and fix, merge. `until` stops the pipeline early."
argument-hint: "[until review|commit|pr] [context]"
disable-model-invocation: true
---

# Ship

Take the current branch from "code written" to "merged into the default branch" in one run. Every phase ends on a checkable criterion; the next phase starts only when the criterion holds.

## Usage

```text
/ship                          # review, fix, commit, PR, CI, merge
/ship until review             # stop after the review and validation phases; nothing committed
/ship until commit             # stop after the commits; nothing pushed
/ship until pr                 # stop with a green PR open; not merged
/ship <context>                # any other text is context about the work (issue number, scope)
```

## Project procedures win

When the repository ships its own procedure for a phase, that procedure governs the phase and this skill orchestrates it:

| Phase | Project file, when present | Use |
| --- | --- | --- |
| Validate | `.claude/skills/run-tests.md` | affected-test selection and escalation rules |
| Commit | `.claude/skills/safe-commit.md` | scoped staging and validation bar |
| Integrate, PR, merge readiness | `.claude/skills/create-pr.md`, `scripts/prepare-merge-ready-pr.sh` | base resolution, merge-ready verification, screenshots, labels |
| Issue claims | `scripts/agent-claim-issue.sh` or `~/.claude/skills/claim-issue/claim-issue.sh` | release the claim after the merge |
| Delivery state | `scripts/delivery-state.mts` | record task start and validation result |
| Worktree runtime | `scripts/worktree-env.sh` | run tests through the wrapper in a linked worktree; stop the runtime after the merge |

Read the project's `AGENTS.md` or `CLAUDE.md` before Phase 1. Its rules are review criteria.

## Phase 0: Scope

```bash
git fetch origin --prune
BRANCH=$(git branch --show-current)
BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null || gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git status --short
git log --oneline "origin/$BASE..HEAD"
git diff --stat "origin/$BASE...HEAD"
```

- On `$BASE` itself with changes to ship: create `<type>/<slug>` first, then continue on it.
- No commits ahead of the base and no uncommitted changes: report "nothing to ship" and stop.
- The diff under review is the branch diff (`origin/$BASE...HEAD`) plus the uncommitted diff (`git diff HEAD`).
- When `scripts/delivery-state.mts` exists: `node scripts/delivery-state.mts --task "<what ships>" --next "Adversarial review"`.

Done when `$BASE`, `$BRANCH`, and the list of changed files are known.

## Phase 1: Adversarial review

Spawn reviewer subagents in parallel with the Agent tool (type `general-purpose`). Reviewers read and report; they do not edit. Each gets the same brief plus one lens:

- **Brief**: the base ref, the changed-file list, the project instruction files to read, and the stance: assume the change is broken and find the way it breaks. Read each changed file in full, not only the hunks. Report each finding as `file:line`, a concrete failure scenario (input or state, then wrong output or crash), and severity P0 to P3. A finding without a concrete failure scenario is a question, not a finding.
- **Lenses**: (1) correctness and data flow, including edge cases and concurrency; (2) security and authorization, including injection, secrets, and privilege checks; (3) silenced failures and project-rule compliance: catches that swallow errors, fallbacks, defaults on failure, skipped or weakened tests, rules in `AGENTS.md`/`CLAUDE.md`; (4) test coverage: changed behavior without a test, bug fixes without a regression test.

Triage every finding:

- It stands when the failure scenario is reproducible or the cited code shows it. Fix it, at every severity.
- It falls when the scenario cannot happen in context. Record the one-line reason in the report.
- It needs a product or threat-model decision: surface the options to the user. Fix everything else first; stop at the end of the phase when the decision blocks the merge.

Fixing rules:

- Every behavioral fix gets a regression test that fails before the fix and passes after it.
- The fix for a silenced failure is to let it surface.
- A secret in the diff stops the pipeline. Report the file and line; nothing is committed.

Re-run the reviewers on the updated diff after the fixes. Done when a full reviewer pass returns zero standing findings.

## Phase 2: Validate

Run the smallest reliable set of checks for the integrated diff: lint, type check, affected unit and component tests, affected integration suites for changed boundaries, affected browser specs for changed workflows. A project test skill decides the scope when one exists; otherwise detect the runner from the repository (`package.json` scripts, `pyproject.toml`, `Cargo.toml`, `go.mod`). Escalate to the wider suite for a cascading change (shared auth, global layout or routing, a contract several workflows consume, build or dependency configuration).

Done when every selected check reports zero errors and zero warnings, from the root cause: an inline disable, a skipped test, or a changed assertion is not a pass.

With `until review`: write the Phase 2 result to delivery state when the script exists, report, and stop.

## Phase 3: Commit

Group the changes into logical commits: one coherent change per commit (a feature with its tests, a fix with its regression test, an unrelated config change on its own). Stage each group by file name.

```bash
git add <files-in-group...>
git commit -m "<type>(<scope>): <description>" -m "Refs #<issue>"
```

- Conventional Commits. `Closes #<N>` when the commit resolves the issue; `Refs #<N>` otherwise. Subject suffix `(#<PR>)` and body `Refs #<PR>` once a PR exists. Never invent a reference.
- Hooks run on every commit (`--no-verify` and `-n` are denied). A failing hook is fixed at its cause.
- Commit messages carry no AI attribution, session link, or co-author trailer.
- In a shared primary checkout, commit the files that belong to this task and list every file left behind.

Done when `git status --porcelain` lists only files outside this task.

With `until commit`: report and stop.

## Phase 4: Integrate the base and push

```bash
./scripts/prepare-merge-ready-pr.sh integrate --base "$BASE"   # when the helper exists
git merge "origin/$BASE"                                        # otherwise: a normal merge commit
```

Resolve conflicts semantically, keeping both the upstream change and the feature's intent, and show the resolution of every conflicted hunk in the report. When the merge brought new base behavior into files the diff touches, rerun the affected Phase 2 checks.

```bash
git push -u origin HEAD
```

Done when `origin/$BASE` is an ancestor of `HEAD` and the branch is pushed. A force push needs the user's explicit approval in this conversation.

## Phase 5: Pull request

An existing PR for the head branch is updated; a second PR is never opened. Otherwise create one against `$BASE`.

Body: summary, changes by area, exact test commands with pass counts, `Closes #<N>` for the issue this work resolves. When the repository has a PR template (`.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `PULL_REQUEST_TEMPLATE.md`), fill its sections. No AI attribution.

Labels:

```bash
gh label list --limit 200 --json name,description
gh pr create --base "$BASE" --title "<title>" --body-file "<body-file>" --label "<label>" --label "<label>"
gh pr view <PR-NUMBER> --json labels
```

Select every existing label that the title, body, linked issue, or changed paths clearly match (work type such as `bug`, `enhancement`, `refactor`, `security`, `tests`, `documentation`; area labels from the changed paths). Use exact names from the list; never create or rename a label. Verification must show every selected label. A result that omits a selected label fails the phase; fix and verify again.

A user-visible UI change needs before and after screenshots attached to the PR (`gh pr comment <PR> --attach <image>`) before CI is treated as the gate; a project `create-pr` skill defines the exact procedure.

Done when `gh pr view` shows a non-draft PR with the right base, head, labels, and body.

## Phase 6: CI

```bash
gh pr checks <PR> --watch
```

On a failing check:

```bash
gh run view <run-id> --log-failed
```

Diagnose from the log. Fix the cause in source (with a regression test when behavior changed), commit with the `(#<PR>)` suffix, push, and watch again. Rerun a failed job without a code change (`gh run rerun <run-id> --failed`) only when the log shows an infrastructure fault unrelated to the diff, such as a runner boot failure or a job timeout with no failing assertion; a second failure of the same job is treated as real. Do not propose CI tuning for a slow run.

Done when every required check is green on the current head commit.

With `until pr`: report the PR URL and stop.

## Phase 7: Merge

```bash
./scripts/prepare-merge-ready-pr.sh verify --base "$BASE"   # when the helper exists
gh pr view <PR> --json mergeable,mergeStateStatus,reviewDecision
gh pr merge <PR> --merge --delete-branch
```

Merge when GitHub reports `MERGEABLE` with `CLEAN`, or `BLOCKED` only because a human review is pending and the repository has no protection rule enforcing it. `CONFLICTING`, `DIRTY`, `BEHIND`, `UNKNOWN`, or a red check returns to Phase 4 or Phase 6.

When `gh pr merge` is refused because the diff touches `.github/workflows/` (the token lacks the `workflow` scope), merge locally with a merge commit and push the base branch normally:

```bash
git checkout "$BASE" && git pull --ff-only origin "$BASE"
git merge --no-ff "$BRANCH" -m "Merge pull request #<PR> from <owner>/<branch>" -m "Refs #<PR>"
git push origin "$BASE"
git push origin --delete "$BRANCH"
```

After the merge:

- `gh pr view <PR> --json state,mergeCommit` shows `MERGED`.
- Release the issue claim: `<claim script> release <N> "merged in PR #<PR>"`.
- Fast-forward the local base: `git checkout "$BASE" && git pull --ff-only origin "$BASE"`. A fast-forward failure means the base has local commits that bypassed a PR; report the divergence.
- In a linked worktree with a runtime: `./scripts/worktree-env.sh stop` (keeps the database for review).
- When the delivery-state script exists: `node scripts/delivery-state.mts --validation "<commands and pass counts>" --next "none; merged in PR #<PR>"`.

Done when the PR state is `MERGED` and the local base matches `origin/$BASE`.

## Report

```markdown
## Ship: <branch> -> <base>

| Phase | Result |
| --- | --- |
| Review | <N> findings fixed over <M> passes, <K> dropped (reasons below) |
| Validate | <commands with pass counts> |
| Commit | <sha> <subject>, one line per commit |
| Integrate | merge commit <sha> or "already current"; conflicts resolved: <files or none> |
| PR | <url>, labels <list> |
| CI | green at <sha>; fixes pushed: <N> |
| Merge | <merge sha>, PR MERGED, local <base> fast-forwarded |

### Dropped findings
- <finding>: <one-line reason>

### Needs your decision
- <finding>: <options>
```

Stopped early (`until`, a secret, a blocking decision, a merge refusal): the report names the phase, the exact blocker, and the single next action.
