---
name: commit
description: "Commit session changes only, or all changes if no session edits."
argument-hint: "[message] [files...]"
disable-model-invocation: true
allowed-tools: Bash(git add:*), Bash(git restore --staged:*), Bash(git reset HEAD:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git commit:*), Bash(git apply:*), Bash(filterdiff:*)
---

# Commit

Commit changes from this session. If no files were edited in this session, review and commit all working-tree changes.

## Usage

```text
/commit                              # auto-group changes
/commit "<message>" [file1 file2 ...]  # commit specific files with message
```

## Required Behavior

### 1. Determine Scope

Check your conversation history for files modified via Edit or Write tools.

- **Session has edits**: only consider files you touched. Leave other dirty files alone.
- **No session edits** (e.g., user runs /commit at start of a fresh session): review and commit all working-tree changes.

```bash
git status --short
git diff --stat
git diff --cached --stat
```

### 2. Handle Mixed Files (Session Mode Only)

When committing session changes, for each file you edited, run `git diff <file>` and inspect the hunks:

- **All hunks are yours**: safe to `git add <file>`.
- **Some hunks are NOT yours** (changes you don't recognize from this session): stage only your hunks using a patch:
  ```bash
  git diff <file> | filterdiff --hunks=<your-hunk-numbers> | git apply --cached
  ```
  If `filterdiff` is unavailable, construct the patch manually:
  ```bash
  git diff <file> > /tmp/full.patch
  # Edit to remove hunks that aren't yours
  git apply --cached /tmp/trimmed.patch
  rm /tmp/full.patch
  ```

### 3. Group Into Logical Commits

Split changes into logical groups. Each group = one coherent change.

Grouping heuristics:
- Files that serve the same purpose (e.g., a component + its test + its styles) belong together.
- Config changes unrelated to code changes get their own commit.
- Unrelated bug fixes get separate commits from feature work.
- If ALL changes are related, a single commit is fine.

### 4. Commit Each Group

For each logical group:
1. Stage only that group's files:
   ```bash
   git add <files-in-group...>
   ```
2. Generate a commit message following Conventional Commits (`<type>(scope): description`).
   - If the user provided a message and there's only one group, use that message.
   - If the user provided a message and there are multiple groups, use it for the most relevant group and generate messages for the others.
3. **Add GitHub issue references** if the work relates to an issue:
   - Include `(#<number>)` at the end of the commit subject line.
   - If the commit fully resolves the issue, add `Closes #<number>` in the body.
4. Commit:
   ```bash
   git commit -m "<message>"
   ```

### 5. Report Results

After all commits, show a summary:
```
Committed:
  abc1234 fix(auth): tighten role checks
  def5678 chore(deps): bump eslint to v9
```
If in session mode, also list skipped files:
```
Skipped (not from this session):
  src/other/file.py
```

## Hard Rules

- Never use `git add -A` or `git add .`.
- For mixed files, stage only your hunks — never commit another agent's work.
- Never run tests, linters, type checks, or quality gates.
- If no changes exist, abort.
- If file args are provided, commit exactly those files (skip grouping).
