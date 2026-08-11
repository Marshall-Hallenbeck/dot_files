# GitHub Label Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shared GitHub skills discover, apply, and verify appropriate existing repository labels for pull requests and issues.

**Architecture:** Put a compact label contract directly in each GitHub workflow skill. Use GitHub CLI commands for label discovery, mutation, and verification. Add static regression checks to the existing dotfiles shell test suite, and use fresh-agent evaluations to verify that the instructions shape behavior.

**Tech Stack:** Markdown Agent Skills, GitHub CLI, Bash regression tests

## Global Constraints

- Use only labels returned by `gh label list --limit 200 --json name,description`.
- Never create, rename, guess, or remove repository labels.
- Select all clearly applicable work-type and affected-area labels.
- If no existing label clearly applies, continue and report that no match exists.
- Preserve unrelated changes in `.claude/global-learned-insights.md` and `.gitconfig`.
- Complete RED, GREEN, and fresh-agent verification for one skill before changing the next skill.

---

### Task 1: Pull Request Labels

**Files:**
- Modify: `.claude/skills/create-pr/SKILL.md:1-89`
- Test: `test/verify-hooks.sh`

**Interfaces:**
- Consumes: the current branch diff, linked issue data, and repository labels returned by GitHub CLI.
- Produces: a pull request created with repeated `--label "<label>"` arguments and verified with `gh pr view <PR-NUMBER> --json labels`.

- [ ] **Step 1: Add the failing static check**

Add these checks before the final results block in `test/verify-hooks.sh`:

```bash
create_pr_skill="$dotfiles_root/.claude/skills/create-pr/SKILL.md"
if grep -Fq 'gh label list --limit 200 --json name,description' "$create_pr_skill" &&
    grep -Fq -- '--label "<label>"' "$create_pr_skill" &&
    grep -Fq 'gh pr view <PR-NUMBER> --json labels' "$create_pr_skill"; then
    res=present
else
    res=missing
fi
check "create-pr discovers, applies, and verifies labels" "present" "$res"
```

- [ ] **Step 2: Run the check and verify RED**

Run: `bash test/verify-hooks.sh`

Expected: `FAIL: create-pr discovers, applies, and verifies labels` because the current skill creates the PR without label arguments or verification.

- [ ] **Step 3: Add the minimal pull request label contract**

Change the frontmatter description to a trigger-only description:

```yaml
description: Use when asked to create, open, publish, or submit a pull request from the current branch
```

After PR context collection, add:

### 4. Select Labels (REQUIRED)

List labels that exist in the repository:

```bash
gh label list --limit 200 --json name,description
```

Select all clearly applicable labels from the PR title, body, linked issue, and changed files.

- Prefer an existing work-type label such as `bug`, `enhancement`, `documentation`, `refactor`, `security`, or `tests` when it accurately describes the change.
- Add existing affected-area labels when the changed files clearly identify the area.
- Use exact names from the command output. Never create, rename, or guess a label.
- Keep labels already present on a linked issue only when they also describe the PR.
- If no existing label clearly applies, create the PR without a label and report that no match exists.

Create the PR with one argument for each selected label:

```bash
gh pr create --title "[title]" --body "[description]" --base main \
  --label "<label>" --label "<label>"
```

Then verify:

```bash
gh pr view <PR-NUMBER> --json labels
```

Add `Labels: [saved labels]` to the success report. Add label discovery and label mutation failures to error handling.

- [ ] **Step 4: Run the static check and verify GREEN**

Run: `bash test/verify-hooks.sh`

Expected: all checks pass, including `create-pr discovers, applies, and verifies labels`.

- [ ] **Step 5: Run a fresh-agent pull request evaluation**

Give a fresh agent the changed skill and a frontend bug-fix PR scenario with available `bug`, `frontend`, and `tests` labels.

Expected: the agent lists repository labels, creates the PR with all three exact labels, verifies saved labels, and reports them.

- [ ] **Step 6: Commit the pull request workflow**

```bash
git add .claude/skills/create-pr/SKILL.md test/verify-hooks.sh
git commit -m "feat(skills): label created pull requests"
```

### Task 2: GitHub Issue Creation

**Files:**
- Create: `.claude/skills/create-github-issue/SKILL.md`
- Modify: `test/verify-hooks.sh`

**Interfaces:**
- Consumes: an issue request, repository issue history, and repository labels returned by GitHub CLI.
- Produces: a structured issue created with repeated `--label "<label>"` arguments and verified with `gh issue view <ISSUE-NUMBER> --json labels`.

- [ ] **Step 1: Add the failing static check**

Add:

```bash
create_issue_skill="$dotfiles_root/.claude/skills/create-github-issue/SKILL.md"
if [ -f "$create_issue_skill" ] &&
    grep -Fq 'gh label list --limit 200 --json name,description' "$create_issue_skill" &&
    grep -Fq -- '--label "<label>"' "$create_issue_skill" &&
    grep -Fq 'gh issue view <ISSUE-NUMBER> --json labels' "$create_issue_skill"; then
    res=present
else
    res=missing
fi
check "create-github-issue discovers, applies, and verifies labels" "present" "$res"
```

- [ ] **Step 2: Run the check and verify RED**

Run: `bash test/verify-hooks.sh`

Expected: `FAIL: create-github-issue discovers, applies, and verifies labels` because the skill file does not exist.

- [ ] **Step 3: Create the issue workflow skill**

Create frontmatter with:

```yaml
---
name: create-github-issue
description: Use when asked to create, open, file, or draft a GitHub issue
argument-hint: "[title]"
disable-model-invocation: true
---
```

