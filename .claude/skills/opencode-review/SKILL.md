---
name: opencode_review
description: "Run OpenCode (MiniMax) and Claude code reviews iteratively until both find no issues. Use after making changes and before committing."
---

# OpenCode Review

Iterative dual-review pipeline using both OpenCode (MiniMax M2.5) and Claude. Runs reviews, fixes issues, and repeats until both reviewers are satisfied.

## Usage

```
/opencode_review
```

## Behavior

### 1. Run OpenCode Review

```bash
~/.opencode/bin/opencode run -m opencode/minimax-m2.5-free "/review" 2>&1
```

Capture the full output. Parse it for:
- Specific file and line references
- Issue severity (bugs, style, security, performance)
- Actionable suggestions vs informational comments

If `opencode` is not found at `~/.opencode/bin/opencode`, tell the user to install it (`curl -fsSL https://raw.githubusercontent.com/opencode-ai/opencode/refs/heads/main/install | bash`) or add it to PATH.

### 2. Run Claude Self-Review

Review the same uncommitted changes yourself:

```bash
git diff
git diff --cached
```

Check for:
- Logic errors and bugs in the changed code
- Security issues (injection, exposed secrets, missing validation)
- Consistency with existing code patterns (read surrounding code if needed)
- Missing error handling at system boundaries
- Test coverage gaps for new/changed functionality

### 3. Consolidate Issues

Merge findings from both reviews. Deduplicate — if OpenCode and Claude flag the same issue, count it once. Categorize:

- **Must fix**: Bugs, security issues, logic errors
- **Should fix**: Style violations, missing edge cases, unclear code
- **Informational**: Suggestions, minor nits, opinions

### 4. Fix Must-Fix and Should-Fix Issues

For each actionable issue:
1. Read the file and understand the context
2. Apply the fix
3. Keep fixes minimal — only address the flagged issue

Do NOT fix informational/nit issues unless trivially adjacent to a real fix.

### 5. Re-Run Both Reviews

After fixing, run both reviewers again:

```bash
~/.opencode/bin/opencode run -m opencode/minimax-m2.5-free "/review" 2>&1
```

And repeat your own Claude review of the current diff.

### 6. Iterate

If new issues are found:
- Fix them and re-run (back to step 5)
- **Max 3 iterations total** to prevent infinite loops
- If issues persist after 3 rounds, report remaining issues to the user

If both reviews come back clean: proceed to summary.

### 7. Summary

```markdown
## OpenCode Review Results

### Iteration 1
**OpenCode found:** 3 issues (1 bug, 2 style)
**Claude found:** 2 issues (1 logic error, 1 missing null check)
**Deduplicated total:** 4 issues
**Fixed:** 4/4

### Iteration 2
**OpenCode found:** 0 issues
**Claude found:** 0 issues

### Status: CLEAN

### Fixes Applied
1. `src/api/tournaments.ts:45` — Added null check for optional `season` field (bug)
2. `src/components/Bracket.tsx:112` — Fixed off-by-one in round calculation (logic error)
3. `src/utils/scoring.ts:30` — Consistent naming: `calcScore` → `calculateScore` (style)
4. `src/api/tournaments.ts:78` — Added input validation on `status` parameter (missing check)

### Remaining (informational only)
- OpenCode suggested extracting lines 45-60 into a helper — skipped (one-time operation)

Ready to commit.
```

## Important Rules

- **Max 3 iterations.** If still finding issues after 3 rounds, stop and report.
- **Fix source code, not symptoms.** If OpenCode flags a symptom, trace to the root cause.
- **Don't fix nits in a loop.** Informational items are reported but not acted on — they don't trigger another iteration.
- **Both reviewers must be clean** to declare success. One clean + one with issues = keep iterating.
- **Don't argue with OpenCode.** If it flags something legitimate, fix it. If it flags something wrong, note it in the summary as a false positive and move on.
- **Never suppress warnings** by adding ignore comments (e.g., `// eslint-disable`, `@ts-ignore`) unless the user explicitly asked.
