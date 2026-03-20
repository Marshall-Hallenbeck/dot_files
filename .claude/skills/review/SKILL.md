---
name: review
description: "Review uncommitted code changes for bugs, security issues, and correctness. Finds AND fixes all issues."
argument-hint: "[path]"
context: fork
---

# Code Review (Uncommitted Changes)

Review all uncommitted changes (staged + unstaged) for bugs and correctness issues, then fix every finding. Does NOT post to GitHub — this is a local review.

## Usage

```
/review
/review backend/src/   (scope to specific paths)
```

## Behavior

### 1. Gather the Diff

```bash
git diff HEAD
```

If arguments were provided, scope the diff:
```bash
git diff HEAD -- <path>
```

If there are no uncommitted changes, say so and stop.

### 2. Read CLAUDE.md Files

Read the root `CLAUDE.md` and any `CLAUDE.md` files in directories touched by the diff. These contain project conventions that inform the review.

### 3. Review the Diff

For each changed file, read the full file for context (not just the diff hunks). Then review against these criteria, adapted from OpenAI Codex's review guidelines:

**Flag an issue ONLY if ALL of these are true:**
1. It meaningfully impacts accuracy, performance, security, or maintainability
4. It is visible in the changed files (if you see it, own it — regardless of when it was introduced)
6. It doesn't rely on unstated assumptions about the codebase or intent
7. If claiming it disrupts other code, you must identify the affected code specifically
8. It is clearly not just an intentional change

**Also check for:**
- Leftover `console.log`/`console.debug`/`console.warn` statements in production code (not in test files or intentional logging utilities)
- Dead exports — functions/types exported but not imported anywhere in the codebase

**Explicitly ignore:**
- Style/formatting (prettier and linters handle this)
- Missing tests (unless the CLAUDE.md requires them)
- Type errors, import issues (TypeScript/linters catch these)
- General "could be better" suggestions

### 4. Assign Priority

For each finding:
- **[P0]** — Drop everything. Blocking bug, security vulnerability, data loss. Universal — no assumptions needed.
- **[P1]** — Urgent. Should be fixed before committing. Clear bug that will be hit in practice.
- **[P2]** — Normal. Real issue but lower impact. Should still fix now.
- **[P3]** — Low. Nice to have. Fix eventually.

### 5. Self-Check Each Finding

Before reporting a finding, verify:
- Is this actually a bug, or am I speculating?
- Could this be intentional?
- Does the surrounding code context explain why it's written this way?
- Am I being pedantic?

If confidence is below 70%, drop the finding.

### 6. Fix ALL Findings

After identifying findings, fix every one of them — P0 through P3. Do not leave any finding unfixed.

For each finding:
1. Read the full file for context
2. Apply the fix using Edit
3. Briefly note what was changed

Run tests after all fixes to verify nothing broke:
```bash
uv run pytest tests/ -x -q
```

If tests fail due to a fix, adjust the fix until tests pass.

### 7. Output

After fixing, output the review summary:

```markdown
## Code Review

Reviewed N files with uncommitted changes.

### Findings (all fixed)

1. **[P1] Brief title** — `file:line`

   One paragraph explaining the problem. **Fixed:** brief description of the fix.

2. **[P2] Brief title** — `file:line`

   Explanation. **Fixed:** brief description of the fix.

### Verdict: PASS | NEEDS FIXES

- **PASS**: All findings fixed and tests passing.
- **NEEDS FIXES**: Has findings that could not be auto-fixed (explain why).
```

If there are zero findings:

```markdown
## Code Review

Reviewed N files with uncommitted changes.

No issues found. Checked for bugs, security issues, and CLAUDE.md compliance.

### Verdict: PASS
```

## Important Rules

- **No false positives over missed bugs.** When in doubt, don't flag it. One wrong finding wastes more time than one missed nit.
- **Brief comments.** One paragraph max per finding. No multi-paragraph essays.
- **Fix everything.** Every finding from P0 to P3 gets fixed, not just reported. A clean review means zero open findings.
- **Respect intent.** If a change looks intentional (renaming, restructuring, removing features), don't flag it as a bug.
- **Read context.** Always read the full file, not just the diff hunks. Many "bugs" in isolation are correct in context.
- **Run tests after fixes.** Verify fixes don't introduce regressions.
- **Matter-of-fact tone.** No flattery, no accusations. Just helpful observations.