Add these required workflow sections in order:

1. Gather the problem, expected behavior, actual behavior, acceptance criteria, and relevant scope.
2. Search open and closed issues with `gh issue list --state all --search "<search terms>" --limit 20` and stop if a duplicate already covers the request.
3. List repository labels and apply the same exact-name label contract used by `create-pr`.
4. Build a body with `Summary`, `Current Behavior`, `Expected Behavior`, `Acceptance Criteria`, and `Technical Notes` sections.
5. Run `gh issue create` with one `--label "<label>"` argument for each selected label.
6. Verify with `gh issue view <ISSUE-NUMBER> --json labels` and report the issue URL and saved labels.

- [ ] **Step 4: Run the static check and verify GREEN**

Run: `bash test/verify-hooks.sh`

Expected: all checks pass, including `create-github-issue discovers, applies, and verifies labels`.

- [ ] **Step 5: Run a fresh-agent issue creation evaluation**

Give a fresh agent the new skill and a frontend signup bug scenario with available `bug`, `frontend`, and `tests` labels.

Expected: the agent checks duplicates, lists repository labels, creates the issue with all three exact labels, verifies the labels, and reports them.

- [ ] **Step 6: Commit the issue creation workflow**

```bash
git add .claude/skills/create-github-issue/SKILL.md test/verify-hooks.sh
git commit -m "feat(skills): add labeled GitHub issue creation"
```

### Task 3: Labels for Issues Being Completed

**Files:**
- Modify: `.claude/skills/complete-github-issue/SKILL.md:27-116`
- Modify: `test/verify-hooks.sh`

**Interfaces:**
- Consumes: issue title, body, current labels, acceptance criteria, referenced files, and existing repository labels.
- Produces: an issue whose clearly applicable existing labels are present before implementation starts.

- [ ] **Step 1: Add the failing static check**

Add:

```bash
complete_issue_skill="$dotfiles_root/.claude/skills/complete-github-issue/SKILL.md"
if grep -Fq 'gh label list --limit 200 --json name,description' "$complete_issue_skill" &&
    grep -Fq 'gh issue edit <NUMBER> --add-label "<label>"' "$complete_issue_skill" &&
    grep -Fq 'gh issue view <NUMBER> --json labels' "$complete_issue_skill"; then
    res=present
else
    res=missing
fi
check "complete-github-issue repairs and verifies issue labels" "present" "$res"
```

- [ ] **Step 2: Run the check and verify RED**

Run: `bash test/verify-hooks.sh`

Expected: `FAIL: complete-github-issue repairs and verifies issue labels` because the current skill only reads labels.

- [ ] **Step 3: Add issue label reconciliation before reconnaissance**

Change the initial read command to:

```bash
gh issue view <NUMBER> --json number,title,body,state,labels,assignees,url
```

Add a required label step directly after issue extraction:

```bash
gh label list --limit 200 --json name,description
gh issue edit <NUMBER> --add-label "<label>" --add-label "<label>"
gh issue view <NUMBER> --json labels
```

The step must require these rules:

- If the issue has no labels, add all clearly applicable existing work-type and affected-area labels before implementation.
- If labels exist, preserve them and add only clearly missing applicable labels.
- Never remove, create, rename, or guess a label.
- If no existing label clearly applies, report that result and continue.

Update the process diagram so label reconciliation occurs between issue reading and the implementation-work decision.

- [ ] **Step 4: Run the static check and verify GREEN**

Run: `bash test/verify-hooks.sh`

Expected: all checks pass, including `complete-github-issue repairs and verifies issue labels`.

- [ ] **Step 5: Run a fresh-agent issue completion evaluation**

Give a fresh agent the changed skill and an unlabeled backend security issue with available `security`, `backend`, and `tests` labels.

Expected: the agent lists labels, applies all three before reconnaissance, verifies them, and does not remove any existing label.

- [ ] **Step 6: Commit the issue completion workflow**

```bash
git add .claude/skills/complete-github-issue/SKILL.md test/verify-hooks.sh
git commit -m "feat(skills): repair labels before issue work"
```

### Task 4: Cross-Workflow Verification

**Files:**
- Verify: `.claude/skills/create-pr/SKILL.md`
- Verify: `.claude/skills/create-github-issue/SKILL.md`
- Verify: `.claude/skills/complete-github-issue/SKILL.md`
- Verify: `test/verify-hooks.sh`

**Interfaces:**
- Consumes: all three completed skill workflows.
- Produces: validated shared instructions with convergent label behavior.

- [ ] **Step 1: Run five fresh-context wording evaluations**

Run two PR scenarios, one issue creation scenario, and two issue completion scenarios. Use different work types and areas.

Expected for every sample: exact existing labels are discovered, all clear matches are applied, saved labels are verified, and no label is created or removed.

- [ ] **Step 2: Close instruction gaps**

If any agent omits discovery, application, or verification, add only the missing structural requirement to that skill and repeat the failed scenario with a fresh agent.

- [ ] **Step 3: Run the complete dotfiles checks**

```bash
bash test/verify-hooks.sh
python3 test/test_agent_sync_portability.py
git diff --check
```

Expected: every command exits with status 0.

Do not run `test/verify-environment.sh` directly on the host. It validates the Docker test user named `testuser` and runs only inside `test/Dockerfile` through `test/run-test.sh`.

- [ ] **Step 4: Review repository state**

```bash
git status --short
git log --oneline -5
```

Expected: only the pre-existing changes to `.claude/global-learned-insights.md` and `.gitconfig` remain uncommitted. All session files are committed in the task commits.
