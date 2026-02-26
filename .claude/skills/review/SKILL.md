---
name: review
description: "Review uncommitted code changes for bugs, security issues, and correctness. Like Codex's review but runs locally."
---

# Code Review (Uncommitted Changes)

Review all uncommitted changes (staged + unstaged) for bugs and correctness issues. Does NOT post to GitHub — this is a local review.

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
2. It is discrete and actionable (not a general codebase complaint)
3. Fixing it doesn't demand rigor absent from the rest of the codebase
4. It is visible in the changed files (whether newly introduced or pre-existing — if you see it, own it)
5. The author would likely fix it if aware
6. It doesn't rely on unstated assumptions about the codebase or intent
7. If claiming it disrupts other code, you must identify the affected code specifically
8. It is clearly not just an intentional change

**Explicitly ignore:**
- Style/formatting (prettier and linters handle this)
- Missing tests (unless the CLAUDE.md requires them)
- Type errors, import issues (TypeScript/linters catch these)
- Issues in files you haven't touched and that aren't related to the change
- General "could be better" suggestions

### 4. Assign Priority

For each finding:
- **[P0]** — Drop everything. Blocking bug, security vulnerability, data loss. Universal — no assumptions needed.
- **[P1]** — Urgent. Should be fixed before committing. Clear bug that will be hit in practice.
- **[P2]** — Normal. Real issue but lower impact. Fix eventually.
- **[P3]** — Low. Nice to have. Borderline nit with substance.

### 5. Self-Check Each Finding

Before reporting a finding, verify:
- Is this actually a bug, or am I speculating?
- Could this be intentional?
- Does the surrounding code context explain why it's written this way?
- Am I being pedantic?

If confidence is below 70%, drop the finding.

### 6. Output

```markdown
## Code Review

Reviewed N files with uncommitted changes.

### Findings

1. **[P1] Brief title** — `file:line`

   One paragraph explaining why this is a problem and the specific scenario where it manifests.

2. **[P2] Brief title** — `file:line`

   Explanation.

### Verdict: PASS | NEEDS FIXES

- **PASS**: No P0 or P1 findings. Safe to commit.
- **NEEDS FIXES**: Has P0 or P1 findings that should be addressed.
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
- **No code suggestions.** Describe the problem; don't write the fix. The author knows their code.
- **Respect intent.** If a change looks intentional (renaming, restructuring, removing features), don't flag it as a bug.
- **Read context.** Always read the full file, not just the diff hunks. Many "bugs" in isolation are correct in context.
- **Don't run tests or builds.** This is a read-only review. Assume CI handles tests, linting, and type checking.
- **Matter-of-fact tone.** No flattery, no accusations. Just helpful observations.
