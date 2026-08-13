# Shared Learned Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude Code and Codex use one tracked global learned-insights file.

**Architecture:** Keep `.claude/global-learned-insights.md` as the canonical file in the dotfiles repository. Link both Linux runtime paths directly to it and verify the exact resolved targets.

**Tech Stack:** Bash, Python `unittest`, Git symlinks

## Global Constraints

- Preserve all entries in the live Claude file before replacing it.
- Preserve the existing uncommitted `.claude/skills/complete-github-issue/SKILL.md` change.
- Keep the Windows installer behavior unchanged.

---

### Task 1: Define the shared-link contract

**Files:**
- Modify: `test/test_agent_sync_portability.py:191-209`
- Modify: `test/verify-environment.sh:88-93`

**Interfaces:**
- Consumes: `link_file SOURCE DEST` from `install_environment.sh`
- Produces: tests that require both runtime links to resolve to `.claude/global-learned-insights.md`

- [ ] **Step 1: Write the failing static installer test**

Require these exact installer calls:

```python
self.assertIn(
    'link_file "$DOTFILES_DIR/.claude/global-learned-insights.md" ~/.claude/global-learned-insights.md',
    installer,
)
self.assertIn(
    'link_file "$DOTFILES_DIR/.claude/global-learned-insights.md" ~/.codex/global-learned-insights.md',
    installer,
)
```

- [ ] **Step 2: Add runtime link checks**

Add checks for both runtime files and compare their resolved targets with the
tracked file.

- [ ] **Step 3: Run the focused test and verify failure**

Run: `python3 -m unittest test.test_agent_sync_portability`

Expected: FAIL because the installer still calls `seed_runtime_file` and has
no Codex insights link.

### Task 2: Link the shared file and preserve data

**Files:**
- Modify: `.claude/global-learned-insights.md`
- Modify: `install_environment.sh:79-92,224-232,287-292`
- Modify: `.codex/AGENTS.md:131-133`
- Modify: `scripts/dotfiles:86-99`

**Interfaces:**
- Consumes: `link_file SOURCE DEST`
- Produces: two direct runtime links to one canonical file

- [ ] **Step 1: Merge the four live-only insights**

Copy the four added bullets from `~/.claude/global-learned-insights.md` into
the matching sections of `.claude/global-learned-insights.md`.

- [ ] **Step 2: Replace the seed operation with direct links**

Use:

```bash
link_file "$DOTFILES_DIR/.claude/global-learned-insights.md" ~/.codex/global-learned-insights.md
link_file "$DOTFILES_DIR/.claude/global-learned-insights.md" ~/.claude/global-learned-insights.md
```

Remove `seed_runtime_file` after its final call is removed.

- [ ] **Step 3: Fix the Codex path case**

Change `~/.Codex` and `<project-root>/.Codex` to `~/.codex` and
`<project-root>/.codex`.

- [ ] **Step 4: Make `dotfiles status` audit the Claude link**

Remove `.claude/global-learned-insights.md` from `repo_only`. Keep the Codex
alias covered by the installer and environment tests.

- [ ] **Step 5: Create the live links safely**

Back up the live Claude file. Create both direct links only after the tracked
file contains all live entries.

- [ ] **Step 6: Run validation**

Run:

```bash
python3 -m unittest test.test_agent_sync_portability
bash -n install_environment.sh test/verify-environment.sh scripts/dotfiles
shellcheck install_environment.sh test/verify-environment.sh scripts/dotfiles
dotfiles status
```

Expected: all tests pass, both links resolve to the same canonical file, and
`dotfiles status` does not report the Claude insights file as a regular file.

- [ ] **Step 7: Commit only task files**

```bash
git add .claude/global-learned-insights.md .codex/AGENTS.md install_environment.sh scripts/dotfiles test/test_agent_sync_portability.py test/verify-environment.sh docs/plans/2026-08-13-shared-learned-insights-design.md docs/superpowers/plans/2026-08-13-shared-learned-insights.md
git commit -m "fix(ai): share learned insights across Claude and Codex"
```
